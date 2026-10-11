#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../helpers/test_helper.bash"
  proxystack_test_init
}

@test "backup excludes secrets unless requested" {
  printf 'PROXSTACK_LANG=en\nDANTE_PORT=51080\n' >"$PROXSTACK_CONFIG_FILE"
  printf 'old-dante\n' >"$PROXSTACK_DANTE_CONF"
  printf 'DANTE_PASSWORD=secret-value\n' >"$PROXSTACK_SECRETS_FILE"
  chmod 600 "$PROXSTACK_SECRETS_FILE"
  local dest listing
  dest="$BATS_TEST_TMPDIR/plain.tar.gz"
  backup_create "$dest" 0
  listing="$(tar -tzf "$dest")"
  [[ "$listing" == *"etc/proxystack/config.env"* ]]
  [[ "$listing" == *"dante/danted.conf"* ]]
  [[ "$listing" == *"meta/metadata.json"* ]]
  [[ "$listing" != *"secrets.env"* ]]
  ! tar -xOzf "$dest" etc/proxystack/config.env | grep -q 'secret-value'
}

@test "secret backup is encrypted" {
  printf 'PROXSTACK_LANG=en\n' >"$PROXSTACK_CONFIG_FILE"
  printf 'TOKEN=secret-value\n' >"$PROXSTACK_SECRETS_FILE"
  local dest
  dest="$BATS_TEST_TMPDIR/secrets.tar.gz.enc"
  backup_create "$dest" 1 "unit-test-passphrase"
  run tar -tzf "$dest"
  [ "$status" -ne 0 ]
  local stage
  stage="$BATS_TEST_TMPDIR/restored"
  backup_extract "$dest" "$stage" "unit-test-passphrase"
  grep -q 'secret-value' "$stage/etc/proxystack/secrets.env"
}

@test "download order is release, raw GitHub, then jsDelivr" {
  local log="$BATS_TEST_TMPDIR/fetch.log"
  export PROXSTACK_FETCH_LOG="$log"
  http_hook() { return 1; }
  export PROXSTACK_HTTP_GET_HOOK=http_hook
  run fetch_with_fallback "$BATS_TEST_TMPDIR/out" \
    "$(release_asset_url v0.1.0 proxystack.sh)" \
    "$(raw_file_url v0.1.0 proxystack.sh)" \
    "$(jsdelivr_file_url v0.1.0 proxystack.sh)"
  [ "$status" -ne 0 ]
  [ "$(sed -n '1p' "$log")" = "https://github.com/driverm35/proxy-stack-cli/releases/download/v0.1.0/proxystack.sh" ]
  [ "$(sed -n '2p' "$log")" = "https://raw.githubusercontent.com/driverm35/proxy-stack-cli/v0.1.0/proxystack.sh" ]
  [ "$(sed -n '3p' "$log")" = "https://cdn.jsdelivr.net/gh/driverm35/proxy-stack-cli@v0.1.0/proxystack.sh" ]
}

@test "checksum verification accepts a matching SHA256SUMS entry" {
  printf 'hello\n' >"$BATS_TEST_TMPDIR/proxystack.sh"
  local sum
  sum="$(sha256sum "$BATS_TEST_TMPDIR/proxystack.sh" | awk '{print $1}')"
  printf '%s  proxystack.sh\n' "$sum" >"$BATS_TEST_TMPDIR/SHA256SUMS"
  verify_sha256 "$BATS_TEST_TMPDIR/proxystack.sh" "$BATS_TEST_TMPDIR/SHA256SUMS" proxystack.sh
  printf 'ffff  proxystack.sh\n' >"$BATS_TEST_TMPDIR/SHA256SUMS"
  run verify_sha256 "$BATS_TEST_TMPDIR/proxystack.sh" "$BATS_TEST_TMPDIR/SHA256SUMS" proxystack.sh
  [ "$status" -ne 0 ]
}

@test "install-script with a prefix does not touch system paths" {
  local prefix="$BATS_TEST_TMPDIR/opt"
  run cli install-script --prefix "$prefix" --non-interactive
  [ "$status" -eq 0 ]
  [ -x "$prefix/bin/proxystack" ]
  [ -f "$prefix/lib/proxystack/common.sh" ]
  [ -f "$prefix/lib/proxystack/locales/ru.sh" ]
  run "$prefix/bin/proxystack" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.1.0"* ]]
  run "$prefix/bin/proxystack" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"install-script"* ]]
  run "$prefix/bin/proxystack" --lang ru help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Установка"* ]]
}
