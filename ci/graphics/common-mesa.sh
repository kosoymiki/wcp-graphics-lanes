#!/usr/bin/env bash
set -euo pipefail

: "${MESA_SOURCE_GIT_URL:=https://gitlab.freedesktop.org/mesa/mesa.git}"

json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

resolve_latest_mesa_version() {
  local version
  version="$(
    git ls-remote --tags --refs "${MESA_SOURCE_GIT_URL}" 'mesa-*' \
      | sed 's#.*refs/tags/mesa-##' \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
      | sort -V \
      | tail -n 1
  )"
  if [[ -z "${version}" ]]; then
    printf '[mesa][error] unable to resolve latest stable tag from %s\n' "${MESA_SOURCE_GIT_URL}" >&2
    exit 1
  fi
  printf '%s' "${version}"
}

resolve_latest_mesa_main_head() {
  local head
  head="$(git ls-remote "${MESA_SOURCE_GIT_URL}" refs/heads/main | awk '{print $1}')"
  if [[ -z "${head}" ]]; then
    printf '[mesa][error] unable to resolve refs/heads/main from %s\n' "${MESA_SOURCE_GIT_URL}" >&2
    exit 1
  fi
  printf '%s' "${head}"
}

mesa_source_archive_url() {
  local version="${1:?mesa version required}"
  printf 'https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-%s/mesa-mesa-%s.tar.gz' "${version}" "${version}"
}

mesa_commit_archive_url() {
  local commit="${1:?mesa commit required}"
  printf 'https://gitlab.freedesktop.org/mesa/mesa/-/archive/%s/mesa-%s.tar.gz' "${commit}" "${commit}"
}
