# shellcheck shell=bash

if [[ -n "${PROXSTACK_CADDY_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_CADDY_LOADED=1

parse_upstream_url() {
  local url="$1"
  valid_upstream_url "$url" || return 1
  [[ "$url" =~ ^(https?)://([^/:]+)(:([0-9]{1,5}))?(/.*)?$ ]] || return 1
  UPSTREAM_SCHEME="${BASH_REMATCH[1]}"
  UPSTREAM_HOST="${BASH_REMATCH[2]}"
  UPSTREAM_PORT="${BASH_REMATCH[4]:-}"
  UPSTREAM_PATH="${BASH_REMATCH[5]:-}"
  if [[ -n "$UPSTREAM_PATH" && "$UPSTREAM_PATH" != "/" ]]; then
    log_warn "Upstream path is ignored so the original request path is preserved"
  fi
  if [[ -z "$UPSTREAM_PORT" ]]; then
    if [[ "$UPSTREAM_SCHEME" == "https" ]]; then
      UPSTREAM_PORT=443
    else
      UPSTREAM_PORT=80
    fi
  fi
  valid_port "$UPSTREAM_PORT" || return 1
  UPSTREAM_DIAL="${UPSTREAM_SCHEME}://${UPSTREAM_HOST}:${UPSTREAM_PORT}"
}

render_caddyfile() {
  local domain="$1" upstream="$2" path="$3" log_file="${4:-/var/log/caddy/access.log}" email="${5:-}"
  local npath
  valid_domain "$domain" || return 1
  parse_upstream_url "$upstream" || return 1
  npath="$(normalize_webhook_path "$path")" || return 1
  [[ "$log_file" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
  if [[ -n "$email" ]]; then
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || return 1
    printf '{\n\temail %s\n}\n\n' "$email"
  fi
  cat <<EOF
${domain} {
	log {
		output file ${log_file}
	}
	@webhook path ${npath} ${npath}*
	handle @webhook {
		reverse_proxy ${UPSTREAM_DIAL} {
			header_up Host {upstream_hostport}
		}
	}
}
EOF
}

caddy_validate_file() {
  local file="$1"
  if [[ -n "${PROXSTACK_CADDY_VALIDATE:-}" ]]; then
    "$PROXSTACK_CADDY_VALIDATE" "$file"
    return
  fi
  if have_cmd caddy; then
    caddy validate --config "$file" --adapter caddyfile
    return
  fi
  grep -q 'reverse_proxy ' "$file" && grep -q 'header_up Host {upstream_hostport}' "$file" && grep -q '/webhook/' "$file"
}

caddy_install_package() {
  local keyring="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
  local list="/etc/apt/sources.list.d/caddy-stable.list"
  if have_cmd caddy; then
    return 0
  fi
  require_root
  apt_install debian-keyring debian-archive-keyring apt-transport-https curl gnupg ca-certificates
  rm -f "$keyring"
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o "$keyring"
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' >"$list"
  chmod 644 "$keyring" "$list"
  remember_new_package caddy
}

caddy_prepare_log_dir() {
  proxystack_paths_init
  mkdir -p "$PROXSTACK_CADDY_LOG_DIR"
  if id caddy >/dev/null 2>&1; then
    chown caddy:caddy "$PROXSTACK_CADDY_LOG_DIR"
  fi
  chmod 755 "$PROXSTACK_CADDY_LOG_DIR"
}

caddy_restart_live() {
  caddy_prepare_log_dir
  svc_enable_restart caddy
}

caddy_health_live() {
  svc_active caddy || return 1
  wait_for_port 80 || return 1
  wait_for_port 443 || return 1
  return 0
}

caddy_collect_settings() {
  local domain upstream path email
  domain="$(flag_value --domain "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  upstream="$(flag_value --upstream "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  path="$(flag_value --webhook-path "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  email="$(flag_value --acme-email "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  [[ -n "$domain" ]] || domain="${CADDY_DOMAIN:-}"
  [[ -n "$upstream" ]] || upstream="${CADDY_UPSTREAM:-}"
  [[ -n "$path" ]] || path="${CADDY_WEBHOOK_PATH:-/webhook/}"
  if [[ -z "$domain" ]]; then
    ui_prompt domain "$(msg ask_domain)" "" || return 1
  fi
  if [[ -z "$upstream" ]]; then
    ui_prompt upstream "$(msg ask_upstream)" "" || return 1
  fi
  if [[ -z "$path" ]]; then
    ui_prompt path "$(msg ask_path)" "/webhook/" || return 1
  fi
  if [[ -z "$email" && "${PROXSTACK_NONINTERACTIVE:-0}" != "1" && -t 0 ]]; then
    ui_prompt email "$(msg ask_email)" "" || true
  fi
  valid_domain "$domain" || die "$(msg domain_invalid)"
  valid_upstream_url "$upstream" || die "$(msg upstream_invalid)"
  path="$(normalize_webhook_path "$path")" || die "$(msg port_invalid)"
  CADDY_DOMAIN="$domain"
  CADDY_UPSTREAM="$upstream"
  CADDY_WEBHOOK_PATH="$path"
  CADDY_ACME_EMAIL="$email"
}

caddy_install() {
  local rendered
  require_root
  require_supported_os
  proxystack_paths_init
  caddy_collect_settings || return 1
  caddy_install_package
  caddy_prepare_log_dir
  rendered="$(mktemp)"
  render_caddyfile "$CADDY_DOMAIN" "$CADDY_UPSTREAM" "$CADDY_WEBHOOK_PATH" \
    "$PROXSTACK_CADDY_LOG_DIR/access.log" "${CADDY_ACME_EMAIL:-}" >"$rendered"
  if ! apply_with_rollback "$PROXSTACK_CADDYFILE" "$rendered" 644 caddy_validate_file caddy_restart_live caddy_health_live; then
    rm -f "$rendered"
    return 1
  fi
  rm -f "$rendered"
  config_set CADDY_ENABLED 1
  config_set CADDY_DOMAIN "$CADDY_DOMAIN"
  config_set CADDY_UPSTREAM "$CADDY_UPSTREAM"
  config_set CADDY_WEBHOOK_PATH "$CADDY_WEBHOOK_PATH"
  if [[ -n "${CADDY_ACME_EMAIL:-}" ]]; then
    config_set CADDY_ACME_EMAIL "$CADDY_ACME_EMAIL"
  fi
  log_info "Caddy is serving ${CADDY_DOMAIN}${CADDY_WEBHOOK_PATH}"
}

caddy_post_webhook() {
  local domain="$1" path="$2" code
  code="$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' \
    --data '{"update_id":1,"message":{"message_id":1,"text":"proxystack-test"}}' \
    "https://${domain}${path}" || true)"
  printf '%s' "$code"
}

cmd_restart_caddy() {
  require_root
  caddy_prepare_log_dir
  if have_cmd caddy; then
    caddy validate --config "$PROXSTACK_CADDYFILE" --adapter caddyfile
    svc reload caddy || svc_enable_restart caddy
    return
  fi
  svc_enable_restart caddy
}

cmd_logs_caddy() {
  if have_cmd journalctl; then
    journalctl -u caddy -n 200 --no-pager || true
  fi
  if [[ -f "${PROXSTACK_CADDY_LOG_DIR:-/var/log/caddy}/access.log" ]]; then
    tail -n 50 "${PROXSTACK_CADDY_LOG_DIR:-/var/log/caddy}/access.log"
  fi
}
