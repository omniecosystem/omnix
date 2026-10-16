param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [switch]$CompileOnly
)

$ErrorActionPreference = 'Stop'
$matterSource = (Resolve-Path -LiteralPath $SourcePath).ProviderPath
$matterRevision = & git -C $matterSource rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $matterRevision -ne '74fff78b1bf9297e783da2319e7f6a66321ad627') {
    throw 'Use the documented rs-matter revision; this spike is adapted to that API.'
}
$matterChanges = & git -C $matterSource status --porcelain
if ($LASTEXITCODE -ne 0 -or $matterChanges) { throw 'Use a clean rs-matter checkout.' }
$matterDockerOS = & docker info --format '{{.OSType}}'
if ($LASTEXITCODE -ne 0 -or $matterDockerOS -ne 'linux') {
    throw 'Start Docker Desktop with Linux containers. Docker is test tooling, not an app dependency.'
}

$matterRustImage = 'rust@sha256:452176c0cefca88c0b3184ce85a4eb03e3d4fa05d2afb5366abcba853221019e'
# Official connectedhomeip image at SDK revision 99a81bd. ARM64 is emulated on x64 Docker Desktop.
$matterDeviceImage = 'connectedhomeip/chip-cert-bins@sha256:4d4c5931db65ecc777b626518556b0d1e70499233213f5b1852d46cdb0ba4d5e'
$matterRunId = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$matterNetwork = "omnix-matter-$matterRunId"
$matterDevice = "omnix-light-$matterRunId"
$matterController = "omnix-controller-$matterRunId"
$matterNetworkCreated = $false
$matterDeviceCreated = $false
$matterControllerCreated = $false

$matterCommand = @'
set -eu
mkdir /work
tar -C /source --exclude=./target --exclude=./.git -cf - . | tar -C /work -xf -
cp /spike/matter_controller.rs /work/rs-matter/tests/omnix_matter_controller.rs
cp /spike/matter_mdns.rs /work/rs-matter/tests/matter_mdns.rs
cd /work
cp /spike/matter.Cargo.lock Cargo.lock
if [ "$MATTER_COMPILE_ONLY" = 1 ]; then
    timeout 600s cargo test --locked -p rs-matter --test omnix_matter_controller --no-run
else
    timeout 600s cargo test --locked -p rs-matter --test omnix_matter_controller -- --nocapture
fi
'@

try {
    $matterNetworkArgs = @()
    $matterPeer = '[::1]:5540'
    if (-not $CompileOnly) {
        Write-Output 'Testing a disposable C++ software light; no host network ports are published.'
        Write-Output 'First run downloads the official ARM64 image (approximately 1.2 GB compressed).'
        & docker pull --platform linux/arm64 $matterDeviceImage
        if ($LASTEXITCODE -ne 0) { throw 'Could not obtain the pinned official C++ device image.' }
        # Unique ULA /64; isolated from both the host LAN and other test invocations.
        $matterSubnet = "fd73:$($matterRunId.Substring(0, 4)):$($matterRunId.Substring(4, 4))::/64"
        & docker network create --ipv6 --subnet $matterSubnet $matterNetwork
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated IPv6 test network.' }
        $matterNetworkCreated = $true
        & docker run -d --platform linux/arm64 --name $matterDevice --network $matterNetwork `
            --entrypoint /root/apps/chip-lighting-app $matterDeviceImage `
            --passcode 20202021 --discriminator 3840 --interface-id eth0 --KVS /tmp/omnix-test-kvs
        if ($LASTEXITCODE -ne 0) { throw 'Could not start the C++ software light.' }
        $matterDeviceCreated = $true
        $matterState = @(& docker inspect $matterDevice | ConvertFrom-Json)[0]
        $matterDeviceAddress = $matterState.NetworkSettings.Networks.$matterNetwork.GlobalIPv6Address
        if (-not $matterDeviceAddress) { throw 'The disposable device has no IPv6 address.' }
        $matterPeer = "[$matterDeviceAddress]:5540"
        $matterNetworkArgs = @('--network', $matterNetwork)
        # Wait for actual Matter listener readiness, not merely a running container.
        $matterReady = $false
        for ($matterAttempt = 0; $matterAttempt -lt 30; $matterAttempt++) {
            $matterLogs = & docker logs $matterDevice 2>&1
            if ($matterLogs -match 'CHIP minimal mDNS started|SetupQRCode') { $matterReady = $true; break }
            if ((& docker inspect --format '{{.State.Running}}' $matterDevice) -ne 'true') {
                throw 'The C++ software light exited during startup.'
            }
            Start-Sleep -Seconds 1
        }
        if (-not $matterReady) { throw 'The C++ software light did not become ready within 30 seconds.' }
    }

    $matterDockerArgs = @(
        'run', '--name', $matterController,
        '--mount', "type=bind,source=$matterSource,target=/source,readonly",
        '--mount', "type=bind,source=$PSScriptRoot,target=/spike,readonly",
        '--mount', 'type=volume,source=omnix-matter-cargo,target=/usr/local/cargo',
        '--mount', 'type=volume,source=omnix-matter-target,target=/build',
        '-e', 'CARGO_TARGET_DIR=/build', '-e', 'CARGO_BUILD_JOBS=2',
        '-e', 'CARGO_PROFILE_TEST_DEBUG=0', '-e', 'RUST_LOG=info',
        '-e', "MATTER_SOURCE_REVISION=$matterRevision", '-e', "MATTER_TEST_PEER=$matterPeer",
        '-e', "MATTER_COMPILE_ONLY=$([int][bool]$CompileOnly)"
    ) + $matterNetworkArgs + @($matterRustImage, 'sh', '-c', $matterCommand)
    $matterControllerCreated = $true
    & docker @matterDockerArgs
    if ($LASTEXITCODE -ne 0) { throw "Matter interoperability test failed (exit code $LASTEXITCODE)." }
} finally {
    if ($matterDeviceCreated) { & docker logs --tail 60 $matterDevice }
    # Only delete resources created by this invocation. Fixtures and caches are retained.
    if ($matterControllerCreated) { & docker rm -f $matterController | Out-Null }
    if ($matterDeviceCreated) { & docker rm -f $matterDevice | Out-Null }
    if ($matterNetworkCreated) { & docker network rm $matterNetwork | Out-Null }
}
