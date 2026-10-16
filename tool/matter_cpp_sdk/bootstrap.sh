#!/usr/bin/env bash
# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
set -eo pipefail
sdk_revision=0fa0eb338e20dad90b269149581c693a970a03cc
if [[ ! -d /work/sdk/.git ]]; then
    git -c safe.directory=/reference clone --no-hardlinks /reference /work/sdk
fi
cd /work/sdk
if [[ $(git rev-parse HEAD) != "$sdk_revision" ]]; then
    echo 'Isolated SDK revision differs from the pinned revision; refusing to overwrite.' >&2
    exit 1
fi
python3 scripts/checkout_submodules.py --shallow --platform linux
# Native controller qualification does not need the SDK's Python agent/test
# packages or the Pigweed meta-package's cloud utilities. Use the supported
# bootstrap override, retaining upstream tool manifests and build constraints.
cp /qualification/controller_environment.json scripts/setup/omnix_controller_environment.json
export PW_CONFIG_FILE=scripts/setup/omnix_controller_environment.json
# Pigweed's multitool doctor imports optional Python plugins omitted by the
# native-only configuration. Use its supported activation switch, then verify
# the native prerequisites explicitly; bootstrap/build failures remain fatal.
export PW_ACTIVATE_SKIP_CHECKS=1
source scripts/bootstrap.sh -p none
gn --version
ninja --version
clang --version
python3 -c 'import jinja2; import lark; import yaml'
mkdir -p /work/project
cp -a /qualification/project/. /work/project/
mkdir -p /work/project/third_party
ln -sfn /work/sdk /work/project/third_party/connectedhomeip
mkdir -p /work/project/shim
cp -a /wrapper/. /work/project/shim/
# SDK overrides resolve chip_root through our own override. Keep the authored
# chip/build overrides; copy only other upstream dependency overrides.
for override in /work/sdk/examples/build_overrides/*; do
    name=$(basename "$override")
    if [[ "$name" != chip.gni && "$name" != build.gni ]]; then
        cp -L "$override" /work/project/build_overrides/
    fi
done
cd /work/project
gn gen out
ninja -C out -j 4 omnix_matter
file out/obj/lib/omnix_matter.so
nm -D out/obj/lib/omnix_matter.so | grep omnix_matter_get_api_v1
python3 /qualification/verify_abi.py "$PWD/out/obj/lib/omnix_matter.so"
ninja -C out -j 4 controller_lifecycle
timeout 90s out/obj/bin/controller_lifecycle
