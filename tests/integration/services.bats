#!/usr/bin/env bats
# Package-level checks. They skip unless the tools exist, so local Windows runs stay green.
# GitHub Actions installs Dante, Squid, and Caddy and executes the probes.

setup() {
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../helpers/test_helper.bash"
  proxystack_test_init
}

@test "danted accepts a rendered config" {
  if ! command -v danted >/dev/null 2>&1; then
    skip "danted is not installed"
  fi
  local cfg="$BATS_TEST_TMPDIR/danted.conf" iface
  iface="$(ip route show default | awk '/default/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
  [ -n "$iface" ]
  render_dante_config "$iface" 51080 >"$cfg"
  timeout --signal=KILL 20 danted -V -f "$cfg"
}

@test "squid parses a rendered config" {
  if ! command -v squid >/dev/null 2>&1 || ! command -v htpasswd >/dev/null 2>&1; then
    skip "squid or htpasswd is not installed"
  fi
  local helper cfg="$BATS_TEST_TMPDIR/squid.conf" pass="$BATS_TEST_TMPDIR/passwords"
  helper="$(detect_squid_auth_helper)"
  printf '%s\n' 'TestPassw0rd' | htpasswd -i -B -c "$pass" testuser
  render_squid_config 51081 "$helper" "$pass" >"$cfg"
  timeout --signal=KILL 30 squid -k parse -f "$cfg"
}

@test "caddy validates a rendered Caddyfile" {
  if ! command -v caddy >/dev/null 2>&1; then
    skip "caddy is not installed"
  fi
  local cfg="$BATS_TEST_TMPDIR/Caddyfile"
  render_caddyfile webhook.example.com http://203.0.113.50:8080 /webhook/ /tmp/proxystack-caddy-access.log >"$cfg"
  timeout --signal=KILL 30 caddy validate --config "$cfg" --adapter caddyfile
}

@test "dante serves a real SOCKS5 request" {
  if [[ "$(id -u)" -ne 0 ]] || ! command -v danted >/dev/null 2>&1; then
    skip "root and danted are required"
  fi
  local iface cfg pid port=15180
  iface="$(ip route show default | awk '/default/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
  id testuser >/dev/null 2>&1 || useradd --shell /usr/sbin/nologin --no-create-home testuser
  printf '%s\n' 'testuser:TestPassw0rd' | chpasswd
  cfg="$BATS_TEST_TMPDIR/danted.live.conf"
  render_dante_config "$iface" "$port" >"$cfg"
  if [[ ! -f /etc/pam.d/sockd ]]; then
    printf '%s\n' 'auth required pam_unix.so' 'account required pam_unix.so' >/etc/pam.d/sockd
  fi
  # -N stays in the foreground. -D detaches, which hid the failure last time.
  danted -f "$cfg" -N >"$BATS_TEST_TMPDIR/danted.out" 2>&1 &
  pid=$!
  sleep 1
  run curl -sS --max-time 25 --socks5-hostname "127.0.0.1:${port}" --proxy-user 'testuser:TestPassw0rd' https://example.com
  kill -9 "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output" >&2
    cat "$BATS_TEST_TMPDIR/danted.out" >&2 || true
  fi
  [ "$status" -eq 0 ]
  [[ "$output" == *"Example Domain"* ]]
}

@test "squid serves a real CONNECT tunnel" {
  if [[ "$(id -u)" -ne 0 ]] || ! command -v squid >/dev/null 2>&1; then
    skip "root and squid are required"
  fi
  local helper cfg pass port=15181 work
  helper="$(detect_squid_auth_helper)"
  # Squid drops to the proxy user. The Bats temp dir is mode 0700, so logs and
  # the NCSA file must live somewhere that user can traverse.
  work="$(mktemp -d /tmp/proxystack-squid.XXXXXX)"
  chown proxy:proxy "$work"
  chmod 755 "$work"
  pass="${work}/passwords"
  cfg="${work}/squid.conf"
  printf '%s\n' 'TestPassw0rd' | htpasswd -i -B -c "$pass" httpproxy
  chown root:proxy "$pass"
  chmod 640 "$pass"
  render_squid_config "$port" "$helper" "$pass" >"$cfg"
  printf 'pid_filename %s\naccess_log stdio:%s\ncache_log %s\n' \
    "${work}/squid.pid" "${work}/access.log" "${work}/cache.log" >>"$cfg"
  touch "${work}/access.log" "${work}/cache.log"
  chown proxy:proxy "${work}/access.log" "${work}/cache.log"
  squid -f "$cfg" -N -d 1 >"$BATS_TEST_TMPDIR/squid.out" 2>&1 &
  local pid=$!
  sleep 2
  local trace="$BATS_TEST_TMPDIR/curl.trace"
  run curl -sS --max-time 20 --proxy "http://127.0.0.1:${port}" --proxy-user 'httpproxy:TestPassw0rd' \
    --trace-ascii "$trace" -o /dev/null -w '%{http_code}' https://example.com
  kill -9 "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output" >&2
    cat "$BATS_TEST_TMPDIR/squid.out" >&2 || true
  fi
  rm -rf "$work"
  [ "$status" -eq 0 ]
  grep -q "Connection established" "$trace"
}

@test "caddy proxies a webhook to a local mock and preserves the path" {
  if ! command -v caddy >/dev/null 2>&1; then
    skip "caddy is not installed"
  fi
  local hit="$BATS_TEST_TMPDIR/webhook-hit.txt"
  cat >"$BATS_TEST_TMPDIR/mock.py" <<PY
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        open("${hit}", "w").write(self.path + "\\n" + self.headers.get("Host", "") + "\\n" + body.decode())
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
    def log_message(self, fmt, *args):
        return
ThreadingHTTPServer(("127.0.0.1", 18081), H).serve_forever()
PY
  python3 "$BATS_TEST_TMPDIR/mock.py" >"$BATS_TEST_TMPDIR/mock.out" 2>&1 &
  local http_pid=$!
  cat >"$BATS_TEST_TMPDIR/Caddyfile" <<'EOF'
:18082 {
	handle /webhook/* {
		reverse_proxy 127.0.0.1:18081 {
			header_up Host {upstream_hostport}
		}
	}
}
EOF
  caddy start --config "$BATS_TEST_TMPDIR/Caddyfile" --adapter caddyfile
  sleep 1
  run curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
    --data '{"update_id":1}' "http://127.0.0.1:18082/webhook/test"
  caddy stop >/dev/null 2>&1 || true
  kill -9 "$http_pid" >/dev/null 2>&1 || true
  wait "$http_pid" >/dev/null 2>&1 || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
  grep -q '/webhook/test' "$hit"
}
