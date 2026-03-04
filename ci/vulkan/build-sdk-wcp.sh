#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/vulkan-sdk-wcp-work}"
SDK_ARCHIVE_PATH="${3:-}"
SDK_VERSION_ARG="${4:-}"

: "${VULKAN_SDK_SOURCE_ARCH:=arm64}"
: "${VULKAN_SDK_LAYOUT_ARCH:=${VULKAN_SDK_SOURCE_ARCH}}"
: "${VULKAN_SDK_DOWNLOAD_URL:=https://sdk.lunarg.com/sdk/download/latest/linux/vulkan-sdk.tar.xz}"
: "${VULKAN_SDK_LATEST_JSON_URL:=https://vulkan.lunarg.com/sdk/latest/linux.json}"

: "${WCP_NAME:=vulkan-sdk-arm64}"
: "${WCP_PROFILE_NAME:=Vulkan SDK ARM64 Toolkit}"
: "${WCP_PROFILE_DESCRIPTION:=Vulkan SDK ${VULKAN_SDK_LAYOUT_ARCH} Toolkit for Ae.solator Contents}"
: "${WCP_PROFILE_TYPE:=VulkanSDK}"
: "${WCP_DISPLAY_CATEGORY:=Vulkan SDK}"
: "${WCP_VERSION_CODE:=1}"
: "${WCP_CHANNEL:=stable}"
: "${WCP_DELIVERY:=remote}"
: "${WCP_SOURCE_REPO:=${GITHUB_REPOSITORY:-kosoymiki/wcp-runtime-lanes}}"
: "${WCP_RELEASE_TAG:=vulkan-sdk-arm64-latest}"
: "${WCP_SOURCE_TYPE:=github-release}"
: "${WCP_SOURCE_VERSION:=rolling-latest}"
: "${WCP_ARTIFACT_NAME:=${WCP_NAME}.wcp}"
: "${WCP_SHA256_ARTIFACT_NAME:=SHA256SUMS-${WCP_NAME}.txt}"
: "${WCP_SHA256_URL:=https://github.com/${WCP_SOURCE_REPO}/releases/download/${WCP_RELEASE_TAG}/${WCP_SHA256_ARTIFACT_NAME}}"

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

mkdir -p "${OUT_DIR}" "${WORK_DIR}"

toolkit_out="${WORK_DIR}/toolkit-out"
toolkit_work="${WORK_DIR}/toolkit-work"

if [[ -z "${SDK_ARCHIVE_PATH}" ]]; then
  if [[ "${VULKAN_SDK_SOURCE_ARCH}" == "arm64" ]]; then
    rm -rf "${toolkit_out}" "${toolkit_work}"
    mkdir -p "${toolkit_out}" "${toolkit_work}"
    bash "${ROOT_DIR}/ci/vulkan/build-sdk-arm.sh" "${toolkit_out}" "${toolkit_work}"
    # shellcheck disable=SC1090
    source "${toolkit_out}/metadata.env"
    SDK_ARCHIVE_PATH="${ARTIFACT_PATH}"
  elif [[ "${VULKAN_SDK_SOURCE_ARCH}" == "x86_64" ]]; then
    SDK_ARCHIVE_PATH="${WORK_DIR}/vulkan-sdk-${VULKAN_SDK_SOURCE_ARCH}.tar.xz"
    curl -fsSL -o "${SDK_ARCHIVE_PATH}" "${VULKAN_SDK_DOWNLOAD_URL}"
  else
    printf '[vulkan-sdk-wcp][error] unsupported source arch: %s\n' "${VULKAN_SDK_SOURCE_ARCH}" >&2
    exit 1
  fi
fi

if [[ -z "${SDK_VERSION_ARG}" ]]; then
  SDK_VERSION_ARG="${VK_SDK_VERSION:-$(curl -fsSL "${VULKAN_SDK_LATEST_JSON_URL}" | jq -r '.linux')}"
fi

VK_SDK_VERSION="${SDK_VERSION_ARG}"
WCP_VERSION_NAME="${WCP_VERSION_NAME:-${VK_SDK_VERSION}-${VULKAN_SDK_LAYOUT_ARCH}}"

extract_root="${WORK_DIR}/extract"
wcp_root="${WORK_DIR}/wcp-root"
metadata_path="${OUT_DIR}/wcp-metadata.env"
artifact_path="${OUT_DIR}/${WCP_ARTIFACT_NAME}"
sha_file="${OUT_DIR}/${WCP_SHA256_ARTIFACT_NAME}"
release_notes="${OUT_DIR}/RELEASE_NOTES-vulkan-sdk.md"

rm -rf "${extract_root}" "${wcp_root}"
mkdir -p "${extract_root}"

tar -xJf "${SDK_ARCHIVE_PATH}" -C "${extract_root}"

sdk_root="${extract_root}/${VK_SDK_VERSION}"
if [[ ! -d "${sdk_root}" ]]; then
  printf '[vulkan-sdk-wcp][error] extracted SDK root missing: %s\n' "${sdk_root}" >&2
  exit 1
fi

layout_source_root="${sdk_root}"
case "${VULKAN_SDK_LAYOUT_ARCH}" in
  arm64)
    layout_source_root="${sdk_root}"
    ;;
  x86_64)
    layout_source_root="${sdk_root}/x86_64"
    ;;
  *)
    printf '[vulkan-sdk-wcp][error] unsupported layout arch: %s\n' "${VULKAN_SDK_LAYOUT_ARCH}" >&2
    exit 1
    ;;
esac

if [[ ! -d "${layout_source_root}" ]]; then
  printf '[vulkan-sdk-wcp][error] layout source missing for %s: %s\n' "${VULKAN_SDK_LAYOUT_ARCH}" "${layout_source_root}" >&2
  exit 1
fi

layout_install_root="${wcp_root}/sdk/${VK_SDK_VERSION}/${VULKAN_SDK_LAYOUT_ARCH}"
mkdir -p "${layout_install_root}"
cp -a "${layout_source_root}/." "${layout_install_root}/"

cat > "${layout_install_root}/manifest.json" <<EOF_MANIFEST
{
  "sdkVersion": "$(json_escape "${VK_SDK_VERSION}")",
  "arch": "$(json_escape "${VULKAN_SDK_LAYOUT_ARCH}")",
  "packageName": "$(json_escape "${WCP_NAME}")",
  "layout": "share/vulkan-sdk/$(json_escape "${VK_SDK_VERSION}")/$(json_escape "${VULKAN_SDK_LAYOUT_ARCH}")",
  "sourceRepo": "$(json_escape "${WCP_SOURCE_REPO}")",
  "releaseTag": "$(json_escape "${WCP_RELEASE_TAG}")"
}
EOF_MANIFEST

files_json="$(
  cd "${wcp_root}"
  first=1
  printf '['
  while IFS= read -r rel; do
    target_rel="${rel#sdk/${VK_SDK_VERSION}/${VULKAN_SDK_LAYOUT_ARCH}/}"
    target="\${sharedir}/vulkan-sdk/${VK_SDK_VERSION}/${VULKAN_SDK_LAYOUT_ARCH}/${target_rel}"
    if [[ ${first} -eq 0 ]]; then
      printf ','
    fi
    printf '\n    {"source": "%s", "target": "%s"}' \
      "$(json_escape "${rel}")" \
      "$(json_escape "${target}")"
    first=0
  done < <(find "sdk/${VK_SDK_VERSION}/${VULKAN_SDK_LAYOUT_ARCH}" -type f | LC_ALL=C sort)
  if [[ ${first} -eq 0 ]]; then
    printf '\n  '
  fi
  printf ']'
)"

utc_now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "${wcp_root}/profile.json" <<EOF_PROFILE
{
  "type": "${WCP_PROFILE_TYPE}",
  "name": "$(json_escape "${WCP_PROFILE_NAME}")",
  "versionName": "$(json_escape "${WCP_VERSION_NAME}")",
  "versionCode": ${WCP_VERSION_CODE},
  "description": "$(json_escape "${WCP_PROFILE_DESCRIPTION}")",
  "channel": "$(json_escape "${WCP_CHANNEL}")",
  "delivery": "$(json_escape "${WCP_DELIVERY}")",
  "displayCategory": "$(json_escape "${WCP_DISPLAY_CATEGORY}")",
  "sourceRepo": "$(json_escape "${WCP_SOURCE_REPO}")",
  "sourceType": "$(json_escape "${WCP_SOURCE_TYPE}")",
  "sourceVersion": "$(json_escape "${WCP_SOURCE_VERSION}")",
  "releaseTag": "$(json_escape "${WCP_RELEASE_TAG}")",
  "artifactName": "$(json_escape "${WCP_ARTIFACT_NAME}")",
  "sha256Url": "$(json_escape "${WCP_SHA256_URL}")",
  "files": ${files_json},
  "vulkanSdk": {
    "sdkVersion": "$(json_escape "${VK_SDK_VERSION}")",
    "arch": "$(json_escape "${VULKAN_SDK_LAYOUT_ARCH}")",
    "toolkitArtifact": "$(json_escape "$(basename -- "${SDK_ARCHIVE_PATH}")")",
    "installRoot": "share/vulkan-sdk/$(json_escape "${VK_SDK_VERSION}")/$(json_escape "${VULKAN_SDK_LAYOUT_ARCH}")"
  },
  "built": "${utc_now}"
}
EOF_PROFILE

tar -cJf "${artifact_path}" -C "${wcp_root}" .

artifact_sha="$(sha256_file "${artifact_path}")"
cat > "${sha_file}" <<EOF_SHA
${artifact_sha}  ${WCP_ARTIFACT_NAME}
EOF_SHA

cat > "${release_notes}" <<EOF_NOTES
Vulkan SDK ${VULKAN_SDK_LAYOUT_ARCH} Contents package

RU:
- Канал: stable (${WCP_RELEASE_TAG})
- Тип в Winlator Contents: ${WCP_DISPLAY_CATEGORY}
- Установка: отдельный installable package через Contents
- Архитектура: ${VULKAN_SDK_LAYOUT_ARCH}
- Лэйаут: share/vulkan-sdk/${VK_SDK_VERSION}/${VULKAN_SDK_LAYOUT_ARCH}

EN:
- Channel: stable (${WCP_RELEASE_TAG})
- Winlator Contents type: ${WCP_DISPLAY_CATEGORY}
- Delivery: standalone installable package via Contents
- Arch: ${VULKAN_SDK_LAYOUT_ARCH}
- Layout: share/vulkan-sdk/${VK_SDK_VERSION}/${VULKAN_SDK_LAYOUT_ARCH}

Commit: ${GITHUB_SHA:-local}
EOF_NOTES

cat > "${metadata_path}" <<EOF_METADATA
VK_SDK_VERSION=${VK_SDK_VERSION}
WCP_NAME=${WCP_NAME}
WCP_RELEASE_TAG=${WCP_RELEASE_TAG}
WCP_ARTIFACT_NAME=${WCP_ARTIFACT_NAME}
WCP_ARTIFACT_PATH=${artifact_path}
WCP_SHA256_PATH=${sha_file}
WCP_RELEASE_NOTES=${release_notes}
EOF_METADATA

printf '[vulkan-sdk-wcp] version=%s artifact=%s\n' "${VK_SDK_VERSION}" "${artifact_path}"
