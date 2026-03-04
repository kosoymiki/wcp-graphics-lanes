# Repo Split Topology

This document defines the mandatory split between source/control and release lanes.

## Repositories

- `kosoymiki/winlator-wine-proton-arm64ec-wcp`
  - Control repo: CI scripts, patch-base, docs, `contents/contents.json`.
  - Must not be used as a runtime/graphics release artifact host.
- `kosoymiki/freewine11`
  - Native FreeWine source tree repository.
  - Primary development branch: `main` (mirrors local `freewine11-main`).
- `kosoymiki/aeolator`
  - Ae.solator APK release repository (`winlator-latest` lane).
- `kosoymiki/wcp-runtime-lanes`
  - Runtime WCP release repository.
  - Active tag: `freewine11-arm64ec-latest`.
- `kosoymiki/wcp-graphics-lanes`
  - Graphics/Vulkan WCP+ZIP release repository.
  - Active tags: `aeturnip-arm64-latest`, `aeopengl-driver-arm64-latest`,
    `dgvoodoo-latest`, `dxvk-gplasync-latest`, `dxvk-gplasync-arm64ec-latest`,
    `vkd3d-proton-latest`, `vkd3d-proton-arm64ec-latest`,
    `vulkan-sdk-arm64-latest`, `vulkan-sdk-x86_64-latest`.

## Contract Rules

1. `contents/contents.json` and `ci/winlator/artifact-source-map.json` must reference only split release repos.
2. Legacy runtime lanes (`proton-ge10`, `protonwine10`) are removed from active overlay and active workflows.
3. Any new package lane must declare `sourceRepo` to its dedicated release repo.
4. Release cleanup must remove stale WCP assets from control-repo releases.

## Migration Status

- Split repos are created and active.
- FreeWine source tree is tracked independently in `freewine11`.
- Workflows are routed to split release repos.
- Remaining task: keep archival docs as history only; do not treat them as active release topology.
