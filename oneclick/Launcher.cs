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
[assembly: AssemblyVersion("0.2.0.0")]
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
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            bool selection = MainForm.VerifySelectionRules();
            bool integrity = Hash(Backend()) == BackendHash;
            bool ok = integrity && selection;
            Console.WriteLine("{\"resource_integrity\":" + integrity.ToString().ToLowerInvariant() + ",\"instance_selection\":" + selection.ToString().ToLowerInvariant() + ",\"live_settings_touched\":false,\"version\":\"0.2.0\"}");
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

internal sealed class InstanceChoice
{
    internal string Index, Name;
    internal bool Running;
    public override string ToString() { return "#" + Index + "  " + Name + (Running ? "  [运行中]" : "  [未启动]"); }
}

internal sealed class MainForm : Form
{
    private TextBox install = new TextBox(), output = new TextBox();
    private ComboBox index = new ComboBox();
    private Button enable = new Button(), disable = new Button(), status = new Button(), restore = new Button(), browse = new Button(), refresh = new Button();
    private string backupDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MuMuLocalQuality", "backups");
    private string managerPath, catalogRoot;
    private bool preview, busy, applying;
    protected override bool ShowWithoutActivation { get { return preview; } }
    public MainForm() : this(false) { }
    public MainForm(bool previewMode)
    {
        preview = previewMode;
        Text = "MuMu 本地画质助手 · 免安装 0.2.0"; ClientSize = new Size(760, 580);
        FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = false; StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10F); BackColor = Color.FromArgb(245, 247, 250);
        Label title = new Label { Text = "火影忍者 · 本地高清初始化", Font = new Font(Font.FontFamily, 18F, FontStyle.Bold), AutoSize = true, Location = new Point(24, 20) };
        Label note = new Label { Text = "不修改账号或会员状态。先刷新列表，再选择实际实例；不再默认猜编号 0。\n原生参数 on 只证明初始化值读回，不等于自动验证了高清纹理。", Location = new Point(24, 62), Size = new Size(710, 52) };
        Label pathLabel = new Label { Text = "MuMu 安装目录（留空自动查找；多份安装需手动指定）", Location = new Point(24, 122), AutoSize = true };
        install.SetBounds(24, 148, 600, 28); browse.Text = "选择…"; browse.SetBounds(634, 146, 102, 32);
        install.TextChanged += delegate { if (!applying) InvalidateCatalog(); };
        browse.Click += delegate {
            using (FolderBrowserDialog d = new FolderBrowserDialog())
            { if (d.ShowDialog(this) == DialogResult.OK) { install.Text = d.SelectedPath; Run("List", null); } }
        };
        Label instanceLabel = new Label { Text = "选择实例", Location = new Point(24, 194), AutoSize = true };
        index.DropDownStyle = ComboBoxStyle.DropDownList; index.SetBounds(108, 190, 516, 30);
        index.SelectedIndexChanged += delegate { UpdateButtons(); };
        refresh.Text = "刷新实例"; refresh.SetBounds(634, 188, 102, 34); refresh.Click += delegate { Run("List", null); };
        Label selectionHint = new Label { Text = "显示真实编号、名称、运行状态；多个实例时须主动选择。", Location = new Point(108, 224), Size = new Size(620, 24), ForeColor = Color.DimGray };
        enable.Text = "一键开启"; disable.Text = "关闭"; status.Text = "读取状态"; restore.Text = "恢复备份…";
        enable.SetBounds(24, 260, 170, 42); disable.SetBounds(204, 260, 170, 42); status.SetBounds(384, 260, 170, 42); restore.SetBounds(564, 260, 170, 42);
        enable.BackColor = Color.FromArgb(45, 119, 240); enable.ForeColor = Color.White; enable.FlatStyle = FlatStyle.Flat;
        enable.Click += delegate { Run("Enable", null); }; disable.Click += delegate { Run("Disable", null); }; status.Click += delegate { Run("Status", null); };
        restore.Click += delegate {
            using (OpenFileDialog d = new OpenFileDialog()) { d.Filter = "本工具备份 (*.json)|*.json"; if (Directory.Exists(backupDir)) d.InitialDirectory = backupDir; if (d.ShowDialog(this) == DialogResult.OK) Run("Restore", d.FileName); }
        };
        output.SetBounds(24, 320, 710, 158); output.Multiline = true; output.ReadOnly = true; output.ScrollBars = ScrollBars.Vertical; output.BackColor = Color.White;
        output.Text = "先刷新实例列表，再选择要操作的实例。\r\n不会自动启动、重启游戏、安装更新或登录账号。";
        Label warning = new Label { Text = "开启后请手动重启游戏。高清缓存最多可能占 20 GB，关闭可能清理缓存。\n备份保存在当前用户的应用数据目录；不保证所有模拟器版本通用。", Location = new Point(24, 500), Size = new Size(710, 56), ForeColor = Color.FromArgb(110, 75, 20) };
        Controls.AddRange(new Control[] { title, note, pathLabel, install, browse, instanceLabel, index, refresh, selectionHint, enable, disable, status, restore, output, warning });
        UpdateButtons();
        if (preview) { StartPosition = FormStartPosition.Manual; Location = new Point(-32000, -32000); ShowInTaskbar = false; Opacity = 0; }
        else Shown += delegate { Run("List", null); };
    }
    private void InvalidateCatalog()
    {
        managerPath = null; catalogRoot = null; index.Items.Clear();
        output.Text = "安装目录已改变，请刷新实例列表。未修改模拟器设置。"; UpdateButtons();
    }
    private void UpdateButtons()
    {
        InstanceChoice selected = index.SelectedItem as InstanceChoice;
        bool valid = !busy && selected != null && managerPath != null && catalogRoot == install.Text.Trim();
        enable.Enabled = disable.Enabled = restore.Enabled = valid && selected.Running;
        status.Enabled = valid;
        refresh.Enabled = browse.Enabled = install.Enabled = !busy;
        index.Enabled = !busy && index.Items.Count > 0;
    }
    private void Busy(bool value) { busy = value; UpdateButtons(); }
    private void ApplyCatalog(string manager, List<InstanceChoice> choices)
    {
        InstanceChoice old = index.SelectedItem as InstanceChoice;
        string retain = old != null && String.Equals(managerPath, manager, StringComparison.OrdinalIgnoreCase) ? old.Index : null;
        string root = Path.GetDirectoryName(Path.GetDirectoryName(manager));
        applying = true;
        try { install.Text = root; } finally { applying = false; }
        catalogRoot = install.Text.Trim(); managerPath = manager;
        index.Items.Clear();
        foreach (InstanceChoice choice in choices) index.Items.Add(choice);
        index.SelectedIndex = -1;
        for (int i = 0; i < choices.Count; i++) if (choices[i].Index == retain) index.SelectedIndex = i;
        if (index.SelectedIndex < 0 && choices.Count == 1) index.SelectedIndex = 0;
        UpdateButtons();
    }
    internal static bool VerifySelectionRules()
    {
        // Offline WinForms binding checks only. No backend process is launched.
        Dictionary<string, object> parsed = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>("{\"Instances\":[{\"Index\":\"7\",\"Name\":\"fixture\",\"Running\":true}]}");
        List<InstanceChoice> decoded = ParseChoices(parsed);
        if (decoded.Count != 1 || decoded[0].Index != "7" || !decoded[0].Running) return false;
        if (ParseChoices(new JavaScriptSerializer().Deserialize<Dictionary<string, object>>("{\"Instances\":[]}")).Count != 0) return false;
        using (MainForm f = new MainForm(true))
        {
            string m = Path.Combine(Path.GetTempPath(), "MuMuFixture", "nx_main", "MuMuManager.exe");
            List<InstanceChoice> pair = new List<InstanceChoice> { new InstanceChoice { Index = "3", Name = "fixture A", Running = true }, new InstanceChoice { Index = "7", Name = "fixture B", Running = false } };
            f.ApplyCatalog(m, pair);
            if (f.index.SelectedIndex != -1 || f.enable.Enabled || f.status.Enabled) return false;
            f.index.SelectedIndex = 0;
            if (!f.enable.Enabled || !f.status.Enabled) return false;
            f.ApplyCatalog(m, pair);
            if (((InstanceChoice)f.index.SelectedItem).Index != "3") return false;
            f.index.SelectedIndex = 1;
            if (f.enable.Enabled || !f.status.Enabled) return false;
            f.ApplyCatalog(m, new List<InstanceChoice> { pair[1] });
            if (((InstanceChoice)f.index.SelectedItem).Index != "7" || f.enable.Enabled) return false;
            f.install.Text = Path.Combine(Path.GetTempPath(), "OtherMuMuFixture");
            if (f.index.Items.Count != 0 || f.status.Enabled || f.enable.Enabled) return false;
            f.ApplyCatalog(m, pair); f.index.SelectedIndex = 0;
            f.ApplyCatalog(Path.Combine(Path.GetTempPath(), "OtherMuMuFixture", "nx_main", "MuMuManager.exe"), pair);
            if (f.index.SelectedIndex != -1) return false;
            f.ApplyCatalog(m, new List<InstanceChoice>());
            return f.index.Items.Count == 0 && !f.status.Enabled && !f.enable.Enabled;
        }
    }
    private static List<InstanceChoice> ParseChoices(Dictionary<string, object> data)
    {
        List<InstanceChoice> choices = new List<InstanceChoice>();
        foreach (object item in (System.Collections.IEnumerable)data["Instances"])
        {
            Dictionary<string, object> info = (Dictionary<string, object>)item;
            choices.Add(new InstanceChoice { Index = Convert.ToString(info["Index"]), Name = Convert.ToString(info["Name"]), Running = (bool)info["Running"] });
        }
        return choices;
    }
    private static Dictionary<string, object> Execute(string action, string root, string vm, string backup, string backups)
    {
        byte[] bytes = Program.Backend(); if (Program.Hash(bytes) != Program.BackendHash) throw new Exception("内置脚本校验失败。");
        string dir = Path.Combine(Path.GetTempPath(), "MuMuLocalQuality", Program.BackendHash); Directory.CreateDirectory(dir);
        string script = Path.Combine(dir, "Backend.ps1");
        if (File.Exists(script)) { if (Program.Hash(File.ReadAllBytes(script)) != Program.BackendHash) throw new Exception("临时脚本已被修改，停止执行。"); }
        else { using (FileStream f = new FileStream(script, FileMode.CreateNew, FileAccess.Write, FileShare.None)) f.Write(bytes, 0, bytes.Length); }
        string arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Program.Quote(script) + " -Action " + action + " -BackupDirectory " + Program.Quote(backups) + " -AsJson";
        if (vm != null) arguments += " -VmIndex " + Program.Quote(vm);
        if (root.Length > 0) arguments += " -InstallPath " + Program.Quote(root);
        if (backup != null) arguments += " -BackupPath " + Program.Quote(backup);
        ProcessStartInfo start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"), arguments);
        start.UseShellExecute = false; start.CreateNoWindow = true; start.RedirectStandardOutput = true; start.RedirectStandardError = true;
        start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
        // Do not inherit PowerShell 7 module paths when launched from a pwsh terminal.
        start.EnvironmentVariables.Remove("PSModulePath");
        using (Process p = Process.Start(start))
        {
            var stdout = p.StandardOutput.ReadToEndAsync(); var stderr = p.StandardError.ReadToEndAsync();
            if (!p.WaitForExit(45000)) { try { p.Kill(); } catch { } throw new Exception("操作超时，可能已部分执行。请先读取状态，不要重复点击开启。"); }
            string text = stdout.Result, error = stderr.Result;
            if (p.ExitCode != 0) throw new Exception(error + "\r\n" + text);
            return new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(text);
        }
    }
    private void Run(string action, string backup)
    {
        if (busy) return;
        InstanceChoice selected = index.SelectedItem as InstanceChoice;
        if (action != "List" && (selected == null || managerPath == null || catalogRoot != install.Text.Trim()))
        { InvalidateCatalog(); output.Text = "请先刷新实例列表，再选择实际实例。"; return; }
        string root = install.Text.Trim(), vm = selected == null ? null : selected.Index;
        Busy(true); output.Text = action == "List" ? "正在读取实例列表（只读）…" : "正在执行 " + action + "…";
        ThreadPool.QueueUserWorkItem(delegate {
            Dictionary<string, object> data = null; string message;
            List<InstanceChoice> choices = null;
            try
            {
                data = Execute(action, root, vm, backup, backupDir);
                if (action == "List")
                {
                    choices = ParseChoices(data);
                    message = "已从此安装读取 " + choices.Count + " 个实例：\r\n" + Convert.ToString(data["Manager"]) + "\r\n" +
                        (choices.Count == 0 ? "未发现实例，请确认安装目录。不支持自动猜选编号。" : choices.Count == 1 ? "已选择唯一实例；请确认名称和运行状态。" : "请选择实际要操作的实例；不会默认选择编号 0。");
                }
                else
                {
                    string native = data["NativeAfter"] == null ? "未读取（实例未运行）" : Convert.ToString(data["NativeAfter"]);
                    if (native == "") native = "未设置";
                    message = "操作完成：" + action + " / 实例 #" + vm + "\r\n本地初始化值：" + native + "\r\n" +
                        ((bool)data["Written"] ? "已写入并读回核对；请手动重启游戏。" : "未修改当前设置。") + "\r\n" +
                        (data["BackupPath"] == null ? "" : "备份：" + data["BackupPath"] + "\r\n") + "注意：这不是自动验证画质提升或会员开通。";
                }
            }
            catch (Exception ex) { message = "操作未完成验证：\r\n" + ex.Message; }
            if (!IsDisposed) try {
                BeginInvoke((MethodInvoker)delegate {
                    if (choices != null) ApplyCatalog(Convert.ToString(data["Manager"]), choices);
                    else if (data == null) InvalidateCatalog();
                    else if (selected != null) selected.Running = (bool)data["Running"];
                    output.Text = message; Busy(false);
                });
            } catch (ObjectDisposedException) { }
        });
    }
}
