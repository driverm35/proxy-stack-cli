# Changelog

## [0.1.0] - 2026-10-11

### Added

- Interactive bilingual CLI (`proxystack`) for Ubuntu and Debian.
- Dante SOCKS5 install with interface detection, username auth, TCP and UDP, config validation, and rollback.
- Squid HTTP CONNECT install with NCSA auth, `squid -k parse`, and a CONNECT probe.
- Caddy reverse proxy for `/webhook/` and `/webhook/*`, preserving the request path and setting the upstream Host header.
- Telegram webhook `set`, `info`, `delete`, and `test`, with explanations for 404, 502, and timeout.
- Firewall profiles that keep SSH and refuse to flush an existing nftables or iptables policy.
- `proxystack doctor`, backup/restore/migration, and checksum-verified CLI self-update.
