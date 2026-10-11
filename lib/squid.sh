# shellcheck shell=bash

if [[ -n "${PROXSTACK_SQUID_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_SQUID_LOADED=1

detect_squid_auth_helper() {
  local candidate
  for candidate in \
    /usr/lib/squid/basic_ncsa_auth \
    /usr/lib64/squid/basic_ncsa_auth \
    /usr/libexec/squid/basic_ncsa_auth \
    /usr/lib/squid3/basic_ncsa_auth; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

render_squid_config() {
  local port="$1" helper="$2" passfile="$3"
  valid_port "$port" || return 1
  [[ "$helper" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
  [[ "$passfile" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
  cat <<EOF
http_port ${port}
visible_hostname proxystack
auth_param basic program ${helper} ${passfile}
auth_param basic children 5
auth_param basic realm ProxyStack
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT
http_access allow CONNECT SSL_ports authenticated
http_access allow authenticated
http_access deny all
cache deny all
via off
forwarded_for delete
EOF
}

squid_validate_file() {
  local file="$1"
  if [[ -n "${PROXSTACK_SQUID_VALIDATE:-}" ]]; then
    "$PROXSTACK_SQUID_VALIDATE" "$file"
    return
  fi
  if have_cmd squid; then
    squid -k parse -f "$file"
    return
  fi
  grep -q "^http_port " "$file" && grep -q "auth_param basic program" "$file"
}

squid_write_password() {
  local user="$1" pass="$2" file="$3" group="proxy"
  umask 077
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if have_cmd htpasswd; then
    if htpasswd -h 2>&1 | grep -q -- '-i'; then
      printf '%s\n' "$pass" | htpasswd -i -B -c "$file" "$user"
    else
      htpasswd -bB -c "$file" "$user" "$pass"
    fi
  else
    return 1
  fi
  if getent group proxy >/dev/null 2>&1; then
    group="proxy"
  elif getent group squid >/dev/null 2>&1; then
    group="squid"
  fi
  chown "root:${group}" "$file" 2>/dev/null || true
  chmod 640 "$file" 2>/dev/null || chmod 600 "$file"
}

squid_restart_live() {
  svc_enable_restart squid
}

squid_health_live() {
  wait_for_port "${SQUID_PORT:-51081}" || return 1
  squid_probe "${SQUID_USER}" "${SQUID_PASS_RUNTIME}" "${SQUID_PORT:-51081}"
}

squid_probe() {
  local user="$1" pass="$2" port="$3" target="${4:-${PROXSTACK_SQUID_TEST_URL:-https://api.ipify.org}}"
  local trace body code established=0 tracing=0
  case "$-" in
    *x*) tracing=1 && set +x ;;
  esac
  trace="$(mktemp)"
  body="$(mktemp)"
  code="$(
    curl -sS --max-time 25 \
      --proxy "http://127.0.0.1:${port}" \
      --proxy-user "${user}:${pass}" \
      --trace-ascii "$trace" \
      -o "$body" -w '%{http_code}' \
      "$target" 2>/dev/null || true
  )"
  if grep -q "Connection established" "$trace"; then
    established=1
  fi
  rm -f "$trace"
  [[ "$tracing" -eq 1 ]] && set -x
  if [[ "$established" -eq 1 || "$code" == "200" ]]; then
    if [[ "$established" -eq 1 ]]; then
      printf 'HTTP/1.1 200 Connection established\n'
    fi
    if [[ -s "$body" ]]; then
      head -c 120 "$body"
      printf '\n'
    fi
    rm -f "$body"
    return 0
  fi
  rm -f "$body"
  return 1
}

squid_collect_settings() {
  local user port pass
  user="$(flag_value --squid-user "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  port="$(flag_value --squid-port "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  pass="${PROXSTACK_SQUID_PASSWORD:-}"
  if [[ -z "$pass" ]]; then
    pass="$(flag_value --squid-password "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  fi
  [[ -n "$user" ]] || user="${SQUID_USER:-}"
  [[ -n "$port" ]] || port="${SQUID_PORT:-51081}"
  if [[ -z "$user" ]]; then
    ui_prompt user "$(msg ask_squid_user)" "httpproxy" || return 1
  fi
  if [[ -z "$port" ]]; then
    ui_prompt port "$(msg ask_squid_port)" "51081" || return 1
  fi
  valid_username "$user" || die "$(msg user_invalid)"
  valid_port "$port" || die "$(msg port_invalid)"
  if [[ -z "$pass" ]]; then
    ui_choose_password pass || die "$(msg pass_invalid)"
  fi
  valid_password "$pass" || die "$(msg pass_invalid)"
  SQUID_USER="$user"
  SQUID_PORT="$port"
  SQUID_PASS_RUNTIME="$pass"
  if [[ " ${PROXSTACK_POSITIONAL[*]} " == *" --save-secrets "* ]]; then
    PROXSTACK_SAVE_SECRETS=1
  fi
  if [[ "${PROXSTACK_SAVE_SECRETS:-0}" != "1" && "${PROXSTACK_NONINTERACTIVE:-0}" != "1" && -t 0 ]]; then
    if ui_confirm "$(msg ask_save_secrets)"; then
      PROXSTACK_SAVE_SECRETS=1
    fi
  fi
}

squid_install() {
  local helper rendered
  require_root
  require_supported_os
  proxystack_paths_init
  squid_collect_settings || return 1
  remember_new_package squid
  remember_new_package apache2-utils
  helper="$(detect_squid_auth_helper)" || die "basic_ncsa_auth was not found"
  squid_write_password "$SQUID_USER" "$SQUID_PASS_RUNTIME" "$PROXSTACK_SQUID_PASSWD"
  if [[ "${PROXSTACK_SAVE_SECRETS:-0}" == "1" ]]; then
    write_secrets_line SQUID_PASSWORD "$SQUID_PASS_RUNTIME"
  fi
  ui_show_secret_once "$(msg password_label_squid)" "$SQUID_PASS_RUNTIME"
  rendered="$(mktemp)"
  render_squid_config "$SQUID_PORT" "$helper" "$PROXSTACK_SQUID_PASSWD" >"$rendered"
  if ! apply_with_rollback "$PROXSTACK_SQUID_CONF" "$rendered" 644 squid_validate_file squid_restart_live squid_health_live; then
    rm -f "$rendered"
    unset SQUID_PASS_RUNTIME
    return 1
  fi
  rm -f "$rendered"
  config_set SQUID_ENABLED 1
  config_set SQUID_PORT "$SQUID_PORT"
  config_set SQUID_USER "$SQUID_USER"
  unset SQUID_PASS_RUNTIME
  log_info "Squid listening on port ${SQUID_PORT}"
}

cmd_restart_squid() {
  require_root
  svc_enable_restart squid
}

cmd_logs_squid() {
  if have_cmd journalctl; then
    journalctl -u squid -n 200 --no-pager || true
    return 0
  fi
  [[ -f /var/log/squid/access.log ]] && tail -n 100 /var/log/squid/access.log
}
