# WCP Graphics Lanes

Graphics build/control repository for Ae.solator.

## Scope

- Build graphics packages and wrapper contracts from source:
  - AeTurnip ZIP (Mesa main, Android)
  - AeOpenGLDriver ZIP (Mesa main, Android GL fallback)
  - dgVoodoo WCP (upstream wrapper + proxy overlay)
  - DXVK GPLAsync WCP
  - VKD3D-Proton WCP
  - Vulkan SDK WCP
- Embed runtime compatibility metadata:
  - `ae-runtime-contract.json`
  - `wrapperContract`
  - `ae-runtime-wrapper.env`

## Current Mainline State

- This repository owns graphics/provider package lanes, not the main runtime.
- Runtime source-of-truth remains `freewine11`.
- Archive/release host for runtime/APK remains `wcp-runtime-lanes`.
- This repository is the source-of-truth for:
  - AeTurnip ZIP
  - AeOpenGLDriver ZIP
  - graphics-side wrapper/package lane build logic

## Release Routing

- Release host in this repo:
  - `aeturnip-arm64-latest`
  - `aeopengl-driver-arm64-latest`
- Release host in **WCP Archive** (`kosoymiki/wcp-runtime-lanes`):
  - `dgvoodoo-x86_64-latest`
  - `dgvoodoo-arm64ec-latest`
  - `dxvk-gplasync-latest`
  - `dxvk-gplasync-arm64ec-latest`
  - `vkd3d-proton-latest`
  - `vkd3d-proton-arm64ec-latest`
  - `vulkan-sdk-arm64-latest`
  - `vulkan-sdk-x86_64-latest`

## Main Workflows

- `.github/workflows/ci-graphics-drivers.yml`
- `.github/workflows/ci-vulkan-sdk-arm.yml`

## dgVoodoo Source Modes

- `ci/graphics/build-dgvoodoo-wcp.sh` supports:
  - upstream mode (`DGVOODOO_SOURCE_MODE=upstream`) with `dev64` asset preference (used in CI)
  - pinned local ingest (`DGVOODOO_SOURCE_MODE=local`, `DGVOODOO_LOCAL_ZIP=/path/to/dgVoodoo2_86_5_dev64.zip`)
- CI emits two architecture lanes:
  - `dgvoodoo-x86_64.wcp` (`dgvoodoo-x86_64-latest`)
  - `dgvoodoo-arm64ec.wcp` (`dgvoodoo-arm64ec-latest`)

## Docs

- `docs/REPO_SPLIT_TOPOLOGY.md`
- `docs/CONTENT_PACKAGES_ARCHITECTURE.md`
- `docs/CONTENTS_QA_CHECKLIST.md`
- `docs/GRAPHICS_UPSTREAM_REFERENCE_MATRIX.md`
- `docs/MESA_DRIVER_CURATION_POLICY.md`
