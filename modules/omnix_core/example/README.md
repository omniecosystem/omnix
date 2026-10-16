# Standalone Core example

## GGUF / llama.cpp

This isolated example selects `runtimes: [litertlm, llamacpp]` in Native Assets.
The native source build needs CMake and C++ compiler tools. Rust C-API bindings
are checked in; only maintainers regenerating them need libclang.
No model download is built into this example.

```powershell
flutter pub get
$env:OMNIX_CORE_TEST_MODEL = Join-Path $env:LOCALAPPDATA 'Omnix/test-models/smollm2-360m-instruct-q8_0.gguf'
Remove-Item Env:OMNIX_CORE_TEST_LIBRARY -ErrorAction SilentlyContinue
flutter run -d windows
```

Use your trusted local GGUF path if the documented test artifact is not present.
Click **Run local demo** to stream a reply, stop a turn and check follow-up recall.
The packaged integration-test command below exercises the same path. To test
LiteRT-LM instead, supply only the model variable as below; routing
checks the model header, not the filename. Changing a runtime setting may trigger
a full native rebuild. Models are external artifacts, not embedded in the app.

A minimal cyan/dark Flutter host importing only `omnix_core`. It loads an
explicitly trusted local model, sends two text turns and closes
the conversation. Windows runtimes are built/bundled automatically; models are not.

From this directory, with Flutter, Rust 1.93.1 and Windows compiler tools:

```powershell
flutter pub get
Remove-Item Env:OMNIX_CORE_TEST_LIBRARY -ErrorAction SilentlyContinue
$env:OMNIX_CORE_TEST_MODEL = "C:\models\gemma-4-E2B-it.litertlm"
flutter run -d windows
```

Click **Run local demo**. LiteRT-LM uses its checksum-verified build-time bundle.
An optional trusted DLL override is available for advanced testing;
loading an arbitrary DLL is unsafe. Core currently supports Windows CPU/text
only, not Android or multimodal inference. The demo streams text, stops a turn
and verifies follow-up memory. See the [module README](../README.md).

Packaged Windows regression (with the same trusted artifact variables):

```powershell
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/native_demo_test.dart -d windows
```

`flutter test` checks progress, retries and disposal with an injected callback;
it does not load a model. The isolated Android application ID is
`xyz.omniecosystem.omnix_core_example`. Do not install over a consumer app or
use its data as a test harness.
