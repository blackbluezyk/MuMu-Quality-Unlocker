# MuMu 本地画质助手 · 免安装懒人包 0.2.0

## 怎么用

1. 先安装并启动 MuMu 模拟器，准备好《火影忍者》。本包不安装 MuMu 或游戏。
2. 解压整个 ZIP，双击 `MuMuLocalQuality.exe`。
3. 点击 **刷新实例**，从下拉列表选择实际的 **编号 + 名称 + 运行状态**。只存在一个实例时可自动选中该唯一实例（不要求编号为 0）；存在多个实例时必须主动选择。
4. 安装目录留空会尝试查找；若有多份安装或列表不符，点“选择”指定正在运行的 MuMu 安装根目录，或其 `nx_main` 子目录。修改目录会清空旧实例选择；刷新后按返回的真实安装目录绑定后续操作。
5. 点击 **一键开启**。工具先保存改变前的值，再写入并读回本地 `picfx` 初始化参数。
6. 按提示 **手动重启游戏**，进入相同场景观察画质。

无需 Python、Node.js、管理员权限或额外安装程序。依赖 Windows 10/11 自带的 Windows PowerShell 5.1 和 .NET Framework 4.x。

### 操作按钮

- **刷新实例**：仅执行 `MuMuManager info -v all`，显示真实实例；不读写 picfx，不创建快照，不自动启动/重启。
- **一键开启**：把选中实例的 `nemud.tool.com.tencent.KiHan.picfx` 设置为 `on`。已是 `on` 时不重复写入。
- **关闭**：设置为 `off`；相关高清缓存可能随之被清理。
- **读取状态**：只读，不创建备份，不改设置，不启动或重启游戏。
- **恢复备份…**：选择本工具生成的 JSON。必须保留同名 `.sha256` 文件；校验安装位置、实例编号、Android 引擎和固定属性后才恢复。

备份在 `%LOCALAPPDATA%\MuMuLocalQuality\backups`，每次实际改变前都创建独立快照。它保存的是**操作前的值**，不一定是原厂默认值；恢复也会先保存恢复前的状态。

## `-200 / player index not found` 排查

旧版默认填写 0，不一定是实际实例编号。新版先列出实例并在每次操作前重新校验；如果该实例不存在、刚被删除或已经停止，拒绝写入，不自动换成其他实例。请刷新后重选；列表为空或不符时核对安装目录，不要盲试 1、2。错误提示保留原始返回，便于反馈。

旧 0.1.0 ZIP 仅作历史归档。请完整解压新版，不与旧版 EXE 或脚本混用。后端快照格式不变，原有合法备份可继续按同一安装/实例/引擎校验恢复。

## 实测与限制

- 2026-11-12，项目维护者反馈：在本机开启相应本地画质设置后，**画质有提升**。这是用户实测反馈，不是脚本自动测量画质的结论。
- 已知本机环境为 MuMu 6.8.8.0 / Android 15；其他版本、机型、游戏更新后的行为未保证通用。
- **原生值为 `on` 只证明初始化参数读回成功**，不证明插件已处理纹理、缓存已生成、VIP 界面开关已亮起，或账号会员已开通。
- 该选项与模拟器的分辨率、DPI、帧率上限不同。本包不改这些显示参数，不改会员/账号数据，不补丁或注入任何程序。
- 根据本机工具箱功能说明，高清资源最多可能占用 **20 GB** 空间；初次处理可能短暂卡顿，关闭可能清理缓存。
- 不自动重启、更新游戏、登录账号或代点协议。遇到版本/登录问题请自行处理，再重新读取状态。
- 如果 CLI 不支持该原生属性、实例未启动、值未知或写后读回不一致，工具报错，不宣称成功。

## 安全与源码

程序未数字签名，Windows 可能显示未知发布者。请先核对下载包 SHA256 和公开源码；**不需要关闭杀毒、防火墙或其他安全防护**。

EXE 内嵌本目录 `Backend.ps1`，执行前校验其 SHA256。无自动联网下载、无账号采集、无管理员提权。只有 MuMu 和游戏本身可能按其正常行为联网。

源码包含 `Launcher.cs`、`Backend.ps1`、`app.manifest`、`build.ps1`、`tests.ps1`、`instance-tests.ps1` 和 `smoke.ps1`。

```powershell
# 编译；不改模拟器设置
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1

# 固定夹具测试；不调用真实 MuMu
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests.ps1

# 实例列表检查和编译后的 GUI/CLI 隔离冒烟测试
powershell -NoProfile -ExecutionPolicy Bypass -File .\instance-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\smoke.ps1

# 命令行只读实例列表（不会默认操作实例 0）
powershell -NoProfile -ExecutionPolicy Bypass -File .\Backend.ps1 -Action List -AsJson

# 命令行只读状态（显式填写实际实例编号）
powershell -NoProfile -ExecutionPolicy Bypass -File .\Backend.ps1 -Action Status -VmIndex ACTUAL_INDEX -AsJson
```

测试包含原有 22 项后端用例、新增 34 项实例选择用例，以及 4 项编译 EXE/UI 绑定和真实子进程协议冒烟检查。冒烟测试使用临时构建的假 CLI，禁止 native 设置访问，不调用安装的 MuMu。项目级测试还保留显示参数与 picfx 的 59 项用例；Windows PowerShell 5.1 / PowerShell 7 均运行。自动化测试不等于用户机器上的实际画质验证。

项目：https://github.com/blackbluezyk/MuMu-Quality-Unlocker

本工具不隶属于网易，使用者自行确认适用性。MIT License。
