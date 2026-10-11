# shellcheck shell=bash

if [[ -n "${PROXSTACK_UI_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_UI_LOADED=1

ui_init() {
  UI_RED=""
  UI_GREEN=""
  UI_YELLOW=""
  UI_BLUE=""
  UI_BOLD=""
  UI_RESET=""
  if [[ -t 1 && -z "${NO_COLOR:-}" && "${PROXSTACK_QUIET:-0}" != "1" ]]; then
    # shellcheck disable=SC2034
    UI_RED=$'\033[31m'
    # shellcheck disable=SC2034
    UI_GREEN=$'\033[32m'
    # shellcheck disable=SC2034
    UI_YELLOW=$'\033[33m'
    UI_BLUE=$'\033[34m'
    UI_BOLD=$'\033[1m'
    UI_RESET=$'\033[0m'
  fi
}

ui_is_tty() {
  [[ -t 0 && -t 1 ]]
}

ui_prompt() {
  local varname="$1" text="$2" default="${3:-}" answer
  if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
    if [[ -n "$default" ]]; then
      printf -v "$varname" '%s' "$default"
      return 0
    fi
    log_error "$(msg noninteractive_missing) ($text)"
    return 1
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$text [$default]: " answer
    answer="${answer:-$default}"
  else
    read -r -p "$text: " answer
  fi
  printf -v "$varname" '%s' "$answer"
}

ui_prompt_secret() {
  local varname="$1" text="$2" first second tracing=0
  case "$-" in
    *x*) tracing=1 && set +x ;;
  esac
  if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
    [[ "$tracing" -eq 1 ]] && set -x
    return 1
  fi
  read -r -s -p "$text: " first
  printf '\n' >&2
  read -r -s -p "$(msg confirm_password): " second
  printf '\n' >&2
  [[ "$tracing" -eq 1 ]] && set -x
  if [[ "$first" != "$second" ]]; then
    log_error "$(msg password_mismatch)"
    return 1
  fi
  printf -v "$varname" '%s' "$first"
}

ui_confirm() {
  local text="$1" answer
  if [[ "${PROXSTACK_FORCE:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
    return 1
  fi
  read -r -p "$text [y/N]: " answer
  case "$answer" in
    y | Y | yes | YES | да | Да) return 0 ;;
    *) return 1 ;;
  esac
}

ui_pause() {
  local _
  [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]] && return 0
  read -r -p "$(msg press_enter)" _
}

ui_prompt_language() {
  local choice norm
  if [[ -n "${PROXSTACK_LANG_CLI:-}" ]]; then
    language_set "$PROXSTACK_LANG_CLI" || die "$(msg invalid_choice)"
    return 0
  fi
  if config_get PROXSTACK_LANG >/dev/null 2>&1; then
    PROXSTACK_LANG="$(config_get PROXSTACK_LANG)"
    return 0
  fi
  if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
    PROXSTACK_LANG="${PROXSTACK_LANG:-en}"
    return 0
  fi
  printf '%s\n' "Select language / Выберите язык"
  printf '  1) Russian\n'
  printf '  2) English\n'
  read -r -p "> " choice
  norm="$(language_normalize "$choice")" || die "$(msg invalid_choice)"
  language_set "$norm"
  log_info "$(msg lang_saved): $norm"
}

ui_choose_password() {
  local varname="$1" generated choice
  if [[ "${PROXSTACK_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
    generated="$(generate_password)" || return 1
    printf -v "$varname" '%s' "$generated"
    return 0
  fi
  ui_prompt choice "$(msg ask_generate)" "1" || return 1
  case "$choice" in
    1 | yes | y)
      generated="$(generate_password)" || return 1
      printf -v "$varname" '%s' "$generated"
      ;;
    *)
      ui_prompt_secret "$varname" "$(msg ask_custom_password)" || return 1
      ;;
  esac
  valid_password "${!varname}" || {
    log_error "$(msg pass_invalid)"
    return 1
  }
}

ui_show_secret_once() {
  local label="$1" value="$2" tracing=0
  case "$-" in
    *x*) tracing=1 && set +x ;;
  esac
  printf '%s: %s\n' "$label" "$value" >&2
  printf '%s\n' "$(msg password_once)" >&2
  [[ "$tracing" -eq 1 ]] && set -x
}

ui_main_menu() {
  local choice
  while true; do
    printf '\n%s%s %s%s\n' "$UI_BOLD" "$(msg menu_title)" "$(proxystack_version_read)" "$UI_RESET"
    printf '  %s1%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_install)"
    printf '  %s2%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_status)"
    printf '  %s3%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_configure)"
    printf '  %s4%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_tests)"
    printf '  %s5%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_doctor)"
    printf '  %s6%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_credentials)"
    printf '  %s7%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_firewall)"
    printf '  %s8%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_webhook)"
    printf '  %s9%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_logs)"
    printf '  %s10%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_backup)"
    printf '  %s11%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_migration)"
    printf '  %s12%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_update)"
    printf '  %s13%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_uninstall)"
    printf '  %s14%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_about)"
    printf '  %s0%s) %s\n' "$UI_BLUE" "$UI_RESET" "$(msg menu_exit)"
    read -r -p "$(msg menu_select): " choice
    case "$choice" in
      1) cmd_install ;;
      2) cmd_status ;;
      3) cmd_configure ;;
      4) PROXSTACK_POSITIONAL=(test all) && cmd_test ;;
      5) cmd_doctor ;;
      6) cmd_credentials ;;
      7) cmd_firewall ;;
      8) cmd_webhook ;;
      9) cmd_logs ;;
      10) cmd_backup_menu ;;
      11) cmd_migration ;;
      12) cmd_update_script ;;
      13) cmd_uninstall ;;
      14) cmd_about ;;
      0 | q | exit) exit 0 ;;
      *) log_warn "$(msg invalid_choice)" ;;
    esac
    ui_pause
  done
}

cmd_help() {
  msg_block help
  printf '\n'
}

cmd_about() {
  cmd_version
  msg_block about
  printf 'repo: https://github.com/%s\n' "$(proxystack_repo)"
}

cmd_version() {
  local v repo
  v="$(proxystack_version_read)"
  repo="$(proxystack_repo)"
  if [[ "${PROXSTACK_JSON:-0}" == "1" ]]; then
    printf '{"name":"proxystack","version":"%s","repo":"%s"}\n' "$(json_escape "$v")" "$(json_escape "$repo")"
  else
    printf 'proxystack %s\n' "$v"
  fi
}

cmd_language() {
  local choice="${PROXSTACK_POSITIONAL[1]:-}"
  if [[ -z "$choice" ]]; then
    ui_prompt choice "1 Russian, 2 English" "" || return 1
  fi
  language_set "$choice" || die "$(msg invalid_choice)"
  log_info "$(msg lang_saved): $PROXSTACK_LANG"
}
