# MuMu Quality Unlocker

**本地显示参数工具 + 实验性《火影忍者》picfx 初始化控制。**

[English](README.en.md) · [更新记录](CHANGELOG.md) · [MIT License](LICENSE)

> 请先运行只读状态检查，不要把“参数读回成功”当成“所有游戏画质最高”或“会员已开通”。
> 原脚本 `unlock-quality.ps1` 为兼容旧版保留默认行为：**直接无参数运行会应用 1080p，并可能重启模拟器**。
> 新增的 `picfx-local.ps1` 默认只读；非预览的开关/恢复操作必须显式加 `-Experimental`。

## 两类功能，不混为一谈

| 功能 | 脚本 | 验证范围 |
| --- | --- | --- |
| 模拟器分辨率、DPI、帧率上限 | `unlock-quality.ps1` | 官方 CLI 参数及 Android 显示读回；不测游戏实际帧率 |
| 《火影忍者》工具箱对应的本地 picfx 初始化 | `picfx-local.ps1` | 原生初始化值、写前快照、写后读回；不自动判断纹理处理/画质效果 |

**本机实测记录：**2026-11-12，项目使用者已确认本地画质效果。脚本侧另外记录过初始化值 `off → on → off（回滚）→ on` 及重启后读回。用户的画面确认与自动化测试是两类证据，不能合并成跨设备兼容性或量化画质结论。

本次开发所用环境是 Windows、MuMu 6.8.8.0、Android 15 引擎。其他版本可能改变接口或行为，需要自行验证。项目不修改账号/会员数据、不分发厂商 DLL 或游戏资源、不注入或修改可执行文件；不提供远控、云手机、去广告等账号权益。

## Windows 一键懒人包 · 免安装

**[下载 MuMuLocalQuality-v0.1.0.zip](https://github.com/blackbluezyk/MuMu-Quality-Unlocker/raw/refs/heads/main/downloads/MuMuLocalQuality-v0.1.0.zip)** · [SHA256 校验](downloads/MuMuLocalQuality-v0.1.0.zip.sha256) · [使用说明与源码](oneclick/README.md)

先启动 MuMu，解压后双击 **MuMuLocalQuality.exe**，选好实例编号，点 **一键开启**；随后手动重启游戏。提供状态读取、关闭、带校验和的备份恢复。无需 Python 或管理员权限。程序未数字签名，请核对源码与校验值，不需要关闭安全防护。

这项独立工具针对《火影忍者》的本地 `picfx` 初始化，不等于主脚本的分辨率设置，也不激活会员账号或保证 VIP 界面开关亮起。高清缓存最多可能占 20 GB，关闭可能清理缓存。

**用户实测反馈（2026-11-12）：项目维护者确认本机开启后画质有提升。** 这是用户实测，不是脚本自动验证纹理处理；已知本机环境为 MuMu 6.8.8.0 / Android 15，其他版本未保证通用。程序只承诺检查写后读回，不把 `on` 等同于所有画质效果已验证。

懒人包后端在 Windows PowerShell 5.1、PowerShell 7 各通过 22/22 项固定夹具测试；打包测试不修改真实模拟器。构建与完整源码见 [oneclick](oneclick/)。

说明：懒人包组件版本仍为 0.1.0，本次命令行/文档更新为项目 0.2.0；保留原下载包与源码。懒人包与命令行 picfx 快照格式不同，请分别使用创建该快照的工具恢复。

## 环境

- Windows 10/11，PowerShell **5.1 或 7**；不依赖 Python、Node 或 Pester。
- 已安装 MuMu，安装目录下存在 `nx_main/MuMuManager.exe`。
- 默认实例 `0`。picfx 仅支持单实例和 `com.tencent.KiHan`，不套用到其他游戏。
- 实验性 picfx 操作要求实例正在运行；不会自动启动、更新、登录或重启游戏。

## 1. 先查看，不改任何东西

在解压后的项目目录打开 PowerShell：

```powershell
# 显示参数 + 运行中的 Android 显示读回，不创建备份、不重启
powershell -NoProfile -ExecutionPolicy Bypass -File .\unlock-quality.ps1 -Status

# 可供程序解析的 JSON 数组；原生读回不可用时会给出错误字段，不伪造成功
powershell -NoProfile -ExecutionPolicy Bypass -File .\unlock-quality.ps1 -Status -AsJson

# picfx 默认操作就是 Status；只读原生初始化值
powershell -NoProfile -ExecutionPolicy Bypass -File .\picfx-local.ps1 -AsJson
```

安装路径识别失败时显式传 `-InstallPath 'D:\MuMuPlayer'`。显示参数支持 `-VmIndex '0,2'` 或 `-VmIndex all`；picfx 只接受一个非负实例编号。

状态输出中的 `ConfiguredFpsLimit=144` 只是上限，**不是实测 144 FPS**。Android 横竖屏交换尺寸时按等价尺寸比较。运行实例停止或 ADB 不可用时，不会把配置值冒充运行值。

## 2. 修改显示参数

```powershell
# 先预览：不写入、不生成备份、不重启
.\unlock-quality.ps1 -Preset 2k -FrameRate 144 -DryRun

# 应用 2K；默认会重启模拟器，请先保存游戏进度
.\unlock-quality.ps1 -Preset 2k -FrameRate 144

# 自定义尺寸；三个参数必须同时给出
.\unlock-quality.ps1 -Width 2560 -Height 1440 -Dpi 320 -NoRestart

# 恢复该实例的原始显示配置（默认随后重启）
.\unlock-quality.ps1 -Restore
```

| 预设 | 分辨率 | DPI |
| --- | --- | --- |
| 720p | 1280×720 | 160 |
| 1080p | 1920×1080 | 280 |
| 2k | 2560×1440 | 320 |
| 4k | 3840×2160 | 480 |

`-FrameRate` 范围为 15–480，仅是配置请求。部分游戏采用固定内部分辨率，提升模拟器分辨率未必提升画面细节；高分辨率也可能增加显存占用、卡顿。

显示配置的备份位于该实例 `configs/customer_config.json` 旁：

- `*.bak_original`：首次保留的恢复基线，不被后续应用覆盖；若已有合法旧式备份，会选择最早的文件名基线。
- `*.bak_<UTC时间>_<GUID>`：每次应用前的独立快照，避免同秒覆盖。
- `-Restore` 仅恢复选定实例；缺少或存在歧义的备份/配置映射会报错。

## 3. 实验性本地 picfx

此入口来自本机安装版本记录的工具箱配置：工具 ID 为 `hd`，关联 `gi_api_plugin_picfx`。开关初始化操作使用 `nemud.tool.com.tencent.KiHan.picfx`。

**必须使用 MuMuManager 的原生 `sh` 命名空间。**不能把 `adb shell getprop` 返回空字符串当作这个原生开关已关闭的证明。版本差异仍可能改变该行为。

```powershell
# 预览开启，不写原生参数，也不创建快照目录
.\picfx-local.ps1 -Action Enable -DryRun -AsJson

# 明确选择实验性操作；写入前保存并校验当前值
.\picfx-local.ps1 -Action Enable -Experimental

# 关闭（可能清理生成的高清缓存）
.\picfx-local.ps1 -Action Disable -Experimental

# 恢复某个写前快照：路径必须使用实际输出的 SnapshotPath
.\picfx-local.ps1 -Action Restore -BackupPath '.\backups\picfx-实际文件名.json' -Experimental
```

### 开关不等于最终效果

- `NativeAfter=on` 只表示初始化值读回为 on。
- `EffectVerification=NotMeasuredByThisScript` 表示脚本**没有做画质测量**，不是判定效果不存在。
- 脚本不声称会员状态、界面按钮状态已改变；这些不是本地初始化值的同义词。
- 配置注明变更后需重启游戏；请自行保存进度并重启。脚本不会替你关闭对局。
- 配置注明高清资源最多可能占 **20 GB** 本地空间；首次生成可能短暂卡顿，关闭时可能自动清理。
- 建议进入相同游戏场景，对照插件/缓存处理与画面；仅靠分辨率、登录动画、一个开关值不能得出普遍效果结论。

### picfx 快照与恢复

默认保存在项目的 `backups/`，每次真实变更创建独立 JSON 和 `.sha256` 侧文件；`-DryRun`、只读查询和无实际变化的操作不会创建快照。

恢复会校验 SHA256、格式版本、安装管理器路径、实例编号、Android 版本、固定包名和属性名，再恢复原值；恢复前也会保存当前值。快照是**该次写入前的状态**，不保证是从未修改过的安装初始值。校验和用于检测意外变动，不是数字签名，不要使用不可信快照。

## 测试与开发

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
pwsh -NoProfile -File .\tests\Run-All.ps1
```

测试入口还会运行保留的一键懒人包 22 项夹具。全部测试使用临时夹具和模拟 CLI；**不调用已安装 MuMu、不修改原生开关、不重启游戏**。包括旧显示配置回归、只读状态、正确原生命名空间、显式实验性开关、预览零写入、快照校验、错误实例拒绝和读回失败检测。

仓库提供 Windows PowerShell 5.1 / PowerShell 7 双环境 CI。CI 测试通过只说明这些软件行为的测试通过，不是游戏画质或性能基准。

## 反馈与隐私

提交问题请提供 MuMu/Android/PowerShell 版本、操作命令和去敏后的错误。**不要上传账号令牌、完整私人日志、备份或高清缓存**。默认备份和本地测试产物已列入 `.gitignore`。

本项目与网易无隶属关系。MuMu 为相应权利人的商标。
