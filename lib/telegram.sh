# shellcheck shell=bash

if [[ -n "${PROXSTACK_TELEGRAM_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_TELEGRAM_LOADED=1

telegram_explain_error() {
  local text="$1" low
  low="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  if [[ "$low" == *404* ]]; then
    printf '%s\n' "$(msg wh_404)"
    return 0
  fi
  if [[ "$low" == *502* ]]; then
    printf '%s\n' "$(msg wh_502)"
    return 0
  fi
  if [[ "$low" == *timeout* || "$low" == *"timed out"* ]]; then
    printf '%s\n' "$(msg wh_timeout)"
    return 0
  fi
  return 1
}

telegram_format_info() {
  local json="$1" key value
  for key in url ip_address pending_update_count last_error_date last_error_message max_connections; do
    value="$(telegram_json_string "$json" "$key")"
    printf '%s: %s\n' "$key" "$value"
  done
}

telegram_json_string() {
  local json="$1" key="$2"
  printf '%s' "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n1
  if [[ "$key" == "pending_update_count" || "$key" == "last_error_date" || "$key" == "max_connections" ]]; then
    printf '%s' "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" | head -n1
  fi
}

telegram_read_token() {
  local token="${PROXSTACK_TELEGRAM_TOKEN:-}"
  if [[ -z "$token" ]]; then
    token="$(flag_value --bot-token "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  fi
  if [[ -z "$token" ]]; then
    token="$(read_secret_key TELEGRAM_BOT_TOKEN 2>/dev/null || true)"
  fi
  if [[ -z "$token" ]]; then
    if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
      log_error "$(msg tg_missing)"
      return 1
    fi
    local tracing=0
    case "$-" in
      *x*) tracing=1 && set +x ;;
    esac
    read -r -s -p "$(msg tg_token): " token
    printf '\n' >&2
    [[ "$tracing" -eq 1 ]] && set -x
  fi
  [[ -n "$token" ]] || return 1
  TELEGRAM_TOKEN_RUNTIME="$token"
  if [[ " ${PROXSTACK_POSITIONAL[*]} " == *" --save-token "* ]]; then
    write_secrets_line TELEGRAM_BOT_TOKEN "$token"
  elif [[ "${PROXSTACK_NONINTERACTIVE:-0}" != "1" && -t 0 ]]; then
    if ui_confirm "$(msg tg_save)"; then
      write_secrets_line TELEGRAM_BOT_TOKEN "$token"
    fi
  fi
}

telegram_proxy_args() {
  local via="${1:-direct}" user pass port proxy
  case "$via" in
    direct) return 0 ;;
    squid)
      user="${SQUID_USER:-$(config_get SQUID_USER 2>/dev/null || true)}"
      port="${SQUID_PORT:-51081}"
      pass="${PROXSTACK_SQUID_PASSWORD:-}"
      [[ -n "$pass" ]] || pass="$(read_secret_key SQUID_PASSWORD 2>/dev/null || true)"
      [[ -n "$user" && -n "$pass" ]] || return 1
      printf '%s\0%s' "--proxy" "http://127.0.0.1:${port}"
      return 0
      ;;
    http)
      proxy="$(flag_value --http-proxy "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
      [[ -n "$proxy" ]] || return 1
      printf '%s\0%s' "--proxy" "$proxy"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

telegram_api() {
  local method="$1"
  shift
  local via="${TELEGRAM_VIA:-direct}" url out err code tracing=0
  local -a extra=()
  telegram_read_token || return 1
  url="https://api.telegram.org/bot${TELEGRAM_TOKEN_RUNTIME}/${method}"
  out="$(mktemp)"
  err="$(mktemp)"
  case "$-" in
    *x*) tracing=1 && set +x ;;
  esac
  extra=()
  case "$via" in
    squid)
      local user pass port
      user="${SQUID_USER:-$(config_get SQUID_USER 2>/dev/null || true)}"
      port="${SQUID_PORT:-51081}"
      pass="${PROXSTACK_SQUID_PASSWORD:-}"
      [[ -n "$pass" ]] || pass="$(read_secret_key SQUID_PASSWORD 2>/dev/null || true)"
      extra=(--proxy "http://127.0.0.1:${port}" --proxy-user "${user}:${pass}")
      ;;
    http)
      local proxy
      proxy="$(flag_value --http-proxy "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
      extra=(--proxy "$proxy")
      ;;
  esac
  code="$(curl -sS --max-time 30 -o "$out" -w '%{http_code}' "${extra[@]}" "$url" "$@" 2>"$err" || true)"
  if [[ -s "$err" ]]; then
    log_debug "$(redact_text "$(cat "$err")")"
  fi
  rm -f "$err"
  [[ "$tracing" -eq 1 ]] && set -x
  cat "$out"
  rm -f "$out"
  unset TELEGRAM_TOKEN_RUNTIME
  [[ "$code" == "200" ]]
}

telegram_choose_via() {
  local choice
  choice="$(flag_value --via "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  if [[ -z "$choice" && "${PROXSTACK_NONINTERACTIVE:-0}" != "1" && -t 0 ]]; then
    ui_prompt choice "$(msg tg_via)" "1" || return 1
  fi
  case "${choice:-1}" in
    1 | direct) TELEGRAM_VIA="direct" ;;
    2 | squid) TELEGRAM_VIA="squid" ;;
    3 | http) TELEGRAM_VIA="http" ;;
    *) TELEGRAM_VIA="direct" ;;
  esac
}

cmd_webhook() {
  local action="${PROXSTACK_POSITIONAL[1]:-info}" body url
  telegram_choose_via || return 1
  case "$action" in
    set)
      url="$(flag_value --url "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
      if [[ -z "$url" ]]; then
        url="https://${CADDY_DOMAIN:-$(config_get CADDY_DOMAIN 2>/dev/null || true)}${CADDY_WEBHOOK_PATH:-/webhook/}"
      fi
      if [[ "$url" == "https:///webhook/" || "$url" == "https://" ]]; then
        ui_prompt url "$(msg tg_url)" "" || return 1
      fi
      body="$(telegram_api setWebhook --data-urlencode "url=${url}")" || return 1
      log_info "$(msg tg_set_ok)"
      printf '%s\n' "$(redact_text "$body")"
      ;;
    delete)
      body="$(telegram_api deleteWebhook)" || return 1
      log_info "$(msg tg_deleted)"
      printf '%s\n' "$(redact_text "$body")"
      ;;
    info)
      body="$(telegram_api getWebhookInfo)" || return 1
      telegram_format_info "$body"
      local errm
      errm="$(telegram_format_info "$body" | awk -F': ' '/last_error_message/ {print substr($0, index($0,$2))}')"
      if [[ -n "$errm" ]]; then
        telegram_explain_error "$errm" || true
      fi
      ;;
    test)
      url="$(flag_value --url "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
      [[ -n "$url" ]] || url="https://${CADDY_DOMAIN:-$(config_get CADDY_DOMAIN 2>/dev/null || true)}${CADDY_WEBHOOK_PATH:-/webhook/}"
      local code
      code="$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' -X POST \
        -H 'Content-Type: application/json' \
        --data '{"update_id":1,"message":{"message_id":1,"text":"proxystack-test"}}' \
        "$url" || true)"
      printf 'webhook_post_status: %s\n' "$code"
      ;;
    *)
      die "$(msg unknown_command)"
      ;;
  esac
}
