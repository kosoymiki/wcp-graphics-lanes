#!/usr/bin/env bash
set -eEuo pipefail

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/aedxvk-wcp-work}"

: "${DXVK_GPLASYNC_GIT_URL:=https://gitlab.com/Ph42oN/dxvk-gplasync.git}"
: "${DXVK_UPSTREAM_GIT_URL:=https://github.com/doitsujin/dxvk.git}"
: "${AEDXVK_VERSION_NAME:=2.7.1-1-gplasync}"
: "${AEDXVK_VERSION_CODE:=1}"
: "${AEDXVK_CHANNEL:=stable}"
: "${AEDXVK_DELIVERY:=remote}"
: "${AEDXVK_FLAVOR:=generic}"
: "${AEDXVK_SOURCE_REPO:=${GITHUB_REPOSITORY:-kosoymiki/winlator-wine-proton-arm64ec-wcp}}"
: "${AEDXVK_RELEASE_TAG:=dxvk-gplasync-latest}"
: "${AEDXVK_ARTIFACT_NAME:=dxvk-gplasync.wcp}"
: "${AEDXVK_SHA256_ARTIFACT_NAME:=SHA256SUMS-dxvk-gplasync.txt}"
: "${AEDXVK_RELEASE_NOTES_NAME:=RELEASE_NOTES-dxvk-gplasync.md}"
: "${AEDXVK_PROFILE_NAME:=AeDXVK GPLAsync}"
: "${AEDXVK_PROFILE_DESCRIPTION:=AeDXVK GPLAsync source-built package}"

trap 'ec=$?; printf "[aedxvk][error] command failed (exit=%s) at line %s: %s\n" "${ec}" "${LINENO}" "${BASH_COMMAND}" >&2' ERR

git_clone_retry() {
  local attempt
  for attempt in 1 2 3; do
    if git clone "$@"; then
      return 0
    fi
    if [[ "${attempt}" -lt 3 ]]; then
      printf '[aedxvk][warn] git clone attempt %s/3 failed, retrying...\n' "${attempt}" >&2
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

resolve_latest_tag() {
  local remote="${1:?remote required}"
  local pattern="${2:-refs/tags/v*}"
  local tag
  tag="$(
    git ls-remote --tags --refs "${remote}" "${pattern}" \
      | sed 's#.*refs/tags/##' \
      | sort -V \
      | tail -n 1
  )"
  if [[ -z "${tag}" ]]; then
    printf '[aedxvk][error] unable to resolve latest tag from %s\n' "${remote}" >&2
    exit 1
  fi
  printf '%s' "${tag}"
}

mkdir -p "${OUT_DIR}" "${WORK_DIR}"
rm -rf "${WORK_DIR}/src" "${WORK_DIR}/build" "${WORK_DIR}/wcp-root"

src_dir="${WORK_DIR}/src"
build_dir="${WORK_DIR}/build"
wcp_root="${WORK_DIR}/wcp-root"
stage_dir="${wcp_root}/payload"
mkdir -p "${build_dir}" "${stage_dir}/x64" "${stage_dir}/x32"

resolved_tag="$(resolve_latest_tag "${DXVK_UPSTREAM_GIT_URL}" 'refs/tags/v*')"
selected_repo="${DXVK_GPLASYNC_GIT_URL}"

git_clone_retry --depth 1 --recursive --shallow-submodules "${DXVK_GPLASYNC_GIT_URL}" "${src_dir}"

if [[ ! -x "${src_dir}/package-release.sh" ]]; then
  printf '[aedxvk][warn] package-release.sh missing in GPLAsync checkout, falling back to upstream tag %s\n' "${resolved_tag}" >&2
  rm -rf "${src_dir}"
  git_clone_retry --depth 1 --branch "${resolved_tag}" --recursive --shallow-submodules "${DXVK_UPSTREAM_GIT_URL}" "${src_dir}"
  selected_repo="${DXVK_UPSTREAM_GIT_URL}"
fi

if [[ ! -x "${src_dir}/package-release.sh" ]]; then
  printf '[aedxvk][error] package-release.sh missing in selected source checkout\n' >&2
  exit 1
fi

resolved_commit="$(git -C "${src_dir}" rev-parse HEAD)"
resolved_short="${resolved_commit:0:12}"

(cd "${src_dir}" && ./package-release.sh "${AEDXVK_VERSION_NAME}" "${build_dir}" --no-package)

package_root="$(find "${build_dir}" -mindepth 1 -maxdepth 1 -type d -name 'dxvk-*' | LC_ALL=C sort | head -n 1)"
if [[ -z "${package_root}" || ! -d "${package_root}" ]]; then
  printf '[aedxvk][error] built package root not found under %s\n' "${build_dir}" >&2
  exit 1
fi

required_dlls=(d3d8.dll d3d9.dll d3d10.dll d3d10_1.dll d3d10core.dll d3d11.dll dxgi.dll)
for dll in "${required_dlls[@]}"; do
  [[ -f "${package_root}/x64/${dll}" ]] || { printf '[aedxvk][error] missing x64/%s\n' "${dll}" >&2; exit 1; }
  [[ -f "${package_root}/x32/${dll}" ]] || { printf '[aedxvk][error] missing x32/%s\n' "${dll}" >&2; exit 1; }
done

cp -a "${package_root}/x64/." "${stage_dir}/x64/"
cp -a "${package_root}/x32/." "${stage_dir}/x32/"

files_json="$(
  first=1
  printf '['
  for dll in "${required_dlls[@]}"; do
    if [[ ${first} -eq 0 ]]; then
      printf ','
    fi
    printf '\n    {"source": "payload/x64/%s", "target": "${system32}/%s"},' "${dll}" "${dll}"
    printf '\n    {"source": "payload/x32/%s", "target": "${syswow64}/%s"}' "${dll}" "${dll}"
    first=0
  done
  printf '\n  ]'
)"

cat > "${wcp_root}/dxvk-source.json" <<EOF_SOURCE
{
  "lane": "AeDXVKGPLAsync",
  "packageVersion": "$(json_escape "${AEDXVK_VERSION_NAME}")",
  "packageFlavor": "$(json_escape "${AEDXVK_FLAVOR}")",
  "upstreamRepo": "$(json_escape "${selected_repo}")",
  "resolvedSourceCommit": "$(json_escape "${resolved_commit}")",
  "resolvedSourceShort": "$(json_escape "${resolved_short}")",
  "resolvedUpstreamStableTag": "$(json_escape "${resolved_tag}")",
  "upstreamStableRepo": "$(json_escape "${DXVK_UPSTREAM_GIT_URL}")",
  "trackingMode": "head-exact",
  "gplasyncMode": "source-built",
  "buildToolchain": "mingw-w64",
  "sourceBuild": "1",
  "runtimeTarget": "$(json_escape "${AEDXVK_FLAVOR}")"
}
EOF_SOURCE

cat > "${wcp_root}/profile.json" <<EOF_PROFILE
{
  "type": "DXVK",
  "name": "$(json_escape "${AEDXVK_PROFILE_NAME}")",
  "versionName": "$(json_escape "${AEDXVK_VERSION_NAME}")",
  "versionCode": ${AEDXVK_VERSION_CODE},
  "description": "$(json_escape "${AEDXVK_PROFILE_DESCRIPTION}")",
  "channel": "$(json_escape "${AEDXVK_CHANNEL}")",
  "delivery": "$(json_escape "${AEDXVK_DELIVERY}")",
  "displayCategory": "DXVK",
  "sourceRepo": "$(json_escape "${AEDXVK_SOURCE_REPO}")",
  "sourceType": "github-release",
  "sourceVersion": "rolling-latest",
  "releaseTag": "$(json_escape "${AEDXVK_RELEASE_TAG}")",
  "artifactName": "$(json_escape "${AEDXVK_ARTIFACT_NAME}")",
  "sha256Url": "https://github.com/$(json_escape "${AEDXVK_SOURCE_REPO}")/releases/download/$(json_escape "${AEDXVK_RELEASE_TAG}")/$(json_escape "${AEDXVK_SHA256_ARTIFACT_NAME}")",
  "files": ${files_json},
  "dxvkSource": {
    "resolvedSourceCommit": "$(json_escape "${resolved_commit}")",
    "resolvedSourceShort": "$(json_escape "${resolved_short}")",
    "resolvedUpstreamStableTag": "$(json_escape "${resolved_tag}")",
    "runtimeTarget": "$(json_escape "${AEDXVK_FLAVOR}")",
    "sourceBuild": true
  }
}
EOF_PROFILE

artifact_path="${OUT_DIR}/${AEDXVK_ARTIFACT_NAME}"
sha_path="${OUT_DIR}/${AEDXVK_SHA256_ARTIFACT_NAME}"
release_notes="${OUT_DIR}/${AEDXVK_RELEASE_NOTES_NAME}"
metadata_path="${OUT_DIR}/aedxvk-metadata.env"

rm -f "${artifact_path}" "${sha_path}" "${release_notes}" "${metadata_path}"
tar -cJf "${artifact_path}" -C "${wcp_root}" .

artifact_sha="$(sha256_file "${artifact_path}")"
cat > "${sha_path}" <<EOF_SHA
${artifact_sha}  ${AEDXVK_ARTIFACT_NAME}
EOF_SHA

cat > "${release_notes}" <<EOF_NOTES
AeDXVK GPLAsync source-built package

RU:
- Формат: WCP, ставится через Winlator Contents
- Источник: ${selected_repo}
- Exact commit: ${resolved_commit}
- Ближайший upstream stable tag: ${resolved_tag}
- Runtime target: ${AEDXVK_FLAVOR}

EN:
- Format: WCP, installable via Winlator Contents
- Source: ${selected_repo}
- Exact commit: ${resolved_commit}
- Nearest upstream stable tag: ${resolved_tag}
- Runtime target: ${AEDXVK_FLAVOR}

Commit: ${GITHUB_SHA:-local}
EOF_NOTES

cat > "${metadata_path}" <<EOF_META
AEDXVK_RESOLVED_COMMIT=${resolved_commit}
AEDXVK_RESOLVED_TAG=${resolved_tag}
AEDXVK_ARTIFACT_PATH=${artifact_path}
AEDXVK_ARTIFACT_NAME=${AEDXVK_ARTIFACT_NAME}
AEDXVK_SHA256_PATH=${sha_path}
AEDXVK_RELEASE_NOTES=${release_notes}
EOF_META

printf '[aedxvk] flavor=%s commit=%s artifact=%s\n' \
  "${AEDXVK_FLAVOR}" "${resolved_short}" "${artifact_path}"
