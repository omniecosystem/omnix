#!/usr/bin/env bash
# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Produce a local candidate, not a published or device-qualified runtime.
if [[ $# -ne 4 && $# -ne 5 ]]; then
  echo 'Usage: package_litertlm_android.sh CHECKOUT NDK BINARY OUTPUT [cpu|gpu]' >&2
  exit 64
fi
checkout=$(realpath "$1")
ndk=$(realpath "$2")
binary=$(realpath "$3")
mkdir -p "$4"
output=$(realpath "$4")
profile=${5:-cpu}
if [[ "$profile" != cpu && "$profile" != gpu ]]; then
  echo 'Select cpu or gpu explicitly; NPU needs vendor-specific qualification.' >&2
  exit 64
fi
revision=b2f686e2ed4718fb84ec398a61dd59ca0f0aff27
if [[ $(git -C "$checkout" rev-parse HEAD) != "$revision" ]]; then
  echo 'The source revision does not match the Android runtime pin.' >&2
  exit 1
fi
readelf="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
repository=$(realpath "$(dirname "$0")/..")
package=$(mktemp -d "$output/$profile-candidate.XXXXXX")
mkdir -p "$package/lib/arm64-v8a" "$package/evidence"
cp "$binary" "$package/lib/arm64-v8a/liblitert-lm.so"
cp "$checkout/LICENSE" "$package/LICENSE"
printf '%s\n' "$revision" > "$package/UPSTREAM_REVISION"

queue=(liblitert-lm.so)
if [[ "$profile" == gpu ]]; then
  # These are dynamically loaded, so DT_NEEDED on the engine is insufficient.
  # Include both upstream GPU implementations and their sampling companions.
  for companion in libLiteRtGpuAccelerator.so libLiteRtOpenClAccelerator.so \
    libLiteRtTopKOpenClSampler.so libLiteRtTopKWebGpuSampler.so \
    libLiteRtWebGpuAccelerator.so libwebgpu_dawn.so; do
    source="$checkout/prebuilt/android_arm64/$companion"
    expected=$(git -C "$checkout" show "HEAD:prebuilt/android_arm64/$companion" | sed -n 's/^oid sha256://p')
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || ! -f "$source" ]]; then
      echo "No pinned GPU companion: $companion" >&2
      exit 1
    fi
    actual=$(sha256sum "$source" | cut -d ' ' -f 1)
    if [[ "$actual" != "$expected" ]]; then
      echo "GPU companion checksum mismatch: $companion" >&2
      exit 1
    fi
    cp "$source" "$package/lib/arm64-v8a/$companion"
    queue+=("$companion")
  done
fi
for ((index=0; index<${#queue[@]}; index++)); do
  name=${queue[index]}
  file="$package/lib/arm64-v8a/$name"
  "$readelf" -h "$file" > "$package/evidence/$name.header.txt"
  "$readelf" -n "$file" > "$package/evidence/$name.notes.txt"
  if ! grep -q 'AArch64' "$package/evidence/$name.header.txt"; then
    echo "Expected an Android ARM64 ELF library: $name" >&2
    exit 1
  fi
  "$readelf" -l --wide "$file" > "$package/evidence/$name.segments.txt"
  # Check every load segment, not merely the first one.
  mapfile -t alignments < <(awk '$1 == "LOAD" {print $NF}' "$package/evidence/$name.segments.txt")
  if [[ ${#alignments[@]} -eq 0 ]]; then
    echo "No ELF load segments: $name" >&2
    exit 1
  fi
  for alignment in "${alignments[@]}"; do
    if (( alignment < 16384 )); then
      echo "ELF is not 16 KiB page aligned: $name ($alignment)" >&2
      exit 1
    fi
  done
  "$readelf" -d "$file" > "$package/evidence/$name.dependencies.txt"
  mapfile -t dependencies < <(sed -n 's/.*(NEEDED).*\[\([^]]*\)\].*/\1/p' "$package/evidence/$name.dependencies.txt")
  for dependency in "${dependencies[@]}"; do
    case "$dependency" in
      # Public Android platform libraries; EGL/GLES also appear in the full
      # upstream C target even when this package is used for CPU execution.
      libc.so|libm.so|libdl.so|liblog.so|libandroid.so|libEGL.so|libGLESv2.so|libGLESv3.so) continue ;;
    esac
    if [[ ! "$dependency" =~ ^lib[A-Za-z0-9_.+-]+\.so$ ]]; then
      echo "Unsafe dependency name: $dependency" >&2
      exit 1
    fi
    if [[ -f "$package/lib/arm64-v8a/$dependency" ]]; then continue; fi
    if [[ "$dependency" == libc++_shared.so ]]; then
      source="$ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
      cp "$ndk/NOTICE" "$package/NDK_NOTICE"
    else
      source="$checkout/prebuilt/android_arm64/$dependency"
      # Companion files must match the Git LFS object at the pinned revision.
      if [[ ! -f "$source" ]]; then
        echo "No pinned source for dependency: $dependency" >&2
        exit 1
      fi
      expected=$(git -C "$checkout" show "HEAD:prebuilt/android_arm64/$dependency" | sed -n 's/^oid sha256://p')
      if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || ! -f "$source" ]]; then
        echo "No pinned source for dependency: $dependency" >&2
        exit 1
      fi
      actual=$(sha256sum "$source" | cut -d ' ' -f 1)
      if [[ "$actual" != "$expected" ]]; then
        echo "Companion checksum mismatch: $dependency" >&2
        exit 1
      fi
    fi
    cp "$source" "$package/lib/arm64-v8a/$dependency"
    queue+=("$dependency")
  done
done

"$readelf" --dyn-syms --wide "$binary" > "$package/evidence/symbols.txt"
mapfile -t symbols < <(sed -n 's/^    pub \(litert_lm_[a-z0-9_]*\):.*/\1/p' \
  "$repository/modules/omnix_core/rust/backend/src/litertlm_bindings.rs" \
  "$repository/modules/omnix_core/rust/backend/src/litertlm_embedding_bindings.rs" | sort -u)
if [[ ${#symbols[@]} -eq 0 ]]; then
  echo 'No required C symbols were found in the Rust binding tables.' >&2
  exit 1
fi
for symbol in "${symbols[@]}"; do
  if ! grep -Eq "GLOBAL +DEFAULT +[0-9]+ +${symbol}(@[^ ]+)?$" "$package/evidence/symbols.txt"; then
    echo "Missing exported C symbol: $symbol" >&2
    exit 1
  fi
done
if [[ "$profile" == cpu ]]; then
  printf '%s\n' 'CPU candidate only. Device inference and complete redistribution notices remain release gates.' > "$package/QUALIFICATION.txt"
else
  printf '%s\n' 'CPU/GPU candidate only. Device inference and complete redistribution notices remain release gates.' > "$package/QUALIFICATION.txt"
fi
(
  cd "$package"
  # Relative entries keep verification portable after extraction.
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum --check SHA256SUMS >/dev/null
)
archive="$package.tar.gz"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$archive" -C "$package" .
(cd "$output" && sha256sum "$(basename "$archive")") > "$archive.sha256"
echo "Packaged $profile candidate: $archive"
echo 'This archive is not yet enabled in the Flutter build hook.'
