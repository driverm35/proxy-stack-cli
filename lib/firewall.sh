# shellcheck shell=bash

if [[ -n "${PROXSTACK_FIREWALL_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_FIREWALL_LOADED=1

firewall_backend() {
  local status
  if have_cmd ufw; then
    status="$(ufw status 2>/dev/null || true)"
    if [[ "$status" == *[Aa]ctive* && "$status" != *"inactive"* ]]; then
      printf 'ufw'
      return 0
    fi
  fi
  if have_cmd nft && nft list ruleset >/dev/null 2>&1; then
    if nft list ruleset 2>/dev/null | grep -q '[^[:space:]]'; then
      printf 'nftables'
      return 0
    fi
  fi
  if have_cmd iptables; then
    if iptables -S 2>/dev/null | grep -Eq '^-A '; then
      printf 'iptables'
      return 0
    fi
  fi
  if have_cmd ufw; then
    printf 'ufw'
    return 0
  fi
  printf 'none'
}

firewall_profile_name() {
  case "$1" in
    1 | recommended | Recommended) printf 'recommended' ;;
    2 | vpn | lan | VPN) printf 'vpn' ;;
    3 | public | Public) printf 'public' ;;
    *) return 1 ;;
  esac
}

render_firewall_plan() {
  local profile="$1" ssh_port="$2" dante_port="$3" squid_port="$4" cidrs_csv="$5" backend="${6:-ufw}"
  local cidr normalized
  valid_port "$ssh_port" || return 1
  valid_port "$dante_port" || return 1
  valid_port "$squid_port" || return 1
  profile="$(firewall_profile_name "$profile")" || return 1
  printf '%s\n' "# proxystack firewall plan"
  printf '%s\n' "# backend: ${backend}"
  printf '%s\n' "# SSH port ${ssh_port} is allowed before any default policy change"
  printf '%s\n' "# existing rules are kept; proxystack does not flush nftables, iptables, or ufw"
  if [[ "$backend" != "ufw" && "$backend" != "none" ]]; then
    printf '%s\n' "# REFUSE: backend ${backend} already has rules; no changes will be applied"
    return 0
  fi
  printf '%s\n' "ufw allow ${ssh_port}/tcp comment proxystack-ssh"
  printf '%s\n' "ufw allow 80/tcp comment proxystack-http"
  printf '%s\n' "ufw allow 443/tcp comment proxystack-https"
  case "$profile" in
    recommended | vpn)
      if [[ "$profile" == "vpn" && -z "$cidrs_csv" ]]; then
        cidrs_csv="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
      fi
      [[ -n "$cidrs_csv" ]] || return 1
      local IFS=','
      # shellcheck disable=SC2086
      for cidr in $cidrs_csv; do
        cidr="${cidr// /}"
        [[ -n "$cidr" ]] || continue
        normalized="$(normalize_cidr "$cidr")" || return 1
        printf '%s\n' "ufw allow from ${normalized} to any port ${dante_port} proto tcp comment proxystack-dante"
        printf '%s\n' "ufw allow from ${normalized} to any port ${dante_port} proto udp comment proxystack-dante-udp"
        printf '%s\n' "ufw allow from ${normalized} to any port ${squid_port} proto tcp comment proxystack-squid"
      done
      ;;
    public)
      printf '%s\n' "# WARNING: proxy ports are open to the Internet. Authentication is not a firewall."
      printf '%s\n' "ufw allow ${dante_port}/tcp comment proxystack-dante"
      printf '%s\n' "ufw allow ${dante_port}/udp comment proxystack-dante-udp"
      printf '%s\n' "ufw allow ${squid_port}/tcp comment proxystack-squid"
      ;;
  esac
  printf '%s\n' "ufw enable"
}

firewall_apply_line() {
  local line="$1"
  if [[ "$line" =~ ^ufw\ allow\ ([0-9]+)/(tcp|udp)\ comment\ ([A-Za-z0-9_-]+)$ ]]; then
    ufw allow "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" comment "${BASH_REMATCH[3]}"
    return
  fi
  if [[ "$line" =~ ^ufw\ allow\ from\ ([0-9./]+)\ to\ any\ port\ ([0-9]+)\ proto\ (tcp|udp)\ comment\ ([A-Za-z0-9_-]+)$ ]]; then
    normalize_cidr "${BASH_REMATCH[1]}" >/dev/null || return 1
    ufw allow from "${BASH_REMATCH[1]}" to any port "${BASH_REMATCH[2]}" proto "${BASH_REMATCH[3]}" comment "${BASH_REMATCH[4]}"
    return
  fi
  if [[ "$line" == "ufw enable" ]]; then
    ufw --force enable
    return
  fi
  [[ "$line" == \#* || -z "$line" ]] && return 0
  return 1
}

firewall_delete_line() {
  local line="$1"
  if [[ "$line" =~ ^ufw\ allow\ ([0-9]+)/(tcp|udp)\ comment\ ([A-Za-z0-9_-]+)$ ]]; then
    ufw delete allow "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" || true
    return
  fi
  if [[ "$line" =~ ^ufw\ allow\ from\ ([0-9./]+)\ to\ any\ port\ ([0-9]+)\ proto\ (tcp|udp)\ comment\ ([A-Za-z0-9_-]+)$ ]]; then
    ufw delete allow from "${BASH_REMATCH[1]}" to any port "${BASH_REMATCH[2]}" proto "${BASH_REMATCH[3]}" || true
  fi
}

cmd_firewall() {
  local sub="${PROXSTACK_POSITIONAL[1]:-apply}" profile cidrs ssh_port backend plan line
  local -a added=()
  if [[ "$sub" == "status" ]]; then
    if have_cmd ufw; then
      ufw status verbose || true
    else
      log_warn "ufw is not installed"
    fi
    if have_cmd nft; then
      log_info "nftables ruleset is present; proxystack will not flush it"
    fi
    return 0
  fi
  require_root
  profile="$(flag_value --firewall-profile "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  cidrs="$(flag_value --allow-cidr "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  ssh_port="$(detect_ssh_port)"
  backend="$(firewall_backend)"
  if [[ -z "$profile" ]]; then
    ui_prompt profile "$(msg fw_profile)" "1" || return 1
  fi
  profile="$(firewall_profile_name "$profile")" || die "$(msg invalid_choice)"
  if [[ "$profile" == "public" ]]; then
    log_warn "$(msg fw_public_warn)"
    if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" ]]; then
      [[ " ${PROXSTACK_POSITIONAL[*]} " == *" --allow-public "* ]] || die "$(msg fw_public_warn)"
    else
      local typed
      ui_prompt typed "$(msg fw_type_public)" "" || return 1
      [[ "$typed" == "PUBLIC" ]] || die "$(msg cancelled)"
    fi
  fi
  if [[ "$profile" == "recommended" && -z "$cidrs" ]]; then
    local more=""
    while true; do
      ui_prompt more "$(msg fw_cidr)" "" || return 1
      [[ -n "$more" ]] || break
      normalize_cidr "$more" >/dev/null || die "invalid CIDR"
      if [[ -n "$cidrs" ]]; then
        cidrs="${cidrs},${more}"
      else
        cidrs="$more"
      fi
      if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" ]]; then
        break
      fi
      ui_prompt more "$(msg fw_more_cidr)" "" || true
      [[ -n "$more" ]] || break
      normalize_cidr "$more" >/dev/null || die "invalid CIDR"
      cidrs="${cidrs},${more}"
    done
  fi
  plan="$(render_firewall_plan "$profile" "$ssh_port" "${DANTE_PORT:-51080}" "${SQUID_PORT:-51081}" "$cidrs" "$backend")" || return 1
  printf '%s\n' "$(msg fw_plan)"
  printf '%s\n' "$plan"
  if [[ "$backend" == "nftables" || "$backend" == "iptables" ]]; then
    log_warn "$(msg fw_skip)"
    return 2
  fi
  if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" && "${PROXSTACK_FORCE:-0}" != "1" ]]; then
    log_warn "$(msg fw_need_force)"
    return 2
  fi
  ui_confirm "$(msg fw_confirm)" || {
    log_info "$(msg cancelled)"
    return 1
  }
  if [[ "$backend" == "none" ]]; then
    remember_new_package ufw
  fi
  proxystack_paths_init
  mkdir -p "$PROXSTACK_VAR/firewall"
  ufw status verbose >"$PROXSTACK_VAR/firewall/ufw-before-$(date +%Y%m%dT%H%M%S).txt" 2>/dev/null || true
  local ssh_before=0
  if ufw status 2>/dev/null | grep -Eq "${ssh_port}/tcp"; then
    ssh_before=1
  fi
  while IFS= read -r line; do
    [[ "$line" == ufw\ * ]] || continue
    if [[ "$line" == "ufw enable" ]]; then
      if ! ufw status | grep -Eq "${ssh_port}/tcp"; then
        log_error "SSH port ${ssh_port} is not allowed; refusing to enable UFW"
        local undo
        for undo in "${added[@]}"; do
          firewall_delete_line "$undo"
        done
        log_info "$(msg rollback_ok)"
        return 1
      fi
    fi
    if ! firewall_apply_line "$line"; then
      local undo
      for undo in "${added[@]}"; do
        firewall_delete_line "$undo"
      done
      log_error "$(msg rollback_fail)"
      return 1
    fi
    if [[ "$line" == *"proxystack-ssh"* && "$ssh_before" -eq 1 ]]; then
      continue
    fi
    added+=("$line")
    printf '%s\n' "$line" >>"$PROXSTACK_VAR/firewall/applied.rules"
  done <<<"$plan"
  config_set FIREWALL_PROFILE "$profile"
  config_set FIREWALL_CIDRS "$cidrs"
  config_set FIREWALL_SSH_PORT "$ssh_port"
  log_info "$(msg fw_applied)"
}

firewall_remove_managed() {
  local line
  proxystack_paths_init
  [[ -f "$PROXSTACK_VAR/firewall/applied.rules" ]] || return 0
  while IFS= read -r line; do
    firewall_delete_line "$line"
  done <"$PROXSTACK_VAR/firewall/applied.rules"
  rm -f "$PROXSTACK_VAR/firewall/applied.rules"
}
