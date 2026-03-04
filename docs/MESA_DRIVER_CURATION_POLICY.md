# Mesa Driver Curation Policy

This document is the current policy for `AeTurnip`, `AeOpenGLDriver`, and the graphics driver curation lanes that track Mesa.

## Source Of Truth

- Mesa upstream source-of-truth is the official GitLab repo: `https://gitlab.freedesktop.org/mesa/mesa.git`
- CI resolves two Mesa refs:
  - the latest stable tag from Git tags (`mesa-*`, excluding `rc`)
  - the exact current `refs/heads/main` commit
- Package metadata uses the exact `main` commit as the authoritative moving upstream ref.
- The nearest stable tag is still recorded for human comparison and rollback context.
- On `2026-03-01`, the latest stable tag resolved by that contract was `mesa-26.0.1`, and the exact `main` head resolved was `1e1d8931c7de6316b2c7b4c2c20e370079c23402`.

## AeTurnip

- Delivery format: adrenotools-compatible ZIP installed via `Contents`.
- Payload source: independent Turnip ZIP release from the curated author set.
- Priority order:
  - `StevenMXZ/freedreno_turnip-CI`
  - `whitebelyash/freedreno_turnip-CI`
  - `Weab-chan/freedreno_turnip-CI`
  - `MrPurple666/purple-turnip`
- Normalize the package before publish:
  - extract the chosen external ZIP that contains a root `meta.json`
  - flatten to a root-level ZIP (no nested wrapper directory)
  - stamp `provider=aeturnip`
  - keep the chosen independent payload intact
  - add `aero-source.json` with source-release + Mesa provenance

Why this is safe now:

- It preserves a validated independent payload instead of pretending we can cross-compile Mesa Turnip safely inside this repo today.
- It still pins every published package to an explicitly resolved exact Mesa `main` commit for provenance and review.

What is intentionally not done yet:

- No in-repo Mesa Turnip compile lane.
- No blind merge of every external Turnip tweak. Only the newest valid ZIP from the curated priority list is accepted.

## AeOpenGLDriver

- Delivery format: `profile.json` ZIP installed via `Contents`.
- Payload source: validated fallback GL overlay extracted from a pinned external payload source ref.
- Current payload purpose:
  - provide clean `libGL` / `libglapi` fallback for the `freedreno-gallium` OpenGL lane
  - keep Vulkan ownership with the separate Turnip lane

Why this is safe now:

- It keeps the OpenGL lane narrow and avoids silently mutating the Vulkan provider.
- It uses a pinned external payload ref instead of coupling the lane to whichever `latest` app asset exists at build time.

What is intentionally not done yet:

- No full Mesa Gallium compile lane in CI.
- No attempt to replace the whole Mesa userspace with a mixed, harder-to-verify build.

## dgVoodoo

- Delivery format: upstream ZIP mirrored into our own release lane and installed via `Contents`.
- Upstream source: `dege-diosg/dgVoodoo2`
- Current mirror policy:
  - take the latest upstream release ZIP
  - reject debug/dev64 side assets
  - verify the ZIP contains an `MS/x86` runtime tree
  - preserve exact upstream version in metadata so local and remote installs merge cleanly

## Curated Authors

These are the current named upstream authors or curation sources used for active Turnip curation and future Mesa analysis:

- `StevenMXZ`
- `whitebelyash`
- `Weab-chan`
- `MrPurple666`
- `dege-diosg`

For `DXVK`, `VKD3D-Proton`, and `virgl`, we currently track upstream/reference lanes separately and do not ingest extra donor binary variants into the graphics ZIP package flow.

## Transfer Boundaries

Use these rules when expanding the graphics stack:

- Prefer `Turnip + Zink` as the Vulkan-first path.
- Keep `freedreno-gallium` as a bounded OpenGL fallback lane.
- Do not collapse the Vulkan and OpenGL providers into one opaque package.
- Treat external improvements as analysis input, not as direct binary ownership transfer.
