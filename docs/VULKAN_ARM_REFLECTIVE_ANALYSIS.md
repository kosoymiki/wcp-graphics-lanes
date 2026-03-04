# Vulkan ARM Reflective Analysis

Date: 2026-03-01

## Scope

Reference repo:
- https://github.com/jakoch/vulkan-sdk-arm

Reference loader docs:
- https://vulkan.lunarg.com/doc/view/latest/linux/LoaderInterfaceArchitecture.html

Pinned latest Linux SDK checked from LunarG `latest/linux.json` on 2026-03-01:
- `1.4.341.1`

## Findings

The upstream ARM-focused repo is intentionally narrow. It does not carry runtime patches for Winlator, Wine, Turnip, DXVK, or VKD3D. It automates one specific gap in the ecosystem:

- build the official LunarG Vulkan SDK on Linux ARM64 runners
- replace missing x86_64-only binaries with aarch64 builds
- keep loader, validation layers, extension layer, tools, and shaderc available on ARM64 CI

The repo's useful design signals for this fork are:

- use native `ubuntu-24.04-arm` runners
- build only the Vulkan components that matter for loader and diagnostics
- package the rebuilt SDK as a reproducible artifact
- keep CI logic separate from app/runtime policy

## Applicability To Ae.solator

Directly applicable:

- ARM64 Vulkan SDK artifact workflow for diagnostics and future packaging
- Vulkan loader modernization in runtime env:
  - `VK_DRIVER_FILES` alongside `VK_ICD_FILENAMES`
  - explicit loader debug policy
  - explicit validation-layer policy
- forensic normalization for loader/layer/validation failures

Not directly applicable:

- copying the whole release model unchanged
- dual Ubuntu matrix (`22.04-arm`, `24.04-arm`) for our repo
- shipping the entire SDK inside the Android app

These do not fit the current X11-first Winlator runtime or the current artifact structure.

## Adopted In This Repo

1. Added `ci/vulkan/build-sdk-arm.sh`
2. Added `.github/workflows/ci-vulkan-sdk-arm.yml`
3. Extended app graphics policy with:
   - Vulkan loader debug
   - Vulkan validation layer
4. Extended runtime env and forensic logs with:
   - `VK_DRIVER_FILES`
   - explicit Vulkan policy snapshot fields
5. Extended runtime log assembler with:
   - validation error detection
   - loader failure detection
   - missing layer / ICD detection
6. Added native Vulkan API lane policy in Winlator:
   - dynamic selector now exposes `auto`, `1.1`, `1.2`, `1.3`, `1.4`
   - runtime emits `requested/detected/effective/reason`
   - default container lane moves from static `1.3` to `auto`
7. Added WCP metadata for Vulkan provenance:
   - `WCP_VULKAN_SDK_VERSION=1.4.341.1`
   - `WCP_VULKAN_API_LANE=1.4`
   - `WCP_VULKAN_SDK_LANES=1.1,1.2,1.3,1.4`
   - release notes and forensic manifest now carry Vulkan lane metadata
8. Added native bionic Vulkan runtime embedding for WCP:
   - materialize wrapper ICD from `app/assets/graphics_driver/wrapper.tzst`
   - materialize validation layer from `app/assets/layers.tzst`
   - prefer embedded WCP `share/vulkan/icd.d/wrapper_icd.aarch64.json` at runtime
   - keep `imagefs/usr/share/vulkan` as fallback only

## Runtime Decision

The ARM64 Ubuntu/glibc SDK artifact remains useful for CI provenance and future tooling, but it must not be injected directly into current `bionic-native` WCP packages.

Reason:

- the CI-built LunarG SDK artifact is glibc-linked
- current WCP packages target `bionic-native`
- direct glibc payload embedding would create ABI risk in Winlator runtime

So the current repo now uses a split model:

- CI ARM SDK artifact for reference/provenance
- embedded bionic Vulkan runtime in WCP from Ae.solator app assets
- API lanes `1.1/1.2/1.3/1.4` controlled in Winlator policy, not as four separate SDK payloads

## Deferred

- automatic release publication for ARM64 Vulkan SDK artifacts
- consuming the rebuilt glibc SDK artifact as a tool-only sidecar
- expanding the bionic runtime payload beyond wrapper ICD and validation layer
- shipping a complete bionic api-dump layer in addition to validation

These should be done only after the current package patch-base is stabilized and the black-screen path is closed.
