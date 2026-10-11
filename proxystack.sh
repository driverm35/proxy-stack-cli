#!/usr/bin/env bash
# proxystack — installer and CLI for Dante, Squid, Caddy, and Telegram webhooks.
# A checkout or an installed copy sources lib/. A lone download bootstraps from GitHub.
set -euo pipefail

# shellcheck disable=SC2034
PROXSTACK_EMBEDDED_VERSION="0.1.0"
PROXSTACK_DEFAULT_REPO="driverm35/proxy-stack-cli"

resolve_script_dir() {
  local src=""
  # A pipe (`curl | bash`) leaves BASH_SOURCE empty. set -u must not abort.
  if [[ ${#BASH_SOURCE[@]} -gt 0 ]]; then
    src="${BASH_SOURCE[0]}"
  fi
  [[ -n "$src" ]] || return 1
  cd "$(dirname "$src")" 2>/dev/null && pwd
}

resolve_lib_dir() {
  local src=""
  if [[ -n "${PROXSTACK_LIB_DIR:-}" && -f "${PROXSTACK_LIB_DIR}/common.sh" ]]; then
    printf '%s\n' "$PROXSTACK_LIB_DIR"
    return 0
  fi
  src="$(resolve_script_dir || true)"
  if [[ -n "$src" && -f "$src/lib/common.sh" ]]; then
    printf '%s\n' "$src/lib"
    return 0
  fi
  if [[ -n "$src" && -f "$src/../lib/proxystack/common.sh" ]]; then
    cd "$src/../lib/proxystack" && pwd
    return 0
  fi
  if [[ -f /usr/local/lib/proxystack/common.sh ]]; then
    printf '%s\n' /usr/local/lib/proxystack
    return 0
  fi
  return 1
}

resolve_locale_dir() {
  local lib="$1"
  if [[ -f "$lib/locales/en.sh" ]]; then
    printf '%s\n' "$lib/locales"
    return 0
  fi
  if [[ -f "$lib/../locales/en.sh" ]]; then
    cd "$lib/../locales" && pwd
    return 0
  fi
  return 1
}

bootstrap_fetch() {
  local url="$1" dest="$2"
  curl -fsSL --retry 3 --retry-delay 1 --max-time 90 -o "$dest" "$url"
}

bootstrap_main() {
  local repo="${PROXSTACK_GITHUB_REPO:-$PROXSTACK_DEFAULT_REPO}"
  local tmp api tag asset sums root
  command -v curl >/dev/null 2>&1 || {
    printf '%s\n' "curl is required to download proxystack" >&2
    exit 1
  }
  tmp="$(mktemp -d)"
  api="$tmp/release.json"
  sums="$tmp/SHA256SUMS"
  if bootstrap_fetch "https://api.github.com/repos/${repo}/releases/latest" "$api"; then
    tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$api" | head -n1)"
  fi
  tag="${tag:-main}"
  asset="proxy-stack-cli-${tag}.tar.gz"
  mkdir -p "$tmp/src"
  if [[ "$tag" != "main" ]] && bootstrap_fetch "https://github.com/${repo}/releases/download/${tag}/SHA256SUMS" "$sums"; then
    if bootstrap_fetch "https://github.com/${repo}/releases/download/${tag}/${asset}" "$tmp/bundle.tar.gz"; then
      if command -v sha256sum >/dev/null 2>&1; then
        local expected actual
        expected="$(awk -v n="$asset" '$2==n || $2=="*"n {print $1; exit}' "$sums")"
        actual="$(sha256sum "$tmp/bundle.tar.gz" | awk '{print $1}')"
        if [[ -n "$expected" && "$expected" == "$actual" ]]; then
          tar -C "$tmp/src" -xzf "$tmp/bundle.tar.gz"
        else
          rm -f "$tmp/bundle.tar.gz"
        fi
      fi
    fi
  fi
  if [[ ! -d "$tmp/src/lib" ]] && ! find "$tmp/src" -type f -name common.sh -path '*/lib/common.sh' | grep -q .; then
    if bootstrap_fetch "https://github.com/${repo}/archive/refs/heads/main.tar.gz" "$tmp/main.tar.gz"; then
      tar -C "$tmp/src" -xzf "$tmp/main.tar.gz"
    elif bootstrap_fetch "https://cdn.jsdelivr.net/gh/${repo}@main/proxystack.sh" "$tmp/src/proxystack.sh"; then
      local rel
      while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        mkdir -p "$tmp/src/$(dirname "$rel")"
        bootstrap_fetch "https://cdn.jsdelivr.net/gh/${repo}@main/${rel}" "$tmp/src/$rel" ||
          bootstrap_fetch "https://raw.githubusercontent.com/${repo}/main/${rel}" "$tmp/src/$rel" || true
      done <<'EOF'
VERSION
lib/common.sh
lib/i18n.sh
lib/ui.sh
lib/system.sh
lib/dante.sh
lib/squid.sh
lib/caddy.sh
lib/telegram.sh
lib/firewall.sh
lib/doctor.sh
lib/backup.sh
lib/update.sh
locales/en.sh
locales/ru.sh
EOF
    fi
  fi
  root="$(find "$tmp/src" -type f -path '*/lib/common.sh' | head -n1 || true)"
  if [[ -z "$root" ]]; then
    printf '%s\n' "Could not download proxystack from GitHub or jsDelivr" >&2
    exit 1
  fi
  root="$(dirname "$(dirname "$root")")"
  bash "$root/proxystack.sh" "$@"
}

source_lib() {
  local file="$PROXSTACK_LIB_DIR/$1"
  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    source "$file"
  fi
}

maybe_reexec_sudo() {
  local cmd="$1"
  shift
  if [[ "${PROXSTACK_ALLOW_NONROOT:-0}" == "1" || -n "${PROXSTACK_PREFIX:-}" ]]; then
    return 0
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  case "$cmd" in
    "" | install | configure | restart | firewall | backup | restore | export | import | uninstall | webhook | credentials | update | update-script | install-script | uninstall-script)
      if command -v sudo >/dev/null 2>&1; then
        exec sudo --preserve-env=PROXSTACK_DANTE_PASSWORD,PROXSTACK_SQUID_PASSWORD,PROXSTACK_TELEGRAM_TOKEN,PROXSTACK_LANG,PROXSTACK_HTTP_GET_HOOK,PROXSTACK_PREFIX \
          -- "$0" "$@"
      fi
      ;;
  esac
}

cmd_install() {
  local target="${PROXSTACK_POSITIONAL[1]:-}"
  if [[ "$target" == --* || "$target" == "" ]]; then
    if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" ]]; then
      die "$(msg noninteractive_missing)"
    fi
    ui_prompt target "$(msg ask_components)" "4" || return 1
    case "$target" in
      1) target="dante" ;;
      2) target="squid" ;;
      3) target="caddy" ;;
      4 | all) target="all" ;;
    esac
  fi
  case "$target" in
    all)
      dante_install
      squid_install
      caddy_install
      ;;
    dante) dante_install ;;
    squid) squid_install ;;
    caddy) caddy_install ;;
    *) die "$(msg unknown_command)" ;;
  esac
}

cmd_configure() {
  cmd_install
}

cmd_status() {
  local dante="missing" squid="missing" caddy="missing"
  proxystack_paths_init
  config_load || true
  if declare -F svc_active >/dev/null 2>&1; then
    svc_active danted 2>/dev/null && dante="active" || dante="inactive"
    svc_active squid 2>/dev/null && squid="active" || squid="inactive"
    svc_active caddy 2>/dev/null && caddy="active" || caddy="inactive"
  fi
  if [[ "${PROXSTACK_JSON:-0}" == "1" ]]; then
    printf '{"version":"%s","dante":{"enabled":"%s","port":"%s","service":"%s"},"squid":{"enabled":"%s","port":"%s","service":"%s"},"caddy":{"enabled":"%s","domain":"%s","service":"%s"}}\n' \
      "$(json_escape "$(proxystack_version_read)")" \
      "$(json_escape "${DANTE_ENABLED:-0}")" "$(json_escape "${DANTE_PORT:-51080}")" "$(json_escape "$dante")" \
      "$(json_escape "${SQUID_ENABLED:-0}")" "$(json_escape "${SQUID_PORT:-51081}")" "$(json_escape "$squid")" \
      "$(json_escape "${CADDY_ENABLED:-0}")" "$(json_escape "${CADDY_DOMAIN:-}")" "$(json_escape "$caddy")"
    return 0
  fi
  printf 'proxystack %s\n' "$(proxystack_version_read)"
  printf 'dante: %s port %s user %s\n' "$dante" "${DANTE_PORT:-51080}" "${DANTE_USER:-}"
  printf 'squid: %s port %s user %s\n' "$squid" "${SQUID_PORT:-51081}" "${SQUID_USER:-}"
  printf 'caddy: %s domain %s path %s\n' "$caddy" "${CADDY_DOMAIN:-}" "${CADDY_WEBHOOK_PATH:-/webhook/}"
}

cmd_test() {
  local target="${PROXSTACK_POSITIONAL[1]:-all}"
  local pass user port
  case "$target" in
    all | dante)
      user="${DANTE_USER:-$(config_get DANTE_USER 2>/dev/null || true)}"
      port="${DANTE_PORT:-51080}"
      pass="${PROXSTACK_DANTE_PASSWORD:-$(read_secret_key DANTE_PASSWORD 2>/dev/null || true)}"
      if [[ -n "$user" && -n "$pass" ]]; then
        dante_probe "$user" "$pass" "$port" || log_warn "Dante SOCKS5 probe failed"
      else
        log_warn "Dante probe skipped; password is not available"
      fi
      [[ "$target" == "dante" ]] && return 0
      ;;&
    all | squid)
      user="${SQUID_USER:-$(config_get SQUID_USER 2>/dev/null || true)}"
      port="${SQUID_PORT:-51081}"
      pass="${PROXSTACK_SQUID_PASSWORD:-$(read_secret_key SQUID_PASSWORD 2>/dev/null || true)}"
      if [[ -n "$user" && -n "$pass" ]]; then
        squid_probe "$user" "$pass" "$port" || log_warn "Squid CONNECT probe failed"
      else
        log_warn "Squid probe skipped; password is not available"
      fi
      [[ "$target" == "squid" ]] && return 0
      ;;&
    all | caddy | webhook)
      if [[ -n "${CADDY_DOMAIN:-$(config_get CADDY_DOMAIN 2>/dev/null || true)}" ]]; then
        caddy_post_webhook "${CADDY_DOMAIN:-$(config_get CADDY_DOMAIN)}" "${CADDY_WEBHOOK_PATH:-/webhook/}" || true
      else
        log_warn "Caddy webhook probe skipped; domain is not configured"
      fi
      [[ "$target" == "caddy" || "$target" == "webhook" ]] && return 0
      ;;&
    all | upstream)
      if [[ -n "${CADDY_UPSTREAM:-$(config_get CADDY_UPSTREAM 2>/dev/null || true)}" ]]; then
        parse_upstream_url "${CADDY_UPSTREAM:-$(config_get CADDY_UPSTREAM)}" || true
        local result="timeout"
        if [[ -n "${UPSTREAM_HOST:-}" ]]; then
          result="$(tcp_probe "${UPSTREAM_HOST}" "${UPSTREAM_PORT:-80}" 5 || true)"
        fi
        doctor_upstream_diagnosis ok ok "$result" "502" "$(detect_default_interface 2>/dev/null || echo any)" "${UPSTREAM_HOST:-unknown}" "${UPSTREAM_PORT:-80}" || true
      fi
      ;;
    *) die "$(msg unknown_command)" ;;
  esac
}

cmd_logs() {
  local target="${PROXSTACK_POSITIONAL[1]:-all}"
  case "$target" in
    all | dante) cmd_logs_dante ;;
  esac
  case "$target" in
    all | squid) cmd_logs_squid ;;
  esac
  case "$target" in
    all | caddy) cmd_logs_caddy ;;
  esac
}

cmd_restart() {
  local target="${PROXSTACK_POSITIONAL[1]:-all}"
  case "$target" in
    all | dante) cmd_restart_dante ;;
  esac
  case "$target" in
    all | squid) cmd_restart_squid ;;
  esac
  case "$target" in
    all | caddy) cmd_restart_caddy ;;
  esac
}

cmd_credentials() {
  local sub="${PROXSTACK_POSITIONAL[1]:-show}" pass
  proxystack_paths_init
  config_load || true
  printf 'dante user: %s port: %s\n' "${DANTE_USER:-}" "${DANTE_PORT:-51080}"
  printf 'squid user: %s port: %s\n' "${SQUID_USER:-}" "${SQUID_PORT:-51081}"
  printf 'secrets file: %s\n' "$PROXSTACK_SECRETS_FILE"
  if [[ "$sub" != "rotate" ]]; then
    return 0
  fi
  require_root
  if [[ -n "${DANTE_USER:-}" ]]; then
    pass="$(generate_password)" || die "$(msg pass_invalid)"
    ensure_login_user "$DANTE_USER" "$pass"
    ui_show_secret_once "$(msg password_label_dante)" "$pass"
    if [[ -f "$PROXSTACK_SECRETS_FILE" ]]; then
      write_secrets_line DANTE_PASSWORD "$pass"
    fi
  fi
  if [[ -n "${SQUID_USER:-}" ]]; then
    pass="$(generate_password)" || die "$(msg pass_invalid)"
    squid_write_password "$SQUID_USER" "$pass" "$PROXSTACK_SQUID_PASSWD"
    ui_show_secret_once "$(msg password_label_squid)" "$pass"
    if [[ -f "$PROXSTACK_SECRETS_FILE" ]]; then
      write_secrets_line SQUID_PASSWORD "$pass"
    fi
    svc_enable_restart squid || true
  fi
}

cmd_uninstall() {
  local target="${PROXSTACK_POSITIONAL[1]:-all}" pkg
  if [[ "$target" == --* ]]; then
    target="all"
  fi
  if [[ "${PROXSTACK_FORCE:-0}" != "1" ]]; then
    ui_confirm "Uninstall ${target}?" || {
      log_info "$(msg cancelled)"
      return 1
    }
  fi
  require_root
  proxystack_paths_init
  case "$target" in
    all | dante)
      svc disable --now danted 2>/dev/null || true
      ;;
  esac
  case "$target" in
    all | squid)
      svc disable --now squid 2>/dev/null || true
      ;;
  esac
  case "$target" in
    all | caddy)
      svc disable --now caddy 2>/dev/null || true
      ;;
  esac
  if [[ "$target" == "all" ]]; then
    firewall_remove_managed || true
    if [[ -f "$PROXSTACK_VAR/installed.packages" ]]; then
      while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        apt-get remove -y "$pkg" || true
      done <"$PROXSTACK_VAR/installed.packages"
    fi
  fi
  log_info "Uninstall finished. SSH rules that proxystack did not create were left in place."
}

proxystack_dispatch() {
  local cmd="${PROXSTACK_POSITIONAL[0]:-}"
  case "$cmd" in
    "")
      if [[ -t 0 && -t 1 && "${PROXSTACK_NONINTERACTIVE:-0}" != "1" ]]; then
        ui_main_menu
      else
        cmd_help
      fi
      ;;
    help) cmd_help ;;
    version) cmd_version ;;
    language) cmd_language ;;
    about) cmd_about ;;
    install-script) cmd_install_script ;;
    uninstall-script) cmd_uninstall_script ;;
    update | update-script) cmd_update_script ;;
    install) cmd_install ;;
    configure) cmd_configure ;;
    status) cmd_status ;;
    doctor) cmd_doctor ;;
    test) cmd_test ;;
    logs) cmd_logs ;;
    restart) cmd_restart ;;
    credentials) cmd_credentials ;;
    firewall) cmd_firewall ;;
    webhook) cmd_webhook ;;
    backup) cmd_backup ;;
    restore) cmd_restore ;;
    export) cmd_export ;;
    import) cmd_import ;;
    uninstall) cmd_uninstall ;;
    migration) cmd_migration ;;
    *) die "$(msg unknown_command)" ;;
  esac
}

main() {
  local lib locale cmd
  if ! lib="$(resolve_lib_dir)"; then
    bootstrap_main "$@"
    return
  fi
  PROXSTACK_LIB_DIR="$lib"
  local src
  src="$(resolve_script_dir || true)"
  if [[ -n "$src" && -f "$src/lib/common.sh" ]]; then
    # shellcheck disable=SC2034
    PROXSTACK_ROOT="$src"
  fi
  source_lib common.sh
  source_lib i18n.sh
  source_lib ui.sh
  source_lib system.sh
  source_lib dante.sh
  source_lib squid.sh
  source_lib caddy.sh
  source_lib telegram.sh
  source_lib firewall.sh
  source_lib doctor.sh
  source_lib backup.sh
  source_lib update.sh
  locale="$(resolve_locale_dir "$lib")"
  i18n_init "$locale"
  proxystack_parse_args "$@"
  proxystack_paths_init
  proxystack_version_read >/dev/null
  config_load || true
  ui_init
  cmd="${PROXSTACK_POSITIONAL[0]:-}"
  maybe_reexec_sudo "$cmd" "$@"
  if [[ -n "${PROXSTACK_LANG_CLI:-}" ]]; then
    PROXSTACK_LANG="$(language_normalize "$PROXSTACK_LANG_CLI")" || die "$(msg invalid_choice)"
  elif [[ "$cmd" == "version" || "$cmd" == "help" ]]; then
    PROXSTACK_LANG="${PROXSTACK_LANG:-en}"
  else
    ui_prompt_language
  fi
  proxystack_dispatch
}

_proxystack_src=""
if [[ ${#BASH_SOURCE[@]} -gt 0 ]]; then
  _proxystack_src="${BASH_SOURCE[0]}"
fi
if [[ -z "$_proxystack_src" || "$_proxystack_src" == "$0" ]]; then
  main "$@"
fi
unset -v _proxystack_src
