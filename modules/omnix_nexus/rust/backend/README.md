# omnix-nexus Rust backend

Use identity and protocol adapters without depending on Flutter, an inference
model or the root Omnix crate. Your host supplies handlers, private storage,
networking and access policy.

## Select components

No protocol is enabled by default. Select only the features your application
needs:

| Cargo feature | Purpose |
| --- | --- |
| `a2a` | Paired A2A text endpoints, client requests and public-knowledge compatibility helpers |
| `matter-host` | Typed contract for a host-owned Matter controller |
| `matter-process` | Windows Node/Matter.js disposable-fixture adapter; includes `matter-host` |
| `matter-cpp` | Loader for the Omnix C shim over the official C++ SDK |
| `experimental-matter` | Simulator-only rs-matter controller |
| `matter` | Compatibility alias for `experimental-matter` |

A2A and Matter selections are independent. Native A2A and rs-matter adapters do
not provide browser implementations. Selecting a feature does not acquire an
Android SDK, Node runtime or official C++ controller distribution.

Root Omnix can compose Nexus with other modules, but native consumers can use
this crate directly. The separate bridge in the parent `rust` directory is not
a dependency of this backend.

## Identity and A2A

`SigningIdentity` creates or restores a local signing key.
`PeerProofVerifier` verifies short-lived audience-bound proofs and can consume
their nonces to reject replay. Identity verification is not permission to read
knowledge or execute an action.

Use `PairedNodeAuthorizer::with_access` to supply endpoint access policy.
Public-knowledge registry helpers are provided for examples; their grants are
loaded when the router is created. Reload the router after a grant changes.

Text routers invoke host-supplied handlers after verification. The host owns the
listener, TLS termination, lifecycle and resource-level authorization.
`send_text` accepts HTTPS origins, with IPv4 loopback HTTP allowed for tests;
it checks the discovered Agent Card's origin and disables redirects.

Keep signing keys and fabric state in private host-owned storage. The demo bearer
adapter is for loopback tests, not public deployment. Browser listeners, NAT
traversal and durable background hosting are not supplied by these adapters.

## Matter boundaries

`matter-host` controls an already commissioned On/Off endpoint through a host
implementation. It distinguishes command acknowledgement from attribute readback
and blocks reuse after ambiguous failures. The host retains SDK callbacks and
owns permissions, credentials, deadlines and shutdown.

The [C++ shim guide](native/matter_cpp/README.md) describes the separately built
official-SDK integration. Its Rust loader does not initialize or commission an
SDK controller.

`matter-process` is a Windows test adapter for an explicitly bundled Node
runtime and script. It launches a disposable software light using a fresh private
directory; it is not a general consumer-device commissioner. The
`matter_host_check` example exercises this fixture when supplied a verified
bundle. Fixture storage is scoped to the controller's lifetime rather than
retained intentionally. Cleanup errors are reported on normal completion;
unwinding attempts cleanup, while forced process termination can leave files.

`experimental-matter` explicitly allows test attestation for the upstream
disposable fixture, requires simulator consent and accepts only its test setup
passcode. It uses UDP/mDNS and persists simulator pairings in the supplied
directory. State contains unencrypted operational keys; do not use this path for
production devices. The built-in mDNS adapter selects one interface
heuristically; it does not expose host-directed interface selection.

## Verify locally

From this backend directory:

```sh
cargo test --locked --no-default-features --features a2a --lib
cargo test --locked --no-default-features --features matter-host --test matter_host_contract
cargo test --locked --no-default-features --features experimental-matter --lib
```

On Windows, the Rust process/shim contract tests can also run without devices:

```sh
cargo test --locked --no-default-features --features matter-process,matter-cpp --lib
```

These tests use in-process handlers, temporary identities and state, parser inputs
or function-table doubles. Passing them does not establish real-device
interoperability, platform packaging or official SDK compatibility. Opt-in native
integration tests require separate trusted artifacts.

The backend is a source-only developer preview with `publish = false`.
See the [module guide](../../README.md) for the separate Dart API and host setup.

## Adapted source

`src/matter/experimental/mdns.rs` is adapted from
[rs-matter's mDNS example at the pinned revision](https://github.com/project-chip/rs-matter/blob/74fff78b1bf9297e783da2319e7f6a66321ad627/examples/src/common/mdns.rs).
It retains the upstream Project CHIP copyright and Apache-2.0 license header.
The Omnix adaptation selects the built-in backend and accepts a host-provided
hostname.
