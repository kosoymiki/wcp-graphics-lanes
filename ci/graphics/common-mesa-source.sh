#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# shellcheck disable=SC1091
source "${ROOT_DIR}/ci/graphics/common-mesa.sh"

: "${MESA_ANDROID_API_LEVEL:=28}"
: "${MESA_TERMUX_REPO_BASE_URL:=https://packages.termux.dev/apt/termux-main}"
: "${MESA_TERMUX_PACKAGES_INDEX_URL:=${MESA_TERMUX_REPO_BASE_URL}/dists/stable/main/binary-aarch64/Packages}"
: "${MESA_TERMUX_SEED_PACKAGES:=libdrm libx11 libxext libxfixes libxrender libxshmfence libxxf86vm libandroid-shmem zstd xorgproto libxcb}"
: "${MESA_TERMUX_RUNPATH:=/data/data/com.termux/files/usr/bin/../../usr/lib}"

require_cmd() {
  local cmd="${1:?command name required}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf '[mesa][error] required command is missing: %s\n' "${cmd}" >&2
    exit 1
  fi
}

resolve_android_ndk_bin_dir() {
  local ndk_root="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
  if [[ -z "${ndk_root}" ]]; then
    printf '[mesa][error] ANDROID_NDK_ROOT (or ANDROID_NDK_HOME) is required\n' >&2
    exit 1
  fi
  local ndk_bin="${ndk_root}/toolchains/llvm/prebuilt/linux-x86_64/bin"
  if [[ ! -x "${ndk_bin}/clang" ]]; then
    printf '[mesa][error] Android NDK clang not found: %s\n' "${ndk_bin}/clang" >&2
    exit 1
  fi
  printf '%s' "${ndk_bin}"
}

mesa_checkout_exact_commit() {
  local checkout_dir="${1:?checkout dir required}"
  local commit="${2:?mesa commit required}"
  rm -rf "${checkout_dir}"
  mkdir -p "${checkout_dir}"
  git -C "${checkout_dir}" init -q
  git -C "${checkout_dir}" remote add origin "${MESA_SOURCE_GIT_URL}"
  git -C "${checkout_dir}" fetch --depth 1 origin "${commit}"
  git -C "${checkout_dir}" checkout --detach FETCH_HEAD
}

list_mesa_patch_candidates() {
  local patch_root="${1:?patch root required}"
  local lane="${2:?lane required}"
  local scope
  for scope in common "${lane}"; do
    local scope_dir="${patch_root}/${scope}"
    if [[ -d "${scope_dir}" ]]; then
      find "${scope_dir}" -maxdepth 1 -type f -name '*.patch' | LC_ALL=C sort
    fi
  done
}

apply_mesa_patchset() {
  local source_dir="${1:?source dir required}"
  local patch_root="${2:?patch root required}"
  local lane="${3:?lane required}"
  local log_path="${4:?log path required}"

  : > "${log_path}"
  local applied=0
  local patch_file

  while IFS= read -r patch_file; do
    [[ -n "${patch_file}" ]] || continue
    if ! git -C "${source_dir}" apply --check "${patch_file}"; then
      printf '[mesa][error] patch does not apply cleanly: %s\n' "${patch_file}" >&2
      exit 1
    fi
    git -C "${source_dir}" apply "${patch_file}"
    if [[ "${patch_file}" == "${ROOT_DIR}/"* ]]; then
      printf '%s\n' "${patch_file#${ROOT_DIR}/}" >> "${log_path}"
    else
      printf '%s\n' "${patch_file}" >> "${log_path}"
    fi
    applied=$((applied + 1))
  done < <(list_mesa_patch_candidates "${patch_root}" "${lane}")

  printf '%s' "${applied}"
}

disable_freedreno_libarchive_fallback() {
  local source_dir="${1:?source dir required}"
  local meson_file="${source_dir}/src/freedreno/meson.build"

  if [[ ! -f "${meson_file}" ]]; then
    return 0
  fi

  # libarchive is optional for freedreno tools. Fallback subproject pulls OpenSSL
  # headers that are not part of Android NDK toolchains and breaks cross builds.
  sed -i -E \
    "s/dependency\\('libarchive',[[:space:]]*allow_fallback:[[:space:]]*true/dependency('libarchive', allow_fallback: false/" \
    "${meson_file}"
}

prepare_android_cutils_trace_stub() {
  local include_root="${1:?include root required}"
  mkdir -p "${include_root}/cutils" "${include_root}/log"
  cat > "${include_root}/cutils/native_handle.h" <<'EOF_NATIVE_HANDLE_H'
#ifndef CUTILS_NATIVE_HANDLE_H
#define CUTILS_NATIVE_HANDLE_H

#include <android/native_handle.h>

#endif
EOF_NATIVE_HANDLE_H
  cat > "${include_root}/cutils/trace.h" <<'EOF_TRACE_H'
#ifndef CUTILS_TRACE_H
#define CUTILS_TRACE_H

#include <stdint.h>

#ifndef ATRACE_TAG_GRAPHICS
#define ATRACE_TAG_GRAPHICS 0
#endif

static inline void atrace_init(void) {}
static inline void atrace_begin(uint64_t tag, const char *name)
{
  (void)tag;
  (void)name;
}
static inline void atrace_end(uint64_t tag)
{
  (void)tag;
}

#endif
EOF_TRACE_H
  cat > "${include_root}/cutils/properties.h" <<'EOF_PROPERTIES_H'
#ifndef CUTILS_PROPERTIES_H
#define CUTILS_PROPERTIES_H

#include <string.h>

#ifndef PROPERTY_VALUE_MAX
#define PROPERTY_VALUE_MAX 92
#endif

#ifndef PROPERTY_KEY_MAX
#define PROPERTY_KEY_MAX 32
#endif

static inline int property_get(const char *key, char *value, const char *default_value)
{
  (void)key;
  if (!value) return 0;
  if (!default_value) {
    value[0] = '\0';
    return 0;
  }
  size_t len = strlen(default_value);
  if (len >= PROPERTY_VALUE_MAX) len = PROPERTY_VALUE_MAX - 1;
  memcpy(value, default_value, len);
  value[len] = '\0';
  return (int)len;
}

static inline int property_set(const char *key, const char *value)
{
  (void)key;
  (void)value;
  return 0;
}

#endif
EOF_PROPERTIES_H
  cat > "${include_root}/log/log.h" <<'EOF_LOG_H'
#ifndef LOG_LOG_H
#define LOG_LOG_H

#include <android/log.h>

#ifndef LOG_PRI
#define LOG_PRI(priority, tag, ...) __android_log_print((priority), (tag), __VA_ARGS__)
#endif

#endif
EOF_LOG_H
  if [[ ! -d "${include_root}/spirv-tools" ]]; then
    if [[ -d /usr/include/spirv-tools ]]; then
      cp -a /usr/include/spirv-tools "${include_root}/"
    elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
      local archive_path="${include_root}/.spirv-tools-main.tar.gz"
      local unpack_dir="${include_root}/.spirv-tools-main"
      rm -rf "${unpack_dir}" "${archive_path}"
      if curl -fsSL "https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/heads/main.tar.gz" -o "${archive_path}"; then
        mkdir -p "${unpack_dir}"
        if tar -xzf "${archive_path}" -C "${unpack_dir}" --strip-components=2 "SPIRV-Tools-main/include/spirv-tools"; then
          if [[ -d "${unpack_dir}/spirv-tools" ]]; then
            cp -a "${unpack_dir}/spirv-tools" "${include_root}/"
          fi
        fi
      fi
      rm -rf "${unpack_dir}" "${archive_path}"
    fi
  fi
  printf '%s' "${include_root}"
}

lines_file_to_json_array() {
  local lines_path="${1:?lines file required}"
  python3 - <<'PY' "${lines_path}"
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
rows = []
if path.is_file():
    rows = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
print(json.dumps(rows, ensure_ascii=True))
PY
}

write_mesa_native_file() {
  local native_file="${1:?native file path required}"
  cat > "${native_file}" <<'EOF_NATIVE'
[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
strip = 'strip'
pkg-config = '/usr/bin/pkg-config'
EOF_NATIVE
}

write_mesa_android_cross_file() {
  local cross_file="${1:?cross file path required}"
  local ndk_bin="${2:?ndk bin dir required}"
  local api_level="${3:?api level required}"
  local target="${4:-aarch64-linux-android}"

  cat > "${cross_file}" <<EOF_CROSS
[binaries]
ar = '${ndk_bin}/llvm-ar'
c = '${ndk_bin}/${target}${api_level}-clang'
cpp = '${ndk_bin}/${target}${api_level}-clang++'
strip = '${ndk_bin}/llvm-strip'
pkg-config = '/usr/bin/pkg-config'
c_ld = '${ndk_bin}/ld.lld'
cpp_ld = '${ndk_bin}/ld.lld'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF_CROSS
}

write_mesa_android_x11_cross_file() {
  local cross_file="${1:?cross file path required}"
  local ndk_bin="${2:?ndk bin dir required}"
  local api_level="${3:?api level required}"
  local pkg_config_wrapper="${4:?pkg-config wrapper path required}"
  local target="${5:-aarch64-linux-android}"

  cat > "${cross_file}" <<EOF_CROSS
[binaries]
ar = '${ndk_bin}/llvm-ar'
c = '${ndk_bin}/${target}${api_level}-clang'
cpp = '${ndk_bin}/${target}${api_level}-clang++'
strip = '${ndk_bin}/llvm-strip'
pkg-config = '${pkg_config_wrapper}'
c_ld = '${ndk_bin}/ld.lld'
cpp_ld = '${ndk_bin}/ld.lld'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF_CROSS
}

prepare_termux_sysroot() {
  local out_dir="${1:?termux sysroot out dir required}"
  local packages_index="${out_dir}/Packages"
  local deb_dir="${out_dir}/debs"
  local root_dir="${out_dir}/root"

  mkdir -p "${deb_dir}" "${root_dir}"
  curl -fsSL -o "${packages_index}" "${MESA_TERMUX_PACKAGES_INDEX_URL}"

  python3 - <<'PY' "${packages_index}" "${deb_dir}" "${root_dir}" "${MESA_TERMUX_REPO_BASE_URL}" "${MESA_TERMUX_SEED_PACKAGES}"
import pathlib
import re
import subprocess
import sys
import urllib.request

packages_path = pathlib.Path(sys.argv[1])
deb_dir = pathlib.Path(sys.argv[2])
root_dir = pathlib.Path(sys.argv[3])
repo_base = sys.argv[4].rstrip("/")
seed = [token.strip() for token in sys.argv[5].split() if token.strip()]

records = {}
current = {}
for line in packages_path.read_text(encoding="utf-8", errors="replace").splitlines() + [""]:
    if not line.strip():
        if "Package" in current:
            records[current["Package"]] = current
        current = {}
        continue
    if ": " in line:
        key, value = line.split(": ", 1)
        current[key] = value

queue = list(seed)
seen = set()
order = []

while queue:
    name = queue.pop(0)
    if name in seen:
        continue
    seen.add(name)
    record = records.get(name)
    if not record:
        continue
    order.append(name)
    depends = record.get("Depends", "")
    for part in depends.split(","):
        dep = part.strip()
        if not dep:
            continue
        dep = dep.split("|")[0].strip()
        dep = re.sub(r"\s*\(.*\)", "", dep).strip()
        if dep and dep not in seen:
            queue.append(dep)

for name in order:
    record = records.get(name, {})
    filename = record.get("Filename", "").strip()
    if not filename:
        continue
    url = f"{repo_base}/{filename}"
    local_path = deb_dir / pathlib.Path(filename).name
    if not local_path.exists():
        urllib.request.urlretrieve(url, local_path)
    subprocess.check_call(["dpkg-deb", "-x", str(local_path), str(root_dir)])
PY

  printf '%s' "${root_dir}/data/data/com.termux/files/usr"
}
