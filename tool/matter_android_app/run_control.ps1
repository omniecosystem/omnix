param(
    [Parameter(Mandatory=$true)][string]$DeviceId,
    [Parameter(Mandatory=$true)][string]$LightAddress,
    [switch]$Commission,
    [switch]$DiscoveryOnly,
    [switch]$LifecycleOnly,
    [switch]$RustHost,
    [switch]$FrbHost
)
$ErrorActionPreference = 'Stop'
$matterAdb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
if (-not (Test-Path -LiteralPath $matterAdb)) { throw 'Android SDK adb was not found.' }
if (-not $env:OMNIX_MATTER_ANDROID_AAR) { throw 'Set OMNIX_MATTER_ANDROID_AAR first.' }
$matterPackage = 'xyz.omniecosystem.qualification.omnix_matter_android_app'
$matterForward = $null
Push-Location $PSScriptRoot
try {
    $matterCommission = ([bool]$Commission).ToString().ToLowerInvariant()
    if (($RustHost -or $FrbHost) -and ($Commission -or $LifecycleOnly -or $DiscoveryOnly)) { throw 'Rust host test uses an already commissioned fixture; do not combine modes.' }
    if ($RustHost -and $FrbHost) { throw 'Select one Rust qualification mode.' }
    if ($RustHost -and -not $env:OMNIX_MATTER_ANDROID_RUST_HOST) { throw 'Set OMNIX_MATTER_ANDROID_RUST_HOST first.' }
    if (($Commission -and ($DiscoveryOnly -or $LifecycleOnly)) -or ($DiscoveryOnly -and $LifecycleOnly)) {
        throw 'Choose commissioning, discovery-only, or lifecycle-only, not a combination.'
    }
    $matterTarget = if ($FrbHost) { 'integration_test/frb_host_test.dart' } elseif ($RustHost) { 'integration_test/rust_host_test.dart' } elseif ($LifecycleOnly) { 'integration_test/lifecycle_test.dart' } elseif ($DiscoveryOnly) { 'integration_test/discovery_test.dart' } else { 'integration_test/control_test.dart' }
    & flutter build apk --debug --target-platform android-arm64 --target $matterTarget `
        "--dart-define=MATTER_LIGHT_ADDRESS=$LightAddress" "--dart-define=MATTER_COMMISSION=$matterCommission"
    if ($LASTEXITCODE -ne 0) { throw 'Qualification build failed.' }
    # Stop only the isolated app, then explicitly preserve its data. Never
    # fall back to uninstall if signing or installation is incompatible.
    & $matterAdb -s $DeviceId shell am force-stop $matterPackage
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop the isolated app.' }
    & $matterAdb -s $DeviceId install -r build/app/outputs/flutter-apk/app-debug.apk
    if ($LASTEXITCODE -ne 0) { throw 'Data-preserving install failed. Do not uninstall.' }
    & $matterAdb -s $DeviceId shell am start -n "$matterPackage/.MainActivity" `
        --ez enable-dart-profiling true --ez enable-checked-mode true `
        --ez verify-entry-points true --ez start-paused true
    if ($LASTEXITCODE -ne 0) { throw 'Could not launch the isolated app.' }
    $matterVm = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $matterProcessId = [string](& $matterAdb -s $DeviceId shell pidof $matterPackage)
        if ($matterProcessId) {
            $matterProcessId = $matterProcessId.Trim()
            $matterLogs = & $matterAdb -s $DeviceId logcat -d "--pid=$matterProcessId"
            $matterVmLine = $matterLogs | Select-String 'The Dart VM service is listening on (http://127\.0\.0\.1:\d+/\S+)' | Select-Object -Last 1
            if ($matterVmLine) {
                $matterVm = [uri]$matterVmLine.Matches[0].Groups[1].Value
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $matterVm) { throw 'The isolated app did not publish a Dart VM service within 30 seconds.' }
    $matterPortProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $matterPortProbe.Start()
    try { $matterForward = [string]$matterPortProbe.LocalEndpoint.Port }
    finally { $matterPortProbe.Stop() }
    & $matterAdb -s $DeviceId forward --no-rebind "tcp:$matterForward" "tcp:$($matterVm.Port)" | Out-Null
    if ($LASTEXITCODE -ne 0) { $matterForward = $null; throw 'Could not forward the test VM service.' }
    $matterHostVm = "http://127.0.0.1:$matterForward$($matterVm.AbsolutePath)"
    & flutter drive --driver=test_driver/integration_test.dart "--use-existing-app=$matterHostVm" -d $DeviceId
    if ($LASTEXITCODE -ne 0) { throw "Matter assertions failed: $matterTarget" }
} catch {
    Write-Error -Message "Qualification runner failed: $($_.Exception.Message) at $($_.ScriptStackTrace)" -ErrorAction Continue
    throw
} finally {
    if ($matterForward -match '^\d+$') {
        & $matterAdb -s $DeviceId forward --remove "tcp:$matterForward" | Out-Null
    }
    # Process shutdown releases process-global SDK resources, not consumer data.
    & $matterAdb -s $DeviceId shell am force-stop $matterPackage | Out-Null
    Pop-Location
}
