# Matter SDK and Flutter integration reference

[flutter_matter](https://github.com/Tan-yi-xiong/flutter_matter) is a reference
for Android and Apple platform integration. It is not an Omnix dependency.

## Platform boundaries

Its Android integration combines a controller distribution with BLE, DNS-SD,
configuration storage and platform services. Its Apple integration uses
framework-backed wrappers. These platform adapters are not a portable C API,
and their existence does not establish Windows or Linux support.

Omnix's C++ shim exposes an explicit C boundary over an official SDK controller.
The controller must be created by a host built against the matching SDK
revision and configuration. Java or Objective-C object handles cannot be cast
to C++ controller pointers.

## Ownership

Platform services, fabric state and controller ownership must outlive commands.
Method submission and asynchronous command completion are separate outcomes.
Outstanding callbacks must not access released host or frontend state.

JNI and Apple framework integrations require explicit ownership and callback
routing in addition to native libraries. Rust alone cannot supply BLE or
operating-system permission UI.

## Credentials and distribution

Fixture credentials and attestation overrides are not production defaults.
Production consumers need appropriate trust configuration, secure fabric/key
storage and failure handling. Do not log pairing or fabric secrets.

Native artifacts require provenance, pinned SDK revisions, architecture
compatibility and license review. A companion binary distribution does not
remove those responsibilities.

## Validation

Contract tests with doubles establish ABI and callback behavior only.
Official SDK build/link tests, controller startup, commissioning, command
completion, attribute readback and persistent reconnect are separate checks.

The repository includes tooling for
[repeatable SDK builds](../tool/matter_cpp_sdk/README.md).
Its fixtures and qualification hosts are not a general production controller
distribution. Consult [Nexus](../modules/omnix_nexus/README.md) for current
backend boundaries.
