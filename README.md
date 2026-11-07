# MuMu Quality Unlocker

Raise the rendering resolution and frame rate of **MuMu Player** (NetEase Android emulator) instances — including the presets the GUI marks as membership-only — by writing plain local configuration through the vendor's own command line tool.

No executable patching, no process injection, no memory hooking, no account or entitlement data touched. Only display settings.

---

## Why this works

MuMu Player's GUI gates its higher resolution presets behind a membership ("HD quality" is listed as a premium benefit). But the rendering resolution is a **purely local parameter**. The emulator reads it from `customer_config.json` on boot and hands it straight to the Android framebuffer. No membership check happens on that path.

Evidence from the vendor binary and runtime log:

```
[setting]: current resolution , set value: 1920.000000:1080.000000:280.000000
apply player setting: action=apply_setting,
                     {"resolution_mode":"custom","resolution_width.custom":"1920.000000",...}
```

Immediately after, the client still broadcasts `membershipStatusChanged` with its expired value — and the resolution is **unaffected**. The two subsystems are independent.

`MuMuManager.exe` (shipped with every install) exposes `resolution_mode`, `resolution_width.custom`, `resolution_height.custom`, `resolution_dpi.custom` and `max_frame_rate` as writable keys. This script drives exactly those.

**This is not a membership bypass.** Membership-backed *server-side* benefits (remote control, cloud phone, sync, ad removal) are decided by a backend API and stay out of reach — as they should. What this changes is display quality, which belongs on your machine anyway.

---

## Requirements

- Windows 10 / 11
- MuMu Player 12 / 6.x installed (`MuMuManager.exe` present under `<install>\nx_main\`)
- PowerShell 5.1 (built in) — no external dependencies
- The CLI must support `info -v all` (verified against the installed CLI help and response).

Verified on MuMu Player **6.8.8.0**, Android 15 engine, Windows 11.

---

## Quick start

```powershell
# 1080p, the safe sweet spot
.\unlock-quality.ps1

# 2K at 144 fps
.\unlock-quality.ps1 -Preset 2k -FrameRate 144

# Any resolution you want
.\unlock-quality.ps1 -Width 2560 -Height 1440 -Dpi 320

# Every instance
.\unlock-quality.ps1 -VmIndex all -Preset 1080p

# See what would happen, change nothing
.\unlock-quality.ps1 -Preset 2k -DryRun

# Undo everything
.\unlock-quality.ps1 -Restore
```

If PowerShell refuses to run the file (`AuthorizationManager check failed` / `running scripts is disabled`), launch it like this:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\unlock-quality.ps1
```

---

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Preset` | `720p` `1080p` `2k` `4k` | `1080p` | Ready-made resolution preset |
| `-Width` | int | — | Custom width (needs `-Height` and `-Dpi`) |
| `-Height` | int | — | Custom height |
| `-Dpi` | int | — | Custom display density |
| `-FrameRate` | int | — | Desired frame rate (15–480) |
| `-VmIndex` | string | `0` | Instance index, `0,1,2` or `all` |
| `-InstallPath` | string | auto | MuMu install root |
| `-Restore` | switch | — | Restore the selected instances' original baseline, or earliest named legacy backup |
| `-NoRestart` | switch | — | Write config, skip the restart |
| `-DryRun` | switch | — | Print commands, write nothing |

Presets:

| Preset | Resolution | Dpi |
|---|---|---|
| `720p` | 1280 × 720 | 160 |
| `1080p` | 1920 × 1080 | 280 |
| `2k` | 2560 × 1440 | 320 |
| `4k` | 3840 × 2160 | 480 |

---

## How to verify it took effect

```powershell
adb connect 127.0.0.1:16384
adb -s 127.0.0.1:16384 shell wm size
adb -s 127.0.0.1:16384 shell wm density
```

`adb.exe` ships with MuMu at `<install>\nx_main\adb.exe`. The ADB port differs per instance — check with:

```powershell
MuMuManager.exe info -v 0
```

Resolution values only apply after the instance restarts. The script restarts it for you unless you pass `-NoRestart`.

---

## Rollback

Before the first write, the script creates `customer_config.json.bak_original` next to the selected instance's config. This baseline is created without overwrite and is never replaced by subsequent runs. If legacy timestamped backups exist, the earliest filename is preserved as the baseline instead of treating an already-modified current config as pristine.

Every apply also creates a separate `customer_config.json.bak_<UTC timestamp>_<GUID>` snapshot. Backups are staged, SHA256-checked, and published without overwrite. Repeated runs in the same second cannot replace one another's snapshots. Previously overwritten or damaged legacy backups cannot be recovered by this repair.

`-Restore` restores **only the selected instances**, preferring the original baseline. Legacy backups are ordered by timestamp in their names, not their mutable filesystem modification time. Missing or ambiguous config mappings and missing backups are errors, not success messages:

```
<install>\vms\MuMuPlayer-<Android version>-<index>\configs\customer_config.json.bak_original
<install>\vms\MuMuPlayer-<Android version>-<index>\configs\customer_config.json.bak_YYYYMMDD_HHMMSS_fffffff_<GUID>
```

You can also copy any of those files back by hand and restart the instance.

The script now rejects nonzero CLI exit codes and JSON errors, checks that the returned mode, resolution, DPI, and requested frame rate match, and exits nonzero on failure. `info -v all` enumerates sparse instance indexes without stopping at the first gap. Numeric arguments use invariant-culture decimal formatting. A restart readiness timeout is also an error.

## Repair regression tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Regression.ps1
```

The regression suite imports the script's function bodies and exercises main branches in child processes with fixture-only installation discovery and CLI responses. It does not write to or restart an installed MuMu instance. Results and literal child-process output are written to the reported temporary test directory. A failing check produces a nonzero exit code.

The repair was checked with Windows PowerShell 5.1 and PowerShell 7, plus a read-only `-DryRun -NoRestart` against the installed CLI. These tests do not establish actual Android rendering quality, game FPS, membership status, or compatibility with every MuMu release.

---

## Caveats

- Very high resolutions cost real GPU time. 4K on an emulator usually looks worse than 1080p because of upscaled UI assets and text; 1080p is the practical sweet spot.
- Some games render their own fixed-resolution surface and will not benefit.
- A future MuMu release could move this validation into the renderer. If `-Restore` no longer has any effect on picture quality, that is what happened.
- The script edits configuration, nothing else. It will not unlock remote control, cloud phone, cloud saves, sync, or ad removal — those are backend-decided.

---

## License

MIT. See [LICENSE](LICENSE).

Not affiliated with NetEase. "MuMu" is a trademark of its respective owner. Use at your own discretion.
