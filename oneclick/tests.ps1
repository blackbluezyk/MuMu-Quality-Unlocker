param([string]$WorkDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('mumu-oneclick-tests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
[IO.Directory]::CreateDirectory($WorkDirectory)|Out-Null
. (Join-Path $PSScriptRoot 'Backend.ps1')
$script:Manager='FIXTURE:\MuMuManager.exe'
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function Reset-Mock {
    $script:Native='off';$script:Writes=0;$script:Running=$true;$script:Mismatch=$false;$script:NativeFailure=$false;$script:Calls=@()
}
function Invoke-MuMu([string[]]$Arguments) {
    $script:Calls+=,($Arguments)
    if ($script:NativeFailure) {throw 'Fixture CLI error'}
    if ($Arguments[0] -eq 'info') {return (@{index=$Arguments[2];is_android_started=$script:Running;android_version='15.0';error_code=0}|ConvertTo-Json -Compress)}
    Assert ($Arguments[0] -eq 'sh') 'Must use native sh, not adb'
    if ($Arguments[4] -eq ('getprop '+$script:Property)) {return $script:Native}
    $prefix='setprop '+$script:Property+' '
    Assert ($Arguments[4].StartsWith($prefix)) 'Unexpected native operation'
    $v=$Arguments[4].Substring($prefix.Length)
    if ($v -eq "''") {$v=''}
    Assert-Value $v
    $script:Writes++
    if (-not $script:Mismatch) {$script:Native=$v}
    return ''
}
function Case([string]$Name,[scriptblock]$Body) {
    Reset-Mock
    try {& $Body;$results.Add([pscustomobject]@{name=$Name;pass=$true})}
    catch {$results.Add([pscustomobject]@{name=$Name;pass=$false;error=$_.Exception.Message})}
}
function Must-Throw([scriptblock]$Body) {$threw=$false;try {& $Body|Out-Null}catch {$threw=$true};Assert $threw 'Expected a rejecting error'}
function New-Backup([string]$Sub='backups') {return (Save-Snapshot (Join-Path $WorkDirectory $Sub) '0' '15.0' 'off')}

Case 'syntax' {$t=$null;$e=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Backend.ps1'),[ref]$t,[ref]$e)|Out-Null;Assert ($e.Count -eq 0) 'Parser errors'}
Case 'status-never-writes' {$r=Run-Action Status '0' (Join-Path $WorkDirectory 'status-no-dir') '';Assert ($r.NativeAfter -eq 'off' -and $script:Writes -eq 0) 'Status wrote';Assert (-not(Test-Path -LiteralPath (Join-Path $WorkDirectory 'status-no-dir'))) 'Status created backup folder'}
Case 'stopped-status-is-unknown' {$script:Running=$false;$r=Run-Action Status '0' '' '';Assert ($null -eq $r.NativeAfter -and -not $r.Running -and $script:Writes -eq 0) 'Stopped status inaccurate'}
Case 'stopped-enable-rejected' {$script:Running=$false;Must-Throw {Run-Action Enable '0' '' ''};Assert ($script:Writes -eq 0) 'Stopped instance mutated'}
Case 'enable-backup-and-readback' {$r=Run-Action Enable '0' (Join-Path $WorkDirectory 'enable') '';Assert ($r.Written -and $r.NativeAfter -eq 'on') 'Enable not confirmed';$s=Read-Snapshot $r.BackupPath '0' '15.0';Assert ($s.Value -eq 'off') 'Wrong pre-write backup'}
Case 'already-on-is-noop' {$script:Native='on';$r=Run-Action Enable '0' '' '';Assert (-not $r.Written -and $script:Writes -eq 0) 'Repeated enable wrote'}
Case 'disable-records-on' {$script:Native='on';$r=Run-Action Disable '0' (Join-Path $WorkDirectory 'disable') '';Assert ($r.NativeAfter -eq 'off' -and (Read-Snapshot $r.BackupPath '0' '15.0').Value -eq 'on') 'Disable backup wrong'}
Case 'restore-off' {$b=New-Backup 'restore';$script:Native='on';$r=Run-Action Restore '0' (Join-Path $WorkDirectory 'restore-undo') $b;Assert ($r.NativeAfter -eq 'off' -and $r.Written) 'Restore failed'}
Case 'restore-empty-value' {$b=Save-Snapshot (Join-Path $WorkDirectory 'empty') '0' '15.0' '';$script:Native='on';$r=Run-Action Restore '0' (Join-Path $WorkDirectory 'empty-undo') $b;Assert ($r.NativeAfter -ceq '') 'Empty original not restored'}
Case 'tampered-snapshot-rejected' {$b=New-Backup 'tamper';[IO.File]::AppendAllText($b,' ');Must-Throw {Read-Snapshot $b '0' '15.0'}}
Case 'missing-sidecar-rejected' {$b=New-Backup 'sidecar';$copy=Join-Path $WorkDirectory 'no-sidecar.json';Copy-Item -LiteralPath $b -Destination $copy;Must-Throw {Read-Snapshot $copy '0' '15.0'}}
Case 'wrong-instance-rejected' {$b=New-Backup 'instance';Must-Throw {Read-Snapshot $b '1' '15.0'}}
Case 'wrong-engine-rejected' {$b=New-Backup 'engine';Must-Throw {Read-Snapshot $b '0' '12.0'}}
Case 'wrong-manager-rejected' {$b=New-Backup 'manager';$script:Manager='FIXTURE:\Other.exe';Must-Throw {Read-Snapshot $b '0' '15.0'};$script:Manager='FIXTURE:\MuMuManager.exe'}
Case 'unknown-native-value-rejected' {$script:Native='unexpected';Must-Throw {Run-Action Enable '0' '' ''};Assert ($script:Writes -eq 0) 'Guessed a native value'}
Case 'native-failure-not-success' {$script:NativeFailure=$true;Must-Throw {Run-Action Status '0' '' ''}}
Case 'mismatch-not-success' {$script:Mismatch=$true;Must-Throw {Run-Action Enable '0' (Join-Path $WorkDirectory 'mismatch') ''}}
Case 'failed-backup-prevents-write' {$file=Join-Path $WorkDirectory 'not-a-directory';[IO.File]::WriteAllText($file,'fixture');Must-Throw {Run-Action Enable '0' $file ''};Assert ($script:Writes -eq 0) 'Wrote after backup failure'}
Case 'same-second-snapshots-unique' {$a=New-Backup 'collision';$b=New-Backup 'collision';Assert ($a -ne $b -and (Test-Path -LiteralPath $a) -and (Test-Path -LiteralPath $b)) 'Backup overwritten'}
Case 'instance-injection-rejected' {Must-Throw {Run-Action Enable '0;echo injected' '' ''};Assert ($script:Writes -eq 0) 'Index injection'}
Case 'never-claims-automatic-quality' {$r=Run-Action Status '0' '' '';Assert (-not $r.TextureEffectAutomaticallyVerified -and -not $r.GuiSwitchVerified) 'Unverified visual claim'}
Case 'only-one-scoped-property-written' {$r=Run-Action Enable '0' (Join-Path $WorkDirectory 'scope') '';Assert ($script:Writes -eq 1) 'Unexpected write count';foreach($call in $script:Calls){Assert ($call[0] -in @('info','sh')) 'Unexpected game/device command'}}
$fails=@($results|Where-Object {-not $_.pass}).Count
$report=[ordered]@{checks=$results.Count;passed=$results.Count-$fails;failed=$fails;engine=$PSVersionTable.PSVersion.ToString();live_mumu_called=$false;tests=@($results.ToArray())}
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $WorkDirectory 'results.json') -Encoding UTF8
Write-Output ('CHECKS={0} PASS={1} FAIL={2}' -f $results.Count,($results.Count-$fails),$fails)
$results|ForEach-Object {Write-Output (('{0} {1}' -f $(if($_.pass){'PASS'}else{'FAIL'}),$_.name));if(-not $_.pass){Write-Output $_.error}}
if ($fails) {exit 1}
