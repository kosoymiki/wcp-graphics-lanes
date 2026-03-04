#!/usr/bin/env python3
"""Static contract gate for Contents QA checklist.

This gate validates repository-side invariants that do not require device access.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Sequence

ALLOWED_INTERNAL_TYPES = {"wine", "proton", "protonge", "protonwine", "vulkansdk", "turnip", "freedreno", "dgvoodoo", "dxvk", "vkd3d"}
ALLOWED_TYPES = {"Wine", "Proton", "VulkanSDK", "TurnipDriver", "OpenGLDriver", "DgVoodoo", "DXVK", "VKD3D"}
EXPECTED_TYPE_BY_INTERNAL = {
    "wine": "Wine",
    "proton": "Proton",
    "protonge": "Proton",
    "protonwine": "Proton",
    "vulkansdk": "VulkanSDK",
    "turnip": "TurnipDriver",
    "freedreno": "OpenGLDriver",
    "dgvoodoo": "DgVoodoo",
    "dxvk": "DXVK",
    "vkd3d": "VKD3D",
}
EXPECTED_DISPLAY_BY_TYPE = {
    "Wine": "Wine",
    "Proton": "Proton",
    "VulkanSDK": "Vulkan SDK",
    "TurnipDriver": "Turnip",
    "OpenGLDriver": "OpenGL Driver",
    "DgVoodoo": "dgVoodoo",
    "DXVK": "DXVK",
    "VKD3D": "VKD3D",
}
TARGET_REPO = "kosoymiki/winlator-wine-proton-arm64ec-wcp"
RUNTIME_RELEASE_REPO = "kosoymiki/wcp-runtime-lanes"
GRAPHICS_RELEASE_REPO = "kosoymiki/wcp-graphics-lanes"
TARGET_RELEASE_REPO_BY_INTERNAL = {
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
TARGET_OVERLAY_URL = (
    "https://raw.githubusercontent.com/"
    f"{TARGET_REPO}/main/contents/contents.json"
)
TARGET_HUB_PROFILES_URL = "https://raw.githubusercontent.com/Arihany/WinlatorWCPHub/main/pack.json"

WORKFLOW_EXPECTATIONS = {
    ".github/workflows/ci-arm64ec-wine.yml": {
        "WCP_VERSION_CODE": "\"1\"",
        "WCP_CHANNEL": "nightly",
        "WCP_DELIVERY": "remote",
        "WCP_PROFILE_TYPE": "Wine",
        "WCP_DISPLAY_CATEGORY": "Wine",
        "WCP_RELEASE_TAG": "freewine11-arm64ec-latest",
        "WCP_SOURCE_REPO": "kosoymiki/wcp-runtime-lanes",
    },
    ".github/workflows/ci-vulkan-sdk-arm.yml": {
        "WCP_VERSION_CODE": "\"1\"",
        "WCP_CHANNEL": "stable",
        "WCP_DELIVERY": "remote",
        "WCP_PROFILE_TYPE": "VulkanSDK",
        "WCP_DISPLAY_CATEGORY": "Vulkan SDK",
        "WCP_SOURCE_REPO": "kosoymiki/wcp-graphics-lanes",
        "VULKAN_SDK_LATEST_JSON_URL": "https://vulkan.lunarg.com/sdk/latest/linux.json",
        "VULKAN_SDK_LINUX_SDK_URL": "https://sdk.lunarg.com/sdk/download/latest/linux/vulkan-sdk.tar.xz",
    },
    ".github/workflows/ci-graphics-drivers.yml": {
        "AETURNIP_SOURCE_REPO": "kosoymiki/wcp-graphics-lanes",
        "AEOPENGL_SOURCE_REPO": "kosoymiki/wcp-graphics-lanes",
        "AEDXVK_SOURCE_REPO": "kosoymiki/wcp-graphics-lanes",
        "AEVKD3D_SOURCE_REPO": "kosoymiki/wcp-graphics-lanes",
        "MESA_SOURCE_GIT_URL": "https://gitlab.freedesktop.org/mesa/mesa.git",
        "AETURNIP_VERSION_NAME": "rolling-arm64",
        "AEOPENGL_VERSION_NAME": "rolling-arm64",
        "DGVOODOO_LATEST_RELEASE_API": "https://api.github.com/repos/dege-diosg/dgVoodoo2/releases/latest",
        "DGVOODOO_VERSION_NAME": "2.86.5",
        "DXVK_GPLASYNC_GIT_URL": "https://gitlab.com/Ph42oN/dxvk-gplasync.git",
        "DXVK_UPSTREAM_GIT_URL": "https://github.com/doitsujin/dxvk.git",
        "AEDXVK_GENERIC_VERSION_NAME": "2.7.1-1-gplasync",
        "AEDXVK_ARM64EC_VERSION_NAME": "2.7.1-1-gplasync-arm64ec",
        "VKD3D_PROTON_GIT_URL": "https://github.com/HansKristian-Work/vkd3d-proton.git",
        "AEVKD3D_GENERIC_VERSION_NAME": "3.0b",
        "AEVKD3D_ARM64EC_VERSION_NAME": "3.0b-arm64ec",
    },
}

WORKFLOW_REQUIRED_TOKENS = {
    ".github/workflows/ci-vulkan-sdk-arm.yml": [
        "WCP_RELEASE_TAG: vulkan-sdk-arm64-latest",
        "WCP_RELEASE_TAG: vulkan-sdk-x86_64-latest",
        "VULKAN_SDK_LAYOUT_ARCH: arm64",
        "VULKAN_SDK_LAYOUT_ARCH: x86_64",
        "Build Vulkan SDK ARM64 WCP contents package",
        "Build Vulkan SDK x86_64 WCP contents package",
    ],
    ".github/workflows/ci-graphics-drivers.yml": [
        "AETURNIP_RELEASE_TAG: aeturnip-arm64-latest",
        "AEOPENGL_RELEASE_TAG: aeopengl-driver-arm64-latest",
        "DGVOODOO_RELEASE_TAG: dgvoodoo-latest",
        "release_tag: dxvk-gplasync-latest",
        "release_tag: dxvk-gplasync-arm64ec-latest",
        "release_tag: vkd3d-proton-latest",
        "release_tag: vkd3d-proton-arm64ec-latest",
        "Build AeTurnip ARM64 ZIP driver",
        "Build AeOpenGLDriver ARM64 ZIP overlay",
        "Build dgVoodoo latest ZIP mirror",
        "Build AeDXVK GPLAsync source WCP",
        "Build AeVKD3D-Proton source WCP",
    ],
}

DEPRECATED_WORKFLOWS = (
    ".github/workflows/ci-proton-ge10-wcp.yml",
    ".github/workflows/ci-protonwine10-wcp.yml",
)

ARTIFACT_EXPECTED_ENTRIES = {
    "freewine11": {"internalType": "wine", "artifactName": "freewine11-arm64ec.wcp"},
    "wine11": {"internalType": "wine", "artifactName": "freewine11-arm64ec.wcp"},
    "vulkansdkarm64": {"internalType": "vulkansdk", "artifactName": "vulkan-sdk-arm64.wcp"},
    "vulkansdkx86_64": {"internalType": "vulkansdk", "artifactName": "vulkan-sdk-x86_64.wcp"},
    "aedxvkgplasync": {"internalType": "dxvk", "artifactName": "dxvk-gplasync.wcp"},
    "aedxvkgplasyncarm64ec": {"internalType": "dxvk", "artifactName": "dxvk-gplasync-arm64ec.wcp"},
    "aevkd3dproton": {"internalType": "vkd3d", "artifactName": "vkd3d-proton.wcp"},
    "aevkd3dprotonarm64ec": {"internalType": "vkd3d", "artifactName": "vkd3d-proton-arm64ec.wcp"},
    "aeturniparm64": {"internalType": "turnip", "artifactName": "aeturnip-arm64.zip"},
    "dgvoodoolatest": {"internalType": "dgvoodoo", "artifactName": "dgvoodoo-latest.zip"},
    "aeopengldriverarm64": {"internalType": "freedreno", "artifactName": "aeopengl-driver-arm64.zip"},
}


@dataclass
class CheckResult:
    failures: List[str]
    warnings: List[str]


def fail(msg: str, failures: List[str]) -> None:
    failures.append(msg)


def warn(msg: str, warnings: List[str]) -> None:
    warnings.append(msg)


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def check_contents_schema(
    contents_path: Path,
    artifact_map_path: Path,
    failures: List[str],
    _warnings: List[str],
) -> None:
    payload = load_json(contents_path)
    if not isinstance(payload, list):
        fail("contents root must be JSON array", failures)
        return
    if not payload:
        fail("contents list is empty", failures)
        return

    artifact_map = load_json(artifact_map_path)
    artifacts = artifact_map.get("artifacts", {}) if isinstance(artifact_map, dict) else {}
    if not isinstance(artifacts, dict):
        fail("artifact-source-map artifacts must be object", failures)
        artifacts = {}

    required_fields = {
        "type",
        "internalType",
        "verName",
        "verCode",
        "channel",
        "delivery",
        "displayCategory",
        "sourceRepo",
        "releaseTag",
        "artifactName",
        "remoteUrl",
        "sha256Url",
    }

    seen_identity = set()
    family_entries_by_internal: Dict[str, List[dict]] = {}

    for idx, row in enumerate(payload):
        if not isinstance(row, dict):
            fail(f"entry[{idx}] is not object", failures)
            continue

        missing = sorted(required_fields - set(row.keys()))
        if missing:
            fail(f"entry[{idx}] missing fields: {','.join(missing)}", failures)
            continue

        type_name = str(row.get("type", ""))
        internal_type = str(row.get("internalType", "")).strip().lower()
        channel = str(row.get("channel", "")).strip().lower()
        delivery = str(row.get("delivery", "")).strip().lower()
        display_category = str(row.get("displayCategory", "")).strip()
        source_repo = str(row.get("sourceRepo", "")).strip()
        release_tag = str(row.get("releaseTag", "")).strip()
        artifact_name = str(row.get("artifactName", "")).strip()
        remote_url = str(row.get("remoteUrl", "")).strip()
        sha256_url = str(row.get("sha256Url", "")).strip()
        ver_name = str(row.get("verName", "")).strip()
        ver_code = str(row.get("verCode", "")).strip()

        identity = (type_name.lower(), internal_type, ver_name, ver_code)
        if identity in seen_identity:
            fail(f"duplicate entry identity: {identity}", failures)
        seen_identity.add(identity)

        if type_name not in ALLOWED_TYPES:
            fail(
                f"entry[{idx}] type must be one of {sorted(ALLOWED_TYPES)}; got {type_name}",
                failures,
            )

        if internal_type not in ALLOWED_INTERNAL_TYPES:
            fail(
                f"entry[{idx}] internalType must be one of {sorted(ALLOWED_INTERNAL_TYPES)}; got {internal_type}",
                failures,
            )
        else:
            expected_type = EXPECTED_TYPE_BY_INTERNAL[internal_type]
            if type_name != expected_type:
                fail(
                    f"entry[{idx}] internalType {internal_type} requires type {expected_type}; got {type_name}",
                    failures,
                )

        if channel != "stable":
            fail(f"entry[{idx}] channel must be stable in overlay contents; got {channel}", failures)

        if delivery != "remote":
            fail(f"entry[{idx}] delivery must be remote; got {delivery}", failures)

        expected_display = EXPECTED_DISPLAY_BY_TYPE.get(type_name, type_name)
        if display_category != expected_display:
            fail(
                f"entry[{idx}] displayCategory must be {expected_display}; got {display_category}",
                failures,
            )

        expected_repo = TARGET_RELEASE_REPO_BY_INTERNAL.get(internal_type, "")
        if source_repo != expected_repo:
            fail(f"entry[{idx}] sourceRepo must be {expected_repo}; got {source_repo}", failures)

        if not release_tag.endswith("-latest"):
            fail(f"entry[{idx}] releaseTag must end with -latest: {release_tag}", failures)

        if internal_type in {"turnip", "freedreno", "dgvoodoo"}:
            if not artifact_name.endswith(".zip"):
                fail(f"entry[{idx}] artifactName must end with .zip; got {artifact_name}", failures)
        else:
            if not artifact_name.endswith(".wcp"):
                fail(f"entry[{idx}] artifactName must end with .wcp; got {artifact_name}", failures)
        if internal_type == "vulkansdk":
            if "vulkan-sdk" not in release_tag:
                fail(f"entry[{idx}] vulkansdk releaseTag must contain vulkan-sdk; got {release_tag}", failures)
            if "vulkan-sdk" not in artifact_name:
                fail(f"entry[{idx}] vulkansdk artifactName must contain vulkan-sdk; got {artifact_name}", failures)
        if internal_type == "turnip":
            if "turnip" not in release_tag:
                fail(f"entry[{idx}] turnip releaseTag must contain turnip; got {release_tag}", failures)
            if "turnip" not in artifact_name:
                fail(f"entry[{idx}] turnip artifactName must contain turnip; got {artifact_name}", failures)
        if internal_type == "freedreno":
            if "aeopengl-driver" not in release_tag:
                fail(f"entry[{idx}] freedreno releaseTag must contain aeopengl-driver; got {release_tag}", failures)
            if "aeopengl-driver" not in artifact_name:
                fail(f"entry[{idx}] freedreno artifactName must contain aeopengl-driver; got {artifact_name}", failures)
        if internal_type == "dgvoodoo":
            if "dgvoodoo" not in release_tag:
                fail(f"entry[{idx}] dgvoodoo releaseTag must contain dgvoodoo; got {release_tag}", failures)
            if "dgvoodoo" not in artifact_name:
                fail(f"entry[{idx}] dgvoodoo artifactName must contain dgvoodoo; got {artifact_name}", failures)
        if internal_type == "dxvk":
            if "dxvk-gplasync" not in release_tag:
                fail(f"entry[{idx}] dxvk releaseTag must contain dxvk-gplasync; got {release_tag}", failures)
            if "dxvk-gplasync" not in artifact_name:
                fail(f"entry[{idx}] dxvk artifactName must contain dxvk-gplasync; got {artifact_name}", failures)
        if internal_type == "vkd3d":
            if "vkd3d-proton" not in release_tag:
                fail(f"entry[{idx}] vkd3d releaseTag must contain vkd3d-proton; got {release_tag}", failures)
            if "vkd3d-proton" not in artifact_name:
                fail(f"entry[{idx}] vkd3d artifactName must contain vkd3d-proton; got {artifact_name}", failures)

        release_prefix = f"https://github.com/{source_repo}/releases/download/"
        if not remote_url.startswith(release_prefix):
            fail(f"entry[{idx}] remoteUrl must point to {source_repo} releases repo; got {remote_url}", failures)

        if f"/{release_tag}/" not in remote_url:
            fail(f"entry[{idx}] remoteUrl must include releaseTag segment {release_tag}", failures)

        if not remote_url.endswith("/" + artifact_name):
            fail(
                f"entry[{idx}] remoteUrl must end with artifactName ({artifact_name}); got {remote_url}",
                failures,
            )

        if not sha256_url.startswith(release_prefix):
            fail(f"entry[{idx}] sha256Url must point to {source_repo} releases repo; got {sha256_url}", failures)

        if f"/{release_tag}/" not in sha256_url:
            fail(f"entry[{idx}] sha256Url must include releaseTag segment {release_tag}", failures)

        source_version = str(row.get("sourceVersion", "")).strip()
        if source_version != "rolling-latest":
            fail(
                f"entry[{idx}] sourceVersion must be rolling-latest for overlay rows; got {source_version}",
                failures,
            )

        family_entries_by_internal.setdefault(internal_type, []).append(row)

    for artifact_key, expected in ARTIFACT_EXPECTED_ENTRIES.items():
        artifact = artifacts.get(artifact_key)
        if not isinstance(artifact, dict):
            fail(f"artifact-source-map missing artifact key: {artifact_key}", failures)
            continue

        internal_type = expected["internalType"]
        artifact_name = expected["artifactName"]
        entries = family_entries_by_internal.get(internal_type, [])
        entry = next((candidate for candidate in entries if str(candidate.get("artifactName", "")).strip() == artifact_name), None)
        if not entry:
            fail(
                f"contents missing internalType/artifactName entry for artifact key {artifact_key}: "
                f"{internal_type}/{artifact_name}",
                failures,
            )
            continue

        expected_remote = str(artifact.get("remoteUrl", "")).strip()
        expected_sha = str(artifact.get("sha256Url", "")).strip()
        actual_remote = str(entry.get("remoteUrl", "")).strip()
        actual_sha = str(entry.get("sha256Url", "")).strip()

        if expected_remote != actual_remote:
            fail(
                f"remoteUrl mismatch for {artifact_key}: contents={actual_remote} artifact-map={expected_remote}",
                failures,
            )
        if expected_sha != actual_sha:
            fail(
                f"sha256Url mismatch for {artifact_key}: contents={actual_sha} artifact-map={expected_sha}",
                failures,
            )


def check_patch_contract(patch_path: Path, failures: List[str]) -> None:
    text = patch_path.read_text(encoding="utf-8", errors="ignore")

    required_tokens = [
        'REMOTE_PROFILES = "' + TARGET_HUB_PROFILES_URL + '";',
        'REMOTE_WINE_PROTON_OVERLAY = "' + TARGET_OVERLAY_URL + '"',
        'ContentProfile.MARK_DISPLAY_CATEGORY',
        'ContentProfile.MARK_SOURCE_REPO',
        'ContentProfile.MARK_RELEASE_TAG',
        'if (includeBeta && !isBeta) continue;',
        'if (!includeBeta && isBeta) continue;',
    ]

    for token in required_tokens:
        if token not in text:
            fail(f"patch contract token missing in 0001: {token}", failures)


def check_contents_validator_contract(root: Path, failures: List[str]) -> None:
    validator = root / "ci/contents/validate-contents-json.py"
    contents = root / "contents/contents.json"
    if not validator.is_file():
        fail("contents validator missing: ci/contents/validate-contents-json.py", failures)
        return
    if not contents.is_file():
        fail("contents file missing: contents/contents.json", failures)
        return
    result = subprocess.run(
        [sys.executable, str(validator), str(contents)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        first_line = stderr.splitlines()[0] if stderr else f"rc={result.returncode}"
        fail(f"contents validator failed: {first_line}", failures)


def check_release_publish_contract(root: Path, failures: List[str]) -> None:
    publish_script = root / "ci/release/publish-0.9c.sh"
    notes_template = root / "ci/release/templates/wcp-stable.ru-en.md"
    notes_prepare = root / "ci/release/prepare-0.9c-notes.sh"

    for path in (publish_script, notes_template, notes_prepare):
        if not path.is_file():
            fail(f"required release contract file missing: {path}", failures)
            return

    publish_text = publish_script.read_text(encoding="utf-8", errors="ignore")
    template_text = notes_template.read_text(encoding="utf-8", errors="ignore")
    prepare_text = notes_prepare.read_text(encoding="utf-8", errors="ignore")

    required_publish_tokens = [
        'WCP_TAG="freewine11-arm64ec-latest"',
        'WCP_NOTES="${ROOT_DIR}/out/release-notes/wcp-stable.md"',
        'mkdir -p "${STAGE_DIR}/wcp-stable" "${STAGE_DIR}/winlator-latest"',
        'gh release upload "${WCP_TAG}" --repo "${WCP_REPO}" --clobber "${WCP_ASSETS[@]}"',
    ]
    for token in required_publish_tokens:
        if token not in publish_text:
            fail(f"release publish contract token missing: {token}", failures)

    if "freewine11-arm64ec" not in template_text:
        fail("wcp-stable notes template must describe freewine11 lane metadata", failures)

    if 'wcp-stable.md' not in prepare_text:
        fail("prepare release notes flow must produce wcp-stable.md", failures)


def check_workflow_contract(root: Path, failures: List[str]) -> None:
    for rel_path, expectations in WORKFLOW_EXPECTATIONS.items():
        workflow_path = root / rel_path
        if not workflow_path.is_file():
            fail(f"workflow missing: {rel_path}", failures)
            continue
        text = workflow_path.read_text(encoding="utf-8", errors="ignore")

        for key, value in expectations.items():
            pattern = rf"^\s*{re.escape(key)}\s*:\s*{re.escape(value)}\s*$"
            if not re.search(pattern, text, re.MULTILINE):
                fail(f"workflow {rel_path} missing expected env contract: {key}: {value}", failures)

        for token in WORKFLOW_REQUIRED_TOKENS.get(rel_path, []):
            if token not in text:
                fail(f"workflow {rel_path} missing required token: {token}", failures)

    for rel_path in DEPRECATED_WORKFLOWS:
        if (root / rel_path).exists():
            fail(f"deprecated workflow must be removed: {rel_path}", failures)


def render_markdown(result: CheckResult) -> str:
    status = "PASS" if not result.failures else "FAIL"
    lines: List[str] = [
        "# Contents QA Contract",
        "",
        f"- status: **{status}**",
        f"- failures: **{len(result.failures)}**",
        f"- warnings: **{len(result.warnings)}**",
        "",
        "## Failures",
        "",
    ]
    if not result.failures:
        lines.append("- none")
    else:
        for item in result.failures:
            lines.append(f"- {item}")

    lines.extend(["", "## Warnings", ""])
    if not result.warnings:
        lines.append("- none")
    else:
        for item in result.warnings:
            lines.append(f"- {item}")
    lines.append("")
    return "\n".join(lines)


def write_report(output: Path, result: CheckResult) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_markdown(result), encoding="utf-8")

    json_out = output.with_suffix(".json")
    json_out.write_text(
        json.dumps(
            {
                "passed": not result.failures,
                "failures": result.failures,
                "warnings": result.warnings,
            },
            indent=2,
            ensure_ascii=True,
        )
        + "\n",
        encoding="utf-8",
    )


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate static contents QA contract")
    parser.add_argument("--root", default=".", help="Repository root")
    parser.add_argument("--output", default="-", help="Markdown report path or '-' for stdout")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero on warnings too")
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()

    contents_path = root / "contents/contents.json"
    artifact_map_path = root / "ci/winlator/artifact-source-map.json"
    patch_path = root / "ci/winlator/patches/0001-mainline-full-stack-consolidated.patch"

    failures: List[str] = []
    warnings: List[str] = []

    for path in (contents_path, artifact_map_path, patch_path):
        if not path.is_file():
            fail(f"required file missing: {path}", failures)

    if not failures:
        check_contents_schema(contents_path, artifact_map_path, failures, warnings)
        check_patch_contract(patch_path, failures)
        check_contents_validator_contract(root, failures)
        check_release_publish_contract(root, failures)
        check_workflow_contract(root, failures)

    result = CheckResult(failures=failures, warnings=warnings)

    if args.output == "-":
        sys.stdout.write(render_markdown(result))
    else:
        write_report(Path(args.output), result)

    if result.failures:
        return 1
    if args.strict and result.warnings:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
