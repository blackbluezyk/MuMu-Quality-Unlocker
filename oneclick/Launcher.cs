using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("MuMu Local Quality")]
[assembly: AssemblyVersion("0.1.0.0")]
internal static class Program
{
    internal const string BackendHash = "__BACKEND_HASH__";
    internal static byte[] Backend()
    {
        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("Backend.ps1"))
        using (MemoryStream output = new MemoryStream()) { input.CopyTo(output); return output.ToArray(); }
    }
    internal static string Hash(byte[] bytes)
    { using (SHA256 hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant(); }
    internal static string Quote(string s)
    {
        StringBuilder b = new StringBuilder("\""); int slashes = 0;
        foreach (char c in s)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { b.Append('\\', slashes * 2 + 1); b.Append('"'); slashes = 0; continue; }
            b.Append('\\', slashes); slashes = 0; b.Append(c);
        }
        b.Append('\\', slashes * 2); return b.Append('"').ToString();
    }
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--self-test")
        {
            bool ok = Hash(Backend()) == BackendHash;
            Console.WriteLine("{\"resource_integrity\":" + ok.ToString().ToLowerInvariant() + ",\"live_settings_touched\":false,\"version\":\"0.1.0\"}");
            return ok ? 0 : 1;
        }
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        if (args.Length == 2 && args[0] == "--render-preview")
        {
            using (MainForm f = new MainForm(true))
            using (Bitmap image = new Bitmap(f.Width, f.Height))
            { f.Show(); Application.DoEvents(); f.DrawToBitmap(image, new Rectangle(0, 0, image.Width, image.Height)); image.Save(args[1], System.Drawing.Imaging.ImageFormat.Png); f.Hide(); }
            return 0;
        }
        Application.Run(new MainForm()); return 0;
    }
}

internal sealed class MainForm : Form
{
    private TextBox install = new TextBox();
    private NumericUpDown index = new NumericUpDown();
    private TextBox output = new TextBox();
    private Button enable = new Button(), disable = new Button(), status = new Button(), restore = new Button(), browse = new Button();
    private string backupDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MuMuLocalQuality", "backups");
    private bool preview;
    protected override bool ShowWithoutActivation { get { return preview; } }
    public MainForm() : this(false) { }
    public MainForm(bool previewMode)
    {
        preview = previewMode;
        Text = "MuMu 本地画质助手 · 免安装 0.1.0"; ClientSize = new Size(720, 510);
        FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = false; StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10F); BackColor = Color.FromArgb(245, 247, 250);
        Label title = new Label { Text = "火影忍者 · 本地高清初始化", Font = new Font(Font.FontFamily, 18F, FontStyle.Bold), AutoSize = true, Location = new Point(24, 20) };
        Label note = new Label { Text = "用户已反馈本机画质有提升；不修改账号或会员状态。\n适配状态需自行确认：原生参数 on 不等于自动验证了高清纹理。", Location = new Point(24, 62), Size = new Size(670, 52) };
        Label pathLabel = new Label { Text = "MuMu 安装目录（留空自动查找）", Location = new Point(24, 122), AutoSize = true };
        install.SetBounds(24, 148, 568, 28); browse.Text = "选择…"; browse.SetBounds(602, 146, 92, 32);
        browse.Click += delegate { using (FolderBrowserDialog d = new FolderBrowserDialog()) { if (d.ShowDialog(this) == DialogResult.OK) install.Text = d.SelectedPath; } };
        Label instanceLabel = new Label { Text = "实例编号", Location = new Point(24, 194), AutoSize = true };
        index.SetBounds(108, 190, 90, 28); index.Maximum = 99999;
        enable.Text = "一键开启"; disable.Text = "关闭"; status.Text = "读取状态"; restore.Text = "恢复备份…";
        enable.SetBounds(24, 236, 160, 42); disable.SetBounds(194, 236, 160, 42); status.SetBounds(364, 236, 160, 42); restore.SetBounds(534, 236, 160, 42);
        enable.BackColor = Color.FromArgb(45, 119, 240); enable.ForeColor = Color.White; enable.FlatStyle = FlatStyle.Flat;
        enable.Click += delegate { Run("Enable", null); }; disable.Click += delegate { Run("Disable", null); }; status.Click += delegate { Run("Status", null); };
        restore.Click += delegate {
            using (OpenFileDialog d = new OpenFileDialog()) { d.Filter = "本工具备份 (*.json)|*.json"; if (Directory.Exists(backupDir)) d.InitialDirectory = backupDir; if (d.ShowDialog(this) == DialogResult.OK) Run("Restore", d.FileName); }
        };
        output.SetBounds(24, 296, 670, 136); output.Multiline = true; output.ReadOnly = true; output.ScrollBars = ScrollBars.Vertical; output.BackColor = Color.White;
        output.Text = "先启动 MuMu 实例，再点击一键开启。\r\n不会自动重启游戏、安装更新或登录账号。";
        Label warning = new Label { Text = "开启后请手动重启游戏。高清缓存最多可能占 20 GB，关闭可能清理缓存。\n请勿将此工具宣传为会员激活或所有版本通用。备份保存在当前用户的应用数据目录。", Location = new Point(24, 446), Size = new Size(670, 52), ForeColor = Color.FromArgb(110, 75, 20) };
        Controls.AddRange(new Control[] { title, note, pathLabel, install, browse, instanceLabel, index, enable, disable, status, restore, output, warning });
        if (preview) { StartPosition = FormStartPosition.Manual; Location = new Point(-32000, -32000); ShowInTaskbar = false; Opacity = 0; }
    }
    private void Busy(bool value)
    { foreach (Control c in new Control[] { enable, disable, status, restore, browse, install, index }) c.Enabled = !value; }
    private void Run(string action, string backup)
    {
        string root = install.Text.Trim(), vm = index.Value.ToString(System.Globalization.CultureInfo.InvariantCulture);
        Busy(true); output.Text = "正在执行 " + action + "…";
        ThreadPool.QueueUserWorkItem(delegate {
            string message;
            try
            {
                byte[] bytes = Program.Backend(); if (Program.Hash(bytes) != Program.BackendHash) throw new Exception("内置脚本校验失败。");
                string dir = Path.Combine(Path.GetTempPath(), "MuMuLocalQuality", Program.BackendHash); Directory.CreateDirectory(dir);
                string script = Path.Combine(dir, "Backend.ps1");
                if (File.Exists(script)) { if (Program.Hash(File.ReadAllBytes(script)) != Program.BackendHash) throw new Exception("临时脚本已被修改，停止执行。"); }
                else { using (FileStream f = new FileStream(script, FileMode.CreateNew, FileAccess.Write, FileShare.None)) f.Write(bytes, 0, bytes.Length); }
                string arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Program.Quote(script) + " -Action " + action + " -VmIndex " + vm + " -BackupDirectory " + Program.Quote(backupDir) + " -AsJson";
                if (root.Length > 0) arguments += " -InstallPath " + Program.Quote(root);
                if (backup != null) arguments += " -BackupPath " + Program.Quote(backup);
                ProcessStartInfo start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"), arguments);
                start.UseShellExecute = false; start.CreateNoWindow = true; start.RedirectStandardOutput = true; start.RedirectStandardError = true;
                start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
                using (Process p = Process.Start(start))
                {
                    var stdout = p.StandardOutput.ReadToEndAsync(); var stderr = p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(45000)) { try { p.Kill(); } catch { } throw new Exception("操作超时，可能已部分执行。请先读取状态，不要重复点击开启。"); }
                    string text = stdout.Result, error = stderr.Result;
                    if (p.ExitCode != 0) throw new Exception(error + "\r\n" + text);
                    Dictionary<string, object> data = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(text);
                    string native = data["NativeAfter"] == null ? "未读取（实例未运行）" : Convert.ToString(data["NativeAfter"]);
                    if (native == "") native = "未设置";
                    message = "操作完成：" + action + "\r\n本地初始化值：" + native + "\r\n" +
                        ((bool)data["Written"] ? "已写入并读回核对；请手动重启游戏。" : "未修改当前设置。") + "\r\n" +
                        (data["BackupPath"] == null ? "" : "备份：" + data["BackupPath"] + "\r\n") + "注意：这不是自动验证画质提升或会员开通。";
                }
            }
            catch (Exception ex) { message = "操作未完成验证：\r\n" + ex.Message; }
            if (!IsDisposed) { try { BeginInvoke((MethodInvoker)delegate { output.Text = message; Busy(false); }); } catch (ObjectDisposedException) { } }
        });
    }
}
