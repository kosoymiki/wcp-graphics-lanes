# Graphics Donor Integration Matrix

This file records which donor graphics/runtime ideas are safe to transfer into
the current mainline and which ones require a separate architecture lane.

## Status Snapshot

Date: `2026-03-04`

Current mainline accepts only contract-safe, observable transfers. We do not
blind-import donor graphics stacks into the current Winlator runtime.

## Donor Matrix

### `MiceWine` / `Lorie`

- Source: `https://github.com/KreitinnSoftware/MiceWine-Application`
- Status: `partially adopted`
- Adopted now:
  - X11 focus re-arm after attach/config changes
  - low-latency `requestUnbufferedDispatch()` on first touch-down
  - memory-safe `Vulkan-first` policy work continues in mainline, but not from a full donor transplant
- Explicitly not adopted:
  - native `Xlorie` server replacement
  - donor renderer/native bridge ownership
  - donor-wide memory/runtime policy as a wholesale import
  - full UI/UX surface and settings flow

### `dgVoodoo2`

- Source: `https://dege.freeweb.hu/`
- Status: `active as archive WCP lane`
- Current rule:
  - active `dgVoodoo` package lanes in `Contents` (`dgvoodoo-x86_64.wcp`, `dgvoodoo-arm64ec.wcp`)
  - release host: `wcp-runtime-lanes` (`dgvoodoo-x86_64-latest`, `dgvoodoo-arm64ec-latest`)
  - build/proxy orchestration owner: `wcp-graphics-lanes`
  - translation route contracts include `dgVoodoo` as legacy API lane with explicit fallback to `WineD3D`

### `freedreno` / `Turnip` / Gallium

- Source: `https://docs.mesa3d.org/drivers/freedreno.html`
- Status: `source-build lane active`, `provider split active`
- Current mainline:
  - `AeTurnip` is built from Mesa upstream sources in CI
  - `AeOpenGLDriver` fallback is built from Mesa upstream sources in CI
  - now carries separate internal provider contract fields for:
    - `Vulkan provider` (`turnip` vs `system`)
    - `OpenGL provider` (`zink`, `freedreno-gallium`, `system`)
    - `OpenGL fallback` (`freedreno-gallium`, `system`, `none`)
  - default policy is now `Vulkan-first` (`Turnip + Zink`) with `freedreno-gallium` fallback
- Required before deeper integration:
  - expand patchset quality gates per lane (`turnip` vs `opengl`)
  - device/runtime matrix to prevent mismatched OpenGL/Vulkan providers on older SoCs
  - optional virgl lane without coupling to Turnip/OpenGL package ownership

### `virgl`

- Source: `https://gitlab.freedesktop.org/virgl/virglrenderer`
- Status: `code present, lane dormant`
- Current mainline:
  - `VirGLRendererComponent` exists in tree
  - no active end-to-end runtime lane exposes it in the current container/launcher path
- Required before activation:
  - graphics-driver selection contract
  - socket/env ownership for guest-side virgl client
  - explicit QA lane for virgl-only rendering and fallback

### `vortek`

- Source of evidence:
  - local reverse snapshots from GameNative branches and APK inspection
- Status: `reverse-only evidence`, `not integrated`
- Safe current rule:
  - do not transplant opaque donor binaries into mainline without provenance and runtime contract coverage
- Required before activation:
  - provenance and package source definition
  - explicit library ownership and ABI checks
  - fallback routing if `libvulkan_vortek.so` is unavailable or mismatched

## Mainline Rule

Only two classes of donor transfer are allowed directly into current mainline:

- view/input lifecycle improvements that preserve current runtime ownership
- env/forensic contract improvements that make future runtime lanes observable

Anything that changes graphics-driver ownership, loader routing, or native
server components must land as a dedicated lane with its own package contract,
fallback path, and regression gate.

## Execution Order

Current progression for deeper graphics work remains:

1. keep `AeTurnip` and `AeOpenGLDriver` source-build lanes green on latest Mesa
2. keep `Turnip Vulkan` and `freedreno-gallium OpenGL` providers separated in package/runtime routing
3. activate the dormant `virgl` lane with explicit routing/fallback
4. design `AeroXServer` as a new backend behind adapters, not as a blind rewrite
