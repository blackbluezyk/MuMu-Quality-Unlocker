param([string]$SourcePath,[string]$FixtureRoot,[ValidateSet('SetterFalse','RestoreScope','MissingBackup','HappyApply')][string]$Case)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Source parse error'}
$defs=@($ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
foreach($fn in $defs){Invoke-Expression $fn.Extent.Text}
$script:Root=$FixtureRoot
foreach($i in @(0,1)){
    $dir=Join-Path $FixtureRoot "vms\MuMuPlayer-15.0-$i\configs"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'customer_config.json'),"CURRENT_$i")
    if($Case -eq 'RestoreScope'){
        [IO.File]::WriteAllText((Join-Path $dir 'customer_config.json.bak_20260101_000000'),"ORIGINAL_$i")
    }
}
$DryRun=$false;$NoRestart=$true;$Restore=($Case -in @('RestoreScope','MissingBackup'))
$Preset='2k';$Width=0;$Height=0;$Dpi=0;$FrameRate=144;$VmIndex='0';$InstallPath='FIXTURE'
function Initialize-MuMu {param([string]$Path)}
function Resolve-TargetIndexes {param([string]$Selector) [pscustomobject]@{Index='0';Name='MOCK';AndroidVersion='15.0'}}
if($Case -eq 'SetterFalse'){
    function Set-InstanceResolution {return $false}
}
function Invoke-Manager {
    param([string[]]$CliArgs)
    # Never invokes an installed executable. All responses are deterministic fixtures.
    return [pscustomobject]@{resolution_mode='custom';'resolution_width.custom'='2560.000000';'resolution_height.custom'='1440.000000';'resolution_dpi.custom'='320.000000';max_frame_rate='144'}
}
function Restart-Instance {throw 'Unexpected restart during isolated NoRestart case'}
$main=@($ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[-1]
& ([scriptblock]::Create($main.Extent.Text))
