using System.IO;
using System.Net.Http;
using System.Text.Json;

namespace Xiangshang.FieldClient.Windows;

public partial class MainWindow : System.Windows.Window
{
    private FieldApiClient? _api;
    private SqliteOutboxStore? _outbox;
    private OfflineSyncService? _sync;
    private FieldBootstrap? _bootstrap;
    private QueueEntry? _activeEntry;
    private string? _activeClientSessionId;
    private static readonly string[] MovementItems = ["连续双脚障碍跳", "侧向滑步", "倒退平衡", "接球-上手掷准", "手运球绕杆", "脚运球变向", "定点踢准"];

    public MainWindow()
    {
        InitializeComponent();
        Loaded += OnLoadedAsync;
    }

    private async void OnLoadedAsync(object sender, System.Windows.RoutedEventArgs e)
    {
        try
        {
            ConfigureServices();
            await RefreshBootstrapAsync();
        }
        catch (Exception error)
        {
            ConnectionStatus.Text = "等待设备配置";
            OperationHint.Text = error.Message;
        }
    }

    private void ConfigureServices()
    {
        var apiBaseUrl = Environment.GetEnvironmentVariable("FIELD_API_BASE_URL");
        if (string.IsNullOrWhiteSpace(apiBaseUrl))
        {
            throw new InvalidOperationException("请由部署工具配置 FIELD_API_BASE_URL；设备凭证必须存于 Windows Credential Manager 或首次部署环境变量中。");
        }
        if (!Uri.TryCreate(apiBaseUrl, UriKind.Absolute, out var baseUri) || baseUri.Scheme is not ("https" or "http"))
        {
            throw new InvalidOperationException("FIELD_API_BASE_URL 必须是有效的 HTTP(S) 地址。");
        }
        var credentials = DeviceCredentialSource.Resolve(
            Environment.GetEnvironmentVariable("FIELD_DEVICE_ID"),
            Environment.GetEnvironmentVariable("FIELD_DEVICE_KEY"),
            () => WindowsCredentialStore.TryReadDeviceCredentials());
        Environment.SetEnvironmentVariable("FIELD_DEVICE_ID", null, EnvironmentVariableTarget.Process);
        Environment.SetEnvironmentVariable("FIELD_DEVICE_KEY", null, EnvironmentVariableTarget.Process);
        var localPath = Environment.GetEnvironmentVariable("FIELD_LOCAL_DB")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XiangshangField", "field-client.db");
        Directory.CreateDirectory(Path.GetDirectoryName(localPath) ?? throw new InvalidOperationException("本地数据库目录无效。"));
        _outbox = new SqliteOutboxStore(localPath);
        _api = new FieldApiClient(new HttpClient { BaseAddress = baseUri }, credentials);
        _sync = new OfflineSyncService(_api, _outbox);
    }

    private async Task RefreshBootstrapAsync()
    {
        if (_api is null || _outbox is null) return;
        await _outbox.InitializeAsync(CancellationToken.None);
        // Do not claim a calibrated visual station while this fallback shell
        // has no vendor capture adapter. The central gate will show the exact
        // missing preflight checks and refuse formal scoring until the adapter
        // supplies a passing FieldHardwareHealth payload.
        await _api.HeartbeatAsync(FieldHardwareHealthFactory.ManualFallback(), "field-client/0.1", CancellationToken.None);
        _bootstrap = await _api.GetBootstrapAsync(null, CancellationToken.None);
        QueueList.ItemsSource = _bootstrap.Queue;
        ConnectionStatus.Text = $"{_bootstrap.Device.Name} · 已连接";
        OperationHint.Text = _bootstrap.Task is null
            ? "中央端当前没有已发布的体测任务。"
            : !_bootstrap.Readiness.Ready
                ? $"{_bootstrap.Task.Title} 暂不可开始：{string.Join("；", _bootstrap.Readiness.Blockers)}"
                : $"{_bootstrap.Task.Title} · {_bootstrap.Queue.Count} 人在队列中 · 标定 {_bootstrap.Readiness.CalibrationVersion ?? "未下发"} · 场地已就绪";
    }

    private async void CallNextButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        var entry = QueueList.SelectedItem as QueueEntry;
        if (entry is null || _outbox is null) { OperationHint.Text = "请先选择一名候测学生。"; return; }
        await EnqueueAsync("queue.transition", new
        {
            queueEntryId = entry.Id,
            status = "called",
            expectedVersion = entry.StateVersion,
            happenedAt = DateTimeOffset.UtcNow,
            note = "Windows 场地端叫号"
        });
        OperationHint.Text = $"已为 {entry.StudentName} 写入本地叫号事件。";
    }

    private async void StartCaptureButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        var entry = QueueList.SelectedItem as QueueEntry;
        if (entry is null || _bootstrap?.Task is null || _outbox is null) { OperationHint.Text = "请先加载任务并选择一名候测学生。"; return; }
        if (!_bootstrap.Readiness.Ready) { OperationHint.Text = $"当前不能开始采集：{string.Join("；", _bootstrap.Readiness.Blockers)}"; return; }
        if (_activeClientSessionId is not null) { OperationHint.Text = "当前已有正在进行的测试，请先录入成绩并完成。"; return; }
        var clientSessionId = $"field-{Guid.NewGuid():N}";
        await EnqueueAsync("session.open", new
        {
            clientSessionId,
            taskId = _bootstrap.Task.Id,
            studentId = entry.StudentId,
            startedAt = DateTimeOffset.UtcNow,
            algorithmVersion = "field-client/0.1-manual-fallback",
            summary = new { captureMode = "manual-fallback", station = _bootstrap.Station?.StationCode, readiness = "verified-at-bootstrap" }
        });
        await EnqueueAsync("session.events", new
        {
            sessionId = clientSessionId,
            events = new[] { new { clientEventId = Guid.NewGuid(), sequenceNo = 0, eventType = "capture.started", happenedAt = DateTimeOffset.UtcNow, payload = new { source = "field-client" } } }
        });
        _activeClientSessionId = clientSessionId;
        _activeEntry = entry;
        OperationHint.Text = $"已为 {entry.StudentName} 创建本地会话；硬件适配器可继续记录动作和评分，即使当前断网。";
    }

    private async void CompleteCaptureButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_activeClientSessionId is null || _activeEntry is null) { OperationHint.Text = "请先开始一场测试。"; return; }
        var scores = PromptManualScores();
        if (scores is null) return;
        await EnqueueAsync("session.complete", new
        {
            sessionId = _activeClientSessionId,
            algorithmVersion = "field-client/0.1-manual-fallback",
            endedAt = DateTimeOffset.UtcNow,
            scores = scores.Select(score => new { item = score.Item, score = score.Score, confidence = 0.0m, note = "现场人工录入，待复核" }),
            summary = new { captureMode = "manual-fallback", operatorConfirmed = true }
        });
        OperationHint.Text = $"{_activeEntry.StudentName} 的成绩已写入本地队列；同步后会自动进入后台复核。";
        _activeClientSessionId = null;
        _activeEntry = null;
    }

    private async void SyncButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_sync is null) { OperationHint.Text = "场地端尚未配置设备凭证。"; return; }
        try
        {
            var synced = await _sync.FlushAsync(CancellationToken.None);
            var conflicts = _outbox is null ? new OutboxConflictSummary(0, null) : await _outbox.GetConflictSummaryAsync(CancellationToken.None);
            OperationHint.Text = conflicts.Count > 0
                ? $"发现 {conflicts.Count} 条需人工处理的同步冲突：{conflicts.LastError}。原始事件已保留，不能自动覆盖中央记录。"
                : synced ? "本地事件已安全同步到中央服务。" : "同步未完成；事件已保留在本地 SQLite，网络恢复后可重试。";
            if (synced) await RefreshBootstrapAsync();
        }
        catch (Exception error) { OperationHint.Text = $"同步失败：{error.Message}"; }
    }

    private async Task EnqueueAsync(string eventType, object payload)
    {
        if (_outbox is null) return;
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(payload));
        await _outbox.EnqueueAsync(new OutboxEvent(Guid.NewGuid(), eventType, DateTimeOffset.UtcNow, document.RootElement.Clone()), CancellationToken.None);
    }

    private static IReadOnlyList<ManualScore>? PromptManualScores()
    {
        var panel = new System.Windows.Controls.StackPanel { Margin = new System.Windows.Thickness(20) };
        panel.Children.Add(new System.Windows.Controls.TextBlock { Text = "人工录入七项运动能力分数（0–5）", FontWeight = System.Windows.FontWeights.Bold, Margin = new System.Windows.Thickness(0, 0, 0, 12) });
        var inputs = new List<(string Item, System.Windows.Controls.TextBox Input)>();
        foreach (var item in MovementItems)
        {
            var row = new System.Windows.Controls.Grid { Margin = new System.Windows.Thickness(0, 3, 0, 3) };
            row.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition());
            row.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new System.Windows.GridLength(90) });
            var label = new System.Windows.Controls.TextBlock { Text = item, VerticalAlignment = System.Windows.VerticalAlignment.Center };
            var input = new System.Windows.Controls.TextBox { Text = "0", Margin = new System.Windows.Thickness(8, 0, 0, 0) };
            System.Windows.Controls.Grid.SetColumn(input, 1); row.Children.Add(label); row.Children.Add(input); panel.Children.Add(row); inputs.Add((item, input));
        }
        var confirm = new System.Windows.Controls.Button { Content = "确认成绩", Width = 110, HorizontalAlignment = System.Windows.HorizontalAlignment.Right, Margin = new System.Windows.Thickness(0, 14, 0, 0), IsDefault = true };
        panel.Children.Add(confirm);
        var dialog = new System.Windows.Window { Title = "完成测试", Content = panel, Width = 390, Height = 470, ResizeMode = System.Windows.ResizeMode.NoResize, WindowStartupLocation = System.Windows.WindowStartupLocation.CenterOwner };
        IReadOnlyList<ManualScore>? result = null;
        confirm.Click += (_, _) =>
        {
            var values = new List<ManualScore>();
            foreach (var (item, input) in inputs)
            {
                if (!decimal.TryParse(input.Text, out var value) || value < 0 || value > 5)
                {
                    System.Windows.MessageBox.Show(dialog, $"{item} 的分数必须在 0 到 5 之间。", "分数不合法", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Warning);
                    return;
                }
                values.Add(new ManualScore(item, Math.Round(value, 1)));
            }
            result = values; dialog.DialogResult = true;
        };
        dialog.ShowDialog();
        return result;
    }

    private sealed record ManualScore(string Item, decimal Score);
}
