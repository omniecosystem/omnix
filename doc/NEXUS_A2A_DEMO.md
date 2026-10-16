# Nexus A2A demo

The old Dart command-line/reference-runtime host has been retired. This Rust
demonstration uses static public answers; no Dart subprocess is started.
For the current Flutter controls, see [the native example](../example/README.md).

The A2A adapter lives in the `omnix-nexus` workspace crate at
`modules/omnix_nexus/rust/backend/src/a2a`. The root native crate re-exports it through
the existing `omnix::nexus` path when the `nexus` feature is enabled.
The sample exposes synthetic or public Knowledge only. It is not production
pairing, private-data access, or remote-action authority.

From the `omnix/rust` directory, verify the module:

```powershell
cargo test --all-targets --features nexus
cargo clippy --all-targets --features nexus -- -D warnings
```

For a local two-terminal test, run this in the server terminal:

```powershell
cargo run --features nexus --example two_agents -- serve
```

Copy the printed demo token, then run this in the client terminal:

```powershell
$env:OMNIXUS_DEMO_TOKEN = "<token printed by server>"
cargo run --features nexus --example two_agents -- ask "What is Omnixus?"
cargo run --features nexus --example two_agents -- ask "private note"
```

The second request should be refused. The `OMNIXUS_DEMO_*` names are retained
for compatibility with the earlier test commands; they do not select an
Omnixus library. The default listener binds to `127.0.0.1:46137`.

## Two laptops with a private HTTPS route

Both laptops need the Omnix repository and Rust. A route such as Tailscale
Serve can forward an HTTPS tailnet URL to the server's local port. Tailscale
is a test transport, not a Nexus or A2A protocol requirement. Keep the Rust
listener on loopback, do not expose port 46137 directly, and use only public
demo data.

On laptop A, configure the route separately, then start the server:

```powershell
$env:OMNIXUS_DEMO_PUBLIC_URL = "https://<laptop-a-tailnet-name>.ts.net"
cargo run --features nexus --example two_agents -- serve
```

On laptop B, use laptop A's URL and the token printed by A:

```powershell
$env:OMNIXUS_DEMO_URL = "https://<laptop-a-tailnet-name>.ts.net"
$env:OMNIXUS_DEMO_TOKEN = "<token printed by laptop A>"
cargo run --features nexus --example two_agents -- ask "What is Omnixus?"
```

The copied-token path has been tried on two laptops. It is not secure node
pairing. Stop a running server with Ctrl+C before rebuilding or switching
its mode.

## Experimental paired-key mode

Each laptop chooses its own private node directory outside the repository.
Run `identity init` once per node; it refuses to replace an existing key.
Exchange only the printed **public** keys. On each receiving laptop, grant
the other laptop's key, then start its server using its own HTTPS URL:

```powershell
$env:OMNIXUS_NODE_DIR = Join-Path $env:LOCALAPPDATA "Omnix\nexus-demo-node"
cargo run --features nexus --example two_agents -- identity init
cargo run --features nexus --example two_agents -- identity allow "<other-laptop-public-key>"
$env:OMNIXUS_DEMO_PUBLIC_URL = "https://<this-laptop-tailnet-name>.ts.net"
cargo run --features nexus --example two_agents -- serve
```

On the caller, keep its own `OMNIXUS_NODE_DIR`, set the remote URL, and ask:

```powershell
$env:OMNIXUS_DEMO_URL = "https://<other-laptop-tailnet-name>.ts.net"
cargo run --features nexus --example two_agents -- ask "What is Omnixus?"
```

No copied demo token is needed in paired-key mode. This path still needs
physical two-device validation. Private keys are local files, grants load at
server startup, and replay state is in memory; do not use it for private
Knowledge or actions. Revoke a grant with `identity deny` and restart the
receiving server.

For actual native Knowledge and host callbacks, use the root Flutter example or
the [standalone Nexus example](../modules/omnix_nexus/example/README.md).
The obsolete `OMNIXUS_DEMO_OMNIX_EXAMPLE` subprocess route is no longer supported.
