# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
# Prepare only: opening the generated .wsb starts the interactive clean VM.
param(
    [Parameter(Mandatory = $true)][string]$ModelPath,
    [Parameter(Mandatory = $true)][string]$BundlePath
)
$ErrorActionPreference = 'Stop'
$model = (Resolve-Path -LiteralPath $ModelPath).Path
if ((Split-Path -Leaf $model) -ne 'gemma-4-E2B-it.litertlm') {
    throw 'This initial harness requires the already-downloaded gemma-4-E2B-it.litertlm model.'
}
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
foreach ($file in @('litertlm_chat.exe', 'LiteRtLm.dll', 'libLiteRt.dll', 'libGemmaModelConstraintProvider.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $file) -PathType Leaf)) { throw "Missing $file" }
}
$session = Join-Path ([IO.Path]::GetTempPath()) ('omnix-sandbox-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $session | Out-Null
$results = Join-Path $session 'results'
New-Item -ItemType Directory -Path $results | Out-Null
$guest = Join-Path $session 'guest'
New-Item -ItemType Directory -Path $guest | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'core_sandbox_guest.ps1') -Destination $guest
$escape = { param($value) [Security.SecurityElement]::Escape($value) }
$configuration = @"
<Configuration>
  <Networking>Disable</Networking>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MemoryInMB>8192</MemoryInMB>
  <MappedFolders>
    <MappedFolder><HostFolder>$(& $escape $bundle)</HostFolder><SandboxFolder>C:\OmnixBundle</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$(& $escape (Split-Path $model))</HostFolder><SandboxFolder>C:\OmnixModel</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$(& $escape $guest)</HostFolder><SandboxFolder>C:\OmnixHarness</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$(& $escape $results)</HostFolder><SandboxFolder>C:\OmnixResults</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OmnixHarness\core_sandbox_guest.ps1</Command></LogonCommand>
</Configuration>
"@
# Generated test configuration, not a source rewrite. Only logs are writable.
$configPath = Join-Path $session 'core-cpu.wsb'
$configuration | Set-Content -LiteralPath $configPath -Encoding UTF8
"Sandbox configuration: $configPath"
"Results directory: $results"
