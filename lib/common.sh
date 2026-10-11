# shellcheck shell=bash
# Shared helpers for proxystack. Safe to source; no service changes on load.

if [[ -n "${PROXSTACK_COMMON_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_COMMON_LOADED=1

PROXSTACK_EMBEDDED_VERSION="0.1.0"
PROXSTACK_DEFAULT_REPO="driverm35/proxy-stack-cli"

proxystack_paths_init() {
  if [[ -n "${PROXSTACK_PREFIX:-}" ]]; then
    : "${PROXSTACK_BIN_DIR:=$PROXSTACK_PREFIX/bin}"
    : "${PROXSTACK_LIB_INSTALL:=$PROXSTACK_PREFIX/lib/proxystack}"
    : "${PROXSTACK_ETC:=$PROXSTACK_PREFIX/etc/proxystack}"
    : "${PROXSTACK_VAR:=$PROXSTACK_PREFIX/var/lib/proxystack}"
    : "${PROXSTACK_LOG_DIR:=$PROXSTACK_PREFIX/var/log/proxystack}"
  else
    : "${PROXSTACK_BIN_DIR:=/usr/local/bin}"
    : "${PROXSTACK_LIB_INSTALL:=/usr/local/lib/proxystack}"
    : "${PROXSTACK_ETC:=/etc/proxystack}"
    : "${PROXSTACK_VAR:=/var/lib/proxystack}"
    : "${PROXSTACK_LOG_DIR:=/var/log/proxystack}"
  fi
  : "${PROXSTACK_CONFIG_FILE:=$PROXSTACK_ETC/config.env}"
  : "${PROXSTACK_SECRETS_FILE:=$PROXSTACK_ETC/secrets.env}"
  : "${PROXSTACK_DANTE_CONF:=/etc/danted.conf}"
  : "${PROXSTACK_SQUID_CONF:=/etc/squid/squid.conf}"
  : "${PROXSTACK_SQUID_PASSWD:=/etc/squid/passwords}"
  : "${PROXSTACK_CADDYFILE:=/etc/caddy/Caddyfile}"
  : "${PROXSTACK_CADDY_LOG_DIR:=/var/log/caddy}"
  : "${DANTE_PORT:=51080}"
  : "${SQUID_PORT:=51081}"
  : "${CADDY_WEBHOOK_PATH:=/webhook/}"
}

proxystack_version_read() {
  local candidate
  if [[ -n "${PROXSTACK_VERSION_FILE:-}" && -f "${PROXSTACK_VERSION_FILE}" ]]; then
    tr -d '[:space:]' <"${PROXSTACK_VERSION_FILE}"
    return 0
  fi
  for candidate in \
    "${PROXSTACK_ROOT:-}/VERSION" \
    "${PROXSTACK_LIB_DIR:-}/VERSION" \
    "${PROXSTACK_LIB_DIR:-}/../VERSION"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      tr -d '[:space:]' <"$candidate"
      return 0
    fi
  done
  printf '%s' "$PROXSTACK_EMBEDDED_VERSION"
}

proxystack_repo() {
  local candidate
  if [[ -n "${PROXSTACK_GITHUB_REPO:-}" ]]; then
    printf '%s' "$PROXSTACK_GITHUB_REPO"
    return 0
  fi
  for candidate in \
    "${PROXSTACK_LIB_DIR:-}/REPO" \
    "${PROXSTACK_LIB_INSTALL:-}/REPO"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      tr -d '[:space:]' <"$candidate"
      return 0
    fi
  done
  printf '%s' "$PROXSTACK_DEFAULT_REPO"
}

proxystack_parse_args() {
  PROXSTACK_NONINTERACTIVE="${PROXSTACK_NONINTERACTIVE:-0}"
  PROXSTACK_FORCE="${PROXSTACK_FORCE:-0}"
  PROXSTACK_JSON="${PROXSTACK_JSON:-0}"
  PROXSTACK_VERBOSE="${PROXSTACK_VERBOSE:-0}"
  PROXSTACK_QUIET="${PROXSTACK_QUIET:-0}"
  PROXSTACK_LANG_CLI=""
  PROXSTACK_POSITIONAL=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --non-interactive)
        PROXSTACK_NONINTERACTIVE=1
        shift
        ;;
      --force)
        PROXSTACK_FORCE=1
        shift
        ;;
      --json)
        PROXSTACK_JSON=1
        shift
        ;;
      --verbose)
        PROXSTACK_VERBOSE=1
        shift
        ;;
      --quiet)
        PROXSTACK_QUIET=1
        shift
        ;;
      --lang)
        # shellcheck disable=SC2034
        PROXSTACK_LANG_CLI="${2:-}"
        shift 2
        ;;
      --lang=*)
        # shellcheck disable=SC2034
        PROXSTACK_LANG_CLI="${1#*=}"
        shift
        ;;
      --prefix)
        PROXSTACK_PREFIX="${2:-}"
        shift 2
        ;;
      --prefix=*)
        PROXSTACK_PREFIX="${1#*=}"
        shift
        ;;
      --help | -h)
        PROXSTACK_POSITIONAL+=("help")
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          PROXSTACK_POSITIONAL+=("$1")
          shift
        done
        ;;
      *)
        PROXSTACK_POSITIONAL+=("$1")
        shift
        ;;
    esac
  done
}

flag_value() {
  local name="$1"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      "$name")
        printf '%s' "${2:-}"
        return 0
        ;;
      "$name"=*)
        printf '%s' "${1#*=}"
        return 0
        ;;
      *)
        shift
        ;;
    esac
  done
  return 1
}

redact_text() {
  local s="$1"
  local out="$s"
  out="$(printf '%s' "$out" | sed -E \
    -e 's/[Pp]roxy-[Aa]uthorization:[[:space:]]*[^[:space:]]+/Proxy-Authorization: REDACTED/g' \
    -e 's/[Aa]uthorization:[[:space:]]*[Bb]asic[[:space:]]+[^[:space:]]+/Authorization: Basic REDACTED/g' \
    -e 's#(https?://)[^[:space:]/@:]+:[^[:space:]@]+@#\1***:***@#g' \
    -e 's/[0-9]{6,12}:[A-Za-z0-9_-]{20,}/REDACTED_TOKEN/g' \
    -e 's/(--[A-Za-z0-9-]*password[[:space:]]+)[^[:space:]]+/\1***/Ig' \
    -e 's/(--[A-Za-z0-9-]*token[[:space:]]+)[^[:space:]]+/\1***/Ig' \
    -e 's/([Pp]ass(word|wd)|[Tt]oken|[Ss]ecret)([=:][[:space:]]*)[^[:space:],;&]+/\1\3***/g')"
  printf '%s' "$out"
}

log_file() {
  local level="$1"
  local msg="$2"
  proxystack_paths_init
  mkdir -p "$PROXSTACK_LOG_DIR" 2>/dev/null || return 0
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$msg" >>"$PROXSTACK_LOG_DIR/proxystack.log" 2>/dev/null || true
}

log_debug() {
  [[ "${PROXSTACK_VERBOSE:-0}" == "1" ]] || return 0
  local msg
  msg="$(redact_text "$*")"
  printf 'debug: %s\n' "$msg" >&2
  log_file DEBUG "$msg"
}

log_info() {
  local msg
  msg="$(redact_text "$*")"
  if [[ "${PROXSTACK_QUIET:-0}" != "1" ]]; then
    printf '%s\n' "$msg"
  fi
  log_file INFO "$msg"
}

log_warn() {
  local msg
  msg="$(redact_text "$*")"
  printf '%s\n' "$msg" >&2
  log_file WARN "$msg"
}

log_error() {
  local msg
  msg="$(redact_text "$*")"
  printf '%s\n' "$msg" >&2
  log_file ERROR "$msg"
}

die() {
  log_error "$*"
  exit 1
}

is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

require_root() {
  if [[ "${PROXSTACK_ALLOW_NONROOT:-0}" == "1" ]]; then
    return 0
  fi
  if is_root; then
    return 0
  fi
  die "root privileges are required; re-run with sudo"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  ((10#$p >= 1 && 10#$p <= 65535))
}

valid_ipv4() {
  local ip="$1" o1 o2 o3 o4 o
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  o1="${BASH_REMATCH[1]}"
  o2="${BASH_REMATCH[2]}"
  o3="${BASH_REMATCH[3]}"
  o4="${BASH_REMATCH[4]}"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    [[ "$o" =~ ^0[0-9]+$ ]] && return 1
    if ((10#$o > 255)); then
      return 1
    fi
  done
  return 0
}

is_public_ipv4() {
  local ip="$1" a b
  valid_ipv4 "$ip" || return 1
  IFS=. read -r a b _ _ <<<"$ip"
  ((10#$a == 0 || 10#$a == 10 || 10#$a == 127 || 10#$a >= 224)) && return 1
  ((10#$a == 172 && 10#$b >= 16 && 10#$b <= 31)) && return 1
  ((10#$a == 192 && 10#$b == 168)) && return 1
  ((10#$a == 169 && 10#$b == 254)) && return 1
  ((10#$a == 100 && 10#$b >= 64 && 10#$b <= 127)) && return 1
  return 0
}

valid_cidr() {
  local c="$1" ip prefix
  if [[ "$c" =~ ^([0-9.]+)/([0-9]+)$ ]]; then
    ip="${BASH_REMATCH[1]}"
    prefix="${BASH_REMATCH[2]}"
    valid_ipv4 "$ip" || return 1
    ((10#$prefix >= 0 && 10#$prefix <= 32)) || return 1
    return 0
  fi
  valid_ipv4 "$c"
}

normalize_cidr() {
  local c="$1"
  valid_cidr "$c" || return 1
  if [[ "$c" == */* ]]; then
    printf '%s' "$c"
  else
    printf '%s/32' "$c"
  fi
}

valid_domain() {
  local d="$1"
  [[ ${#d} -le 253 ]] || return 1
  [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

valid_iface() {
  [[ "$1" =~ ^[A-Za-z0-9_.:-]{1,15}$ ]]
}

valid_password() {
  local p="$1"
  [[ ${#p} -ge 8 && ${#p} -le 128 ]] || return 1
  [[ "$p" =~ ^[A-Za-z0-9!#%^*+=._-]+$ ]] || return 1
  return 0
}

valid_upstream_url() {
  local url="$1"
  [[ "$url" != *$'\n'* && "$url" != *" "* ]] || return 1
  [[ "$url" =~ ^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?(/.*)?$ ]]
}

normalize_webhook_path() {
  local p="${1:-/webhook/}"
  [[ "$p" == /* ]] || p="/$p"
  [[ "$p" == */ ]] || p="$p/"
  [[ "$p" =~ ^/[A-Za-z0-9._~/-]*/$ ]] || return 1
  printf '%s' "$p"
}

generate_password() {
  local raw="" filtered
  if [[ -r /dev/urandom ]]; then
    raw="$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9' || true)"
  fi
  if [[ ${#raw} -lt 24 ]] && command -v openssl >/dev/null 2>&1; then
    raw="$(openssl rand -base64 96 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9' || true)"
  fi
  filtered="${raw//[^A-Za-z0-9]/}"
  if [[ ${#filtered} -lt 24 ]]; then
    return 1
  fi
  printf '%s' "${filtered:0:24}"
}

config_key_ok() {
  [[ "$1" =~ ^[A-Z][A-Z0-9_]*$ ]]
}

config_set() {
  local key="$1" value="$2" tmp line k
  config_key_ok "$key" || return 1
  [[ "$value" != *$'\n'* ]] || return 1
  proxystack_paths_init
  mkdir -p "$PROXSTACK_ETC"
  touch "$PROXSTACK_CONFIG_FILE"
  chmod 644 "$PROXSTACK_CONFIG_FILE"
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    k="${line%%=*}"
    if [[ "$k" == "$key" ]]; then
      continue
    fi
    printf '%s\n' "$line" >>"$tmp"
  done <"$PROXSTACK_CONFIG_FILE"
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv "$tmp" "$PROXSTACK_CONFIG_FILE"
  chmod 644 "$PROXSTACK_CONFIG_FILE"
  printf -v "$key" '%s' "$value"
}

config_get() {
  local key="$1" line k v
  config_key_ok "$key" || return 1
  proxystack_paths_init
  [[ -f "$PROXSTACK_CONFIG_FILE" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || continue
    k="${line%%=*}"
    v="${line#*=}"
    if [[ "$k" == "$key" ]]; then
      printf '%s' "$v"
      return 0
    fi
  done <"$PROXSTACK_CONFIG_FILE"
  return 1
}

config_load() {
  local line k v
  proxystack_paths_init
  [[ -f "$PROXSTACK_CONFIG_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || continue
    k="${line%%=*}"
    v="${line#*=}"
    printf -v "$k" '%s' "$v"
  done <"$PROXSTACK_CONFIG_FILE"
}

language_normalize() {
  case "$1" in
    1 | ru | RU | ru_RU | russian | Russian)
      printf 'ru'
      ;;
    2 | en | EN | en_US | english | English)
      printf 'en'
      ;;
    *)
      return 1
      ;;
  esac
}

language_set() {
  local norm
  norm="$(language_normalize "$1")" || return 1
  # shellcheck disable=SC2034
  PROXSTACK_LANG="$norm"
  config_set PROXSTACK_LANG "$norm"
}

version_is_newer() {
  local latest="${1#v}" current="${2#v}" first
  [[ "$latest" == "$current" ]] && return 1
  first="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | head -n1)"
  [[ "$first" == "$current" ]]
}

backup_stamp() {
  date -u +%Y%m%dT%H%M%SZ
}

backup_archive_name() {
  local stamp="$1"
  [[ "$stamp" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || return 1
  printf 'proxystack-%s.tar.gz' "$stamp"
}

timestamp_backup_file() {
  local src="$1" dest stamp
  [[ -f "$src" ]] || return 1
  stamp="$(date +%Y%m%dT%H%M%S)"
  dest="${src}.bak.${stamp}"
  cp -a "$src" "$dest"
  printf '%s' "$dest"
}

rollback_config() {
  local dest="$1" backup="$2" restart_fn="$3"
  if [[ -n "$backup" && -f "$backup" ]]; then
    cp -a "$backup" "$dest" || return 1
  else
    rm -f "$dest"
  fi
  "$restart_fn"
}

apply_with_rollback() {
  local dest="$1" newfile="$2" mode="$3" validate_fn="$4" restart_fn="$5" health_fn="$6"
  local backup="" stamp dir
  PROXSTACK_LAST_BACKUP=""
  if [[ ! -f "$newfile" ]]; then
    log_error "rendered config is missing"
    return 1
  fi
  if ! "$validate_fn" "$newfile"; then
    log_error "validation failed; current configuration was not changed"
    return 1
  fi
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  stamp="$(date +%Y%m%dT%H%M%S)"
  if [[ -f "$dest" ]]; then
    backup="${dest}.bak.${stamp}"
    cp -a "$dest" "$backup"
    # shellcheck disable=SC2034
    PROXSTACK_LAST_BACKUP="$backup"
    log_info "backed up current file to ${backup}"
  fi
  cp "$newfile" "$dest"
  chmod "$mode" "$dest" 2>/dev/null || true
  if ! "$restart_fn"; then
    log_error "restart failed"
    if rollback_config "$dest" "$backup" "$restart_fn"; then
      log_warn "rollback succeeded"
    else
      log_error "rollback failed"
    fi
    return 1
  fi
  if ! "$health_fn"; then
    log_error "health check failed"
    if rollback_config "$dest" "$backup" "$restart_fn"; then
      log_warn "rollback succeeded"
    else
      log_error "rollback failed"
    fi
    return 1
  fi
  return 0
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_quiet() {
  "$@" >/dev/null 2>&1
}

append_unique_line() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -Fxq "$line" "$file" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$line" >>"$file"
}

bundle_file_list() {
  cat <<'EOF'
proxystack.sh
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
}
