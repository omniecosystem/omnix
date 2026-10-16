#!/usr/bin/env bash
# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
# Maintainer build, not an application launch/install script.
set -eo pipefail
sdk_revision=0fa0eb338e20dad90b269149581c693a970a03cc
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
: "${OMNIX_MATTER_SOURCE:?Set OMNIX_MATTER_SOURCE to an isolated official SDK checkout}"
: "${ANDROID_HOME:?Set ANDROID_HOME to a SDK containing platforms/android-34/android.jar}"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to Linux NDK 28.2.13676358}"
: "${JAVA_HOME:?Set JAVA_HOME to JDK 17}"
: "${OMNIX_MATTER_OUTPUT:?Set OMNIX_MATTER_OUTPUT to the artifact destination}"
export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | grep -q 'version "17\.'
cd "$OMNIX_MATTER_SOURCE"
[[ $(git rev-parse HEAD) == "$sdk_revision" ]] || { echo 'SDK revision mismatch' >&2; exit 1; }
grep -q 'Pkg.Revision = 28.2.13676358' "$ANDROID_NDK_HOME/source.properties"
test -f "$ANDROID_HOME/platforms/android-34/android.jar"
command -v kotlinc
kotlinc -version 2>&1 | grep -q '2.1.10'
python3 scripts/checkout_submodules.py --shallow --platform android --jobs "${OMNIX_BUILD_JOBS:-4}"
# Upstream-supported native-only environment, with ZAP retained. Android uses
# the NDK compiler, not the unrelated bare-metal ARM GCC package.
# Do not install SDK Python agents/tests to produce a JNI controller library.
cp "$script_dir/environment.json" scripts/setup/omnix_controller_environment.json
export PW_CONFIG_FILE=scripts/setup/omnix_controller_environment.json
export PW_ACTIVATE_SKIP_CHECKS=1
source scripts/bootstrap.sh -p none
python3 third_party/android_deps/set_up_android_deps.py
bash third_party/java_deps/set_up_java_deps.sh
out=out/omnix-android-arm64-controller
gn gen --check --fail-on-unused-args "$out" --args="target_os=\"android\" target_cpu=\"arm64\" android_ndk_root=\"$ANDROID_NDK_HOME\" android_sdk_root=\"$ANDROID_HOME\" is_debug=false chip_build_tests=false chip_enable_python_modules=false chip_build_controller_dynamic_server=true"
# Explicit library targets: no sample APK, installation or test-app code.
ninja -C "$out" -j "${OMNIX_BUILD_JOBS:-4}" \
    src/controller/java:java src/controller/java:chipcluster \
    src/controller/java:chipclusterID src/controller/java:jsontlv \
    src/controller/java:onboarding_payload src/controller/java:tlv \
    src/platform/android:java
python3 "$script_dir/package.py" --sdk "$PWD" --build "$PWD/$out" \
    --destination "$OMNIX_MATTER_OUTPUT"
