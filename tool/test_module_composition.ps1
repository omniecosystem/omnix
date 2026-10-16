$ErrorActionPreference = 'Stop'
$manifest = Join-Path $PSScriptRoot '../rust/Cargo.toml'

# Inspect normal dependencies, not this repository's test tooling.
$cases = @(
    @{ Features = ''; Modules = @() },
    @{ Features = 'core-litertlm'; Modules = @('omnix-core') },
    @{ Features = 'nexus'; Modules = @('omnix-nexus') },
    @{ Features = 'storage'; Modules = @('omnix-storage') },
    @{ Features = 'core-litertlm,nexus,storage'; Modules = @('omnix-core', 'omnix-nexus', 'omnix-storage') },
    @{ Features = 'flutter-bridge'; Modules = @() }
)
foreach ($case in $cases) {
    $selection = @('--manifest-path', $manifest, '-p', 'omnix', '--no-default-features')
    if ($case.Features) { $selection += @('--features', $case.Features) }
    $tree = & cargo tree @selection --edges normal --prefix none --format '{p}'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect Cargo dependencies' }
    $names = @($tree | ForEach-Object { ($_ -split ' ')[0] })
    if (-not $case.Features -and @($names | Where-Object { $_ -ne 'omnix' }).Count) {
        throw 'The foundation unexpectedly pulls in an implementation dependency'
    }
    foreach ($module in @('omnix-core', 'omnix-nexus', 'omnix-storage')) {
        $expected = $case.Modules -contains $module
        if (($names -contains $module) -ne $expected) {
            throw "Unexpected dependency $module for features '$($case.Features)'"
        }
    }
    $expectsBridge = $case.Features -eq 'flutter-bridge'
    if (($names -contains 'flutter_rust_bridge') -ne $expectsBridge) {
        throw "Unexpected Flutter bridge dependency for features '$($case.Features)'"
    }
    & cargo check @selection --lib
    if ($LASTEXITCODE -ne 0) { throw "Build failed for features '$($case.Features)'" }
    Write-Host "Verified selection: '$($case.Features)'"
}
