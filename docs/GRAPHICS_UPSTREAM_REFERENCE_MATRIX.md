# Graphics Upstream Reference Matrix

This is the current external reference snapshot used for graphics package planning.

Date: `2026-03-01`

## Upstreams

- Primary upstream owners currently monitored for this lane:
  - `Mesa3D / freedesktop.org`
  - `doitsujin` (`DXVK`)
  - `HansKristian-Work` (`VKD3D-Proton`)
  - `dege-diosg` (`dgVoodoo2`)
  - `Arihany` (`WCPHub` reference package index)
- External Turnip authors monitored for research and diff-analysis only:
  - `StevenMXZ`
  - `whitebelyash`
  - `Weab-chan`
  - `MrPurple666`

- Mesa GitLab main head: `1e1d8931c7de6316b2c7b4c2c20e370079c23402`
- Mesa latest stable tag: `mesa-26.0.1`
- DXVK latest upstream tag: `v2.7.1`
- VKD3D-Proton latest upstream stable tag: `v3.0`
- VKD3D-Proton latest upstream prerelease tag seen in tags: `v3.0b`
- dgVoodoo2 latest upstream release tag: `v2.86.5`

## WCPHub Reference Packages

From `https://raw.githubusercontent.com/Arihany/WinlatorWCPHub/main/pack.json`:

- Latest DXVK generic reference: `2.7.1`
- Latest DXVK ARM64EC reference: `2.7.1-arm64ec`
- Latest DXVK GPLAsync reference: `2.7.1-1-gplasync`
- Latest DXVK GPLAsync ARM64EC reference: `2.7.1-1-gplasync-arm64ec`
- Latest VKD3D-Proton generic reference: `3.0b`
- Latest VKD3D-Proton ARM64EC reference: `3.0b-arm64ec`

## Current Packaging Direction

- `AeTurnip`: independent curated ZIP lane from the current Turnip author set, with exact Mesa `main` commit metadata.
- `AeOpenGLDriver`: independent pinned `profile.json` ZIP lane, with exact Mesa `main` commit metadata.
- `dgVoodoo`: mirrored upstream ZIP lane through `Contents`.
- `DXVK` / `VKD3D-Proton`: still sourced via existing `Contents` hub references today, but the target direction is to replace those with our own build lanes once the self-build contract is finalized.
- `virgl`: runtime lane is still dormant and remains separate from the current driver ZIP package flow.
