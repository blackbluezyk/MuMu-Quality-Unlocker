param(
    [string]$SourceDirectory=(Split-Path $PSScriptRoot -Parent),
    [string]$OutDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('mumu-features-'+[guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
$SourceDirectory=(Resolve-Path -LiteralPath $SourceDirectory).Path
New-Item -ItemType Directory -Path $OutDirectory -Force|Out-Null
$OutDirectory=(Resolve-Path -LiteralPath $OutDirectory).Path
$results=New-Object 'System.Collections.Generic.List[object]'
$common=Join-Path $OutDirectory 'common.ps1';$picfx=Join-Path $OutDirectory 'picfx-functions.ps1'
$parse=@{}
foreach($pair in @(@{Name='stable';File='unlock-quality.ps1';Dest=$common},@{Name='picfx';File='picfx-local.ps1';Dest=$picfx})){
    $p=Join-Path $SourceDirectory $pair.File
    if(-not (Test-Path -LiteralPath $p)){ $parse[$pair.Name]=-1; [IO.File]::WriteAllText($pair.Dest,'');continue }
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
    $parse[$pair.Name]=@($errors).Count
    $defs=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
    [IO.File]::WriteAllText($pair.Dest,(($defs|ForEach-Object {$_.Extent.Text})-join "`r`n"),[Text.UTF8Encoding]::new($true))
}
function Check([string]$Name,[scriptblock]$Body){
    try{
        $items=@(& $Body 6>&1)
        $v=@($items|Where-Object {$_ -is [pscustomobject] -and $_.PSObject.Properties['Passed']})|Select-Object -Last 1
        if($null -eq $v){throw 'No verdict'}
        $results.Add([pscustomobject]@{name=$Name;pass=[bool]$v.Passed;observed=$v.Observed})
    }catch{$results.Add([pscustomobject]@{name=$Name;pass=$false;error=$_.Exception.Message;location=$_.ScriptStackTrace})}
}
function Verdict($Passed,$Observed){[pscustomobject]@{Passed=[bool]$Passed;Observed=$Observed}}
$script:PicFxPackage='com.tencent.KiHan';$script:PicFxKey='nemud.tool.com.tencent.KiHan.picfx'
$script:ManagerPath='FIXTURE_MANAGER'
Check 'syntax-display' { Verdict ($parse.stable -eq 0) $parse.stable }
Check 'syntax-picfx' { Verdict ($parse.picfx -eq 0) $parse.picfx }
Check 'native-getter-is-sh-not-adb' {
    . $common;. $picfx
    $script:Captured=@()
    function Invoke-Manager {param([string[]]$CliArgs) $script:Captured=$CliArgs;return 'on'}
    $v=Get-NativePicFxValue '0'
    Verdict ($v -eq 'on' -and $script:Captured[0] -eq 'sh' -and $script:Captured[-1] -ceq 'getprop nemud.tool.com.tencent.KiHan.picfx') $script:Captured
}
Check 'native-empty-value-preserved' {
    . $common;. $picfx
    function Invoke-Manager {param([string[]]$CliArgs) return $null}
    $v=Get-NativePicFxValue '0'
    Verdict ($v -ceq '') ('value=['+$v+']')
}
Check 'native-json-not-treated-as-value' {
    . $common;. $picfx
    function Invoke-Manager {param([string[]]$CliArgs) [pscustomobject]@{value='on'}}
    $threw=$false;try{Get-NativePicFxValue '0'|Out-Null}catch{$threw=$true}
    Verdict $threw "rejected=$threw"
}
Check 'raw-native-text-does-not-convert-json-null' {
    . $common
    $cli=Join-Path $OutDirectory 'literal-null.cmd'
    [IO.File]::WriteAllText($cli,"@echo off`r`necho null`r`nexit /b 0`r`n",[Text.Encoding]::ASCII)
    $previousManager=$script:ManagerPath
    try {
        $script:ManagerPath=$cli
        $text=Invoke-Manager -CliArgs @('sh') -RawText
        Verdict ($text -is [string] -and $text -ceq 'null') @{type=($text.GetType().Name);value=$text}
    } finally { $script:ManagerPath=$previousManager }
}
foreach($bad in @('ON','true','null','on; dangerous','on value')){
    $value=$bad
    Check ('reject-unknown-value-'+$value) {
        . $common;. $picfx
        $threw=$false;try{Assert-PicFxValue $value}catch{$threw=$true}
        Verdict $threw $value
    }
}
Check 'setter-rejects-false-success' {
    . $common;. $picfx
    function Invoke-Manager {param([string[]]$CliArgs) if($CliArgs[-1] -like 'getprop *'){return 'off'}}
    $threw=$false;try{Set-NativePicFxValue '0' 'on'|Out-Null}catch{$threw=$true}
    Verdict $threw "mismatch_rejected=$threw"
}
Check 'snapshot-round-trip-and-collision-safety' {
    . $common;. $picfx
    $dir=Join-Path $OutDirectory 'snapshots'
    $a=Save-PicFxSnapshot $dir '0' '15.0' 'off';$b=Save-PicFxSnapshot $dir '0' '15.0' 'on'
    $s=Read-PicFxSnapshot $a '0' '15.0'
    Verdict ($a -ne $b -and $s.NativeValue -ceq 'off') @{distinct=($a -ne $b);restored_value=$s.NativeValue}
}
Check 'snapshot-empty-value-round-trip' {
    . $common;. $picfx
    $a=Save-PicFxSnapshot (Join-Path $OutDirectory 'empty-snapshot') '0' '15.0' ''
    $s=Read-PicFxSnapshot $a '0' '15.0'
    Verdict ($s.NativeValue -ceq '') @{value=$s.NativeValue}
}
foreach($kind in @('checksum','sidecar','instance','version','package','property','manager','null-value','schema')){
    $mode=$kind
    Check ('snapshot-reject-'+$mode) {
        . $common;. $picfx
        $a=Save-PicFxSnapshot (Join-Path $OutDirectory ('bad-'+$mode)) '0' '15.0' 'off'
        $idx='0';$ver='15.0'
        switch($mode){
            'checksum' {[IO.File]::AppendAllText($a,' ')}
            'sidecar' {Remove-Item -LiteralPath ($a+'.sha256')}
            'instance' {$idx='1'}
            'version' {$ver='12.0'}
            default {
                $s=Get-Content -LiteralPath $a -Raw -Encoding UTF8|ConvertFrom-Json
                switch($mode){
                    'package' {$s.GamePackage='another.package'}
                    'property' {$s.PropertyName='another.property'}
                    'manager' {$s.ManagerPath='OTHER_MANAGER'}
                    'null-value' {$s.NativeValue=$null}
                    'schema' {$s.SchemaVersion=999}
                }
                [IO.File]::WriteAllText($a,($s|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
                [IO.File]::WriteAllText(($a+'.sha256'),(Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash)
            }
        }
        $threw=$false;try{Read-PicFxSnapshot $a $idx $ver|Out-Null}catch{$threw=$true}
        Verdict $threw "rejected=$threw"
    }
}
Check 'display-rejects-invalid-number' {
    . $common
    function Invoke-Manager {param([string[]]$CliArgs) [pscustomobject]@{'resolution_width.custom'='NaN';'resolution_height.custom'='1080';'resolution_dpi.custom'='280';max_frame_rate='144'}}
    $threw=$false;try{Get-DisplayStatus '0' $false|Out-Null}catch{$threw=$true}
    Verdict $threw "rejected=$threw"
}
Check 'display-runtime-failure-not-faked-as-match' {
    . $common
    function Invoke-Manager {param([string[]]$CliArgs)
        if($CliArgs[0] -eq 'adb'){throw 'Fixture ADB unavailable'}
        [pscustomobject]@{resolution_mode='custom';'resolution_width.custom'='1920';'resolution_height.custom'='1080';'resolution_dpi.custom'='280';max_frame_rate='144'}
    }
    $s=Get-DisplayStatus '0' $true
    Verdict (-not $s.RuntimeMatchesConfiguredDisplay -and $s.RuntimeReadbackError -eq 'Fixture ADB unavailable' -and $null -eq $s.ActualGameFps) $s
}
$engine=(Get-Process -Id $PID).Path
foreach($name in @('Import','DisplayStatus','DisplayStopped','Status','Stopped','Enable','NoConsent','DryRun','Restore','StoppedEnable','Mismatch','Unknown')){
    $case=$name
    Check ('entry-'+$case) {
        $dir=Join-Path $OutDirectory ('entry-'+$case)
        $stdout=$dir+'.stdout.txt';$stderr=$dir+'.stderr.txt'
        # Windows PowerShell 5.1 turns redirected native stderr into ErrorRecords.
        # Capture expected failing-child cases without stopping the harness itself.
        $previousErrorAction=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'FeatureCase.ps1') -SourceDirectory $SourceDirectory -FixtureRoot $dir -Case $case 1> $stdout 2> $stderr
            $exit=$LASTEXITCODE
        } finally { $ErrorActionPreference=$previousErrorAction }
        $text=[IO.File]::ReadAllText($stdout);$err=[IO.File]::ReadAllText($stderr)
        $obsPath=Join-Path $dir 'observation.json';$obs=$null
        if(Test-Path -LiteralPath $obsPath){$obs=Get-Content -LiteralPath $obsPath -Raw|ConvertFrom-Json}
        $pass=$false
        if($case -eq 'Import'){$pass=($exit -eq 0 -and $text -match 'IMPORT_READONLY')}
        elseif($case -in @('NoConsent','StoppedEnable','Mismatch','Unknown')){
            $pass=($exit -eq 1)
            if($case -eq 'NoConsent'){$pass=$pass -and $err -match 'require -Experimental' -and $obs.Writes -eq 0}
            if($case -eq 'StoppedEnable'){$pass=$pass -and $err -match 'instance is stopped' -and $obs.Writes -eq 0}
            if($case -eq 'Unknown'){$pass=$pass -and $err -match 'Unrecognized native picfx value' -and $obs.Writes -eq 0}
            if($case -eq 'Mismatch'){$pass=$pass -and $err -match 'readback mismatch' -and $obs.Writes -eq 1}
        }elseif($exit -eq 0){
            $obj=$text|ConvertFrom-Json
            if($case -eq 'DisplayStatus'){$pass=($obs.Writes -eq 0 -and -not $obs.BackupsExist -and $obj[0].RuntimeMatchesConfiguredDisplay -and $null -eq $obj[0].ActualGameFps)}
            elseif($case -eq 'DisplayStopped'){$pass=($obs.Writes -eq 0 -and -not $obj[0].Running -and $null -eq $obj[0].AndroidDisplay)}
            elseif($case -eq 'Enable'){$pass=($obs.Writes -eq 1 -and $obj.NativeAfter -ceq 'on' -and (Test-Path -LiteralPath $obj.SnapshotPath) -and $obj.EffectVerification -eq 'NotMeasuredByThisScript')}
            elseif($case -eq 'Restore'){$pass=($obs.Writes -eq 1 -and $obj.NativeAfter -ceq 'off')}
            elseif($case -eq 'DryRun'){$pass=($obs.Writes -eq 0 -and -not $obs.BackupsExist -and $obj.RequestedValue -eq 'on' -and -not $obj.Written)}
            else{$pass=($obs.Writes -eq 0 -and -not $obs.BackupsExist -and $obj.EffectVerification -eq 'NotMeasuredByThisScript')}
        }
        Verdict $pass @{exit=$exit;stdout=$text;stderr=$err;observation=$obs}
    }
}
$failed=@($results.ToArray()|Where-Object {-not $_.pass}).Count
[ordered]@{source=$SourceDirectory;engine=[string]$PSVersionTable.PSVersion;checks=$results.Count;passed=($results.Count-$failed);failed=$failed;scope='Fixture-only. No installed MuMu executable, account or game is called.';tests=@($results.ToArray())}|
    ConvertTo-Json -Depth 14|Set-Content -LiteralPath (Join-Path $OutDirectory 'results.json') -Encoding UTF8
Write-Output ('CHECKS={0} PASS={1} FAIL={2}' -f $results.Count,($results.Count-$failed),$failed)
foreach($r in $results){$tag=if($r.pass){'PASS '}else{'FAIL '};Write-Output ($tag+$r.name)}
if($failed){exit 1};exit 0
