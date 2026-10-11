# proxystack

[![CI](https://github.com/driverm35/proxy-stack-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/driverm35/proxy-stack-cli/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/driverm35/proxy-stack-cli)](https://github.com/driverm35/proxy-stack-cli/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420)](https://ubuntu.com/)
[![Debian](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33)](https://www.debian.org/)

**[Русский](README_RU.md)**

`proxystack` is an interactive CLI for Ubuntu and Debian. It installs and operates three services that are often used together:

- **Dante** as a SOCKS5 proxy (TCP and UDP, username authentication)
- **Squid** as an HTTP CONNECT proxy (Basic auth)
- **Caddy** as an HTTPS reverse proxy in front of a webhook upstream
- **Telegram** webhook setup, inspection, and a short explanation when Telegram reports 404, 502, or a timeout

Proxy authentication is not a firewall. The recommended profile opens the proxy ports only to the source addresses you list, and it leaves SSH reachable.

```text
clients --SOCKS5--> Dante :51080 --+
clients --CONNECT--> Squid :51081 --+--> Internet / Telegram API
                                    |
Telegram --> :443 Caddy /webhook/* -+--> your upstream
```

## Quick start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/driverm35/proxy-stack-cli/main/proxystack.sh) install-script
sudo proxystack
```

The first run asks for a language (1 Russian, 2 English) and stores it in `/etc/proxystack/config.env`. `proxystack` with no arguments opens the menu.

If GitHub is hard to reach, use the jsDelivr copy of the same file:

```bash
bash <(curl -Ls https://cdn.jsdelivr.net/gh/driverm35/proxy-stack-cli@main/proxystack.sh) install-script
```

## Installation

`install-script` copies only the CLI. It does not install Dante, Squid, or Caddy.

```bash
curl -fsSL https://raw.githubusercontent.com/driverm35/proxy-stack-cli/main/proxystack.sh | sudo bash -s -- install-script
```

Process substitution (`bash <(curl ...)`) keeps stdin free for later prompts. The pipe form is better with flags.

Install a component when you are ready:

```bash
sudo proxystack install dante
sudo proxystack install squid
sudo proxystack install caddy
sudo proxystack install all
```

Non-interactive example with documentation addresses from TEST-NET and `example.com`:

```bash
sudo proxystack install all --non-interactive --force --lang en \
  --dante-user socksuser --dante-password 'ExamplePassw0rd' \
  --squid-user httpproxy --squid-password 'ExamplePassw0rd' \
  --domain webhook.example.com \
  --upstream http://203.0.113.50:8080 \
  --webhook-path /webhook/ \
  --firewall-profile recommended \
  --allow-cidr 203.0.113.10/32
```

Passwords may also be supplied as `PROXSTACK_DANTE_PASSWORD` and `PROXSTACK_SQUID_PASSWORD`. A missing password is generated, printed once, and not written to the log. Nothing in this repository uses a fixed server address.

## Interactive menu

```text
Proxy Stack 0.1.0
  1) Install
  2) Status
  3) Configure
  4) Tests
  5) Doctor
  6) Credentials
  7) Firewall
  8) Telegram Webhook
  9) Logs
  10) Backup/Restore
  11) Migration
  12) Update
  13) Uninstall
  14) About/Version
  0) Exit
```

Colors are used on a terminal and omitted when stdout is not a TTY.

## Commands

| Command | Purpose |
| --- | --- |
| `proxystack` | Open the menu |
| `install [all\|dante\|squid\|caddy]` | Install one component or all of them |
| `install-script` / `uninstall-script` | Install or remove only the CLI |
| `configure` | Re-render a config through validate, backup, and rollback |
| `status` | Services, ports, user names, domain |
| `doctor` | Ordered health report |
| `test [all\|dante\|squid\|caddy\|webhook\|upstream]` | Live probes |
| `logs [dante\|squid\|caddy]` | Recent journal entries |
| `restart [dante\|squid\|caddy]` | Restart a service |
| `credentials [rotate]` | Show usernames; rotate passwords |
| `firewall [status]` | Show or apply an access profile |
| `webhook set\|info\|delete\|test` | Telegram webhook API |
| `backup` / `restore` / `export` / `import` | Archives and migration |
| `update` / `update-script` | Update the CLI only |
| `uninstall [all\|dante\|squid\|caddy]` | Remove components this CLI installed |
| `language [en\|ru]` | Switch language |
| `version` / `help` | Version and usage |

Global flags: `--non-interactive`, `--force`, `--json`, `--verbose`, `--quiet`, `--lang`, `--prefix`.

Repeating an install is safe. Before a config is replaced, proxystack writes a timestamped copy, validates the new file, restarts, and runs a health check. A failed check restores the previous file and restarts the service again.

## Dante SOCKS5

Default port `51080`, method `username`, TCP plus UDP (`udpassociate`). The external interface comes from the default route. `eth0` is never assumed. The config is checked with `danted -V` before `danted` is restarted, and a SOCKS request is used as the health check.

```bash
curl -sS --socks5-hostname 'socksuser:ExamplePassw0rd@203.0.113.10:51080' https://ifconfig.me/ip
```

## Squid HTTP CONNECT

Default port `51081`. The package set is `squid` and `apache2-utils`. Passwords are stored as hashes in `/etc/squid/passwords`. `squid -k parse` runs before the new file is installed.

```bash
curl -sS -x 'http://httpproxy:ExamplePassw0rd@203.0.113.10:51081' https://ifconfig.me/ip
```

A successful tunnel reports `HTTP/1.1 200 Connection established`. The doctor can also try the Telegram API through Squid when a password is available.

## Caddy

The stable Caddy build is installed from the official repository. You provide the public webhook domain and the upstream URL. The Caddyfile matches `/webhook/` and `/webhook/*`, reverse-proxies to the upstream, keeps the original path, and sets `Host` to the upstream host. Let's Encrypt uses ports 80 and 443. The log directory `/var/log/caddy` is created as `caddy:caddy` so Caddy does not fail with `permission denied`. `caddy validate` runs before reload.

```bash
curl -sS -D - -o /dev/null -X POST \
  -H 'Content-Type: application/json' \
  --data '{"update_id":1,"message":{"message_id":1,"text":"proxystack-test"}}' \
  https://webhook.example.com/webhook/
```

## Telegram webhook

The bot token is read from a hidden prompt, `PROXSTACK_TELEGRAM_TOKEN`, or `--bot-token`. It is not stored unless you pass `--save-token` or confirm the prompt. The optional file is `/etc/proxystack/secrets.env`, mode `600`, owner root.

```bash
sudo proxystack webhook set --url https://webhook.example.com/webhook/ --via direct
sudo proxystack webhook info
sudo proxystack webhook test --url https://webhook.example.com/webhook/
sudo proxystack webhook delete
```

`webhook info` prints URL, IP, `pending_update_count`, `last_error_date`, `last_error_message`, and `max_connections`. API calls can go direct, through the local Squid proxy, or through `--http-proxy`.

| Telegram error | Likely meaning |
| --- | --- |
| 404 | The path does not match the app, or Caddy is not routing `/webhook/` |
| 502 | The upstream behind Caddy failed; run `proxystack doctor` |
| timeout | Packets did not arrive, or the upstream never answered |

## Security

- Generated passwords use a 24-character alphabet without spaces or `:`.
- Logs and `--verbose` output pass through redaction (`password` → `***`, bot token → `REDACTED_TOKEN`, `Proxy-Authorization` → `REDACTED`).
- The CLI does not run `curl -v` against a URL that contains a secret.
- Config backups are timestamped. Secret archives require `--with-secrets` and a passphrase (`openssl enc -aes-256-cbc -pbkdf2`).

## Firewall

| Profile | Behavior |
| --- | --- |
| 1 Recommended | Proxy ports accept only the CIDRs you enter. 80/443 may be public. |
| 2 VPN/LAN | Same idea, defaulting to `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`. |
| 3 Public | Proxy ports are open to the Internet. You must type `PUBLIC` or pass `--allow-public`. |

The SSH port is taken from `SSH_CONNECTION` when present, otherwise from `sshd_config`, otherwise 22. The plan is printed before it is applied. UFW is never reset. If nftables or iptables already has rules, proxystack prints the plan and does not change that policy. A failed apply deletes only the rules added in that attempt. Non-interactive apply requires `--force`.

```bash
sudo proxystack firewall status
sudo proxystack firewall --firewall-profile recommended --allow-cidr 203.0.113.10/32 --force
```

## Doctor

`sudo proxystack doctor` walks the checks in order and prints `[ OK ]`, `[ WARN ]`, or `[ FAIL ]`. The summary lists Passed, Warnings, Failed, and concrete recommendations.

Checks cover the OS, root, architecture, RAM and disk, default route, external interface, public IPv4, DNS, the webhook domain, the route and TCP path to the upstream, outbound 80/443, Dante, Squid, Caddy (including certificate expiry and a webhook POST), the host firewall, and `getWebhookInfo` when a token is available.

Special case: Caddy returns **502** and a direct connection to the upstream **times out**. Doctor then states that DNS works, a route exists, TCP timed out, and the problem is **NOT Caddy**. The usual cause is source-IP filtering, a firewall, a security group, or the upstream network. It prints a tcpdump command you can run on the upstream host:

```bash
sudo tcpdump -ni ens3 host 203.0.113.50 and tcp port 8080
```

Use the interface, address, and port from the report. Seeing no SYN on the upstream means the packet was dropped before it arrived.

`--json` prints the same checks as one object.

## Tests

On a development machine:

```bash
make check
```

That is ShellCheck, `shfmt -d`, and the Bats unit tests (parser, language, validation, redaction, interface selection, config rendering, firewall plans, the 502 diagnosis, backup names, checksums). Integration tests install packages only in GitHub Actions on Ubuntu 22.04 and 24.04. They validate Dante and Squid configs, validate a Caddyfile, open a real SOCKS5 connection, open a real CONNECT tunnel, and POST a webhook at a local mock upstream.

## Migration

```bash
# old server
sudo proxystack export --output /root/proxystack-migrate.tar.gz
# new server
sudo proxystack install-script
sudo proxystack import --file /root/proxystack-migrate.tar.gz
sudo proxystack doctor
```

Import reads the new default route and public IPv4. It rewrites Dante's interface, leaves the old address out of the new config, and lets Caddy obtain a certificate for the current host. If the public address changed, the report tells you to update DNS before expecting Telegram to succeed.

## Backup and restore

```bash
sudo proxystack backup --output /root/proxystack.tar.gz
sudo proxystack backup --output /root/proxystack.tar.gz.enc --with-secrets --secrets-passphrase 'choose-one'
sudo proxystack restore --file /root/proxystack.tar.gz
```

A normal archive contains CLI settings, Dante, Squid, the Caddyfile, firewall notes, and metadata. Secrets stay out unless `--with-secrets` is set, in which case the archive is encrypted and the warning is printed first.

## Update

`proxystack update` and `proxystack update-script` compare the installed CLI with the latest GitHub Release, show the notes, and stop when you are current. A newer build is downloaded from the release asset, then raw GitHub, then jsDelivr. `SHA256SUMS` is verified before files are copied. Running proxies are not restarted.

```bash
sudo proxystack update-script
```

## Uninstall

```bash
sudo proxystack uninstall dante
sudo proxystack uninstall all --force
sudo proxystack uninstall-script
```

`uninstall` stops the selected services and removes packages that this CLI installed. It does not delete SSH access rules it did not create. `uninstall-script` removes `/usr/local/bin/proxystack` and `/usr/local/lib/proxystack` and keeps `/etc/proxystack`.

## Files

```text
/usr/local/bin/proxystack
/usr/local/lib/proxystack/
/etc/proxystack/config.env
/etc/proxystack/secrets.env          # only if you opted in, mode 600
/var/lib/proxystack/
/var/log/proxystack/proxystack.log
/etc/danted.conf
/etc/squid/squid.conf
/etc/caddy/Caddyfile
/var/log/caddy/
```

Repository layout:

```text
proxystack.sh          # installer and CLI entrypoint
lib/                   # common, i18n, ui, system, dante, squid, caddy,
                       # telegram, firewall, doctor, backup, update
locales/en.sh
locales/ru.sh
tests/unit
tests/integration
```

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| `Could not detect the external interface` | `ip route show default` must show a `dev`. Fix networking; do not hardcode an interface name. |
| Dante or Squid health check rolls back | Read the line `rollback succeeded` or `rollback failed`, then `journalctl -u danted` or `journalctl -u squid`. |
| `open /var/log/caddy/... permission denied` | `sudo proxystack restart caddy` recreates the directory as `caddy:caddy`. |
| Webhook 502 and upstream timeout | `sudo proxystack doctor`. Treat it as a network filter, not a Caddy bug, when the diagnosis says `NOT Caddy`. |
| Certificate is not issued | DNS A/AAAA must point at this host and port 80 must be reachable. |
| UFW was not changed | An existing nftables or iptables ruleset was detected. Add allows yourself; proxystack will not flush it. |

## GitHub Releases

Tagged versions publish `proxystack.sh`, `proxy-stack-cli-vX.Y.Z.tar.gz`, and `SHA256SUMS`. The current series is [0.1.0](https://github.com/driverm35/proxy-stack-cli/releases/latest). Verify a download with `sha256sum -c SHA256SUMS` before you install it.

## License

MIT. See [LICENSE](LICENSE).
