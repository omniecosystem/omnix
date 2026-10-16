# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
param([Parameter(Mandatory = $true)][string]$SourcePath)
$ErrorActionPreference = 'Stop'
$sdkSource = (Resolve-Path -LiteralPath $SourcePath).ProviderPath
$revision = & git -C $sdkSource rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $revision -ne '0fa0eb338e20dad90b269149581c693a970a03cc') {
    throw 'The reference SDK must match the pinned qualification revision.'
}
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$qualification = Join-Path $PSScriptRoot 'matter_cpp_sdk'
$wrapper = Join-Path $repository 'modules\omnix_nexus\rust\backend\native\matter_cpp'
$volume = 'omnix-matter-sdk-qualification'
$container = 'omnix-matter-sdk-' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
Write-Output 'Development-only SDK bootstrap: downloads SDK dependencies; cache is retained in a dedicated Docker volume.'
& docker build -t omnix-matter-sdk-dev:local $qualification
if ($LASTEXITCODE -ne 0) { throw 'Could not build SDK development image.' }
& docker volume create $volume
if ($LASTEXITCODE -ne 0) { throw 'Could not create SDK qualification cache.' }
& docker run --rm --name $container `
    --mount "type=volume,source=$volume,target=/work" `
    --mount "type=bind,source=$sdkSource,target=/reference,readonly" `
    --mount "type=bind,source=$qualification,target=/qualification,readonly" `
    --mount "type=bind,source=$wrapper,target=/wrapper,readonly" `
    omnix-matter-sdk-dev:local bash /qualification/bootstrap.sh
if ($LASTEXITCODE -ne 0) { throw 'Official SDK qualification failed; cache retained for diagnosis/retry.' }
Write-Output 'PASS: Linux SDK build, ABI and real controller lifecycle. This is not device or Android qualification.'
