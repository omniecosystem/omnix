$ErrorActionPreference = 'Stop'
$matterNdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64'
$matterLinker = Join-Path $matterNdk 'bin/aarch64-linux-android24-clang.cmd'
if (-not (Test-Path -LiteralPath $matterLinker)) { throw 'Pinned Android NDK linker is missing.' }
$matterOldLinker = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
$matterOldFlags = $env:RUSTFLAGS
Push-Location $PSScriptRoot
try {
    $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $matterLinker
    $env:RUSTFLAGS = '-C link-arg=-Wl,-z,max-page-size=16384'
    & cargo build --release --target aarch64-linux-android
    if ($LASTEXITCODE -ne 0) { throw 'Rust Android host build failed.' }
    Write-Output 'Set OMNIX_MATTER_ANDROID_RUST_HOST to the absolute target/aarch64-linux-android/release/libomnix_matter_android_host.so path.'
} finally {
    $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $matterOldLinker
    $env:RUSTFLAGS = $matterOldFlags
    Pop-Location
}
