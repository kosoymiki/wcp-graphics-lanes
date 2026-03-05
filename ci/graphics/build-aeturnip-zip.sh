#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/ci/graphics/common-mesa.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/ci/graphics/common-mesa-source.sh"

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/aeturnip-zip-work}"

: "${AETURNIP_VERSION_NAME:=rolling-arm64}"
: "${AETURNIP_VERSION_CODE:=0}"
: "${AETURNIP_CHANNEL:=stable}"
: "${AETURNIP_DELIVERY:=remote}"
: "${AETURNIP_SOURCE_REPO:=${GITHUB_REPOSITORY:-kosoymiki/wcp-graphics-lanes}}"
: "${AETURNIP_RELEASE_TAG:=aeturnip-arm64-latest}"
: "${AETURNIP_ARTIFACT_NAME:=aeturnip-arm64.zip}"
: "${AETURNIP_SHA256_ARTIFACT_NAME:=SHA256SUMS-aeturnip-arm64.txt}"
: "${AETURNIP_RELEASE_NOTES_NAME:=RELEASE_NOTES-aeturnip.md}"
: "${AETURNIP_PATCHSET_DIR:=${ROOT_DIR}/ci/graphics/mesa-patches}"
: "${AETURNIP_PACKAGE_VENDOR:=Mesa}"
: "${AETURNIP_PACKAGE_AUTHOR:=AeTurnip source-build lane}"
: "${AETURNIP_PACKAGE_DESCRIPTION:=AeTurnip ARM64 source-built from Mesa main}"
: "${AETURNIP_PACKAGE_VERSION:=1}"
: "${AETURNIP_MIN_API:=28}"

mkdir -p "${OUT_DIR}" "${WORK_DIR}"
rm -rf "${WORK_DIR}/mesa-src" "${WORK_DIR}/build-turnip" "${WORK_DIR}/install-turnip" "${WORK_DIR}/normalized"
mkdir -p "${WORK_DIR}/normalized"

MESA_STABLE_VERSION="${MESA_STABLE_VERSION:-$(resolve_latest_mesa_version)}"
MESA_STABLE_TAG="mesa-${MESA_STABLE_VERSION}"
MESA_MAIN_COMMIT="${MESA_MAIN_COMMIT:-$(resolve_latest_mesa_main_head)}"
MESA_MAIN_SHORT="${MESA_MAIN_COMMIT:0:12}"
MESA_VERSION_ID="${MESA_STABLE_VERSION}-main-${MESA_MAIN_SHORT}"
MESA_ARCHIVE_URL="${MESA_ARCHIVE_URL:-$(mesa_commit_archive_url "${MESA_MAIN_COMMIT}")}"
require_cmd git
require_cmd meson
require_cmd ninja
require_cmd python3
require_cmd zip

ndk_bin="$(resolve_android_ndk_bin_dir)"
source_dir="${WORK_DIR}/mesa-src"
patch_log="${WORK_DIR}/mesa-patches-turnip-applied.txt"
cross_file="${WORK_DIR}/android-aarch64-turnip.ini"
native_file="${WORK_DIR}/native.ini"
build_dir="${WORK_DIR}/build-turnip"
install_dir="${WORK_DIR}/install-turnip"

mesa_checkout_exact_commit "${source_dir}" "${MESA_MAIN_COMMIT}"
patch_count="$(apply_mesa_patchset "${source_dir}" "${AETURNIP_PATCHSET_DIR}" "turnip" "${patch_log}")"
patches_json="$(lines_file_to_json_array "${patch_log}")"
disable_freedreno_libarchive_fallback "${source_dir}"
android_trace_stub_dir="$(prepare_android_cutils_trace_stub "${WORK_DIR}/android-stubs")"

write_mesa_android_cross_file "${cross_file}" "${ndk_bin}" "${MESA_ANDROID_API_LEVEL}"
write_mesa_native_file "${native_file}"

CFLAGS="-fPIC -I${android_trace_stub_dir} -include${android_trace_stub_dir}/cutils/pthread_cancel_compat.h" \
CXXFLAGS="-fPIC -I${android_trace_stub_dir} -include${android_trace_stub_dir}/cutils/pthread_cancel_compat.h" \
meson setup "${build_dir}" "${source_dir}" \
  --cross-file "${cross_file}" \
  --native-file "${native_file}" \
  --prefix "${install_dir}" \
  -Dbuildtype=release \
  -Dstrip=true \
  -Dplatforms=android \
  -Dvideo-codecs= \
  -Dplatform-sdk-version="${MESA_ANDROID_API_LEVEL}" \
  -Dandroid-stub=true \
  -Dandroid-libbacktrace=disabled \
  -Dgallium-drivers= \
  -Dvulkan-drivers=freedreno \
  -Dvulkan-beta=true \
  -Dfreedreno-kmds=kgsl \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dglx=disabled \
  -Dopengl=false \
  -Dgles1=disabled \
  -Dgles2=disabled \
  -Dllvm=disabled \
  -Dspirv-tools=disabled \
  -Dzstd=disabled \
  -Dshared-glapi=disabled

ninja -C "${build_dir}" -j "${MESA_BUILD_JOBS:-$(nproc)}" install

turnip_library="$(find "${install_dir}" -type f -name 'libvulkan_freedreno.so' | LC_ALL=C sort | head -n 1)"
if [[ -z "${turnip_library}" || ! -f "${turnip_library}" ]]; then
  printf '[aeturnip][error] source build did not produce libvulkan_freedreno.so\n' >&2
  exit 1
fi

cp -a "${turnip_library}" "${WORK_DIR}/normalized/libvulkan_freedreno.so"

cat > "${WORK_DIR}/normalized/meta.json" <<EOF_META_JSON
{
  "schemaVersion": 1,
  "name": "$(json_escape "${AETURNIP_VERSION_NAME}")",
  "description": "$(json_escape "${AETURNIP_PACKAGE_DESCRIPTION}")",
  "author": "$(json_escape "${AETURNIP_PACKAGE_AUTHOR}")",
  "packageVersion": "$(json_escape "${AETURNIP_PACKAGE_VERSION}")",
  "vendor": "$(json_escape "${AETURNIP_PACKAGE_VENDOR}")",
  "driverVersion": "$(json_escape "${MESA_VERSION_ID}")",
  "minApi": ${AETURNIP_MIN_API},
  "libraryName": "libvulkan_freedreno.so",
  "provider": "aeturnip",
  "channel": "$(json_escape "${AETURNIP_CHANNEL}")",
  "sourceRepo": "$(json_escape "${AETURNIP_SOURCE_REPO}")",
  "sourceType": "mesa-source-build",
  "sourceVersion": "main-head-exact",
  "mesaMainCommit": "$(json_escape "${MESA_MAIN_COMMIT}")",
  "mesaStableTag": "$(json_escape "${MESA_STABLE_TAG}")",
  "mesaSourceArchive": "$(json_escape "${MESA_ARCHIVE_URL}")",
  "appliedPatchCount": ${patch_count}
}
EOF_META_JSON

cat > "${WORK_DIR}/normalized/ae-runtime-contract.json" <<EOF_RUNTIME
{
  "schemaVersion": 2,
  "lane": "aeturnip",
  "role": "graphics-provider",
  "freewineLane": "freewine11-arm64ec",
  "providerLane": "turnip-vulkan",
  "translationLayers": ["dxvk", "vkd3d-proton", "wined3d", "zink"],
  "driverRoute": "vulkan-first",
  "providerRoutePolicy": {
    "primary": "turnip-vulkan",
    "fallback": "freedreno-opengl",
    "fallbackReasonHint": "vulkan-unavailable-or-unstable"
  },
  "x11Integration": {
    "required": true,
    "preferredServer": "x11-lorie",
    "legacyApiFallbackViaOpenGLLane": true
  },
  "compatibility": {
    "runtime": ["freewine11-arm64ec"],
    "translationLayers": ["dxvk", "vkd3d-proton", "wined3d", "zink"],
    "apiFocus": ["dx9", "dx10", "dx11", "dx12", "vulkan"],
    "openglFallbackLane": "aeopengl-driver-arm64"
  },
  "upscaler": {
    "matrixVersion": "2026.03",
    "supportsLinuxFG": true,
    "supportsMobFGSR": true,
    "supportsVkBasaltBridge": true,
    "supportsScreenFXBridge": true
  },
  "forensic": {
    "requiredEnvPrefixes": ["AERO_TURNIP_", "AERO_UPSCALE_", "AERO_DXVK_", "AERO_VKD3D_", "AERO_X11_"],
    "requiredEvents": [
      "RUNTIME_UPSCALE_RUNTIME_MATRIX",
      "RUNTIME_DX_ROUTE_POLICY",
      "RUNTIME_GRAPHICS_SUITABILITY"
    ],
    "liveDiagnosticsTopics": [
      "RUNTIME_UPSCALE_RUNTIME_MATRIX",
      "RUNTIME_DX_ROUTE_POLICY",
      "RUNTIME_GRAPHICS_SUITABILITY"
    ],
    "issueBundleKeys": [
      "runtime-conflict-contour.json",
      "runtime-mismatch-matrix.json",
      "graphics-runtime-matrix.json"
    ]
  },
  "build": {
    "mesaMainCommit": "$(json_escape "${MESA_MAIN_COMMIT}")",
    "mesaStableTag": "$(json_escape "${MESA_STABLE_TAG}")",
    "appliedPatchCount": ${patch_count}
  }
}
EOF_RUNTIME

cat > "${WORK_DIR}/normalized/aero-source.json" <<EOF_SOURCE
{
  "lane": "AeTurnip",
  "packageVersion": "$(json_escape "${AETURNIP_VERSION_NAME}")",
  "resolvedMesaStableVersion": "$(json_escape "${MESA_STABLE_VERSION}")",
  "resolvedMesaStableTag": "$(json_escape "${MESA_STABLE_TAG}")",
  "resolvedMesaMainCommit": "$(json_escape "${MESA_MAIN_COMMIT}")",
  "resolvedMesaMainShort": "$(json_escape "${MESA_MAIN_SHORT}")",
  "mesaSourceGit": "$(json_escape "${MESA_SOURCE_GIT_URL}")",
  "mesaSourceArchive": "$(json_escape "${MESA_ARCHIVE_URL}")",
  "mesaTrackingMode": "main-head-exact",
  "payloadMode": "mesa-source-build",
  "mesaBuildType": "android-aarch64-turnip",
  "androidApiLevel": "${MESA_ANDROID_API_LEVEL}",
  "mesaPatchsetRoot": "$(json_escape "${AETURNIP_PATCHSET_DIR}")",
  "appliedPatchCount": ${patch_count},
  "appliedPatches": ${patches_json}
}
EOF_SOURCE

artifact_path="${OUT_DIR}/${AETURNIP_ARTIFACT_NAME}"
sha_path="${OUT_DIR}/${AETURNIP_SHA256_ARTIFACT_NAME}"
release_notes="${OUT_DIR}/${AETURNIP_RELEASE_NOTES_NAME}"
metadata_path="${OUT_DIR}/aeturnip-metadata.env"

rm -f "${artifact_path}" "${sha_path}" "${release_notes}" "${metadata_path}"
(
  cd "${WORK_DIR}/normalized"
  zip -qr "${artifact_path}" .
)

artifact_sha="$(sha256_file "${artifact_path}")"
cat > "${sha_path}" <<EOF_SHA
${artifact_sha}  ${AETURNIP_ARTIFACT_NAME}
EOF_SHA

cat > "${release_notes}" <<EOF_NOTES
AeTurnip ARM64 source-built ZIP driver

RU:
- Формат: adrenotools ZIP, ставится через Winlator Contents
- Payload source: Mesa main source build (Android aarch64)
- Mesa exact main ref: ${MESA_MAIN_COMMIT}
- Mesa nearest stable tag: ${MESA_STABLE_TAG}
- Mesa archive: ${MESA_ARCHIVE_URL}
- Applied patch count: ${patch_count}

EN:
- Format: adrenotools ZIP, installable via Winlator Contents
- Payload source: Mesa main source build (Android aarch64)
- Mesa exact main ref: ${MESA_MAIN_COMMIT}
- Mesa nearest stable tag: ${MESA_STABLE_TAG}
- Mesa archive: ${MESA_ARCHIVE_URL}
- Applied patch count: ${patch_count}

Commit: ${GITHUB_SHA:-local}
EOF_NOTES

cat > "${metadata_path}" <<EOF_META
MESA_STABLE_VERSION=${MESA_STABLE_VERSION}
MESA_MAIN_COMMIT=${MESA_MAIN_COMMIT}
AETURNIP_ARTIFACT_PATH=${artifact_path}
AETURNIP_ARTIFACT_NAME=${AETURNIP_ARTIFACT_NAME}
AETURNIP_SHA256_PATH=${sha_path}
AETURNIP_RELEASE_NOTES=${release_notes}
AETURNIP_PATCH_COUNT=${patch_count}
AETURNIP_RUNTIME_CONTRACT=ae-runtime-contract.json
EOF_META

printf '[aeturnip] mesa=%s patches=%s artifact=%s\n' \
  "${MESA_MAIN_SHORT}" "${patch_count}" "${artifact_path}"
