# Mesa Driver Curation Policy

This document defines the build contract for `AeTurnip` and `AeOpenGLDriver`.

## Source Of Truth

- Primary upstream: `https://gitlab.freedesktop.org/mesa/mesa.git`
- Build scripts always resolve:
  - latest Mesa stable tag (`mesa-*`, non-rc) for provenance
  - exact `refs/heads/main` commit for build input
- Published packages must record both values in metadata (`meta.json`, `mesa-source.json`, release notes).

## Build Model

- `AeTurnip` and `AeOpenGLDriver` are source-built in CI from Mesa `main`.
- No external prebuilt donor ZIP payload is used as final package content.
- Donor repositories are used only as patch-analysis input.

## AeTurnip Lane

- Format: adrenotools ZIP (`aeturnip-arm64.zip`) for `Contents`.
- Build target: Android aarch64, `vulkan-drivers=freedreno`, `freedreno-kmds=kgsl`.
- Output contract:
  - `libvulkan_freedreno.so`
  - `meta.json`
  - `aero-source.json`
- Patch intake:
  - `ci/graphics/mesa-patches/common/*.patch`
  - `ci/graphics/mesa-patches/turnip/*.patch`

## AeOpenGLDriver Lane

- Format: `profile.json` ZIP (`aeopengl-driver-arm64.zip`) for `Contents`.
- Build target: Android aarch64 with X11 fallback route for `libGL`.
- `libglapi` is packaged only when Mesa emits a shared `libglapi.so`; static embedding is accepted.
- Dependency sysroot: resolved from Termux AArch64 package index at build time.
- Output contract:
  - `usr/lib/libGL.so.1.5.0`
  - optional: `usr/lib/libglapi.so.0.0.0`
  - `profile.json`
  - `mesa-source.json`
- Patch intake:
  - `ci/graphics/mesa-patches/common/*.patch`
  - `ci/graphics/mesa-patches/opengl/*.patch`

## Donor Integration Rule

- Allowed: convert donor improvements to explicit Mesa patch files inside `ci/graphics/mesa-patches`.
- Not allowed: shipping donor binary artifacts as first-class AE packages.
- Every accepted donor change must be attributable to a patch file and reflected in `appliedPatchCount`.

## Boundaries

- Keep Vulkan route and OpenGL route separate at package identity level.
- Do not collapse Turnip and OpenGL fallback into one opaque payload.
- `DXVK`, `VKD3D-Proton`, and Vulkan SDK lanes remain independent package lanes.
