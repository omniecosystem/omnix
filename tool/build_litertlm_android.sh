#!/usr/bin/env bash
# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Uses the upstream Bazel build, not a replacement SDK implementation.
# Usage: bash tool/build_litertlm_android.sh CHECKOUT NDK BAZEL OUTPUT
if [[ $# -ne 4 ]]; then
  echo 'Usage: build_litertlm_android.sh CHECKOUT NDK BAZEL OUTPUT' >&2
  exit 64
fi
checkout=$(realpath "$1")
ndk=$(realpath "$2")
bazel=$(realpath "$3")
mkdir -p "$4"
output=$(realpath "$4")
revision=b2f686e2ed4718fb84ec398a61dd59ca0f0aff27
if [[ $(git -C "$checkout" rev-parse HEAD) != "$revision" ]]; then
  echo 'Expected the pinned LiteRT-LM v0.18.0 revision.' >&2
  exit 1
fi
if ! git -C "$checkout" diff --quiet || ! git -C "$checkout" diff --cached --quiet; then
  echo 'Refusing to qualify modified upstream sources.' >&2
  exit 1
fi
readelf="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
if [[ ! -x "$readelf" || ! -x "$bazel" ]]; then
  echo 'A Linux-host Android NDK and executable Bazel are required.' >&2
  exit 1
fi
for companion in "$checkout"/prebuilt/android_arm64/*.so; do
  if ! "$readelf" -h "$companion" >/dev/null 2>&1; then
    echo 'Android prebuilts are missing: fetch the pinned Git LFS objects first.' >&2
    exit 1
  fi
done
export ANDROID_NDK_HOME="$ndk"
cd "$checkout"
"$bazel" build --config=android_arm64 -c opt --jobs=6 \
  --local_resources=memory=4096 --linkopt=-Wl,-z,max-page-size=16384 \
  --repo_env=HERMETIC_PYTHON_VERSION=3.11 //c:litert-lm
binary="$checkout/bazel-bin/c/liblitert-lm.so"
test -f "$binary"
"$readelf" -h "$binary" | grep -q 'AArch64'
"$readelf" --dyn-syms --wide "$binary" > "$output/symbols.txt"
for symbol in \
  litert_lm_embedding_engine_settings_create litert_lm_embedding_engine_settings_delete \
  litert_lm_embedding_engine_settings_set_max_input_length \
  litert_lm_embedding_engine_settings_set_activation_data_type \
  litert_lm_embedding_engine_create litert_lm_embedding_engine_delete \
  litert_lm_embedding_engine_compute_embedding \
  litert_lm_embedding_options_create litert_lm_embedding_options_delete \
  litert_lm_embedding_options_set_normalize \
  litert_lm_embedding_options_set_insert_special_tokens \
  litert_lm_embedding_options_set_output_size \
  litert_lm_embedding_options_set_input_overflow_strategy \
  litert_lm_embedding_response_get_values \
  litert_lm_embedding_response_get_size \
  litert_lm_embedding_response_delete litert_lm_input_data_create \
  litert_lm_input_data_delete; do
  if ! grep -Eq "GLOBAL +DEFAULT +[0-9]+ +${symbol}(@[^ ]+)?$" "$output/symbols.txt"; then
    echo "Missing exported C symbol: $symbol" >&2
    exit 1
  fi
done
"$readelf" -d "$binary" > "$output/dependencies.txt"
"$readelf" -l --wide "$binary" > "$output/segments.txt"
# Do not overwrite an existing qualified artifact. Each run owns a new folder.
package=$(mktemp -d "$output/artifact.XXXXXX")
cp "$binary" "$package/liblitert-lm.so"
cp "$checkout/LICENSE" "$package/LICENSE"
printf '%s\n' "$revision" > "$package/UPSTREAM_REVISION"
(cd "$package" && sha256sum liblitert-lm.so > SHA256SUMS)
echo "Built candidate: $package"
bash "$(dirname "$(realpath "$0")")/package_litertlm_android.sh" "$checkout" "$ndk" "$binary" "$output"
