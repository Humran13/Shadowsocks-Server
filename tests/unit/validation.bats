#!/usr/bin/env bats
# Unit tests for pure validation/generation logic in lib/common.sh

setup() {
  export SS_CONFIG_DIR="$BATS_TEST_TMPDIR/etc"
  export SS_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export SS_USERS_FILE="$SS_CONFIG_DIR/users.json"
  export SS_CONFIG_FILE="$SS_CONFIG_DIR/config.json"
  mkdir -p "$SS_CONFIG_DIR"
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
}

@test "validate_username accepts normal names" {
  validate_username "alice"
  validate_username "bob-2"
  validate_username "user.name_1"
}

@test "validate_username rejects empty string" {
  run validate_username ""
  [ "$status" -ne 0 ]
}

@test "validate_username rejects shell metacharacters" {
  run validate_username "; rm -rf /"
  [ "$status" -ne 0 ]
  run validate_username '$(whoami)'
  [ "$status" -ne 0 ]
  run validate_username "user\`id\`"
  [ "$status" -ne 0 ]
}

@test "validate_username rejects names starting with dash or dot" {
  run validate_username "-rf"
  [ "$status" -ne 0 ]
  run validate_username ".hidden"
  [ "$status" -ne 0 ]
}

@test "validate_username rejects over-length names" {
  local long; long="$(printf 'a%.0s' {1..40})"
  run validate_username "$long"
  [ "$status" -ne 0 ]
}

@test "validate_port accepts valid unprivileged ports" {
  validate_port 8388
  validate_port 65535
  validate_port 1024
}

@test "validate_port rejects zero" {
  run validate_port 0
  [ "$status" -ne 0 ]
}

@test "validate_port rejects out-of-range" {
  run validate_port 65536
  [ "$status" -ne 0 ]
  run validate_port 999999
  [ "$status" -ne 0 ]
}

@test "validate_port rejects reserved low ports" {
  run validate_port 80
  [ "$status" -ne 0 ]
  run validate_port 22
  [ "$status" -ne 0 ]
}

@test "validate_port rejects non-numeric input" {
  run validate_port "abc"
  [ "$status" -ne 0 ]
  run validate_port "8388; rm -rf /"
  [ "$status" -ne 0 ]
}

@test "validate_method accepts allowlisted ciphers" {
  validate_method "chacha20-ietf-poly1305"
  validate_method "aes-256-gcm"
  validate_method "2022-blake3-aes-256-gcm"
}

@test "validate_method rejects deprecated/weak ciphers" {
  run validate_method "rc4-md5"
  [ "$status" -ne 0 ]
  run validate_method "table"
  [ "$status" -ne 0 ]
  run validate_method "plain"
  [ "$status" -ne 0 ]
}

@test "validate_date accepts valid calendar dates" {
  validate_date "2026-12-31"
  validate_date "2028-02-29"
}

@test "validate_date rejects malformed dates" {
  run validate_date "2026-13-01"
  [ "$status" -ne 0 ]
  run validate_date "2026-02-30"
  [ "$status" -ne 0 ]
  run validate_date "not-a-date"
  [ "$status" -ne 0 ]
  run validate_date "12/31/2026"
  [ "$status" -ne 0 ]
}

@test "generate_password produces non-empty output for each supported method" {
  for m in "${SUPPORTED_METHODS[@]}"; do
    pw="$(generate_password "$m")"
    [ -n "$pw" ]
  done
}

@test "key_length_for_method returns correct byte lengths" {
  [ "$(key_length_for_method "aes-128-gcm")" = "16" ]
  [ "$(key_length_for_method "aes-256-gcm")" = "32" ]
  [ "$(key_length_for_method "chacha20-ietf-poly1305")" = "32" ]
}

@test "atomic_write_json rejects invalid JSON and leaves target untouched" {
  echo '{"valid":true}' > "$SS_USERS_FILE"
  run atomic_write_json "$SS_USERS_FILE" '{not valid json'
  [ "$status" -ne 0 ]
  run cat "$SS_USERS_FILE"
  [[ "$output" == *'"valid":true'* ]]
}

@test "atomic_write_json accepts valid JSON and sets restrictive permissions" {
  atomic_write_json "$SS_USERS_FILE" '{"users":[]}'
  run cat "$SS_USERS_FILE"
  [[ "$output" == *'"users":[]'* ]]
  perms="$(stat -c %a "$SS_USERS_FILE")"
  [ "$perms" = "600" ]
}

@test "port_in_use detects existing port assignment" {
  atomic_write_json "$SS_USERS_FILE" '{"users":[{"username":"alice","port":8388}]}'
  port_in_use 8388
  run port_in_use 9999
  [ "$status" -ne 0 ]
}
