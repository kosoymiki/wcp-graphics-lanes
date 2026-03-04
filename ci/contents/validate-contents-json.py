#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

ALLOWED_CHANNELS = {"stable", "beta", "nightly"}
ALLOWED_DELIVERY = {"remote", "embedded", ""}
ALLOWED_TYPES = {"wine", "proton", "vulkansdk", "turnipdriver", "opengldriver", "dgvoodoo", "dxvk", "vkd3d"}
ALLOWED_INTERNAL_TYPES = {"wine", "proton", "protonge", "protonwine", "vulkansdk", "turnip", "freedreno", "dgvoodoo", "dxvk", "vkd3d"}
EXPECTED_TYPE_BY_INTERNAL = {
    "wine": "wine",
    "proton": "proton",
    "protonge": "proton",
    "protonwine": "proton",
    "vulkansdk": "vulkansdk",
    "turnip": "turnipdriver",
    "freedreno": "opengldriver",
    "dgvoodoo": "dgvoodoo",
    "dxvk": "dxvk",
    "vkd3d": "vkd3d",
}
EXPECTED_DISPLAY_BY_TYPE = {
    "wine": "Wine",
    "proton": "Proton",
    "vulkansdk": "Vulkan SDK",
    "turnipdriver": "Turnip",
    "opengldriver": "OpenGL Driver",
    "dgvoodoo": "dgVoodoo",
    "dxvk": "DXVK",
    "vkd3d": "VKD3D",
}
WINE_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*(?:-[0-9]+(?:\.[0-9]+)*)?-(x86|x86_64|arm64ec)$")
VULKAN_SDK_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*-(arm64|x86_64)$")
GRAPHICS_PROVIDER_VERSION_RE = re.compile(r"^(?:rolling|[0-9]+(?:\.[0-9]+)*)-arm64$")
DGVOODOO_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*$")
DXVK_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*(?:-[0-9]+)?(?:-gplasync)?(?:-arm64ec)?$")
VKD3D_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*(?:[ab][0-9]*)?(?:-arm64ec)?$")
RUNTIME_RELEASE_REPO = "kosoymiki/wcp-runtime-lanes"
GRAPHICS_RELEASE_REPO = "kosoymiki/wcp-graphics-lanes"
EXPECTED_SOURCE_REPO_BY_INTERNAL = {
    "wine": RUNTIME_RELEASE_REPO,
    "proton": RUNTIME_RELEASE_REPO,
    "protonge": RUNTIME_RELEASE_REPO,
    "protonwine": RUNTIME_RELEASE_REPO,
    "vulkansdk": GRAPHICS_RELEASE_REPO,
    "turnip": GRAPHICS_RELEASE_REPO,
    "freedreno": GRAPHICS_RELEASE_REPO,
    "dgvoodoo": GRAPHICS_RELEASE_REPO,
    "dxvk": GRAPHICS_RELEASE_REPO,
    "vkd3d": GRAPHICS_RELEASE_REPO,
}


def fail(msg: str) -> None:
    print(f"[contents-validate][error] {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "contents/contents.json")
    if not path.is_file():
        fail(f"file not found: {path}")

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        fail("root must be a JSON array")

    seen = set()
    nightly_seen = 0
    stable_seen = 0
    vulkan_sdk_arches = set()
    turnip_rows = 0
    freedreno_rows = 0
    dgvoodoo_rows = 0
    dxvk_rows = 0
    vkd3d_rows = 0
    for idx, item in enumerate(data):
        if not isinstance(item, dict):
            fail(f"entry {idx} is not an object")
        for key in ("type", "verName", "verCode", "remoteUrl"):
            if key not in item:
                fail(f"entry {idx} missing required field: {key}")

        type_name = str(item["type"]).strip()
        type_key = type_name.lower()
        ver_name = str(item["verName"])
        ver_code = int(item["verCode"])
        channel = str(item.get("channel", "stable")).strip().lower()
        delivery = str(item.get("delivery", "")).strip().lower()
        remote_url = str(item["remoteUrl"])
        internal_type = str(item.get("internalType", "")).strip().lower()
        display_category = str(item.get("displayCategory", "")).strip()
        source_repo = str(item.get("sourceRepo", "")).strip()
        release_tag = str(item.get("releaseTag", "")).strip()
        source_version = str(item.get("sourceVersion", "")).strip()
        artifact_name = str(item.get("artifactName", "")).strip()
        sha256_url = str(item.get("sha256Url", "")).strip()

        if channel not in ALLOWED_CHANNELS:
            fail(f"entry {idx} has invalid channel: {channel}")
        if delivery not in ALLOWED_DELIVERY:
            fail(f"entry {idx} has invalid delivery: {delivery}")
        if not remote_url.startswith("https://github.com/"):
            fail(f"entry {idx} remoteUrl must point to a GitHub release: {remote_url}")
        if type_key not in ALLOWED_TYPES:
            fail(f"entry {idx} type must be one of {sorted(ALLOWED_TYPES)}: {type_name}")
        if type_key in {"wine", "proton"}:
            version_ok = WINE_VERSION_RE.match(ver_name)
        elif type_key == "vulkansdk":
            version_ok = VULKAN_SDK_VERSION_RE.match(ver_name)
        elif type_key == "dgvoodoo":
            version_ok = DGVOODOO_VERSION_RE.match(ver_name)
        elif type_key == "dxvk":
            version_ok = DXVK_VERSION_RE.match(ver_name)
        elif type_key == "vkd3d":
            version_ok = VKD3D_VERSION_RE.match(ver_name)
        else:
            version_ok = GRAPHICS_PROVIDER_VERSION_RE.match(ver_name)
        if not version_ok:
            fail(f"entry {idx} verName is not valid for {type_name}: {ver_name}")
        if type_key == "vulkansdk":
            sdk_arch = ver_name.rsplit("-", 1)[-1]
            vulkan_sdk_arches.add(sdk_arch)
        elif type_key == "turnipdriver":
            turnip_rows += 1
        elif type_key == "opengldriver":
            freedreno_rows += 1
        elif type_key == "dgvoodoo":
            dgvoodoo_rows += 1
        elif type_key == "dxvk":
            dxvk_rows += 1
        elif type_key == "vkd3d":
            vkd3d_rows += 1
        if internal_type not in ALLOWED_INTERNAL_TYPES:
            fail(
                f"entry {idx} internalType must be one of "
                f"{sorted(ALLOWED_INTERNAL_TYPES)}"
            )
        expected_type = EXPECTED_TYPE_BY_INTERNAL.get(internal_type)
        if expected_type and type_key != expected_type:
            fail(
                f"entry {idx} internalType {internal_type} requires type "
                f"{EXPECTED_DISPLAY_BY_TYPE[expected_type]} (got {type_name})"
            )
        expected_display = EXPECTED_DISPLAY_BY_TYPE[type_key]
        if display_category != expected_display:
            fail(
                f"entry {idx} displayCategory must be {expected_display} for "
                f"type {type_name}: {display_category}"
            )
        if internal_type == "wine":
            if "wine" not in release_tag:
                fail(f"entry {idx} wine internalType requires *wine* releaseTag: {release_tag}")
            if "wine" not in artifact_name:
                fail(f"entry {idx} wine internalType requires *wine* artifactName: {artifact_name}")
        elif internal_type == "proton":
            if "proton-" not in release_tag:
                fail(f"entry {idx} proton internalType requires proton-* releaseTag: {release_tag}")
            if "proton-" not in artifact_name:
                fail(f"entry {idx} proton internalType requires proton-* artifactName: {artifact_name}")
        elif internal_type == "protonge":
            if "proton-ge" not in release_tag:
                fail(f"entry {idx} protonge internalType requires proton-ge* releaseTag: {release_tag}")
            if "proton-ge" not in artifact_name:
                fail(f"entry {idx} protonge internalType requires proton-ge* artifactName: {artifact_name}")
        elif internal_type == "protonwine":
            if "protonwine" not in release_tag:
                fail(f"entry {idx} protonwine internalType requires protonwine* releaseTag: {release_tag}")
            if "protonwine" not in artifact_name:
                fail(f"entry {idx} protonwine internalType requires protonwine* artifactName: {artifact_name}")
        elif internal_type == "vulkansdk":
            if "vulkan-sdk" not in release_tag:
                fail(f"entry {idx} vulkansdk internalType requires vulkan-sdk* releaseTag: {release_tag}")
            if "vulkan-sdk" not in artifact_name:
                fail(f"entry {idx} vulkansdk internalType requires vulkan-sdk* artifactName: {artifact_name}")
            if "arm64" in ver_name and "arm64" not in release_tag:
                fail(f"entry {idx} arm64 VulkanSDK row requires arm64 releaseTag: {release_tag}")
            if "arm64" in ver_name and "arm64" not in artifact_name:
                fail(f"entry {idx} arm64 VulkanSDK row requires arm64 artifactName: {artifact_name}")
            if "x86_64" in ver_name and "x86_64" not in release_tag:
                fail(f"entry {idx} x86_64 VulkanSDK row requires x86_64 releaseTag: {release_tag}")
            if "x86_64" in ver_name and "x86_64" not in artifact_name:
                fail(f"entry {idx} x86_64 VulkanSDK row requires x86_64 artifactName: {artifact_name}")
        elif internal_type == "turnip":
            if "turnip" not in release_tag:
                fail(f"entry {idx} turnip internalType requires turnip* releaseTag: {release_tag}")
            if "turnip" not in artifact_name:
                fail(f"entry {idx} turnip internalType requires turnip* artifactName: {artifact_name}")
            if "arm64" not in release_tag:
                fail(f"entry {idx} turnip row requires arm64 releaseTag: {release_tag}")
            if "arm64" not in artifact_name:
                fail(f"entry {idx} turnip row requires arm64 artifactName: {artifact_name}")
        elif internal_type == "freedreno":
            if "aeopengl-driver" not in release_tag:
                fail(f"entry {idx} freedreno internalType requires aeopengl-driver* releaseTag: {release_tag}")
            if "aeopengl-driver" not in artifact_name:
                fail(f"entry {idx} freedreno internalType requires aeopengl-driver* artifactName: {artifact_name}")
            if "arm64" not in release_tag:
                fail(f"entry {idx} freedreno row requires arm64 releaseTag: {release_tag}")
            if "arm64" not in artifact_name:
                fail(f"entry {idx} freedreno row requires arm64 artifactName: {artifact_name}")
        elif internal_type == "dgvoodoo":
            if "dgvoodoo" not in release_tag:
                fail(f"entry {idx} dgvoodoo internalType requires dgvoodoo* releaseTag: {release_tag}")
            if "dgvoodoo" not in artifact_name:
                fail(f"entry {idx} dgvoodoo internalType requires dgvoodoo* artifactName: {artifact_name}")
        elif internal_type == "dxvk":
            if "dxvk-gplasync" not in release_tag:
                fail(f"entry {idx} dxvk internalType requires dxvk-gplasync* releaseTag: {release_tag}")
            if "dxvk-gplasync" not in artifact_name:
                fail(f"entry {idx} dxvk internalType requires dxvk-gplasync* artifactName: {artifact_name}")
            if "arm64ec" in ver_name and "arm64ec" not in release_tag:
                fail(f"entry {idx} dxvk arm64ec row requires arm64ec releaseTag: {release_tag}")
            if "arm64ec" in ver_name and "arm64ec" not in artifact_name:
                fail(f"entry {idx} dxvk arm64ec row requires arm64ec artifactName: {artifact_name}")
        elif internal_type == "vkd3d":
            if "vkd3d-proton" not in release_tag:
                fail(f"entry {idx} vkd3d internalType requires vkd3d-proton* releaseTag: {release_tag}")
            if "vkd3d-proton" not in artifact_name:
                fail(f"entry {idx} vkd3d internalType requires vkd3d-proton* artifactName: {artifact_name}")
            if "arm64ec" in ver_name and "arm64ec" not in release_tag:
                fail(f"entry {idx} vkd3d arm64ec row requires arm64ec releaseTag: {release_tag}")
            if "arm64ec" in ver_name and "arm64ec" not in artifact_name:
                fail(f"entry {idx} vkd3d arm64ec row requires arm64ec artifactName: {artifact_name}")
        if not source_repo:
            fail(f"entry {idx} missing sourceRepo")
        expected_repo = EXPECTED_SOURCE_REPO_BY_INTERNAL.get(internal_type)
        if expected_repo and source_repo != expected_repo:
            fail(f"entry {idx} sourceRepo must be {expected_repo}: {source_repo}")
        if not release_tag:
            fail(f"entry {idx} missing releaseTag")
        if not source_version:
            fail(f"entry {idx} missing sourceVersion")
        if not artifact_name:
            fail(f"entry {idx} missing artifactName")
        if not remote_url.endswith("/" + artifact_name):
            fail(f"entry {idx} remoteUrl must end with artifactName ({artifact_name}): {remote_url}")
        release_prefix = f"https://github.com/{source_repo}/releases/download/"
        if not remote_url.startswith(release_prefix):
            fail(f"entry {idx} remoteUrl must use sourceRepo release lane ({source_repo}): {remote_url}")
        if not sha256_url:
            fail(f"entry {idx} missing sha256Url")
        if not sha256_url.startswith(release_prefix):
            fail(f"entry {idx} sha256Url must use sourceRepo release lane ({source_repo}): {sha256_url}")
        if f"/{release_tag}/" not in sha256_url:
            fail(f"entry {idx} sha256Url must use matching releaseTag {release_tag}: {sha256_url}")
        if type_key in {"turnipdriver", "opengldriver", "dgvoodoo"}:
            if not artifact_name.endswith(".zip"):
                fail(f"entry {idx} artifactName must end with .zip for {type_name}: {artifact_name}")
        else:
            if not artifact_name.endswith(".wcp"):
                fail(f"entry {idx} artifactName must end with .wcp: {artifact_name}")

        key = (type_key, internal_type, ver_name, ver_code)
        if key in seen:
            fail(f"duplicate type/internalType/verName/verCode entry: {key}")
        seen.add(key)

        if channel == "nightly":
            nightly_seen += 1
        if channel == "stable":
            stable_seen += 1

    if stable_seen == 0:
        fail("no stable entries found")
    if vulkan_sdk_arches and vulkan_sdk_arches != {"arm64", "x86_64"}:
        fail(f"vulkansdk entries must cover exactly arm64 and x86_64; got {sorted(vulkan_sdk_arches)}")
    if turnip_rows not in {0, 1}:
        fail(f"turnipdriver entries must appear once at most; got {turnip_rows}")
    if freedreno_rows not in {0, 1}:
        fail(f"opengldriver entries must appear once at most; got {freedreno_rows}")
    if dgvoodoo_rows not in {0, 1}:
        fail(f"dgvoodoo entries must appear once at most; got {dgvoodoo_rows}")
    if dxvk_rows not in {0, 2}:
        fail(f"dxvk entries must appear exactly as generic+arm64ec pair; got {dxvk_rows}")
    if vkd3d_rows not in {0, 2}:
        fail(f"vkd3d entries must appear exactly as generic+arm64ec pair; got {vkd3d_rows}")
    print(f"[contents-validate] OK: {len(data)} entries ({stable_seen} stable, {nightly_seen} beta/nightly)")


if __name__ == "__main__":
    main()
