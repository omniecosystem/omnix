param([Parameter(Mandatory=$true)][string]$NodeExecutable)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $root 'tool\matterjs_spike'
$stage = Join-Path $root '.local-native\matterjs-app'
$node = (Resolve-Path -LiteralPath $NodeExecutable).Path
$signature = Get-AuthenticodeSignature -LiteralPath $node
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'OpenJS Foundation') {
  throw 'Supply an Authenticode-verified OpenJS Node executable.'
}
$version = & $node --version
if ($LASTEXITCODE -ne 0 -or $version -ne 'v24.19.0') {
  throw 'This qualification pins Node v24.19.0; use that version explicitly.'
}
$architecture = & $node -p 'process.arch'
if ($LASTEXITCODE -ne 0 -or $architecture -ne 'x64') {
  throw 'This qualification targets Windows x64, not another Node architecture.'
}
if (Test-Path -LiteralPath $stage) {
  throw "Stage already exists: $stage. Inspect it before replacing; no automatic deletion."
}
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath $node -Destination (Join-Path $stage 'node.exe')
foreach ($name in @('package.json', 'pnpm-lock.yaml', 'controller.mjs', 'windows_interfaces.mjs', 'host_controller.mjs')) {
  Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $stage $name)
}
Push-Location $stage
try {
  # A hoisted physical dependency tree avoids links to the developer's pnpm store.
  & pnpm install --prod --frozen-lockfile --node-linker=hoisted --ignore-scripts
  if ($LASTEXITCODE -ne 0) { throw 'Portable dependency staging failed.' }
  $links = Get-ChildItem node_modules -Recurse -Attributes ReparsePoint
  if ($links) { throw 'The dependency bundle contains links; packaging refused.' }
} finally { Pop-Location }
$hash = (Get-FileHash -LiteralPath (Join-Path $stage 'node.exe') -Algorithm SHA256).Hash
Write-Output "Staged signed $version; node.exe SHA256=$hash"
Write-Output 'Private qualification only. Add complete Node and dependency license notices before distribution.'
