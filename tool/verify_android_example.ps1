# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0

param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][string]$ReadElf,
    [Parameter(Mandatory = $true)][string]$Aapt
)
$ErrorActionPreference = 'Stop'
$apkPath = (Resolve-Path -LiteralPath $Apk).Path
$readElfPath = (Resolve-Path -LiteralPath $ReadElf).Path
$aaptPath = (Resolve-Path -LiteralPath $Aapt).Path
$badging = (& $aaptPath dump badging $apkPath) -join "`n"
if ($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='xyz.omniecosystem.omnix'" -or
    $badging -notmatch "sdkVersion:'31'") {
    throw 'Expected the dedicated Omnix example with minimum API 31.'
}
$manifest = (& $aaptPath dump xmltree $apkPath AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0 -or $manifest -notmatch 'extractNativeLibs.*0xffffffff') {
    throw 'The example must extract native libraries for sibling runtime discovery.'
}
$auditDirectory = Join-Path ([IO.Path]::GetTempPath()) ('omnix-apk-audit-' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $auditDirectory | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($apkPath)
try {
    $entries = @($zip.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/[^/]+\.so$' })
    if ($entries | Where-Object { $_.FullName -notmatch '^lib/arm64-v8a/' }) {
        throw 'This candidate APK must contain only the qualified ARM64 ABI.'
    }
    $required = @('liblitert-lm.so', 'libGemmaModelConstraintProvider.so',
        'libomnix_core_bridge.so', 'libomnix_knowledge_bridge.so',
        'libomnix_storage_bridge.so', 'libomnix_nexus_bridge.so')
    $names = @($entries | ForEach-Object { $_.Name })
    foreach ($name in $required) {
        if (@($names | Where-Object { $_ -eq $name }).Count -ne 1) {
            throw "Missing or duplicate APK library: $name"
        }
    }
    $systemLibraries = @('libc.so', 'libm.so', 'libdl.so', 'liblog.so',
        'libandroid.so', 'libEGL.so', 'libGLESv2.so', 'libGLESv3.so',
        'libz.so', 'libOpenSLES.so', 'libvulkan.so', 'libnativewindow.so',
        'libjnigraphics.so')
    foreach ($entry in $entries) {
        # Entry names have already been restricted to a single basename.
        $destination = Join-Path $auditDirectory $entry.Name
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination)
        $header = (& $readElfPath --file-header $destination) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $header -notmatch 'AArch64') {
            throw "Not an ARM64 ELF: $($entry.Name)"
        }
        $segments = & $readElfPath --program-headers --wide $destination
        if ($LASTEXITCODE -ne 0) { throw 'ELF segment inspection failed.' }
        $loads = @($segments | Where-Object { $_ -match '^\s*LOAD\s' })
        if ($loads.Count -eq 0) { throw 'Missing ELF load segments.' }
        foreach ($load in $loads) {
            $alignment = ($load.Trim() -split '\s+')[-1]
            if ([Convert]::ToUInt64($alignment, 16) -lt 16384) {
                throw "ELF alignment below 16 KiB: $($entry.Name)"
            }
        }
        $dynamic = (& $readElfPath --dynamic --wide $destination) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'ELF dependency inspection failed.' }
        foreach ($match in [regex]::Matches($dynamic, 'NEEDED.*\[([^\]]+)\]')) {
            $dependency = $match.Groups[1].Value
            if ($dependency -notin $names -and $dependency -notin $systemLibraries) {
                throw "Unbundled dependency in $($entry.Name): $dependency"
            }
        }
        Write-Output "$($entry.Name): ARM64, >=16 KiB alignment, dependency closure checked"
    }
    $symbols = (& $readElfPath --dyn-syms --wide (Join-Path $auditDirectory 'liblitert-lm.so')) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'C symbol inspection failed.' }
    $definedSymbols = (($symbols -split "`n") | Where-Object { $_ -notmatch '\bUND\b' }) -join "`n"
    $bindingRoot = Join-Path $PSScriptRoot '../modules/omnix_core/rust/backend/src'
    $count = 0
    foreach ($file in @('litertlm_bindings.rs', 'litertlm_embedding_bindings.rs')) {
        $binding = Get-Content -Raw -LiteralPath (Join-Path $bindingRoot $file)
        foreach ($match in [regex]::Matches($binding, 'pub (litert_lm_[a-z0-9_]+):')) {
            $symbol = $match.Groups[1].Value
            if ($definedSymbols -notmatch "\b$symbol\b") { throw "Missing defined C export: $symbol" }
            $count++
        }
    }
    if ($count -ne 46) { throw "Unexpected required C symbol count: $count" }
    Write-Output "PASS: dedicated API 31 example, extracted libraries, all 46 required C exports."
    Write-Output "APK SHA-256: $((Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash)"
    Write-Output "Inspection files retained in $auditDirectory. Device execution remains untested."
} finally {
    $zip.Dispose()
}
