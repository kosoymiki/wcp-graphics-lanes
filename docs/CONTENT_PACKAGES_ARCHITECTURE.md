# Content Packages Architecture (Ae.solator)

## Goal
`Contents` in Ae.solator must clearly separate:
- local installed packages,
- downloadable packages,
- stable vs beta/nightly channels,
without implying that our Wine/Proton packages are embedded inside the APK.

## Source of truth
- Repository file: `contents/contents.json`
- Runtime URL in app: `raw.githubusercontent.com/<repo>/main/contents/contents.json`
- Package assets: GitHub Releases of this repository (`wcp-stable` + per-package rolling `*-latest` tags)

## Entry model (extended, backward-compatible)
Required legacy fields still supported:
- `type`, `verName`, `verCode`, `remoteUrl`

New/extended fields used by this fork:
- `channel`: `stable | beta | nightly` (primary visibility filter)
- `delivery`: `remote | embedded` (UI honesty; current WCP entries use `remote`)
- `internalType`: Wine-family subtype (`wine | proton | protonge | protonwine`) for deterministic package identity
- `displayCategory`: UI label override; current overlay mirrors the top-level family category (`Wine` or `Proton`)
- `sourceRepo`: provenance (`owner/repo`)
- `releaseTag`: release source (`wcp-stable` or per-package rolling tag like `wine-11-arm64ec-latest`)

## Filtering policy
1. Stable entries are always visible.
2. `Show beta / nightly` toggle controls `beta` and `nightly` entries for non-Wine-family content lanes.
3. The repo-backed Wine/Proton overlay is intentionally presented as a stable-only track in UI, even when the release tag is a rolling `*-latest` tag.
4. Legacy entries without `channel` use fallback heuristics (`beta/nightly` in metadata/URL).

## Type and display mapping
- Top-level type is now explicit: `Wine` for Wine rows, `Proton` for Proton-family rows.
- Wine-family subtype remains in `internalType` (`wine/proton/protonge/protonwine`) for deterministic package identity and backward-compatible heuristics.
- UI display category mirrors the top-level type (`Wine` or `Proton`) instead of collapsing both into one label.
- Winlator still treats both categories as one runtime family for install/update and compatibility code paths.

## Turnip vs Contents
- Turnip driver downloads remain upstream-sourced and are handled by `Adrenotools`.
- Wine/Proton content packages are distributed from this repo releases and surfaced through `Contents`.

## Graphics translation payload families

Contents metadata and release notes should keep naming consistent for these
external payload families:

- `DXVK`
- `VKD3D`
- `D8VK`

## Packaging metadata propagation
WCP build scripts inject the same metadata into `profile.json` (`type`, `channel`, `delivery`, `displayCategory`, `sourceRepo`, `releaseTag`) so installed packages retain the same provenance and family category as the remote overlay row.
