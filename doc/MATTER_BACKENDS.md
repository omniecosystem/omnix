# Nexus Matter backends

Matter is an opt-in Nexus capability, independent of A2A.
Backend selection is explicit; it must not silently change with the target OS.

| Selection | Implementation | Boundary |
| --- | --- | --- |
| Experimental Matter | rs-matter prototype | Experimental controller behavior, not production certification |
| `matter-cpp` | Official SDK through an Omnix C shim | Host must supply matching controller/platform ownership |
| `windows_qualification` / `matter-process` | Bundled Matter.js process | Requires a separately verified runtime bundle |
| `android_host` / `matter-android` | Official SDK Java/JNI owner | Requires Android platform services and the pinned AAR |

Android does not use Matter.js. The desktop software-light fixture used by
Android tests is a separate process on the test network.

## Shared command boundary

The Rust host contract separates command acknowledgment from attribute readback.
Windows child-process ownership and Android JVM/platform ownership remain
distinct behind that contract.

Java controller handles cannot be cast to C++ controller pointers.
A C++ shim must use a controller created with compatible SDK configuration.

## Distribution

Windows qualification does not automatically bundle Node into every consumer.
Android artifact resolution supports verified local/cache inputs and explicitly
configured download sources. A general public SDK release URL is not supplied.

Source pins, checksums and provenance are necessary but do not replace license
notices, target compatibility or production trust configuration.

## Development environments

Linux containers and Ubuntu on WSL are suitable SDK build environments.
They are development tools, not runtime requirements for consumer devices.
A Linux-built shared library does not provide native Windows support.

Container compile/link tests do not qualify multicast, BLE, commissioning or
real-device networking. Validate those separately on the intended host.

## Qualification

Test controller startup, commissioning, independent readback, saved-fabric
reconnect, outstanding callbacks and shutdown separately.
Public fixture credentials and software-light results are not production
attestation or commercial-device certification.

See [the host contract](MATTER_HOST_CONTRACT.md),
[example setup](MATTER_EXAMPLE.md), and
[official-source Android builds](../tool/matter_android_sdk/README.md).
