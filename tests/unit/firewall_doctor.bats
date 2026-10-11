#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../helpers/test_helper.bash"
  proxystack_test_init
}

@test "firewall plan keeps SSH and does not flush existing policy" {
  run render_firewall_plan recommended 22 51080 51081 203.0.113.10/32 ufw
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw allow 22/tcp comment proxystack-ssh"* ]]
  [[ "$output" == *"ufw allow from 203.0.113.10/32 to any port 51080 proto tcp comment proxystack-dante"* ]]
  [[ "$output" == *"ufw allow from 203.0.113.10/32 to any port 51080 proto udp comment proxystack-dante-udp"* ]]
  [[ "$output" == *"ufw allow 80/tcp comment proxystack-http"* ]]
  [[ "$output" != *"ufw reset"* ]]
  [[ "$output" != *"iptables -F"* ]]
  [[ "$output" != *"nft flush"* ]]
}

@test "vpn profile defaults to private ranges" {
  run render_firewall_plan vpn 2222 51080 51081 "" ufw
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw allow 2222/tcp comment proxystack-ssh"* ]]
  [[ "$output" == *"10.0.0.0/8"* ]]
  [[ "$output" == *"192.168.0.0/16"* ]]
}

@test "existing nftables backend is not modified" {
  run render_firewall_plan recommended 22 51080 51081 203.0.113.10/32 nftables
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSE"* ]]
  [[ "$output" != *"ufw allow"* ]]
}

@test "public profile warns and opens proxy ports" {
  run render_firewall_plan public 22 51080 51081 "" ufw
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"ufw allow 51080/tcp comment proxystack-dante"* ]]
  [[ "$output" == *"ufw allow 22/tcp comment proxystack-ssh"* ]]
}

@test "502 with an upstream timeout is not blamed on Caddy" {
  run doctor_upstream_diagnosis ok ok timeout 502 ens3 203.0.113.50 8080
  [ "$status" -eq 0 ]
  [[ "$output" == *"DNS works"* ]]
  [[ "$output" == *"route exists"* ]]
  [[ "$output" == *"timeout"* ]]
  [[ "$output" == *"NOT Caddy"* ]]
  [[ "$output" == *"source-IP filtering"* ]]
  [[ "$output" == *"tcpdump -ni ens3 host 203.0.113.50 and tcp port 8080"* ]]
}

@test "telegram webhook errors explain 404, 502, and timeout" {
  run telegram_explain_error "Wrong response from the webhook: 404 Not Found"
  [ "$status" -eq 0 ]
  [[ "$output" == *"404"* ]]
  run telegram_explain_error "Wrong response from the webhook: 502 Bad Gateway"
  [ "$status" -eq 0 ]
  [[ "$output" == *"502"* ]]
  run telegram_explain_error "Connection timed out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"timeout"* ]]
}

@test "getWebhookInfo fields are printed" {
  local json='{"ok":true,"result":{"url":"https://webhook.example.com/webhook/","ip_address":"203.0.113.10","pending_update_count":2,"last_error_date":0,"last_error_message":"","max_connections":40}}'
  run telegram_format_info "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"url: https://webhook.example.com/webhook/"* ]]
  [[ "$output" == *"ip_address: 203.0.113.10"* ]]
  [[ "$output" == *"pending_update_count: 2"* ]]
  [[ "$output" == *"max_connections: 40"* ]]
}
