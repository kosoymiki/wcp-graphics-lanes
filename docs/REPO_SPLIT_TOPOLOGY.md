# Repo Split Topology

Final split model for graphics/runtime package ownership.

## Repositories

- `kosoymiki/aesolator`
  - Android app repository (launcher/UI/Contents consumer).
- `kosoymiki/freewine11`
  - Native FreeWine source tree.
- `kosoymiki/wcp-runtime-lanes` (**WCP Archive**)
  - Canonical WCP host for:
    - `freewine11-arm64ec-latest`
    - `dxvk-gplasync-latest`
    - `dxvk-gplasync-arm64ec-latest`
    - `vkd3d-proton-latest`
    - `vkd3d-proton-arm64ec-latest`
    - `vulkan-sdk-arm64-latest`
    - `vulkan-sdk-x86_64-latest`
    - `dgvoodoo-latest`
- `kosoymiki/wcp-graphics-lanes`
  - Graphics build/control repo and release host for ZIP graphics providers:
    - `aeturnip-arm64-latest`
    - `aeopengl-driver-arm64-latest`
  - Build owner for archive lane:
    - `dgvoodoo-latest` (published as `dgvoodoo.wcp` to `wcp-runtime-lanes`)
- `kosoymiki/winlator-wine-proton-arm64ec-wcp`
  - Legacy monorepo (archived history only, not active source-of-truth).

## Contract Rules

1. `sourceRepo` in package metadata must match the actual release host.
2. DXVK/VKD3D/VulkanSDK are archive lanes (`wcp-runtime-lanes`), not graphics release lanes.
3. Turnip/OpenGL ZIP lanes remain in `wcp-graphics-lanes`; dgVoodoo ships as WCP via archive.
4. Legacy monorepo tags are out of active delivery topology.

## Status

- Split ownership is active in CI/workflows.
- Contents metadata routes runtime/archive and graphics lanes separately.
