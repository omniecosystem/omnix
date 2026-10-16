# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
param([Parameter(Mandatory = $true)][string]$SourcePath)

$ErrorActionPreference = 'Stop'
$sdkSource = (Resolve-Path -LiteralPath $SourcePath).ProviderPath
$trustStore = Join-Path $sdkSource 'credentials\development\paa-root-certs'
if (-not (Test-Path -LiteralPath (Join-Path $trustStore 'Chip-Test-PAA-FFF1-Cert.der'))) {
    throw 'The official SDK checkout must contain the public development PAA certificate store.'
}
$image = 'connectedhomeip/chip-cert-bins@sha256:4d4c5931db65ecc777b626518556b0d1e70499233213f5b1852d46cdb0ba4d5e'
$dockerOS = & docker info --format '{{.OSType}}'
if ($LASTEXITCODE -ne 0 -or $dockerOS -ne 'linux') {
    throw 'Start Docker Desktop with Linux containers. This is isolated test tooling only.'
}
& docker image inspect $image *> $null
if ($LASTEXITCODE -ne 0) {
    throw "The pinned SDK test image is not cached. No automatic download was performed. Obtain $image explicitly (approximately 1.2 GB compressed)."
}

$runId = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$network = "omnix-cpp-$runId"
$light = "omnix-cpp-light-$runId"
$commandContainer = "omnix-cpp-command-$runId"
$storage = "omnix-cpp-fabric-$runId"
$networkCreated = $false
$lightCreated = $false
$storageCreated = $false
$diagnostics = Join-Path $PSScriptRoot "results\matter-cpp-$runId"
New-Item -ItemType Directory -Path $diagnostics | Out-Null
$sequence = 0
$controllerStartup = @'
set -eu
ulimit -c 0
mkdir -p /run/dbus
dbus-daemon --system --fork
avahi-daemon --daemonize --no-drop-root --no-chroot
exec timeout --kill-after=5s 60 /root/apps/chip-tool "$@"
'@

function Invoke-Controller {
    param([string[]]$Arguments)
    $script:sequence++
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell turns native stderr into error records; retain
        # diagnostics and judge failure by the process exit code instead.
        $ErrorActionPreference = 'Continue'
        $output = & docker run --rm --platform linux/arm64 --name $commandContainer `
            --network $network --mount "type=volume,source=$storage,target=/state" `
            --mount "type=bind,source=$trustStore,target=/trust,readonly" `
            --entrypoint sh $image -c $controllerStartup controller @Arguments `
            --storage-directory /state --paa-trust-store-path /trust 2>&1
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    $text = $output -join "`n"
    $text | Set-Content -LiteralPath (Join-Path $diagnostics "$($script:sequence)-controller.log")
    if ($exitCode -ne 0) { throw "Official controller failed (exit $exitCode). Inspect private test logs in $diagnostics" }
    return $text
}

function Assert-OnOff {
    param([bool]$Expected)
    $output = Invoke-Controller -Arguments @('onoff', 'read', 'on-off', '1', '1')
    $value = if ($Expected) { '(?:true|1)' } else { '(?:false|0)' }
    if ($output -notmatch "(?im)\bOnOff:\s*$value\b") {
        throw "Attribute response did not confirm OnOff=$Expected. Inspect private logs in $diagnostics"
    }
}

try {
    $subnet = "fd75:$($runId.Substring(0, 4)):$($runId.Substring(4, 4))::/64"
    & docker network create --ipv6 --subnet $subnet $network | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated IPv6 network.' }
    $networkCreated = $true
    & docker volume create $storage | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create disposable controller storage.' }
    $storageCreated = $true
    & docker run -d --platform linux/arm64 --name $light --network $network `
        --entrypoint /root/apps/chip-lighting-app $image `
        --passcode 20202021 --discriminator 3840 --interface-id eth0 --KVS /tmp/omnix-cpp-light-kvs | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not start the official software light.' }
    $lightCreated = $true
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $logs = (& docker logs $light 2>&1) -join "`n"
        if ($logs -match 'CHIP minimal mDNS started|SetupQRCode') { $ready = $true; break }
        if ((& docker inspect --format '{{.State.Running}}' $light) -ne 'true') { throw 'Software light exited.' }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Software light did not become ready within 30 seconds.' }
    Invoke-Controller -Arguments @('pairing', 'onnetwork-long', '1', '20202021', '3840') | Out-Null
    Write-Output 'PASS: official C++ controller commissioned the software light without bypassing attestation.'
    Invoke-Controller -Arguments @('onoff', 'on', '1', '1') | Out-Null
    Assert-OnOff -Expected $true
    Write-Output 'PASS: On command and real attribute read.'
    Invoke-Controller -Arguments @('onoff', 'off', '1', '1') | Out-Null
    Assert-OnOff -Expected $false
    Write-Output 'PASS: Off command and real attribute read.'
    # Every command uses a new controller process and the same private volume.
    # Restart the device too, retaining its container-owned KVS, then use CASE
    # without repeating commissioning. No host sockets or app data are used.
    & docker restart $light | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restart the isolated software light.' }
    Invoke-Controller -Arguments @('onoff', 'on', '1', '1') | Out-Null
    Assert-OnOff -Expected $true
    Write-Output 'PASS: controller/device restart reused fabric credentials without recommissioning.'
} finally {
    if ($lightCreated) {
        (& docker logs $light 2>&1) | Set-Content -LiteralPath (Join-Path $diagnostics 'light.log')
    }
    # Exact uniquely named test resources only. Never prune Docker or delete
    # consumer model, database, identity or fabric directories.
    & docker rm -f $commandContainer *> $null
    if ($lightCreated) { & docker rm -f $light *> $null }
    if ($storageCreated) { & docker volume rm $storage *> $null }
    if ($networkCreated) { & docker network rm $network *> $null }
    Write-Output "Private test diagnostics: $diagnostics"
}
