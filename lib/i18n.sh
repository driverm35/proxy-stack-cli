# shellcheck shell=bash

if [[ -n "${PROXSTACK_I18N_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_I18N_LOADED=1

i18n_init() {
  local dir="$1"
  # shellcheck disable=SC1090
  source "$dir/en.sh"
  # shellcheck disable=SC1090
  source "$dir/ru.sh"
}

msg() {
  local key="$1" text=""
  case "${PROXSTACK_LANG:-en}" in
    ru)
      text="$(i18n_ru "$key")"
      if [[ -z "$text" || "$text" == "$key" ]]; then
        text="$(i18n_en "$key")"
      fi
      ;;
    *)
      text="$(i18n_en "$key")"
      ;;
  esac
  printf '%s' "$text"
}

msg_block() {
  local key="$1"
  case "${PROXSTACK_LANG:-en}" in
    ru) i18n_ru_block "$key" ;;
    *) i18n_en_block "$key" ;;
  esac
}
