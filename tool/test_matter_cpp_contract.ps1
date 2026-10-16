# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$harness = Join-Path $PSScriptRoot 'matter_cpp_contract'
$previousContractLibrary = $env:OMNIX_MATTER_CONTRACT_LIBRARY
try {
    Push-Location -LiteralPath $harness
    try {
        & dart pub get
        if ($LASTEXITCODE -ne 0) { throw 'Contract harness dependency resolution failed.' }
        & dart run bin/build.dart
        if ($LASTEXITCODE -ne 0) { throw 'Contract C++ build failed.' }
        $library = Get-ChildItem -LiteralPath (Join-Path $harness '.dart_tool') -Recurse -Filter omnix_matter_contract.dll |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if (-not $library) { throw 'Windows native contract DLL was not produced.' }
        $env:OMNIX_MATTER_CONTRACT_LIBRARY = $library.FullName
    } finally { Pop-Location }
    Push-Location -LiteralPath $repository
    try {
        & cargo +1.93.1 test --manifest-path modules/omnix_nexus/rust/Cargo.toml -p omnix-nexus `
            --no-default-features --features matter-cpp --test matter_cpp_contract -- --ignored --nocapture
        if ($LASTEXITCODE -ne 0) { throw 'Native C++ contract test failed.' }
    } finally { Pop-Location }
    Write-Output 'PASS: native C++ boundary contract. This is not official SDK or Android qualification.'
} finally { $env:OMNIX_MATTER_CONTRACT_LIBRARY = $previousContractLibrary }
