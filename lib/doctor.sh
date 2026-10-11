# shellcheck shell=bash

if [[ -n "${PROXSTACK_DOCTOR_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_DOCTOR_LOADED=1

doctor_result() {
  local status="$1" name="$2" detail="$3" rec="${4:-}" label color
  case "$status" in
    OK)
      DOCTOR_PASS=$((DOCTOR_PASS + 1))
      label="[ OK ]"
      color="${UI_GREEN:-}"
      ;;
    WARN)
      DOCTOR_WARN=$((DOCTOR_WARN + 1))
      label="[ WARN ]"
      color="${UI_YELLOW:-}"
      ;;
    FAIL)
      DOCTOR_FAIL=$((DOCTOR_FAIL + 1))
      label="[ FAIL ]"
      color="${UI_RED:-}"
      ;;
    *) return 1 ;;
  esac
  if [[ "${PROXSTACK_JSON:-0}" != "1" ]]; then
    printf '%s%s%s %s — %s\n' "$color" "$label" "${UI_RESET:-}" "$name" "$detail"
  else
    DOCTOR_JSON_ITEMS+=("{\"status\":\"${status}\",\"name\":\"$(json_escape "$name")\",\"detail\":\"$(json_escape "$detail")\"}")
  fi
  if [[ -n "$rec" ]]; then
    DOCTOR_RECS+=("$rec")
  fi
}

doctor_upstream_diagnosis() {
  local dns="$1" route="$2" tcp="$3" http_status="$4" iface="$5" ip="$6" port="$7"
  if [[ "$http_status" == "502" && "$dns" == "ok" && "$route" == "ok" && "$tcp" == "timeout" ]]; then
    msg_block diag_not_caddy
    printf 'sudo tcpdump -ni %s host %s and tcp port %s\n' "${iface:-any}" "$ip" "$port"
    return 0
  fi
  return 1
}

doctor_finish() {
  local rec joined="" item
  if [[ "${PROXSTACK_JSON:-0}" == "1" ]]; then
    for item in "${DOCTOR_JSON_ITEMS[@]}"; do
      if [[ -n "$joined" ]]; then
        joined="${joined},${item}"
      else
        joined="$item"
      fi
    done
    printf '{"passed":%s,"warnings":%s,"failed":%s,"checks":[%s]}\n' \
      "$DOCTOR_PASS" "$DOCTOR_WARN" "$DOCTOR_FAIL" "$joined"
  else
    printf '\nSummary\n%s: %s\n%s: %s\n%s: %s\n' \
      "$(msg doc_passed)" "$DOCTOR_PASS" \
      "$(msg doc_warnings)" "$DOCTOR_WARN" \
      "$(msg doc_failed)" "$DOCTOR_FAIL"
    if [[ ${#DOCTOR_RECS[@]} -gt 0 ]]; then
      printf '%s:\n' "$(msg doc_recs)"
      for rec in "${DOCTOR_RECS[@]}"; do
        printf -- '- %s\n' "$rec"
      done
    fi
  fi
  [[ "$DOCTOR_FAIL" -eq 0 ]]
}

doctor_check_os() {
  local id ver pretty
  id="$(os_id 2>/dev/null || true)"
  ver="$(os_version 2>/dev/null || true)"
  pretty="$(os_pretty 2>/dev/null || true)"
  if [[ "$id" == "ubuntu" || "$id" == "debian" ]]; then
    doctor_result OK "os" "${pretty:-$id $ver}"
  elif [[ -z "$id" ]]; then
    doctor_result WARN "os" "os-release is missing" "Install on Ubuntu or Debian"
  else
    doctor_result WARN "os" "${pretty:-$id} is outside the tested Ubuntu/Debian set" "Use Ubuntu 22.04+ or Debian 12+"
  fi
}

doctor_check_root() {
  if is_root; then
    doctor_result OK "root" "running as root"
  elif have_cmd sudo; then
    doctor_result WARN "root" "not root; sudo is available" "Re-run with sudo proxystack doctor"
  else
    doctor_result FAIL "root" "not root and sudo is missing" "Run as root"
  fi
}

doctor_check_arch() {
  doctor_result OK "arch" "$(arch_name)"
}

doctor_check_resources() {
  local mem disk
  mem="$(mem_total_mb 2>/dev/null || true)"
  disk="$(disk_free_mb / 2>/dev/null || true)"
  if [[ -z "$mem" || -z "$disk" ]]; then
    doctor_result WARN "resources" "RAM or disk information is unavailable"
    return
  fi
  if ((mem < 256 || disk < 500)); then
    doctor_result WARN "resources" "RAM ${mem} MB, free disk ${disk} MB" "Free disk and at least 512 MB RAM are recommended"
  else
    doctor_result OK "resources" "RAM ${mem} MB, free disk ${disk} MB"
  fi
}

doctor_check_route() {
  local text iface
  if ! have_cmd ip; then
    doctor_result WARN "route" "iproute2 is not installed" "apt-get install iproute2"
    return
  fi
  text="$(ip route show default 2>/dev/null || true)"
  if iface="$(select_default_interface "$text")"; then
    doctor_result OK "default-route" "via ${iface}"
    DOCTOR_IFACE="$iface"
  else
    doctor_result FAIL "default-route" "no default route" "Check the network configuration; proxystack will not assume eth0"
  fi
}

doctor_check_iface() {
  local ip
  if [[ -z "${DOCTOR_IFACE:-}" ]]; then
    doctor_result FAIL "interface" "external interface was not detected" "Fix the default route first"
    return
  fi
  if ip="$(detect_iface_ipv4 "$DOCTOR_IFACE" 2>/dev/null || true)" && [[ -n "$ip" ]]; then
    doctor_result OK "interface" "${DOCTOR_IFACE} address ${ip}"
  else
    doctor_result WARN "interface" "${DOCTOR_IFACE} has no IPv4 address"
  fi
}

doctor_check_public_ip() {
  local ip
  if ip="$(detect_public_ipv4 2>/dev/null || true)" && [[ -n "$ip" ]]; then
    DOCTOR_PUBLIC_IP="$ip"
    doctor_result OK "public-ipv4" "$ip"
  else
    doctor_result WARN "public-ipv4" "could not detect a public IPv4" "Check outbound HTTPS"
  fi
}

doctor_check_dns() {
  local ns
  ns="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
  if [[ -z "$ns" ]]; then
    doctor_result FAIL "dns-resolver" "no nameserver in resolv.conf" "Configure DNS"
    return
  fi
  if resolve_host_ips example.com 2>/dev/null | grep -q .; then
    doctor_result OK "dns-resolver" "nameserver ${ns}; example.com resolves"
  else
    doctor_result FAIL "dns-resolver" "nameserver ${ns} did not resolve example.com" "Fix DNS before installing Caddy"
  fi
}

doctor_check_domain() {
  local domain ips a
  domain="${CADDY_DOMAIN:-}"
  [[ -n "$domain" ]] || domain="$(config_get CADDY_DOMAIN 2>/dev/null || true)"
  if [[ -z "$domain" ]]; then
    doctor_result WARN "domain" "webhook domain is not configured"
    return
  fi
  ips="$(resolve_host_ips "$domain" 2>/dev/null || true)"
  if [[ -z "$ips" ]]; then
    doctor_result FAIL "domain" "${domain} did not resolve" "Create an A record before expecting TLS"
    return
  fi
  doctor_result OK "domain" "${domain} -> $(printf '%s' "$ips" | tr '\n' ' ')"
  if [[ -n "${DOCTOR_PUBLIC_IP:-}" ]]; then
    if printf '%s\n' "$ips" | grep -Fxq "$DOCTOR_PUBLIC_IP"; then
      doctor_result OK "domain-a" "A record matches this server"
    else
      doctor_result WARN "domain-a" "A record does not match public IPv4 ${DOCTOR_PUBLIC_IP}" "Update DNS, then rerun doctor"
    fi
  fi
  if printf '%s\n' "$ips" | grep -q ':'; then
    doctor_result WARN "domain-aaaa" "AAAA records exist; confirm they point at this host if IPv6 is used" "A mismatch can send clients to another machine"
  fi
}

doctor_check_upstream_route() {
  local upstream ip route
  upstream="${CADDY_UPSTREAM:-}"
  [[ -n "$upstream" ]] || upstream="$(config_get CADDY_UPSTREAM 2>/dev/null || true)"
  if [[ -z "$upstream" ]]; then
    doctor_result WARN "upstream-route" "upstream URL is not configured"
    return
  fi
  parse_upstream_url "$upstream" || {
    doctor_result FAIL "upstream-route" "upstream URL is invalid"
    return
  }
  if valid_ipv4 "$UPSTREAM_HOST"; then
    ip="$UPSTREAM_HOST"
    doctor_result OK "upstream-dns" "upstream host is an IPv4 address"
  else
    ip="$(resolve_host_ips "$UPSTREAM_HOST" 2>/dev/null | awk 'NR==1 {print; exit}')"
    if [[ -n "$ip" ]]; then
      doctor_result OK "upstream-dns" "${UPSTREAM_HOST} -> ${ip}"
    else
      doctor_result FAIL "upstream-dns" "${UPSTREAM_HOST} did not resolve"
      return
    fi
  fi
  DOCTOR_UPSTREAM_IP="$ip"
  DOCTOR_UPSTREAM_PORT="$UPSTREAM_PORT"
  if have_cmd ip; then
    route="$(ip route get "$ip" 2>/dev/null || true)"
    if [[ -n "$route" ]]; then
      doctor_result OK "upstream-route" "$route"
      DOCTOR_ROUTE_OK="ok"
    else
      doctor_result FAIL "upstream-route" "no route to ${ip}"
      DOCTOR_ROUTE_OK="fail"
    fi
  else
    doctor_result WARN "upstream-route" "ip route is unavailable"
    DOCTOR_ROUTE_OK="fail"
  fi
}

doctor_check_upstream_tcp() {
  local result
  if [[ -z "${DOCTOR_UPSTREAM_IP:-}" ]]; then
    doctor_result WARN "upstream-tcp" "upstream address is unknown"
    return
  fi
  result="$(tcp_probe "$DOCTOR_UPSTREAM_IP" "$DOCTOR_UPSTREAM_PORT" 5 || true)"
  DOCTOR_TCP="$result"
  case "$result" in
    ok) doctor_result OK "upstream-tcp" "${DOCTOR_UPSTREAM_IP}:${DOCTOR_UPSTREAM_PORT} accepts TCP" ;;
    timeout) doctor_result FAIL "upstream-tcp" "TCP to ${DOCTOR_UPSTREAM_IP}:${DOCTOR_UPSTREAM_PORT} timed out" "Check source-IP filtering on the upstream" ;;
    *) doctor_result FAIL "upstream-tcp" "TCP to ${DOCTOR_UPSTREAM_IP}:${DOCTOR_UPSTREAM_PORT} was refused" "The upstream port is closed" ;;
  esac
}

doctor_check_outbound() {
  local a b
  a="$(tcp_probe 1.1.1.1 443 5 || true)"
  b="$(tcp_probe 1.1.1.1 80 5 || true)"
  if [[ "$a" == "ok" && "$b" == "ok" ]]; then
    doctor_result OK "outbound" "TCP 80 and 443 are reachable"
  else
    doctor_result WARN "outbound" "80=${b} 443=${a}" "Caddy and package downloads need outbound 80/443"
  fi
}

doctor_check_dante() {
  local port="${DANTE_PORT:-51080}" user
  [[ -n "${DANTE_ENABLED:-}" ]] || DANTE_ENABLED="$(config_get DANTE_ENABLED 2>/dev/null || true)"
  if ! have_cmd danted && [[ "${DANTE_ENABLED:-0}" != "1" ]]; then
    doctor_result WARN "dante" "package is not installed"
    return
  fi
  if have_cmd danted; then
    doctor_result OK "dante-package" "danted is installed"
  else
    doctor_result FAIL "dante-package" "danted binary is missing" "proxystack install dante"
  fi
  if [[ -f "${PROXSTACK_DANTE_CONF:-/etc/danted.conf}" ]]; then
    if dante_validate_file "${PROXSTACK_DANTE_CONF}"; then
      doctor_result OK "dante-config" "config validates"
    else
      doctor_result FAIL "dante-config" "danted rejected the config" "Restore the last .bak file or reinstall"
    fi
  else
    doctor_result WARN "dante-config" "config file is missing"
  fi
  if svc_active danted 2>/dev/null; then
    doctor_result OK "dante-service" "active"
  else
    doctor_result FAIL "dante-service" "not active" "systemctl restart danted"
  fi
  if port_is_listening "$port"; then
    doctor_result OK "dante-port" "listening on ${port}"
  else
    doctor_result FAIL "dante-port" "nothing listens on ${port}"
  fi
  user="${DANTE_USER:-$(config_get DANTE_USER 2>/dev/null || true)}"
  if [[ -n "$user" ]] && id "$user" >/dev/null 2>&1; then
    doctor_result OK "dante-auth" "user ${user} exists"
  else
    doctor_result WARN "dante-auth" "proxy user is not configured"
  fi
}

doctor_check_squid() {
  local port="${SQUID_PORT:-51081}"
  if ! have_cmd squid && [[ "${SQUID_ENABLED:-0}" != "1" ]]; then
    doctor_result WARN "squid" "package is not installed"
    return
  fi
  if have_cmd squid; then
    doctor_result OK "squid-package" "squid is installed"
  else
    doctor_result FAIL "squid-package" "squid binary is missing"
  fi
  if [[ -f "${PROXSTACK_SQUID_CONF:-/etc/squid/squid.conf}" ]]; then
    if squid_validate_file "${PROXSTACK_SQUID_CONF}"; then
      doctor_result OK "squid-config" "squid -k parse succeeded"
    else
      doctor_result FAIL "squid-config" "squid -k parse failed" "Fix squid.conf before restart"
    fi
  else
    doctor_result WARN "squid-config" "squid.conf is missing"
  fi
  if svc_active squid 2>/dev/null; then
    doctor_result OK "squid-service" "active"
  else
    doctor_result FAIL "squid-service" "not active"
  fi
  if port_is_listening "$port"; then
    doctor_result OK "squid-port" "listening on ${port}"
  else
    doctor_result FAIL "squid-port" "nothing listens on ${port}"
  fi
  if [[ -f "${PROXSTACK_SQUID_PASSWD:-/etc/squid/passwords}" ]]; then
    doctor_result OK "squid-auth" "password file exists"
  else
    doctor_result WARN "squid-auth" "password file is missing"
  fi
}

doctor_check_caddy() {
  local domain path code
  if ! have_cmd caddy && [[ "${CADDY_ENABLED:-0}" != "1" ]]; then
    doctor_result WARN "caddy" "package is not installed"
    return
  fi
  if have_cmd caddy; then
    doctor_result OK "caddy-package" "caddy is installed"
  else
    doctor_result FAIL "caddy-package" "caddy binary is missing"
  fi
  if [[ -f "${PROXSTACK_CADDYFILE:-/etc/caddy/Caddyfile}" ]]; then
    if caddy_validate_file "${PROXSTACK_CADDYFILE}"; then
      doctor_result OK "caddy-config" "caddy validate succeeded"
    else
      doctor_result FAIL "caddy-config" "caddy validate failed" "Run caddy validate --config /etc/caddy/Caddyfile"
    fi
  else
    doctor_result WARN "caddy-config" "Caddyfile is missing"
  fi
  if svc_active caddy 2>/dev/null; then
    doctor_result OK "caddy-service" "active"
  else
    doctor_result FAIL "caddy-service" "not active"
  fi
  if port_is_listening 80; then
    doctor_result OK "caddy-http" "port 80 is listening"
  else
    doctor_result FAIL "caddy-http" "port 80 is closed" "Let's Encrypt HTTP-01 needs port 80"
  fi
  if port_is_listening 443; then
    doctor_result OK "caddy-https" "port 443 is listening"
  else
    doctor_result FAIL "caddy-https" "port 443 is closed"
  fi
  domain="${CADDY_DOMAIN:-$(config_get CADDY_DOMAIN 2>/dev/null || true)}"
  path="${CADDY_WEBHOOK_PATH:-$(config_get CADDY_WEBHOOK_PATH 2>/dev/null || true)}"
  path="${path:-/webhook/}"
  if [[ -n "$domain" ]] && have_cmd curl; then
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "http://${domain}/" || true)"
    case "$code" in
      301 | 308 | 302 | 307) doctor_result OK "caddy-redirect" "HTTP ${code} redirect" ;;
      *) doctor_result WARN "caddy-redirect" "HTTP status ${code}" ;;
    esac
    if have_cmd openssl; then
      local end
      end="$(echo | openssl s_client -servername "$domain" -connect "${domain}:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null || true)"
      if [[ -n "$end" ]]; then
        doctor_result OK "caddy-cert" "$end"
      else
        doctor_result WARN "caddy-cert" "certificate was not readable" "Confirm DNS and that port 80 is reachable"
      fi
    fi
    code="$(caddy_post_webhook "$domain" "$path" || true)"
    if [[ "$code" == "502" && "${DOCTOR_TCP:-}" == "timeout" && "${DOCTOR_ROUTE_OK:-}" == "ok" ]]; then
      doctor_result FAIL "caddy-webhook" "POST ${path} returned 502" "See the upstream diagnosis below"
      doctor_upstream_diagnosis ok ok timeout 502 "${DOCTOR_IFACE:-any}" "${DOCTOR_UPSTREAM_IP:-upstream}" "${DOCTOR_UPSTREAM_PORT:-443}" || true
    elif [[ "$code" =~ ^[0-9]+$ && "$code" -ge 200 && "$code" -lt 500 ]]; then
      doctor_result OK "caddy-webhook" "POST ${path} returned ${code}"
    else
      doctor_result WARN "caddy-webhook" "POST ${path} returned ${code:-none}"
    fi
  fi
}

doctor_check_firewall() {
  local backend
  backend="$(firewall_backend)"
  case "$backend" in
    ufw) doctor_result OK "firewall" "ufw is the active backend" ;;
    nftables) doctor_result WARN "firewall" "nftables has rules; proxystack will not flush them" "Add proxy allows manually if you need them" ;;
    iptables) doctor_result WARN "firewall" "iptables has rules; proxystack will not flush them" "Add proxy allows manually if you need them" ;;
    none) doctor_result WARN "firewall" "no host firewall detected" "Use proxystack firewall with the recommended profile" ;;
    *) doctor_result WARN "firewall" "backend ${backend}" ;;
  esac
}

doctor_check_telegram() {
  local body errm
  if [[ -z "${PROXSTACK_TELEGRAM_TOKEN:-}" ]] && ! read_secret_key TELEGRAM_BOT_TOKEN >/dev/null 2>&1; then
    doctor_result WARN "telegram" "bot token is not stored" "Run proxystack webhook info and pass the token when prompted"
    return
  fi
  body="$(telegram_api getWebhookInfo 2>/dev/null || true)"
  if [[ -z "$body" ]]; then
    doctor_result WARN "telegram" "getWebhookInfo failed"
    return
  fi
  telegram_format_info "$body"
  errm="$(printf '%s' "$body" | sed -n 's/.*"last_error_message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -n "$errm" ]]; then
    doctor_result WARN "telegram-error" "$errm"
    telegram_explain_error "$errm" || true
  else
    doctor_result OK "telegram" "getWebhookInfo returned no last error"
  fi
}

cmd_doctor() {
  proxystack_paths_init
  config_load || true
  ui_init
  DOCTOR_PASS=0
  DOCTOR_WARN=0
  DOCTOR_FAIL=0
  DOCTOR_JSON_ITEMS=()
  DOCTOR_RECS=()
  DOCTOR_IFACE=""
  DOCTOR_PUBLIC_IP=""
  DOCTOR_UPSTREAM_IP=""
  DOCTOR_UPSTREAM_PORT=""
  DOCTOR_TCP=""
  DOCTOR_ROUTE_OK=""
  doctor_check_os
  doctor_check_root
  doctor_check_arch
  doctor_check_resources
  doctor_check_route
  doctor_check_iface
  doctor_check_public_ip
  doctor_check_dns
  doctor_check_domain
  doctor_check_upstream_route
  doctor_check_upstream_tcp
  doctor_check_outbound
  doctor_check_dante
  doctor_check_squid
  doctor_check_caddy
  doctor_check_firewall
  doctor_check_telegram
  doctor_finish
}
