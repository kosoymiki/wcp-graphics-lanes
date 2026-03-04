# Content Packages Architecture (Ae.solator)

## Goal

`Contents` must expose package provenance and install intent clearly:

- runtime/archive WCP lanes,
- graphics provider ZIP lanes,
- stable remote delivery without implying APK-embedded payloads.

## Sources of Truth

- Metadata index: `contents/contents.json`
- Artifact parity map: `ci/winlator/artifact-source-map.json`
- App overlay consumer: `kosoymiki/aesolator` (`ContentsManager.REMOTE_WINE_PROTON_OVERLAY`)

## Release Ownership

- `kosoymiki/wcp-runtime-lanes` (**WCP Archive**):
  - `freewine11-arm64ec`
  - `vulkan-sdk-*`
  - `dxvk-gplasync*`
  - `vkd3d-proton*`
  - `dgvoodoo`
- `kosoymiki/wcp-graphics-lanes`:
  - `aeturnip-arm64.zip`
  - `aeopengl-driver-arm64.zip`

`sourceRepo` and artifact URLs must match this ownership model exactly.

## Entry Model

Mandatory metadata fields:

- `type`, `internalType`, `verName`, `verCode`
- `channel`, `delivery`, `displayCategory`
- `sourceRepo`, `releaseTag`, `artifactName`
- `remoteUrl`, `sha256Url`

Graphics/runtime contract fields:

- `runtimeContract` for `turnip` / `freedreno` / `dxvk` / `vkd3d`
- `forensicContract` for issue-bundle/live diagnostics key-space
- `wrapperContract` for translation lanes (`dxvk`, `vkd3d`)

## Routing Policy

1. Vulkan-first route is default (`turnip-vulkan`).
2. OpenGL fallback lane remains explicit (`freedreno-opengl` / `wined3d` legacy fallback).
3. Translation lanes (DXVK/VKD3D/dgVoodoo) are WCP Archive lanes, even if built from graphics CI.
4. Provider lanes (Turnip/OpenGL) remain graphics ZIP lanes.

## Contract Propagation

Build scripts must embed the same lane/provenance contract into payload metadata
so `contents/contents.json`, `artifact-source-map.json`, and final artifacts stay
in sync for diagnostics and reproducible installs.
