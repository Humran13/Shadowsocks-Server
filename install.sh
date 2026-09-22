#!/usr/bin/env bash
# Shadowsocks Server Manager - installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Humran13/Shadowsocks-Server/main/install.sh | sudo bash
set -Eeuo pipefail

REPO="Humran13/Shadowsocks-Server"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
SS_UPSTREAM_REPO="shadowsocks/shadowsocks-rust"

CONFIG_DIR="/etc/shadowsocks-server"
RUNTIME_DIR="/run/shadowsocks-server"
BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/shadowsocks-server"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="shadowsocks-server"

# ---------------------------------------------------------------------------
log_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
log_warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
log_err()   { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }
die()       { log_err "$*"; exit 1; }

trap 'log_err "Installer failed at line $LINENO. No changes were left half-applied where avoidable."' ERR

# ---------------------------------------------------------------------------
[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "This installer must be run as root (use: sudo bash install.sh, or via curl | sudo bash)"

command -v curl >/dev/null 2>&1 || die "curl is required"

# ---------------------------------------------------------------------------
log_info "Detecting operating system..."
[[ -f /etc/os-release ]] || die "Cannot detect OS: /etc/os-release not found"
# shellcheck disable=SC1091
source /etc/os-release
OS_ID="${ID:-unknown}"
OS_VERSION="${VERSION_ID:-unknown}"

if [[ "$OS_ID" != "ubuntu" ]]; then
  die "Unsupported OS: $OS_ID. This installer currently supports Ubuntu only (18.04, 20.04, 22.04, 24.04+)."
fi

case "$OS_VERSION" in
  18.04|20.04|22.04|24.04) : ;;
  *)
    awk_major="${OS_VERSION%%.*}"
    if [[ "$awk_major" =~ ^[0-9]+$ ]] && (( awk_major >= 24 )); then
      log_warn "Ubuntu $OS_VERSION is newer than explicitly tested versions (18.04/20.04/22.04/24.04) but will be attempted."
    else
      die "Unsupported Ubuntu version: $OS_VERSION"
    fi
    ;;
esac
log_ok "OS: Ubuntu $OS_VERSION"

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  # musl builds are statically linked and avoid glibc-version mismatches
  # across Ubuntu 18.04-24.04 (the gnu builds require a glibc newer than
  # what's available on older LTS releases).
  x86_64|amd64) ARCH="x86_64"; SS_ASSET_ARCH="x86_64-unknown-linux-musl" ;;
  aarch64|arm64) ARCH="aarch64"; SS_ASSET_ARCH="aarch64-unknown-linux-musl" ;;
  *) die "Unsupported architecture: $ARCH_RAW" ;;
esac
log_ok "Architecture: $ARCH"

if ! command -v systemctl >/dev/null 2>&1; then
  die "systemd is required but not found on this system"
fi
log_ok "systemd detected"

log_info "Checking Internet connectivity..."
if ! curl -fsS --max-time 5 https://api.github.com >/dev/null 2>&1; then
  die "No outbound Internet access to github.com. Check network/firewall and retry."
fi
log_ok "Internet connectivity confirmed"

# ---------------------------------------------------------------------------
log_info "Installing minimal dependencies (jq, openssl, curl, ufw, qrencode, ca-certificates, tar)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || die "apt-get update failed"
apt-get install -y -qq jq openssl curl ufw ca-certificates tar xz-utils qrencode >/dev/null \
  || die "Failed to install dependencies"
log_ok "Dependencies installed"

# ---------------------------------------------------------------------------
log_info "Resolving latest stable shadowsocks-rust release..."
LATEST_TAG="$(curl -fsS "https://api.github.com/repos/${SS_UPSTREAM_REPO}/releases/latest" | jq -r '.tag_name')"
[[ -n "$LATEST_TAG" && "$LATEST_TAG" != "null" ]] || die "Could not resolve latest shadowsocks-rust release"
log_ok "Latest shadowsocks-rust: $LATEST_TAG"

ASSET_NAME="shadowsocks-${LATEST_TAG}.${SS_ASSET_ARCH}.tar.xz"
ASSET_URL="https://github.com/${SS_UPSTREAM_REPO}/releases/download/${LATEST_TAG}/${ASSET_NAME}"
CHECKSUM_URL="${ASSET_URL}.sha256"

WORKDIR="$(mktemp -d /tmp/ss-install.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

log_info "Downloading $ASSET_NAME ..."
if ! curl -fsSL -o "$WORKDIR/$ASSET_NAME" "$ASSET_URL"; then
  die "Failed to download release asset: $ASSET_URL"
fi

if curl -fsSL -o "$WORKDIR/$ASSET_NAME.sha256" "$CHECKSUM_URL" 2>/dev/null; then
  log_info "Verifying checksum..."
  EXPECTED="$(awk '{print $1}' "$WORKDIR/$ASSET_NAME.sha256")"
  ACTUAL="$(sha256sum "$WORKDIR/$ASSET_NAME" | awk '{print $1}')"
  [[ "$EXPECTED" == "$ACTUAL" ]] || die "Checksum mismatch for $ASSET_NAME (expected $EXPECTED, got $ACTUAL)"
  log_ok "Checksum verified"
else
  log_warn "No published checksum file found upstream for this asset; proceeding without verification"
fi

log_info "Extracting..."
mkdir -p "$WORKDIR/extract"
tar -xJf "$WORKDIR/$ASSET_NAME" -C "$WORKDIR/extract"

for bin in ssserver sslocal ssmanager ssurl; do
  if [[ -f "$WORKDIR/extract/$bin" ]]; then
    install -m 755 "$WORKDIR/extract/$bin" "$BIN_DIR/$bin"
  fi
done
[[ -x "$BIN_DIR/ssserver" ]] || die "ssserver binary missing after extraction"
log_ok "shadowsocks-rust $LATEST_TAG installed to $BIN_DIR"

# ---------------------------------------------------------------------------
log_info "Setting up directories..."
install -d -m 700 "$CONFIG_DIR"
install -d -m 700 "$CONFIG_DIR/backups"
install -d -m 755 "$RUNTIME_DIR"
install -d -m 755 "$LIB_DIR"

if [[ ! -f "$CONFIG_DIR/users.json" ]]; then
  umask 077
  printf '{"users":[]}' > "$CONFIG_DIR/users.json"
  chmod 600 "$CONFIG_DIR/users.json"
fi
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
  umask 077
  printf '{"servers":[]}' > "$CONFIG_DIR/config.json"
  chmod 600 "$CONFIG_DIR/config.json"
fi
echo "$LATEST_TAG" > "$CONFIG_DIR/version"
log_ok "Configuration directory ready: $CONFIG_DIR"

# ---------------------------------------------------------------------------
log_info "Installing manager..."
for f in common.sh uri.sh firewall.sh; do
  curl -fsSL -o "$LIB_DIR/$f" "$RAW_BASE/lib/$f" || die "Failed to download lib/$f"
done
curl -fsSL -o "$BIN_DIR/shadowsocks" "$RAW_BASE/bin/shadowsocks" || die "Failed to download manager CLI"
chmod 755 "$BIN_DIR/shadowsocks"
chmod 644 "$LIB_DIR"/*.sh

if [[ ! -e "$BIN_DIR/ss-manager" ]]; then
  ln -s "$BIN_DIR/shadowsocks" "$BIN_DIR/ss-manager"
fi
log_ok "Manager installed: run 'sudo shadowsocks'"

# ---------------------------------------------------------------------------
log_info "Installing systemd service..."
curl -fsSL -o "$SYSTEMD_DIR/${SERVICE_NAME}.service" "$RAW_BASE/systemd/${SERVICE_NAME}.service" \
  || die "Failed to download systemd unit"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
systemctl restart "$SERVICE_NAME" || log_warn "Service did not start (expected if no users are configured yet)"
log_ok "systemd service installed and enabled"

# ---------------------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
  if ! ufw status | grep -qi "^Status: active"; then
    log_warn "UFW is installed but not active. Leaving it untouched to avoid locking you out of SSH."
    log_warn "If you enable UFW yourself, make sure to allow SSH first: sudo ufw allow OpenSSH"
  fi
fi

# ---------------------------------------------------------------------------
echo
log_ok "Installation complete."
echo
echo "  shadowsocks-rust version: $LATEST_TAG"
echo "  Config directory:         $CONFIG_DIR"
echo
echo "  Next step: run 'sudo shadowsocks' to open the manager and add your first user."
echo
