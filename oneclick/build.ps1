param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not(Test-Path -LiteralPath $compiler)) {$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
if (-not(Test-Path -LiteralPath $compiler)) {throw '.NET Framework C# compiler was not found.'}
$framework=Split-Path $compiler -Parent
[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$backend=Join-Path $PSScriptRoot 'Backend.ps1'
$hash=(Get-FileHash -LiteralPath $backend -Algorithm SHA256).Hash.ToLowerInvariant()
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Launcher.cs')).Replace('__BACKEND_HASH__',$hash)
$generated=Join-Path $OutputDirectory 'Launcher.generated.cs'
[IO.File]::WriteAllText($generated,$source,[Text.UTF8Encoding]::new($false))
$exe=Join-Path $OutputDirectory 'MuMuLocalQuality.exe'
$args=@('/nologo','/utf8output','/codepage:65001','/target:winexe','/optimize+','/platform:anycpu',
    ('/out:'+$exe),('/win32manifest:'+(Join-Path $PSScriptRoot 'app.manifest')),
    ('/resource:'+$backend+',Backend.ps1'),('/reference:'+(Join-Path $framework 'System.Windows.Forms.dll')),
    ('/reference:'+(Join-Path $framework 'System.Drawing.dll')),('/reference:'+(Join-Path $framework 'System.Web.Extensions.dll')),$generated)
& $compiler @args
if ($LASTEXITCODE -ne 0) {throw 'C# compilation failed.'}
Write-Output ('BUILT='+$exe)
Write-Output ('SHA256='+(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash)
