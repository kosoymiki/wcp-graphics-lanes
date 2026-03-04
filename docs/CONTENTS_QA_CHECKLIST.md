# Contents QA Checklist

## Current Closure Status (2026-03-01)

- Repository-side contract closure is already in place:
  - `check-contents-qa-contract.py`
  - `run-wcp-parity-suite.sh`
  - release-prep/final-stage gate integration
- This checklist remains open because UI/device/install behavior still requires
  manual or real-device confirmation.
- Repository-side taxonomy is now aligned to `FreeWine + graphics contents`
  split release repos; what remains open is behavioral QA, not metadata/model drift.
- Current blocker snapshot: `adb` is available, but there is no attached device
  in this session yet, so device-side closure cannot be executed right now.
- Treat this file as the authoritative remaining-plan document for contents work;
  do not infer closure from repository-only gates.

## Static Contract Gate (No Device Required)
- `python3 ci/validation/check-contents-qa-contract.py --root . --output /tmp/contents-qa-contract.md`
- `WLT_WCP_PARITY_REQUIRE_ANY=1 WLT_WCP_PARITY_FAIL_ON_MISSING=1 bash ci/validation/run-wcp-parity-suite.sh`
- `WLT_RELEASE_PREP_RUN_COMMIT_SCAN=0 WLT_RELEASE_PREP_RUN_HARVEST=0 WLT_RELEASE_PREP_RUN_PATCH_BASE=0 bash ci/validation/prepare-release-patch-base.sh`
- This gate validates repository-side invariants for:
  `contents/contents.json`, `artifact-source-map.json`, patch contract tokens in
  `0001-mainline-full-stack-consolidated.patch`, and WCP workflow metadata
  (`WCP_VERSION_CODE/WCP_CHANNEL/WCP_DELIVERY/WCP_PROFILE_TYPE/WCP_DISPLAY_CATEGORY/WCP_RELEASE_TAG`).
- Parity suite validates binary payload parity for configured source/install pairs in
  `ci/validation/wcp-parity-pairs.tsv` (critical path coverage + missing/extra/drift report).

## Contents source and schema
- [x] `ContentsManager.REMOTE_WINE_PROTON_OVERLAY` points to this repo `contents/contents.json`
- [x] `ContentsManager.REMOTE_PROFILES` remains WCP Hub source (`pack.json`) for non-Wine packages
- [x] `ci/contents/validate-contents-json.py contents/contents.json` passes
- [x] `FreeWine` entry points to runtime release repo (`wcp-runtime-lanes`) with rolling tag (`freewine11-arm64ec-latest`)
- [x] Graphics entries point to graphics release repo (`wcp-graphics-lanes`) with per-package rolling tags
- [x] Stable bundle release flow keeps `wcp-stable` publish lane in `ci/release/publish-0.9c.sh`
- [x] `channel`, `delivery`, `displayCategory`, `sourceRepo`, `releaseTag` are present
- [x] Wine-family entries carry `internalType=wine`; Proton legacy lanes are removed from active overlay

## Winlator UI behavior
- [ ] Spinner/category exposes `Wine` lane for FreeWine and graphics lanes for DXVK/VKD3D/Turnip/Vulkan SDK
- [ ] Stable `Wine` overlay package (`freewine11`) is visible in the `Wine` lane
- [ ] Beta/nightly toggle is hidden for `Wine` family tab
- [ ] Rows show source/provenance line for remote packages (repo + release tag)
- [ ] UI does not imply packages are embedded in APK

## Install/update paths
- [ ] Downloading a remote WCP from `Contents` installs successfully
- [ ] Installed package moves from download action to local menu action
- [ ] Duplicate install is rejected cleanly (`content already exist`)
- [ ] Removing an installed `Wine` package fails safely if a container uses it

## Turnip / Adrenotools UX
- [ ] Version picker opens (latest + recent/history entries)
- [ ] Refresh reloads release list
- [ ] Selected Turnip ZIP downloads with progress and installs
- [ ] Installed driver list refreshes without duplicates
- [ ] Network/API failures show user-readable error messages

## CI/WCP metadata parity
- [x] `freewine11` nightly build emits `channel=nightly`, `releaseTag=freewine11-arm64ec-latest`, `versionCode=1`
- [x] `freewine11` nightly build emits `channel=nightly`, `releaseTag=freewine11-arm64ec-latest`, `versionCode=1`
- [x] Graphics lanes emit stable per-package rolling tags from `wcp-graphics-lanes`
- [x] Stable release flow keeps `channel=stable` messaging and `wcp-stable` publish tag

## Immediate Next Device Pass
- [ ] Attach one ADB device and confirm it appears in `adb devices`
- [ ] Refresh/install latest `freewine11` + graphics payloads on-device
- [ ] Verify `Contents` shows FreeWine + graphics lanes on the committed baseline
- [ ] Run install/update/remove checks for `freewine11` and one graphics package

Use `docs/DEVICE_EXECUTION_CHECKLIST_RC005_CONTENTS.md` as the exact execution
order once a device is attached.
