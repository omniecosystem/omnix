# Standalone Storage example

A minimal cyan/dark Flutter host importing only `omnix_storage`. Its demo
writes a version-1 conversation snapshot into its own temporary SQLite database,
closes it, reopens it and verifies recovery. It then removes only its own
temporary directory. No consumer database or account is used.

The example selects both SQLite and Qdrant; independent consumers may select
either alone. From this directory, with Flutter, Rust 1.98.1 and Windows compiler tools:

```powershell
flutter pub get
flutter run -d windows
```

Click **Run local demo**. Native Assets builds and bundles the module bridge;
there is no manual DLL environment variable. See the [module README](../README.md).

Packaged Windows regression:

```powershell
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/native_demo_test.dart -d windows
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/vector_native_test.dart -d windows
```

The vector test runs the same example UI with a Qdrant callback. It inserts
synthetic vectors, closes/reopens the shard, checks public filtering before
top-k and source metadata, then deletes and reopens again to verify durability.
It requires no embedding model, network account, or manual DLL path. It removes
only its own temporary shard. The ordinary demo button still runs SQLite.

The packaged tests exercise Windows persistence and recovery; they do not
establish mobile or clean-machine compatibility. Use the pinned Rust toolchain
and install the compilation targets required by the host platform before
running native tests.

`flutter test` checks progress, retries and disposal with an injected callback,
not the native database. Browsers are unsupported; Android runtime qualification
for this extracted package remains pending. Its independent Android application
ID is `xyz.omniecosystem.omnix_storage_example`. Physical-device deployment needs
explicit approval and must not replace a consumer app.
