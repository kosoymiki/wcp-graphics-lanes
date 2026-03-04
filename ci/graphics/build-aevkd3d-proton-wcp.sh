#!/usr/bin/env bash
set -eEuo pipefail

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/aevkd3d-wcp-work}"

: "${VKD3D_PROTON_GIT_URL:=https://github.com/HansKristian-Work/vkd3d-proton.git}"
: "${AEVKD3D_VERSION_NAME:=3.0b}"
: "${AEVKD3D_VERSION_CODE:=1}"
: "${AEVKD3D_CHANNEL:=stable}"
: "${AEVKD3D_DELIVERY:=remote}"
: "${AEVKD3D_FLAVOR:=generic}"
: "${AEVKD3D_SOURCE_REPO:=${GITHUB_REPOSITORY:-kosoymiki/wcp-runtime-lanes}}"
: "${AEVKD3D_RELEASE_TAG:=vkd3d-proton-latest}"
: "${AEVKD3D_ARTIFACT_NAME:=vkd3d-proton.wcp}"
: "${AEVKD3D_SHA256_ARTIFACT_NAME:=SHA256SUMS-vkd3d-proton.txt}"
: "${AEVKD3D_RELEASE_NOTES_NAME:=RELEASE_NOTES-vkd3d-proton.md}"
: "${AEVKD3D_PROFILE_NAME:=AeVKD3D-Proton}"
: "${AEVKD3D_PROFILE_DESCRIPTION:=AeVKD3D-Proton source-built package}"

trap 'ec=$?; printf "[aevkd3d][error] command failed (exit=%s) at line %s: %s\n" "${ec}" "${LINENO}" "${BASH_COMMAND}" >&2' ERR

git_clone_retry() {
  local attempt
  for attempt in 1 2 3; do
    if git clone "$@"; then
      return 0
    fi
    if [[ "${attempt}" -lt 3 ]]; then
      printf '[aevkd3d][warn] git clone attempt %s/3 failed, retrying...\n' "${attempt}" >&2
      sleep $((attempt * 3))
    fi
  done
  return 1
}

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

resolve_latest_v3_tag() {
  local tag
  tag="$(
    git ls-remote --tags --refs "${VKD3D_PROTON_GIT_URL}" 'refs/tags/v3*' \
      | sed 's#.*refs/tags/##' \
      | sort -V \
      | tail -n 1
  )"
  if [[ -z "${tag}" ]]; then
    printf '[aevkd3d][error] unable to resolve latest v3 tag from %s\n' "${VKD3D_PROTON_GIT_URL}" >&2
    exit 1
  fi
  printf '%s' "${tag}"
}

ensure_prefixed_widl() {
  local compat_bin widl_bin
  if command -v x86_64-w64-mingw32-widl >/dev/null 2>&1; then
    return 0
  fi
  if command -v i686-w64-mingw32-widl >/dev/null 2>&1; then
    widl_bin="$(command -v i686-w64-mingw32-widl)"
  elif command -v widl >/dev/null 2>&1; then
    widl_bin="$(command -v widl)"
  else
    printf '[aevkd3d][error] neither x86_64-w64-mingw32-widl nor widl is available in PATH\n' >&2
    exit 1
  fi
  compat_bin="${WORK_DIR}/compat-bin"
  mkdir -p "${compat_bin}"
  ln -sfn "${widl_bin}" "${compat_bin}/x86_64-w64-mingw32-widl"
  export PATH="${compat_bin}:${PATH}"
  printf '[aevkd3d] using widl compatibility shim: %s -> %s\n' "${compat_bin}/x86_64-w64-mingw32-widl" "${widl_bin}"
}

mkdir -p "${OUT_DIR}" "${WORK_DIR}"
rm -rf "${WORK_DIR}/src" "${WORK_DIR}/build" "${WORK_DIR}/wcp-root"

src_dir="${WORK_DIR}/src"
build_dir="${WORK_DIR}/build"
wcp_root="${WORK_DIR}/wcp-root"
stage_dir="${wcp_root}/payload"
mkdir -p "${build_dir}" "${stage_dir}/x64" "${stage_dir}/x86"
ensure_prefixed_widl

resolved_tag="$(resolve_latest_v3_tag)"
git_clone_retry --depth 1 --branch "${resolved_tag}" --recursive --shallow-submodules "${VKD3D_PROTON_GIT_URL}" "${src_dir}"
resolved_commit="$(git -C "${src_dir}" rev-parse HEAD)"
resolved_short="${resolved_commit:0:12}"
lane_name="aevkd3d-proton"
if [[ "${AEVKD3D_FLAVOR}" == "arm64ec" ]]; then
  lane_name="${lane_name}-arm64ec"
fi

git -C "${src_dir}" submodule sync --recursive
if ! git -C "${src_dir}" submodule update --init --recursive --depth 1; then
  printf '[aevkd3d][warn] shallow submodule update failed, retrying full submodule fetch\n' >&2
  git -C "${src_dir}" submodule update --init --recursive
fi

if [[ ! -x "${src_dir}/package-release.sh" ]]; then
  printf '[aevkd3d][error] package-release.sh missing in source checkout\n' >&2
  exit 1
fi

(cd "${src_dir}" && ./package-release.sh "${AEVKD3D_VERSION_NAME}" "${build_dir}" --no-package)

package_root="$(find "${build_dir}" -mindepth 1 -maxdepth 1 -type d -name 'vkd3d-proton-*' | LC_ALL=C sort | head -n 1)"
if [[ -z "${package_root}" || ! -d "${package_root}" ]]; then
  printf '[aevkd3d][error] built package root not found under %s\n' "${build_dir}" >&2
  exit 1
fi

required_dlls=(d3d12.dll d3d12core.dll)
for dll in "${required_dlls[@]}"; do
  [[ -f "${package_root}/x64/${dll}" ]] || { printf '[aevkd3d][error] missing x64/%s\n' "${dll}" >&2; exit 1; }
  [[ -f "${package_root}/x86/${dll}" ]] || { printf '[aevkd3d][error] missing x86/%s\n' "${dll}" >&2; exit 1; }
done

cp -a "${package_root}/x64/." "${stage_dir}/x64/"
cp -a "${package_root}/x86/." "${stage_dir}/x86/"

files_json="$(
  first=1
  printf '['
  for dll in "${required_dlls[@]}"; do
    if [[ ${first} -eq 0 ]]; then
      printf ','
    fi
    printf '\n    {"source": "payload/x64/%s", "target": "${system32}/%s"},' "${dll}" "${dll}"
    printf '\n    {"source": "payload/x86/%s", "target": "${syswow64}/%s"}' "${dll}" "${dll}"
    first=0
  done
  printf '\n  ]'
)"

cat > "${wcp_root}/vkd3d-source.json" <<EOF_SOURCE
{
  "lane": "AeVKD3DProton",
  "packageVersion": "$(json_escape "${AEVKD3D_VERSION_NAME}")",
  "packageFlavor": "$(json_escape "${AEVKD3D_FLAVOR}")",
  "upstreamRepo": "$(json_escape "${VKD3D_PROTON_GIT_URL}")",
  "resolvedSourceCommit": "$(json_escape "${resolved_commit}")",
  "resolvedSourceShort": "$(json_escape "${resolved_short}")",
  "resolvedUpstreamTag": "$(json_escape "${resolved_tag}")",
  "trackingMode": "head-exact",
  "buildToolchain": "mingw-w64",
  "sourceBuild": "1",
  "runtimeTarget": "$(json_escape "${AEVKD3D_FLAVOR}")"
}
EOF_SOURCE

cat > "${wcp_root}/ae-runtime-wrapper.env" <<EOF_WRAPPER
# Aeolator runtime wrapper hints for VKD3D/DXVK route selection.
# This file is declarative and does not force upstream runtime changes by itself.
AERO_GRAPHICS_WRAPPER_SCHEMA=1
AERO_GRAPHICS_WRAPPER_PROFILE=balanced
AERO_VKD3D_ROUTE_MODE=turnip-first
AERO_VKD3D_GL_FALLBACK=1
AERO_DXVK_ROUTE_MODE=turnip-first
AERO_DXVK_GL_FALLBACK=1
AERO_DXVK_LEGACY_DX89_PATH=wined3d
AERO_GL_FALLBACK_ENGINE=wined3d
EOF_WRAPPER

cat > "${wcp_root}/ae-runtime-contract.json" <<EOF_RUNTIME
{
  "schemaVersion": 2,
  "lane": "$(json_escape "${lane_name}")",
  "role": "translation-layer",
  "freewineLane": "freewine11-arm64ec",
  "providerLanes": ["turnip-vulkan", "freedreno-opengl"],
  "translationLayers": ["dxvk", "vkd3d-proton", "wined3d", "zink"],
  "providerRoutePolicy": {
    "primary": "turnip-vulkan",
    "fallback": "freedreno-opengl",
    "fallbackReasonHint": "vulkan-unavailable-or-unstable"
  },
  "legacyDxFallback": {
    "engine": "wined3d",
    "targetApis": ["dx8", "dx9"],
    "activationHint": "force-gl-fallback-for-legacy"
  },
  "wrapperContract": {
    "schemaVersion": 1,
    "defaultProfile": "balanced",
    "supportedProfiles": ["conservative", "balanced", "aggressive"],
    "profileEnv": {
      "conservative": {
        "AERO_VKD3D_FEATURE_LEVEL": "compat",
        "AERO_VKD3D_QUEUE_STRATEGY": "safe",
        "AERO_VKD3D_ROUTE_MODE": "turnip-first",
        "AERO_VKD3D_GL_FALLBACK": "1",
        "AERO_DXVK_FEATURE_LEVEL": "compat",
        "AERO_DXVK_ROUTE_MODE": "turnip-first",
        "AERO_DXVK_GL_FALLBACK": "1",
        "AERO_DXVK_LEGACY_DX89_PATH": "wined3d"
      },
      "balanced": {
        "AERO_VKD3D_FEATURE_LEVEL": "default",
        "AERO_VKD3D_QUEUE_STRATEGY": "balanced",
        "AERO_VKD3D_ROUTE_MODE": "turnip-first",
        "AERO_VKD3D_GL_FALLBACK": "1",
        "AERO_DXVK_FEATURE_LEVEL": "default",
        "AERO_DXVK_ROUTE_MODE": "turnip-first",
        "AERO_DXVK_GL_FALLBACK": "1",
        "AERO_DXVK_LEGACY_DX89_PATH": "wined3d"
      },
      "aggressive": {
        "AERO_VKD3D_FEATURE_LEVEL": "performance",
        "AERO_VKD3D_QUEUE_STRATEGY": "aggressive",
        "AERO_VKD3D_ROUTE_MODE": "turnip-first",
        "AERO_VKD3D_GL_FALLBACK": "1",
        "AERO_DXVK_FEATURE_LEVEL": "performance",
        "AERO_DXVK_ROUTE_MODE": "turnip-first",
        "AERO_DXVK_GL_FALLBACK": "1",
        "AERO_DXVK_LEGACY_DX89_PATH": "wined3d"
      }
    },
    "routeHints": {
      "primaryProvider": "turnip-vulkan",
      "fallbackProvider": "freedreno-opengl",
      "legacyFallbackEngine": "wined3d",
      "legacyTargetApis": ["dx8", "dx9"]
    },
    "socClassProfiles": {
      "adreno-6xx-and-older": "conservative",
      "adreno-7xx": "balanced",
      "xclipse-rdna-mobile": "balanced",
      "mali-g7xx-or-newer": "aggressive",
      "unknown": "balanced"
    }
  },
  "forensic": {
    "requiredEnvPrefixes": ["AERO_VKD3D_", "AERO_DXVK_", "AERO_TURNIP_", "AERO_WINE_"],
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
    "resolvedSourceCommit": "$(json_escape "${resolved_commit}")",
    "resolvedUpstreamTag": "$(json_escape "${resolved_tag}")",
    "runtimeTarget": "$(json_escape "${AEVKD3D_FLAVOR}")"
  }
}
EOF_RUNTIME

cat > "${wcp_root}/profile.json" <<EOF_PROFILE
{
  "type": "VKD3D",
  "name": "$(json_escape "${AEVKD3D_PROFILE_NAME}")",
  "versionName": "$(json_escape "${AEVKD3D_VERSION_NAME}")",
  "versionCode": ${AEVKD3D_VERSION_CODE},
  "description": "$(json_escape "${AEVKD3D_PROFILE_DESCRIPTION}")",
  "channel": "$(json_escape "${AEVKD3D_CHANNEL}")",
  "delivery": "$(json_escape "${AEVKD3D_DELIVERY}")",
  "displayCategory": "VKD3D",
  "sourceRepo": "$(json_escape "${AEVKD3D_SOURCE_REPO}")",
  "sourceType": "github-release",
  "sourceVersion": "rolling-latest",
  "releaseTag": "$(json_escape "${AEVKD3D_RELEASE_TAG}")",
  "artifactName": "$(json_escape "${AEVKD3D_ARTIFACT_NAME}")",
  "sha256Url": "https://github.com/$(json_escape "${AEVKD3D_SOURCE_REPO}")/releases/download/$(json_escape "${AEVKD3D_RELEASE_TAG}")/$(json_escape "${AEVKD3D_SHA256_ARTIFACT_NAME}")",
  "files": ${files_json},
  "vkd3dSource": {
    "resolvedSourceCommit": "$(json_escape "${resolved_commit}")",
    "resolvedSourceShort": "$(json_escape "${resolved_short}")",
    "resolvedUpstreamTag": "$(json_escape "${resolved_tag}")",
    "runtimeTarget": "$(json_escape "${AEVKD3D_FLAVOR}")",
    "sourceBuild": true
  }
}
EOF_PROFILE

artifact_path="${OUT_DIR}/${AEVKD3D_ARTIFACT_NAME}"
sha_path="${OUT_DIR}/${AEVKD3D_SHA256_ARTIFACT_NAME}"
release_notes="${OUT_DIR}/${AEVKD3D_RELEASE_NOTES_NAME}"
metadata_path="${OUT_DIR}/aevkd3d-metadata.env"

rm -f "${artifact_path}" "${sha_path}" "${release_notes}" "${metadata_path}"
tar -cJf "${artifact_path}" -C "${wcp_root}" .

artifact_sha="$(sha256_file "${artifact_path}")"
cat > "${sha_path}" <<EOF_SHA
${artifact_sha}  ${AEVKD3D_ARTIFACT_NAME}
EOF_SHA

cat > "${release_notes}" <<EOF_NOTES
AeVKD3D-Proton source-built package

RU:
- Формат: WCP, ставится через Winlator Contents
- Источник: ${VKD3D_PROTON_GIT_URL}
- Exact commit: ${resolved_commit}
- Ближайший upstream 3.x tag: ${resolved_tag}
- Runtime target: ${AEVKD3D_FLAVOR}
- Wrapper contract: turnip-first + freedreno/wined3d fallback

EN:
- Format: WCP, installable via Winlator Contents
- Source: ${VKD3D_PROTON_GIT_URL}
- Exact commit: ${resolved_commit}
- Nearest upstream 3.x tag: ${resolved_tag}
- Runtime target: ${AEVKD3D_FLAVOR}
- Wrapper contract: turnip-first + freedreno/wined3d fallback

Commit: ${GITHUB_SHA:-local}
EOF_NOTES

cat > "${metadata_path}" <<EOF_META
AEVKD3D_RESOLVED_COMMIT=${resolved_commit}
AEVKD3D_RESOLVED_TAG=${resolved_tag}
AEVKD3D_ARTIFACT_PATH=${artifact_path}
AEVKD3D_ARTIFACT_NAME=${AEVKD3D_ARTIFACT_NAME}
AEVKD3D_SHA256_PATH=${sha_path}
AEVKD3D_RELEASE_NOTES=${release_notes}
EOF_META

printf '[aevkd3d] flavor=%s commit=%s artifact=%s\n' \
  "${AEVKD3D_FLAVOR}" "${resolved_short}" "${artifact_path}"
