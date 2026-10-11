#!/usr/bin/env bash
# Build release assets: proxystack.sh, the versioned tarball, and SHA256SUMS.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
version="$(tr -d '[:space:]' <VERSION)"
tag="v${version}"
mkdir -p dist
rm -f dist/proxystack.sh "dist/proxy-stack-cli-${tag}.tar.gz" dist/SHA256SUMS dist/RELEASE_NOTES.md

cp proxystack.sh dist/proxystack.sh
tar -czf "dist/proxy-stack-cli-${tag}.tar.gz" \
  proxystack.sh VERSION LICENSE lib locales

{
  sha256sum proxystack.sh VERSION lib/*.sh locales/*.sh
  sha256sum "dist/proxy-stack-cli-${tag}.tar.gz" | awk -v name="proxy-stack-cli-${tag}.tar.gz" '{print $1 "  " name}'
  sha256sum dist/proxystack.sh | awk '{print $1 "  proxystack.sh"}'
} | awk '!seen[$2]++' >dist/SHA256SUMS

notes="dist/RELEASE_NOTES.md"
repo="${PROXSTACK_GITHUB_REPO:-driverm35/proxy-stack-cli}"
{
  printf '## %s\n\n' "$tag"
  printf 'Install:\n\n'
  printf '    bash <(curl -Ls https://raw.githubusercontent.com/%s/main/proxystack.sh) install-script\n\n' "$repo"
  printf 'Upgrade the CLI without touching Dante, Squid, or Caddy:\n\n'
  printf '    sudo proxystack update-script\n\n'
  printf '### Checksums\n\n'
  cat dist/SHA256SUMS
  printf '\n'
  if [[ -f CHANGELOG.md ]]; then
    awk 'BEGIN{p=0} /^## \[/{if(p){exit} p=1} p' CHANGELOG.md
  fi
} >"$notes"

printf 'wrote dist/proxystack.sh dist/proxy-stack-cli-%s.tar.gz dist/SHA256SUMS\n' "$tag"
