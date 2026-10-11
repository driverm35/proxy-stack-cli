# shellcheck shell=bash

if [[ -n "${PROXSTACK_SYSTEM_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_SYSTEM_LOADED=1

os_field() {
  local key="$1"
  [[ -r /etc/os-release ]] || return 1
  awk -F= -v k="$key" '$1==k {gsub(/"/,"",$2); print $2; exit}' /etc/os-release
}

os_id() { os_field ID; }
os_version() { os_field VERSION_ID; }
os_pretty() { os_field PRETTY_NAME; }

arch_name() { uname -m; }

os_supported() {
  local id
  id="$(os_id 2>/dev/null || true)"
  [[ "$id" == "ubuntu" || "$id" == "debian" ]]
}

mem_total_mb() {
  [[ -r /proc/meminfo ]] || return 1
  awk '/MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo
}

disk_free_mb() {
  local path="${1:-/}"
  df -Pm "$path" 2>/dev/null | awk 'NR==2 {print $4}'
}

parse_route_dev() {
  local line="$1"
  if [[ "$line" =~ [[:space:]]dev[[:space:]]+([^[:space:]]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

parse_route_metric() {
  local line="$1"
  if [[ "$line" =~ [[:space:]]metric[[:space:]]+([0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '0'
}

select_default_interface() {
  local text="$1" line dev metric best_dev="" best_metric=0 have=0
  while IFS= read -r line; do
    [[ "$line" == default\ * ]] || continue
    dev="$(parse_route_dev "$line")" || continue
    valid_iface "$dev" || continue
    metric="$(parse_route_metric "$line")"
    if [[ "$have" -eq 0 || "$metric" -lt "$best_metric" ]]; then
      best_dev="$dev"
      best_metric="$metric"
      have=1
    fi
  done <<<"$text"
  [[ "$have" -eq 1 ]] || return 1
  printf '%s' "$best_dev"
}

detect_default_interface() {
  local text
  [[ "${PROXSTACK_SKIP_DETECT:-0}" == "1" ]] && return 1
  have_cmd ip || return 1
  text="$(ip route show default 2>/dev/null || true)"
  select_default_interface "$text"
}

detect_iface_ipv4() {
  local iface="$1" ip
  have_cmd ip || return 1
  ip="$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | head -n1 | cut -d/ -f1)"
  valid_ipv4 "$ip" || return 1
  printf '%s' "$ip"
}

detect_public_ipv4() {
  local url ip
  [[ "${PROXSTACK_SKIP_DETECT:-0}" == "1" ]] && return 1
  have_cmd curl || return 1
  for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    ip="$(curl -4 -fsS --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    if is_public_ipv4 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
}

detect_ssh_port() {
  local port="" extra
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    # shellcheck disable=SC2086
    set -- ${SSH_CONNECTION}
    if valid_port "${4:-}"; then
      printf '%s' "$4"
      return 0
    fi
  fi
  if [[ -r /etc/ssh/sshd_config ]]; then
    port="$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2; exit}' /etc/ssh/sshd_config)"
  fi
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    extra="$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {p=$2} END{if (p != "") print p}' /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true)"
    [[ -n "${extra:-}" ]] && port="$extra"
  fi
  [[ -n "$port" ]] || port=22
  printf '%s' "$port"
}

port_is_listening() {
  local port="$1"
  valid_port "$port" || return 1
  if have_cmd ss; then
    ss -lntuH 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[:.])${port}$"
    return
  fi
  if have_cmd netstat; then
    netstat -lntu 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[:.])${port}$"
    return
  fi
  return 2
}

wait_for_port() {
  local port="$1"
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if port_is_listening "$port"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

resolve_host_ips() {
  local host="$1"
  if have_cmd getent; then
    getent ahosts "$host" 2>/dev/null | awk '{print $1}' | awk '!seen[$0]++'
    return
  fi
  if have_cmd python3; then
    python3 -c 'import socket,sys
host=sys.argv[1]
seen=set()
for item in socket.getaddrinfo(host, None):
    ip=item[4][0]
    if ip not in seen:
        seen.add(ip)
        print(ip)
' "$host"
    return
  fi
  return 1
}

tcp_probe() {
  local host="$1" port="$2" timeout_s="${3:-5}" err rc
  valid_port "$port" || {
    printf 'refused'
    return 1
  }
  err="$(mktemp)"
  if have_cmd curl; then
    if curl -4 -sS --connect-timeout "$timeout_s" --max-time "$timeout_s" -o /dev/null "telnet://${host}:${port}" 2>"$err"; then
      rm -f "$err"
      printf 'ok'
      return 0
    fi
    rc=$?
    if grep -Eqi 'timed out|timeout|Operation timed out' "$err"; then
      rm -f "$err"
      printf 'timeout'
      return 1
    fi
    if grep -Eqi 'refused|failed to connect|Could not connect' "$err"; then
      rm -f "$err"
      printf 'refused'
      return 1
    fi
  fi
  rm -f "$err"
  if have_cmd timeout; then
    if timeout "$timeout_s" bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
      printf 'ok'
      return 0
    fi
    rc=$?
    if [[ "${rc:-1}" -eq 124 ]]; then
      printf 'timeout'
      return 1
    fi
  fi
  printf 'timeout'
  return 1
}

apt_install() {
  require_root
  have_cmd apt-get || die "apt-get is required"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "$@"
}

remember_new_package() {
  local pkg="$1"
  proxystack_paths_init
  if have_cmd dpkg && dpkg -s "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  apt_install "$pkg"
  mkdir -p "$PROXSTACK_VAR"
  append_unique_line "$PROXSTACK_VAR/installed.packages" "$pkg"
}

svc() {
  if [[ -n "${PROXSTACK_SYSTEMCTL:-}" ]]; then
    "$PROXSTACK_SYSTEMCTL" "$@"
    return
  fi
  systemctl "$@"
}

svc_enable_restart() {
  local unit="$1"
  svc enable "$unit"
  svc restart "$unit"
}

svc_active() {
  local unit="$1"
  if [[ -z "${PROXSTACK_SYSTEMCTL:-}" ]] && ! have_cmd systemctl; then
    return 1
  fi
  svc is-active --quiet "$unit"
}

require_supported_os() {
  if os_supported; then
    return 0
  fi
  if [[ "${PROXSTACK_FORCE:-0}" == "1" ]]; then
    log_warn "$(msg os_unsupported)"
    return 0
  fi
  die "$(msg os_unsupported)"
}

ensure_login_user() {
  local user="$1" pass="$2"
  valid_username "$user" || return 1
  valid_password "$pass" || return 1
  if ! id "$user" >/dev/null 2>&1; then
    useradd --shell /usr/sbin/nologin --no-create-home "$user"
  fi
  printf '%s:%s\n' "$user" "$pass" | chpasswd
}

write_secrets_line() {
  local key="$1" value="$2" tmp line k
  proxystack_paths_init
  umask 077
  mkdir -p "$PROXSTACK_ETC"
  touch "$PROXSTACK_SECRETS_FILE"
  tmp="$(mktemp)"
  if [[ -f "$PROXSTACK_SECRETS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      k="${line%%=*}"
      [[ "$k" == "$key" ]] && continue
      printf '%s\n' "$line" >>"$tmp"
    done <"$PROXSTACK_SECRETS_FILE"
  fi
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv "$tmp" "$PROXSTACK_SECRETS_FILE"
  chmod 600 "$PROXSTACK_SECRETS_FILE"
  if is_root; then
    chown root:root "$PROXSTACK_SECRETS_FILE" 2>/dev/null || true
  fi
}

read_secret_key() {
  local key="$1" line k v
  proxystack_paths_init
  [[ -f "$PROXSTACK_SECRETS_FILE" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    k="${line%%=*}"
    v="${line#*=}"
    if [[ "$k" == "$key" ]]; then
      printf '%s' "$v"
      return 0
    fi
  done <"$PROXSTACK_SECRETS_FILE"
  return 1
}
