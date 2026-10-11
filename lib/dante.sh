# shellcheck shell=bash

if [[ -n "${PROXSTACK_DANTE_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_DANTE_LOADED=1

render_dante_config() {
  local iface="$1" port="$2"
  valid_iface "$iface" || return 1
  valid_port "$port" || return 1
  cat <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

internal: ${iface} port = ${port}
internal: 127.0.0.1 port = ${port}
external: ${iface}

socksmethod: username

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: connect disconnect error
    socksmethod: username
}
EOF
}

dante_validate_file() {
  local file="$1"
  if [[ -n "${PROXSTACK_DANTE_VALIDATE:-}" ]]; then
    "$PROXSTACK_DANTE_VALIDATE" "$file"
    return
  fi
  if have_cmd danted; then
    danted -V -f "$file"
    return
  fi
  grep -q '^internal:' "$file" && grep -q 'socksmethod: username' "$file" && grep -q 'udpassociate' "$file"
}

dante_unit() {
  if have_cmd systemctl && systemctl cat danted.service >/dev/null 2>&1; then
    printf 'danted'
    return
  fi
  printf 'danted'
}

dante_restart_live() {
  svc_enable_restart "$(dante_unit)"
}

dante_health_live() {
  local port="${DANTE_PORT:-51080}"
  wait_for_port "$port" || return 1
  dante_probe "${DANTE_USER}" "${DANTE_PASS_RUNTIME}" "$port"
}

dante_probe() {
  local user="$1" pass="$2" port="$3" target="${4:-${PROXSTACK_DANTE_TEST_URL:-https://api.ipify.org}}"
  local trace body code tracing=0
  case "$-" in
    *x*) tracing=1 && set +x ;;
  esac
  trace="$(mktemp)"
  body="$(mktemp)"
  code="$(
    curl -sS --max-time 25 \
      --socks5-hostname "127.0.0.1:${port}" \
      --proxy-user "${user}:${pass}" \
      --trace-ascii "$trace" \
      -o "$body" -w '%{http_code}' \
      "$target" 2>/dev/null || true
  )"
  rm -f "$trace"
  [[ "$tracing" -eq 1 ]] && set -x
  if [[ "$code" == "200" ]]; then
    head -c 120 "$body"
    printf '\n'
    rm -f "$body"
    return 0
  fi
  rm -f "$body"
  return 1
}

dante_collect_settings() {
  local user port pass save
  user="$(flag_value --dante-user "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  port="$(flag_value --dante-port "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  port="${port:-$(flag_value --port "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)}"
  pass="${PROXSTACK_DANTE_PASSWORD:-}"
  if [[ -z "$pass" ]]; then
    pass="$(flag_value --dante-password "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  fi
  [[ -n "$user" ]] || user="${DANTE_USER:-}"
  [[ -n "$port" ]] || port="${DANTE_PORT:-51080}"
  if [[ -z "$user" ]]; then
    ui_prompt user "$(msg ask_dante_user)" "socks" || return 1
  fi
  if [[ -z "$port" ]]; then
    ui_prompt port "$(msg ask_dante_port)" "51080" || return 1
  fi
  valid_username "$user" || die "$(msg user_invalid)"
  valid_port "$port" || die "$(msg port_invalid)"
  if [[ -z "$pass" ]]; then
    ui_choose_password pass || die "$(msg pass_invalid)"
  fi
  valid_password "$pass" || die "$(msg pass_invalid)"
  DANTE_USER="$user"
  DANTE_PORT="$port"
  DANTE_PASS_RUNTIME="$pass"
  save="$(flag_value --save-secrets "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  if [[ "$save" == "1" || "$save" == "yes" || " ${PROXSTACK_POSITIONAL[*]} " == *" --save-secrets "* ]]; then
    PROXSTACK_SAVE_SECRETS=1
  fi
  if [[ "${PROXSTACK_SAVE_SECRETS:-0}" != "1" && "${PROXSTACK_NONINTERACTIVE:-0}" != "1" && -t 0 ]]; then
    if ui_confirm "$(msg ask_save_secrets)"; then
      PROXSTACK_SAVE_SECRETS=1
    fi
  fi
}

dante_install() {
  local iface rendered
  require_root
  require_supported_os
  proxystack_paths_init
  dante_collect_settings || return 1
  iface="$(detect_default_interface)" || die "$(msg iface_missing)"
  valid_iface "$iface" || die "$(msg iface_missing)"
  # shellcheck disable=SC2034
  DANTE_IFACE="$iface"
  remember_new_package dante-server
  ensure_login_user "$DANTE_USER" "$DANTE_PASS_RUNTIME"
  if [[ "${PROXSTACK_SAVE_SECRETS:-0}" == "1" ]]; then
    write_secrets_line DANTE_PASSWORD "$DANTE_PASS_RUNTIME"
  fi
  ui_show_secret_once "$(msg password_label_dante)" "$DANTE_PASS_RUNTIME"
  rendered="$(mktemp)"
  render_dante_config "$iface" "$DANTE_PORT" >"$rendered"
  if ! apply_with_rollback "$PROXSTACK_DANTE_CONF" "$rendered" 644 dante_validate_file dante_restart_live dante_health_live; then
    rm -f "$rendered"
    unset DANTE_PASS_RUNTIME
    return 1
  fi
  rm -f "$rendered"
  config_set DANTE_ENABLED 1
  config_set DANTE_PORT "$DANTE_PORT"
  config_set DANTE_USER "$DANTE_USER"
  config_set DANTE_IFACE "$iface"
  unset DANTE_PASS_RUNTIME
  log_info "Dante listening on port ${DANTE_PORT} via ${iface}"
}

cmd_restart_dante() {
  require_root
  svc_enable_restart "$(dante_unit)"
}

cmd_logs_dante() {
  if have_cmd journalctl; then
    journalctl -u danted -n 200 --no-pager || true
    return 0
  fi
  log_warn "journalctl is not available"
}
