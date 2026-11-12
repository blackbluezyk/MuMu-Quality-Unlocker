param([string]$SourceDirectory,[string]$FixtureRoot,[string]$Case)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $FixtureRoot -Force | Out-Null
$stable=Join-Path $SourceDirectory 'unlock-quality.ps1'
if ($Case -eq 'Import') {
    . $stable -InstallPath (Join-Path $FixtureRoot 'NOT_INSTALLED')
    Write-Output 'IMPORT_READONLY'
    exit 0
}
$isDisplay=$Case -like 'Display*'
$file=if ($isDisplay) { $stable } else { Join-Path $SourceDirectory 'picfx-local.ps1' }
foreach ($p in @($stable,$file) | Select-Object -Unique) {
    $tok=$null; $err=$null
    $a=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tok,[ref]$err)
    if ($err.Count) { throw 'Source parse error' }
    foreach ($fn in $a.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) {
        Invoke-Expression $fn.Extent.Text
    }
}
$main=@($a.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[-1]
$script:PicFxPackage='com.tencent.KiHan'; $script:PicFxKey='nemud.tool.com.tencent.KiHan.picfx'
$script:ManagerPath=Join-Path $FixtureRoot 'MOCK_MANAGER.exe'
$script:Root=$FixtureRoot; $script:MockValue='off'; $script:Writes=0
$script:Calls=New-Object 'System.Collections.Generic.List[object]'
$VmIndex='0';$InstallPath='FIXTURE';$AsJson=$true;$DryRun=($Case -eq 'DryRun')
$Experimental=($Case -notin @('NoConsent','DryRun')); $BackupPath=''
$BackupDirectory=Join-Path $FixtureRoot 'backups';$Action='Status'
$Status=$isDisplay; $Restore=$false;$NoRestart=$true;$Width=0;$Height=0;$Dpi=0;$FrameRate=0;$Preset='2k'
switch($Case){
    'Enable' {$Action='Enable'}
    'NoConsent' {$Action='Enable'}
    'DryRun' {$Action='Enable'}
    'StoppedEnable' {$Action='Enable'}
    'Restore' {$Action='Restore'}
    'Mismatch' {$Action='Enable'}
}
function Initialize-MuMu {param([string]$Path,[switch]$Quiet)}
function Resolve-TargetIndexes {
    param([string]$Selector)
    [pscustomobject]@{Index='0';Name='FIXTURE';AndroidVersion='15.0';Running=($Case -notin @('Stopped','StoppedEnable','DisplayStopped'))}
}
function Backup-Config {throw 'Unexpected display backup in read-only status'}
function Set-InstanceResolution {throw 'Unexpected display write in read-only status'}
function Restart-Instance {throw 'Unexpected restart'}
function Invoke-Manager {
    param([string[]]$CliArgs,[switch]$RawText)
    $script:Calls.Add(@($CliArgs))
    switch ($CliArgs[0]) {
        'setting' {
            if ($CliArgs -contains '--value') { throw 'Unexpected display writer' }
            return [pscustomobject]@{resolution_mode='custom';'resolution_width.custom'='1920.000000';'resolution_height.custom'='1080.000000';'resolution_dpi.custom'='280.000000';max_frame_rate='144'}
        }
        'adb' {
            if ($CliArgs[-1] -eq 'shell wm size') {return "Physical size: 1080x1920"}
            if ($CliArgs[-1] -eq 'shell wm density') {return 'Physical density: 280'}
            throw 'Unexpected ADB command'
        }
        'sh' {
            if ($CliArgs[-1] -eq ('getprop '+$script:PicFxKey)) {
                if ($Case -eq 'Unknown') {return 'unexpected-value'}
                return $script:MockValue
            }
            if ($CliArgs[-1] -match ('^setprop '+[regex]::Escape($script:PicFxKey)+' (on|off|'''')$')) {
                $script:Writes++
                if ($Case -ne 'Mismatch') { $script:MockValue=if($Matches[1] -eq "''"){''}else{$Matches[1]} }
                return $null
            }
            throw 'Unexpected native command'
        }
        default {throw 'Unexpected native operation'}
    }
}
if ($Case -eq 'Restore') {
    $BackupPath=Save-PicFxSnapshot -Directory $BackupDirectory -Index '0' -AndroidVersion '15.0' -Value 'off'
    $script:MockValue='on'
}
try { & ([scriptblock]::Create($main.Extent.Text)) }
finally {
    [pscustomobject]@{Writes=$script:Writes;NativeValue=$script:MockValue;Calls=@($script:Calls.ToArray());BackupsExist=(Test-Path -LiteralPath $BackupDirectory)} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $FixtureRoot 'observation.json') -Encoding UTF8
}
