# Mesa Patchset Contract

Patch intake for source-built Mesa lanes is split by scope:

- `common/` - patches shared by both `AeTurnip` and `AeOpenGLDriver`
- `turnip/` - Vulkan Turnip-specific patches
- `opengl/` - OpenGL fallback-specific patches

Rules:

1. Use one logical change per patch file.
2. Keep patch names stable and descriptive.
3. Patches must apply cleanly to the resolved Mesa `main` commit.
4. Build scripts record applied patch count and patch list into package provenance files.
