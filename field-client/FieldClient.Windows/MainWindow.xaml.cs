using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows.Threading;

namespace Xiangshang.FieldClient.Windows;

public partial class MainWindow : System.Windows.Window
{
    private FieldApiClient? _api;
    private SqliteOutboxStore? _outbox;
    private OfflineSyncService? _sync;
    private CaptureAdapterHost? _captureAdapter;
    private string? _evidenceDirectory;
    private string? _configurationPath;
    private Uri? _apiBaseUri;
    private DeviceCredentials? _deviceCredentials;
    private FieldBootstrap? _bootstrap;
    private QueueEntry? _activeEntry;
    private string? _activeClientSessionId;
    private ICaptureRun? _activeCaptureRun;
    private PreparedCaptureResult? _preparedCaptureResult;
    private InterruptedCaptureState? _interruptedCapture;
    private bool _captureDetachedFromTask;
    private CancellationTokenSource? _captureEventsCancellation;
    private Task? _captureEventsTask;
    private int _captureEventCount;
    private IReadOnlyList<FieldProtocolItemProgress> _protocolProgress = [];
    private string? _protocolProgressTaskId;
    private readonly DispatcherTimer _maintenanceTimer = new() { Interval = TimeSpan.FromSeconds(15) };
    private bool _maintenanceBusy;
    private bool _pausedByCentral;
    private bool _localEmergencyStop;
    private bool _captureAllowedByConnection;
    private bool _operatorStateRestored;
    private bool _taskSelectorUpdating;
    private bool _taskSwitchBusy;
    private bool _pendingQueueStateRestored;
    private string? _selectedTaskId;
    private readonly Dictionary<string, string> _localQueueStatuses = new();
    private readonly FieldQueueVersionChain _queueVersionChain = new();
    private IReadOnlyList<QueueEntry>? _lastCentralQueue;
    private static readonly JsonSerializerOptions SnapshotJson = new(JsonSerializerDefaults.Web);
    private static readonly string SoftwareVersion = FieldClientVersion.Format(typeof(MainWindow).Assembly.GetName().Version);
    private static readonly System.Windows.Media.Brush StepIdleBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(57, 83, 111));
    private static readonly System.Windows.Media.Brush StepActiveBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(47, 124, 227));
    private static readonly System.Windows.Media.Brush StepDoneBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(66, 214, 164));
    private static readonly System.Windows.Media.Brush StepTextIdleBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(113, 137, 165));
    private static readonly System.Windows.Media.Brush StepTextActiveBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(193, 208, 225));

    public MainWindow()
    {
        InitializeComponent();
        Title = $"向上少年 · 现场体测工作台 · {SoftwareVersion.Replace("field-client/", "v", StringComparison.Ordinal)}";
        Loaded += OnLoadedAsync;
        _maintenanceTimer.Tick += MaintenanceTimer_Tick;
        Closed += async (_, _) =>
        {
            _maintenanceTimer.Stop();
            _captureEventsCancellation?.Cancel();
            if (_captureAdapter is not null) await _captureAdapter.DisposeAsync();
        };
    }

    private async void OnLoadedAsync(object sender, System.Windows.RoutedEventArgs e)
    {
        try
        {
            if (!ConfigureServicesWithFirstRunSetup()) return;
            await RefreshBootstrapAsync();
            if (_sync is not null) _ = await _sync.FlushAsync(CancellationToken.None);
            await ReconcileQueueSyncConflictsAsync(showOperatorHint: true);
            await RefreshSyncStatusAsync();
            await ProcessDeviceCommandsAsync();
            _maintenanceTimer.Start();
        }
        catch (Exception error)
        {
            if (!await TryLoadSnapshotAsync(error)) ShowConnectionError(error);
            if (_api is not null) _maintenanceTimer.Start();
        }
    }

    private void ConfigureServices()
    {
        var applicationDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XiangshangField");
        Directory.CreateDirectory(applicationDirectory);
        _evidenceDirectory = Path.Combine(applicationDirectory, "evidence");
        Directory.CreateDirectory(_evidenceDirectory);
        var localPath = Environment.GetEnvironmentVariable("FIELD_LOCAL_DB") ?? Path.Combine(applicationDirectory, "field-client.db");
        Directory.CreateDirectory(Path.GetDirectoryName(localPath) ?? throw new InvalidOperationException("本地数据库目录无效。"));
        _outbox = new SqliteOutboxStore(localPath);
        _pendingQueueStateRestored = false;
        _localQueueStatuses.Clear();
        _queueVersionChain.Clear();
        _configurationPath = Path.Combine(applicationDirectory, "field-client.json");
        var baseUri = FieldClientConfiguration.ResolveApiBaseUrl(
            Environment.GetEnvironmentVariable("FIELD_API_BASE_URL"),
            _configurationPath);
        var environmentDeviceId = Environment.GetEnvironmentVariable("FIELD_DEVICE_ID");
        var environmentDeviceKey = Environment.GetEnvironmentVariable("FIELD_DEVICE_KEY");
        var credentials = DeviceCredentialSource.Resolve(
            environmentDeviceId,
            environmentDeviceKey,
            () => WindowsCredentialStore.TryReadDeviceCredentials());
        if (!string.IsNullOrWhiteSpace(environmentDeviceId) && !string.IsNullOrWhiteSpace(environmentDeviceKey)) WindowsCredentialStore.SaveDeviceCredentials(credentials);
        Environment.SetEnvironmentVariable("FIELD_DEVICE_ID", null, EnvironmentVariableTarget.Process);
        Environment.SetEnvironmentVariable("FIELD_DEVICE_KEY", null, EnvironmentVariableTarget.Process);
        _apiBaseUri = baseUri;
        _deviceCredentials = credentials;
        _api = new FieldApiClient(new HttpClient { BaseAddress = baseUri }, credentials);
        _sync = new OfflineSyncService(_api, _outbox);
        _captureAdapter = CaptureAdapterHost.LoadFromConfiguration(_configurationPath);
    }

    private bool ConfigureServicesWithFirstRunSetup()
    {
        try
        {
            ConfigureServices();
            return true;
        }
        catch (InvalidOperationException error) when (error.Message.Contains("中央服务地址", StringComparison.Ordinal) || error.Message.Contains("设备凭证", StringComparison.Ordinal) || error.Message.Contains("FIELD_DEVICE", StringComparison.Ordinal))
        {
            var applicationDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XiangshangField");
            Directory.CreateDirectory(applicationDirectory);
            _configurationPath = Path.Combine(applicationDirectory, "field-client.json");
            Uri? existingUri = null;
            try { existingUri = FieldClientConfiguration.TryReadApiBaseUrl(_configurationPath); } catch { }
            var existingCredentials = WindowsCredentialStore.TryReadDeviceCredentials();
            var setup = new ConnectionSetupWindow(_configurationPath, existingUri, existingCredentials, error.Message) { Owner = this };
            if (setup.ShowDialog() != true)
            {
                ShowConnectionError(new InvalidOperationException("尚未完成场地端连接设置。请展开右侧“设备、连接与同步”，点击“中央服务连接设置”继续。"));
                return false;
            }
            ConfigureServices();
            return true;
        }
    }

    private async void ConnectionSettingsButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_activeClientSessionId is not null || _interruptedCapture is not null)
        {
            OperationHint.Text = "当前有未结束或待恢复的采集，处理完成后才能修改连接设置。";
            return;
        }
        var applicationDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XiangshangField");
        Directory.CreateDirectory(applicationDirectory);
        _configurationPath ??= Path.Combine(applicationDirectory, "field-client.json");
        var setup = new ConnectionSetupWindow(_configurationPath, _apiBaseUri, _deviceCredentials) { Owner = this };
        if (setup.ShowDialog() != true) return;
        ConnectionSettingsButton.IsEnabled = false;
        try
        {
            if (_captureAdapter is not null) await _captureAdapter.DisposeAsync();
            ConfigureServices();
            OperationHint.Text = "连接设置已更新，正在下载设备、任务和学生名单…";
            await RefreshBootstrapAsync();
            await ProcessDeviceCommandsAsync();
            await RefreshSyncStatusAsync();
            _maintenanceTimer.Start();
        }
        catch (Exception error) { ShowConnectionError(error); }
        finally { ConnectionSettingsButton.IsEnabled = true; }
    }

    private async void CaptureSettingsButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_activeClientSessionId is not null || _interruptedCapture is not null)
        {
            OperationHint.Text = "当前有未结束或待恢复的采集，处理完成后才能修改采集设备。";
            return;
        }
        if (string.IsNullOrWhiteSpace(_configurationPath))
        {
            OperationHint.Text = "请先完成中央服务连接设置，再配置采集设备。";
            return;
        }
        var setup = new CaptureAdapterSetupWindow(_configurationPath) { Owner = this };
        if (setup.ShowDialog() != true) return;
        CaptureSettingsButton.IsEnabled = false;
        try
        {
            if (_captureAdapter is not null) await _captureAdapter.DisposeAsync();
            _captureAdapter = CaptureAdapterHost.LoadFromConfiguration(_configurationPath);
            OperationHint.Text = setup.AdapterRemoved
                ? "采集设备配置已移除，当前仍可查看学生和同步记录，但不能叫号或开始正式采集。"
                : $"采集适配器 {setup.SavedAdapterName ?? "已配置"} 已保存，正在重新执行设备自检…";
            await RefreshBootstrapAsync(updateOperationHint: false);
            if (_captureAdapter.IsAvailable)
                OperationHint.Text = _bootstrap?.Readiness.Ready == true
                    ? $"采集适配器 {_captureAdapter.AdapterName} 已通过中央开测检查。"
                    : $"采集适配器 {_captureAdapter.AdapterName} 已加载；请按右侧检查清单完成其余开测条件。";
        }
        catch (Exception error)
        {
            OperationHint.Text = $"采集设备设置已保存，但重新自检失败：{error.Message}";
        }
        finally
        {
            CaptureSettingsButton.IsEnabled = true;
            UpdateQueueActionAvailability();
        }
    }

    private async Task RefreshBootstrapAsync(bool updateOperationHint = true)
    {
        if (_api is null || _outbox is null) return;
        await _outbox.InitializeAsync(CancellationToken.None);
        await RestoreOperatorStateAsync();
        await RefreshSyncStatusAsync();
        // Bootstrap first to obtain the central calibration, then let the
        // certified adapter attest against that exact version before refresh.
        FieldBootstrap initialBootstrap;
        string? taskHandoffNotice = null;
        try
        {
            initialBootstrap = await _api.GetBootstrapAsync(_selectedTaskId, CancellationToken.None);
        }
        catch (FieldApiException error) when (_selectedTaskId is not null && error.Code is "FIELD_TASK_NOT_FOUND" or "FIELD_TASK_INACTIVE")
        {
            taskHandoffNotice = error.Code == "FIELD_TASK_INACTIVE"
                ? "后台已关闭原现场任务"
                : "后台已移除原现场任务";
            if (_activeClientSessionId is not null)
            {
                _interruptedCapture = await StopActiveCaptureAsync();
                _captureDetachedFromTask = _interruptedCapture is not null;
            }
            _selectedTaskId = null;
            await _outbox.DeleteSnapshotAsync("selected-task", CancellationToken.None);
            initialBootstrap = await _api.GetBootstrapAsync(null, CancellationToken.None);
        }
        var health = await (_captureAdapter?.GetHealthAsync(initialBootstrap.Calibration, CancellationToken.None)
            ?? Task.FromResult(FieldHardwareHealthFactory.ManualFallback()));
        health = FieldHardwareHealthFactory.ApplyLocalEmergencyStop(health, _localEmergencyStop);
        await _api.HeartbeatAsync(health, SoftwareVersion, CancellationToken.None);
        _bootstrap = await _api.GetBootstrapAsync(_selectedTaskId, CancellationToken.None);
        await ReconcileCentralControlStateAsync(_bootstrap.Device.ControlState);
        _selectedTaskId = _bootstrap.Task?.Id;
        if (_selectedTaskId is not null) await _outbox.SaveSnapshotAsync("selected-task", JsonSerializer.Serialize(_selectedTaskId, SnapshotJson), CancellationToken.None);
        await _outbox.SaveSnapshotAsync("bootstrap", JsonSerializer.Serialize(_bootstrap, SnapshotJson), CancellationToken.None);
        await RestorePendingQueueTransitionsAsync();
        ApplyBootstrap(_bootstrap, updateOperationHint, allowCapture: true);
        if (taskHandoffNotice is not null)
        {
            OperationHint.Text = _bootstrap.Task is null
                ? $"{taskHandoffNotice}，本站已停止叫号；等待后台发布下一任务。"
                : $"{taskHandoffNotice}，已安全切换到“{_bootstrap.Task.Title}”。请核对名单后继续。";
            if (_bootstrap.Task is null)
            {
                ReadinessTitle.Text = "现场任务已关闭";
                ReadinessDetail.Text = "未完成学生已由后台收尾，客户端不会继续叫号或采集；等待下一任务下发。";
                ReadinessPanel.Background = (System.Windows.Media.Brush)FindResource("AmberSoft");
                ReadinessPanel.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(241, 217, 158));
                ReadinessTitle.Foreground = (System.Windows.Media.Brush)FindResource("Amber");
            }
        }
        await RestoreInterruptedCaptureAsync();
    }

    private async Task RestoreOperatorStateAsync()
    {
        if (_operatorStateRestored || _outbox is null) return;
        var selectedTask = await _outbox.ReadSnapshotAsync("selected-task", CancellationToken.None);
        if (selectedTask is not null)
        {
            try { _selectedTaskId = JsonSerializer.Deserialize<string>(selectedTask.Json, SnapshotJson); }
            catch (JsonException) { await _outbox.DeleteSnapshotAsync("selected-task", CancellationToken.None); }
        }
        var pause = await _outbox.ReadSnapshotAsync("central-pause", CancellationToken.None);
        if (pause is not null)
        {
            try { _pausedByCentral = JsonSerializer.Deserialize<CentralPauseState>(pause.Json, SnapshotJson) is not null; }
            catch (JsonException) { await _outbox.DeleteSnapshotAsync("central-pause", CancellationToken.None); }
        }
        var emergencyStop = await _outbox.ReadSnapshotAsync("local-emergency-stop", CancellationToken.None);
        if (emergencyStop is not null)
        {
            try { _localEmergencyStop = JsonSerializer.Deserialize<LocalEmergencyStopState>(emergencyStop.Json, SnapshotJson) is not null; }
            catch (JsonException) { await _outbox.DeleteSnapshotAsync("local-emergency-stop", CancellationToken.None); }
        }
        _operatorStateRestored = true;
    }

    private async Task PersistCentralPauseAsync(string? commandType)
    {
        if (_outbox is null) return;
        if (commandType is null) await _outbox.DeleteSnapshotAsync("central-pause", CancellationToken.None);
        else await _outbox.SaveSnapshotAsync("central-pause", JsonSerializer.Serialize(new CentralPauseState(commandType, DateTimeOffset.UtcNow), SnapshotJson), CancellationToken.None);
    }

    private async Task ReconcileCentralControlStateAsync(string? controlState)
    {
        if (controlState is not ("running" or "paused" or "stopped")) return;
        _pausedByCentral = controlState is "paused" or "stopped";
        await PersistCentralPauseAsync(_pausedByCentral ? controlState : null);
    }

    private void UpdateEmergencyStopVisual()
    {
        if (EmergencyStopButton is null) return;
        EmergencyStopButton.Content = _localEmergencyStop ? "解除本地急停" : "紧急停止";
        EmergencyStopButton.ToolTip = _localEmergencyStop ? "解除前请确认现场风险已排除" : "立即停止活动采集并锁定所有新操作";
    }

    private void ApplyBootstrap(FieldBootstrap bootstrap, bool updateOperationHint, bool allowCapture)
    {
        _captureAllowedByConnection = allowCapture;
        var previousCentralQueue = _lastCentralQueue;
        var queueDelta = FieldQueueChangeDetector.Compare(previousCentralQueue, bootstrap.Queue);
        _lastCentralQueue = bootstrap.Queue.ToArray();
        foreach (var entry in bootstrap.Queue)
        {
            if (_localQueueStatuses.TryGetValue(entry.Id, out var localStatus) && localStatus == entry.Status)
            {
                if (!_queueVersionChain.HasPending(entry.Id) || _queueVersionChain.TryReconcile(entry, localStatus))
                {
                    _localQueueStatuses.Remove(entry.Id);
                }
            }
        }
        var selectedStudentId = SelectedQueueEntry()?.StudentId;
        var selectedEntry = selectedStudentId is null ? null : bootstrap.Queue.FirstOrDefault(item => item.StudentId == selectedStudentId);
        var selectedHasLocalActiveFlow = selectedEntry is not null && EffectiveQueueStatus(selectedEntry) is "called" or "checked_in" or "testing";
        var queueAttention = selectedHasLocalActiveFlow
            ? new FieldQueueAttention(selectedStudentId, selectedEntry!.StudentName, EffectiveQueueStatus(selectedEntry), false)
            : FieldQueueAttentionPolicy.Select(previousCentralQueue, bootstrap.Queue, selectedStudentId);
        RefreshQueueDisplay(queueAttention.StudentId ?? selectedStudentId);
        QueueRefreshText.Text = allowCapture
            ? queueAttention.ChangedByCentral ? $"后台状态已同步 · {DateTime.Now:HH:mm:ss}" : $"已更新 {DateTime.Now:HH:mm:ss} · 自动 15 秒"
            : "本地离线快照";
        ConnectionStatus.Text = $"{bootstrap.Device.Name} · {SoftwareVersion.Replace("field-client/", "v", StringComparison.Ordinal)}";
        ConnectionDot.Fill = StepDoneBrush;
        HeaderConnectionButton.Content = "连接设置";
        var availableTasks = bootstrap.AvailableTasks ?? [];
        _taskSelectorUpdating = true;
        TaskSelector.ItemsSource = availableTasks;
        TaskSelector.SelectedValue = bootstrap.Task?.Id;
        TaskSelector.Visibility = availableTasks.Count > 0 ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        TaskSelector.IsEnabled = availableTasks.Count > 1 && _activeClientSessionId is null && _interruptedCapture is null && !_taskSwitchBusy;
        TaskTitleText.Visibility = availableTasks.Count > 0 ? System.Windows.Visibility.Collapsed : System.Windows.Visibility.Visible;
        _taskSelectorUpdating = false;
        TaskTitleText.Text = bootstrap.Task?.Title ?? "暂无已发布测评任务";
        var rosterStatus = FieldRosterStatusPolicy.Describe(bootstrap.Task is not null, bootstrap.Station is not null, bootstrap.QueueSummary, bootstrap.Queue.Count);
        var stationStatus = FieldStationStatusPolicy.Describe(bootstrap.Station?.Status, bootstrap.Station?.StatusReason);
        TaskMetaText.Text = bootstrap.Task is null
            ? "请在后台发布任务后刷新"
            : $"{bootstrap.Task.TestDate:yyyy-MM-dd} · {bootstrap.Station?.Name ?? "未绑定测试点"} · {(bootstrap.Station?.Status == "online" ? "在线" : stationStatus.Title)} · 本站 {bootstrap.QueueSummary?.StationActiveCount ?? bootstrap.Queue.Count}/{bootstrap.QueueSummary?.RosterCount ?? bootstrap.Queue.Count} 人";
        var stationTaskCompatible = StationSupportsTask(bootstrap.Station, bootstrap.Task);
        TaskScopeText.Text = bootstrap.Task is null
            ? "等待后台下发测评项目"
            : $"项目：{string.Join("、", bootstrap.Task.Items)} · {(string.IsNullOrWhiteSpace(bootstrap.Station?.ItemCode) ? "整套任务通道" : $"单项通道：{bootstrap.Station.ItemCode}")}";
        CurrentTaskScopeText.Text = bootstrap.Task is null
            ? "等待中央服务下发任务项目"
            : string.Join("  ·  ", bootstrap.Task.Items);
        TaskScopeText.Foreground = stationTaskCompatible ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(175, 196, 221)) : (System.Windows.Media.Brush)FindResource("Red");
        if (_activeClientSessionId is null && !string.Equals(_protocolProgressTaskId, bootstrap.Task?.Id, StringComparison.Ordinal)) ResetProtocolProgress();
        ReadinessTitle.Text = bootstrap.Readiness.Ready ? "场地已就绪" : "开测条件未完成";
        ReadinessPanel.Background = bootstrap.Readiness.Ready ? (System.Windows.Media.Brush)FindResource("GreenSoft") : (System.Windows.Media.Brush)FindResource("AmberSoft");
        ReadinessPanel.BorderBrush = bootstrap.Readiness.Ready ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 230, 214)) : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(241, 217, 158));
        ReadinessTitle.Foreground = bootstrap.Readiness.Ready ? (System.Windows.Media.Brush)FindResource("Green") : (System.Windows.Media.Brush)FindResource("Amber");
        CaptureModeBadge.Text = _captureAdapter?.IsAvailable == true ? $"已认证 · {_captureAdapter.AdapterName}" : "设备未接入";
        CaptureModeBadge.Foreground = _captureAdapter?.IsAvailable == true ? StepDoneBrush : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(240, 184, 74));
        RenderReadinessChecklist(bootstrap.Readiness);
        if (bootstrap.Task is null)
        {
            ReadinessTitle.Text = "当前没有进行中的任务";
            ReadinessDetail.Text = "本站已停止叫号和采集；请在后台发布任务后刷新。";
            ReadinessPanel.Background = (System.Windows.Media.Brush)FindResource("AmberSoft");
            ReadinessPanel.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(241, 217, 158));
            ReadinessTitle.Foreground = (System.Windows.Media.Brush)FindResource("Amber");
            ReadinessChecklistScroll.Visibility = System.Windows.Visibility.Collapsed;
            ReadinessMoreText.Visibility = System.Windows.Visibility.Collapsed;
        }
        if (!stationTaskCompatible && bootstrap.Task is not null)
        {
            ReadinessTitle.Text = "测试点与任务项目不匹配";
            ReadinessDetail.Text = string.IsNullOrWhiteSpace(bootstrap.Station?.ItemCode)
                ? "当前任务项目配置无效，请在后台检查任务。"
                : $"本站只支持“{bootstrap.Station.ItemCode}”，当前任务为：{string.Join("、", bootstrap.Task.Items)}。请在后台调整测试点能力或切换任务。";
            ReadinessPanel.Background = (System.Windows.Media.Brush)FindResource("AmberSoft");
            ReadinessPanel.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(241, 217, 158));
            ReadinessTitle.Foreground = (System.Windows.Media.Brush)FindResource("Amber");
        }
        if (stationStatus.BlocksOperations)
        {
            ReadinessTitle.Text = stationStatus.Title;
            ReadinessDetail.Text = $"{stationStatus.Detail} {stationStatus.RecoveryHint}";
            ReadinessPanel.Background = bootstrap.Station?.Status == "disabled"
                ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 235, 235))
                : (System.Windows.Media.Brush)FindResource("AmberSoft");
            ReadinessPanel.BorderBrush = bootstrap.Station?.Status == "disabled"
                ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(239, 174, 174))
                : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(241, 217, 158));
            ReadinessTitle.Foreground = bootstrap.Station?.Status == "disabled"
                ? (System.Windows.Media.Brush)FindResource("Red")
                : (System.Windows.Media.Brush)FindResource("Amber");
        }
        if (_pausedByCentral && !stationStatus.BlocksOperations)
        {
            ReadinessTitle.Text = "中央管理端已暂停";
            ReadinessDetail.Text = "现场操作保持锁定；即使重启 Windows，也必须等待后台明确恢复。";
            ReadinessPanel.Background = (System.Windows.Media.Brush)FindResource("AmberSoft");
            ReadinessPanel.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(241, 217, 158));
            ReadinessTitle.Foreground = (System.Windows.Media.Brush)FindResource("Amber");
        }
        if (_localEmergencyStop)
        {
            ReadinessTitle.Text = "本地紧急停止已触发";
            ReadinessDetail.Text = "认证采集已停止，所有新操作保持锁定；排除现场风险后再解除。";
            ReadinessPanel.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 235, 235));
            ReadinessPanel.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(239, 174, 174));
            ReadinessTitle.Foreground = (System.Windows.Media.Brush)FindResource("Red");
        }
        UpdateEmergencyStopVisual();
        UpdateQueueActionAvailability();
        if (!updateOperationHint)
        {
            if (_activeClientSessionId is null && _interruptedCapture is null && !_pausedByCentral && !_localEmergencyStop && queueAttention.ToOperatorMessage() is { } attentionMessage)
            {
                OperationHint.Text = attentionMessage;
            }
            else if (queueDelta.HasChanges && _activeClientSessionId is null && _interruptedCapture is null && !_pausedByCentral && !_localEmergencyStop)
            {
                OperationHint.Text = queueDelta.ToOperatorMessage();
            }
            return;
        }
        OperationHint.Text = _localEmergencyStop
            ? "本地紧急停止已触发，当前只能查看名单和同步记录。"
            : stationStatus.BlocksOperations
            ? $"{stationStatus.Title}：{stationStatus.Detail}"
            : _pausedByCentral
            ? "中央管理端已暂停现场操作，当前只能查看名单和同步本地记录。"
            : bootstrap.Task is null
            ? "中央端当前没有已发布的体测任务。"
            : !bootstrap.Readiness.Ready
                ? $"{bootstrap.Task.Title} 暂不可开始：{string.Join("；", bootstrap.Readiness.Blockers)}"
                : bootstrap.Queue.Count == 0
                    ? rosterStatus.EmptyDetail
                : $"{bootstrap.Task.Title} · {bootstrap.Queue.Count} 人在队列中 · 标定 {bootstrap.Readiness.CalibrationVersion ?? "未下发"} · 场地已就绪";
    }

    private void RenderReadinessChecklist(FieldReadiness readiness)
    {
        var checks = readiness.Checks ?? [];
        if (checks.Count == 0)
        {
            ReadinessDetail.Text = readiness.Ready
                ? $"设备自检通过 · 标定 {readiness.CalibrationVersion ?? "已生效"}"
                : string.Join("；", readiness.Blockers);
            ReadinessChecklistScroll.Visibility = System.Windows.Visibility.Collapsed;
            ReadinessMoreText.Visibility = System.Windows.Visibility.Collapsed;
            return;
        }
        var failed = checks.Where(item => item.Status == "blocked").ToList();
        var pending = checks.Where(item => item.Status == "pending").ToList();
        var selected = readiness.Ready
            ? checks.Where(item => item.Key is "central_control" or "station_online" or "capture_adapter" or "calibration_check" or "storage").Take(5).ToList()
            : failed.Concat(pending).Take(6).ToList();
        ReadinessDetail.Text = readiness.Ready
            ? $"{checks.Count(item => item.Status == "passed")}/{checks.Count} 项开测检查已通过 · 标定 {readiness.CalibrationVersion ?? "已生效"}"
            : $"{failed.Count} 项未通过，{pending.Count} 项等待前置条件";
        ReadinessChecklist.ItemsSource = selected.Select(item => new ReadinessCheckDisplay(
            item.Label,
            item.Status == "passed" ? "✓" : item.Status == "pending" ? "○" : "!",
            item.Status == "passed" ? (System.Windows.Media.Brush)FindResource("Green") : item.Status == "pending" ? (System.Windows.Media.Brush)FindResource("Muted") : (System.Windows.Media.Brush)FindResource("Red"),
            item.Status == "passed" ? item.Detail : $"{item.Detail} · {item.Remediation}"));
        ReadinessChecklistScroll.Visibility = selected.Count > 0 ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        var hiddenCount = readiness.Ready ? checks.Count - selected.Count : failed.Count + pending.Count - selected.Count;
        ReadinessMoreText.Text = hiddenCount > 0 ? $"另有 {hiddenCount} 项，请在后台查看完整开测检查" : string.Empty;
        ReadinessMoreText.Visibility = hiddenCount > 0 ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
    }

    private async Task<bool> TryLoadSnapshotAsync(Exception error)
    {
        if (_outbox is null) return false;
        try
        {
            await _outbox.InitializeAsync(CancellationToken.None);
            await RestoreOperatorStateAsync();
            var snapshot = await _outbox.ReadSnapshotAsync("bootstrap", CancellationToken.None);
            var bootstrap = snapshot is null ? null : JsonSerializer.Deserialize<FieldBootstrap>(snapshot.Json, SnapshotJson);
            if (bootstrap is null || snapshot is null) return false;
            _bootstrap = bootstrap;
            await RestorePendingQueueTransitionsAsync();
            ApplyBootstrap(bootstrap, updateOperationHint: false, allowCapture: false);
            ConnectionStatus.Text = "离线 · 已加载本地名单";
            ConnectionDot.Fill = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(240, 184, 74));
            HeaderConnectionButton.Content = "恢复连接";
            TaskMetaText.Text += " · 离线快照";
            ReadinessTitle.Text = "当前处于离线模式";
            ReadinessDetail.Text = $"已加载 {snapshot.UpdatedAt.ToLocalTime():yyyy-MM-dd HH:mm} 保存的任务和名单。离线时仅可查看名单和本地记录；叫号、签到与正式采集均需恢复中央连接。";
            ReadinessChecklistScroll.Visibility = System.Windows.Visibility.Collapsed;
            ReadinessMoreText.Visibility = System.Windows.Visibility.Collapsed;
            OperationHint.Text = $"中央服务暂不可用：{error.Message}。本地事件会在网络恢复后自动同步。";
            await RestoreInterruptedCaptureAsync();
            return true;
        }
        catch (Exception) { return false; }
    }

    private void ShowConnectionError(Exception error)
    {
        ConnectionStatus.Text = "设备未连接";
        ConnectionDot.Fill = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(226, 93, 93));
        HeaderConnectionButton.Content = "立即连接";
        TaskTitleText.Text = "无法加载测评任务";
        TaskMetaText.Text = "请检查服务地址与设备凭证";
        QueueRefreshText.Text = "中央服务连接失败";
        ReadinessTitle.Text = "开测检查未通过";
        ReadinessDetail.Text = error.Message;
        ReadinessChecklistScroll.Visibility = System.Windows.Visibility.Collapsed;
        ReadinessMoreText.Visibility = System.Windows.Visibility.Collapsed;
        OperationHint.Text = error.Message;
        UpdateQueueActionAvailability();
    }

    private async void MaintenanceTimer_Tick(object? sender, EventArgs e)
    {
        if (_maintenanceBusy || _api is null) return;
        _maintenanceBusy = true;
        try
        {
            await RefreshBootstrapAsync(updateOperationHint: false);
            if (_sync is not null) _ = await _sync.FlushAsync(CancellationToken.None);
            await ReconcileQueueSyncConflictsAsync(showOperatorHint: true);
            await RefreshSyncStatusAsync();
            await ProcessDeviceCommandsAsync();
        }
        catch (Exception error)
        {
            _captureAllowedByConnection = false;
            ConnectionStatus.Text = "离线 · 正在自动重连";
            ConnectionDot.Fill = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(240, 184, 74));
            HeaderConnectionButton.Content = "恢复连接";
            ReadinessTitle.Text = "中央服务暂时无法连接";
            ReadinessDetail.Text = error.Message;
            QueueRefreshText.Text = $"重连中 · {DateTime.Now:HH:mm:ss}";
            ReadinessChecklistScroll.Visibility = System.Windows.Visibility.Collapsed;
            ReadinessMoreText.Visibility = System.Windows.Visibility.Collapsed;
            UpdateQueueActionAvailability();
        }
        finally { _maintenanceBusy = false; }
    }

    private async Task ProcessDeviceCommandsAsync()
    {
        if (_api is null) return;
        var commands = await _api.GetCommandsAsync(CancellationToken.None);
        foreach (var command in commands)
        {
            var failed = false;
            try
            {
                switch (command.CommandType)
                {
                    case "refresh_config":
                        await RefreshBootstrapAsync(updateOperationHint: false);
                        OperationHint.Text = "中央管理端已下发配置刷新，任务与名单已更新。";
                        break;
                    case "pause":
                    case "stop":
                        _pausedByCentral = true;
                        await PersistCentralPauseAsync(command.CommandType);
                        if (_bootstrap is not null) ApplyBootstrap(_bootstrap, updateOperationHint: false, allowCapture: _captureAllowedByConnection);
                        else UpdateQueueActionAvailability();
                        OperationHint.Text = command.CommandType == "stop" ? "中央管理端已停止新的现场操作。" : "中央管理端已暂停现场操作。";
                        break;
                    case "resume":
                        _pausedByCentral = false;
                        await PersistCentralPauseAsync(null);
                        if (_bootstrap is not null) ApplyBootstrap(_bootstrap, updateOperationHint: false, allowCapture: _captureAllowedByConnection);
                        OperationHint.Text = "中央管理端已恢复现场操作。";
                        break;
                    case "call_next":
                        await CallSelectedStudentAsync();
                        break;
                    case "recall":
                        var recallEntry = FieldDeviceCommandPolicy.ResolveQueueTarget(command.Payload, _bootstrap?.Queue ?? []);
                        if (recallEntry is null || EffectiveQueueStatus(recallEntry) != "called")
                        {
                            failed = true;
                            OperationHint.Text = "收到再次提醒指令，但目标学生已不在本站的已叫号队列；请刷新名单并由后台核查。";
                            break;
                        }
                        RefreshQueueDisplay(recallEntry.StudentId);
                        System.Media.SystemSounds.Exclamation.Play();
                        OperationHint.Text = $"后台再次提醒：请呼叫 {recallEntry.StudentName}（{recallEntry.ClassName}）前往本站，并核验身份后签到。";
                        break;
                    default:
                        failed = true;
                        OperationHint.Text = $"收到暂不支持的中央指令：{command.CommandType}。";
                        break;
                }
            }
            catch (Exception error)
            {
                failed = true;
                OperationHint.Text = $"执行中央指令失败：{error.Message}";
            }
            await _api.AcknowledgeCommandAsync(command.Id, failed, CancellationToken.None);
        }
    }

    private void QueueList_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        var entry = SelectedQueueEntry();
        if (entry is null)
        {
            SelectedStudentAvatar.Text = "—";
            SelectedStudentName.Text = "请从左侧选择";
            SelectedStudentClass.Text = "候测名单将在这里显示";
            SelectedStudentIdentity.Text = "选择后显示学籍身份信息";
            SelectedStudentNote.Text = string.Empty;
            SelectedStudentNotePanel.Visibility = System.Windows.Visibility.Collapsed;
            SelectedStudentStatus.Text = "未选择";
            UpdateProgressIndicator(string.Empty);
            UpdateQueueActionAvailability();
            return;
        }
        SelectedStudentAvatar.Text = string.IsNullOrWhiteSpace(entry.StudentName) ? "学" : entry.StudentName[..1];
        SelectedStudentName.Text = entry.StudentName;
        var timing = FieldQueueTimingPolicy.Describe(EffectiveQueueStatus(entry), entry.StateAgeSeconds, entry.CalledOverdue, entry.TimingSeverity);
        SelectedStudentClass.Text = $"{entry.ClassName} · 队列序号 {entry.QueueOrder} · {timing.Label}";
        SelectedStudentIdentity.Text = StudentIdentityText(entry);
        SelectedStudentNote.Text = string.IsNullOrWhiteSpace(entry.Note) ? string.Empty : $"现场说明：{entry.Note.Trim()}";
        SelectedStudentNotePanel.Visibility = string.IsNullOrWhiteSpace(entry.Note) ? System.Windows.Visibility.Collapsed : System.Windows.Visibility.Visible;
        SelectedStudentStatus.Text = EffectiveQueueStatus(entry) switch
        {
            "called" => timing.IsOverdue ? "叫号超时" : "已叫号",
            "checked_in" => "已确认",
            "testing" => "采集中",
            "completed" => "已完成",
            "retest" => "待重测",
            "absent" => "缺席",
            "skipped" => "已跳过",
            "paused" => "已暂停",
            _ => "候测"
        };
        UpdateProgressIndicator(EffectiveQueueStatus(entry));
        UpdateQueueActionAvailability();
    }

    private string EffectiveQueueStatus(QueueEntry entry) => _localQueueStatuses.TryGetValue(entry.Id, out var localStatus) ? localStatus : entry.Status;

    private QueueEntry? SelectedQueueEntry() => (QueueList?.SelectedItem as QueueDisplayEntry)?.Entry;

    private bool AssignedToCurrentStation(QueueEntry? entry) =>
        entry is not null && _bootstrap?.Station is not null && string.Equals(entry.StationId, _bootstrap.Station.Id, StringComparison.Ordinal);

    private static string StudentIdentityText(QueueEntry entry) =>
        $"学籍号 {entry.StudentNo ?? "待补"} · {entry.Gender ?? "性别待补"} · 出生 {entry.BirthDate?.ToString("yyyy-MM-dd") ?? "待补"}";

    private static bool StationSupportsTask(FieldStation? station, FieldTask? task)
    {
        if (station is null || task is null || task.Items.Count == 0) return false;
        if (string.IsNullOrWhiteSpace(station.ItemCode)) return true;
        return task.Items.Count == 1 && string.Equals(task.Items[0], station.ItemCode, StringComparison.Ordinal);
    }

    private static string QueueStatusLabel(string status) => status switch
    {
        "waiting" => "候测",
        "called" => "已叫号",
        "checked_in" => "已签到",
        "testing" => "测试中",
        "completed" => "已完成",
        "absent" => "缺席",
        "skipped" => "已跳过",
        "paused" => "已暂停",
        "retest" => "待重测",
        "cancelled" => "已取消",
        _ => status
    };

    private void RefreshQueueDisplay(string? preserveStudentId = null)
    {
        if (QueueList is null || _bootstrap is null) return;
        preserveStudentId ??= SelectedQueueEntry()?.StudentId;
        var filter = (QueueStatusFilter?.SelectedItem as System.Windows.Controls.ComboBoxItem)?.Tag?.ToString() ?? "active";
        var query = QueueSearchTextBox?.Text?.Trim() ?? string.Empty;
        var activeStatuses = new[] { "waiting", "called", "checked_in", "testing", "retest" };
        var exceptionStatuses = new[] { "retest", "absent", "skipped", "paused", "cancelled" };
        var all = _bootstrap.Queue.Select(entry =>
        {
            var status = EffectiveQueueStatus(entry);
            var timing = FieldQueueTimingPolicy.Describe(status, entry.StateAgeSeconds, entry.CalledOverdue, entry.TimingSeverity);
            return new QueueDisplayEntry(entry, status, timing.IsOverdue && status == "called" ? "叫号超时" : QueueStatusLabel(status), timing);
        }).ToList();
        var visible = all.Where(item => filter switch
        {
            "active" => activeStatuses.Contains(item.Status),
            "timing" => item.Timing.IsOverdue,
            "exception" => exceptionStatuses.Contains(item.Status),
            "completed" => item.Status == "completed",
            _ => true
        }).Where(item => string.IsNullOrWhiteSpace(query) || $"{item.StudentName}{item.ClassName}{item.Entry.StudentNo}".Contains(query, StringComparison.OrdinalIgnoreCase))
            .OrderBy(item => FieldQueueTimingPolicy.OperationalPriority(item.Status, item.Timing))
            .ThenByDescending(item => item.Timing.IsOverdue ? item.Timing.ElapsedMinutes : -1)
            .ThenBy(item => item.QueueOrder)
            .ToList();
        var rosterStatus = FieldRosterStatusPolicy.Describe(_bootstrap.Task is not null, _bootstrap.Station is not null, _bootstrap.QueueSummary, all.Count);
        QueueCoverageText.Text = rosterStatus.CoverageText;
        var nextEntry = FieldQueueAttentionPolicy.SelectNextWaiting(_bootstrap.Queue, _bootstrap.Station?.Id);
        var next = nextEntry is null ? null : all.FirstOrDefault(item => item.Entry.Id == nextEntry.Id);
        NextStudentText.Text = next is null ? "当前没有待叫号学生" : next.Status == "retest" ? $"{next.StudentName} · 补测 · {next.ClassName} · {next.Timing.Label}" : $"{next.StudentName} · {next.ClassName} · {next.Timing.Label}";
        SelectNextStudentButton.IsEnabled = next is not null && _activeClientSessionId is null && _interruptedCapture is null;
        WaitingCountText.Text = all.Count(item => item.Status is "waiting" or "retest").ToString();
        ActiveCountText.Text = all.Count(item => item.Status is "called" or "checked_in" or "testing").ToString();
        CompletedCountText.Text = all.Count(item => item.Status == "completed").ToString();
        ExceptionCountText.Text = all.Count(item => item.Status is "retest" or "absent" or "skipped" or "paused" or "cancelled").ToString();
        QueueList.ItemsSource = visible;
        QueueCountText.Text = visible.Count == all.Count ? $"{all.Count} 人" : $"{visible.Count}/{all.Count} 人";
        QueueEmptyState.Visibility = visible.Count == 0 ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        QueueEmptyTitle.Text = all.Count == 0 ? rosterStatus.EmptyTitle : "没有匹配的学生";
        QueueEmptyDetail.Text = all.Count == 0 ? rosterStatus.EmptyDetail : "请调整搜索词或状态筛选";
        QueueEmptyActionButton.Tag = all.Count == 0 ? "refresh" : "clear";
        QueueEmptyActionButton.Content = all.Count == 0 ? "刷新任务和名单" : "清除搜索和筛选";
        var selectedIndex = preserveStudentId is null ? visible.FindIndex(item => item.Status is "testing" or "checked_in" or "called") : visible.FindIndex(item => item.StudentId == preserveStudentId);
        QueueList.SelectedIndex = visible.Count == 0 ? -1 : selectedIndex >= 0 ? selectedIndex : 0;
    }

    private void QueueSearchTextBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) => RefreshQueueDisplay();

    private void QueueStatusFilter_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e) => RefreshQueueDisplay();

    private void SelectNextStudentButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_bootstrap is null) return;
        if (_activeClientSessionId is not null || _interruptedCapture is not null)
        {
            OperationHint.Text = "请先完成或处理中断的当前采集，再定位下一位学生。";
            return;
        }
        var next = FieldQueueAttentionPolicy.SelectNextWaiting(_bootstrap.Queue, _bootstrap.Station?.Id);
        if (next is null)
        {
            OperationHint.Text = "本站当前没有待叫号或待重测学生。";
            return;
        }
        QueueSearchTextBox.Text = string.Empty;
        QueueStatusFilter.SelectedIndex = 0;
        RefreshQueueDisplay(next.StudentId);
        if (QueueList.SelectedItem is not null) QueueList.ScrollIntoView(QueueList.SelectedItem);
        OperationHint.Text = $"已定位下一位：{next.StudentName}（{next.ClassName}）。请核对名单后点击“叫号”。";
    }

    private async void TaskSelector_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (_taskSelectorUpdating || _taskSwitchBusy || TaskSelector.SelectedItem is not FieldTaskOption selected || selected.Id == _bootstrap?.Task?.Id) return;
        if (_activeClientSessionId is not null || _interruptedCapture is not null)
        {
            OperationHint.Text = "当前有未结束或待恢复的采集，处理完成后才能切换测评任务。";
            _taskSelectorUpdating = true;
            TaskSelector.SelectedValue = _bootstrap?.Task?.Id;
            _taskSelectorUpdating = false;
            return;
        }
        var previousTaskId = _selectedTaskId;
        _taskSwitchBusy = true;
        TaskSelector.IsEnabled = false;
        _selectedTaskId = selected.Id;
        try
        {
            if (_outbox is not null) await _outbox.SaveSnapshotAsync("selected-task", JsonSerializer.Serialize(selected.Id, SnapshotJson), CancellationToken.None);
            OperationHint.Text = $"正在切换到“{selected.Title}”并下载对应学生名单…";
            await RefreshBootstrapAsync();
            OperationHint.Text = $"已切换到“{selected.Title}”，名单与规则已更新。";
        }
        catch (Exception error)
        {
            _selectedTaskId = previousTaskId;
            if (_outbox is not null)
            {
                if (previousTaskId is null) await _outbox.DeleteSnapshotAsync("selected-task", CancellationToken.None);
                else await _outbox.SaveSnapshotAsync("selected-task", JsonSerializer.Serialize(previousTaskId, SnapshotJson), CancellationToken.None);
            }
            OperationHint.Text = $"任务切换失败：{error.Message}";
            _taskSelectorUpdating = true;
            TaskSelector.SelectedValue = _bootstrap?.Task?.Id;
            _taskSelectorUpdating = false;
        }
        finally
        {
            _taskSwitchBusy = false;
            TaskSelector.IsEnabled = (_bootstrap?.AvailableTasks?.Count ?? 0) > 1 && _activeClientSessionId is null && _interruptedCapture is null;
        }
    }

    private void UpdateProgressIndicator(string status)
    {
        var (doneCount, activeIndex) = status switch
        {
            "waiting" or "retest" => (0, 0),
            "called" => (1, 1),
            "checked_in" => (2, 2),
            "testing" or "paused" => (2, 2),
            "completed" => (4, -1),
            _ => (0, -1)
        };
        var dots = new[] { StepCallDot, StepCheckInDot, StepCaptureDot, StepCompleteDot };
        var labels = new[] { StepCallText, StepCheckInText, StepCaptureText, StepCompleteText };
        for (var index = 0; index < dots.Length; index++)
        {
            dots[index].Fill = index < doneCount ? StepDoneBrush : index == activeIndex ? StepActiveBrush : StepIdleBrush;
            labels[index].Foreground = index < doneCount || index == activeIndex ? StepTextActiveBrush : StepTextIdleBrush;
        }
    }

    private async Task RefreshSyncStatusAsync()
    {
        if (_outbox is null || SyncStatusText is null) return;
        var summary = await _outbox.GetStatusSummaryAsync(CancellationToken.None);
        var text = summary.ConflictCount > 0 ? $"{summary.ConflictCount} 条冲突" : summary.PendingCount > 0 ? $"待同步 {summary.PendingCount} 条" : "已全部同步";
        var brush = summary.ConflictCount > 0
            ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(184, 117, 8))
            : (System.Windows.Media.Brush)FindResource("Green");
        if (Dispatcher.CheckAccess()) { SyncStatusText.Text = text; SyncStatusText.Foreground = brush; }
        else await Dispatcher.InvokeAsync(() => { SyncStatusText.Text = text; SyncStatusText.Foreground = brush; });
    }

    private async Task RestorePendingQueueTransitionsAsync()
    {
        if (_pendingQueueStateRestored || _outbox is null) return;
        var transitions = await _outbox.GetPendingQueueTransitionsAsync(CancellationToken.None);
        foreach (var transition in transitions)
        {
            _localQueueStatuses[transition.QueueEntryId] = transition.Status;
            _queueVersionChain.RestoreTransition(transition.QueueEntryId, transition.ExpectedVersion);
        }
        _pendingQueueStateRestored = true;
    }

    private async Task<bool> ReconcileQueueSyncConflictsAsync(bool showOperatorHint)
    {
        if (_outbox is null) return false;
        var conflicts = await _outbox.GetConflictedQueueTransitionsAsync(CancellationToken.None);
        if (conflicts.Count == 0) return false;
        foreach (var queueEntryId in conflicts.Select(item => item.QueueEntryId).Distinct(StringComparer.Ordinal))
        {
            _localQueueStatuses.Remove(queueEntryId);
            _queueVersionChain.Remove(queueEntryId);
        }
        RefreshQueueDisplay(SelectedQueueEntry()?.StudentId);
        if (showOperatorHint && _activeClientSessionId is null && _interruptedCapture is null && !_pausedByCentral && !_localEmergencyStop)
        {
            var summary = await _outbox.GetConflictSummaryAsync(CancellationToken.None);
            OperationHint.Text = $"发现 {summary.Count} 条需人工处理的同步冲突：{summary.LastError}。已恢复显示中央名单；请在后台“现场运行 → 同步冲突工作台”核对，原始本地事件会保留到后台确认。";
        }
        return true;
    }

    private void UpdateQueueActionAvailability()
    {
        var entry = SelectedQueueEntry();
        var status = entry is null ? string.Empty : EffectiveQueueStatus(entry);
        var assignedToCurrentStation = AssignedToCurrentStation(entry);
        var runtimeConfigurationLocked = _activeClientSessionId is not null || _interruptedCapture is not null;
        if (SelectNextStudentButton is not null)
            SelectNextStudentButton.IsEnabled = !runtimeConfigurationLocked && _bootstrap is not null
                && FieldQueueAttentionPolicy.SelectNextWaiting(_bootstrap.Queue, _bootstrap.Station?.Id) is not null;
        var canOperate = entry is not null && assignedToCurrentStation && !_pausedByCentral && !_localEmergencyStop && _activeClientSessionId is null && _interruptedCapture is null;
        var stationTaskCompatible = StationSupportsTask(_bootstrap?.Station, _bootstrap?.Task);
        var callReady = _captureAllowedByConnection && _bootstrap?.Readiness.Ready == true && stationTaskCompatible && _captureAdapter?.IsAvailable == true;
        CallNextButton.IsEnabled = canOperate && callReady && status is "waiting" or "retest";
        CheckInButton.IsEnabled = canOperate && status == "called";
        StartCaptureButton.IsEnabled = canOperate && _captureAllowedByConnection && _bootstrap?.Readiness.Ready == true && stationTaskCompatible && status == "checked_in";
        CompleteCaptureButton.IsEnabled = _activeClientSessionId is not null && !_localEmergencyStop;
        RetestCaptureButton.IsEnabled = _activeClientSessionId is not null && !_localEmergencyStop;
        AbsentButton.IsEnabled = canOperate && status is "waiting" or "called" or "checked_in" or "retest";
        RecoverInterruptedButton.IsEnabled = _interruptedCapture is not null && _activeClientSessionId is null;
        var presentation = FieldOperatorWorkflow.Describe(
            status,
            entry is not null,
            _pausedByCentral,
            _localEmergencyStop,
            _activeClientSessionId is not null,
            _interruptedCapture is not null,
            _captureAllowedByConnection,
            _bootstrap?.Readiness.Ready == true && stationTaskCompatible,
            _captureAdapter?.IsAvailable == true,
            _bootstrap?.Readiness.Blockers.FirstOrDefault());
        var stationPresentation = FieldStationStatusPolicy.Describe(_bootstrap?.Station?.Status, _bootstrap?.Station?.StatusReason);
        WorkflowActionTitle.Text = presentation.ActionTitle;
        WorkflowActionDetail.Text = presentation.ActionDetail;
        if (stationPresentation.BlocksOperations && !_localEmergencyStop)
        {
            WorkflowActionTitle.Text = stationPresentation.Title;
            WorkflowActionDetail.Text = $"{stationPresentation.Detail} {stationPresentation.RecoveryHint}";
        }
        if (entry is not null && !assignedToCurrentStation)
        {
            WorkflowActionTitle.Text = "学生尚未分配到本站";
            WorkflowActionDetail.Text = "这是旧名单或未分配记录；请恢复中央连接并在后台重新分流，本站不会执行叫号、签到或采集。";
        }
        RecoverInterruptedButton.Content = "处理中断并安排补测";
        if (_captureDetachedFromTask && _interruptedCapture is not null)
        {
            WorkflowActionTitle.Text = "先封存旧任务采集记录";
            WorkflowActionDetail.Text = $"后台已关闭或移除原任务，但本机保留了 {_interruptedCapture.StudentName} 的中断采集。封存前禁止切换和操作新任务。";
            RecoverInterruptedButton.Content = "封存旧任务采集记录";
        }
        if (entry is not null && status == "called")
        {
            var timing = FieldQueueTimingPolicy.Describe(status, entry.StateAgeSeconds, entry.CalledOverdue, entry.TimingSeverity);
            if (timing.IsOverdue)
            {
                WorkflowActionTitle.Text = "叫号后仍未签到";
                WorkflowActionDetail.Text = $"已等待 {Math.Max(2, timing.ElapsedMinutes)} 分钟；请再次口头呼叫，仍未到场可标记缺席。";
            }
            AbsentButton.Content = timing.IsOverdue ? "再次呼叫后确认缺席" : "标记缺席";
        }
        else AbsentButton.Content = "标记缺席";
        CaptureStageIcon.Text = presentation.StageIcon;
        CaptureStageTitle.Text = presentation.StageTitle;
        CaptureStageDetail.Text = presentation.StageDetail;
        CallNextButton.Visibility = presentation.ShowCall ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        CheckInButton.Visibility = presentation.ShowCheckIn ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        StartCaptureButton.Visibility = presentation.ShowStartCapture ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        CompleteCaptureButton.Visibility = presentation.ShowComplete ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        RetestCaptureButton.Visibility = presentation.ShowRetest ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        RecoverInterruptedButton.Visibility = presentation.ShowRecover ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        AbsentButton.Visibility = presentation.ShowAbsent ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        ActionEmptyText.Visibility = presentation.HasVisibleAction ? System.Windows.Visibility.Collapsed : System.Windows.Visibility.Visible;
        var recovery = FieldReadinessRecoveryPolicy.Describe(
            _bootstrap?.Task is not null,
            _captureAllowedByConnection,
            _pausedByCentral,
            _localEmergencyStop,
            _captureAdapter?.IsAvailable == true,
            stationTaskCompatible,
            _bootstrap?.Readiness.Ready == true,
            _bootstrap?.Station?.Status);
        var showRecoveryAction = recovery.HasAction && !runtimeConfigurationLocked;
        ReadinessActionButton.Tag = recovery.Action;
        ReadinessActionButton.Content = recovery.Label;
        ReadinessActionButton.Visibility = showRecoveryAction ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        ReadinessActionHint.Text = recovery.Hint;
        ReadinessActionHint.Visibility = showRecoveryAction && !string.IsNullOrWhiteSpace(recovery.Hint) ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        if (TaskSelector is not null) TaskSelector.IsEnabled = (_bootstrap?.AvailableTasks?.Count ?? 0) > 1 && _activeClientSessionId is null && _interruptedCapture is null && !_taskSwitchBusy;
        if (ConnectionSettingsButton is not null) ConnectionSettingsButton.IsEnabled = !runtimeConfigurationLocked;
        if (HeaderConnectionButton is not null) HeaderConnectionButton.IsEnabled = !runtimeConfigurationLocked;
        if (CaptureSettingsButton is not null) CaptureSettingsButton.IsEnabled = !runtimeConfigurationLocked;
        if (CaptureModeBadge is not null)
        {
            CaptureModeBadge.Text = _activeClientSessionId is not null
                ? "采集中 · 配置已锁定"
                : _interruptedCapture is not null
                    ? "中断待处理 · 配置已锁定"
                    : _captureAdapter?.IsAvailable == true ? $"已认证 · {_captureAdapter.AdapterName}" : "设备未接入";
            CaptureModeBadge.Foreground = runtimeConfigurationLocked || _captureAdapter?.IsAvailable == true
                ? StepDoneBrush
                : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(240, 184, 74));
        }
    }

    private async Task RestoreInterruptedCaptureAsync()
    {
        if (_outbox is null || _bootstrap is null || _activeClientSessionId is not null) return;
        var snapshot = await _outbox.ReadSnapshotAsync("active-capture", CancellationToken.None);
        if (snapshot is null)
        {
            _interruptedCapture = null;
            _captureDetachedFromTask = false;
            UpdateQueueActionAvailability();
            return;
        }
        InterruptedCaptureState? interrupted;
        try { interrupted = JsonSerializer.Deserialize<InterruptedCaptureState>(snapshot.Json, SnapshotJson); }
        catch (JsonException) { interrupted = null; }
        if (interrupted is null)
        {
            await _outbox.DeleteSnapshotAsync("active-capture", CancellationToken.None);
            _interruptedCapture = null;
            _captureDetachedFromTask = false;
            UpdateQueueActionAvailability();
            return;
        }
        var entry = _bootstrap.Queue.FirstOrDefault(item => item.Id == interrupted.QueueEntryId || item.StudentId == interrupted.StudentId);
        var centralStatus = entry is null ? string.Empty : EffectiveQueueStatus(entry);
        var disposition = InterruptedCapturePolicy.Decide(
            interrupted,
            _bootstrap.Task?.Id,
            centralStatus,
            await _outbox.HasPendingCompletionAsync(interrupted.ClientSessionId, CancellationToken.None));
        if (disposition is InterruptedCaptureDisposition.DiscardAfterDurableCompletion or InterruptedCaptureDisposition.DiscardAfterCentralResolution)
        {
            await _outbox.DeleteSnapshotAsync("active-capture", CancellationToken.None);
            _interruptedCapture = null;
            _captureDetachedFromTask = false;
            if (entry is not null && centralStatus == "retest")
                OperationHint.Text = $"后台已将 {interrupted.StudentName} 的异常会话安全收口并转入补测，本机旧采集上下文已清理。请按补测队列重新叫号。";
            UpdateQueueActionAvailability();
            return;
        }
        _interruptedCapture = interrupted;
        _captureDetachedFromTask = disposition == InterruptedCaptureDisposition.RetireOutsideCurrentTask;
        if (_captureDetachedFromTask)
        {
            SelectedStudentStatus.Text = "旧任务采集中断";
            OperationHint.Text = $"后台已关闭或移除原任务，但本机检测到 {interrupted.StudentName} 在 {interrupted.StartedAt.ToLocalTime():MM-dd HH:mm} 开始的未收尾采集。旧记录尚未封存，当前任务已锁定；请点击“封存旧任务采集记录”。";
            ReadinessTitle.Text = "旧任务仍有本地采集记录";
            ReadinessDetail.Text = "客户端已停止采集设备，并禁止新任务叫号、签到和采集。封存后将同步原始事实；若后台显示冲突，请在同步冲突工作台确认。";
            ReadinessPanel.Background = (System.Windows.Media.Brush)FindResource("AmberSoft");
            ReadinessPanel.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(241, 217, 158));
            ReadinessTitle.Foreground = (System.Windows.Media.Brush)FindResource("Amber");
            UpdateQueueActionAvailability();
            return;
        }
        _localQueueStatuses[entry!.Id] = "testing";
        RefreshQueueDisplay(entry.StudentId);
        SelectedStudentStatus.Text = "采集中断";
        OperationHint.Text = $"检测到 {interrupted.StudentName} 在 {interrupted.StartedAt.ToLocalTime():MM-dd HH:mm} 开始的采集异常中断。原硬件上下文无法安全恢复，请点击“处理中断采集”安排补测。";
        UpdateQueueActionAvailability();
    }

    private async Task QueueTransitionAsync(QueueEntry entry, string status, string note, bool identityVerified = false)
    {
        var expectedVersion = _queueVersionChain.GetExpectedVersion(entry);
        await EnqueueAsync("queue.transition", new
        {
            taskId = entry.TaskId,
            queueEntryId = entry.Id,
            status,
            expectedVersion,
            happenedAt = DateTimeOffset.UtcNow,
            note,
            identityVerified
        });
        _queueVersionChain.MarkTransitionQueued(entry.Id, expectedVersion);
        _localQueueStatuses[entry.Id] = status;
        RefreshQueueDisplay(entry.StudentId);
    }

    private async Task RefreshQueueFromCentralAsync()
    {
        RefreshQueueButton.IsEnabled = false;
        QueueEmptyActionButton.IsEnabled = false;
        try
        {
            OperationHint.Text = "正在从中央服务刷新任务和学生名单…";
            await RefreshBootstrapAsync();
        }
        catch (Exception error)
        {
            ConnectionStatus.Text = "连接失败";
            ConnectionDot.Fill = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(226, 93, 93));
            HeaderConnectionButton.Content = "恢复连接";
            ReadinessTitle.Text = "名单刷新失败";
            ReadinessDetail.Text = error.Message;
            OperationHint.Text = $"名单刷新失败：{error.Message}";
        }
        finally
        {
            RefreshQueueButton.IsEnabled = true;
            QueueEmptyActionButton.IsEnabled = true;
        }
    }

    private async void RefreshQueueButton_Click(object sender, System.Windows.RoutedEventArgs e) => await RefreshQueueFromCentralAsync();

    private async void QueueEmptyActionButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (QueueEmptyActionButton.Tag?.ToString() == "clear")
        {
            QueueSearchTextBox.Text = string.Empty;
            QueueStatusFilter.SelectedIndex = 0;
            RefreshQueueDisplay();
            return;
        }
        await RefreshQueueFromCentralAsync();
    }

    private async void ReadinessActionButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        switch (ReadinessActionButton.Tag?.ToString())
        {
            case "connection":
                ConnectionSettingsButton.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                break;
            case "adapter":
                CaptureSettingsButton.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                break;
            case "emergency":
                EmergencyStopButton.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                break;
            case "refresh":
                await RefreshQueueFromCentralAsync();
                break;
        }
    }

    private void Window_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (System.Windows.Input.Keyboard.FocusedElement is System.Windows.Controls.Primitives.TextBoxBase or System.Windows.Controls.ComboBox) return;
        System.Windows.Controls.Button? target = e.Key switch
        {
            System.Windows.Input.Key.F5 => RefreshQueueButton,
            System.Windows.Input.Key.F2 => CallNextButton,
            System.Windows.Input.Key.F3 => CheckInButton,
            System.Windows.Input.Key.F4 => StartCaptureButton,
            System.Windows.Input.Key.F6 => SelectNextStudentButton,
            System.Windows.Input.Key.F8 => CompleteCaptureButton,
            _ => null
        };
        if (target is null || !target.IsEnabled) return;
        target.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
        e.Handled = true;
    }

    private async void CallNextButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        await CallSelectedStudentAsync();
    }

    private async Task CallSelectedStudentAsync()
    {
        if (_interruptedCapture is not null) { OperationHint.Text = _captureDetachedFromTask ? "请先封存旧任务的中断采集记录，再操作新任务。" : "请先处理中断采集，再继续叫号。"; return; }
        var entry = SelectedQueueEntry() ?? (_bootstrap is not null && _bootstrap.Queue.Count > 0 ? _bootstrap.Queue[0] : null);
        if (entry is null || _outbox is null) { OperationHint.Text = "当前没有可叫号的候测学生，请先刷新名单。"; return; }
        if (!AssignedToCurrentStation(entry)) { OperationHint.Text = "该学生尚未分配到本站，不能叫号；请在后台重新分流后刷新名单。"; return; }
        if (EffectiveQueueStatus(entry) is not ("waiting" or "retest")) { OperationHint.Text = "当前学生不能再次叫号，请先刷新名单或处理现场状态。"; return; }
        if (!_captureAllowedByConnection) { OperationHint.Text = "中央服务尚未连接，恢复连接并重新确认开测条件后才能叫号。"; return; }
        if (_captureAdapter is null || !_captureAdapter.IsAvailable) { OperationHint.Text = _captureAdapter?.UnavailableReason ?? "采集设备尚未接入，通过设备自检前不能叫号。"; return; }
        if (_bootstrap?.Readiness.Ready != true) { OperationHint.Text = $"测试点尚未具备叫号条件：{string.Join("；", _bootstrap?.Readiness.Blockers ?? [])}"; return; }
        if (!StationSupportsTask(_bootstrap.Station, _bootstrap.Task)) { OperationHint.Text = "当前测试点与任务项目不匹配，请在后台调整测试能力后刷新。"; return; }
        await QueueTransitionAsync(entry, "called", "Windows 场地端叫号");
        SelectedStudentStatus.Text = "已叫号";
        UpdateQueueActionAvailability();
        OperationHint.Text = $"已叫号：{entry.StudentName}。请完成身份核验并点击“确认签到”。";
    }

    private async void CheckInButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        var entry = SelectedQueueEntry();
        if (entry is null) { OperationHint.Text = "请先选择已叫号的学生。"; return; }
        if (!AssignedToCurrentStation(entry)) { OperationHint.Text = "该学生不属于本站，不能签到；请刷新名单并核对后台分流。"; return; }
        if (EffectiveQueueStatus(entry) != "called") { OperationHint.Text = "请先叫号，再确认学生签到。"; return; }
        var identityComplete = !string.IsNullOrWhiteSpace(entry.StudentNo) && entry.BirthDate is not null;
        var confirmation = System.Windows.MessageBox.Show(this,
            $"请当面核对学生身份：\n\n姓名：{entry.StudentName}\n班级：{entry.ClassName}\n学籍号：{entry.StudentNo ?? "待补"}\n性别：{entry.Gender ?? "待补"}\n出生日期：{entry.BirthDate?.ToString("yyyy-MM-dd") ?? "待补"}\n\n{(identityComplete ? "确认本人、名单或腕带信息完全一致后再继续。" : "身份字段不完整，请使用学校现场名册进行二次核对后再继续。")}",
            "学生身份核验", System.Windows.MessageBoxButton.YesNo, identityComplete ? System.Windows.MessageBoxImage.Question : System.Windows.MessageBoxImage.Warning);
        if (confirmation != System.Windows.MessageBoxResult.Yes) { OperationHint.Text = $"未确认 {entry.StudentName} 身份，签到未提交。"; return; }
        await QueueTransitionAsync(entry, "checked_in", "Windows 场地端已核对姓名、班级、学籍号和出生日期并确认签到", identityVerified: true);
        SelectedStudentStatus.Text = "已签到";
        UpdateQueueActionAvailability();
        OperationHint.Text = $"已确认 {entry.StudentName} 身份。设备就绪后即可开始正式采集。";
    }

    private async void AbsentButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        var entry = SelectedQueueEntry();
        if (entry is null) { OperationHint.Text = "请先选择需要处理的学生。"; return; }
        var timing = FieldQueueTimingPolicy.Describe(EffectiveQueueStatus(entry), entry.StateAgeSeconds, entry.CalledOverdue, entry.TimingSeverity);
        var confirmationText = EffectiveQueueStatus(entry) == "called" && timing.IsOverdue
            ? $"已再次口头呼叫 {entry.StudentName}，并确认学生仍未到场？\n\n确认后将标记缺席并移出当前候测流程；该操作可在后台恢复。"
            : $"确认将 {entry.StudentName} 标记为缺席？该操作可在后台恢复候测。";
        var confirmation = System.Windows.MessageBox.Show(this, confirmationText, "确认学生缺席", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Warning);
        if (confirmation != System.Windows.MessageBoxResult.Yes) return;
        await QueueTransitionAsync(entry, "absent", EffectiveQueueStatus(entry) == "called" && timing.IsOverdue ? $"Windows 场地端再次呼叫后确认缺席；{timing.Label}" : "Windows 场地端标记缺席");
        SelectedStudentStatus.Text = "缺席";
        UpdateQueueActionAvailability();
        OperationHint.Text = $"{entry.StudentName} 已标记为缺席，可在后台恢复候测或安排补测。";
    }

    private async void StartCaptureButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        var entry = SelectedQueueEntry();
        if (_localEmergencyStop) { OperationHint.Text = "本地紧急停止尚未解除，不能开始采集。"; return; }
        if (entry is null || _bootstrap?.Task is null || _outbox is null) { OperationHint.Text = "请先加载任务并选择一名候测学生。"; return; }
        if (!AssignedToCurrentStation(entry)) { OperationHint.Text = "该学生不属于本站，不能开始采集；请刷新名单并核对后台分流。"; return; }
        if (!_bootstrap.Readiness.Ready) { OperationHint.Text = $"当前不能开始采集：{string.Join("；", _bootstrap.Readiness.Blockers)}"; return; }
        if (!StationSupportsTask(_bootstrap.Station, _bootstrap.Task)) { OperationHint.Text = "当前测试点与任务项目不匹配，请在后台调整测试能力后刷新。"; return; }
        if (EffectiveQueueStatus(entry) != "checked_in") { OperationHint.Text = "请先叫号并确认学生签到，再开始采集。"; return; }
        if (_activeClientSessionId is not null) { OperationHint.Text = "当前已有正在进行的测试，请先完成设备采集。"; return; }
        if (_captureAdapter is null || !_captureAdapter.IsAvailable) { OperationHint.Text = _captureAdapter?.UnavailableReason ?? "认证采集适配器不可用。"; return; }
        if (_bootstrap.Calibration is not null)
        {
            var calibration = await _captureAdapter.CheckCalibrationAsync(_bootstrap.Calibration, CancellationToken.None);
            if (!calibration.Passed) { OperationHint.Text = $"标定复核未通过：{calibration.Message}"; return; }
        }
        var clientSessionId = $"field-{Guid.NewGuid():N}";
        var adapterName = _captureAdapter.AdapterName;
        if (string.IsNullOrWhiteSpace(adapterName)) { OperationHint.Text = "认证采集适配器未报告版本名称。"; return; }
        var startedAt = DateTimeOffset.UtcNow;
        var interruptedState = new InterruptedCaptureState(Guid.NewGuid(), clientSessionId, entry.Id, entry.StudentId, entry.StudentName, _bootstrap.Task.Id, adapterName, startedAt);
        await _outbox.SaveSnapshotAsync("active-capture", JsonSerializer.Serialize(interruptedState, SnapshotJson), CancellationToken.None);
        ICaptureRun? captureRun = null;
        try
        {
            captureRun = await _captureAdapter.StartAsync(new CaptureRequest(clientSessionId, entry, _bootstrap.Task, _bootstrap.Calibration), CancellationToken.None);
            await EnqueueAsync("session.open", new
            {
                clientSessionId,
                taskId = _bootstrap.Task.Id,
                studentId = entry.StudentId,
                startedAt,
                algorithmVersion = adapterName,
                summary = new { captureMode = "certified-adapter", adapter = adapterName, station = _bootstrap.Station?.StationCode, readiness = "verified-at-bootstrap" }
            }, interruptedState.OpenEventId);
        }
        catch (Exception error)
        {
            try { await _captureAdapter.StopAsync(CancellationToken.None); } catch { }
            if (captureRun is not null) await captureRun.DisposeAsync();
            await _outbox.DeleteSnapshotAsync("active-capture", CancellationToken.None);
            OperationHint.Text = $"无法启动认证采集：{error.Message}";
            return;
        }
        _activeClientSessionId = clientSessionId;
        _activeEntry = entry;
        _activeCaptureRun = captureRun;
        _preparedCaptureResult = null;
        _captureEventCount = 0;
        ResetProtocolProgress(force: true);
        CaptureLiveEventTitle.Text = "等待采集设备首条反馈";
        CaptureLiveEventDetail.Text = $"{entry.StudentName} 已进入设备采集；动作事件保存后会立即显示。";
        CaptureLiveEventPanel.Visibility = System.Windows.Visibility.Visible;
        _captureEventsCancellation = new CancellationTokenSource();
        _captureEventsTask = PumpCaptureEventsAsync(captureRun, clientSessionId, _captureEventsCancellation.Token);
        _localQueueStatuses[entry.Id] = "testing";
        SelectedStudentStatus.Text = "采集中";
        UpdateQueueActionAvailability();
        OperationHint.Text = $"{entry.StudentName} 已进入认证采集流程。完成动作后由设备生成成绩。";
    }

    private async void CompleteCaptureButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_activeClientSessionId is null || _activeEntry is null || _activeCaptureRun is null || _captureAdapter is null || _outbox is null || _evidenceDirectory is null) { OperationHint.Text = "请先开始一场测试。"; return; }
        var managedEvidence = new List<PendingFieldEvidence>();
        var persisted = false;
        var synced = false;
        string? syncError = null;
        CompleteCaptureButton.IsEnabled = false;
        try
        {
            if (_preparedCaptureResult is null)
            {
                var adapterName = _captureAdapter.AdapterName ?? throw new InvalidOperationException("认证采集适配器未报告版本名称。");
                await _captureAdapter.StopAsync(CancellationToken.None);
                _captureEventsCancellation?.Cancel();
                if (_captureEventsTask is not null) await _captureEventsTask;
                var scores = await _activeCaptureRun.GetScoresAsync(CancellationToken.None);
                var localEvidence = await _activeCaptureRun.GetEvidenceAsync(CancellationToken.None);
                _protocolProgress = FieldProtocolProgressPolicy.ApplyScores(_protocolProgress, scores);
                RenderProtocolProgress();
                var assessment = CaptureCompletionPolicy.Evaluate(scores, localEvidence, _bootstrap?.Task?.Items);
                if (!assessment.CanSubmit)
                {
                    var blockers = string.Join("\n", assessment.Blockers.Select(item => $"• {item}"));
                    System.Windows.MessageBox.Show(this,
                        $"本次采集不能提交：\n\n{blockers}\n\n禁止使用人工分数替代设备结果。请检查设备后，点击“终止并安排补测”。",
                        "采集结果不完整", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Warning);
                    OperationHint.Text = $"{_activeEntry.StudentName} 的设备结果不完整，不能提交；请终止本次会话并安排补测。";
                    CompleteCaptureButton.IsEnabled = true;
                    return;
                }
                _preparedCaptureResult = new PreparedCaptureResult(adapterName, DateTimeOffset.UtcNow, scores, localEvidence, assessment);
            }

            var prepared = _preparedCaptureResult ?? throw new InvalidOperationException("采集结果尚未准备完成。");
            var scorePreview = string.Join("\n", prepared.Scores.Select(score => $"{score.Item}：{score.Score:0.0} 分 · 置信度 {score.Confidence:P0}"));
            var reviewNotice = prepared.Assessment.RequiresCentralReview
                ? $"\n\n以下项目低于 80% 置信度，提交后必须由后台核对证据：{string.Join("、", prepared.Assessment.LowConfidenceItems)}"
                : "\n\n全部项目达到自动通过置信度；后台仍可追溯证据。";
            var confirmation = System.Windows.MessageBox.Show(this,
                $"请核对 {_activeEntry.StudentName} 的设备成绩：\n\n{scorePreview}\n\n证据文件：{prepared.LocalEvidence.Count} 份{reviewNotice}\n\n确认无误后提交？选择“否”可返回现场核对，或使用“终止并安排补测”。",
                "核对并提交成绩", System.Windows.MessageBoxButton.YesNo,
                prepared.Assessment.RequiresCentralReview ? System.Windows.MessageBoxImage.Warning : System.Windows.MessageBoxImage.Information);
            if (confirmation != System.Windows.MessageBoxResult.Yes)
            {
                OperationHint.Text = $"{_activeEntry.StudentName} 的成绩尚未提交；请重新核对，确认异常时安排补测。";
                CompleteCaptureButton.IsEnabled = true;
                return;
            }

            managedEvidence.AddRange(await CopyEvidenceToManagedStorageAsync(_activeClientSessionId, prepared.LocalEvidence, _evidenceDirectory, CancellationToken.None));
            var scorePayload = JsonSerializer.SerializeToElement(prepared.Scores.Select(score => new { item = score.Item, score = score.Score, confidence = score.Confidence, note = score.Note, evidence = score.Evidence }));
            var summary = JsonSerializer.SerializeToElement(new
            {
                captureMode = "certified-adapter",
                adapter = prepared.AdapterName,
                operatorConfirmed = true,
                operatorConfirmedAt = DateTimeOffset.UtcNow,
                evidenceCount = managedEvidence.Count,
                requiresCentralReview = prepared.Assessment.RequiresCentralReview,
                lowConfidenceItems = prepared.Assessment.LowConfidenceItems
            });
            await _outbox.SavePendingCompletionAsync(new PendingFieldCompletion(Guid.NewGuid(), _activeClientSessionId, prepared.AdapterName, prepared.EndedAt, scorePayload, summary), managedEvidence, CancellationToken.None);
            persisted = true;
            try { await _outbox.DeleteSnapshotAsync("active-capture", CancellationToken.None); } catch { }
            synced = _sync is not null && await _sync.FlushAsync(CancellationToken.None);
        }
        catch (Exception error)
        {
            if (!persisted) DeleteManagedEvidenceCopies(managedEvidence.Select(item => item.LocalPath));
            if (!persisted)
            {
                OperationHint.Text = $"完成采集失败：{error.Message}";
                CompleteCaptureButton.IsEnabled = true;
                return;
            }
            syncError = error.Message;
        }
        var completedEntry = _activeEntry ?? throw new InvalidOperationException("当前学生上下文已丢失。");
        var requiresReview = _preparedCaptureResult?.Assessment.RequiresCentralReview == true;
        await _activeCaptureRun.DisposeAsync();
        _captureEventsCancellation?.Dispose();
        _captureEventsCancellation = null;
        _captureEventsTask = null;
        _activeCaptureRun = null;
        _preparedCaptureResult = null;
        OperationHint.Text = synced
            ? requiresReview
                ? $"{completedEntry.StudentName} 的成绩和 {managedEvidence.Count} 份证据已同步，低置信度项目正在等待后台复核。"
                : $"{completedEntry.StudentName} 的成绩和 {managedEvidence.Count} 份证据已同步。"
            : $"{completedEntry.StudentName} 的成绩和 {managedEvidence.Count} 份证据已安全保存在本机，联网后将自动补传。{(syncError is null ? string.Empty : $" 同步提示：{syncError}")}";
        SelectedStudentStatus.Text = requiresReview ? "已提交待复核" : "已提交";
        _localQueueStatuses[completedEntry.Id] = "completed";
        RefreshQueueDisplay();
        _activeClientSessionId = null;
        _activeEntry = null;
        _interruptedCapture = null;
        ResetCaptureLiveProgress();
        UpdateQueueActionAvailability();
        var nextStudent = _bootstrap?.Queue.FirstOrDefault(item => EffectiveQueueStatus(item) is "waiting" or "retest");
        if (nextStudent is not null) OperationHint.Text += $" 下一位：{nextStudent.StudentName}（{nextStudent.ClassName}）。";
        await RefreshSyncStatusAsync();
    }

    private async void RetestCaptureButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_activeClientSessionId is null || _activeEntry is null) { OperationHint.Text = "当前没有需要终止的采集。"; return; }
        var studentName = _activeEntry.StudentName;
        var confirmation = System.Windows.MessageBox.Show(this,
            $"确认终止 {studentName} 的本次采集并安排补测？\n\n本次设备成绩不会提交，后台会保留中止记录。",
            "终止并安排补测", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Warning);
        if (confirmation != System.Windows.MessageBoxResult.Yes) return;
        RetestCaptureButton.IsEnabled = false;
        try
        {
            var interrupted = await StopActiveCaptureAsync();
            if (interrupted is null) throw new InvalidOperationException("找不到当前采集上下文。");
            var synced = await QueueCaptureAbortAsync(interrupted, "现场操作员主动终止采集并安排补测", "operator_retest");
            OperationHint.Text = synced
                ? $"{studentName} 的本次采集已终止，并已加入补测队列。"
                : $"{studentName} 的终止记录已保存在本机，联网后会自动安排补测。";
        }
        catch (Exception error)
        {
            OperationHint.Text = $"安排补测失败：{error.Message}";
            if (_activeClientSessionId is null) await RestoreInterruptedCaptureAsync();
        }
        finally { UpdateQueueActionAvailability(); await RefreshSyncStatusAsync(); }
    }

    private async void EmergencyStopButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_outbox is null) { OperationHint.Text = "本地安全状态尚未初始化。"; return; }
        EmergencyStopButton.IsEnabled = false;
        try
        {
            if (!_localEmergencyStop)
            {
                var confirmation = System.Windows.MessageBox.Show(this,
                    "确认触发本地紧急停止？\n\n正在进行的采集会立即停止且不生成成绩，学生将自动转入补测；所有新操作会保持锁定。",
                    "触发紧急停止", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Stop);
                if (confirmation != System.Windows.MessageBoxResult.Yes) return;
                const string reason = "现场操作员触发本地紧急停止";
                _localEmergencyStop = true;
                await _outbox.SaveSnapshotAsync("local-emergency-stop", JsonSerializer.Serialize(new LocalEmergencyStopState(reason, DateTimeOffset.UtcNow), SnapshotJson), CancellationToken.None);
                var interrupted = await StopActiveCaptureAsync();
                var synced = interrupted is null || await QueueCaptureAbortAsync(interrupted, reason, "emergency");
                try { await RefreshBootstrapAsync(updateOperationHint: false); } catch { _captureAllowedByConnection = false; }
                OperationHint.Text = interrupted is null
                    ? "本地紧急停止已触发，所有新操作已锁定。排除风险后再解除。"
                    : synced ? $"已紧急停止 {interrupted.StudentName} 的采集并安排补测。" : $"已停止 {interrupted.StudentName} 的采集；补测安排已保存在本机，联网后自动同步。";
            }
            else
            {
                var confirmation = System.Windows.MessageBox.Show(this,
                    "仅在现场风险已经排除、采集设备状态正常后解除。中央管理端的暂停或停止不会被本操作覆盖。\n\n确认解除本地紧急停止？",
                    "解除本地急停", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Warning);
                if (confirmation != System.Windows.MessageBoxResult.Yes) return;
                _localEmergencyStop = false;
                await _outbox.DeleteSnapshotAsync("local-emergency-stop", CancellationToken.None);
                try
                {
                    await RefreshBootstrapAsync(updateOperationHint: false);
                    OperationHint.Text = _pausedByCentral ? "本地急停已解除，但中央管理端仍处于暂停或停止状态。" : "本地急停已解除，请重新确认设备自检和标定状态。";
                }
                catch (Exception error)
                {
                    _captureAllowedByConnection = false;
                    OperationHint.Text = $"本地急停已解除，但中央服务未连接：{error.Message}。恢复连接前不能正式采集。";
                }
            }
        }
        catch (Exception error)
        {
            OperationHint.Text = $"紧急停止处理失败：{error.Message}";
            if (_localEmergencyStop && _activeClientSessionId is null) await RestoreInterruptedCaptureAsync();
        }
        finally
        {
            EmergencyStopButton.IsEnabled = true;
            UpdateEmergencyStopVisual();
            UpdateQueueActionAvailability();
            await RefreshSyncStatusAsync();
        }
    }

    private async Task<InterruptedCaptureState?> StopActiveCaptureAsync()
    {
        if (_activeClientSessionId is null || _outbox is null) return null;
        InterruptedCaptureState? interrupted = null;
        var snapshot = await _outbox.ReadSnapshotAsync("active-capture", CancellationToken.None);
        if (snapshot is not null)
        {
            try { interrupted = JsonSerializer.Deserialize<InterruptedCaptureState>(snapshot.Json, SnapshotJson); } catch (JsonException) { }
        }
        if (interrupted is null && _activeEntry is not null && _bootstrap?.Task is not null)
        {
            interrupted = new InterruptedCaptureState(Guid.NewGuid(), _activeClientSessionId, _activeEntry.Id, _activeEntry.StudentId, _activeEntry.StudentName, _bootstrap.Task.Id, _captureAdapter?.AdapterName ?? "certified-adapter", DateTimeOffset.UtcNow);
        }
        try { if (_captureAdapter is not null) await _captureAdapter.StopAsync(CancellationToken.None); } catch { }
        _captureEventsCancellation?.Cancel();
        try { if (_captureEventsTask is not null) await _captureEventsTask; } catch (OperationCanceledException) { }
        if (_activeCaptureRun is not null) await _activeCaptureRun.DisposeAsync();
        _captureEventsCancellation?.Dispose();
        _captureEventsCancellation = null;
        _captureEventsTask = null;
        _activeCaptureRun = null;
        _preparedCaptureResult = null;
        _activeClientSessionId = null;
        _activeEntry = null;
        ResetCaptureLiveProgress();
        return interrupted;
    }

    private async Task<bool> QueueCaptureAbortAsync(InterruptedCaptureState interrupted, string reason, string cause)
    {
        if (_outbox is null) return false;
        await EnqueueAsync("session.open", new
        {
            clientSessionId = interrupted.ClientSessionId,
            taskId = interrupted.TaskId,
            studentId = interrupted.StudentId,
            startedAt = interrupted.StartedAt,
            algorithmVersion = interrupted.AdapterName,
            summary = new
            {
                captureMode = "certified-adapter",
                adapter = interrupted.AdapterName,
                recoveredAfterRestart = cause == "restart",
                emergencyStopped = cause == "emergency",
                operatorRequestedRetest = cause == "operator_retest",
                taskRetiredRecovery = cause == "task_retired"
            }
        }, interrupted.OpenEventId);
        await EnqueueAsync("session.abort", new { sessionId = interrupted.ClientSessionId, endedAt = DateTimeOffset.UtcNow, reason });
        await _outbox.DeleteSnapshotAsync("active-capture", CancellationToken.None);
        var entry = string.Equals(_bootstrap?.Task?.Id, interrupted.TaskId, StringComparison.Ordinal)
            ? _bootstrap!.Queue.FirstOrDefault(item => item.Id == interrupted.QueueEntryId || item.StudentId == interrupted.StudentId)
            : null;
        if (entry is not null)
        {
            _localQueueStatuses[entry.Id] = "retest";
            RefreshQueueDisplay(entry.StudentId);
            SelectedStudentStatus.Text = "待重测";
        }
        _interruptedCapture = null;
        _captureDetachedFromTask = false;
        return _sync is not null && await _sync.FlushAsync(CancellationToken.None);
    }

    private async void RecoverInterruptedButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_interruptedCapture is null || _outbox is null) return;
        var interrupted = _interruptedCapture;
        var detachedFromTask = _captureDetachedFromTask;
        var confirmation = System.Windows.MessageBox.Show(this,
            detachedFromTask
                ? $"后台已关闭或移除原任务。确认停止并封存 {interrupted.StudentName} 的本机中断采集？\n\n原采集不会生成成绩；记录会同步到后台留痕，任务不会重新开启。"
                : $"确认关闭 {interrupted.StudentName} 的中断会话并安排补测？原采集不会生成成绩。",
            detachedFromTask ? "封存旧任务采集记录" : "处理中断采集", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Warning);
        if (confirmation != System.Windows.MessageBoxResult.Yes) return;
        RecoverInterruptedButton.IsEnabled = false;
        try
        {
            var reason = detachedFromTask
                ? "后台关闭或移除任务时，Windows 场地端仍有未收尾采集；本机已停止设备并封存原始上下文"
                : "Windows 场地端异常退出，原硬件采集上下文无法恢复";
            var synced = await QueueCaptureAbortAsync(interrupted, reason, detachedFromTask ? "task_retired" : "restart");
            OperationHint.Text = detachedFromTask
                ? synced
                    ? $"{interrupted.StudentName} 的旧任务中断记录已同步封存。当前任务现已解锁，请重新核对名单后继续。"
                    : $"{interrupted.StudentName} 的旧任务中断记录已安全保存在本机。若右上角显示同步冲突，请在后台“现场运行 → 同步冲突工作台”确认；记录不会丢失。"
                : synced
                    ? $"{interrupted.StudentName} 的中断会话已关闭，并已加入补测队列。"
                    : $"{interrupted.StudentName} 的中断处理已保存在本机，联网后会自动关闭旧会话并安排补测。";
        }
        catch (Exception error) { OperationHint.Text = $"处理中断采集失败：{error.Message}"; }
        finally { UpdateQueueActionAvailability(); await RefreshSyncStatusAsync(); }
    }

    private static async Task<IReadOnlyList<PendingFieldEvidence>> CopyEvidenceToManagedStorageAsync(string sessionId, IReadOnlyList<LocalEvidence> evidence, string evidenceDirectory, CancellationToken cancellationToken)
    {
        var allowedContentTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "application/pdf", "text/plain", "image/jpeg", "image/png", "video/mp4" };
        var allowedEvidenceTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "video", "image", "skeleton", "timeline", "calibration", "log", "other" };
        var result = new List<PendingFieldEvidence>();
        try
        {
            foreach (var item in evidence)
            {
                if (!File.Exists(item.LocalPath)) throw new FileNotFoundException("采集设备返回的证据文件不存在。", item.LocalPath);
                if (!allowedContentTypes.Contains(item.ContentType)) throw new InvalidDataException($"不支持的证据文件类型：{item.ContentType}");
                if (!allowedEvidenceTypes.Contains(item.EvidenceType)) throw new InvalidDataException($"不支持的证据用途：{item.EvidenceType}");
                var source = new FileInfo(item.LocalPath);
                if (source.Length > 20 * 1024 * 1024) throw new InvalidDataException($"证据文件 {source.Name} 超过 20MB。");
                var safeName = Path.GetFileName(string.IsNullOrWhiteSpace(item.FileName) ? source.Name : item.FileName);
                if (string.IsNullOrWhiteSpace(safeName)) throw new InvalidDataException("证据文件名无效。");
                var targetPath = Path.Combine(evidenceDirectory, $"{sessionId}-{Guid.NewGuid():N}-{safeName}");
                var bytes = await File.ReadAllBytesAsync(item.LocalPath, cancellationToken);
                var checksum = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
                if (!string.IsNullOrWhiteSpace(item.ChecksumSha256) && !string.Equals(item.ChecksumSha256, checksum, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException($"证据文件 {safeName} 的校验值与设备声明不一致。");
                }
                await File.WriteAllBytesAsync(targetPath, bytes, cancellationToken);
                var metadata = item.Metadata?.Clone() ?? JsonSerializer.SerializeToElement(new { });
                result.Add(new PendingFieldEvidence(Guid.NewGuid(), sessionId, targetPath, safeName, item.ContentType, item.EvidenceType.ToLowerInvariant(), checksum, metadata));
            }
            return result;
        }
        catch
        {
            DeleteManagedEvidenceCopies(result.Select(item => item.LocalPath));
            throw;
        }
    }

    private static void DeleteManagedEvidenceCopies(IEnumerable<string> paths)
    {
        foreach (var path in paths)
        {
            try { if (File.Exists(path)) File.Delete(path); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private async void SyncButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_sync is null) { OperationHint.Text = "场地端尚未配置设备凭证。"; return; }
        try
        {
            var synced = await _sync.FlushAsync(CancellationToken.None);
            await ReconcileQueueSyncConflictsAsync(showOperatorHint: false);
            var conflicts = _outbox is null ? new OutboxConflictSummary(0, null) : await _outbox.GetConflictSummaryAsync(CancellationToken.None);
            OperationHint.Text = conflicts.Count > 0
                ? $"发现 {conflicts.Count} 条需人工处理的同步冲突：{conflicts.LastError}。已恢复显示中央名单；请在后台“现场运行 → 同步冲突工作台”核对，原始本地事件会保留到后台确认。"
                : synced ? "本地事件已安全同步到中央服务。" : "同步未完成；事件已保留在本地 SQLite，网络恢复后可重试。";
            if (synced) await RefreshBootstrapAsync();
        }
        catch (Exception error) { OperationHint.Text = $"同步失败：{error.Message}"; }
        finally { await RefreshSyncStatusAsync(); }
    }

    private async Task EnqueueAsync(string eventType, object payload, Guid? clientEventId = null)
    {
        if (_outbox is null) return;
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(payload));
        await _outbox.EnqueueAsync(new OutboxEvent(clientEventId ?? Guid.NewGuid(), eventType, DateTimeOffset.UtcNow, document.RootElement.Clone()), CancellationToken.None);
        await RefreshSyncStatusAsync();
    }

    private async Task PumpCaptureEventsAsync(ICaptureRun captureRun, string clientSessionId, CancellationToken cancellationToken)
    {
        try
        {
            await foreach (var action in captureRun.Events(cancellationToken))
            {
                await EnqueueAsync("session.events", new
                {
                    sessionId = clientSessionId,
                    events = new[] { new { clientEventId = action.ClientEventId, sequenceNo = action.SequenceNo, eventType = action.EventType, happenedAt = action.HappenedAt, payload = action.Payload } }
                });
                var presentation = CaptureEventPresentationPolicy.Describe(action, Interlocked.Increment(ref _captureEventCount));
                await Dispatcher.InvokeAsync(() =>
                {
                    _protocolProgress = FieldProtocolProgressPolicy.ApplyEvent(_protocolProgress, action);
                    RenderProtocolProgress();
                    CaptureLiveEventPanel.Visibility = System.Windows.Visibility.Visible;
                    CaptureLiveEventTitle.Text = presentation.Title;
                    CaptureLiveEventDetail.Text = presentation.Detail;
                    OperationHint.Text = $"{_activeEntry?.StudentName ?? "当前学生"}：{presentation.Title}。";
                });
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (Exception error)
        {
            await Dispatcher.InvokeAsync(() => OperationHint.Text = $"采集事件保存失败：{error.Message}");
        }
    }

    private void ResetCaptureLiveProgress()
    {
        Interlocked.Exchange(ref _captureEventCount, 0);
        if (CaptureLiveEventPanel is null) return;
        CaptureLiveEventPanel.Visibility = System.Windows.Visibility.Collapsed;
        CaptureLiveEventTitle.Text = "等待设备首条反馈";
        CaptureLiveEventDetail.Text = "采集事件会实时显示在这里";
    }

    private void ResetProtocolProgress(bool force = false)
    {
        var taskId = _bootstrap?.Task?.Id;
        if (!force && string.Equals(_protocolProgressTaskId, taskId, StringComparison.Ordinal) && _protocolProgress.Count > 0) return;
        _protocolProgressTaskId = taskId;
        _protocolProgress = FieldProtocolProgressPolicy.Initialize(_bootstrap?.Protocol, _bootstrap?.Task);
        RenderProtocolProgress();
    }

    private void RenderProtocolProgress()
    {
        if (ProtocolProgressPanel is null) return;
        ProtocolProgressPanel.Visibility = _protocolProgress.Count > 0 ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;
        ProtocolProgressTitle.Text = _bootstrap?.Protocol is { } protocol ? $"{protocol.Name} · v{protocol.Version}" : "当前任务完整通道";
        var done = _protocolProgress.Count(item => item.Status is "completed" or "needs_review");
        ProtocolProgressCount.Text = $"{done}/{_protocolProgress.Count}";
        ProtocolProgressList.ItemsSource = _protocolProgress.Select(item =>
        {
            var color = item.Status switch
            {
                "running" => System.Windows.Media.Color.FromRgb(65, 141, 238),
                "completed" => System.Windows.Media.Color.FromRgb(68, 215, 168),
                "needs_review" => System.Windows.Media.Color.FromRgb(240, 184, 74),
                "retest" => System.Windows.Media.Color.FromRgb(226, 93, 93),
                _ => System.Windows.Media.Color.FromRgb(105, 137, 172)
            };
            var statusLabel = item.Status switch { "running" => "进行中", "completed" => "已完成", "needs_review" => "待复核", "retest" => "需补测", _ => "待进行" };
            return new ProtocolItemDisplay(item.Name, $"{item.SequenceNo:00}", statusLabel,
                new System.Windows.Media.SolidColorBrush(color),
                new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(52, color.R, color.G, color.B)),
                new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(110, color.R, color.G, color.B)));
        }).ToArray();
    }

    private sealed record QueueDisplayEntry(QueueEntry Entry, string Status, string StatusLabel, FieldQueueTiming Timing)
    {
        public string StudentId => Entry.StudentId;
        public string StudentName => Entry.StudentName;
        public string ClassName => Entry.ClassName;
        public string IdentityHint => $"{Entry.ClassName} · {Entry.StudentNo ?? "学籍号待补"} · {Timing.Label}";
        public string NoteHint => string.IsNullOrWhiteSpace(Entry.Note) ? string.Empty : $"说明：{Entry.Note.Trim()}";
        public System.Windows.Visibility NoteVisibility => string.IsNullOrWhiteSpace(Entry.Note) ? System.Windows.Visibility.Collapsed : System.Windows.Visibility.Visible;
        public int QueueOrder => Entry.QueueOrder;
        public System.Windows.Media.Brush StatusBackground => Status switch
        {
            _ when Timing.IsOverdue => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 241, 218)),
            "testing" or "checked_in" or "called" => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(234, 243, 255)),
            "completed" => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(229, 247, 241)),
            "retest" => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 245, 221)),
            "absent" or "skipped" or "paused" or "cancelled" => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 235, 235)),
            _ => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(242, 245, 248))
        };
        public System.Windows.Media.Brush StatusForeground => Status switch
        {
            _ when Timing.IsOverdue => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(181, 93, 7)),
            "testing" or "checked_in" or "called" => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(23, 105, 224)),
            "completed" => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(17, 138, 104)),
            "retest" => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(184, 117, 8)),
            "absent" or "skipped" or "paused" or "cancelled" => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(201, 52, 52)),
            _ => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(111, 127, 148))
        };
    }

    private sealed record ProtocolItemDisplay(string Name, string SequenceLabel, string StatusLabel, System.Windows.Media.Brush Foreground, System.Windows.Media.Brush Background, System.Windows.Media.Brush Border);

    private sealed record PreparedCaptureResult(
        string AdapterName,
        DateTimeOffset EndedAt,
        IReadOnlyList<FieldScore> Scores,
        IReadOnlyList<LocalEvidence> LocalEvidence,
        CaptureCompletionAssessment Assessment);

    private sealed record ReadinessCheckDisplay(string Label, string Symbol, System.Windows.Media.Brush StatusBrush, string DetailText);
}
