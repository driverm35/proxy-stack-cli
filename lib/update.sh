# shellcheck shell=bash

if [[ -n "${PROXSTACK_UPDATE_LOADED:-}" ]]; then
  return 0
fi
PROXSTACK_UPDATE_LOADED=1

http_get() {
  local url="$1" dest="$2"
  if [[ -n "${PROXSTACK_HTTP_GET_HOOK:-}" ]]; then
    "$PROXSTACK_HTTP_GET_HOOK" "$url" "$dest"
    return
  fi
  curl -fsSL --retry 3 --retry-delay 1 --max-time 90 -o "$dest" "$url"
}

verify_sha256() {
  local file="$1" sums="$2" name="$3" expected="" actual="" base
  base="$(basename "$name")"
  expected="$(awk -v n="$name" -v b="$base" '
    $2 == n || $2 == "*" n || $2 == b || $2 == "*" b {print $1; exit}
  ' "$sums")"
  [[ -n "$expected" ]] || return 1
  if have_cmd sha256sum; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif have_cmd openssl; then
    actual="$(openssl dgst -sha256 "$file" | awk '{print $NF}')"
  else
    return 1
  fi
  [[ "$actual" == "$expected" ]]
}

release_api_url() {
  printf 'https://api.github.com/repos/%s/releases/latest' "$(proxystack_repo)"
}

release_asset_url() {
  local tag="$1" name="$2"
  printf 'https://github.com/%s/releases/download/%s/%s' "$(proxystack_repo)" "$tag" "$name"
}

raw_file_url() {
  local ref="$1" path="$2"
  printf 'https://raw.githubusercontent.com/%s/%s/%s' "$(proxystack_repo)" "$ref" "$path"
}

jsdelivr_file_url() {
  local ref="$1" path="$2"
  printf 'https://cdn.jsdelivr.net/gh/%s@%s/%s' "$(proxystack_repo)" "$ref" "$path"
}

github_archive_url() {
  local ref="$1"
  if [[ "$ref" == "main" || "$ref" == "master" ]]; then
    printf 'https://github.com/%s/archive/refs/heads/%s.tar.gz' "$(proxystack_repo)" "$ref"
  else
    printf 'https://github.com/%s/archive/refs/tags/%s.tar.gz' "$(proxystack_repo)" "$ref"
  fi
}

parse_release_tag() {
  sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1
}

parse_release_body() {
  if have_cmd python3; then
    python3 -c 'import json,sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("body") or "")
' "$1"
    return
  fi
  sed -n 's/.*"body"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$1" | head -n1
}

fetch_with_fallback() {
  local dest="$1"
  shift
  local url
  : >"${PROXSTACK_FETCH_LOG:-/dev/null}"
  for url in "$@"; do
    if [[ -n "${PROXSTACK_FETCH_LOG:-}" ]]; then
      printf '%s\n' "$url" >>"$PROXSTACK_FETCH_LOG"
    fi
    if http_get "$url" "$dest"; then
      printf '%s' "$url"
      return 0
    fi
  done
  return 1
}

install_from_root() {
  local src="$1" f
  proxystack_paths_init
  [[ -f "$src/proxystack.sh" && -f "$src/lib/common.sh" ]] || return 1
  if [[ -z "${PROXSTACK_PREFIX:-}" ]]; then
    require_root
  fi
  # Paths are assigned by proxystack_paths_init in common.sh.
  # shellcheck disable=SC2153
  mkdir -p "$PROXSTACK_BIN_DIR" "$PROXSTACK_LIB_INSTALL/locales" "$PROXSTACK_ETC" "$PROXSTACK_VAR/backups" "$PROXSTACK_LOG_DIR"
  cp "$src/proxystack.sh" "$PROXSTACK_BIN_DIR/proxystack"
  chmod 755 "$PROXSTACK_BIN_DIR/proxystack"
  for f in "$src"/lib/*.sh; do
    cp "$f" "$PROXSTACK_LIB_INSTALL/"
    chmod 644 "$PROXSTACK_LIB_INSTALL/$(basename "$f")"
  done
  for f in "$src"/locales/*.sh; do
    cp "$f" "$PROXSTACK_LIB_INSTALL/locales/"
    chmod 644 "$PROXSTACK_LIB_INSTALL/locales/$(basename "$f")"
  done
  cp "$src/VERSION" "$PROXSTACK_LIB_INSTALL/VERSION"
  printf '%s\n' "$(proxystack_repo)" >"$PROXSTACK_LIB_INSTALL/REPO"
  chmod 644 "$PROXSTACK_LIB_INSTALL/VERSION" "$PROXSTACK_LIB_INSTALL/REPO"
}

find_bundle_root() {
  local base="$1" found
  if [[ -f "$base/lib/common.sh" ]]; then
    printf '%s' "$base"
    return 0
  fi
  found="$(find "$base" -type f -path '*/lib/common.sh' | head -n1)"
  [[ -n "$found" ]] || return 1
  dirname "$(dirname "$found")"
}

stage_release_bundle() {
  local tag="$1" dest="$2" asset sums tmp root
  asset="proxy-stack-cli-${tag}.tar.gz"
  tmp="$(mktemp -d)"
  sums="$(mktemp)"
  mkdir -p "$dest"
  if ! fetch_with_fallback "$sums" \
    "$(release_asset_url "$tag" SHA256SUMS)" \
    "$(raw_file_url "$tag" SHA256SUMS)" \
    "$(jsdelivr_file_url "$tag" SHA256SUMS)"; then
    rm -rf "$tmp"
    rm -f "$sums"
    return 1
  fi
  if fetch_with_fallback "$tmp/bundle.tar.gz" \
    "$(release_asset_url "$tag" "$asset")" \
    "$(github_archive_url "$tag")" \
    "$(jsdelivr_file_url "$tag" "$asset")"; then
    if verify_sha256 "$tmp/bundle.tar.gz" "$sums" "$asset"; then
      tar -C "$tmp" -xzf "$tmp/bundle.tar.gz"
      root="$(find_bundle_root "$tmp")" || {
        rm -rf "$tmp"
        rm -f "$sums"
        return 1
      }
      cp -a "$root/." "$dest/"
      rm -rf "$tmp"
      rm -f "$sums"
      log_info "$(msg up_checksum_ok)"
      return 0
    fi
  fi
  local rel failed=0
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    mkdir -p "$dest/$(dirname "$rel")"
    if ! fetch_with_fallback "$dest/$rel" \
      "$(raw_file_url "$tag" "$rel")" \
      "$(jsdelivr_file_url "$tag" "$rel")"; then
      failed=1
      break
    fi
    if ! verify_sha256 "$dest/$rel" "$sums" "$rel"; then
      log_error "$(msg up_checksum_fail)"
      failed=1
      break
    fi
  done < <(bundle_file_list)
  rm -rf "$tmp"
  rm -f "$sums"
  [[ "$failed" -eq 0 ]]
}

cmd_install_script() {
  local root=""
  proxystack_paths_init
  if [[ -n "${PROXSTACK_ROOT:-}" && -f "${PROXSTACK_ROOT}/lib/common.sh" ]]; then
    root="$PROXSTACK_ROOT"
  elif [[ -n "${PROXSTACK_LIB_DIR:-}" && -f "${PROXSTACK_LIB_DIR}/../proxystack.sh" ]]; then
    root="$(cd "${PROXSTACK_LIB_DIR}/.." && pwd)"
  fi
  if [[ -n "$root" ]]; then
    install_from_root "$root"
    log_info "CLI installed to ${PROXSTACK_BIN_DIR}/proxystack"
    return 0
  fi
  die "$(msg up_download_fail)"
}

cmd_uninstall_script() {
  proxystack_paths_init
  if [[ -z "${PROXSTACK_PREFIX:-}" ]]; then
    require_root
  fi
  rm -f "$PROXSTACK_BIN_DIR/proxystack"
  rm -rf "$PROXSTACK_LIB_INSTALL"
  log_info "CLI removed. Configuration in ${PROXSTACK_ETC} was kept."
}

cmd_update_script() {
  local current latest json notes tag dest
  current="$(proxystack_version_read)"
  json="$(mktemp)"
  if ! http_get "$(release_api_url)" "$json"; then
    rm -f "$json"
    die "$(msg up_download_fail)"
  fi
  tag="$(parse_release_tag "$json")"
  notes="$(parse_release_body "$json" || true)"
  rm -f "$json"
  latest="${tag#v}"
  printf '%s: %s\n' "$(msg up_current)" "$current"
  printf '%s: %s\n' "$(msg up_latest)" "$latest"
  printf '%s:\n%s\n' "$(msg up_notes)" "$notes"
  if ! version_is_newer "$latest" "$current"; then
    log_info "$(msg up_same)"
    return 0
  fi
  if [[ "${PROXSTACK_NONINTERACTIVE:-0}" != "1" && "${PROXSTACK_FORCE:-0}" != "1" ]]; then
    ui_confirm "$(msg menu_update)?" || return 1
  fi
  dest="$(mktemp -d)"
  if ! stage_release_bundle "$tag" "$dest"; then
    rm -rf "$dest"
    die "$(msg up_checksum_fail)"
  fi
  install_from_root "$dest"
  rm -rf "$dest"
  log_info "$(msg up_daemons)"
  log_info "$(msg up_done)"
}
