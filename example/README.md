# omnix_example

Demonstrates the intended public developer flow:

1. Create and initialize a LiteRT-LM-backed `OmnixRuntime`.
2. Inspect or install a model through `runtime.models`.
3. Open a conversation and stream thinking and response events.
4. Stop generation and close owned resources.

The model is installed only after the user presses **Install model**. The
example uses Gemma 4 E2B, which is approximately 2.6 GB.

The device integration test exercises the application runtime and conversation
ownership contract with a deterministic backend, so automated verification
does not require network access or a model download.

## Run

The example builds Omnix's Rust Native Asset. Confirm that `rustup` is
available in the same terminal before invoking Flutter:

```shell
rustup --version
flutter run
```

If Rust was installed while the IDE was open, restart the IDE or terminal so
its `PATH` includes the Cargo bin directory.

## Local Nexus round trip (Windows)

This exercises the actual Rust A2A listener, signed peer request, and Dart
Knowledge callback on one computer, without Tailscale or a model download.
From `omnix/example` in PowerShell:

```powershell
cargo build --release --manifest-path ..\rust\Cargo.toml
$env:OMNIX_NATIVE_DLL = (Resolve-Path ..\rust\target\release\omnix.dll).Path
dart run bin/nexus_loopback.dart
```

The demonstration creates two temporary identities and a public and private
chunk. The public answer must cross A2A; the private chunk must not. It removes
its temporary identity directories when finished. The native DLL is selected
explicitly because a plain `dart run` does not use Flutter's packaged DLL
lookup path.

## Two-device Omnix Knowledge round trip (Windows)

This uses `OmnixNexusNode` from Dart on **both** laptops. Each process indexes
its own JSON fixture into an Omnix Knowledge coordinator, then serves only
public matches over the bundled Rust A2A listener. It does not run a model,
use embeddings, expose private documents, or start the Flutter UI.

First push/pull the same Omnix revision to both laptops. Stop the previous
Rust `two_agents serve` processes: this Dart example uses their port `46137`.
Keep the existing Tailscale Serve HTTPS route to `127.0.0.1:46137` on each
laptop. In PowerShell on **each** laptop, from `C:\dev\omni\omnix\example`:

```powershell
flutter pub get
cargo build --release --manifest-path ..\rust\Cargo.toml
$env:OMNIX_NATIVE_DLL = (Resolve-Path ..\rust\target\release\omnix.dll).Path
$env:OMNIXUS_NODE_DIR = Join-Path $env:LOCALAPPDATA "Omnix\nexus-demo-node"
dart run bin/nexus_device.dart show
```

If `show` reports no identity, run `dart run bin/nexus_device.dart init` once.
You can reuse the identities and peer grants from the Rust two-laptop test.
If this is a new pairing, exchange **public** keys only, then on each laptop:

```powershell
dart run bin/nexus_device.dart allow --peer-key "<other-laptop-public-key>"
```

On laptop A, start the server in its own terminal, using the **exact** URL
printed by `tailscale serve status` on A:

```powershell
dart run bin/nexus_device.dart serve --origin "https://<laptop-A-tailnet-name>" --fixture public_knowledge.json
```

On laptop B, also start a server in its own terminal, using B's URL and a
different public/private fixture:

```powershell
dart run bin/nexus_device.dart serve --origin "https://<laptop-B-tailnet-name>" --fixture public_knowledge_laptop_b.json
```

In a separate client terminal on A, repeat the `OMNIX_NATIVE_DLL` and
`OMNIXUS_NODE_DIR` assignments above, then ask B:

```powershell
dart run bin/nexus_device.dart ask --origin "https://<laptop-B-tailnet-name>" --question "blue notebook"
dart run bin/nexus_device.dart ask --origin "https://<laptop-B-tailnet-name>" --question "private note"
```

The first answer must mention laptop B's blue notebook. The private-note
request must fail without returning its contents. On B, repeat the DLL and
node-directory assignments, then ask A:

```powershell
dart run bin/nexus_device.dart ask --origin "https://<laptop-A-tailnet-name>" --question "Omnixus"
dart run bin/nexus_device.dart ask --origin "https://<laptop-A-tailnet-name>" --question "private note"
```

The public answer should come from A's fixture; the private query must fail.
Stop either server with Ctrl+C, restart it with the same fixture and origin,
and repeat a query to check reload behavior. The fixture is indexed in memory
at every start; this example is not a durable Knowledge store. The paired-key
identity and grants persist in the node directory. Do not put sensitive data
in these fixtures or use this experimental pairing for private data/actions.
