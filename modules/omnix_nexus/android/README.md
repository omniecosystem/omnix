# Android Matter SDK artifact resolver

This is an opt-in build helper, not an Android plugin or a cross-platform
controller implementation. Applying `matter_sdk.gradle` alone does not download
anything or enable Matter. The root example explicitly invokes its resolver.

`matter-sdk.json` pins the official-source qualification AAR, source revision,
checksum and Java runtime dependencies. Resolution order is:

1. `OMNIX_MATTER_ANDROID_AAR` (explicit path; must match the pin).
2. The caller's local source-build AAR (reused directly, without copying).
3. The verified Gradle-user-home cache at `omnix/matter/android-arm64`.
4. `OMNIX_MATTER_ANDROID_URL`, or the manifest's release URL.

The release URL is intentionally null until a qualified artifact is published.
Without a local artifact, verified cache or URL, the helper fails with setup
instructions. It does not silently fetch a third-party reference build.

Download admission requires direct HTTPS without credentials or redirects.
Downloads are size/time bounded and protected by a cache lock; a temporary file
is checksum-verified before atomic promotion. Existing invalid artifacts fail
instead of being overwritten. Remote fetching still requires qualification.

The root example's Kotlin Gradle script demonstrates applying the helper and
calling `omnixResolveMatterSdk` with `manifest` and `localAar`, then using
`omnixMatterRuntimeDependencies` for Java dependencies. Module consumers still
provide their own Android host integration; this helper does not install it.

Run local/offline admission checks from `example/android`:

```powershell
.\gradlew.bat -p ../../tool/matter_android_sdk/resolver_test verifyResolver --console=plain
```

Release gates remain: clean rebuild/provenance verification, complete third-party
notices and dependency inventory, a published immutable binary and remote-cache
qualification. Only Android arm64 software-light control is qualified today.
