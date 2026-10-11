#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../helpers/test_helper.bash"
  proxystack_test_init
}

@test "version file matches the embedded version" {
  local file_version embedded
  file_version="$(tr -d '[:space:]' <"$PROXSTACK_ROOT/VERSION")"
  embedded="$(sed -n 's/^PROXSTACK_EMBEDDED_VERSION="\(.*\)"/\1/p' "$PROXSTACK_ROOT/proxystack.sh" | head -n1)"
  [ "$file_version" = "0.1.0" ]
  [ "$embedded" = "$file_version" ]
}

@test "parser accepts global flags in any position before the command" {
  proxystack_parse_args --json --non-interactive --force --quiet --verbose --lang ru status
  [ "$PROXSTACK_JSON" = "1" ]
  [ "$PROXSTACK_NONINTERACTIVE" = "1" ]
  [ "$PROXSTACK_FORCE" = "1" ]
  [ "$PROXSTACK_QUIET" = "1" ]
  [ "$PROXSTACK_VERBOSE" = "1" ]
  [ "$PROXSTACK_LANG_CLI" = "ru" ]
  [ "${PROXSTACK_POSITIONAL[0]}" = "status" ]
}

@test "parser keeps command flags for the subcommand" {
  proxystack_parse_args install dante --dante-user socks --dante-port 51080
  [ "${PROXSTACK_POSITIONAL[0]}" = "install" ]
  [ "$(flag_value --dante-user "${PROXSTACK_POSITIONAL[@]}")" = "socks" ]
  [ "$(flag_value --dante-port "${PROXSTACK_POSITIONAL[@]}")" = "51080" ]
}

@test "language selection accepts menu numbers and names" {
  [ "$(language_normalize 1)" = "ru" ]
  [ "$(language_normalize 2)" = "en" ]
  [ "$(language_normalize russian)" = "ru" ]
  [ "$(language_normalize EN)" = "en" ]
  run language_normalize french
  [ "$status" -ne 0 ]
}

@test "language is stored in config.env" {
  language_set ru
  [ "$(config_get PROXSTACK_LANG)" = "ru" ]
  [ "$PROXSTACK_LANG" = "ru" ]
}

@test "ipv4, cidr, and port validation" {
  valid_ipv4 203.0.113.10
  valid_ipv4 8.8.8.8
  run valid_ipv4 10.0.0.256
  [ "$status" -ne 0 ]
  run valid_ipv4 08.8.8.8
  [ "$status" -ne 0 ]
  is_public_ipv4 8.8.8.8
  run is_public_ipv4 10.1.2.3
  [ "$status" -ne 0 ]
  run is_public_ipv4 127.0.0.1
  [ "$status" -ne 0 ]
  run is_public_ipv4 192.168.1.1
  [ "$status" -ne 0 ]
  run is_public_ipv4 172.16.5.1
  [ "$status" -ne 0 ]
  valid_cidr 203.0.113.0/24
  valid_cidr 203.0.113.10
  run valid_cidr 203.0.113.0/33
  [ "$status" -ne 0 ]
  [ "$(normalize_cidr 203.0.113.10)" = "203.0.113.10/32" ]
  valid_port 1
  valid_port 51080
  valid_port 65535
  run valid_port 0
  [ "$status" -ne 0 ]
  run valid_port 65536
  [ "$status" -ne 0 ]
}

@test "interface selection uses the default route and never invents eth0" {
  local text=$'default via 192.0.2.1 dev ens3 proto dhcp src 192.0.2.10 metric 100\ndefault via 198.51.100.1 dev wlan0 proto dhcp metric 600\n'
  [ "$(select_default_interface "$text")" = "ens3" ]
  text=$'default via 192.0.2.1 dev wlan0 metric 50\ndefault via 198.51.100.1 dev ens3 metric 10\n'
  [ "$(select_default_interface "$text")" = "ens3" ]
  run select_default_interface ""
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "secret redaction hides passwords, tokens, and proxy authorization" {
  local raw redacted token
  token='123456789:AAFakeTokenForUnitTestsOnlyXXXX'
  raw="password=hunter2 token=${token} Proxy-Authorization: Basic abcdef --dante-password hunter2 http://user:hunter2@127.0.0.1:51081"
  redacted="$(redact_text "$raw")"
  [[ "$redacted" != *"hunter2"* ]]
  [[ "$redacted" != *"$token"* ]]
  [[ "$redacted" != *"Basic abcdef"* ]]
  [[ "$redacted" == *"Proxy-Authorization: REDACTED"* ]]
  [[ "$redacted" == *"password=***"* ]]
}

@test "log file does not keep a password that was passed through the logger" {
  log_info "password=hunter2"
  ! grep -q 'hunter2' "$PROXSTACK_LOG_DIR/proxystack.log"
  grep -q 'password=\*\*\*' "$PROXSTACK_LOG_DIR/proxystack.log"
}

@test "backup archive names are timestamped" {
  [ "$(backup_archive_name 20261011T120000Z)" = "proxystack-20261011T120000Z.tar.gz" ]
  run backup_archive_name "not-a-stamp"
  [ "$status" -ne 0 ]
}

@test "rollback restores the previous file when the health check fails" {
  local dest newf
  dest="$BATS_TEST_TMPDIR/service.conf"
  newf="$BATS_TEST_TMPDIR/new.conf"
  printf 'old\n' >"$dest"
  printf 'new\n' >"$newf"
  validate_ok() { return 0; }
  restart_count() {
    printf 'x\n' >>"$BATS_TEST_TMPDIR/restarts"
    return 0
  }
  health_fail() { return 1; }
  run apply_with_rollback "$dest" "$newf" 644 validate_ok restart_count health_fail
  [ "$status" -ne 0 ]
  [ "$(cat "$dest")" = "old" ]
  [ "$(grep -c x "$BATS_TEST_TMPDIR/restarts")" -eq 2 ]
  [[ "$output" == *"rollback succeeded"* ]]
}

@test "validation failure does not replace the current file" {
  local dest newf
  dest="$BATS_TEST_TMPDIR/keep.conf"
  newf="$BATS_TEST_TMPDIR/bad.conf"
  printf 'old\n' >"$dest"
  printf 'new\n' >"$newf"
  validate_bad() { return 1; }
  restart_no() { return 0; }
  health_ok() { return 0; }
  run apply_with_rollback "$dest" "$newf" 644 validate_bad restart_no health_ok
  [ "$status" -ne 0 ]
  [ "$(cat "$dest")" = "old" ]
}

@test "generated passwords are strong and log-safe" {
  local pass
  pass="$(generate_password)"
  [ "${#pass}" -eq 24 ]
  valid_password "$pass"
}

@test "version comparison" {
  version_is_newer 0.2.0 0.1.0
  run version_is_newer 0.1.0 0.1.0
  [ "$status" -ne 0 ]
  run version_is_newer 0.1.0 0.2.0
  [ "$status" -ne 0 ]
}

@test "forbidden example hosts are not embedded" {
  local hits
  hits="$(grep -RInE '104[.]252[.]127[.]243|techhelp[.]dddevspace[.]ru' "$PROXSTACK_ROOT" \
    --exclude-dir .git --exclude-dir dist || true)"
  [ -z "$hits" ]
}
