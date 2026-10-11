#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../helpers/test_helper.bash"
  proxystack_test_init
}

@test "dante config uses the detected interface, username auth, and udp" {
  run render_dante_config ens3 51080
  [ "$status" -eq 0 ]
  [[ "$output" == *"internal: ens3 port = 51080"* ]]
  [[ "$output" == *"external: ens3"* ]]
  [[ "$output" == *"socksmethod: username"* ]]
  [[ "$output" == *"udpassociate"* ]]
  [[ "$output" != *"eth0"* ]]
  run render_dante_config 'ens3; rm -rf /' 51080
  [ "$status" -ne 0 ]
}

@test "squid config is a minimal authenticated CONNECT proxy" {
  run render_squid_config 51081 /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
  [ "$status" -eq 0 ]
  [[ "$output" == *"http_port 51081"* ]]
  [[ "$output" == *"auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords"* ]]
  [[ "$output" == *"acl CONNECT method CONNECT"* ]]
  [[ "$output" == *"http_access allow CONNECT SSL_ports authenticated"* ]]
  [[ "$output" == *"http_access deny all"* ]]
}

@test "caddyfile preserves the webhook path and sets the upstream host" {
  run render_caddyfile webhook.example.com http://203.0.113.50:8080 /webhook/ /var/log/caddy/access.log
  [ "$status" -eq 0 ]
  [[ "$output" == *"@webhook path /webhook/ /webhook/*"* ]]
  [[ "$output" == *"reverse_proxy http://203.0.113.50:8080"* ]]
  [[ "$output" == *"header_up Host {upstream_hostport}"* ]]
  [[ "$output" == *"output file /var/log/caddy/access.log"* ]]
  [[ "$output" != *"strip_prefix"* ]]
  run render_caddyfile 'bad domain' http://203.0.113.50:8080 /webhook/
  [ "$status" -ne 0 ]
}

@test "webhook path is normalized" {
  [ "$(normalize_webhook_path webhook)" = "/webhook/" ]
  [ "$(normalize_webhook_path /webhook/)" = "/webhook/" ]
}
