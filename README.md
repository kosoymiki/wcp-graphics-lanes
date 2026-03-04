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

## Release Routing

- Release host in this repo:
  - `aeturnip-arm64-latest`
  - `aeopengl-driver-arm64-latest`
- Release host in **WCP Archive** (`kosoymiki/wcp-runtime-lanes`):
  - `dgvoodoo-latest`
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
  - upstream auto mode (`DGVOODOO_SOURCE_MODE=auto`) with `dev64` asset preference
  - pinned local ingest (`DGVOODOO_SOURCE_MODE=local`, `DGVOODOO_LOCAL_ZIP=/path/to/dgVoodoo2_86_5_dev64.zip`)
- This keeps archive output stable (`dgvoodoo.wcp`) while allowing direct import of dev64-formatted upstream ZIPs.

## Docs

- `docs/REPO_SPLIT_TOPOLOGY.md`
- `docs/CONTENT_PACKAGES_ARCHITECTURE.md`
- `docs/CONTENTS_QA_CHECKLIST.md`
- `docs/GRAPHICS_UPSTREAM_REFERENCE_MATRIX.md`
- `docs/MESA_DRIVER_CURATION_POLICY.md`
