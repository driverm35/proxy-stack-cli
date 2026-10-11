# shellcheck shell=bash

proxystack_test_init() {
  local here
  here="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROXSTACK_ROOT="$here"
  export PROXSTACK_LIB_DIR="$here/lib"
  export PROXSTACK_LOCALE_DIR="$here/locales"
  export PROXSTACK_ETC="$BATS_TEST_TMPDIR/etc/proxystack"
  export PROXSTACK_VAR="$BATS_TEST_TMPDIR/var/lib/proxystack"
  export PROXSTACK_LOG_DIR="$BATS_TEST_TMPDIR/log/proxystack"
  export PROXSTACK_CONFIG_FILE="$PROXSTACK_ETC/config.env"
  export PROXSTACK_SECRETS_FILE="$PROXSTACK_ETC/secrets.env"
  export PROXSTACK_DANTE_CONF="$BATS_TEST_TMPDIR/danted.conf"
  export PROXSTACK_SQUID_CONF="$BATS_TEST_TMPDIR/squid.conf"
  export PROXSTACK_SQUID_PASSWD="$BATS_TEST_TMPDIR/passwords"
  export PROXSTACK_CADDYFILE="$BATS_TEST_TMPDIR/Caddyfile"
  export PROXSTACK_CADDY_LOG_DIR="$BATS_TEST_TMPDIR/caddy-log"
  export PROXSTACK_NONINTERACTIVE=1
  export PROXSTACK_FORCE=0
  export PROXSTACK_JSON=0
  export PROXSTACK_VERBOSE=0
  export PROXSTACK_QUIET=1
  export PROXSTACK_LANG=en
  export PROXSTACK_ALLOW_NONROOT=1
  export PROXSTACK_SKIP_DETECT=1
  unset PROXSTACK_PREFIX
  mkdir -p "$PROXSTACK_ETC" "$PROXSTACK_VAR" "$PROXSTACK_LOG_DIR"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/common.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/i18n.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/ui.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/system.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/dante.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/squid.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/caddy.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/telegram.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/firewall.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/doctor.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/backup.sh"
  # shellcheck disable=SC1091
  source "$PROXSTACK_LIB_DIR/update.sh"
  i18n_init "$PROXSTACK_LOCALE_DIR"
  ui_init
}

cli() {
  # shellcheck disable=SC2068
  bash "$PROXSTACK_ROOT/proxystack.sh" "$@"
}
