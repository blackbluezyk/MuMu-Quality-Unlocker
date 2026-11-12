<#
.SYNOPSIS
    MuMu Player Quality Unlocker - raise the local rendering resolution and frame rate
    of MuMu Player (NetEase emulator) instances through the official MuMuManager CLI.

.DESCRIPTION
    Adjust local display settings through the vendor CLI, with backup and readback.
    This is not proof that a game-specific "ultimate graphics" feature is enabled.
    Configured resolution and frame-rate limits are not measured game quality/FPS.

    It does NOT modify any executable, does NOT patch / inject / hook any process, and
    does NOT touch account, membership or entitlement data. Only local display settings.

.PARAMETER Preset
    Ready-made resolution preset: 720p | 1080p | 2k | 4k.

.PARAMETER Width
    Custom width in pixels. Requires -Height and -Dpi. Overrides -Preset.

.PARAMETER Height
    Custom height in pixels.

.PARAMETER Dpi
    Custom display density (dpi).

.PARAMETER FrameRate
    Optional desired frame rate, e.g. 60 / 90 / 120 / 144.

.PARAMETER VmIndex
    Instance index, comma separated list, or 'all'. Default 0.

.PARAMETER InstallPath
    MuMu Player installation root. Auto-detected from the registry when omitted.

.PARAMETER Restore
    Restore the original baseline (or earliest legacy backup) for the selected instances.

.PARAMETER NoRestart
    Write the configuration but do not restart the instance.

.PARAMETER DryRun
    Show what would change without writing anything.

.PARAMETER Status
    Read configured display values and, when running, Android display readback.
    Never writes settings, creates backups, starts or restarts an instance.

.PARAMETER AsJson
    Machine-readable output. Requires -Status.

.EXAMPLE
    .\unlock-quality.ps1

.EXAMPLE
    .\unlock-quality.ps1 -Preset 2k -FrameRate 144

.EXAMPLE
    .\unlock-quality.ps1 -Width 2560 -Height 1440 -Dpi 320

.EXAMPLE
    .\unlock-quality.ps1 -VmIndex all -Preset 1080p

.EXAMPLE
    .\unlock-quality.ps1 -Restore
#>
[CmdletBinding()]
param(
    [ValidateSet('720p', '1080p', '2k', '4k')]
    [string]$Preset = '1080p',

    [int]$Width,
    [int]$Height,
    [int]$Dpi,

    [ValidateRange(15, 480)]
    [int]$FrameRate,

    [string]$VmIndex = '0',
    [string]$InstallPath,

    [switch]$Restore,
    [switch]$NoRestart,
    [switch]$DryRun,
    [switch]$Status,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$script:ManagerPath = $null
$script:Root = $null

# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------
function Write-Step { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn2{ param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[x] $Message" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# installation discovery
# ---------------------------------------------------------------------------
function Find-MuMuInstall {
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $uninstallRoots) {
        $entry = Get-ItemProperty $root -ErrorAction SilentlyContinue |
                 Where-Object {
                     $_.DisplayName -match 'MuMu' -and
                     $_.InstallLocation -and
                     (Test-Path (Join-Path $_.InstallLocation 'nx_main\MuMuManager.exe'))
                 } | Select-Object -First 1
        if ($entry) { return $entry.InstallLocation }
    }

    $candidates = @(
        'C:\Program Files\Netease\MuMuPlayer',
        'C:\Program Files\MuMuPlayer-12.0',
        'D:\Program Files\Netease\MuMuPlayer',
        'D:\MuMuPlayer',
        'E:\MuMuPlayer'
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'nx_main\MuMuManager.exe')) { return $c }
    }
    return $null
}

function Initialize-MuMu {
    param([string]$Path, [switch]$Quiet)

    if (-not $Path) { $Path = Find-MuMuInstall }
    if (-not $Path) {
        throw 'MuMu Player installation not found. Use -InstallPath to point at the install root.'
    }

    $manager = Join-Path $Path 'nx_main\MuMuManager.exe'
    if (-not (Test-Path $manager)) {
        throw "MuMuManager.exe not found under '$Path'."
    }

    $script:Root = (Resolve-Path $Path).Path
    $script:ManagerPath = (Resolve-Path $manager).Path
    if (-not $Quiet) {
        Write-Ok "Install root : $($script:Root)"
        Write-Ok "Manager CLI  : $($script:ManagerPath)"
    }
}

# ---------------------------------------------------------------------------
# CLI wrapper
# ---------------------------------------------------------------------------
function Invoke-Manager {
    param([string[]]$CliArgs, [switch]$RawText)

    $raw = & $script:ManagerPath @CliArgs 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "MuMuManager exited with code ${exitCode}: $($raw.Trim())" }
    $trimmed = $raw.Trim()
    if (-not $trimmed) { return $null }
    try { $response = $trimmed | ConvertFrom-Json -ErrorAction Stop }
    catch { $response = $trimmed }
    Assert-ManagerResponse -Response $response
    if ($RawText) { return $trimmed }
    return $response
}

function Assert-ManagerResponse {
    param($Response)
    if ($null -ne $Response -and $Response.PSObject.Properties['error_code'] -and
        $Response.error_code -ne 0) {
        throw "MuMuManager error $($Response.error_code): $($Response | ConvertTo-Json -Compress)"
    }
    if ($Response -is [string] -and $Response -match '\b(error|failed|failure)\b') {
        throw "MuMuManager failed: $Response"
    }
}

function Get-InstanceList {
    # The vendor supports info -v all and returns an index-keyed JSON object.
    $listing = Invoke-Manager @('info', '-v', 'all')
    if ($null -eq $listing -or $listing -is [string] -or $listing -is [array]) {
        throw 'Invalid instance list returned by MuMuManager info -v all.'
    }
    $result = @()
    foreach ($entry in $listing.PSObject.Properties) {
        if ($entry.Name -notmatch '^(0|[1-9][0-9]*)$') {
            throw "Invalid instance index in CLI response: $($entry.Name)"
        }
        $info = $entry.Value
        if ($null -eq $info -or $info -is [string]) { throw "Invalid info for instance $($entry.Name)." }
        Assert-ManagerResponse -Response $info
        if ($info.PSObject.Properties['index'] -and [string]$info.index -ne $entry.Name) {
            throw "Inconsistent instance index: $($entry.Name) / $($info.index)"
        }
        $result += [pscustomobject]@{
            Index = $entry.Name
            Name  = $info.name
            State = $info.player_state
            Running = [bool]$info.is_android_started
            AndroidVersion = [string]$info.android_version
        }
    }
    return $result | Sort-Object { [int]$_.Index }
}

function Resolve-TargetIndexes {
    param([string]$Selector)

    $instances = @(Get-InstanceList)
    if ($instances.Count -eq 0) { throw 'No MuMu instances found.' }

    if ($Selector -eq 'all') { return $instances }

    $requested = @($Selector.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($requested.Count -eq 0) { throw 'Select at least one instance.' }
    $resolved = @()
    foreach ($r in $requested) {
        $match = $instances | Where-Object { $_.Index -eq $r }
        if (-not $match) { throw "Instance index '$r' does not exist. Available: $($instances.Index -join ', ')" }
        $resolved += $match
    }
    return $resolved
}

# ---------------------------------------------------------------------------
# presets
# ---------------------------------------------------------------------------
function Get-PresetTable {
    return @{
        '720p'  = @{ Width = 1280; Height = 720;  Dpi = 160 }
        '1080p' = @{ Width = 1920; Height = 1080; Dpi = 280 }
        '2k'    = @{ Width = 2560; Height = 1440; Dpi = 320 }
        '4k'    = @{ Width = 3840; Height = 2160; Dpi = 480 }
    }
}

function Resolve-Resolution {
    if ($Width -or $Height -or $Dpi) {
        if (-not ($Width -and $Height -and $Dpi)) {
            throw 'Custom resolution needs -Width, -Height and -Dpi together.'
        }
        if ($Width -lt 320 -or $Height -lt 240) { throw 'Resolution must be at least 320x240.' }
        if ($Dpi -lt 72 -or $Dpi -gt 640) { throw 'Dpi must be between 72 and 640.' }
        return @{ Width = $Width; Height = $Height; Dpi = $Dpi }
    }
    $table = Get-PresetTable
    return $table[$Preset]
}

function Get-DisplayStatus {
    param([string]$Index, [bool]$Running)
    $values = Invoke-Manager @('setting', '-v', $Index,
        '--key', 'resolution_mode', '--key', 'resolution_width.custom',
        '--key', 'resolution_height.custom', '--key', 'resolution_dpi.custom', '--key', 'max_frame_rate')
    if ($null -eq $values -or $values -is [string]) { throw 'Invalid display settings response.' }
    $parsed = @{}
    foreach ($key in @('resolution_width.custom', 'resolution_height.custom', 'resolution_dpi.custom', 'max_frame_rate')) {
        $number = [double]0
        if (-not [double]::TryParse([string]$values.$key, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or
            [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -le 0) {
            throw "Invalid or missing display field: $key"
        }
        $parsed[$key] = $number
    }
    $runtime = $null; $runtimeError = $null; $matches = $false
    if ($Running) {
        try {
            $size = [string](Invoke-Manager @('adb', '-v', $Index, '-c', 'shell wm size'))
            $density = [string](Invoke-Manager @('adb', '-v', $Index, '-c', 'shell wm density'))
            $sizes = [regex]::Matches($size, '(?:Physical|Override) size:\s*(\d+)x(\d+)')
            $densities = [regex]::Matches($density, '(?:Physical|Override) density:\s*(\d+)')
            if (-not $sizes.Count -or -not $densities.Count) { throw 'Unrecognized Android display readback.' }
            $s = $sizes[$sizes.Count - 1]; $d = $densities[$densities.Count - 1]
            $rw = [int]$s.Groups[1].Value; $rh = [int]$s.Groups[2].Value; $rd = [int]$d.Groups[1].Value
            $runtime = [pscustomobject]@{ Width=$rw; Height=$rh; Dpi=$rd }
            $cw=$parsed['resolution_width.custom']; $ch=$parsed['resolution_height.custom']
            $matches = ((($rw -eq $cw -and $rh -eq $ch) -or ($rw -eq $ch -and $rh -eq $cw)) -and $rd -eq $parsed['resolution_dpi.custom'])
        } catch { $runtimeError = $_.Exception.Message }
    }
    [pscustomobject]@{
        InstanceIndex=$Index; Running=$Running; ConfiguredMode=[string]$values.resolution_mode
        ConfiguredWidth=$parsed['resolution_width.custom']; ConfiguredHeight=$parsed['resolution_height.custom']
        ConfiguredDpi=$parsed['resolution_dpi.custom']; ConfiguredFpsLimit=$parsed['max_frame_rate']
        AndroidDisplay=$runtime; RuntimeMatchesConfiguredDisplay=$matches; RuntimeReadbackError=$runtimeError
        ActualGameFps=$null; GameGraphicsPreset=$null; GameSpecificEffectVerified=$false
    }
}

# ---------------------------------------------------------------------------
# backup / restore
# ---------------------------------------------------------------------------
function Get-ConfigFile {
    param(
        [ValidatePattern('^(0|[1-9][0-9]*)$')][string]$InstanceIndex,
        [string]$AndroidVersion
    )
    $pattern = Join-Path $script:Root "vms\MuMuPlayer-*\configs\customer_config.json"
    $files = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Where-Object {
        if ($AndroidVersion) {
            $_.Directory.Parent.Name -eq "MuMuPlayer-$AndroidVersion-$InstanceIndex"
        } else {
            $_.Directory.Parent.Name -match ('^MuMuPlayer-(?:.*-)?' + [regex]::Escape($InstanceIndex) + '$')
        }
    })
    if ($files.Count -ne 1) {
        throw "Expected one config for instance $InstanceIndex; found $($files.Count). No files were selected."
    }
    return $files[0]
}

function Copy-ConfigExclusive {
    param([string]$Source, [string]$Destination)
    # Stage, hash-check, then rename without overwrite. Never publish a partial backup.
    $temp = "$Destination.tmp_$([guid]::NewGuid().ToString('N'))"
    $inputStream = $null
    $outputStream = $null
    try {
        $inputStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $outputStream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $inputStream.CopyTo($outputStream)
        $outputStream.Flush()
        $outputStream.Dispose(); $outputStream = $null
        if ((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash) { throw 'Backup hash verification failed.' }
        [IO.File]::Move($temp, $Destination)
    } finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Backup-Config {
    param([string]$FilePath)

    $original = "$FilePath.bak_original"
    if (-not (Test-Path -LiteralPath $original)) {
        $legacy = Get-OriginalBackup -FilePath $FilePath
        $source = if ($legacy) { $legacy.FullName } else { $FilePath }
        Copy-ConfigExclusive -Source $source -Destination $original
    }
    $stamp = [datetime]::UtcNow.ToString('yyyyMMdd_HHmmss_fffffff', [Globalization.CultureInfo]::InvariantCulture)
    $dest = "$FilePath.bak_${stamp}_$([guid]::NewGuid().ToString('N'))"
    Copy-ConfigExclusive -Source $FilePath -Destination $dest
    Write-Ok "Backup: $dest"
    return $dest
}

function Get-OriginalBackup {
    param([string]$FilePath)
    $original = "$FilePath.bak_original"
    if (Test-Path -LiteralPath $original -PathType Leaf) { return Get-Item -LiteralPath $original }
    $dir = Split-Path $FilePath -Parent
    $leaf = Split-Path $FilePath -Leaf
    return Get-ChildItem -LiteralPath $dir -Filter "$leaf.bak_*" -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name.Substring(($leaf + '.bak_').Length) -match '^\d{8}_\d{6}(?:_\d{7}_[a-f0-9]{32})?$' } |
           Sort-Object Name | Select-Object -First 1
}

# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
function Set-InstanceResolution {
    param(
        [string]$Index,
        [int]$W,
        [int]$H,
        [int]$D,
        [int]$Rate
    )

    $culture = [Globalization.CultureInfo]::InvariantCulture
    $wVal = $W.ToString('F6', $culture)
    $hVal = $H.ToString('F6', $culture)
    $dVal = $D.ToString('F6', $culture)

    $argList = @(
        'setting', '-v', $Index,
        '--key', 'resolution_width.custom',  '--value', $wVal,
        '--key', 'resolution_height.custom', '--value', $hVal,
        '--key', 'resolution_dpi.custom',    '--value', $dVal
    )
    if ($Rate) {
        $argList += @('--key', 'max_frame_rate', '--value', "$Rate")
    }

    if ($DryRun) {
        Write-Host "    [dry] $($script:ManagerPath) setting -v $Index --key resolution_mode --value custom.0" -ForegroundColor DarkGray
        Write-Host "    [dry] $($script:ManagerPath) $($argList -join ' ')" -ForegroundColor DarkGray
        return $true
    }

    $before = Invoke-Manager @('setting', '-v', $Index, '--key', 'resolution_mode', '--value', 'custom.0')
    Assert-ManagerResponse -Response $before

    $applied = Invoke-Manager $argList
    Assert-ManagerResponse -Response $applied

    $verify = Invoke-Manager @(
        'setting', '-v', $Index,
        '--key', 'resolution_mode',
        '--key', 'resolution_width.custom',
        '--key', 'resolution_height.custom',
        '--key', 'resolution_dpi.custom',
        '--key', 'max_frame_rate'
    )

    Assert-ManagerResponse -Response $verify
    if ($null -eq $verify -or $verify -is [string] -or
        $verify.resolution_mode -notin @('custom', 'custom.0')) {
        throw "Could not verify custom resolution mode for instance $Index."
    }
    $expected = @{'resolution_width.custom' = $W; 'resolution_height.custom' = $H; 'resolution_dpi.custom' = $D}
    if ($Rate) { $expected['max_frame_rate'] = $Rate }
    foreach ($key in $expected.Keys) {
        $value = [double]0
        if (-not [double]::TryParse([string]$verify.$key, [Globalization.NumberStyles]::Float, $culture, [ref]$value) -or
            $value -ne $expected[$key]) {
            throw "Verification failed for instance ${Index}: $key expected $($expected[$key]), got '$($verify.$key)'."
        }
    }
    if ($verify) {
        $msg = 'Instance {0} -> mode={1} size={2}x{3} dpi={4} fps={5}' -f `
            $Index,
            $verify.resolution_mode,
            $verify.'resolution_width.custom',
            $verify.'resolution_height.custom',
            $verify.'resolution_dpi.custom',
            $verify.max_frame_rate
        Write-Ok $msg
        return $true
    }

    throw "Could not verify settings for instance $Index."
}

function Restart-Instance {
    param([string]$Index)

    if ($DryRun) {
        Write-Host "    [dry] restart instance $Index" -ForegroundColor DarkGray
        return
    }
    Write-Step "Restarting instance $Index ..."
    Invoke-Manager @('control', '-v', $Index, 'restart') | Out-Null

    for ($n = 0; $n -lt 40; $n++) {
        Start-Sleep -Seconds 4
        $info = Invoke-Manager @('info', '-v', $Index)
        if ($info -and $info -isnot [string] -and $info.is_android_started -eq $true) {
            Write-Ok "Instance $Index is up ($($info.player_state))"
            return
        }
    }
    throw "Instance $Index did not report ready in ~160s; check it manually."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
# Loading helpers must not implicitly apply the default display preset.
if ($MyInvocation.InvocationName -eq '.') { return }
try {
    if ($AsJson -and -not $Status) { throw '-AsJson requires -Status.' }
    if ($Status) {
        if ($Restore -or $Width -or $Height -or $Dpi -or $FrameRate -or $PSBoundParameters.ContainsKey('Preset')) {
            throw '-Status cannot be combined with display changes or -Restore.'
        }
        Initialize-MuMu -Path $InstallPath -Quiet
        $rows = @(foreach ($t in @(Resolve-TargetIndexes -Selector $VmIndex)) {
            Get-DisplayStatus -Index $t.Index -Running $t.Running
        })
        if ($AsJson) { ConvertTo-Json -InputObject $rows -Depth 6 }
        else {
            $rows | Format-List
            Write-Warn2 'Read-only status. A frame-rate limit is not measured FPS; game-specific graphics effects are not verified.'
        }
        return
    }
    Write-Host ''
    Write-Host '  MuMu Quality Unlocker' -ForegroundColor White
    Write-Host '  local rendering settings via official MuMuManager CLI' -ForegroundColor DarkGray
    Write-Host ''

    Initialize-MuMu -Path $InstallPath

    $targets = @(Resolve-TargetIndexes -Selector $VmIndex)
    Write-Step "Target instances: $($targets.Index -join ', ')"

    if ($Restore) {
        $restorePlan = @()
        foreach ($t in $targets) {
            $cfg = Get-ConfigFile -InstanceIndex $t.Index -AndroidVersion $t.AndroidVersion
            $bak = Get-OriginalBackup -FilePath $cfg.FullName
            if (-not $bak) { throw "No backup for instance $($t.Index): $($cfg.FullName)" }
            $restorePlan += [pscustomobject]@{Config=$cfg; Backup=$bak}
        }
        foreach ($item in $restorePlan) {
            if ($DryRun) {
                Write-Host "    [dry] restore $($item.Backup.FullName) -> $($item.Config.FullName)" -ForegroundColor DarkGray
            } else {
                Copy-Item -LiteralPath $item.Backup.FullName -Destination $item.Config.FullName -Force
                if ((Get-FileHash -LiteralPath $item.Backup.FullName -Algorithm SHA256).Hash -ne
                    (Get-FileHash -LiteralPath $item.Config.FullName -Algorithm SHA256).Hash) { throw 'Restore hash verification failed.' }
                Write-Ok "Restored $($item.Config.FullName) from $($item.Backup.Name)"
            }
        }
        Write-Host ''
        Write-Warn2 'Backup restored. Restart the instance for it to take effect.'
        if (-not $NoRestart -and -not $DryRun) {
            foreach ($t in $targets) { Restart-Instance -Index $t.Index }
        }
        return
    }

    $res = Resolve-Resolution
    Write-Step "Target resolution: $($res.Width)x$($res.Height) @ $($res.Dpi)dpi"
    if ($FrameRate) { Write-Step "Target frame rate: $FrameRate" }

    foreach ($t in $targets) {
        $cfg = Get-ConfigFile -InstanceIndex $t.Index -AndroidVersion $t.AndroidVersion
        if (-not $DryRun) {
            Backup-Config -FilePath $cfg.FullName | Out-Null
        }
        if (-not (Set-InstanceResolution -Index $t.Index -W $res.Width -H $res.Height -D $res.Dpi -Rate $FrameRate)) {
            throw "Failed to apply settings to instance $($t.Index)."
        }
    }

    if (-not $NoRestart -and -not $DryRun) {
        foreach ($t in $targets) { Restart-Instance -Index $t.Index }
    }

    Write-Host ''
    if ($DryRun) {
        Write-Ok 'Dry run complete. Nothing was written.'
    } else {
        Write-Ok 'Done.'
        Write-Host '    Verify inside Android:  adb shell wm size' -ForegroundColor DarkGray
        Write-Host '    Roll back with       :  .\unlock-quality.ps1 -Restore' -ForegroundColor DarkGray
    }
    Write-Host ''
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
