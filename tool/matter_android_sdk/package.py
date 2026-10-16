# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
"""Package official GN controller outputs, not reference/prebuilt companion files."""
import argparse
import hashlib
import io
import json
import os
import struct
from pathlib import Path
import subprocess
import zipfile

REVISION = "0fa0eb338e20dad90b269149581c693a970a03cc"
JARS = {
    "CHIPController.jar": "src/controller/java",
    "CHIPInteractionModel.jar": "src/controller/java",
    "CHIPClusters.jar": "src/controller/java",
    "CHIPClusterID.jar": "src/controller/java",
    "libMatterJson.jar": "src/controller/java",
    "libMatterTlv.jar": "src/controller/java",
    "OnboardingPayload.jar": "src/controller/java",
    "AndroidPlatform.jar": "src/platform/android",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def archive(entries):
    """Stable ZIP metadata; does not claim the compiler outputs are bit-identical."""
    result = io.BytesIO()
    with zipfile.ZipFile(result, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, data)
    return result.getvalue()


def merge_jars(paths):
    entries = {}
    for path in paths:
        with zipfile.ZipFile(path) as jar:
            for name in jar.namelist():
                if name.startswith("/") or ".." in name.split("/") or "\\" in name:
                    raise ValueError(f"Unsafe JAR entry: {name}")
                if name.endswith("/") or name.upper() == "META-INF/MANIFEST.MF":
                    continue
                if name.upper().endswith((".SF", ".RSA", ".DSA")):
                    raise ValueError(f"Unexpected signed input: {path}:{name}")
                data = jar.read(name)
                if name in entries and entries[name] != data:
                    raise ValueError(f"Conflicting SDK JAR entry: {name}")
                entries[name] = data
    for required in ("chip/devicecontroller/ChipDeviceController.class",
                     "chip/platform/AndroidChipPlatform.class"):
        if required not in entries:
            raise ValueError(f"Missing public controller class: {required}")
    return archive(entries)


def validate_elf(data):
    if data[:6] != b"\x7fELF\x02\x01" or int.from_bytes(data[18:20], "little") != 183:
        raise ValueError("Not ARM64 ELF")
    table = struct.unpack_from("<Q", data, 32)[0]
    entry_size, count = struct.unpack_from("<HH", data, 54)
    if entry_size < 56 or count == 0:
        raise ValueError("Missing ELF program headers")
    loads = 0
    for index in range(count):
        kind, _, offset, address, _, _, _, alignment = struct.unpack_from(
            "<IIQQQQQQ", data, table + index * entry_size)
        if kind == 1:
            loads += 1
            if alignment < 16384 or offset % 16384 != address % 16384:
                raise ValueError("ELF LOAD segment lacks 16-KiB alignment")
    if not loads:
        raise ValueError("Missing ELF LOAD segments")


def package(sdk, build, destination):
    revision = subprocess.check_output(["git", "-C", str(sdk), "rev-parse", "HEAD"], text=True).strip()
    if revision != REVISION:
        raise ValueError("Unexpected official SDK revision")
    # Prevent packaging modified tracked SDK sources as an upstream build.
    subprocess.run(["git", "-C", str(sdk), "diff", "--quiet", "HEAD", "--", ".",
                    ":(exclude)third_party/android_deps/BUILD.gn"], check=True)
    inputs = [build / "lib" / directory / name for name, directory in JARS.items()]
    binaries = [build / "lib/jni/arm64-v8a" / name
                for name in ("libCHIPController.so", "libc++_shared.so")]
    for path in inputs + binaries:
        if not path.is_file():
            raise ValueError(f"Missing official build output: {path}")
    for binary in binaries:
        validate_elf(binary.read_bytes())
    entries = {
        "AndroidManifest.xml": b'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="xyz.omniecosystem.omnix.matter.sdk"><uses-sdk android:minSdkVersion="26"/></manifest>',
        "classes.jar": merge_jars(inputs),
        "proguard.txt": b'-keep class chip.** { *; }\n-keep class matter.** { *; }\n',
        "META-INF/LICENSE.connectedhomeip": (sdk / "LICENSE").read_bytes(),
    }
    for binary in binaries:
        entries[f"jni/arm64-v8a/{binary.name}"] = binary.read_bytes()
    submodules = subprocess.check_output(["git", "-C", str(sdk), "submodule", "status", "--recursive"], text=True)
    if any(line.startswith(("+", "U")) for line in submodules.splitlines()):
        raise ValueError("Initialized SDK submodule differs from the pinned gitlink")
    ndk = Path(os.environ["ANDROID_NDK_HOME"])
    tool_versions = {}
    for name, command in {"java": ["java", "-version"], "kotlin": ["kotlinc", "-version"],
                          "gn": ["gn", "--version"], "ninja": ["ninja", "--version"],
                          "python": ["python3", "--version"]}.items():
        tool_versions[name] = subprocess.check_output(command, stderr=subprocess.STDOUT, text=True).strip()
    provenance = {
        "schema": 1, "upstream": "https://github.com/project-chip/connectedhomeip",
        "revision": revision, "abi": "arm64-v8a", "qualified": False,
        "gn_args": (build / "args.gn").read_text(),
        "android_deps_generated_diff": subprocess.check_output(
            ["git", "-C", str(sdk), "diff", "HEAD", "--", "third_party/android_deps/BUILD.gn"], text=True),
        "submodules": submodules,
        "tools": tool_versions,
        "cipd_instances": json.loads((sdk / ".environment/cipd/packages.json").read_text()),
        "python_dependencies": subprocess.check_output(
            ["python3", "-m", "pip", "freeze"], text=True),
        "ndk": (ndk / "source.properties").read_text(),
        "build_scripts": {path.name: sha(path.read_bytes()) for path in
                          (Path(__file__).resolve(), Path(__file__).with_name("build.sh"),
                           Path(__file__).with_name("environment.json"))},
        "inputs": {str(path.relative_to(build)): sha(path.read_bytes()) for path in inputs + binaries},
        "dependency_jars": {str(path.relative_to(sdk)): sha(path.read_bytes())
                            for directory in ("third_party/java_deps/artifacts",
                                              "third_party/android_deps/artifacts")
                            for path in (sdk / directory).rglob("*.jar")},
    }
    entries["META-INF/omnix-matter-provenance.json"] = json.dumps(provenance, sort_keys=True, indent=2).encode()
    data = archive(entries)
    destination.mkdir(parents=True, exist_ok=True)
    artifact = destination / "omnix-matter-android-arm64.aar"
    pending = artifact.with_suffix(".aar.part")
    pending.write_bytes(data)
    pending.replace(artifact)
    provenance["aar_sha256"] = sha(data)
    (destination / "provenance.json").write_text(json.dumps(provenance, indent=2, sort_keys=True))
    print(f"Source-built artifact (not yet qualified): {artifact}\nSHA256: {sha(data)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", required=True, type=Path)
    parser.add_argument("--build", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args()
    package(args.sdk.resolve(), args.build.resolve(), args.destination.resolve())
