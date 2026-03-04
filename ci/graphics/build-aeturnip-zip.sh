#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/ci/graphics/common-mesa.sh"

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/aeturnip-zip-work}"

: "${AETURNIP_VERSION_NAME:=rolling-arm64}"
: "${AETURNIP_VERSION_CODE:=0}"
: "${AETURNIP_CHANNEL:=stable}"
: "${AETURNIP_DELIVERY:=remote}"
: "${AETURNIP_SOURCE_REPO:=${GITHUB_REPOSITORY:-kosoymiki/winlator-wine-proton-arm64ec-wcp}}"
: "${AETURNIP_RELEASE_TAG:=aeturnip-arm64-latest}"
: "${AETURNIP_ARTIFACT_NAME:=aeturnip-arm64.zip}"
: "${AETURNIP_SHA256_ARTIFACT_NAME:=SHA256SUMS-aeturnip-arm64.txt}"
: "${AETURNIP_RELEASE_NOTES_NAME:=RELEASE_NOTES-aeturnip.md}"

mkdir -p "${OUT_DIR}" "${WORK_DIR}"
rm -rf "${WORK_DIR}/extract" "${WORK_DIR}/normalized"
mkdir -p "${WORK_DIR}/extract" "${WORK_DIR}/normalized"

MESA_STABLE_VERSION="${MESA_STABLE_VERSION:-$(resolve_latest_mesa_version)}"
MESA_STABLE_TAG="mesa-${MESA_STABLE_VERSION}"
MESA_MAIN_COMMIT="${MESA_MAIN_COMMIT:-$(resolve_latest_mesa_main_head)}"
MESA_MAIN_SHORT="${MESA_MAIN_COMMIT:0:12}"
MESA_VERSION_ID="${MESA_STABLE_VERSION}-main-${MESA_MAIN_SHORT}"
MESA_ARCHIVE_URL="${MESA_ARCHIVE_URL:-$(mesa_commit_archive_url "${MESA_MAIN_COMMIT}")}"

selected_provider=""
selected_repo=""
selected_release_tag=""
selected_asset_name=""
selected_asset_url=""
selected_release_url=""
selected_zip="${WORK_DIR}/selected-turnip.zip"

while IFS='|' read -r provider repo api_url; do
  [[ -n "${provider}" ]] || continue
  release_rows="$(curl -fsSL "${api_url}" | jq -r '
    .[] | select(.draft | not) |
    .tag_name as $tag |
    .html_url as $release_url |
    .assets[]? |
    select((.name | ascii_downcase | endswith(".zip")) and (.browser_download_url | ascii_downcase | endswith(".zip"))) |
    [$tag, .name, .browser_download_url, $release_url] | @tsv
  ')" || continue

  while IFS=$'\t' read -r release_tag asset_name asset_url release_url; do
    [[ -n "${asset_url}" ]] || continue
    rm -f "${selected_zip}"
    if ! curl -fsSL -o "${selected_zip}" "${asset_url}"; then
      continue
    fi
    if unzip -Z1 "${selected_zip}" 2>/dev/null | grep -Eq '(^|/)meta\.json$'; then
      selected_provider="${provider}"
      selected_repo="${repo}"
      selected_release_tag="${release_tag}"
      selected_asset_name="${asset_name}"
      selected_asset_url="${asset_url}"
      selected_release_url="${release_url}"
      break 2
    fi
  done <<< "${release_rows}"
done <<'EOF_DONORS'
aeturnip|StevenMXZ/freedreno_turnip-CI|https://api.github.com/repos/StevenMXZ/freedreno_turnip-CI/releases?per_page=12
whitebelyash|whitebelyash/freedreno_turnip-CI|https://api.github.com/repos/whitebelyash/freedreno_turnip-CI/releases?per_page=12
weabchan|Weab-chan/freedreno_turnip-CI|https://api.github.com/repos/Weab-chan/freedreno_turnip-CI/releases?per_page=12
mrpurple|MrPurple666/purple-turnip|https://api.github.com/repos/MrPurple666/purple-turnip/releases?per_page=12
EOF_DONORS

if [[ -z "${selected_asset_url}" || ! -f "${selected_zip}" ]]; then
  printf '[aeturnip][error] unable to find a valid independent Turnip ZIP release\n' >&2
  exit 1
fi

unzip -q "${selected_zip}" -d "${WORK_DIR}/extract"
package_root="$(find "${WORK_DIR}/extract" -name meta.json -printf '%h\n' | LC_ALL=C sort | head -n 1)"
if [[ -z "${package_root}" || ! -f "${package_root}/meta.json" ]]; then
  printf '[aeturnip][error] extracted donor archive does not contain meta.json\n' >&2
  exit 1
fi

cp -a "${package_root}/." "${WORK_DIR}/normalized/"

python3 - <<'PY' "${WORK_DIR}/normalized/meta.json" "${AETURNIP_VERSION_NAME}" "${selected_provider}" "${selected_repo}" "${selected_release_tag}" "${selected_asset_name}" "${selected_asset_url}" "${MESA_VERSION_ID}" "${MESA_ARCHIVE_URL}"
import json
import pathlib
import sys

meta_path = pathlib.Path(sys.argv[1])
version_name = sys.argv[2]
provider = sys.argv[3]
repo = sys.argv[4]
release_tag = sys.argv[5]
asset_name = sys.argv[6]
asset_url = sys.argv[7]
mesa_version = sys.argv[8]
mesa_archive_url = sys.argv[9]

payload = json.loads(meta_path.read_text(encoding="utf-8"))
payload["name"] = version_name
payload["provider"] = "aeturnip"
payload["channel"] = "stable"
payload["sourceRepo"] = repo
payload["sourceReleaseTag"] = release_tag
payload["sourceAsset"] = asset_name
payload["sourceUrl"] = asset_url
payload["mesaVersion"] = mesa_version
payload["mesaSourceUrl"] = mesa_archive_url
driver_version = str(payload.get("driverVersion", "")).strip()
if not driver_version:
    payload["driverVersion"] = mesa_version
description = str(payload.get("description", "")).strip()
prefix = f"AeTurnip independent lane via {provider}/{release_tag}"
payload["description"] = f"{prefix}; {description}" if description else f"{prefix}; rolling Mesa-linked independent package"
author = str(payload.get("author", "")).strip()
payload["author"] = f"{author} | AeTurnip curation" if author else "AeTurnip curation"
meta_path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
PY

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
  "payloadMode": "independent-turnip-zip",
  "selectedProvider": "$(json_escape "${selected_provider}")",
  "selectedRepo": "$(json_escape "${selected_repo}")",
  "selectedReleaseTag": "$(json_escape "${selected_release_tag}")",
  "selectedAssetName": "$(json_escape "${selected_asset_name}")",
  "selectedAssetUrl": "$(json_escape "${selected_asset_url}")",
  "selectedReleaseUrl": "$(json_escape "${selected_release_url}")"
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
AeTurnip ARM64 independent ZIP driver

RU:
- Формат: adrenotools ZIP, ставится через Winlator Contents
- Payload source: независимый ZIP-релиз ${selected_repo} / ${selected_release_tag}
- Выбранный asset: ${selected_asset_name}
- Mesa exact main ref: ${MESA_MAIN_COMMIT}
- Mesa nearest stable tag: ${MESA_STABLE_TAG}
- Mesa archive: ${MESA_ARCHIVE_URL}

EN:
- Format: adrenotools ZIP, installable via Winlator Contents
- Payload source: independent ZIP release ${selected_repo} / ${selected_release_tag}
- Selected asset: ${selected_asset_name}
- Mesa exact main ref: ${MESA_MAIN_COMMIT}
- Mesa nearest stable tag: ${MESA_STABLE_TAG}
- Mesa archive: ${MESA_ARCHIVE_URL}

Commit: ${GITHUB_SHA:-local}
EOF_NOTES

cat > "${metadata_path}" <<EOF_META
MESA_STABLE_VERSION=${MESA_STABLE_VERSION}
MESA_MAIN_COMMIT=${MESA_MAIN_COMMIT}
AETURNIP_ARTIFACT_PATH=${artifact_path}
AETURNIP_ARTIFACT_NAME=${AETURNIP_ARTIFACT_NAME}
AETURNIP_SHA256_PATH=${sha_path}
AETURNIP_RELEASE_NOTES=${release_notes}
AETURNIP_SELECTED_PROVIDER=${selected_provider}
AETURNIP_SELECTED_REPO=${selected_repo}
AETURNIP_SELECTED_RELEASE_TAG=${selected_release_tag}
AETURNIP_SELECTED_ASSET_NAME=${selected_asset_name}
EOF_META

printf '[aeturnip] mesa=%s provider=%s repo=%s release=%s asset=%s artifact=%s\n' \
  "${MESA_MAIN_SHORT}" "${selected_provider}" "${selected_repo}" "${selected_release_tag}" "${selected_asset_name}" "${artifact_path}"
