#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../helpers/test_helper.bash"
  proxystack_test_init
  export PROXSTACK_ETC PROXSTACK_VAR PROXSTACK_LOG_DIR PROXSTACK_CONFIG_FILE
  export PROXSTACK_ALLOW_NONROOT=1
  export PROXSTACK_SKIP_DETECT=1
}

@test "version and json version" {
  run cli version
  [ "$status" -eq 0 ]
  [[ "$output" == "proxystack 0.1.0" ]]
  run cli --json version
  [ "$status" -eq 0 ]
  [[ "$output" == *'"version":"0.1.0"'* ]]
}

@test "help works without a tty" {
  run cli --non-interactive help
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor"* ]]
  [[ "$output" == *"webhook"* ]]
  [[ "$output" == *"firewall"* ]]
}

@test "russian help is selected with --lang" {
  run cli --non-interactive --lang ru help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Диагностика"* ]]
}

@test "piped launch does not trip set -u" {
  run env PROXSTACK_LIB_DIR="$PROXSTACK_ROOT/lib" PROXSTACK_ALLOW_NONROOT=1 \
    bash -s -- version <"$PROXSTACK_ROOT/proxystack.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == "proxystack 0.1.0" ]]
}

@test "unknown command fails" {
  run cli --non-interactive nosuch
  [ "$status" -ne 0 ]
}
