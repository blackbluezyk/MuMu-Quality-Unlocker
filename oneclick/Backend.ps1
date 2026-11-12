[CmdletBinding()]
param(
    [ValidateSet('Status','Enable','Disable','Restore')][string]$Action='Status',
    [ValidatePattern('^(0|[1-9][0-9]*)$')][string]$VmIndex='0',
    [string]$InstallPath,
    [string]$BackupDirectory=(Join-Path $env:LOCALAPPDATA 'MuMuLocalQuality\backups'),
    [string]$BackupPath,
    [switch]$AsJson
)
$ErrorActionPreference='Stop'
$OutputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=$OutputEncoding
$script:Property='nemud.tool.com.tencent.KiHan.picfx'
$script:Package='com.tencent.KiHan'

function Find-Manager([string]$Root) {
    if ($Root) {
        $p=Join-Path $Root 'nx_main\MuMuManager.exe'
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'MuMuManager.exe was not found under the selected install folder.' }
        return (Resolve-Path -LiteralPath $p).Path
    }
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -match 'MuMu' -and $_.InstallLocation})) {
            $p=Join-Path $entry.InstallLocation 'nx_main\MuMuManager.exe'
            if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path }
        }
    }
    foreach ($root in @('E:\MuMuPlayer','D:\MuMuPlayer','C:\Program Files\Netease\MuMuPlayer','C:\Program Files\MuMuPlayer-12.0')) {
        $p=Join-Path $root 'nx_main\MuMuManager.exe'
        if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path }
    }
    throw 'MuMu was not found. Select its install folder; this package does not install MuMu.'
}

function Invoke-MuMu([string[]]$Arguments) {
    $text=(& $script:Manager @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "MuMuManager exit ${LASTEXITCODE}: $text" }
    $parsed=$null
    try { $parsed=$text|ConvertFrom-Json -ErrorAction Stop } catch {}
    if ($parsed -and $parsed.PSObject.Properties['error_code'] -and $parsed.error_code -ne 0) { throw "MuMuManager error: $text" }
    if ($text -match '\b(error|failed|failure)\b') { throw "MuMuManager rejected operation: $text" }
    return $text
}

function Assert-Value([AllowEmptyString()][string]$Value) {
    if ($Value -cnotin @('','on','off')) { throw 'Unrecognized native picfx value. No value will be guessed.' }
}

function Read-NativeValue([string]$Index) {
    # This key belongs to the native sh namespace, NOT adb shell getprop.
    $v=[string](Invoke-MuMu @('sh','-v',$Index,'-c',('getprop '+$script:Property)))
    $v=$v.Trim(); Assert-Value $v; return $v
}

function Write-NativeValue([string]$Index,[AllowEmptyString()][string]$Value) {
    Assert-Value $Value
    $argument=if ($Value -eq '') { "''" } else { $Value }
    Invoke-MuMu @('sh','-v',$Index,'-c',('setprop '+$script:Property+' '+$argument))|Out-Null
    $after=Read-NativeValue $Index
    if ($after -cne $Value) { throw 'Write/readback mismatch. The backup remains available; this is not success.' }
    return $after
}

function Save-Snapshot([string]$Directory,[string]$Index,[string]$Android,[AllowEmptyString()][string]$Value) {
    Assert-Value $Value
    [IO.Directory]::CreateDirectory($Directory)|Out-Null
    $snapshot=[ordered]@{Schema=1;Manager=$script:Manager;Index=$Index;Android=$Android;Package=$script:Package;Property=$script:Property;Value=$Value;Utc=[datetime]::UtcNow.ToString('o')}
    $p=Join-Path $Directory ('picfx-'+$Index+'-'+[datetime]::UtcNow.ToString('yyyyMMdd_HHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.json')
    $temp=$p+'.tmp';$stream=$null
    try {
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($snapshot|ConvertTo-Json))
        $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush();$stream.Dispose();$stream=$null
        [IO.File]::Move($temp,$p)
        $hash=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
        $bytes=[Text.Encoding]::ASCII.GetBytes($hash)
        $stream=[IO.File]::Open(($p+'.sha256'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush();$stream.Dispose();$stream=$null
        return $p
    } finally {
        if ($stream) {$stream.Dispose()}
        if ([IO.File]::Exists($temp)) {[IO.File]::Delete($temp)}
    }
}

function Read-Snapshot([string]$Path,[string]$Index,[string]$Android) {
    if (-not $Path -or -not(Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Choose a backup JSON created by this application.' }
    if ((Get-Item -LiteralPath $Path).Length -gt 1048576) {throw 'Backup exceeds size limit.'}
    $sidecar=$Path+'.sha256'
    if (-not(Test-Path -LiteralPath $sidecar -PathType Leaf)) {throw 'Missing backup checksum file.'}
    $hash=[IO.File]::ReadAllText($sidecar).Trim()
    if ($hash -notmatch '^[A-Fa-f0-9]{64}$' -or $hash -ne (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash) {throw 'Backup checksum mismatch.'}
    $s=[IO.File]::ReadAllText($Path)|ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $s -or $s -is [array] -or $s.Schema -ne 1 -or
        $s.Index -cne $Index -or $s.Android -cne $Android -or $s.Package -cne $script:Package -or
        $s.Property -cne $script:Property -or -not $s.PSObject.Properties['Value'] -or
        $null -eq $s.Value -or $s.Value -isnot [string] -or
        -not [string]::Equals([string]$s.Manager,$script:Manager,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backup does not match this install, instance, engine and property.'
    }
    Assert-Value $s.Value; return $s
}

function Run-Action([string]$Operation,[string]$Index,[string]$Directory,[string]$RestorePath) {
    if ($Index -notmatch '^(0|[1-9][0-9]*)$') {throw 'Invalid instance index.'}
    $infoText=Invoke-MuMu @('info','-v',$Index)
    $info=$infoText|ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $info -or [string]$info.index -cne $Index -or -not $info.PSObject.Properties['is_android_started']) {throw 'Instance identity/readiness could not be confirmed.'}
    $running=($info.is_android_started -eq $true)
    $before=$null;$after=$null;$desired=$null;$saved=$null;$written=$false
    if ($running) {$before=Read-NativeValue $Index;$after=$before}
    elseif ($Operation -ne 'Status') {throw 'Start the selected MuMu instance first. No auto-start or restart was performed.'}
    switch ($Operation) {
        'Status' {}
        'Enable' {$desired='on'}
        'Disable' {$desired='off'}
        'Restore' {$desired=(Read-Snapshot $RestorePath $Index ([string]$info.android_version)).Value}
        default {throw 'Unsupported action.'}
    }
    if ($Operation -ne 'Status' -and $before -cne $desired) {
        $saved=Save-Snapshot $Directory $Index ([string]$info.android_version) $before
        Read-Snapshot $saved $Index ([string]$info.android_version)|Out-Null
        $after=Write-NativeValue $Index $desired;$written=$true
    }
    [pscustomobject]@{Action=$Operation;Instance=$Index;Running=$running;NativeBefore=$before;NativeAfter=$after;Written=$written;BackupPath=$saved;TextureEffectAutomaticallyVerified=$false;GuiSwitchVerified=$false;Manager=$script:Manager;RestartGameManually=$written}
}

if ($MyInvocation.InvocationName -eq '.') {return}
try {
    $script:Manager=Find-Manager $InstallPath
    $answer=Run-Action $Action $VmIndex $BackupDirectory $BackupPath
    if ($AsJson) {$answer|ConvertTo-Json -Depth 4} else {$answer|Format-List}
} catch {[Console]::Error.WriteLine($_.Exception.Message);exit 1}
