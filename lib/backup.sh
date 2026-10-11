# shellcheck shell=bash

if [[ -n "${PROXSTACK_BACKUP_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_BACKUP_LOADED=1

backup_metadata_json() {
  local secrets="$1" iface ip host
  iface="$(detect_default_interface 2>/dev/null || true)"
  ip="$(detect_public_ipv4 2>/dev/null || true)"
  host="$(hostname 2>/dev/null || true)"
  cat <<EOF
{
  "format": 1,
  "cli_version": "$(proxystack_version_read)",
  "created_utc": "$(backup_stamp)",
  "hostname": "$(json_escape "$host")",
  "public_ipv4": "$(json_escape "$ip")",
  "default_interface": "$(json_escape "$iface")",
  "dante_port": "${DANTE_PORT:-51080}",
  "squid_port": "${SQUID_PORT:-51081}",
  "caddy_domain": "$(json_escape "${CADDY_DOMAIN:-}")",
  "caddy_upstream": "$(json_escape "${CADDY_UPSTREAM:-}")",
  "secrets_included": ${secrets}
}
EOF
}

backup_stage_files() {
  local stage="$1" with_secrets="$2"
  proxystack_paths_init
  mkdir -p "$stage/etc/proxystack" "$stage/dante" "$stage/squid" "$stage/caddy" "$stage/firewall" "$stage/meta"
  if [[ -f "$PROXSTACK_CONFIG_FILE" ]]; then
    cp "$PROXSTACK_CONFIG_FILE" "$stage/etc/proxystack/config.env"
  fi
  if [[ -f "$PROXSTACK_DANTE_CONF" ]]; then
    cp "$PROXSTACK_DANTE_CONF" "$stage/dante/danted.conf"
  fi
  if [[ -f "$PROXSTACK_SQUID_CONF" ]]; then
    cp "$PROXSTACK_SQUID_CONF" "$stage/squid/squid.conf"
  fi
  if [[ -f "$PROXSTACK_CADDYFILE" ]]; then
    cp "$PROXSTACK_CADDYFILE" "$stage/caddy/Caddyfile"
  fi
  if [[ -f "$PROXSTACK_VAR/firewall/applied.rules" ]]; then
    cp "$PROXSTACK_VAR/firewall/applied.rules" "$stage/firewall/applied.rules"
  fi
  backup_metadata_json "$with_secrets" >"$stage/meta/metadata.json"
  if [[ "$with_secrets" == "true" ]]; then
    if [[ -f "$PROXSTACK_SECRETS_FILE" ]]; then
      cp "$PROXSTACK_SECRETS_FILE" "$stage/etc/proxystack/secrets.env"
    fi
    if [[ -f "$PROXSTACK_SQUID_PASSWD" ]]; then
      cp "$PROXSTACK_SQUID_PASSWD" "$stage/squid/passwords"
    fi
  fi
}

backup_create() {
  local dest="${1:-}" with_secrets="${2:-0}" passphrase="${3:-}"
  local stage stamp name plain
  proxystack_paths_init
  config_load || true
  stamp="$(backup_stamp)"
  name="$(backup_archive_name "$stamp")"
  if [[ -z "$dest" ]]; then
    mkdir -p "$PROXSTACK_VAR/backups"
    dest="$PROXSTACK_VAR/backups/$name"
  fi
  mkdir -p "$(dirname "$dest")"
  stage="$(mktemp -d)"
  if [[ "$with_secrets" == "1" ]]; then
    log_warn "$(msg bk_secrets_warn)"
    [[ -n "$passphrase" ]] || passphrase="$(flag_value --secrets-passphrase "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
    if [[ -z "$passphrase" ]]; then
      ui_prompt_secret passphrase "$(msg bk_passphrase)" || {
        rm -rf "$stage"
        return 1
      }
    fi
    backup_stage_files "$stage" true
    plain="$(mktemp)"
    tar -C "$stage" -czf "$plain" .
    openssl enc -aes-256-cbc -pbkdf2 -salt -in "$plain" -out "$dest" -pass "pass:${passphrase}"
    rm -f "$plain"
  else
    backup_stage_files "$stage" false
    tar -C "$stage" -czf "$dest" .
  fi
  rm -rf "$stage"
  chmod 600 "$dest" 2>/dev/null || true
  log_info "$(msg bk_created): $dest"
  printf '%s\n' "$dest"
}

backup_extract() {
  local archive="$1" dest="$2" passphrase="${3:-}"
  mkdir -p "$dest"
  if [[ "$archive" == *.enc ]]; then
    [[ -n "$passphrase" ]] || return 1
    local plain
    plain="$(mktemp)"
    openssl enc -d -aes-256-cbc -pbkdf2 -in "$archive" -out "$plain" -pass "pass:${passphrase}"
    tar -C "$dest" -xzf "$plain"
    rm -f "$plain"
  else
    tar -C "$dest" -xzf "$archive"
  fi
}

restore_rewrite_dante() {
  local file="$1" iface port
  [[ -f "$file" ]] || return 0
  iface="$(detect_default_interface 2>/dev/null || true)"
  [[ -n "$iface" ]] || return 0
  port="$(awk '/^internal:/ {for (i=1;i<=NF;i++) if ($i=="=") {print $(i+1); exit}}' "$file")"
  [[ -n "$port" ]] || port="${DANTE_PORT:-51080}"
  render_dante_config "$iface" "$port" >"${file}.new"
  mv "${file}.new" "$file"
  log_info "Dante interface rewritten to ${iface}"
}

cmd_restore() {
  local archive passphrase="" stage old_ip new_ip meta
  archive="$(flag_value --file "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  [[ -n "$archive" ]] || archive="$(flag_value --input "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  if [[ -z "$archive" ]]; then
    ui_prompt archive "Backup file" "" || return 1
  fi
  [[ -f "$archive" ]] || die "backup file not found"
  require_root
  proxystack_paths_init
  if [[ "$archive" == *.enc || " ${PROXSTACK_POSITIONAL[*]} " == *" --with-secrets "* ]]; then
    passphrase="$(flag_value --secrets-passphrase "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
    [[ -n "$passphrase" ]] || ui_prompt_secret passphrase "$(msg bk_passphrase)" || return 1
  fi
  stage="$(mktemp -d)"
  backup_extract "$archive" "$stage" "$passphrase"
  meta="$stage/meta/metadata.json"
  old_ip="$(sed -n 's/.*"public_ipv4"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$meta" | head -n1)"
  new_ip="$(detect_public_ipv4 2>/dev/null || true)"
  if [[ -f "$stage/dante/danted.conf" ]]; then
    restore_rewrite_dante "$stage/dante/danted.conf"
    if [[ -f "$stage/dante/danted.conf" ]]; then
      timestamp_backup_file "$PROXSTACK_DANTE_CONF" >/dev/null 2>&1 || true
      cp "$stage/dante/danted.conf" "$PROXSTACK_DANTE_CONF"
    fi
  fi
  if [[ -f "$stage/squid/squid.conf" ]]; then
    timestamp_backup_file "$PROXSTACK_SQUID_CONF" >/dev/null 2>&1 || true
    mkdir -p "$(dirname "$PROXSTACK_SQUID_CONF")"
    cp "$stage/squid/squid.conf" "$PROXSTACK_SQUID_CONF"
  fi
  if [[ -f "$stage/caddy/Caddyfile" ]]; then
    timestamp_backup_file "$PROXSTACK_CADDYFILE" >/dev/null 2>&1 || true
    mkdir -p "$(dirname "$PROXSTACK_CADDYFILE")"
    cp "$stage/caddy/Caddyfile" "$PROXSTACK_CADDYFILE"
    log_info "Caddy will request a new certificate on the next reload"
  fi
  if [[ -f "$stage/etc/proxystack/config.env" ]]; then
    mkdir -p "$PROXSTACK_ETC"
    cp "$stage/etc/proxystack/config.env" "$PROXSTACK_CONFIG_FILE"
    config_load || true
    if iface="$(detect_default_interface 2>/dev/null || true)" && [[ -n "$iface" ]]; then
      config_set DANTE_IFACE "$iface"
    fi
  fi
  if [[ -f "$stage/etc/proxystack/secrets.env" ]]; then
    cp "$stage/etc/proxystack/secrets.env" "$PROXSTACK_SECRETS_FILE"
    chmod 600 "$PROXSTACK_SECRETS_FILE"
  fi
  if [[ -n "$old_ip" && -n "$new_ip" && "$old_ip" != "$new_ip" ]]; then
    log_warn "Previous public IPv4: ${old_ip}"
    log_warn "Current public IPv4: ${new_ip}"
    log_warn "$(msg bk_dns)"
  elif [[ -n "$new_ip" ]]; then
    log_info "$(msg bk_dns) (${new_ip})"
  fi
  rm -rf "$stage"
  log_info "$(msg bk_restored)"
  if declare -F cmd_doctor >/dev/null 2>&1; then
    cmd_doctor || true
  fi
}

cmd_backup() {
  local dest with=0 pass
  dest="$(flag_value --output "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  if [[ " ${PROXSTACK_POSITIONAL[*]} " == *" --with-secrets "* ]]; then
    with=1
    pass="$(flag_value --secrets-passphrase "${PROXSTACK_POSITIONAL[@]}" 2>/dev/null || true)"
  fi
  backup_create "$dest" "$with" "$pass"
}

cmd_export() { cmd_backup; }
cmd_import() { cmd_restore; }

cmd_backup_menu() {
  local choice
  if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" ]]; then
    cmd_backup
    return
  fi
  printf '1) backup\n2) restore\n3) export\n4) import\n'
  ui_prompt choice "$(msg menu_select)" "1" || return 1
  case "$choice" in
    1) cmd_backup ;;
    2) cmd_restore ;;
    3) cmd_export ;;
    4) cmd_import ;;
    *) die "$(msg invalid_choice)" ;;
  esac
}

cmd_migration() {
  msg_block migration
  local sub="${PROXSTACK_POSITIONAL[1]:-}"
  case "$sub" in
    export) cmd_export ;;
    import) cmd_import ;;
  esac
}
