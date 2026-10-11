# shellcheck shell=bash

i18n_en() {
  case "$1" in
    lang_saved) printf '%s' "Language saved" ;;
    menu_title) printf '%s' "Proxy Stack" ;;
    menu_install) printf '%s' "Install" ;;
    menu_status) printf '%s' "Status" ;;
    menu_configure) printf '%s' "Configure" ;;
    menu_tests) printf '%s' "Tests" ;;
    menu_doctor) printf '%s' "Doctor" ;;
    menu_credentials) printf '%s' "Credentials" ;;
    menu_firewall) printf '%s' "Firewall" ;;
    menu_webhook) printf '%s' "Telegram Webhook" ;;
    menu_logs) printf '%s' "Logs" ;;
    menu_backup) printf '%s' "Backup/Restore" ;;
    menu_migration) printf '%s' "Migration" ;;
    menu_update) printf '%s' "Update" ;;
    menu_uninstall) printf '%s' "Uninstall" ;;
    menu_about) printf '%s' "About/Version" ;;
    menu_exit) printf '%s' "Exit" ;;
    menu_select) printf '%s' "Select" ;;
    invalid_choice) printf '%s' "Unknown choice" ;;
    press_enter) printf '%s' "Press Enter to continue" ;;
    cancelled) printf '%s' "Cancelled" ;;
    root_required) printf '%s' "root privileges are required; re-run with sudo" ;;
    yes) printf '%s' "yes" ;;
    no) printf '%s' "no" ;;
    ask_components) printf '%s' "Component: 1 Dante  2 Squid  3 Caddy  4 All" ;;
    ask_dante_user) printf '%s' "Dante username" ;;
    ask_dante_port) printf '%s' "Dante port" ;;
    ask_squid_user) printf '%s' "Squid username" ;;
    ask_squid_port) printf '%s' "Squid port" ;;
    ask_generate) printf '%s' "Generate a strong password? 1 yes, 2 type my own" ;;
    ask_domain) printf '%s' "Public webhook domain" ;;
    ask_upstream) printf '%s' "Upstream URL (scheme://host:port)" ;;
    ask_path) printf '%s' "Webhook path" ;;
    ask_email) printf '%s' "ACME email (optional)" ;;
    ask_save_secrets) printf '%s' "Save passwords in a root-only file for doctor/rotate?" ;;
    password_once) printf '%s' "Save this password now. It is shown once and is not written to the log." ;;
    password_mismatch) printf '%s' "Passwords did not match" ;;
    pass_invalid) printf '%s' "Password must be 8-128 chars and must not contain spaces or ':'" ;;
    user_invalid) printf '%s' "Invalid username" ;;
    port_invalid) printf '%s' "Invalid port" ;;
    domain_invalid) printf '%s' "Invalid domain" ;;
    upstream_invalid) printf '%s' "Invalid upstream URL" ;;
    os_unsupported) printf '%s' "This installer supports Ubuntu and Debian. Use --force to continue anyway." ;;
    iface_missing) printf '%s' "Could not detect the external interface from the default route." ;;
    validate_fail) printf '%s' "Validation failed; the previous configuration was kept" ;;
    health_fail) printf '%s' "Health check failed" ;;
    rollback_ok) printf '%s' "Rollback succeeded" ;;
    rollback_fail) printf '%s' "Rollback failed" ;;
    fw_profile) printf '%s' "Security profile: 1 Recommended (source IP/CIDR)  2 VPN/LAN only  3 Public authenticated" ;;
    fw_cidr) printf '%s' "Allowed source IP or CIDR" ;;
    fw_more_cidr) printf '%s' "Add another CIDR? Empty line to stop" ;;
    fw_public_warn) printf '%s' "WARNING: authentication is not a firewall. Profile 3 exposes proxy ports to the Internet." ;;
    fw_type_public) printf '%s' "Type PUBLIC to confirm" ;;
    fw_plan) printf '%s' "Firewall plan (SSH is preserved; existing rules are not flushed)" ;;
    fw_confirm) printf '%s' "Apply this firewall plan?" ;;
    fw_skip) printf '%s' "An existing nftables or iptables policy was detected. proxystack will not change it." ;;
    fw_applied) printf '%s' "Firewall profile applied" ;;
    fw_need_force) printf '%s' "Refusing to change the firewall without --force in non-interactive mode" ;;
    tg_token) printf '%s' "Telegram bot token (input hidden, not stored unless you agree)" ;;
    tg_save) printf '%s' "Store the bot token in a root-only file?" ;;
    tg_url) printf '%s' "Webhook URL" ;;
    tg_via) printf '%s' "API path: 1 direct  2 local Squid  3 HTTP proxy" ;;
    tg_set_ok) printf '%s' "Webhook updated" ;;
    tg_deleted) printf '%s' "Webhook deleted" ;;
    tg_missing) printf '%s' "No bot token available" ;;
    wh_404) printf '%s' "Telegram 404 usually means the webhook path does not match the application, or Caddy is not routing /webhook/." ;;
    wh_502) printf '%s' "Telegram 502 usually means the upstream behind Caddy failed. Run proxystack doctor." ;;
    wh_timeout) printf '%s' "Telegram timeout usually means packets never reached the webhook or the upstream did not answer." ;;
    bk_secrets_warn) printf '%s' "WARNING: this archive will contain secrets. It will be encrypted. Keep the passphrase offline." ;;
    bk_passphrase) printf '%s' "Encryption passphrase" ;;
    bk_created) printf '%s' "Backup written" ;;
    bk_restored) printf '%s' "Restore finished" ;;
    bk_dns) printf '%s' "Update DNS so the webhook domain points at this server's current public IPv4, then run proxystack doctor." ;;
    up_current) printf '%s' "Current version" ;;
    up_latest) printf '%s' "Latest version" ;;
    up_notes) printf '%s' "Release notes" ;;
    up_same) printf '%s' "Already up to date" ;;
    up_checksum_ok) printf '%s' "Checksum verified" ;;
    up_checksum_fail) printf '%s' "Checksum verification failed; the update was not installed" ;;
    up_daemons) printf '%s' "CLI files were updated. Dante, Squid, and Caddy were not restarted and their configs were not changed." ;;
    up_done) printf '%s' "CLI update complete" ;;
    up_download_fail) printf '%s' "Could not download a verified update" ;;
    doc_passed) printf '%s' "Passed" ;;
    doc_warnings) printf '%s' "Warnings" ;;
    doc_failed) printf '%s' "Failed" ;;
    doc_recs) printf '%s' "Recommendations" ;;
    password_label_dante) printf '%s' "Dante password (shown once)" ;;
    password_label_squid) printf '%s' "Squid password (shown once)" ;;
    noninteractive_missing) printf '%s' "A required value is missing. Pass it as a flag in non-interactive mode." ;;
    unknown_command) printf '%s' "Unknown command. Run: proxystack help" ;;
    confirm_password) printf '%s' "Repeat password" ;;
    ask_custom_password) printf '%s' "Password" ;;
    *) printf '%s' "$1" ;;
  esac
}

i18n_en_block() {
  case "$1" in
    help)
      cat <<'EOF'
proxystack — Dante SOCKS5, Squid HTTP CONNECT, Caddy, and Telegram webhooks

Usage:
  proxystack [global flags] <command> [target] [flags]

Global flags:
  --non-interactive   Do not prompt
  --force             Apply privileged changes without a second confirmation
  --json              Machine-readable output where supported
  --verbose           Redacted debug log
  --quiet             Hide informational logs
  --lang en|ru        Select language
  --prefix PATH       Relocatable install root (advanced)
  -h, --help          Show help

Commands:
  (no args)                 Interactive menu
  install [all|dante|squid|caddy]
  install-script            Install only the CLI
  uninstall-script          Remove only the CLI
  configure                 Reconfigure an installed component
  status                    Service and port summary
  doctor                    Sequential health report
  test [all|dante|squid|caddy|webhook|upstream]
  logs [dante|squid|caddy]
  restart [dante|squid|caddy]
  credentials [rotate]
  firewall [status]
  webhook set|info|delete|test
  backup | restore | export | import
  update | update-script    Update the CLI only
  uninstall [all|dante|squid|caddy]
  language [en|ru]
  version

Automation example:
  sudo proxystack install all --non-interactive --force \
    --dante-user socksuser --dante-password 'generated-or-yours' \
    --squid-user httpproxy --squid-password 'generated-or-yours' \
    --domain webhook.example.com --upstream http://203.0.113.50:8080 \
    --firewall-profile recommended --allow-cidr 203.0.113.10/32 --lang en
EOF
      ;;
    about)
      cat <<'EOF'
proxystack manages Dante, Squid, and Caddy on Ubuntu/Debian.
Authentication on a proxy is not a substitute for a firewall.
Passwords and bot tokens are never written to the diagnostic log.
License: MIT
EOF
      ;;
    migration)
      cat <<'EOF'
Migration
  1. On the old server: sudo proxystack export --output /root/proxystack-migrate.tar.gz
  2. Copy the archive to the new server.
  3. On the new server, install only the CLI, then import:
       sudo proxystack install-script
       sudo proxystack import --file /root/proxystack-migrate.tar.gz
  4. The import detects the new interface and public IPv4, rewrites Dante, and asks Caddy to obtain a new certificate.
  5. Point DNS at the new IPv4, then run: sudo proxystack doctor
EOF
      ;;
    diag_not_caddy)
      cat <<'EOF'
DNS works, a route exists, and the TCP connection to the upstream times out (timeout).
The problem is NOT Caddy. Likely cause: source-IP filtering, firewall, security group, or the upstream network.
EOF
      ;;
    *)
      return 1
      ;;
  esac
}
