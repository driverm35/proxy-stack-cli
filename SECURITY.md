# Security policy

proxystack configures network services. Authentication on Dante or Squid is not a substitute for a firewall. The recommended firewall profile allows proxy ports only from the source addresses you list. Ports 80 and 443 may stay public so Caddy can obtain a certificate and receive webhooks.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | yes |

## Reporting a vulnerability

Open a private GitHub security advisory on this repository, or email the maintainer listed on the GitHub profile. Do not include live passwords, bot tokens, or unredacted logs. Give the proxystack version, the OS, and the smallest steps that show the problem.

## Handling of secrets

- Generated proxy passwords are printed once and are not written to `/var/log/proxystack`.
- The bot token is kept only when you explicitly agree, in `/etc/proxystack/secrets.env` with mode `600`.
- `proxystack backup` omits secrets unless you pass `--with-secrets`, which encrypts the archive.
- Diagnostic output redacts `password`, bot tokens, and `Proxy-Authorization`.
- `proxystack update-script` verifies `SHA256SUMS` before replacing CLI files and does not reload Dante, Squid, or Caddy.
