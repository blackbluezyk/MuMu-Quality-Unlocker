param([string]$WorkDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('mumu-smoke-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
[IO.Directory]::CreateDirectory($WorkDirectory)|Out-Null
$WorkDirectory=(Resolve-Path -LiteralPath $WorkDirectory).Path
& (Join-Path $PSScriptRoot 'build.ps1') -OutputDirectory (Join-Path $WorkDirectory 'build')
$records=New-Object 'System.Collections.Generic.List[object]'
function Invoke-Child([string]$File,[string]$Arguments,[bool]$Removed=$false) {
    $s=New-Object Diagnostics.ProcessStartInfo
    $s.FileName=$File;$s.Arguments=$Arguments;$s.UseShellExecute=$false;$s.CreateNoWindow=$true
    $s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true
    $s.StandardOutputEncoding=[Text.Encoding]::UTF8;$s.StandardErrorEncoding=[Text.Encoding]::UTF8
    $s.EnvironmentVariables.Remove('PSModulePath')
    $s.EnvironmentVariables['MUMU_FIXTURE_LOG']=(Join-Path $WorkDirectory 'fixture-calls.log')
    $s.EnvironmentVariables['MUMU_FIXTURE_REMOVED']=[string][int]$Removed
    $p=[Diagnostics.Process]::Start($s)
    try {
        $o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(30000)) {try {$p.Kill()} catch {};throw 'Fixture process timed out'}
        $r=[pscustomobject]@{File=$File;Arguments=$Arguments;Stdout=$o.Result;Stderr=$e.Result;Exit=$p.ExitCode}
        $records.Add($r);return $r
    } finally {$p.Dispose()}
}
function Assert($Value,[string]$Message) {if (-not $Value) {throw $Message}}
try {
    $exe=Join-Path $WorkDirectory 'build\MuMuLocalQuality.exe'
    $r=Invoke-Child $exe '--self-test'
    $j=$r.Stdout|ConvertFrom-Json
    Assert ($r.Exit -eq 0 -and $j.resource_integrity -and $j.instance_selection -and -not $j.live_settings_touched) 'EXE self-test failed'
    $nx=Join-Path $WorkDirectory 'fixture\nx_main';[IO.Directory]::CreateDirectory($nx)|Out-Null
    $code=@'
using System;
using System.IO;
class Fixture {
 static int Main(string[] a) {
  File.AppendAllText(Environment.GetEnvironmentVariable("MUMU_FIXTURE_LOG"),String.Join(" ",a)+"\n");
  if(a.Length==3 && a[0]=="info" && a[1]=="-v") {
   if(a[2]=="all") {Console.WriteLine("{\"3\":{\"index\":3,\"name\":\"fixture A\",\"is_android_started\":true,\"android_version\":\"15.0\"},\"7\":{\"index\":7,\"name\":\"fixture B\",\"is_android_started\":false,\"android_version\":\"15.0\"}}");return 0;}
   if(a[2]=="3" && Environment.GetEnvironmentVariable("MUMU_FIXTURE_REMOVED")!="1") {Console.WriteLine("{\"index\":3,\"is_android_started\":true,\"android_version\":\"15.0\"}");return 0;}
   Console.WriteLine("{\"errcode\":-200,\"errmsg\":\"player index not found\",\"info_source\":\"rpc\"}");return -200;
  }
  Console.Error.WriteLine("Fixture forbids native settings access");return 98;
 }
}
'@
    $src=Join-Path $WorkDirectory 'Fixture.cs';[IO.File]::WriteAllText($src,$code)
    $csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not(Test-Path -LiteralPath $csc)) {$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
    & $csc /nologo /target:exe ('/out:'+(Join-Path $nx 'MuMuManager.exe')) $src
    if ($LASTEXITCODE -ne 0) {throw 'Fixture compilation failed'}
    $ps=(Get-Process -Id $PID).Path
    $common='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Backend.ps1')+'" -InstallPath "'+(Split-Path $nx -Parent)+'" -AsJson'
    $r=Invoke-Child $ps ($common+' -Action List')
    $j=$r.Stdout|ConvertFrom-Json
    Assert ($r.Exit -eq 0 -and $j.Instances.Count -eq 2 -and $j.Instances[0].Index -eq '3' -and $j.Instances[1].Index -eq '7' -and -not $j.Written) 'Actual List entry point failed'
    $r=Invoke-Child $ps ($common+' -Action Enable -VmIndex 0')
    Assert ($r.Exit -eq 1 -and $r.Stderr -match '3, 7') 'Missing zero was not rejected'
    $r=Invoke-Child $ps ($common+' -Action Enable -VmIndex 3') $true
    Assert ($r.Exit -eq 1 -and $r.Stderr -match '-200') 'Removed instance was not rejected'
    $calls=[IO.File]::ReadAllText((Join-Path $WorkDirectory 'fixture-calls.log'))
    Assert ($calls -notmatch '(?m)^sh ' -and $calls -notmatch 'setprop|adb|control') 'Fixture unexpectedly reached native settings access'
    Write-Output 'SMOKE_CHECKS=4 PASS=4 FAIL=0 (compiled EXE/UI binding, List entry point, missing zero, removed selection; fixture only)'
} finally {
    [IO.File]::WriteAllText((Join-Path $WorkDirectory 'commands.json'),($records.ToArray()|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
}
