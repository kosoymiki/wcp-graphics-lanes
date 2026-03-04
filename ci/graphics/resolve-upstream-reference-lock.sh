#!/usr/bin/env bash
set -euo pipefail

OUT_PATH="${1:-$PWD/ci/graphics/upstream-reference-lock.json}"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

hub_json="${work_dir}/pack.json"
curl -fsSL -o "${hub_json}" "https://raw.githubusercontent.com/Arihany/WinlatorWCPHub/main/pack.json"

mesa_main="$(git ls-remote https://gitlab.freedesktop.org/mesa/mesa.git refs/heads/main | awk '{print $1}')"
mesa_stable="$(
  git ls-remote --tags --refs https://gitlab.freedesktop.org/mesa/mesa.git 'mesa-*' \
    | sed 's#.*refs/tags/mesa-##' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1
)"
dxvk_latest="$(git ls-remote --tags --refs https://github.com/doitsujin/dxvk.git 'refs/tags/*' | sed 's#.*refs/tags/##' | sort -V | tail -n 1)"
dxvk_gplasync_head="$(git ls-remote https://gitlab.com/Ph42oN/dxvk-gplasync.git HEAD | awk '{print $1}')"
vkd3d_head="$(git ls-remote https://github.com/HansKristian-Work/vkd3d-proton.git HEAD | awk '{print $1}')"
vkd3d_latest_stable="$(git ls-remote --tags --refs https://github.com/HansKristian-Work/vkd3d-proton.git 'refs/tags/v3*' | sed 's#.*refs/tags/##' | grep -Ev '[ab]$' | sort -V | tail -n 1)"
vkd3d_latest_any="$(git ls-remote --tags --refs https://github.com/HansKristian-Work/vkd3d-proton.git 'refs/tags/v3*' | sed 's#.*refs/tags/##' | sort -V | tail -n 1)"
dgvoodoo_latest="$(curl -fsSL https://api.github.com/repos/dege-diosg/dgVoodoo2/releases/latest | jq -r '.tag_name')"

python3 - <<'PY' "${hub_json}" "${OUT_PATH}" "${mesa_main}" "${mesa_stable}" "${dxvk_latest}" "${dxvk_gplasync_head}" "${vkd3d_latest_stable}" "${vkd3d_latest_any}" "${vkd3d_head}" "${dgvoodoo_latest}"
import json
import sys
from pathlib import Path

hub_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
mesa_main = sys.argv[3]
mesa_stable = sys.argv[4]
dxvk_latest = sys.argv[5]
dxvk_gplasync_head = sys.argv[6]
vkd3d_latest_stable = sys.argv[7]
vkd3d_latest_any = sys.argv[8]
vkd3d_head = sys.argv[9]
dgvoodoo_latest = sys.argv[10]

payload = json.loads(hub_path.read_text(encoding="utf-8"))

def latest_for(type_name, include=(), exclude=()):
    matches = []
    for row in payload:
        if row.get("type") != type_name:
            continue
        ver = str(row.get("verName", ""))
        lowered = ver.lower()
        if include:
            ok = True
            for needle in include:
                if needle.lower() not in lowered:
                    ok = False
                    break
            if not ok:
                continue
        for needle in exclude:
            if needle.lower() in lowered:
                break
        else:
            matches.append((ver, row.get("remoteUrl", "")))
    if not matches:
        return {"verName": "", "remoteUrl": ""}
    matches.sort(key=lambda item: item[0])
    ver, url = matches[-1]
    return {"verName": ver, "remoteUrl": url}

result = {
    "generatedAt": "2026-03-01",
    "mesa": {
        "mainCommit": mesa_main,
        "latestStable": mesa_stable,
    },
    "dxvk": {
        "upstreamLatest": dxvk_latest,
        "gplasyncHead": dxvk_gplasync_head,
        "wcphubLatest": latest_for("DXVK", (), ("arm64ec", "gplasync")),
        "wcphubLatestArm64ec": latest_for("DXVK", ("arm64ec",), ("gplasync",)),
        "wcphubLatestGplAsync": latest_for("DXVK", ("gplasync",), ("arm64ec",)),
        "wcphubLatestGplAsyncArm64ec": latest_for("DXVK", ("gplasync", "arm64ec")),
    },
    "vkd3dProton": {
        "upstreamLatestStable": vkd3d_latest_stable,
        "upstreamLatestAny": vkd3d_latest_any,
        "upstreamHead": vkd3d_head,
        "wcphubLatest": latest_for("VKD3D", (), ("arm64ec",)),
        "wcphubLatestArm64ec": latest_for("VKD3D", ("arm64ec",)),
    },
    "dgVoodoo": {
        "upstreamLatest": dgvoodoo_latest,
    },
}

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(result, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
PY
