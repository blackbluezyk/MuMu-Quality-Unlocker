# MuMu 本地画质助手 · 免安装懒人包 0.1.0

## 怎么用

1. 先安装并启动 MuMu 模拟器，准备好《火影忍者》。本包不安装 MuMu 或游戏。
2. 解压整个 ZIP，双击 `MuMuLocalQuality.exe`。
3. 默认实例编号为 `0`。多开用户按自己的实例编号选择；安装目录留空会自动查找，找不到时点“选择”。
4. 点击 **一键开启**。工具先保存改变前的值，再写入并读回本地 `picfx` 初始化参数。
5. 按提示 **手动重启游戏**，进入相同场景观察画质。

无需 Python、Node.js、管理员权限或额外安装程序。依赖 Windows 10/11 自带的 Windows PowerShell 5.1 和 .NET Framework 4.x。

### 四个按钮

- **一键开启**：把选中实例的 `nemud.tool.com.tencent.KiHan.picfx` 设置为 `on`。已是 `on` 时不重复写入。
- **关闭**：设置为 `off`；相关高清缓存可能随之被清理。
- **读取状态**：只读，不创建备份，不改设置，不启动或重启游戏。
- **恢复备份…**：选择本工具生成的 JSON。必须保留同名 `.sha256` 文件；校验安装位置、实例编号、Android 引擎和固定属性后才恢复。

备份在 `%LOCALAPPDATA%\MuMuLocalQuality\backups`，每次实际改变前都创建独立快照。它保存的是**操作前的值**，不一定是原厂默认值；恢复也会先保存恢复前的状态。

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

源码包含 `Launcher.cs`、`Backend.ps1`、`app.manifest`、`build.ps1` 和 `tests.ps1`。

```powershell
# 编译；不改模拟器设置
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1

# 固定夹具测试；不调用真实 MuMu
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests.ps1

# 命令行只读状态
powershell -NoProfile -ExecutionPolicy Bypass -File .\Backend.ps1 -Action Status -AsJson
```

已在 Windows PowerShell 5.1 和 PowerShell 7 分别通过 22/22 项夹具测试；EXE 完成内嵌资源校验和界面渲染检查。这些测试不等于所有环境下的真实画质验证。

项目：https://github.com/blackbluezyk/MuMu-Quality-Unlocker

本工具不隶属于网易，使用者自行确认适用性。MIT License。
