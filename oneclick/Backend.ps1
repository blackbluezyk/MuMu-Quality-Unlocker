[CmdletBinding()]
param(
    [ValidateSet('List','Status','Enable','Disable','Restore')][string]$Action='Status',
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

function Resolve-ManagerCandidate([string]$Root) {
    if (-not $Root) {return}
    foreach ($p in @([IO.Path]::Combine($Root,'nx_main\MuMuManager.exe'),[IO.Path]::Combine($Root,'MuMuManager.exe'))) {
        if ((Split-Path (Split-Path $p -Parent) -Leaf) -ieq 'nx_main' -and (Test-Path -LiteralPath $p -PathType Leaf -ErrorAction SilentlyContinue)) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }
}

function Find-Manager([string]$Root) {
    if ($Root) {
        $p=Resolve-ManagerCandidate $Root
        if (-not $p) { throw '所选目录未找到 nx_main\MuMuManager.exe，请选择正在使用的 MuMu 安装目录（也可选择 nx_main）。' }
        return $p
    }
    $candidates=New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -match 'MuMu' -and $_.InstallLocation})) {
            $p=Resolve-ManagerCandidate $entry.InstallLocation
            if ($p) {$candidates.Add($p)}
        }
    }
    foreach ($root in @('E:\MuMuPlayer','D:\MuMuPlayer','C:\Program Files\Netease\MuMuPlayer','C:\Program Files\MuMuPlayer-12.0')) {
        $p=Resolve-ManagerCandidate $root
        if ($p) {$candidates.Add($p)}
    }
    return Select-ManagerCandidate @($candidates.ToArray())
}

function Select-ManagerCandidate([string[]]$Candidates) {
    $unique=@($Candidates | Where-Object {$_} | Sort-Object -Unique)
    if ($unique.Count -gt 1) {throw ('检测到多份 MuMu 安装，不能自动猜选。请点“选择”指定正在使用的安装目录：'+($unique -join '; '))}
    if ($unique.Count -eq 1) {return $unique[0]}
    throw '未找到 MuMu。请点“选择”指定正在使用的安装目录；本工具不会安装模拟器。'
}

function Assert-ManagerReply([string]$Text,[long]$ExitCode) {
    $parsed=$null
    try {$parsed=$Text|ConvertFrom-Json -ErrorAction Stop} catch {}
    $errorCode=$ExitCode
    if ($parsed -and $parsed -isnot [array]) {
        foreach ($field in @('errcode','error_code')) {
            if ($parsed.PSObject.Properties[$field] -and [string]$parsed.$field -ne '0') {$errorCode=-1;break}
        }
    }
    if ($errorCode -ne 0) {
        if ($Text -match 'player index not found' -or $ExitCode -eq -200 -or ($parsed -and [string]$parsed.errcode -eq '-200')) {
            throw ('找不到所选实例（MuMu -200）。请刷新实例列表，重新选择；若列表不符，请选择正在运行的 MuMu 安装目录。原始返回：'+$Text)
        }
        throw "MuMuManager 操作失败（exit $ExitCode）：$Text"
    }
}

function Invoke-MuMu([string[]]$Arguments) {
    $text=(& $script:Manager @Arguments 2>&1 | Out-String).Trim()
    Assert-ManagerReply $text $LASTEXITCODE
    return $text
}

function Assert-InstanceInfo($Info,[string]$Index) {
    if ($null -eq $Info -or $Info -isnot [pscustomobject] -or
        -not $Info.PSObject.Properties['index'] -or [string]$Info.index -cne $Index -or
        -not $Info.PSObject.Properties['is_android_started'] -or $Info.is_android_started -isnot [bool]) {
        throw "实例 $Index 的身份或运行状态无法确认，请刷新列表。"
    }
    Assert-ManagerReply ($Info|ConvertTo-Json -Depth 8 -Compress) 0
}

function Get-Instances {
    $text=Invoke-MuMu @('info','-v','all')
    $listing=$text|ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $listing -or $listing -isnot [pscustomobject] -or $listing -is [ValueType] -or $listing -is [string]) {throw '实例列表格式不受支持；请检查 MuMu 版本与安装目录。'}
    $items=@()
    foreach ($entry in $listing.PSObject.Properties) {
        $number=0
        if ($entry.Name -notmatch '^(0|[1-9][0-9]*)$' -or -not [int]::TryParse($entry.Name,[ref]$number)) {throw '实例列表含无效编号，已停止；不会猜选实例。'}
        $i=$entry.Value
        Assert-InstanceInfo $i $entry.Name
        $name=if ($i.name -is [string] -and $i.name) {$i.name} else {'实例 '+$entry.Name}
        $items += [pscustomobject]@{Index=$entry.Name;Name=$name;Running=$i.is_android_started;AndroidVersion=[string]$i.android_version}
    }
    return $items | Sort-Object {[int]$_.Index}
}

function Get-InstanceCatalog {
    [pscustomobject]@{Action='List';Manager=$script:Manager;Instances=@(Get-Instances);Written=$false}
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
    $available=@(Get-Instances)
    if (-not ($available | Where-Object {$_.Index -ceq $Index})) {
        throw ('实例编号 '+$Index+' 不在当前安装的列表中。请刷新并重新选择；可用编号：'+($available.Index -join ', ')+ '。若列表为空或不符，请核对 MuMu 安装目录。')
    }
    $infoText=Invoke-MuMu @('info','-v',$Index)
    $info=$infoText|ConvertFrom-Json -ErrorAction Stop
    Assert-InstanceInfo $info $Index
    $running=($info.is_android_started -eq $true)
    $before=$null;$after=$null;$desired=$null;$saved=$null;$written=$false
    if ($running) {$before=Read-NativeValue $Index;$after=$before}
    elseif ($Operation -ne 'Status') {throw '所选实例尚未启动，请先手动启动，再刷新列表；未自动启动或重启。'}
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
    $answer=if ($Action -eq 'List') {Get-InstanceCatalog} else {Run-Action $Action $VmIndex $BackupDirectory $BackupPath}
    if ($AsJson) {$answer|ConvertTo-Json -Depth 4} else {$answer|Format-List}
} catch {[Console]::Error.WriteLine($_.Exception.Message);exit 1}
