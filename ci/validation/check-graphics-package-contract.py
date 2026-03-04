#!/usr/bin/env python3
"""Validate embedded runtime/forensic contract for graphics packages."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import tarfile
import zipfile
from typing import Dict

LANE_EXPECTATIONS: Dict[str, Dict[str, str]] = {
    "aeturnip": {"role": "graphics-provider", "lanePrefix": "aeturnip"},
    "aeopengl-driver": {"role": "graphics-provider", "lanePrefix": "aeopengl-driver"},
    "aedxvk-gplasync": {"role": "translation-layer", "lanePrefix": "aedxvk-gplasync"},
    "aevkd3d-proton": {"role": "translation-layer", "lanePrefix": "aevkd3d-proton"},
    "dgvoodoo": {"role": "translation-layer", "lanePrefix": "dgvoodoo"},
}
REQUIRED_WRAPPER_PROFILES = ("conservative", "balanced", "aggressive")


def fail(msg: str) -> int:
    print(f"[graphics-contract][error] {msg}", file=sys.stderr)
    return 1


def is_non_empty_string_list(value: object) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(item, str) and item.strip() for item in value)


def validate_wrapper_contract(wrapper: object) -> str | None:
    if not isinstance(wrapper, dict):
        return "wrapperContract block is missing for translation-layer role"

    schema_version = wrapper.get("schemaVersion")
    if not isinstance(schema_version, int) or schema_version < 1:
        return "wrapperContract.schemaVersion must be int >= 1"

    supported_profiles = wrapper.get("supportedProfiles")
    if not is_non_empty_string_list(supported_profiles):
        return "wrapperContract.supportedProfiles must be non-empty string[]"
    supported_set = set(supported_profiles)
    for required in REQUIRED_WRAPPER_PROFILES:
        if required not in supported_set:
            return f"wrapperContract.supportedProfiles must include {required!r}"

    default_profile = str(wrapper.get("defaultProfile", "")).strip()
    if not default_profile or default_profile not in supported_set:
        return "wrapperContract.defaultProfile must be one of supportedProfiles"

    profile_env = wrapper.get("profileEnv")
    if not isinstance(profile_env, dict):
        return "wrapperContract.profileEnv must be object"
    for required in REQUIRED_WRAPPER_PROFILES:
        env_map = profile_env.get(required)
        if not isinstance(env_map, dict) or not env_map:
            return f"wrapperContract.profileEnv.{required} must be non-empty object"
        for key, value in env_map.items():
            if not isinstance(key, str) or not key.startswith("AERO_"):
                return f"wrapperContract.profileEnv.{required} contains invalid key {key!r}"
            if not isinstance(value, str) or not value.strip():
                return f"wrapperContract.profileEnv.{required}.{key} must be non-empty string"

    route_hints = wrapper.get("routeHints")
    if not isinstance(route_hints, dict):
        return "wrapperContract.routeHints must be object"
    for required_key in ("primaryProvider", "fallbackProvider", "legacyFallbackEngine"):
        value = str(route_hints.get(required_key, "")).strip()
        if not value:
            return f"wrapperContract.routeHints.{required_key} is required"
    if not is_non_empty_string_list(route_hints.get("legacyTargetApis")):
        return "wrapperContract.routeHints.legacyTargetApis must be non-empty string[]"

    soc_class_profiles = wrapper.get("socClassProfiles")
    if not isinstance(soc_class_profiles, dict) or not soc_class_profiles:
        return "wrapperContract.socClassProfiles must be non-empty object"
    for soc_class, profile_name in soc_class_profiles.items():
        if not isinstance(soc_class, str) or not soc_class.strip():
            return "wrapperContract.socClassProfiles keys must be non-empty strings"
        if not isinstance(profile_name, str) or profile_name not in supported_set:
            return (
                "wrapperContract.socClassProfiles values must reference "
                "wrapperContract.supportedProfiles"
            )

    return None


def read_contract_from_zip(path: pathlib.Path) -> dict:
    with zipfile.ZipFile(path, mode="r") as zf:
        if "ae-runtime-contract.json" not in zf.namelist():
            raise ValueError("ae-runtime-contract.json missing in ZIP package")
        payload = zf.read("ae-runtime-contract.json")
    return json.loads(payload.decode("utf-8"))


def read_contract_from_tar(path: pathlib.Path) -> dict:
    with tarfile.open(path, mode="r:*") as tf:
        candidate = None
        for member in tf.getmembers():
            if member.isfile() and pathlib.PurePosixPath(member.name).name == "ae-runtime-contract.json":
                candidate = member
                break
        if candidate is None:
            raise ValueError("ae-runtime-contract.json missing in WCP package")
        extracted = tf.extractfile(candidate)
        if extracted is None:
            raise ValueError("unable to extract ae-runtime-contract.json from WCP package")
        payload = extracted.read()
    return json.loads(payload.decode("utf-8"))


def read_contract(path: pathlib.Path) -> dict:
    if zipfile.is_zipfile(path):
        return read_contract_from_zip(path)
    return read_contract_from_tar(path)


def validate_contract(contract: dict, lane: str, freewine_lane: str) -> int:
    expected = LANE_EXPECTATIONS[lane]
    if not isinstance(contract, dict):
        return fail("contract payload is not a JSON object")

    schema_version = contract.get("schemaVersion")
    if not isinstance(schema_version, int) or schema_version < 1:
        return fail(f"schemaVersion must be int >= 1, got {schema_version!r}")

    contract_lane = str(contract.get("lane", "")).strip()
    if not contract_lane:
        return fail("lane field is missing")
    if not contract_lane.startswith(expected["lanePrefix"]):
        return fail(
            f"lane must start with {expected['lanePrefix']!r}, got {contract_lane!r}"
        )

    role = str(contract.get("role", "")).strip().lower()
    if role != expected["role"]:
        return fail(f"role must be {expected['role']!r}, got {role!r}")

    runtime_lane = str(contract.get("freewineLane", "")).strip()
    if runtime_lane != freewine_lane:
        return fail(f"freewineLane must be {freewine_lane!r}, got {runtime_lane!r}")

    translation_layers = contract.get("translationLayers")
    if not is_non_empty_string_list(translation_layers):
        return fail("translationLayers must be non-empty string[]")

    if role == "graphics-provider":
        provider_lane = str(contract.get("providerLane", "")).strip()
        if not provider_lane:
            return fail("providerLane is required for graphics-provider role")
    else:
        provider_lanes = contract.get("providerLanes")
        if not is_non_empty_string_list(provider_lanes):
            return fail("providerLanes must be non-empty string[] for translation-layer role")
        wrapper_error = validate_wrapper_contract(contract.get("wrapperContract"))
        if wrapper_error:
            return fail(wrapper_error)

    forensic = contract.get("forensic")
    if not isinstance(forensic, dict):
        return fail("forensic block is missing")

    issue_bundle_keys = forensic.get("issueBundleKeys")
    if not is_non_empty_string_list(issue_bundle_keys):
        return fail("forensic.issueBundleKeys must be non-empty string[]")

    live_topics = forensic.get("liveDiagnosticsTopics")
    if not is_non_empty_string_list(live_topics):
        return fail("forensic.liveDiagnosticsTopics must be non-empty string[]")

    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate embedded ae-runtime-contract.json in graphics package"
    )
    parser.add_argument("--artifact", required=True, help="Path to package artifact (.zip or .wcp)")
    parser.add_argument(
        "--lane",
        required=True,
        choices=sorted(LANE_EXPECTATIONS.keys()),
        help="Logical lane name expected by CI contract",
    )
    parser.add_argument(
        "--freewine-lane",
        default="freewine11-arm64ec",
        help="Expected FreeWine lane identifier",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    artifact = pathlib.Path(args.artifact).resolve()
    if not artifact.is_file():
        return fail(f"artifact not found: {artifact}")

    try:
        contract = read_contract(artifact)
    except Exception as exc:  # noqa: BLE001
        return fail(f"failed to read embedded contract from {artifact.name}: {exc}")

    rc = validate_contract(contract, args.lane, args.freewine_lane)
    if rc != 0:
        return rc

    print(
        "[graphics-contract] OK: "
        f"artifact={artifact.name} lane={args.lane} freewine={args.freewine_lane}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
