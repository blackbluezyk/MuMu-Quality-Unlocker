# MuMu Quality Unlocker

[中文文档](README.md) · [Changelog](CHANGELOG.md)

Two deliberately separate tools for Windows PowerShell 5.1 and PowerShell 7:

- `unlock-quality.ps1`: local display resolution, DPI and configured FPS limit, with backups and readback. Add `-Status -AsJson` for read-only diagnostics. For backwards compatibility, running it without arguments still applies 1080p and may restart the instance.
- `picfx-local.ps1`: experimental Naruto (`com.tencent.KiHan`) native picfx initialization control. Defaults to read-only Status. State changes require `-Experimental`; preview with `-Action Enable -DryRun`.

```powershell
.\unlock-quality.ps1 -Status -AsJson
.\unlock-quality.ps1 -Preset 2k -FrameRate 144 -DryRun
.\picfx-local.ps1 -AsJson
.\picfx-local.ps1 -Action Enable -Experimental
.\picfx-local.ps1 -Action Restore -BackupPath '.\backups\ACTUAL_SNAPSHOT.json' -Experimental
.\tests\Run-All.ps1
```

Use `-InstallPath 'D:\MuMuPlayer'` when automatic discovery fails. Display operations can select multiple instances; picfx accepts one numeric instance only.

## Evidence and limitations

On 2026-11-12, the local user confirmed the picture-quality effect on their installation. Separately, native OFF/ON/rollback readback was recorded. This is not an automated image-quality measurement or a cross-device compatibility guarantee. Development used MuMu 6.8.8.0 / Android 15.

The picfx tool uses the native `MuMuManager sh` namespace, not `adb shell getprop`. Its `NativeAfter=on` only confirms initialization readback. `EffectVerification=NotMeasuredByThisScript` is intentional. It does not establish plugin processing, GUI switch state, measured game FPS or membership activation. The recorded vendor config says the feature may use up to 20 GB of generated cache, may stutter initially, and requires a game restart. Disabling may clear that cache. This tool never restarts, updates or signs into a game.

Before each real picfx change, a unique snapshot and SHA256 sidecar are saved. Restore validates the manager path, instance, Android version, package, property and checksum. Snapshots record the pre-write value, not necessarily a pristine installation. Checksums are not signatures; use trusted snapshots only.

Display restore uses the original baseline or the earliest valid legacy backup for the selected instance. A configured FPS cap is not measured FPS; some games render internally at a fixed resolution.

All tests use temporary fixtures. They do not operate an installed emulator. No executables, account/entitlement data or game assets are patched or distributed. Do not publish private logs, credentials, snapshots or generated cache. MIT licensed; not affiliated with NetEase.

The existing [portable one-click helper](oneclick/README.md) and its v0.1.0 download remain unchanged. Its snapshots are not interchangeable with the CLI tool snapshots.
