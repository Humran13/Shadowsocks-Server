#!/usr/bin/env bash
# shadowsocks-server: SIP002 URI and QR code generation
set -Eeuo pipefail

# Base64url-encode stdin without padding (per SIP002)
b64url() {
  base64 -w0 | tr '+/' '-_' | tr -d '='
}

# build_ss_uri method password host port [tag]
build_ss_uri() {
  local method="$1" password="$2" host="$3" port="$4" tag="${5:-}"
  local userinfo b64 uri
  userinfo="${method}:${password}"
  b64="$(printf '%s' "$userinfo" | b64url)"
  uri="ss://${b64}@${host}:${port}"
  if [[ -n "$tag" ]]; then
    local enc_tag
    enc_tag="$(python3 - "$tag" <<'EOF' 2>/dev/null || printf '%s' "$tag"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
EOF
)"
    uri="${uri}#${enc_tag}"
  fi
  printf '%s' "$uri"
}

# print_qr <uri>  -- prints a terminal QR code if qrencode is available, else no-op
print_qr() {
  local uri="$1"
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 -m 1 "$uri"
  else
    log_warn "qrencode not installed; QR code unavailable (URI shown above still works)"
  fi
}
