<#
.SYNOPSIS
    Experimental local Naruto picfx initialization control; default is read-only Status.
.DESCRIPTION
    Uses the native MuMuManager sh namespace, NOT adb shell getprop.
    Only the recorded com.tencent.KiHan picfx init property is supported.
    An on readback is NOT proof of plugin execution, HD-cache creation, GUI state,
    improved textures or membership activation. No executable or account patching.
    No game/instance restart, update installation, or login is automated.
#>
[CmdletBinding()]
param(
    [ValidateSet('Status','Enable','Disable','Restore')][string]$Action='Status',
    [ValidatePattern('^(0|[1-9][0-9]*)$')][string]$VmIndex='0',
    [string]$InstallPath,
    [switch]$Experimental,
    [switch]$DryRun,
    [string]$BackupPath,
    [string]$BackupDirectory=(Join-Path $PSScriptRoot 'backups'),
    [switch]$AsJson
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'unlock-quality.ps1') -InstallPath $InstallPath -VmIndex $VmIndex -DryRun:$DryRun -AsJson:$AsJson
$script:PicFxPackage='com.tencent.KiHan'
$script:PicFxKey='nemud.tool.com.tencent.KiHan.picfx'

function Assert-PicFxValue {
    param([AllowEmptyString()][string]$Value)
    if ($Value -cnotin @('','on','off')) { throw "Unrecognized native picfx value: '$Value'. Nothing will be changed." }
}

function Get-NativePicFxValue {
    param([string]$Index)
    $value = Invoke-Manager -CliArgs @('sh','-v',$Index,'-c',('getprop '+$script:PicFxKey)) -RawText
    if ($null -eq $value) { return '' }
    if ($value -isnot [string]) { throw 'Native picfx readback was not text.' }
    $value=$value.Trim()
    Assert-PicFxValue -Value $value
    return $value
}

function Set-NativePicFxValue {
    param([string]$Index,[AllowEmptyString()][string]$Value)
    Assert-PicFxValue -Value $Value
    $arg=if ($Value -eq '') { "''" } else { $Value }
    Invoke-Manager @('sh','-v',$Index,'-c',('setprop '+$script:PicFxKey+' '+$arg)) | Out-Null
    $readback=Get-NativePicFxValue -Index $Index
    if ($readback -cne $Value) { throw "Native initialization readback mismatch. Expected '$Value', got '$readback'. Use the saved snapshot if restoration is needed." }
    return $readback
}

function Save-PicFxSnapshot {
    param([string]$Directory,[string]$Index,[string]$AndroidVersion,[AllowEmptyString()][string]$Value)
    Assert-PicFxValue -Value $Value
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $snapshot=[ordered]@{
        SchemaVersion=1; InstanceIndex=$Index; AndroidVersion=$AndroidVersion
        GamePackage=$script:PicFxPackage; PropertyName=$script:PicFxKey; NativeValue=$Value
        ManagerPath=$script:ManagerPath; ObservedAtUtc=[datetime]::UtcNow.ToString('o')
        Scope='Pre-write native init property, not a pristine installation or proven graphics effect.'
    }
    $stamp=[datetime]::UtcNow.ToString('yyyyMMdd_HHmmss_fffffff',[Globalization.CultureInfo]::InvariantCulture)
    $name='picfx-'+$Index+'-'+$stamp+'-'+[guid]::NewGuid().ToString('N')+'.json'
    $path=Join-Path $Directory $name
    $temp=$path+'.tmp'
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($snapshot|ConvertTo-Json -Depth 4))
    $stream=$null
    try {
        $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length); $stream.Flush(); $stream.Dispose(); $stream=$null
        [IO.File]::Move($temp,$path)
        $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $hashBytes=[Text.Encoding]::ASCII.GetBytes($hash)
        $stream=[IO.File]::Open(($path+'.sha256'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($hashBytes,0,$hashBytes.Length); $stream.Flush(); $stream.Dispose(); $stream=$null
        return (Resolve-Path -LiteralPath $path).Path
    } finally {
        if ($stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Read-PicFxSnapshot {
    param([string]$Path,[string]$Index,[string]$AndroidVersion)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Provide an existing -BackupPath.' }
    if ((Get-Item -LiteralPath $Path).Length -gt 1048576) { throw 'Snapshot exceeds the size limit.' }
    $sidecar=$Path+'.sha256'
    if (-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) { throw 'Missing snapshot SHA256 sidecar.' }
    $expected=[IO.File]::ReadAllText($sidecar).Trim()
    if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or $expected -ne (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash) {
        throw 'Snapshot checksum mismatch.'
    }
    $s=[IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $s -or $s -is [array] -or $s -is [string] -or
        -not $s.PSObject.Properties['NativeValue'] -or $null -eq $s.NativeValue -or $s.NativeValue -isnot [string] -or
        $s.SchemaVersion -ne 1 -or [string]$s.InstanceIndex -cne $Index -or [string]$s.AndroidVersion -cne $AndroidVersion -or
        $s.GamePackage -cne $script:PicFxPackage -or $s.PropertyName -cne $script:PicFxKey -or
        -not [string]::Equals([string]$s.ManagerPath,$script:ManagerPath,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Snapshot identity does not match this manager, instance, Android version, package and property.'
    }
    Assert-PicFxValue -Value $s.NativeValue
    return $s
}

# Safe helper import for fixture tests and downstream tooling.
if ($MyInvocation.InvocationName -eq '.') { return }
try {
    if ($Action -ne 'Status' -and -not $DryRun -and -not $Experimental) {
        throw 'State changes require -Experimental. Use -DryRun to preview without writes.'
    }
    if ($Action -ne 'Restore' -and $BackupPath) { throw '-BackupPath is only valid with -Action Restore.' }
    Initialize-MuMu -Path $InstallPath -Quiet
    $targets=@(Resolve-TargetIndexes -Selector $VmIndex)
    if ($targets.Count -ne 1) { throw 'Select exactly one instance.' }
    $target=$targets[0]
    $before=$null; $after=$null; $desired=$null; $snapshotPath=$null; $written=$false
    if ($target.Running) {
        $before=Get-NativePicFxValue -Index $VmIndex
        $after=$before
    } elseif ($Action -ne 'Status') { throw 'The selected instance is stopped. Start it yourself before a state change.' }
    if ($Action -eq 'Restore') {
        $saved=Read-PicFxSnapshot -Path $BackupPath -Index $VmIndex -AndroidVersion $target.AndroidVersion
        $desired=$saved.NativeValue
    } elseif ($Action -eq 'Enable') { $desired='on' }
    elseif ($Action -eq 'Disable') { $desired='off' }
    if ($Action -ne 'Status' -and -not $DryRun -and $before -cne $desired) {
        $snapshotPath=Save-PicFxSnapshot -Directory $BackupDirectory -Index $VmIndex -AndroidVersion $target.AndroidVersion -Value $before
        # No CLI write is permitted until a valid, readable snapshot exists.
        Read-PicFxSnapshot -Path $snapshotPath -Index $VmIndex -AndroidVersion $target.AndroidVersion | Out-Null
        $after=Set-NativePicFxValue -Index $VmIndex -Value $desired
        $written=$true
    }
    $result=[pscustomobject]@{
        Feature='Experimental Naruto picfx initialization'; GamePackage=$script:PicFxPackage
        InstanceIndex=$VmIndex; Running=$target.Running; Action=$Action; NativeBefore=$before
        RequestedValue=$desired; NativeAfter=$after; Written=$written; DryRun=[bool]$DryRun
        SnapshotPath=$snapshotPath; NativeReadbackAvailable=[bool]$target.Running
        EffectVerification='NotMeasuredByThisScript'; GuiSwitchVerified=$false; MembershipChecked=$false
        GameRestartRequired=($written -and -not $DryRun)
        Warning='An on value is only initialization readback. It is not proof of HD textures/plugin activity or a membership benefit. The recorded feature may use up to 20 GB of local cache; disabling may clear it. No restart, login or update was automated.'
    }
    if ($AsJson) { $result | ConvertTo-Json -Depth 5 }
    else { $result | Format-List }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
