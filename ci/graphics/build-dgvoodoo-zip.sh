#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/dgvoodoo-zip-work}"

: "${DGVOODOO_LATEST_RELEASE_API:=https://api.github.com/repos/dege-diosg/dgVoodoo2/releases/latest}"
: "${DGVOODOO_VERSION_NAME:=}"
: "${DGVOODOO_RELEASE_TAG:=dgvoodoo-latest}"
: "${DGVOODOO_ARTIFACT_NAME:=dgvoodoo-latest.zip}"
: "${DGVOODOO_SHA256_ARTIFACT_NAME:=SHA256SUMS-dgvoodoo-latest.txt}"
: "${DGVOODOO_RELEASE_NOTES_NAME:=RELEASE_NOTES-dgvoodoo.md}"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "${OUT_DIR}" "${WORK_DIR}"

release_json="${WORK_DIR}/release.json"
curl -fsSL -o "${release_json}" "${DGVOODOO_LATEST_RELEASE_API}"

upstream_tag="$(jq -r '.tag_name // ""' "${release_json}")"
asset_name="$(jq -r '
  (.assets // [])
  | map(select((.name | test("^dgVoodoo2_[0-9_]+\\.zip$")) and (.name | contains("_dbg") | not) and (.name | contains("_dev64") | not)))
  | .[0].name // ""
' "${release_json}")"
asset_url="$(jq -r '
  (.assets // [])
  | map(select((.name | test("^dgVoodoo2_[0-9_]+\\.zip$")) and (.name | contains("_dbg") | not) and (.name | contains("_dev64") | not)))
  | .[0].browser_download_url // ""
' "${release_json}")"
release_url="$(jq -r '.html_url // ""' "${release_json}")"
version_name="${upstream_tag#v}"

if [[ -z "${upstream_tag}" || -z "${asset_name}" || -z "${asset_url}" || -z "${version_name}" ]]; then
  printf '[dgvoodoo][error] unable to resolve latest upstream release asset\n' >&2
  exit 1
fi

if [[ -n "${DGVOODOO_VERSION_NAME}" && "${DGVOODOO_VERSION_NAME}" != "${version_name}" ]]; then
  printf '[dgvoodoo][error] upstream latest (%s) differs from pinned contents version (%s)\n' \
    "${version_name}" "${DGVOODOO_VERSION_NAME}" >&2
  exit 1
fi

tmp_zip="${WORK_DIR}/${asset_name}"
artifact_path="${OUT_DIR}/${DGVOODOO_ARTIFACT_NAME}"
sha_path="${OUT_DIR}/${DGVOODOO_SHA256_ARTIFACT_NAME}"
release_notes="${OUT_DIR}/${DGVOODOO_RELEASE_NOTES_NAME}"
metadata_path="${OUT_DIR}/dgvoodoo-metadata.env"

curl -fsSL -o "${tmp_zip}" "${asset_url}"
if ! unzip -Z1 "${tmp_zip}" 2>/dev/null | grep -Eq '(^|/)MS/x86/'; then
  printf '[dgvoodoo][error] upstream ZIP does not contain MS/x86 runtime tree\n' >&2
  exit 1
fi

cp -f "${tmp_zip}" "${artifact_path}"

artifact_sha="$(sha256_file "${artifact_path}")"
cat > "${sha_path}" <<EOF_SHA
${artifact_sha}  ${DGVOODOO_ARTIFACT_NAME}
EOF_SHA

cat > "${release_notes}" <<EOF_NOTES
dgVoodoo latest ZIP mirror

RU:
- Формат: upstream ZIP, ставится через Winlator Contents
- Upstream tag: ${upstream_tag}
- Upstream asset: ${asset_name}
- Upstream release: ${release_url}

EN:
- Format: upstream ZIP, installable via Winlator Contents
- Upstream tag: ${upstream_tag}
- Upstream asset: ${asset_name}
- Upstream release: ${release_url}

Commit: ${GITHUB_SHA:-local}
EOF_NOTES

cat > "${metadata_path}" <<EOF_META
DGVOODOO_VERSION_NAME=${version_name}
DGVOODOO_UPSTREAM_TAG=${upstream_tag}
DGVOODOO_UPSTREAM_ASSET=${asset_name}
DGVOODOO_ARTIFACT_PATH=${artifact_path}
DGVOODOO_ARTIFACT_NAME=${DGVOODOO_ARTIFACT_NAME}
DGVOODOO_SHA256_PATH=${sha_path}
DGVOODOO_RELEASE_NOTES=${release_notes}
EOF_META

printf '[dgvoodoo] upstream=%s artifact=%s\n' "${upstream_tag}" "${artifact_path}"
