#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/vulkan-sdk-arm-work}"
ARTIFACT_PREFIX="${VULKAN_SDK_ARM_ARTIFACT_PREFIX:-vulkansdk-ubuntu-24.04-arm}"
SDK_URL="${VULKAN_SDK_ARM_SDK_URL:-${VULKAN_SDK_DOWNLOAD_URL:-https://sdk.lunarg.com/sdk/download/latest/linux/vulkan-sdk.tar.xz}}"
LATEST_JSON_URL="${VULKAN_SDK_LATEST_JSON_URL:-https://vulkan.lunarg.com/sdk/latest/linux.json}"

mkdir -p "${OUT_DIR}" "${WORK_DIR}"

VK_SDK_VERSION="${VK_SDK_VERSION:-$(curl -fsSL "${LATEST_JSON_URL}" | jq -r '.linux')}"
SDK_ARCHIVE="${WORK_DIR}/vulkan-sdk.tar.xz"
SDK_DIR="${WORK_DIR}/${VK_SDK_VERSION}"
ARTIFACT_NAME="${ARTIFACT_PREFIX}-${VK_SDK_VERSION}.tar.xz"
ARTIFACT_PATH="${OUT_DIR}/${ARTIFACT_NAME}"
METADATA_PATH="${OUT_DIR}/metadata.env"

curl -fsSL -o "${SDK_ARCHIVE}" "${SDK_URL}"
tar -xJf "${SDK_ARCHIVE}" -C "${WORK_DIR}"

if [[ ! -x "${SDK_DIR}/vulkansdk" ]]; then
  printf '[vulkan-sdk-arm][error] missing build entrypoint: %s\n' "${SDK_DIR}/vulkansdk" >&2
  exit 1
fi

(
  cd "${SDK_DIR}"
  ./vulkansdk --skip-deps --maxjobs \
    vulkan-loader \
    vulkan-validationlayers \
    vulkan-extensionlayer \
    vulkan-tools \
    shaderc
  rm -rf x86_64 source
)

tar -cJf "${ARTIFACT_PATH}" -C "${WORK_DIR}" "${VK_SDK_VERSION}"

cat > "${METADATA_PATH}" <<EOF
VK_SDK_VERSION=${VK_SDK_VERSION}
ARTIFACT_NAME=${ARTIFACT_NAME}
ARTIFACT_PATH=${ARTIFACT_PATH}
EOF

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'vk_sdk_version=%s\n' "${VK_SDK_VERSION}"
    printf 'artifact_name=%s\n' "${ARTIFACT_NAME}"
    printf 'artifact_path=%s\n' "${ARTIFACT_PATH}"
  } >> "${GITHUB_OUTPUT}"
fi

printf '[vulkan-sdk-arm] version=%s artifact=%s\n' "${VK_SDK_VERSION}" "${ARTIFACT_PATH}"
