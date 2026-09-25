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
