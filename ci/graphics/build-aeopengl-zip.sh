#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/ci/graphics/common-mesa.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/ci/graphics/common-mesa-source.sh"

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/aeopengl-zip-work}"

: "${AEOPENGL_VERSION_NAME:=rolling-arm64}"
: "${AEOPENGL_VERSION_CODE:=1}"
: "${AEOPENGL_CHANNEL:=stable}"
: "${AEOPENGL_DELIVERY:=remote}"
: "${AEOPENGL_SOURCE_REPO:=${GITHUB_REPOSITORY:-kosoymiki/wcp-graphics-lanes}}"
: "${AEOPENGL_RELEASE_TAG:=aeopengl-driver-arm64-latest}"
: "${AEOPENGL_ARTIFACT_NAME:=aeopengl-driver-arm64.zip}"
: "${AEOPENGL_SHA256_ARTIFACT_NAME:=SHA256SUMS-aeopengl-driver-arm64.txt}"
: "${AEOPENGL_RELEASE_NOTES_NAME:=RELEASE_NOTES-aeopengl-driver.md}"
: "${AEOPENGL_PATCHSET_DIR:=${ROOT_DIR}/ci/graphics/mesa-patches}"

mkdir -p "${OUT_DIR}" "${WORK_DIR}"
rm -rf "${WORK_DIR}/stage" "${WORK_DIR}/mesa-src" "${WORK_DIR}/build-opengl" "${WORK_DIR}/install-opengl" "${WORK_DIR}/termux-sysroot"
mkdir -p "${WORK_DIR}/stage/usr/lib"

MESA_STABLE_VERSION="${MESA_STABLE_VERSION:-$(resolve_latest_mesa_version)}"
MESA_STABLE_TAG="mesa-${MESA_STABLE_VERSION}"
MESA_MAIN_COMMIT="${MESA_MAIN_COMMIT:-$(resolve_latest_mesa_main_head)}"
MESA_MAIN_SHORT="${MESA_MAIN_COMMIT:0:12}"
MESA_ARCHIVE_URL="${MESA_ARCHIVE_URL:-$(mesa_commit_archive_url "${MESA_MAIN_COMMIT}")}"
require_cmd git
require_cmd meson
require_cmd ninja
require_cmd python3
require_cmd zip
require_cmd curl
require_cmd dpkg-deb
require_cmd pkg-config

ndk_bin="$(resolve_android_ndk_bin_dir)"
source_dir="${WORK_DIR}/mesa-src"
patch_log="${WORK_DIR}/mesa-patches-opengl-applied.txt"
cross_file="${WORK_DIR}/android-aarch64-x11.ini"
native_file="${WORK_DIR}/native.ini"
build_dir="${WORK_DIR}/build-opengl"
install_dir="${WORK_DIR}/install-opengl"
termux_prefix="$(prepare_termux_sysroot "${WORK_DIR}/termux-sysroot")"
termux_root="${WORK_DIR}/termux-sysroot/root"
termux_pkgconfig_dir="${termux_prefix}/lib/pkgconfig:${termux_prefix}/share/pkgconfig"
pkg_config_wrapper="${WORK_DIR}/pkg-config-termux.sh"

if [[ ! -d "${termux_prefix}" ]]; then
  printf '[aeopengl][error] termux prefix not prepared: %s\n' "${termux_prefix}" >&2
  exit 1
fi

cat > "${pkg_config_wrapper}" <<EOF_PKG
#!/usr/bin/env bash
set -euo pipefail
exec env \\
  PKG_CONFIG_DIR= \\
  PKG_CONFIG_PATH= \\
  PKG_CONFIG_SYSROOT_DIR="${termux_root}" \\
  PKG_CONFIG_LIBDIR="${termux_pkgconfig_dir}" \\
  /usr/bin/pkg-config "\$@"
EOF_PKG
chmod +x "${pkg_config_wrapper}"

mesa_checkout_exact_commit "${source_dir}" "${MESA_MAIN_COMMIT}"
patch_count="$(apply_mesa_patchset "${source_dir}" "${AEOPENGL_PATCHSET_DIR}" "opengl" "${patch_log}")"
patches_json="$(lines_file_to_json_array "${patch_log}")"

write_mesa_android_x11_cross_file "${cross_file}" "${ndk_bin}" "${MESA_ANDROID_API_LEVEL}" "${pkg_config_wrapper}"
write_mesa_native_file "${native_file}"

PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1 \
PKG_CONFIG_ALLOW_SYSTEM_LIBS=1 \
CFLAGS="-D__ANDROID__ -fPIC" \
CXXFLAGS="-D__ANDROID__ -fPIC" \
LDFLAGS="-Wl,-rpath,${MESA_TERMUX_RUNPATH}" \
meson setup "${build_dir}" "${source_dir}" \
  --cross-file "${cross_file}" \
  --native-file "${native_file}" \
  --prefix "${install_dir}" \
  -Dbuildtype=release \
  -Dstrip=true \
  -Dplatforms=x11 \
  -Dglx=xlib \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dllvm=disabled \
  -Dvideo-codecs= \
  -Dopengl=true \
  -Dgles1=disabled \
  -Dgles2=disabled \
  -Dgallium-drivers=freedreno,swrast,zink \
  -Dvulkan-drivers=freedreno \
  -Dfreedreno-kmds=kgsl \
  -Dshared-glapi=enabled

ninja -C "${build_dir}" -j "${MESA_BUILD_JOBS:-$(nproc)}" install

libgl_source="$(find "${install_dir}" -type f -name 'libGL.so.1.5.0' | LC_ALL=C sort | head -n 1)"
if [[ -z "${libgl_source}" ]]; then
  libgl_source="$(find "${install_dir}" -type f -name 'libGL.so.*' | LC_ALL=C sort | head -n 1)"
fi

libglapi_source="$(find "${install_dir}" -type f -name 'libglapi.so.0.0.0' | LC_ALL=C sort | head -n 1)"
if [[ -z "${libglapi_source}" ]]; then
  libglapi_source="$(find "${install_dir}" -type f -name 'libglapi.so.*' | LC_ALL=C sort | head -n 1)"
fi

if [[ -z "${libgl_source}" || ! -f "${libgl_source}" ]]; then
  printf '[aeopengl][error] source build did not produce libGL\n' >&2
  exit 1
fi
if [[ -z "${libglapi_source}" || ! -f "${libglapi_source}" ]]; then
  printf '[aeopengl][error] source build did not produce libglapi\n' >&2
  exit 1
fi

cp -a "${libgl_source}" "${WORK_DIR}/stage/usr/lib/libGL.so.1.5.0"
cp -a "${libglapi_source}" "${WORK_DIR}/stage/usr/lib/libglapi.so.0.0.0"

resolved_libgl_name="$(basename -- "${libgl_source}")"
resolved_libglapi_name="$(basename -- "${libglapi_source}")"

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
  "payloadMode": "mesa-source-build",
  "mesaBuildType": "android-aarch64-x11",
  "androidApiLevel": "${MESA_ANDROID_API_LEVEL}",
  "termuxRepoBase": "$(json_escape "${MESA_TERMUX_REPO_BASE_URL}")",
  "termuxPackagesIndex": "$(json_escape "${MESA_TERMUX_PACKAGES_INDEX_URL}")",
  "termuxSeedPackages": "$(json_escape "${MESA_TERMUX_SEED_PACKAGES}")",
  "termuxRunPath": "$(json_escape "${MESA_TERMUX_RUNPATH}")",
  "resolvedLibGLSource": "$(json_escape "${resolved_libgl_name}")",
  "resolvedLibGLAPISource": "$(json_escape "${resolved_libglapi_name}")",
  "mesaPatchsetRoot": "$(json_escape "${AEOPENGL_PATCHSET_DIR}")",
  "appliedPatchCount": ${patch_count},
  "appliedPatches": ${patches_json}
}
EOF_SOURCE

cat > "${WORK_DIR}/stage/ae-runtime-contract.json" <<EOF_RUNTIME
{
  "schemaVersion": 2,
  "lane": "aeopengl-driver",
  "role": "graphics-provider",
  "freewineLane": "freewine11-arm64ec",
  "providerLane": "freedreno-opengl",
  "translationLayers": ["wined3d", "zink", "dxvk", "vkd3d-proton"],
  "graphicsStackProfile": "vulkan-first-with-gl-fallback",
  "providerRoutePolicy": {
    "primary": "freedreno-opengl",
    "companion": "turnip-vulkan",
    "promotionRule": "prefer-turnip-for-dxvk-vkd3d"
  },
  "forensic": {
    "requiredEnvPrefixes": ["AERO_OPENGL_", "AERO_UPSCALE_", "AERO_DXVK_", "AERO_VKD3D_", "AERO_WINE_"],
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

cat > "${WORK_DIR}/stage/profile.json" <<EOF_PROFILE
{
  "type": "OpenGLDriver",
  "name": "AeOpenGLDriver ARM64",
  "versionName": "$(json_escape "${AEOPENGL_VERSION_NAME}")",
  "versionCode": ${AEOPENGL_VERSION_CODE},
  "description": "AeOpenGLDriver ARM64 source-built fallback (rolling Mesa-linked)",
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
    "payloadMode": "mesa-source-build",
    "resolvedLibGLSource": "$(json_escape "${resolved_libgl_name}")",
    "resolvedLibGLAPISource": "$(json_escape "${resolved_libglapi_name}")",
    "appliedPatchCount": ${patch_count},
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
AeOpenGLDriver ARM64 source-built ZIP overlay

RU:
- Формат: profile.zip, ставится через Winlator Contents
- Payload: Mesa source build (x11 OpenGL fallback for Android aarch64)
- Mesa exact main ref: ${MESA_MAIN_COMMIT}
- Mesa nearest stable tag: ${MESA_STABLE_TAG}
- Mesa archive: ${MESA_ARCHIVE_URL}
- Applied patch count: ${patch_count}
- Resolved libGL source: ${resolved_libgl_name}
- Resolved libglapi source: ${resolved_libglapi_name}

EN:
- Format: profile.zip, installable via Winlator Contents
- Payload: Mesa source build (x11 OpenGL fallback for Android aarch64)
- Mesa exact main ref: ${MESA_MAIN_COMMIT}
- Mesa nearest stable tag: ${MESA_STABLE_TAG}
- Mesa archive: ${MESA_ARCHIVE_URL}
- Applied patch count: ${patch_count}
- Resolved libGL source: ${resolved_libgl_name}
- Resolved libglapi source: ${resolved_libglapi_name}

Commit: ${GITHUB_SHA:-local}
EOF_NOTES

cat > "${metadata_path}" <<EOF_META
MESA_STABLE_VERSION=${MESA_STABLE_VERSION}
MESA_MAIN_COMMIT=${MESA_MAIN_COMMIT}
AEOPENGL_PATCH_COUNT=${patch_count}
AEOPENGL_RESOLVED_LIBGL=${resolved_libgl_name}
AEOPENGL_RESOLVED_LIBGLAPI=${resolved_libglapi_name}
AEOPENGL_ARTIFACT_PATH=${artifact_path}
AEOPENGL_ARTIFACT_NAME=${AEOPENGL_ARTIFACT_NAME}
AEOPENGL_SHA256_PATH=${sha_path}
AEOPENGL_RELEASE_NOTES=${release_notes}
EOF_META

printf '[aeopengl] mesa=%s patches=%s libGL=%s libglapi=%s artifact=%s\n' \
  "${MESA_MAIN_SHORT}" "${patch_count}" "${resolved_libgl_name}" "${resolved_libglapi_name}" "${artifact_path}"
