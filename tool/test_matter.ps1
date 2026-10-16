param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath
)

$ErrorActionPreference = 'Stop'
$matterSource = (Resolve-Path -LiteralPath $SourcePath).ProviderPath
$matterTest = Join-Path $matterSource 'rs-matter\tests\commissioning.rs'
if (-not (Test-Path -LiteralPath $matterTest -PathType Leaf)) {
    throw 'SourcePath must point to the project-chip/rs-matter repository with its commissioning test.'
}

$matterDockerOS = & docker info --format '{{.OSType}}'
if ($LASTEXITCODE -ne 0 -or $matterDockerOS -ne 'linux') {
    throw 'Start Docker Desktop with Linux containers before running this test.'
}

$matterRevision = & git -C $matterSource rev-parse HEAD
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the upstream checkout revision.'
}
$matterChanges = & git -C $matterSource status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw 'Could not inspect the upstream checkout.'
}
if ($matterChanges) {
    throw 'Use a clean rs-matter checkout so the test result and cached dependency lock match the reported revision.'
}

Write-Output "Testing rs-matter revision $matterRevision"
Write-Output 'The virtual light and controller run inside a Linux container. Network discovery is stubbed by the upstream test.'

# Pin the toolchain image; cache generated dependencies and build artifacts only
# in Docker volumes. The upstream checkout is mounted read-only.
$matterImage = 'rust@sha256:452176c0cefca88c0b3184ce85a4eb03e3d4fa05d2afb5366abcba853221019e'
$matterCommand = @'
set -eu
mkdir /work
tar -C /source --exclude=./target --exclude=./.git -cf - . | tar -C /work -xf -
cd /work
rustc --version
lock_dir="/build/locks/$MATTER_SOURCE_REVISION"
if [ -f "$lock_dir/Cargo.lock" ]; then
    cp "$lock_dir/Cargo.lock" Cargo.lock
else
    cargo generate-lockfile
    mkdir -p "$lock_dir"
    cp Cargo.lock "$lock_dir/Cargo.lock"
fi
timeout 600s cargo test --locked -p rs-matter --test commissioning -- --test-threads=1 --nocapture
'@

$matterDockerArgs = @(
    'run', '--rm',
    '--mount', "type=bind,source=$matterSource,target=/source,readonly",
    '--mount', 'type=volume,source=omnix-matter-cargo,target=/usr/local/cargo',
    '--mount', 'type=volume,source=omnix-matter-target,target=/build',
    '-e', 'CARGO_TARGET_DIR=/build',
    '-e', 'CARGO_BUILD_JOBS=2',
    '-e', 'CARGO_PROFILE_TEST_DEBUG=0',
    '-e', 'RUST_LOG=warn,commissioning=info',
    '-e', "MATTER_SOURCE_REVISION=$matterRevision",
    $matterImage, 'sh', '-c', $matterCommand
)

& docker @matterDockerArgs
$matterExitCode = $LASTEXITCODE
if ($matterExitCode -ne 0) {
    throw "Matter test failed (exit code $matterExitCode). Exit code 124 means the ten-minute build/test limit was reached."
}
