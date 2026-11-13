param([string]$OutDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('mumu-all-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$engine=(Get-Process -Id $PID).Path
$failed=$false
foreach($suite in @(@{File='Regression.ps1';Folder='display'},@{File='QualityFeatures.ps1';Folder='features'})){
    & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $suite.File) -OutDirectory (Join-Path $OutDirectory $suite.Folder)
    if($LASTEXITCODE -ne 0){$failed=$true}
}
& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'oneclick\tests.ps1') -WorkDirectory (Join-Path $OutDirectory 'oneclick')
if($LASTEXITCODE -ne 0){$failed=$true}
& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'oneclick\instance-tests.ps1') -WorkDirectory (Join-Path $OutDirectory 'instances')
if($LASTEXITCODE -ne 0){$failed=$true}
& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'oneclick\smoke.ps1') -WorkDirectory (Join-Path $OutDirectory 'smoke')
if($LASTEXITCODE -ne 0){$failed=$true}
Write-Output ('Test records: '+$OutDirectory)
if($failed){exit 1};exit 0
