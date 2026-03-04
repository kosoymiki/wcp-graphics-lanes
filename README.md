# WCP Graphics Lanes

Graphics and Vulkan packaging repository for Aeolator Contents.

## Scope

- Build and publish:
  - AeTurnip ZIP lane
  - AeOpenGLDriver ZIP lane
  - dgVoodoo ZIP lane
  - DXVK GPLAsync WCP lanes (generic + arm64ec)
  - VKD3D-Proton WCP lanes (generic + arm64ec)
  - Vulkan SDK WCP lanes (arm64 + x86_64)

## Release Host

- All graphics lanes are published in `kosoymiki/wcp-graphics-lanes` releases.
- App/runtime consumers:
  - `kosoymiki/aeolator`
  - `kosoymiki/wcp-runtime-lanes`

## Main Workflows

- `.github/workflows/ci-graphics-drivers.yml`
- `.github/workflows/ci-vulkan-sdk-arm.yml`

## Docs

- `docs/REPO_SPLIT_TOPOLOGY.md`
- `docs/CONTENT_PACKAGES_ARCHITECTURE.md`
- `docs/CONTENTS_QA_CHECKLIST.md`
- `docs/GRAPHICS_UPSTREAM_REFERENCE_MATRIX.md`
- `docs/MESA_DRIVER_CURATION_POLICY.md`
