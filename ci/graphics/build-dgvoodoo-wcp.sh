#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-$PWD/out}"
WORK_DIR="${2:-/tmp/dgvoodoo-wcp-work}"

: "${DGVOODOO_LATEST_RELEASE_API:=https://api.github.com/repos/dege-diosg/dgVoodoo2/releases/latest}"
: "${DGVOODOO_VERSION_NAME:=}"
: "${DGVOODOO_VERSION_CODE:=1}"
: "${DGVOODOO_CHANNEL:=stable}"
: "${DGVOODOO_DELIVERY:=remote}"
: "${DGVOODOO_RELEASE_TAG:=dgvoodoo-latest}"
: "${DGVOODOO_ARTIFACT_NAME:=dgvoodoo.wcp}"
: "${DGVOODOO_SHA256_ARTIFACT_NAME:=SHA256SUMS-dgvoodoo.txt}"
: "${DGVOODOO_RELEASE_NOTES_NAME:=RELEASE_NOTES-dgvoodoo.md}"
: "${DGVOODOO_PROFILE_NAME:=Ae dgVoodoo}"
: "${DGVOODOO_PROFILE_DESCRIPTION:=Ae dgVoodoo upstream wrapper package}"
: "${DGVOODOO_SOURCE_REPO:=${GITHUB_REPOSITORY:-kosoymiki/wcp-runtime-lanes}}"
: "${DGVOODOO_SOURCE_TYPE:=github-release}"
: "${DGVOODOO_SOURCE_VERSION:=rolling-latest}"
: "${DGVOODOO_SOURCE_MODE:=auto}"
: "${DGVOODOO_LOCAL_ZIP:=}"
: "${DGVOODOO_UPSTREAM_ASSET_VARIANT:=dev64}"
: "${DGVOODOO_FREEWINE_LANE:=freewine11-arm64ec}"
: "${DGVOODOO_PROXY_ENABLE:=1}"
: "${DGVOODOO_PROXY_MODE:=core}"
: "${DGVOODOO_PROXY_CORE_DLLS:=D3D8.dll D3D9.dll DDraw.dll D3DImm.dll}"
: "${DGVOODOO_PROXY_CC_X86:=i686-w64-mingw32-gcc}"
: "${DGVOODOO_PROXY_CC_X64:=x86_64-w64-mingw32-gcc}"

trap 'ec=$?; printf "[dgvoodoo][error] command failed (exit=%s) at line %s: %s\n" "${ec}" "${LINENO}" "${BASH_COMMAND}" >&2' ERR

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

json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

normalize_lower() {
  local value="${1-}"
  printf '%s' "${value}" | tr '[:upper:]' '[:lower:]'
}

resolve_asset_version_name() {
  local asset_name="${1:?asset name required}"
  python3 - "${asset_name}" <<'PY'
import pathlib
import re
import sys

name = pathlib.Path(sys.argv[1]).name
name_no_ext = re.sub(r'(?i)\.(zip|wcp|wcp\.xz|wcp\.zst)$', '', name)
match = re.search(r'dgVoodoo2_([0-9_]+)(?:_dev64)?', name_no_ext, re.IGNORECASE)
if match:
    version = match.group(1).replace('_', '.').strip('.')
    print(version if version else "local")
else:
    print("local")
PY
}

resolve_release_asset() {
  local release_json_path="${1:?release json required}"
  local variant="${2:?variant required}"
  python3 - "${release_json_path}" "${variant}" <<'PY'
import json
import pathlib
import re
import sys

release_json = pathlib.Path(sys.argv[1])
variant = (sys.argv[2] or "dev64").strip().lower()
payload = json.loads(release_json.read_text(encoding="utf-8"))

assets = []
for item in payload.get("assets", []):
    name = str(item.get("name", "")).strip()
    url = str(item.get("browser_download_url", "")).strip()
    if not name or not url:
        continue
    low = name.lower()
    if "_dbg" in low:
        continue
    if not re.match(r"^dgvoodoo2_[0-9_]+(?:_dev64)?\.zip$", low):
        continue
    assets.append((name, url))

dev64_assets = [entry for entry in assets if "_dev64" in entry[0].lower()]
full_assets = [entry for entry in assets if "_dev64" not in entry[0].lower()]

ordered = []
if variant in {"dev64", "auto", "dev64-first", ""}:
    ordered.extend(dev64_assets)
    ordered.extend(full_assets)
elif variant in {"full", "full-first", "legacy"}:
    ordered.extend(full_assets)
    ordered.extend(dev64_assets)
elif variant in {"dev64-only"}:
    ordered.extend(dev64_assets)
elif variant in {"full-only"}:
    ordered.extend(full_assets)
else:
    ordered.extend(dev64_assets)
    ordered.extend(full_assets)

if not ordered:
    print("")
    print("")
    raise SystemExit(0)

name, url = ordered[0]
print(name)
print(url)
PY
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
      printf '[dgvoodoo][warn] unsupported arch for proxy build: %s\n' "${arch}" >&2
      return 0
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

resolve_runtime_dir() {
  local package_root="${1:?package root required}"
  local arch="${2:?arch required}"

  local direct="${package_root}/MS/${arch}"
  if [[ -d "${direct}" ]]; then
    printf '%s' "${direct}"
    return 0
  fi

  local flat="${package_root}/${arch}"
  if [[ -d "${flat}" ]]; then
    printf '%s' "${flat}"
    return 0
  fi

  if [[ "${arch}" == "arm64ec" ]]; then
    local alt1="${package_root}/MS/arm64-ec"
    local alt2="${package_root}/arm64-ec"
    [[ -d "${alt1}" ]] && { printf '%s' "${alt1}"; return 0; }
    [[ -d "${alt2}" ]] && { printf '%s' "${alt2}"; return 0; }
  fi

  return 1
}

has_any_runtime_arch() {
  local package_root="${1:?package root required}"
  local arch
  for arch in x86 x64 arm64 arm64ec; do
    if resolve_runtime_dir "${package_root}" "${arch}" >/dev/null; then
      return 0
    fi
  done
  return 1
}

find_package_root() {
  local extracted_root="${1:?extracted root required}"
  if has_any_runtime_arch "${extracted_root}"; then
    printf '%s' "${extracted_root}"
    return 0
  fi

  local dir
  while IFS= read -r -d '' dir; do
    if has_any_runtime_arch "${dir}"; then
      printf '%s' "${dir}"
      return 0
    fi
  done < <(find "${extracted_root}" -mindepth 1 -type d -print0 | LC_ALL=C sort -z)

  return 1
}

mkdir -p "${OUT_DIR}" "${WORK_DIR}"
require_cmd curl
require_cmd jq
require_cmd unzip
require_cmd tar
require_cmd python3
require_cmd objdump

release_json="${WORK_DIR}/release.json"
source_mode="$(normalize_lower "${DGVOODOO_SOURCE_MODE}")"
if [[ -n "${DGVOODOO_LOCAL_ZIP}" ]]; then
  source_mode="local"
fi

case "${source_mode}" in
  "" | "auto" | "upstream" | "local") ;;
  *)
    printf '[dgvoodoo][error] unsupported DGVOODOO_SOURCE_MODE: %s\n' "${DGVOODOO_SOURCE_MODE}" >&2
    exit 1
    ;;
esac

asset_name=""
asset_url=""
release_url=""
upstream_tag=""
version_name=""
tracking_mode="latest-release-api+proxy-overlay"

if [[ "${source_mode}" == "local" ]]; then
  [[ -n "${DGVOODOO_LOCAL_ZIP}" ]] || {
    printf '[dgvoodoo][error] DGVOODOO_SOURCE_MODE=local requires DGVOODOO_LOCAL_ZIP\n' >&2
    exit 1
  }
  [[ -f "${DGVOODOO_LOCAL_ZIP}" ]] || {
    printf '[dgvoodoo][error] local dgVoodoo archive not found: %s\n' "${DGVOODOO_LOCAL_ZIP}" >&2
    exit 1
  }

  asset_name="$(basename -- "${DGVOODOO_LOCAL_ZIP}")"
  asset_url="file://${DGVOODOO_LOCAL_ZIP}"
  release_url="${asset_url}"
  version_name="$(resolve_asset_version_name "${asset_name}")"
  upstream_tag="local-v${version_name}"
  tracking_mode="local-zip+proxy-overlay"

  tmp_zip="${WORK_DIR}/${asset_name}"
  cp -f "${DGVOODOO_LOCAL_ZIP}" "${tmp_zip}"
else
  curl -fsSL -o "${release_json}" "${DGVOODOO_LATEST_RELEASE_API}"
  upstream_tag="$(jq -r '.tag_name // ""' "${release_json}")"
  release_url="$(jq -r '.html_url // ""' "${release_json}")"

  mapfile -t resolved_asset < <(resolve_release_asset "${release_json}" "${DGVOODOO_UPSTREAM_ASSET_VARIANT}")
  asset_name="${resolved_asset[0]:-}"
  asset_url="${resolved_asset[1]:-}"
  version_name="${upstream_tag#v}"

  if [[ -z "${upstream_tag}" || -z "${asset_name}" || -z "${asset_url}" || -z "${version_name}" ]]; then
    printf '[dgvoodoo][error] unable to resolve upstream release asset (variant=%s)\n' "${DGVOODOO_UPSTREAM_ASSET_VARIANT}" >&2
    exit 1
  fi

  tmp_zip="${WORK_DIR}/${asset_name}"
  curl -fsSL -o "${tmp_zip}" "${asset_url}"
fi

if [[ -n "${DGVOODOO_VERSION_NAME}" && "${DGVOODOO_VERSION_NAME}" != "${version_name}" ]]; then
  printf '[dgvoodoo][error] resolved version (%s) differs from pinned version (%s)\n' \
    "${version_name}" "${DGVOODOO_VERSION_NAME}" >&2
  exit 1
fi

extract_root="${WORK_DIR}/extract"
rm -rf "${extract_root}"
mkdir -p "${extract_root}"
unzip -q "${tmp_zip}" -d "${extract_root}"

package_root="$(find_package_root "${extract_root}")"
if [[ -z "${package_root}" || ! -d "${package_root}" ]]; then
  printf '[dgvoodoo][error] unable to locate dgVoodoo package root with runtime dirs\n' >&2
  exit 1
fi

proxy_work="${WORK_DIR}/proxy-work"
proxy_map_tsv="${WORK_DIR}/proxy-map.tsv"
proxy_map_json="${WORK_DIR}/ae-proxy-map.json"
rm -rf "${proxy_work}"
mkdir -p "${proxy_work}"
proxy_count=0

if [[ "${DGVOODOO_PROXY_ENABLE}" == "1" ]]; then
  require_cmd "${DGVOODOO_PROXY_CC_X86}"
  require_cmd "${DGVOODOO_PROXY_CC_X64}"
  : > "${proxy_map_tsv}"

  for arch in x86 x64 arm64 arm64ec; do
    runtime_dir="$(resolve_runtime_dir "${package_root}" "${arch}" || true)"
    if [[ -z "${runtime_dir}" || ! -d "${runtime_dir}" ]]; then
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
  cat > "${proxy_map_json}" <<'EOF_PROXY'
{
  "schemaVersion": 1,
  "proxyEngine": "disabled",
  "proxyMode": "none",
  "proxies": []
}
EOF_PROXY
fi

wcp_root="${WORK_DIR}/wcp-root"
payload_runtime="${wcp_root}/payload/runtime"
rm -rf "${wcp_root}"
mkdir -p "${payload_runtime}"
cp -a "${package_root}/." "${payload_runtime}/"
cp -f "${proxy_map_json}" "${wcp_root}/ae-proxy-map.json"

files_json="$(python3 - <<'PY' "${payload_runtime}"
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
entries = []
seen = set()

arch_targets = {
    "x86": "${syswow64}",
    "x64": "${system32}",
    "arm64": "${system32}",
    "arm64ec": "${system32}",
    "arm64-ec": "${system32}",
}

def add_runtime_dir(d: pathlib.Path, target_root: str) -> None:
    if not d.is_dir():
        return
    rel_dir = os.path.relpath(d, root).replace("\\", "/")
    for item in sorted(d.iterdir(), key=lambda p: p.name.lower()):
        if not item.is_file():
            continue
        low = item.name.lower()
        if not (low.endswith(".dll") or low.endswith(".exe")):
            continue
        source = f"payload/runtime/{rel_dir}/{item.name}"
        target = f"{target_root}/{item.name}"
        key = (source, target)
        if key in seen:
            continue
        seen.add(key)
        entries.append({"source": source, "target": target})

for arch, target_root in arch_targets.items():
    candidates = [root / "MS" / arch, root / arch]
    for candidate in candidates:
        add_runtime_dir(candidate, target_root)

for name in ("dgVoodoo.conf", "dgVoodooCpl.exe"):
    candidate = root / name
    if candidate.is_file():
        source = f"payload/runtime/{name}"
        target = f"${{system32}}/{name}"
        key = (source, target)
        if key not in seen:
            seen.add(key)
            entries.append({"source": source, "target": target})

print(json.dumps(entries, ensure_ascii=True, indent=2))
PY
)"

cat > "${wcp_root}/ae-runtime-wrapper.env" <<'EOF_WRAPPER'
# Aeolator runtime wrapper hints for dgVoodoo route selection.
AERO_GRAPHICS_WRAPPER_SCHEMA=1
AERO_GRAPHICS_WRAPPER_PROFILE=balanced
AERO_DX_WRAPPER_MODE=dgvoodoo
AERO_DGVOODOO_SELECTED=1
AERO_DGVOODOO_PROXY_ENGINE=export-forwarder
AERO_DGVOODOO_FALLBACK_ENGINE=wined3d
AERO_DGVOODOO_GLIDE_ROUTE=dgvoodoo
AERO_DGVOODOO_DDRAW_ROUTE=dgvoodoo
AERO_DGVOODOO_DX89_ROUTE=dgvoodoo
AERO_DGVOODOO_DX10PLUS_ROUTE=wined3d
EOF_WRAPPER

cat > "${wcp_root}/ae-runtime-contract.json" <<EOF_RUNTIME
{
  "schemaVersion": 2,
  "lane": "dgvoodoo-latest",
  "role": "translation-layer",
  "freewineLane": "$(json_escape "${DGVOODOO_FREEWINE_LANE}")",
  "providerLanes": ["turnip-vulkan", "freedreno-opengl"],
  "translationLayers": ["dgvoodoo", "wined3d", "dxvk", "vkd3d-proton"],
  "providerRoutePolicy": {
    "primary": "turnip-vulkan",
    "fallback": "freedreno-opengl",
    "fallbackReasonHint": "legacy-api-or-vulkan-incompatibility"
  },
  "legacyDxFallback": {
    "engine": "wined3d",
    "targetApis": ["d3d10", "d3d11", "d3d12"],
    "activationHint": "dgvoodoo-route-unavailable"
  },
  "wrapperContract": {
    "schemaVersion": 1,
    "defaultProfile": "balanced",
    "supportedProfiles": ["conservative", "balanced", "aggressive"],
    "profileEnv": {
      "conservative": {
        "AERO_DX_WRAPPER_MODE": "dgvoodoo",
        "AERO_DGVOODOO_SELECTED": "1",
        "AERO_DGVOODOO_PREF_ARCH": "x86",
        "AERO_DGVOODOO_FORCE_D3D11": "0",
        "AERO_DGVOODOO_VSYNC": "1",
        "AERO_DGVOODOO_FLIP_MODEL": "0"
      },
      "balanced": {
        "AERO_DX_WRAPPER_MODE": "dgvoodoo",
        "AERO_DGVOODOO_SELECTED": "1",
        "AERO_DGVOODOO_PREF_ARCH": "x64",
        "AERO_DGVOODOO_FORCE_D3D11": "0",
        "AERO_DGVOODOO_VSYNC": "0",
        "AERO_DGVOODOO_FLIP_MODEL": "1"
      },
      "aggressive": {
        "AERO_DX_WRAPPER_MODE": "dgvoodoo",
        "AERO_DGVOODOO_SELECTED": "1",
        "AERO_DGVOODOO_PREF_ARCH": "arm64ec",
        "AERO_DGVOODOO_FORCE_D3D11": "1",
        "AERO_DGVOODOO_VSYNC": "0",
        "AERO_DGVOODOO_FLIP_MODEL": "1"
      }
    },
    "routeHints": {
      "primaryProvider": "turnip-vulkan",
      "fallbackProvider": "freedreno-opengl",
      "legacyFallbackEngine": "dgvoodoo",
      "legacyTargetApis": ["ddraw", "d3d1", "d3d2", "d3d3", "d3d5", "d3d6", "d3d7", "glide", "d3d8", "d3d9"]
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
    "requiredEnvPrefixes": ["AERO_DGVOODOO_", "AERO_DXVK_", "AERO_VKD3D_", "AERO_WINE_"],
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
    "upstreamTag": "$(json_escape "${upstream_tag}")",
    "upstreamAsset": "$(json_escape "${asset_name}")",
    "proxyMode": "$(json_escape "${DGVOODOO_PROXY_MODE}")",
    "proxyDllCount": ${proxy_count}
  }
}
EOF_RUNTIME

cat > "${wcp_root}/aero-source.json" <<EOF_SOURCE
{
  "lane": "dgvoodoo-latest",
  "upstreamTag": "$(json_escape "${upstream_tag}")",
  "upstreamAsset": "$(json_escape "${asset_name}")",
  "upstreamReleaseUrl": "$(json_escape "${release_url}")",
  "trackingMode": "$(json_escape "${tracking_mode}")",
  "sourceMode": "$(json_escape "${source_mode}")",
  "upstreamAssetVariant": "$(json_escape "${DGVOODOO_UPSTREAM_ASSET_VARIANT}")",
  "proxyMode": "$(json_escape "${DGVOODOO_PROXY_MODE}")",
  "proxyEnabled": "$(json_escape "${DGVOODOO_PROXY_ENABLE}")",
  "proxyDllCount": ${proxy_count},
  "forensicLinked": true
}
EOF_SOURCE

cat > "${wcp_root}/profile.json" <<EOF_PROFILE
{
  "type": "DgVoodoo",
  "versionName": "$(json_escape "${version_name}")",
  "versionCode": ${DGVOODOO_VERSION_CODE},
  "name": "$(json_escape "${DGVOODOO_PROFILE_NAME}")",
  "description": "$(json_escape "${DGVOODOO_PROFILE_DESCRIPTION}")",
  "channel": "$(json_escape "${DGVOODOO_CHANNEL}")",
  "delivery": "$(json_escape "${DGVOODOO_DELIVERY}")",
  "displayCategory": "dgVoodoo",
  "sourceRepo": "$(json_escape "${DGVOODOO_SOURCE_REPO}")",
  "sourceType": "$(json_escape "${DGVOODOO_SOURCE_TYPE}")",
  "sourceVersion": "$(json_escape "${DGVOODOO_SOURCE_VERSION}")",
  "releaseTag": "$(json_escape "${DGVOODOO_RELEASE_TAG}")",
  "artifactName": "$(json_escape "${DGVOODOO_ARTIFACT_NAME}")",
  "sha256Url": "https://github.com/$(json_escape "${DGVOODOO_SOURCE_REPO}")/releases/download/$(json_escape "${DGVOODOO_RELEASE_TAG}")/$(json_escape "${DGVOODOO_SHA256_ARTIFACT_NAME}")",
  "files": ${files_json},
  "runtimeContract": {
    "schemaVersion": 2,
    "lane": "dgvoodoo-latest",
    "role": "translation-layer",
    "freewineLane": "$(json_escape "${DGVOODOO_FREEWINE_LANE}")",
    "providerLanes": ["turnip-vulkan", "freedreno-opengl"],
    "translationLayers": ["dgvoodoo", "wined3d", "dxvk", "vkd3d-proton"],
    "legacyDxFallback": {
      "engine": "wined3d",
      "targetApis": ["d3d10", "d3d11", "d3d12"],
      "activationHint": "dgvoodoo-route-unavailable"
    },
    "wrapperContract": {
      "schemaVersion": 1,
      "defaultProfile": "balanced",
      "supportedProfiles": ["conservative", "balanced", "aggressive"],
      "profileEnv": {
        "conservative": {
          "AERO_DX_WRAPPER_MODE": "dgvoodoo",
          "AERO_DGVOODOO_SELECTED": "1",
          "AERO_DGVOODOO_PREF_ARCH": "x86",
          "AERO_DGVOODOO_FORCE_D3D11": "0",
          "AERO_DGVOODOO_VSYNC": "1",
          "AERO_DGVOODOO_FLIP_MODEL": "0"
        },
        "balanced": {
          "AERO_DX_WRAPPER_MODE": "dgvoodoo",
          "AERO_DGVOODOO_SELECTED": "1",
          "AERO_DGVOODOO_PREF_ARCH": "x64",
          "AERO_DGVOODOO_FORCE_D3D11": "0",
          "AERO_DGVOODOO_VSYNC": "0",
          "AERO_DGVOODOO_FLIP_MODEL": "1"
        },
        "aggressive": {
          "AERO_DX_WRAPPER_MODE": "dgvoodoo",
          "AERO_DGVOODOO_SELECTED": "1",
          "AERO_DGVOODOO_PREF_ARCH": "arm64ec",
          "AERO_DGVOODOO_FORCE_D3D11": "1",
          "AERO_DGVOODOO_VSYNC": "0",
          "AERO_DGVOODOO_FLIP_MODEL": "1"
        }
      },
      "routeHints": {
        "primaryProvider": "turnip-vulkan",
        "fallbackProvider": "freedreno-opengl",
        "legacyFallbackEngine": "dgvoodoo",
        "legacyTargetApis": ["ddraw", "d3d1", "d3d2", "d3d3", "d3d5", "d3d6", "d3d7", "glide", "d3d8", "d3d9"]
      },
      "socClassProfiles": {
        "adreno-6xx-and-older": "conservative",
        "adreno-7xx": "balanced",
        "xclipse-rdna-mobile": "balanced",
        "mali-g7xx-or-newer": "aggressive",
        "unknown": "balanced"
      }
    }
  }
}
EOF_PROFILE

artifact_path="${OUT_DIR}/${DGVOODOO_ARTIFACT_NAME}"
sha_path="${OUT_DIR}/${DGVOODOO_SHA256_ARTIFACT_NAME}"
release_notes="${OUT_DIR}/${DGVOODOO_RELEASE_NOTES_NAME}"
metadata_path="${OUT_DIR}/dgvoodoo-metadata.env"

rm -f "${artifact_path}" "${sha_path}" "${release_notes}" "${metadata_path}"
tar -cJf "${artifact_path}" -C "${wcp_root}" .

artifact_sha="$(sha256_file "${artifact_path}")"
cat > "${sha_path}" <<EOF_SHA
${artifact_sha}  ${DGVOODOO_ARTIFACT_NAME}
EOF_SHA

cat > "${release_notes}" <<EOF_NOTES
Ae dgVoodoo WCP package

RU:
- Формат: WCP, ставится через Winlator Contents
- Режим источника: ${source_mode}
- Вариант апстрим-ассета: ${DGVOODOO_UPSTREAM_ASSET_VARIANT}
- Upstream tag: ${upstream_tag}
- Upstream asset: ${asset_name}
- Upstream release: ${release_url}
- Proxy mode: ${DGVOODOO_PROXY_MODE}
- Proxy DLL count: ${proxy_count}

EN:
- Format: WCP, installable via Winlator Contents
- Source mode: ${source_mode}
- Upstream asset variant: ${DGVOODOO_UPSTREAM_ASSET_VARIANT}
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
DGVOODOO_SOURCE_MODE=${source_mode}
DGVOODOO_UPSTREAM_ASSET_VARIANT=${DGVOODOO_UPSTREAM_ASSET_VARIANT}
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
