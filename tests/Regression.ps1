param(
    [string]$SourcePath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'unlock-quality.ps1'),
    [string]$OutDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('mumu-regression-'+[guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
$SourcePath=(Resolve-Path -LiteralPath $SourcePath).Path
New-Item -ItemType Directory -Path $OutDirectory -Force | Out-Null
$OutDirectory=(Resolve-Path -LiteralPath $OutDirectory).Path
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
$parseErrorCount=@($errors).Count
$defs=@($ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$functionsFile=Join-Path $OutDirectory 'functions.ps1'
[IO.File]::WriteAllText($functionsFile,(($defs | ForEach-Object {$_.Extent.Text}) -join "`r`n"),[Text.UTF8Encoding]::new($true))
$results=New-Object 'System.Collections.Generic.List[object]'
function Test-Case([string]$Name,[scriptblock]$Body){
    try {
        $messages=@(& $Body 6>&1)
        $verdict=@($messages | Where-Object {$_ -is [pscustomobject] -and $_.PSObject.Properties['Passed']}) | Select-Object -Last 1
        if($null -eq $verdict){throw 'Test did not produce a verdict'}
        $results.Add([pscustomobject]@{name=$Name;pass=[bool]$verdict.Passed;observed=$verdict.Observed;stdout=@($messages | Where-Object {$_ -ne $verdict} | ForEach-Object {"$_"})})
    } catch {
        $results.Add([pscustomobject]@{name=$Name;pass=$false;harness_error=$_.Exception.Message;location=$_.ScriptStackTrace})
    }
}
function Verdict($Passed,$Observed){[pscustomobject]@{Passed=[bool]$Passed;Observed=$Observed}}
function New-Config([string]$Root,[string]$Folder,[string]$Content){
    $dir=Join-Path $Root "vms\$Folder\configs"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $p=Join-Path $dir 'customer_config.json'
    [IO.File]::WriteAllText($p,$Content)
    return $p
}

Test-Case 'syntax' {Verdict ($parseErrorCount -eq 0) "parse_errors=$parseErrorCount"}
Test-Case 'config-index-isolation' {
    . $functionsFile
    $script:Root=Join-Path $OutDirectory 'isolation'
    $p0=New-Config $script:Root 'MuMuPlayer-15.0-0' 'ZERO'
    $p1=New-Config $script:Root 'MuMuPlayer-15.0-1' 'ONE'
    $found=@(Get-ConfigFile -InstanceIndex '0')
    Verdict ($found.Count -eq 1 -and $found[0].FullName -eq $p0) @($found.FullName)
}
Test-Case 'config-ambiguous-fails-closed' {
    . $functionsFile
    $script:Root=Join-Path $OutDirectory 'ambiguous'
    New-Config $script:Root 'MuMuPlayer-12.0-0' 'OLD' | Out-Null
    New-Config $script:Root 'MuMuPlayer-15.0-0' 'NEW' | Out-Null
    $threw=$false;try{Get-ConfigFile -InstanceIndex '0' | Out-Null}catch{$threw=$true}
    Verdict $threw "threw=$threw"
}
Test-Case 'config-active-android-version' {
    . $functionsFile
    $script:Root=Join-Path $OutDirectory 'version'
    New-Config $script:Root 'MuMuPlayer-12.0-0' 'OLD' | Out-Null
    $p=New-Config $script:Root 'MuMuPlayer-15.0-0' 'NEW'
    $found=@(Get-ConfigFile -InstanceIndex '0' -AndroidVersion '15.0')
    Verdict ($found.Count -eq 1 -and $found[0].FullName -eq $p) @($found.FullName)
}
Test-Case 'same-second-backups-preserve-pristine' {
    . $functionsFile
    function Get-Date {param([string]$Format) '20260101_010101'}
    $p=Join-Path $OutDirectory 'collision.json'
    [IO.File]::WriteAllText($p,'PRISTINE')
    $a=Backup-Config $p
    [IO.File]::WriteAllText($p,'CHANGED')
    $b=Backup-Config $p
    $original=Get-OriginalBackup $p
    $text=[IO.File]::ReadAllText($a)
    $baseline=[IO.File]::ReadAllText($original.FullName)
    Verdict ($a -ne $b -and $text -eq 'PRISTINE' -and $baseline -eq 'PRISTINE') ([ordered]@{different_names=($a -ne $b);first_snapshot=$text;restore_baseline=$baseline})
}
Test-Case 'backup-exclusive-copy-never-overwrites' {
    . $functionsFile
    $s=Join-Path $OutDirectory 'exclusive-source';$d=Join-Path $OutDirectory 'exclusive-destination'
    [IO.File]::WriteAllText($s,'NEW');[IO.File]::WriteAllText($d,'PRESERVED')
    $threw=$false
    if(Get-Command Copy-ConfigExclusive -ErrorAction SilentlyContinue){try{Copy-ConfigExclusive $s $d}catch{$threw=$true}}
    $text=[IO.File]::ReadAllText($d)
    Verdict ($threw -and $text -eq 'PRESERVED') ([ordered]@{collision_rejected=$threw;destination=$text})
}
Test-Case 'legacy-backup-order-ignores-mtime' {
    . $functionsFile
    $p=Join-Path $OutDirectory 'legacy.json'
    [IO.File]::WriteAllText($p,'CURRENT')
    $a="$p.bak_20200101_000000";$b="$p.bak_20210101_000000"
    [IO.File]::WriteAllText($a,'FIRST');[IO.File]::WriteAllText($b,'LATER')
    [IO.File]::SetLastWriteTime($a,[datetime]'2030-01-01');[IO.File]::SetLastWriteTime($b,[datetime]'2020-01-01')
    $selected=Get-OriginalBackup $p
    Verdict ($selected.FullName -eq $a) $selected.Name
}
foreach($exitCode in @(7,0)){
    $code=$exitCode
    Test-Case "native-or-json-error-exit-$code" {
        . $functionsFile
        $cli=Join-Path $OutDirectory "native-error-$code.cmd"
        [IO.File]::WriteAllText($cli,"@echo off`r`necho {`"error_code`":7,`"message`":`"denied`"}`r`nexit /b $code`r`n",[Text.Encoding]::ASCII)
        $script:ManagerPath=$cli
        $threw=$false;$message=''
        try{Invoke-Manager @('setting','-v','0') | Out-Null}catch{$threw=$true;$message=$_.Exception.Message}
        Verdict $threw ([ordered]@{exception=$threw;message=$message})
    }
}
Test-Case 'setter-stops-on-mode-json-error' {
    . $functionsFile
    $DryRun=$false;$script:CallCount=0
    function Invoke-Manager {param([string[]]$CliArgs) $script:CallCount++;[pscustomobject]@{error_code=7;message='denied'}}
    $threw=$false;try{Set-InstanceResolution -Index 0 -W 2560 -H 1440 -D 320 -Rate 144 | Out-Null}catch{$threw=$true}
    Verdict ($threw -and $script:CallCount -eq 1) ([ordered]@{exception=$threw;manager_calls=$script:CallCount})
}
Test-Case 'setter-rejects-mismatched-readback' {
    . $functionsFile
    $DryRun=$false
    function Invoke-Manager {param([string[]]$CliArgs) [pscustomobject]@{resolution_mode='custom';'resolution_width.custom'='1280.000000';'resolution_height.custom'='720.000000';'resolution_dpi.custom'='160.000000';max_frame_rate=60}}
    $threw=$false;$answer=$null
    try{$answer=Set-InstanceResolution -Index 0 -W 2560 -H 1440 -D 320 -Rate 144}catch{$threw=$true}
    Verdict ($threw -or $answer -eq $false) ([ordered]@{exception=$threw;returned=$answer})
}
Test-Case 'setter-rejects-empty-readback' {
    . $functionsFile
    $DryRun=$false
    function Invoke-Manager {param([string[]]$CliArgs) return $null}
    $threw=$false;$answer=$null
    try{$answer=Set-InstanceResolution -Index 0 -W 2560 -H 1440 -D 320 -Rate 144}catch{$threw=$true}
    Verdict ($threw -or $answer -eq $false) ([ordered]@{exception=$threw;returned=$answer})
}
Test-Case 'setter-accepts-matching-readback' {
    . $functionsFile
    $DryRun=$false
    function Invoke-Manager {param([string[]]$CliArgs) [pscustomobject]@{resolution_mode='custom';'resolution_width.custom'='2560.000000';'resolution_height.custom'='1440.000000';'resolution_dpi.custom'='320.000000';max_frame_rate='144'}}
    $answer=Set-InstanceResolution -Index 0 -W 2560 -H 1440 -D 320 -Rate 144
    Verdict ($answer -eq $true) $answer
}
Test-Case 'invariant-decimal-serialization' {
    . $functionsFile
    $DryRun=$false;$script:Written=@()
    function Invoke-Manager {param([string[]]$CliArgs)
        if(($CliArgs -contains '--value') -and ($CliArgs -contains 'resolution_width.custom')){$script:Written=$CliArgs}
        [pscustomobject]@{resolution_mode='custom';'resolution_width.custom'='2560.000000';'resolution_height.custom'='1440.000000';'resolution_dpi.custom'='320.000000';max_frame_rate='144'}
    }
    $old=[Threading.Thread]::CurrentThread.CurrentCulture
    try{
        [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('de-DE')
        Set-InstanceResolution -Index 0 -W 2560 -H 1440 -D 320 -Rate 144 | Out-Null
        $i=[array]::IndexOf($script:Written,'resolution_width.custom');$v=$script:Written[$i+2]
        Verdict ($v -eq '2560.000000') $v
    }finally{[Threading.Thread]::CurrentThread.CurrentCulture=$old}
}
Test-Case 'enumerates-sparse-and-high-indexes' {
    . $functionsFile
    function Invoke-Manager {param([string[]]$CliArgs)
        if($CliArgs[2] -eq 'all'){
            return [pscustomobject]@{'0'=[pscustomobject]@{index='0';error_code=0};'2'=[pscustomobject]@{index='2';error_code=0};'128'=[pscustomobject]@{index='128';error_code=0}}
        }
        if($CliArgs[2] -in @('0','2','128')){return [pscustomobject]@{index=$CliArgs[2];error_code=0}}
        return [pscustomobject]@{error_code=1}
    }
    $list=@(Get-InstanceList);$indexes=@($list.Index)
    Verdict (($indexes -join ',') -eq '0,2,128') $indexes
}
Test-Case 'duplicate-selector-processed-once' {
    . $functionsFile
    function Get-InstanceList {[pscustomobject]@{Index='0'}}
    $list=@(Resolve-TargetIndexes '0,0')
    Verdict ($list.Count -eq 1) "count=$($list.Count)"
}
Test-Case 'dry-run-includes-mode-and-never-calls-writer' {
    . $functionsFile
    $DryRun=$true;$script:ManagerPath='MOCK';$script:WriteCalls=0
    function Invoke-Manager {param([string[]]$CliArgs) $script:WriteCalls++;throw 'Unexpected manager invocation'}
    $messages=@(Set-InstanceResolution -Index 0 -W 2560 -H 1440 -D 320 -Rate 144 6>&1)
    $text=($messages | ForEach-Object {"$_"}) -join "`n"
    Verdict ($script:WriteCalls -eq 0 -and $text -match 'resolution_mode --value custom\.0') $text
}
Test-Case 'restart-timeout-is-failure' {
    . $functionsFile
    $DryRun=$false
    function Start-Sleep {param([int]$Seconds)}
    function Invoke-Manager {param([string[]]$CliArgs) [pscustomobject]@{is_android_started=$false}}
    $threw=$false;try{Restart-Instance 0}catch{$threw=$true}
    Verdict $threw "exception=$threw"
}

$engine=(Get-Process -Id $PID).Path
foreach($name in @('SetterFalse','RestoreScope','MissingBackup','HappyApply')){
    $case=$name
    Test-Case "main-$case" {
        $fixture=Join-Path $OutDirectory ("main-"+$case)
        $stdout=Join-Path $OutDirectory ("main-"+$case+'.stdout.txt')
        $stderr=Join-Path $OutDirectory ("main-"+$case+'.stderr.txt')
        & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'MainCase.ps1') -SourcePath $SourcePath -FixtureRoot $fixture -Case $case 1> $stdout 2> $stderr
        $exit=$LASTEXITCODE;$text=[IO.File]::ReadAllText($stdout);$err=[IO.File]::ReadAllText($stderr)
        $pass=$false;$other=$null
        switch($case){
            'SetterFalse' {$pass=($exit -eq 1 -and $text -notmatch '\[\+\] Done\.')}
            'MissingBackup' {$pass=($exit -eq 1)}
            'HappyApply' {$pass=($exit -eq 0 -and $text -match '\[\+\] Done\.')}
            'RestoreScope' {
                $other=[IO.File]::ReadAllText((Join-Path $fixture 'vms\MuMuPlayer-15.0-1\configs\customer_config.json'))
                $target=[IO.File]::ReadAllText((Join-Path $fixture 'vms\MuMuPlayer-15.0-0\configs\customer_config.json'))
                $pass=($exit -eq 0 -and $other -eq 'CURRENT_1' -and $target -eq 'ORIGINAL_0')
            }
        }
        Verdict $pass ([ordered]@{exit=$exit;stdout=$text;stderr=$err;untargeted_instance=$other})
    }
}
$fail=@($results.ToArray() | Where-Object {-not $_.pass}).Count
$report=[ordered]@{source=$SourcePath;source_sha256=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash;engine=[string]$PSVersionTable.PSVersion;checks=$results.Count;passed=($results.Count-$fail);failed=$fail;input='Deterministic fixtures only; indexes 0,1 / 0,2,128; preset 2k, dpi320, fps144; no installed MuMu write/control command';tests=@($results.ToArray())}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutDirectory 'results.json') -Encoding UTF8
Write-Output ("CHECKS={0} PASS={1} FAIL={2}" -f $results.Count,($results.Count-$fail),$fail)
foreach($r in $results.ToArray()){$tag=if($r.pass){'PASS '}else{'FAIL '};Write-Output ($tag+$r.name)}
if($fail){exit 1}
exit 0
