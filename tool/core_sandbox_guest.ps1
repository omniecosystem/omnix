# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'
$result = 'C:\OmnixResults\result.txt'
Start-Transcript -Path 'C:\OmnixResults\transcript.txt' -Force
try {
    'System runtime DLLs (presence is recorded, not assumed absent):'
    foreach ($dll in @('MSVCP140.dll', 'VCRUNTIME140.dll', 'VCRUNTIME140_1.dll', 'VCRUNTIME140_THREADS.dll')) {
        "$dll=$(Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32\$dll"))"
    }
    & 'C:\OmnixBundle\litertlm_chat.exe' 'C:\OmnixModel\gemma-4-E2B-it.litertlm' 'Reply only OK.'
    if ($LASTEXITCODE -ne 0) { throw "Inference exited with $LASTEXITCODE" }
    'PASS: CPU model loaded, generated, and released.' | Set-Content -LiteralPath $result
} catch {
    "FAIL: $_" | Set-Content -LiteralPath $result
} finally {
    Stop-Transcript
}
