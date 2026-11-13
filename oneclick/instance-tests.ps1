param(
    [string]$SourceDirectory=$PSScriptRoot,
    [string]$WorkDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('mumu-instance-tests-'+[guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
[IO.Directory]::CreateDirectory($WorkDirectory)|Out-Null
. (Join-Path $SourceDirectory 'Backend.ps1')
$script:Manager='FIXTURE:\MuMu\nx_main\MuMuManager.exe'
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert($Value,[string]$Message) {if (-not $Value) {throw $Message}}
function New-Info([string]$Id,[bool]$Running=$true) {[pscustomobject]@{index=$Id;name=('fixture '+$Id);is_android_started=$Running;android_version='15.0';errcode=0}}
function Reset-Mock {
    $script:Listing=@{'3'=(New-Info '3');'7'=(New-Info '7' $false)}|ConvertTo-Json -Depth 5 -Compress
    $script:Selected=New-Info '3';$script:Removed=$false;$script:Calls=@();$script:Writes=0;$script:Native='off'
}
function Invoke-MuMu([string[]]$Arguments) {
    $script:Calls+=,($Arguments)
    if ($Arguments[0] -eq 'info') {
        if ($Arguments[2] -eq 'all') {return $script:Listing}
        if ($script:Removed) {throw 'MuMuManager exit -200: player index not found'}
        return ($script:Selected|ConvertTo-Json -Compress)
    }
    Assert ($Arguments[0] -eq 'sh') 'Only native sh may follow info'
    if ($Arguments[4].StartsWith('getprop ')) {return $script:Native}
    Assert ($Arguments[4] -eq ('setprop '+$script:Property+' on')) 'Unexpected write target'
    $script:Writes++;$script:Native='on';return ''
}
function Must-Throw([scriptblock]$Body,[string]$Pattern='.') {
    $message=$null;try {& $Body|Out-Null} catch {$message=$_.Exception.Message}
    Assert ($message -and $message -match $Pattern) ('Expected rejection matching '+$Pattern+', got '+$message)
}
function No-Native {
    Assert ($script:Writes -eq 0) 'Unexpected write'
    Assert (@($script:Calls|Where-Object {$_[0] -eq 'sh'}).Count -eq 0) 'Native access before valid selection'
}
function Case([string]$Name,[scriptblock]$Body) {
    Reset-Mock
    try {& $Body;$results.Add([pscustomobject]@{name=$Name;pass=$true})}
    catch {$results.Add([pscustomobject]@{name=$Name;pass=$false;error=$_.Exception.Message})}
}
Case 'list-nonzero-ids-names-running' {$a=@(Get-Instances);Assert ($a.Count -eq 2 -and $a[0].Index -eq '3' -and $a[1].Index -eq '7' -and $a[0].Name -eq 'fixture 3' -and $a[0].Running -and -not $a[1].Running) 'Bad list';No-Native}
Case 'list-numeric-order' {$script:Listing=@{'10'=(New-Info '10');'2'=(New-Info '2')}|ConvertTo-Json -Depth 5;$a=@(Get-Instances);Assert ($a[0].Index -eq '2') 'Lexical ordering'}
Case 'empty-list-is-empty-array-in-json' {$script:Listing='{}';$r=Get-InstanceCatalog;$j=$r|ConvertTo-Json -Depth 6 -Compress;Assert ($r.Instances.Count -eq 0 -and $j -match '"Instances":\[\]') 'Empty array lost';No-Native}
Case 'singleton-array-preserved' {$script:Listing=@{'7'=(New-Info '7')}|ConvertTo-Json -Depth 5;$r=Get-InstanceCatalog;Assert ($r.Instances.Count -eq 1 -and ($r|ConvertTo-Json -Depth 6 -Compress) -match '"Instances":\[') 'Singleton array lost'}
Case 'list-identifies-manager' {$r=Get-InstanceCatalog;Assert ($r.Manager -ceq $script:Manager -and -not $r.Written -and $r.Action -eq 'List') 'Manager binding missing';No-Native}
Case 'invalid-json-rejected' {$script:Listing='garbage';Must-Throw {Get-Instances};No-Native}
Case 'null-list-rejected' {$script:Listing='null';Must-Throw {Get-Instances}}
Case 'array-list-rejected' {$script:Listing='[]';Must-Throw {Get-Instances}}
Case 'scalar-list-rejected' {$script:Listing='42';Must-Throw {Get-Instances}}
Case 'negative-id-rejected' {$script:Listing=@{'-1'=(New-Info '-1')}|ConvertTo-Json -Depth 5;Must-Throw {Get-Instances}}
Case 'overflow-id-rejected' {$script:Listing=@{'999999999999999999999'=(New-Info '999999999999999999999')}|ConvertTo-Json -Depth 5;Must-Throw {Get-Instances}}
Case 'inconsistent-list-identity-rejected' {$script:Listing=@{'3'=(New-Info '7')}|ConvertTo-Json -Depth 5;Must-Throw {Get-Instances}}
Case 'string-running-rejected' {$i=New-Info '3';$i.is_android_started='false';$script:Listing=@{'3'=$i}|ConvertTo-Json -Depth 5;Must-Throw {Get-Instances}}
Case 'missing-running-rejected' {$script:Listing='{"3":{"index":"3"}}';Must-Throw {Get-Instances}}
Case 'missing-zero-does-not-write-or-guess' {Must-Throw {Run-Action Enable '0' (Join-Path $WorkDirectory 'missing-zero') ''};No-Native;Assert (-not(Test-Path -LiteralPath (Join-Path $WorkDirectory 'missing-zero'))) 'Unexpected backup'}
Case 'empty-list-blocks-action' {$script:Listing='{}';Must-Throw {Run-Action Enable '0' '' ''};No-Native}
Case 'selected-nonzero-is-only-write-target' {$r=Run-Action Enable '3' (Join-Path $WorkDirectory 'valid') '';Assert ($r.Instance -eq '3' -and $r.Written -and $script:Writes -eq 1) 'Nonzero index failed';foreach($c in $script:Calls){Assert ($c[2] -in @('all','3')) 'Another instance targeted'}}
Case 'removed-after-list-blocks-native' {$script:Removed=$true;Must-Throw {Run-Action Enable '3' '' ''};No-Native}
Case 'identity-changed-after-list-blocks-native' {$script:Selected=New-Info '7';Must-Throw {Run-Action Enable '3' '' ''};No-Native}
Case 'stopped-after-list-blocks-write' {$script:Selected=New-Info '3' $false;Must-Throw {Run-Action Enable '3' '' ''};No-Native}
Case 'status-stopped-is-readonly' {$script:Selected=New-Info '3' $false;$r=Run-Action Status '3' '' '';Assert (-not $r.Running -and $null -eq $r.NativeAfter) 'Stopped guessed';No-Native}
Case 'errcode-minus200-even-exit0-rejected' {Must-Throw {Assert-ManagerReply '{"errcode":-200,"errmsg":"player index not found"}' 0} '-200'}
Case 'native-exit-minus200-rejected' {Must-Throw {Assert-ManagerReply '{}' -200} '-200'}
Case 'error-code-alias-rejected' {Must-Throw {Assert-ManagerReply '{"error_code":5}' 0}}
Case 'generic-native-exit-rejected' {Must-Throw {Assert-ManagerReply 'fixture' 1}}
Case 'plain-native-on-accepted' {Assert-ManagerReply 'on' 0}
Case 'empty-native-value-accepted' {Assert-ManagerReply '' 0}
Case 'successful-json-with-error-in-name-accepted' {Assert-ManagerReply '{"0":{"name":"error test"}}' 0}
Case 'ambiguous-installation-rejected' {Must-Throw {Select-ManagerCandidate @('C:\fixtureA\nx_main\MuMuManager.exe','D:\fixtureB\nx_main\MuMuManager.exe')}}
Case 'duplicate-installation-is-one' {$v=Select-ManagerCandidate @('C:\fixture\nx_main\MuMuManager.exe','c:\fixture\nx_main\MuMuManager.exe');Assert ($v -ieq 'C:\fixture\nx_main\MuMuManager.exe') 'Duplicate detection'}
Case 'missing-installation-rejected' {Must-Throw {Select-ManagerCandidate @()}}
Case 'explicit-root-and-nx-main-resolve-same' {$d=Join-Path $WorkDirectory 'install';$nx=Join-Path $d 'nx_main';[IO.Directory]::CreateDirectory($nx)|Out-Null;[IO.File]::WriteAllText((Join-Path $nx 'MuMuManager.exe'),'not executable - path fixture only');Assert ((Find-Manager $d) -eq (Find-Manager $nx)) 'Folder forms differ'}
Case 'ui-has-list-not-number-field' {$s=[IO.File]::ReadAllText((Join-Path $SourceDirectory 'Launcher.cs'));Assert ($s -match 'ComboBox index' -and $s -notmatch 'NumericUpDown index' -and $s -match 'DropDownList') 'Missing explicit instance list'}
Case 'ui-has-readonly-refresh' {$s=[IO.File]::ReadAllText((Join-Path $SourceDirectory 'Launcher.cs'));Assert ($s -match 'refresh.Click' -and $s -match 'Run\("List", null\)' -and $s -match 'InvalidateCatalog') 'Missing refresh or invalidation'}
$fails=@($results|Where-Object {-not $_.pass}).Count
$report=[ordered]@{checks=$results.Count;passed=$results.Count-$fails;failed=$fails;engine=$PSVersionTable.PSVersion.ToString();source=$SourceDirectory;live_mumu_called=$false;tests=@($results.ToArray())}
$report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $WorkDirectory 'results.json') -Encoding UTF8
Write-Output ('INSTANCE_CHECKS={0} PASS={1} FAIL={2}' -f $results.Count,($results.Count-$fails),$fails)
$results|ForEach-Object {Write-Output (('{0} {1}' -f $(if($_.pass){'PASS'}else{'FAIL'}),$_.name));if(-not $_.pass){Write-Output $_.error}}
if ($fails) {exit 1}
