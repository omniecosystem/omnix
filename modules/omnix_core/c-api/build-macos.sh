#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "Run this build on Apple silicon macOS." >&2
  exit 1
fi

here="$(cd -- "$(dirname -- "$0")" && pwd)"
output="${1:-$here/target/macos}"
mkdir -p -- "$output"
output="$(cd -- "$output" && pwd)"

version=0.18.0
runtime_sha256=5f6ee68d95eeccb084c6e66d5ee47255e3020fa0fb29696dd0301ae26d6cfb4f
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
archive="$scratch/CLiteRTLM_mac.xcframework.zip"
curl --fail --location --silent --show-error --retry 3 \
  "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v$version/CLiteRTLM_mac.xcframework.zip" \
  --output "$archive"
printf '%s  %s\n' "$runtime_sha256" "$archive" | shasum -a 256 --check
ditto -x -k "$archive" "$scratch"

runtime="$scratch/CLiteRTLM_mac.xcframework/macos-arm64_x86_64/libCLiteRTLM_mac.dylib"
nm -arch arm64 -gU "$runtime" | awk '{ print $NF }' > "$scratch/exports"
sed -n 's/^[[:space:]]*pub \(litert_lm_[a-z0-9_]*\):.*/_\1/p' \
  "$here/../rust/backend/src/litertlm_bindings.rs" > "$scratch/required"
test -s "$scratch/required"
if grep -Fvx -f "$scratch/exports" "$scratch/required"; then
  echo "The pinned runtime is missing required LiteRT-LM exports." >&2
  exit 1
fi

export CARGO_TARGET_DIR="$here/target"
cargo rustc --locked --release --manifest-path "$here/Cargo.toml" --lib -- \
  -C link-arg=-Wl,-install_name,@rpath/libomnix_core_c.dylib
cp "$CARGO_TARGET_DIR/release/libomnix_core_c.dylib" "$output/"
cp "$runtime" "$output/"
codesign --force --sign - "$output/libomnix_core_c.dylib"
swiftc "$here/examples/macos.swift" -I "$here/include" -L "$output" -lomnix_core_c \
  -Xlinker -rpath -Xlinker '@executable_path' -o "$output/omnix-core-smoke"
"$output/omnix-core-smoke" --check-linkage
echo "macOS build staged at $output"
