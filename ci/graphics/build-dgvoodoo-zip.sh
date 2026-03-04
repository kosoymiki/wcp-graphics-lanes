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
: "${DGVOODOO_FREEWINE_LANE:=freewine11-arm64ec}"
: "${DGVOODOO_PROXY_ENABLE:=1}"
: "${DGVOODOO_PROXY_MODE:=core}"
: "${DGVOODOO_PROXY_CORE_DLLS:=D3D8.dll D3D9.dll DDraw.dll D3DImm.dll}"
: "${DGVOODOO_PROXY_CC_X86:=i686-w64-mingw32-gcc}"
: "${DGVOODOO_PROXY_CC_X64:=x86_64-w64-mingw32-gcc}"

require_cmd() {
  local cmd="${1:?command required}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf '[dgvoodoo][error] required command missing: %s\n' "${cmd}" >&2
    exit 1
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

extract_export_names() {
  local dll_path="${1:?dll path required}"
  objdump -p "${dll_path}" | awk '
    BEGIN { in_table=0; seen=0; }
    /^\[Ordinal\/Name Pointer\] Table/ { in_table=1; next; }
    in_table == 1 {
      if ($0 ~ /^[[:space:]]*$/) {
        if (seen) exit;
        next;
      }
      if ($0 ~ /^[[:space:]]*\[[[:space:]]*[0-9]+]/) {
        name=$NF;
        if (name != "<none>" && name != "") {
          print name;
          seen=1;
        }
        next;
      }
      if (seen) exit;
    }
  '
}

should_proxy_dll() {
  local dll_name="${1:?dll name required}"
  local mode="${2:?proxy mode required}"
  if [[ "${mode}" == "all" ]]; then
    return 0
  fi
  local normalized="${dll_name,,}"
  local candidate
  for candidate in ${DGVOODOO_PROXY_CORE_DLLS}; do
    if [[ "${normalized}" == "${candidate,,}" ]]; then
      return 0
    fi
  done
  return 1
}

build_forwarder_proxy() {
  local dll_path="${1:?dll path required}"
  local arch="${2:?arch required}"
  local work_proxy_dir="${3:?work proxy dir required}"
  local proxy_map_tsv="${4:?proxy map tsv required}"

  local cc
  case "${arch}" in
    x86) cc="${DGVOODOO_PROXY_CC_X86}" ;;
    x64) cc="${DGVOODOO_PROXY_CC_X64}" ;;
    *)
      printf '[dgvoodoo][error] unsupported arch for proxy build: %s\n' "${arch}" >&2
      return 1
      ;;
  esac

  local logical_dll logical_module real_module real_dll real_path def_path dummy_c
  logical_dll="$(basename -- "${dll_path}")"
  logical_module="${logical_dll%.*}"
  real_module="${logical_module}_dgvoodoo"
  real_dll="${real_module}.dll"
  real_path="$(dirname -- "${dll_path}")/${real_dll}"
  def_path="${work_proxy_dir}/${arch}/${logical_module}.def"
  dummy_c="${work_proxy_dir}/proxy_dummy.c"

  mkdir -p "$(dirname -- "${def_path}")"

  mv -f "${dll_path}" "${real_path}"

  mapfile -t exports < <(extract_export_names "${real_path}")
  if [[ "${#exports[@]}" -eq 0 ]]; then
    printf '[dgvoodoo][warn] %s has no named exports, proxy skipped\n' "${logical_dll}" >&2
    mv -f "${real_path}" "${dll_path}"
    return 0
  fi

  {
    printf 'LIBRARY %s\n' "${logical_dll}"
    printf 'EXPORTS\n'
    declare -A seen=()
    local symbol
    for symbol in "${exports[@]}"; do
      [[ -n "${symbol}" ]] || continue
      if [[ -n "${seen[${symbol}]+x}" ]]; then
        continue
      fi
      seen["${symbol}"]=1
      printf '  %s=%s.%s\n' "${symbol}" "${real_module}" "${symbol}"
    done
  } > "${def_path}"

  cat > "${dummy_c}" <<'EOF_DUMMY'
#include <windows.h>
BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpReserved) {
  (void)hinstDLL;
  (void)fdwReason;
  (void)lpReserved;
  return TRUE;
}
EOF_DUMMY

  if ! "${cc}" -shared -s -o "${dll_path}" "${dummy_c}" "${def_path}"; then
    printf '[dgvoodoo][error] failed to build proxy DLL: %s (%s)\n' "${logical_dll}" "${arch}" >&2
    mv -f "${real_path}" "${dll_path}"
    return 1
  fi

  printf '%s\t%s\t%s\t%s\n' "${arch}" "${logical_dll}" "${real_dll}" "${#exports[@]}" >> "${proxy_map_tsv}"
}

mkdir -p "${OUT_DIR}" "${WORK_DIR}"
require_cmd curl
require_cmd jq
require_cmd unzip
require_cmd zip
require_cmd python3
require_cmd objdump

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
stage_root="${WORK_DIR}/stage"
proxy_work="${WORK_DIR}/proxy-work"
proxy_map_tsv="${WORK_DIR}/proxy-map.tsv"
proxy_map_json="${stage_root}/ae-proxy-map.json"

curl -fsSL -o "${tmp_zip}" "${asset_url}"
if ! unzip -Z1 "${tmp_zip}" 2>/dev/null | grep -Eq '(^|/)MS/x86/'; then
  printf '[dgvoodoo][error] upstream ZIP does not contain MS/x86 runtime tree\n' >&2
  exit 1
fi

rm -rf "${stage_root}" "${proxy_work}"
mkdir -p "${stage_root}" "${proxy_work}"
unzip -q "${tmp_zip}" -d "${stage_root}"

proxy_count=0
if [[ "${DGVOODOO_PROXY_ENABLE}" == "1" ]]; then
  require_cmd "${DGVOODOO_PROXY_CC_X86}"
  require_cmd "${DGVOODOO_PROXY_CC_X64}"
  : > "${proxy_map_tsv}"
  for arch in x86 x64; do
    runtime_dir="$(find "${stage_root}" -type d -path "*/MS/${arch}" | LC_ALL=C sort | head -n 1)"
    if [[ -z "${runtime_dir}" || ! -d "${runtime_dir}" ]]; then
      printf '[dgvoodoo][warn] runtime dir missing for %s\n' "${arch}" >&2
      continue
    fi
    while IFS= read -r dll_path; do
      [[ -f "${dll_path}" ]] || continue
      dll_name="$(basename -- "${dll_path}")"
      if ! should_proxy_dll "${dll_name}" "${DGVOODOO_PROXY_MODE}"; then
        continue
      fi
      build_forwarder_proxy "${dll_path}" "${arch}" "${proxy_work}" "${proxy_map_tsv}"
    done < <(find "${runtime_dir}" -maxdepth 1 -type f -iname '*.dll' | LC_ALL=C sort)
  done

  python3 - <<'PY' "${proxy_map_tsv}" "${proxy_map_json}" "${DGVOODOO_PROXY_MODE}"
import json
import pathlib
import sys

tsv_path = pathlib.Path(sys.argv[1])
json_path = pathlib.Path(sys.argv[2])
mode = sys.argv[3]
rows = []
if tsv_path.is_file():
    for line in tsv_path.read_text(encoding="utf-8").splitlines():
        parts = line.strip().split("\t")
        if len(parts) != 4:
            continue
        arch, dll_name, backend_dll, export_count = parts
        rows.append(
            {
                "arch": arch,
                "dll": dll_name,
                "backendDll": backend_dll,
                "exportCount": int(export_count),
            }
        )
payload = {
    "schemaVersion": 1,
    "proxyEngine": "export-forwarder",
    "proxyMode": mode,
    "proxies": rows,
}
json_path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
print(len(rows))
PY
  proxy_count="$(python3 - <<'PY' "${proxy_map_json}"
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
if not path.is_file():
    print(0)
    raise SystemExit(0)
payload = json.loads(path.read_text(encoding="utf-8"))
print(len(payload.get("proxies", [])))
PY
)"
else
  cat > "${proxy_map_json}" <<EOF_PROXY
{
  "schemaVersion": 1,
  "proxyEngine": "disabled",
  "proxyMode": "none",
  "proxies": []
}
EOF_PROXY
fi

meta_dir="${WORK_DIR}/meta"
mkdir -p "${meta_dir}"

cat > "${meta_dir}/ae-runtime-contract.json" <<EOF_RUNTIME
{
  "schemaVersion": 2,
  "lane": "dgvoodoo-latest",
  "role": "translation-layer",
  "freewineLane": "${DGVOODOO_FREEWINE_LANE}",
  "providerLanes": ["turnip-vulkan", "freedreno-opengl"],
  "translationLayers": ["dxvk", "vkd3d-proton", "dgvoodoo", "wined3d"],
  "proxyEngine": "export-forwarder",
  "forensic": {
    "requiredEnvPrefixes": ["AERO_DGVOODOO_", "AERO_DGVOODOO_PROXY_", "AERO_DXVK_", "AERO_WINE_"],
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
  }
}
EOF_RUNTIME

cat > "${meta_dir}/aero-source.json" <<EOF_SOURCE
{
  "lane": "dgvoodoo-latest",
  "upstreamTag": "${upstream_tag}",
  "upstreamAsset": "${asset_name}",
  "upstreamReleaseUrl": "${release_url}",
  "trackingMode": "latest-release-api+proxy-overlay",
  "proxyMode": "$(printf '%s' "${DGVOODOO_PROXY_MODE}")",
  "proxyEnabled": "$(printf '%s' "${DGVOODOO_PROXY_ENABLE}")",
  "proxyDllCount": ${proxy_count},
  "forensicLinked": true
}
EOF_SOURCE

cp -f "${meta_dir}/ae-runtime-contract.json" "${stage_root}/ae-runtime-contract.json"
cp -f "${meta_dir}/aero-source.json" "${stage_root}/aero-source.json"

rm -f "${artifact_path}"
(
  cd "${stage_root}"
  zip -qr "${artifact_path}" .
)

artifact_sha="$(sha256_file "${artifact_path}")"
cat > "${sha_path}" <<EOF_SHA
${artifact_sha}  ${DGVOODOO_ARTIFACT_NAME}
EOF_SHA

cat > "${release_notes}" <<EOF_NOTES
dgVoodoo latest ZIP mirror

RU:
- Формат: upstream ZIP + AE proxy overlay, ставится через Winlator Contents
- Upstream tag: ${upstream_tag}
- Upstream asset: ${asset_name}
- Upstream release: ${release_url}
- Proxy mode: ${DGVOODOO_PROXY_MODE}
- Proxy DLL count: ${proxy_count}

EN:
- Format: upstream ZIP + AE proxy overlay, installable via Winlator Contents
- Upstream tag: ${upstream_tag}
- Upstream asset: ${asset_name}
- Upstream release: ${release_url}
- Proxy mode: ${DGVOODOO_PROXY_MODE}
- Proxy DLL count: ${proxy_count}

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
DGVOODOO_PROXY_ENABLED=${DGVOODOO_PROXY_ENABLE}
DGVOODOO_PROXY_MODE=${DGVOODOO_PROXY_MODE}
DGVOODOO_PROXY_DLL_COUNT=${proxy_count}
EOF_META

printf '[dgvoodoo] upstream=%s proxy_mode=%s proxy_count=%s artifact=%s\n' \
  "${upstream_tag}" "${DGVOODOO_PROXY_MODE}" "${proxy_count}" "${artifact_path}"
