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
