#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/ci/graphics/common-mesa.sh"

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/aeopengl-zip-work}"

: "${AEOPENGL_VERSION_NAME:=rolling-arm64}"
: "${AEOPENGL_VERSION_CODE:=1}"
: "${AEOPENGL_CHANNEL:=stable}"
: "${AEOPENGL_DELIVERY:=remote}"
: "${AEOPENGL_SOURCE_REPO:=${GITHUB_REPOSITORY:-kosoymiki/winlator-wine-proton-arm64ec-wcp}}"
: "${AEOPENGL_RELEASE_TAG:=aeopengl-driver-arm64-latest}"
: "${AEOPENGL_ARTIFACT_NAME:=aeopengl-driver-arm64.zip}"
: "${AEOPENGL_SHA256_ARTIFACT_NAME:=SHA256SUMS-aeopengl-driver-arm64.txt}"
: "${AEOPENGL_RELEASE_NOTES_NAME:=RELEASE_NOTES-aeopengl-driver.md}"
: "${AEOPENGL_PAYLOAD_REPO:=https://github.com/StevenMXZ/Winlator-Ludashi.git}"
: "${AEOPENGL_PAYLOAD_REF:=1e7b09913679d1a9593f5e442241906c8731afc8}"

mkdir -p "${OUT_DIR}" "${WORK_DIR}"
rm -rf "${WORK_DIR}/extract" "${WORK_DIR}/stage" "${WORK_DIR}/payload-src"
mkdir -p "${WORK_DIR}/extract" "${WORK_DIR}/stage/usr/lib"

MESA_STABLE_VERSION="${MESA_STABLE_VERSION:-$(resolve_latest_mesa_version)}"
MESA_STABLE_TAG="mesa-${MESA_STABLE_VERSION}"
MESA_MAIN_COMMIT="${MESA_MAIN_COMMIT:-$(resolve_latest_mesa_main_head)}"
MESA_MAIN_SHORT="${MESA_MAIN_COMMIT:0:12}"
MESA_ARCHIVE_URL="${MESA_ARCHIVE_URL:-$(mesa_commit_archive_url "${MESA_MAIN_COMMIT}")}"

payload_checkout="${WORK_DIR}/payload-src"
git clone --filter=blob:none "${AEOPENGL_PAYLOAD_REPO}" "${payload_checkout}" >/dev/null 2>&1
if [[ -n "${AEOPENGL_PAYLOAD_REF}" ]]; then
  if ! git -C "${payload_checkout}" checkout "${AEOPENGL_PAYLOAD_REF}" >/dev/null 2>&1; then
    git -C "${payload_checkout}" fetch --force --depth 1 origin "${AEOPENGL_PAYLOAD_REF}" >/dev/null 2>&1
    git -C "${payload_checkout}" checkout --detach FETCH_HEAD >/dev/null 2>&1
  fi
fi
AEOPENGL_PAYLOAD_RESOLVED_REF="$(git -C "${payload_checkout}" rev-parse HEAD)"

payload_archive="${payload_checkout}/app/src/main/assets/graphics_driver/extra_libs.tzst"
if [[ ! -f "${payload_archive}" ]]; then
  printf '[aeopengl][error] missing external graphics payload: %s\n' "${payload_archive}" >&2
  exit 1
fi

tar --zstd -xf "${payload_archive}" -C "${WORK_DIR}/extract"

required_files=(
  "usr/lib/libGL.so.1.5.0"
  "usr/lib/libglapi.so.0.0.0"
)

for rel in "${required_files[@]}"; do
  if [[ ! -f "${WORK_DIR}/extract/${rel}" ]]; then
    printf '[aeopengl][error] required payload file missing: %s\n' "${rel}" >&2
    exit 1
  fi
done

cp -a "${WORK_DIR}/extract/usr/lib/libGL.so.1.5.0" "${WORK_DIR}/stage/usr/lib/"
cp -a "${WORK_DIR}/extract/usr/lib/libglapi.so.0.0.0" "${WORK_DIR}/stage/usr/lib/"

cat > "${WORK_DIR}/stage/mesa-source.json" <<EOF_SOURCE
{
  "lane": "AeOpenGLDriver",
  "packageVersion": "$(json_escape "${AEOPENGL_VERSION_NAME}")",
  "resolvedMesaStableVersion": "$(json_escape "${MESA_STABLE_VERSION}")",
  "resolvedMesaStableTag": "$(json_escape "${MESA_STABLE_TAG}")",
  "resolvedMesaMainCommit": "$(json_escape "${MESA_MAIN_COMMIT}")",
  "resolvedMesaMainShort": "$(json_escape "${MESA_MAIN_SHORT}")",
  "mesaSourceGit": "$(json_escape "${MESA_SOURCE_GIT_URL}")",
  "mesaSourceArchive": "$(json_escape "${MESA_ARCHIVE_URL}")",
  "mesaTrackingMode": "main-head-exact",
  "payloadMode": "external-pinned-overlay",
  "payloadSourceRepo": "$(json_escape "${AEOPENGL_PAYLOAD_REPO}")",
  "payloadSourceRef": "$(json_escape "${AEOPENGL_PAYLOAD_RESOLVED_REF}")",
  "payloadSourcePath": "app/src/main/assets/graphics_driver/extra_libs.tzst",
  "notes": "This lane packages an independent pinned GL fallback overlay while tracking current Mesa upstream metadata."
}
EOF_SOURCE

cat > "${WORK_DIR}/stage/profile.json" <<EOF_PROFILE
{
  "type": "OpenGLDriver",
  "name": "AeOpenGLDriver ARM64",
  "versionName": "$(json_escape "${AEOPENGL_VERSION_NAME}")",
  "versionCode": ${AEOPENGL_VERSION_CODE},
  "description": "AeOpenGLDriver ARM64 independent overlay (rolling Mesa-linked)",
  "channel": "$(json_escape "${AEOPENGL_CHANNEL}")",
  "delivery": "$(json_escape "${AEOPENGL_DELIVERY}")",
  "displayCategory": "OpenGL Driver",
  "sourceRepo": "$(json_escape "${AEOPENGL_SOURCE_REPO}")",
  "sourceType": "github-release",
  "sourceVersion": "rolling-latest",
  "releaseTag": "$(json_escape "${AEOPENGL_RELEASE_TAG}")",
  "artifactName": "$(json_escape "${AEOPENGL_ARTIFACT_NAME}")",
  "sha256Url": "https://github.com/$(json_escape "${AEOPENGL_SOURCE_REPO}")/releases/download/$(json_escape "${AEOPENGL_RELEASE_TAG}")/$(json_escape "${AEOPENGL_SHA256_ARTIFACT_NAME}")",
  "files": [
    {"source": "usr/lib/libGL.so.1.5.0", "target": "\${libdir}/libGL.so.1.5.0"},
    {"source": "usr/lib/libGL.so.1.5.0", "target": "\${libdir}/libGL.so.1"},
    {"source": "usr/lib/libglapi.so.0.0.0", "target": "\${libdir}/libglapi.so.0.0.0"},
    {"source": "usr/lib/libglapi.so.0.0.0", "target": "\${libdir}/libglapi.so.0"}
  ],
  "mesaSource": {
    "resolvedStableVersion": "$(json_escape "${MESA_STABLE_VERSION}")",
    "resolvedStableTag": "$(json_escape "${MESA_STABLE_TAG}")",
    "resolvedMainCommit": "$(json_escape "${MESA_MAIN_COMMIT}")",
    "resolvedMainShort": "$(json_escape "${MESA_MAIN_SHORT}")",
    "sourceArchive": "$(json_escape "${MESA_ARCHIVE_URL}")",
    "payloadMode": "external-pinned-overlay",
    "payloadSourceRef": "$(json_escape "${AEOPENGL_PAYLOAD_RESOLVED_REF}")",
    "trackingMode": "main-head-exact"
  }
}
EOF_PROFILE

artifact_path="${OUT_DIR}/${AEOPENGL_ARTIFACT_NAME}"
sha_path="${OUT_DIR}/${AEOPENGL_SHA256_ARTIFACT_NAME}"
release_notes="${OUT_DIR}/${AEOPENGL_RELEASE_NOTES_NAME}"
metadata_path="${OUT_DIR}/aeopengl-metadata.env"

rm -f "${artifact_path}" "${sha_path}" "${release_notes}" "${metadata_path}"
(
  cd "${WORK_DIR}/stage"
  zip -qr "${artifact_path}" .
)

artifact_sha="$(sha256_file "${artifact_path}")"
cat > "${sha_path}" <<EOF_SHA
${artifact_sha}  ${AEOPENGL_ARTIFACT_NAME}
EOF_SHA

cat > "${release_notes}" <<EOF_NOTES
AeOpenGLDriver ARM64 independent ZIP overlay

RU:
- Формат: profile.zip, ставится через Winlator Contents
- Payload: независимый pinned GL fallback overlay
- Payload source repo: ${AEOPENGL_PAYLOAD_REPO}
- Payload source ref: ${AEOPENGL_PAYLOAD_RESOLVED_REF}
- Mesa exact main ref: ${MESA_MAIN_COMMIT}
- Mesa nearest stable tag: ${MESA_STABLE_TAG}
- Mesa archive: ${MESA_ARCHIVE_URL}

EN:
- Format: profile.zip, installable via Winlator Contents
- Payload: independent pinned GL fallback overlay
- Payload source repo: ${AEOPENGL_PAYLOAD_REPO}
- Payload source ref: ${AEOPENGL_PAYLOAD_RESOLVED_REF}
- Mesa exact main ref: ${MESA_MAIN_COMMIT}
- Mesa nearest stable tag: ${MESA_STABLE_TAG}
- Mesa archive: ${MESA_ARCHIVE_URL}

Commit: ${GITHUB_SHA:-local}
EOF_NOTES

cat > "${metadata_path}" <<EOF_META
MESA_STABLE_VERSION=${MESA_STABLE_VERSION}
MESA_MAIN_COMMIT=${MESA_MAIN_COMMIT}
AEOPENGL_PAYLOAD_RESOLVED_REF=${AEOPENGL_PAYLOAD_RESOLVED_REF}
AEOPENGL_ARTIFACT_PATH=${artifact_path}
AEOPENGL_ARTIFACT_NAME=${AEOPENGL_ARTIFACT_NAME}
AEOPENGL_SHA256_PATH=${sha_path}
AEOPENGL_RELEASE_NOTES=${release_notes}
EOF_META

printf '[aeopengl] mesa=%s payload=%s artifact=%s\n' "${MESA_MAIN_SHORT}" "${AEOPENGL_PAYLOAD_RESOLVED_REF:0:12}" "${artifact_path}"
