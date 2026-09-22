#!/usr/bin/env bash
# shadowsocks-server: firewall abstraction (UFW-aware, safe no-op otherwise)
# Only ever touches rules it created itself, tagged with a comment marker.
set -Eeuo pipefail

FW_COMMENT_PREFIX="shadowsocks-server-manager"

fw_backend() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "^Status: active"; then
    echo "ufw"
  else
    echo "none"
  fi
}

# fw_open_port <port>
fw_open_port() {
  local port="$1" backend
  backend="$(fw_backend)"
  case "$backend" in
    ufw)
      ufw allow "${port}/tcp" comment "$FW_COMMENT_PREFIX" >/dev/null
      ufw allow "${port}/udp" comment "$FW_COMMENT_PREFIX" >/dev/null
      log_ok "Firewall (UFW): opened TCP+UDP $port"
      ;;
    none)
      log_warn "No active supported firewall (UFW) detected; port $port left as-is by manager. Ensure it is reachable if you use another firewall."
      ;;
  esac
}

# fw_close_port <port>
fw_close_port() {
  local port="$1" backend
  backend="$(fw_backend)"
  case "$backend" in
    ufw)
      # Only remove rules we can find carrying our own comment tag for this port
      while ufw status numbered 2>/dev/null | grep -q "${port}/tcp.*${FW_COMMENT_PREFIX}"; do
        local num
        num="$(ufw status numbered | grep "${port}/tcp.*${FW_COMMENT_PREFIX}" | head -1 | grep -oP '^\[\s*\K[0-9]+')"
        [[ -n "$num" ]] || break
        yes | ufw delete "$num" >/dev/null 2>&1 || break
      done
      while ufw status numbered 2>/dev/null | grep -q "${port}/udp.*${FW_COMMENT_PREFIX}"; do
        local num
        num="$(ufw status numbered | grep "${port}/udp.*${FW_COMMENT_PREFIX}" | head -1 | grep -oP '^\[\s*\K[0-9]+')"
        [[ -n "$num" ]] || break
        yes | ufw delete "$num" >/dev/null 2>&1 || break
      done
      log_ok "Firewall (UFW): closed TCP+UDP $port"
      ;;
    none)
      : # nothing to remove
      ;;
  esac
}

fw_status_summary() {
  local backend
  backend="$(fw_backend)"
  case "$backend" in
    ufw) ufw status verbose 2>/dev/null | grep -E "$FW_COMMENT_PREFIX|^Status" ;;
    none) echo "No active supported firewall detected (SSH access is not managed by this tool)." ;;
  esac
}
