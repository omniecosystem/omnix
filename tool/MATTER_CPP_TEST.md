# Official C++ controller qualification

This is test tooling, not the embedded Nexus controller adapter. It exercises
the official `chip-tool` and software light from the same pinned SDK image.
No Rust/C++ shim or Flutter app participates yet.

## Run on Windows

Start Docker Desktop with Linux containers. The runner requires an already
cached `connectedhomeip/chip-cert-bins` image at the digest below. It will not
download images automatically. The first explicit download is approximately
1.2 GB compressed; the ARM64 image runs under emulation on x64 Windows.

```powershell
# Run from the Omnix repository root.
# Only if this image is not already cached:
docker pull --platform linux/arm64 connectedhomeip/chip-cert-bins@sha256:4d4c5931db65ecc777b626518556b0d1e70499233213f5b1852d46cdb0ba4d5e
.\tool\test_matter_cpp.ps1 -SourcePath C:/path/to/connectedhomeip
```

`SourcePath` is an official SDK checkout. Only its public development PAA root
certificate directory is mounted, read-only. Controller/device executables come
from the image, not this checkout's current source revision. The pinned image
was previously recorded at SDK revision `99a81bd`.

The test commissions with development passcode `20202021` and discriminator
`3840`, without setting the attestation-bypass option. Development roots are
for this isolated fixture only, not a production trust-store policy.

Expected checks:

1. Official C++ controller commissions the official software light.
2. On and Off commands each have a confirming attribute read.
3. Each command runs in a fresh controller process, restoring one private fabric.
4. A device restart preserves its KVS, and a new controller sends On and reads
   the attribute without commissioning again.

Linux D-Bus and Avahi run inside the disposable controller containers. There
are no published host ports, host-network mode, physical devices or consumer
app installations. Each controller invocation is bounded by a 60-second timeout
and a five-second forced-stop grace period; core dumps are disabled.

The runner removes only its uniquely named containers, network and fabric
volume. Logs remain under ignored `tool/results/matter-cpp-*`. They contain
development identity/session material: keep them private and do not commit them.
No model, application database or existing node identity is modified.

## What this does not prove

All four checks passed on 5 October 2026 on the Windows development host.
The runner cleaned up its disposable containers/network/fabric volume and
retained private diagnostics. This was a fresh fabric, not consumer credentials.

Passing establishes upstream C++ controller functionality in an isolated Linux
environment on this Windows host. It does not establish native Windows support,
Bluetooth commissioning, Android/Apple packaging, production attestation policy,
or an embedded Rust controller. Do not ship `chip-tool`, Docker or these test
credentials as the module implementation.

The next integration gate is a small C-compatible wrapper over the SDK controller
and a Rust-owned safe API. SDK/platform initialization must provide private
storage, credential lifecycle, event-loop scheduling and permission/BLE hooks.
No C++ objects, borrowed callback data or exceptions may escape into Rust;
shutdown must drain or cancel operations before releasing their owners.
