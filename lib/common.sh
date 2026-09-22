#!/usr/bin/env bash
# shadowsocks-server: shared shell library (config, validation, atomic writes)
# Sourced by manager CLI, installer, and update scripts. Not meant to be executed directly.

set -Eeuo pipefail

SS_CONFIG_DIR="${SS_CONFIG_DIR:-/etc/shadowsocks-server}"
SS_RUNTIME_DIR="${SS_RUNTIME_DIR:-/run/shadowsocks-server}"
SS_BIN_DIR="${SS_BIN_DIR:-/usr/local/bin}"
SS_USERS_FILE="$SS_CONFIG_DIR/users.json"
SS_CONFIG_FILE="$SS_CONFIG_DIR/config.json"
SS_MANAGER_CONF="$SS_CONFIG_DIR/manager.conf"
SS_VERSION_FILE="$SS_CONFIG_DIR/version"
SS_BACKUP_DIR="$SS_CONFIG_DIR/backups"
SS_SOCKET_PATH="$SS_RUNTIME_DIR/manager.sock"
SS_SERVICE_NAME="shadowsocks-server"
SS_PROJECT_TAG="shadowsocks-server-manager"

SUPPORTED_METHODS=(
  "chacha20-ietf-poly1305"
  "aes-128-gcm"
  "aes-256-gcm"
  "2022-blake3-aes-128-gcm"
  "2022-blake3-aes-256-gcm"
  "2022-blake3-chacha20-poly1305"
)
DEFAULT_METHOD="chacha20-ietf-poly1305"

# ---- colors (degrade gracefully if not a tty / no color support) ----
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET="$(tput sgr0)"; C_BOLD="$(tput bold)"
  C_RED="$(tput setaf 1)"; C_GREEN="$(tput setaf 2)"; C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"; C_CYAN="$(tput setaf 6)"
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

log_info()  { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
log_ok()    { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()  { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err()   { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()       { log_err "$*"; exit 1; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "This command must be run as root (try: sudo $0 $*)"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# ---- validation ----

# Username: 1-32 chars, alnum/dash/underscore/dot, must not start with dash or dot
validate_username() {
  local u="$1"
  [[ ${#u} -ge 1 && ${#u} -le 32 ]] || { log_err "Username must be 1-32 characters"; return 1; }
  [[ "$u" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { log_err "Username may only contain letters, numbers, dot, dash, underscore, and must start with a letter or number"; return 1; }
  return 0
}

validate_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || { log_err "Port must be a positive integer"; return 1; }
  (( p >= 1 && p <= 65535 )) || { log_err "Port must be between 1 and 65535"; return 1; }
  (( p >= 1 && p <= 1023 )) && { log_err "Ports below 1024 are reserved; choose 1024-65535"; return 1; }
  return 0
}

validate_method() {
  local m="$1" ok=0
  for allowed in "${SUPPORTED_METHODS[@]}"; do
    [[ "$m" == "$allowed" ]] && ok=1 && break
  done
  [[ $ok -eq 1 ]] || { log_err "Unsupported encryption method: $m"; return 1; }
  return 0
}

# Strict YYYY-MM-DD validation using date itself (rejects 2026-02-30 etc.)
validate_date() {
  local d="$1"
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { log_err "Date must be in YYYY-MM-DD format"; return 1; }
  date -d "$d" >/dev/null 2>&1 || { log_err "Date is not a valid calendar date: $d"; return 1; }
  return 0
}

# ---- secret generation ----
# Key length required by cipher, in raw bytes (before base64), per shadowsocks spec.
key_length_for_method() {
  case "$1" in
    chacha20-ietf-poly1305|aes-256-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) echo 32 ;;
    aes-128-gcm|2022-blake3-aes-128-gcm) echo 16 ;;
    *) die "Unknown method for key length: $1" ;;
  esac
}

generate_password() {
  local method="$1"
  local len
  len="$(key_length_for_method "$method")"
  case "$method" in
    2022-blake3-*)
      # SS2022 requires base64-standard-encoded key of exact byte length
      openssl rand -base64 "$len" | head -c "$(( (len + 2) / 3 * 4 ))"
      ;;
    *)
      openssl rand -base64 24
      ;;
  esac
}

# ---- JSON helpers (require jq) ----
json_validate() {
  jq empty "$1" >/dev/null 2>&1
}

# Atomic write: write to temp file in same dir, validate, then rename over target
atomic_write_json() {
  local target="$1" content="$2"
  local dir tmp
  dir="$(dirname "$target")"
  tmp="$(mktemp "$dir/.tmp.XXXXXX")"
  chmod 600 "$tmp"
  printf '%s' "$content" > "$tmp"
  if ! jq empty "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    die "Refusing to write invalid JSON to $target"
  fi
  mv -f "$tmp" "$target"
  chmod 600 "$target"
}

ensure_dirs() {
  install -d -m 700 "$SS_CONFIG_DIR"
  install -d -m 700 "$SS_BACKUP_DIR"
  install -d -m 755 "$SS_RUNTIME_DIR"
}

init_users_file() {
  [[ -f "$SS_USERS_FILE" ]] || atomic_write_json "$SS_USERS_FILE" '{"users":[]}'
}

port_in_use() {
  local port="$1"
  jq -e --argjson p "$port" '.users[] | select(.port == $p)' "$SS_USERS_FILE" >/dev/null 2>&1
}

# Detect public IPv4 with multiple fallbacks; empty string if all fail.
detect_public_ipv4() {
  local ip=""
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)"
  if [[ -z "$ip" ]]; then
    for svc in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
      ip="$(curl -fsS4 --max-time 3 "$svc" 2>/dev/null | tr -d '[:space:]' || true)"
      [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
      ip=""
    done
  fi
  echo "$ip"
}
