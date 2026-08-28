using Microsoft.Data.Sqlite;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Xunit;

namespace Xiangshang.FieldClient.Tests;

public sealed class SqliteOutboxStoreTests : IAsyncLifetime
{
    private readonly string _databasePath = Path.Combine(Path.GetTempPath(), $"xiangshang-field-{Guid.NewGuid():N}.db");
    private SqliteOutboxStore _store = null!;

    public async Task InitializeAsync()
    {
        _store = new SqliteOutboxStore(_databasePath);
        await _store.InitializeAsync(CancellationToken.None);
    }

    public async Task DisposeAsync()
    {
        // Microsoft.Data.Sqlite keeps disposed connections in a process pool.
        // Windows correctly refuses to unlink the WAL database while that
        // pooled handle is still open, so release idle handles before removing
        // the per-test fixture. This does not affect live connections.
        SqliteConnection.ClearAllPools();
        foreach (var path in new[] { _databasePath, $"{_databasePath}-shm", $"{_databasePath}-wal" })
        {
            for (var attempt = 0; attempt < 3 && File.Exists(path); attempt++)
            {
                try { File.Delete(path); }
                catch (IOException) when (attempt < 2) { await Task.Delay(50); }
            }
        }
    }

    [Fact]
    public async Task EnqueueIsIdempotentAndSyncedEventsAreNotRetried()
    {
        using var document = JsonDocument.Parse("{\"sessionId\":\"s-1\",\"status\":\"completed\"}");
        var item = new OutboxEvent(Guid.NewGuid(), "session.complete", DateTimeOffset.UtcNow, document.RootElement.Clone());

        await _store.EnqueueAsync(item, CancellationToken.None);
        await _store.EnqueueAsync(item, CancellationToken.None);
        var pending = await _store.TakePendingAsync(10, CancellationToken.None);

        var saved = Assert.Single(pending);
        Assert.Equal(item.ClientEventId, saved.ClientEventId);
        Assert.Equal("completed", saved.Payload.GetProperty("status").GetString());

        await _store.MarkSyncedAsync(new[] { item.ClientEventId }, CancellationToken.None);
        Assert.Empty(await _store.TakePendingAsync(10, CancellationToken.None));
    }

    [Fact]
    public async Task FailedEventsRemainEligibleForLaterReplay()
    {
        using var document = JsonDocument.Parse("{\"queueEntryId\":\"q-1\",\"status\":\"called\"}");
        var item = new OutboxEvent(Guid.NewGuid(), "queue.transition", DateTimeOffset.UtcNow, document.RootElement.Clone());

        await _store.EnqueueAsync(item, CancellationToken.None);
        await _store.MarkFailedAsync(new[] { item.ClientEventId }, "network unavailable", CancellationToken.None);

        var retry = Assert.Single(await _store.TakePendingAsync(10, CancellationToken.None));
        Assert.Equal(item.ClientEventId, retry.ClientEventId);
        Assert.Equal("queue.transition", retry.EventType);
    }

    [Fact]
    public async Task PendingBatchKeepsItsIdUntilTheCentralReceiptIsAcknowledged()
    {
        using var firstDocument = JsonDocument.Parse("{\"sessionId\":\"s-1\"}");
        using var secondDocument = JsonDocument.Parse("{\"sessionId\":\"s-2\"}");
        var first = new OutboxEvent(Guid.NewGuid(), "session.open", DateTimeOffset.UtcNow, firstDocument.RootElement.Clone());
        var second = new OutboxEvent(Guid.NewGuid(), "session.open", DateTimeOffset.UtcNow.AddSeconds(1), secondDocument.RootElement.Clone());
        await _store.EnqueueAsync(first, CancellationToken.None);
        await _store.EnqueueAsync(second, CancellationToken.None);

        var original = await _store.TakeOrCreatePendingBatchAsync(200, CancellationToken.None);
        var replay = await _store.TakeOrCreatePendingBatchAsync(200, CancellationToken.None);

        Assert.NotNull(original);
        Assert.NotNull(replay);
        Assert.Equal(original!.ClientBatchId, replay!.ClientBatchId);
        Assert.Equal(new[] { first.ClientEventId, second.ClientEventId }, replay.Events.Select(item => item.ClientEventId));

        await _store.MarkSyncedAsync(original.Events.Select(item => item.ClientEventId), CancellationToken.None);
        Assert.Null(await _store.TakeOrCreatePendingBatchAsync(200, CancellationToken.None));
    }

    [Fact]
    public async Task PendingEventsKeepInsertionOrderWhenTheyShareTheSameTimestamp()
    {
        var happenedAt = DateTimeOffset.UtcNow;
        using var checkInDocument = JsonDocument.Parse("{\"status\":\"checked_in\"}");
        using var sessionDocument = JsonDocument.Parse("{\"sessionId\":\"s-1\"}");
        var checkIn = new OutboxEvent(Guid.NewGuid(), "queue.transition", happenedAt, checkInDocument.RootElement.Clone());
        var openSession = new OutboxEvent(Guid.NewGuid(), "session.open", happenedAt, sessionDocument.RootElement.Clone());

        await _store.EnqueueAsync(checkIn, CancellationToken.None);
        await _store.EnqueueAsync(openSession, CancellationToken.None);

        var batch = await _store.TakeOrCreatePendingBatchAsync(10, CancellationToken.None);
        Assert.NotNull(batch);
        Assert.Equal(new[] { checkIn.ClientEventId, openSession.ClientEventId }, batch!.Events.Select(item => item.ClientEventId));
    }

    [Fact]
    public async Task SemanticConflictStopsAutomaticReplayButPreservesLocalFact()
    {
        using var document = JsonDocument.Parse("{\"queueEntryId\":\"q-1\",\"status\":\"called\"}");
        var item = new OutboxEvent(Guid.NewGuid(), "queue.transition", DateTimeOffset.UtcNow, document.RootElement.Clone());
        await _store.EnqueueAsync(item, CancellationToken.None);

        await _store.MarkConflictAsync(new[] { item.ClientEventId }, "FIELD_EVENT_REPLAY_MISMATCH", CancellationToken.None);

        Assert.Empty(await _store.TakePendingAsync(10, CancellationToken.None));
        var conflicts = await _store.GetConflictSummaryAsync(CancellationToken.None);
        Assert.Equal(1, conflicts.Count);
        Assert.Equal("FIELD_EVENT_REPLAY_MISMATCH", conflicts.LastError);
    }

    [Fact]
    public async Task StatusSummarySeparatesPendingWorkFromOperatorConflicts()
    {
        using var firstDocument = JsonDocument.Parse("{\"status\":\"called\"}");
        using var secondDocument = JsonDocument.Parse("{\"status\":\"checked_in\"}");
        var pending = new OutboxEvent(Guid.NewGuid(), "queue.transition", DateTimeOffset.UtcNow, firstDocument.RootElement.Clone());
        var conflict = new OutboxEvent(Guid.NewGuid(), "queue.transition", DateTimeOffset.UtcNow, secondDocument.RootElement.Clone());
        await _store.EnqueueAsync(pending, CancellationToken.None);
        await _store.EnqueueAsync(conflict, CancellationToken.None);
        await _store.MarkConflictAsync(new[] { conflict.ClientEventId }, "FIELD_QUEUE_VERSION_CONFLICT", CancellationToken.None);

        var summary = await _store.GetStatusSummaryAsync(CancellationToken.None);

        Assert.Equal(1, summary.PendingCount);
        Assert.Equal(1, summary.ConflictCount);
    }

    [Fact]
    public async Task CompletionWaitsForEvidenceAndIsFinalizedOnlyAfterCentralSync()
    {
        using var scores = JsonDocument.Parse("[{\"item\":\"连续双脚障碍跳\",\"score\":4.2,\"confidence\":0.93}]");
        using var summaryDocument = JsonDocument.Parse("{\"captureMode\":\"certified-adapter\"}");
        using var metadata = JsonDocument.Parse("{\"frameCount\":300}");
        var completion = new PendingFieldCompletion(Guid.NewGuid(), "field-session-1", "adapter/1.0", DateTimeOffset.UtcNow, scores.RootElement.Clone(), summaryDocument.RootElement.Clone());
        var evidence = new PendingFieldEvidence(Guid.NewGuid(), completion.SessionId, Path.Combine(Path.GetTempPath(), "managed-evidence.txt"), "timeline.txt", "text/plain", "timeline", new string('a', 64), metadata.RootElement.Clone());

        await _store.SavePendingCompletionAsync(completion, new[] { evidence }, CancellationToken.None);

        Assert.Single(await _store.TakePendingEvidenceAsync(10, CancellationToken.None));
        Assert.Empty(await _store.TakeReadyCompletionsAsync(10, CancellationToken.None));
        var beforeUpload = await _store.GetStatusSummaryAsync(CancellationToken.None);
        Assert.Equal(2, beforeUpload.PendingCount);

        await _store.MarkEvidenceUploadedAsync(evidence.Id, new UploadedFieldEvidence("server-file-1", new string('b', 64)), CancellationToken.None);
        var ready = Assert.Single(await _store.TakeReadyCompletionsAsync(10, CancellationToken.None));
        var references = await _store.GetUploadedEvidenceAsync(completion.SessionId, CancellationToken.None);
        Assert.Equal("server-file-1", Assert.Single(references).FileId);

        using var payload = JsonDocument.Parse("{\"sessionId\":\"field-session-1\"}");
        await _store.EnqueueCompletionAsync(ready, new OutboxEvent(ready.ClientEventId, "session.complete", ready.EndedAt, payload.RootElement.Clone()), CancellationToken.None);
        Assert.Empty(await _store.TakeReadyCompletionsAsync(10, CancellationToken.None));
        Assert.Equal(1, (await _store.GetStatusSummaryAsync(CancellationToken.None)).PendingCount);

        await _store.MarkSyncedAsync(new[] { ready.ClientEventId }, CancellationToken.None);
        var cleanupPaths = await _store.FinalizeSyncedCompletionsAsync(new[] { ready.ClientEventId }, CancellationToken.None);
        Assert.Equal(evidence.LocalPath, Assert.Single(cleanupPaths));
        Assert.Empty(await _store.TakePendingEvidenceAsync(10, CancellationToken.None));
        Assert.Equal(0, (await _store.GetStatusSummaryAsync(CancellationToken.None)).PendingCount);
    }

    [Fact]
    public async Task EvidenceValidationConflictIsVisibleToTheOperator()
    {
        using var scores = JsonDocument.Parse("[]");
        using var empty = JsonDocument.Parse("{}");
        var completion = new PendingFieldCompletion(Guid.NewGuid(), "field-session-conflict", "adapter/1.0", DateTimeOffset.UtcNow, scores.RootElement.Clone(), empty.RootElement.Clone());
        var evidence = new PendingFieldEvidence(Guid.NewGuid(), completion.SessionId, "missing.txt", "missing.txt", "text/plain", "timeline", null, empty.RootElement.Clone());
        await _store.SavePendingCompletionAsync(completion, new[] { evidence }, CancellationToken.None);

        await _store.MarkEvidenceFailedAsync(evidence.Id, "本地证据文件不存在", conflict: true, CancellationToken.None);

        var status = await _store.GetStatusSummaryAsync(CancellationToken.None);
        var conflict = await _store.GetConflictSummaryAsync(CancellationToken.None);
        Assert.Equal(1, status.PendingCount);
        Assert.Equal(1, status.ConflictCount);
        Assert.Equal(1, conflict.Count);
        Assert.Equal("本地证据文件不存在", conflict.LastError);
    }

    [Fact]
    public async Task BootstrapSnapshotSurvivesAProcessRestart()
    {
        const string json = "{\"task\":{\"id\":\"task-1\"},\"queue\":[{\"id\":\"q-1\"}]}";
        await _store.SaveSnapshotAsync("bootstrap", json, CancellationToken.None);

        var reopened = new SqliteOutboxStore(_databasePath);
        await reopened.InitializeAsync(CancellationToken.None);
        var snapshot = await reopened.ReadSnapshotAsync("bootstrap", CancellationToken.None);

        Assert.NotNull(snapshot);
        Assert.Equal(json, snapshot!.Json);
        Assert.True(snapshot.UpdatedAt <= DateTimeOffset.UtcNow);
    }

    [Fact]
    public async Task InterruptedCaptureSnapshotCanBeDistinguishedFromADurableCompletion()
    {
        var state = new InterruptedCaptureState(Guid.NewGuid(), "field-interrupted-1", "queue-1", "student-1", "学生甲", "task-1", "adapter/1.0", DateTimeOffset.UtcNow);
        await _store.SaveSnapshotAsync("active-capture", JsonSerializer.Serialize(state), CancellationToken.None);
        Assert.False(await _store.HasPendingCompletionAsync(state.ClientSessionId, CancellationToken.None));

        using var scores = JsonDocument.Parse("[{\"item\":\"连续双脚障碍跳\",\"score\":4,\"confidence\":0.9}]");
        using var summary = JsonDocument.Parse("{}");
        await _store.SavePendingCompletionAsync(new PendingFieldCompletion(Guid.NewGuid(), state.ClientSessionId, state.AdapterName, DateTimeOffset.UtcNow, scores.RootElement.Clone(), summary.RootElement.Clone()), [], CancellationToken.None);

        Assert.True(await _store.HasPendingCompletionAsync(state.ClientSessionId, CancellationToken.None));
        await _store.DeleteSnapshotAsync("active-capture", CancellationToken.None);
        Assert.Null(await _store.ReadSnapshotAsync("active-capture", CancellationToken.None));
    }

    [Fact]
    public void ServerAddressIsPersistedAfterFirstDeploymentLaunch()
    {
        var path = Path.Combine(Path.GetTempPath(), $"xiangshang-field-config-{Guid.NewGuid():N}", "field-client.json");
        try
        {
            var initial = FieldClientConfiguration.ResolveApiBaseUrl("http://192.168.5.11:8080/", path);
            var restored = FieldClientConfiguration.ResolveApiBaseUrl(null, path);
            Assert.Equal(initial, restored);
        }
        finally
        {
            var directory = Path.GetDirectoryName(path);
            if (directory is not null && Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void ServerAddressCanBeSavedByTheFirstRunSetupWithoutEnvironmentVariables()
    {
        var path = Path.Combine(Path.GetTempPath(), $"xiangshang-field-setup-{Guid.NewGuid():N}", "field-client.json");
        try
        {
            var saved = FieldClientConfiguration.SaveApiBaseUrl(" http://192.168.5.11:8080/admin ", path);
            var restored = FieldClientConfiguration.TryReadApiBaseUrl(path);
            Assert.Equal(new Uri("http://192.168.5.11:8080/"), saved);
            Assert.Equal(saved, restored);
        }
        finally
        {
            var directory = Path.GetDirectoryName(path);
            if (directory is not null && Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void CaptureAdapterCanBeSavedWithoutLosingTheServerAddress()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"xiangshang-field-adapter-{Guid.NewGuid():N}");
        var path = Path.Combine(directory, "field-client.json");
        try
        {
            var assemblyPath = typeof(TestCaptureAdapter).Assembly.Location;
            FieldClientConfiguration.SaveApiBaseUrl("http://192.168.5.11:8080", path);
            var saved = FieldClientConfiguration.SaveCaptureAdapter(assemblyPath, typeof(TestCaptureAdapter).FullName!, path);
            FieldClientConfiguration.SaveApiBaseUrl("http://192.168.5.12:8080", path);

            Assert.Equal(Path.GetFullPath(assemblyPath), saved.AssemblyPath);
            Assert.Matches("^[a-f0-9]{64}$", saved.Sha256);
            Assert.Equal(typeof(TestCaptureAdapter).FullName, FieldClientConfiguration.TryReadCaptureAdapter(path)?.TypeName);
            Assert.Equal(new Uri("http://192.168.5.12:8080/"), FieldClientConfiguration.TryReadApiBaseUrl(path));

            FieldClientConfiguration.ClearCaptureAdapter(path);
            Assert.Null(FieldClientConfiguration.TryReadCaptureAdapter(path));
            Assert.Equal(new Uri("http://192.168.5.12:8080/"), FieldClientConfiguration.TryReadApiBaseUrl(path));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }

    [Fact]
    public async Task CaptureAdapterCanBeDiscoveredAndLoadedFromSavedConfiguration()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"xiangshang-field-adapter-load-{Guid.NewGuid():N}");
        var path = Path.Combine(directory, "field-client.json");
        try
        {
            var assemblyPath = typeof(TestCaptureAdapter).Assembly.Location;
            var types = CaptureAdapterHost.DiscoverAdapterTypes(assemblyPath);
            Assert.Contains(typeof(TestCaptureAdapter).FullName!, types);
            FieldClientConfiguration.SaveApiBaseUrl("http://192.168.5.11:8080", path);
            FieldClientConfiguration.SaveCaptureAdapter(assemblyPath, typeof(TestCaptureAdapter).FullName!, path);

            await using var host = CaptureAdapterHost.LoadFromConfiguration(path);
            Assert.True(host.IsAvailable, host.UnavailableReason);
            Assert.Equal("test-certified-adapter/1.0", host.AdapterName);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }

    [Fact]
    public async Task SavedCaptureAdapterIsLockedWhenItsDllChanges()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"xiangshang-field-adapter-hash-{Guid.NewGuid():N}");
        var path = Path.Combine(directory, "field-client.json");
        var adapterPath = Path.Combine(directory, "CertifiedAdapter.dll");
        try
        {
            Directory.CreateDirectory(directory);
            File.Copy(typeof(TestCaptureAdapter).Assembly.Location, adapterPath);
            FieldClientConfiguration.SaveApiBaseUrl("http://192.168.5.11:8080", path);
            FieldClientConfiguration.SaveCaptureAdapter(adapterPath, typeof(TestCaptureAdapter).FullName!, path);
            await File.AppendAllTextAsync(adapterPath, "tampered");

            await using var host = CaptureAdapterHost.LoadFromConfiguration(path);
            Assert.False(host.IsAvailable);
            Assert.Contains("文件已发生变化", host.UnavailableReason);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void DeviceCredentialsRequireBothEnvironmentPartsOrAValidSecureStoreFallback()
    {
        Assert.Throws<InvalidOperationException>(() => DeviceCredentialSource.Resolve("device-1", null, () => new DeviceCredentials("stored", "key")));
        var environment = DeviceCredentialSource.Resolve("device-1", "environment-key", () => new DeviceCredentials("stored", "key"));
        Assert.Equal("device-1", environment.DeviceId);
        Assert.Equal("environment-key", environment.DeviceKey);
        var secureStore = DeviceCredentialSource.Resolve(null, null, () => new DeviceCredentials("stored-device", "stored-key"));
        Assert.Equal("stored-device", secureStore.DeviceId);
        if (!OperatingSystem.IsWindows())
        {
            Assert.Null(WindowsCredentialStore.TryReadDeviceCredentials("XiangshangField:NoCredentialExpectedOnNonWindows"));
            Assert.Throws<PlatformNotSupportedException>(() => WindowsCredentialStore.SaveDeviceCredentials(new DeviceCredentials("device-1", "secret"), "XiangshangField:NoCredentialWriteOnNonWindows"));
        }
    }

    [Fact]
    public void ManualFallbackIsExplicitlyIneligibleForFormalVisualScoring()
    {
        var health = FieldHardwareHealthFactory.ManualFallback();

        Assert.Equal("field-health/v1", health.SchemaVersion);
        Assert.False(health.SelfTest.Passed);
        Assert.False(health.Capture.AdapterReady);
        Assert.Equal("manual-fallback", health.Capture.AdapterName);
    }

    [Fact]
    public void DeviceRequestSignerUsesAStableCanonicalHmacWithoutSendingTheSecret()
    {
        var signature = FieldDeviceRequestSigner.Sign(
            new DeviceCredentials("device-1", "device-secret"),
            "post",
            "/v1/field/heartbeat?taskId=a%20b",
            DateTimeOffset.FromUnixTimeMilliseconds(1_700_000_000_123),
            Enumerable.Range(0, 16).Select(value => (byte)value).ToArray());

        Assert.Equal("1700000000123", signature.Timestamp);
        Assert.Equal("000102030405060708090a0b0c0d0e0f", signature.Nonce);
        Assert.Equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", signature.BodyHash);
        Assert.Equal("907c04c0e4a2f8b16f598477439c10e8ca1d7b3f0406a0423b4c84d075371c8c", signature.Signature);
        Assert.DoesNotContain("device-secret", signature.Signature, StringComparison.Ordinal);
    }

    [Fact]
    public async Task BootstrapSelectionRequestsAndParsesTheChosenPublishedTask()
    {
        using var http = new HttpClient(new DelegateHandler((request, _) =>
        {
            Assert.Equal("/v1/field/bootstrap?taskId=task-2", request.RequestUri!.PathAndQuery);
            Assert.True(request.Headers.Contains("X-Device-Signature"));
            const string json = """
                {"code":"OK","message":"ok","data":{
                  "serverTime":"2026-08-28T00:00:00Z",
                  "device":{"id":"device-1","code":"EDGE-1","name":"边缘主机","type":"edge_host","softwareVersion":"field-client/0.2","controlState":"paused"},
                  "station":null,"calibration":null,
                  "readiness":{"ready":false,"stationStatus":null,"calibrationVersion":null,"blockers":["尚未标定"],"checks":[{"key":"central_calibration","category":"calibration","label":"中央标定配置","status":"blocked","detail":"尚未下发有效标定配置","remediation":"在后台下发并激活由标定工具生成的配置","measuredValue":null}]},
                  "task":{"id":"task-2","title":"秋季体测","testDate":"2026-09-12","location":"体育馆","items":[],"ruleVersion":"v1","status":"published"},
                  "availableTasks":[
                    {"id":"task-1","title":"春季体测","testDate":"2026-03-12","location":"操场","totalCount":30,"completedCount":30},
                    {"id":"task-2","title":"秋季体测","testDate":"2026-09-12","location":"体育馆","totalCount":32,"completedCount":4}
                  ],
                  "queue":[{"id":"queue-1","taskId":"task-2","studentId":"student-1","stationId":"station-1","status":"waiting","priority":0,"queueOrder":1,"retestCount":0,"stateVersion":1,"studentName":"学生甲","className":"三年级2班","studentNo":"XS-001","gender":"女","birthDate":"2017-09-18","gradeName":"三年级"}],
                  "queueSummary":{"rosterCount":32,"queuedCount":32,"activeQueueCount":28,"stationAssignedCount":12,"stationActiveCount":10,"unassignedCount":3,"otherStationCount":15},"standards":[],"commands":[]
                }}
                """;
            return Task.FromResult(JsonResponse(HttpStatusCode.OK, json));
        })) { BaseAddress = new Uri("http://localhost:8080") };
        var api = new FieldApiClient(http, new DeviceCredentials("device-1", "device-secret"));

        var bootstrap = await api.GetBootstrapAsync("task-2", CancellationToken.None);

        Assert.Equal("task-2", bootstrap.Task!.Id);
        Assert.Equal("paused", bootstrap.Device.ControlState);
        Assert.Equal("central_calibration", Assert.Single(bootstrap.Readiness.Checks!).Key);
        Assert.Equal("blocked", bootstrap.Readiness.Checks![0].Status);
        Assert.Equal(2, bootstrap.AvailableTasks!.Count);
        var timing = bootstrap.AvailableTasks[1].TestDate == DateOnly.FromDateTime(DateTime.Today)
            ? "今天"
            : bootstrap.AvailableTasks[1].TestDate < DateOnly.FromDateTime(DateTime.Today) ? "已延期" : "待开始";
        Assert.Equal($"[{timing}] 秋季体测 · 2026-09-12 · 4/32", bootstrap.AvailableTasks[1].DisplayName);
        Assert.Equal("XS-001", Assert.Single(bootstrap.Queue).StudentNo);
        Assert.Equal(new DateOnly(2017, 9, 18), bootstrap.Queue[0].BirthDate);
        Assert.Equal(10, bootstrap.QueueSummary!.StationActiveCount);
        Assert.Equal(3, bootstrap.QueueSummary.UnassignedCount);
    }

    [Fact]
    public void RosterStatusExplainsWhyAFieldStationCannotSeeStudents()
    {
        var summary = new FieldQueueSummary(32, 32, 28, 0, 0, 3, 25);

        var unassigned = FieldRosterStatusPolicy.Describe(true, true, summary, 0);
        Assert.Contains("本站 0 人", unassigned.CoverageText);
        Assert.Equal("本站尚未分配学生", unassigned.EmptyTitle);
        Assert.Contains("生成 / 重新分流", unassigned.EmptyDetail);

        var otherStation = FieldRosterStatusPolicy.Describe(true, true, summary with { UnassignedCount = 0 }, 0);
        Assert.Equal("本站当前没有学生", otherStation.EmptyTitle);
        Assert.Contains("其他测试点", otherStation.EmptyDetail);

        var noRoster = FieldRosterStatusPolicy.Describe(true, true, summary with { RosterCount = 0, QueuedCount = 0, ActiveQueueCount = 0, OtherStationCount = 0 }, 0);
        Assert.Equal("任务尚未添加学生", noRoster.EmptyTitle);
    }

    [Fact]
    public void ConnectionImportParsesOnlyTheVersionedBackendClipboardEnvelope()
    {
        const string json = """{"schemaVersion":"xiangshang-field-connection/v1","apiBaseUrl":"http://192.168.5.11:8080/admin","deviceId":"device-1","deviceKey":"secret-key"}""";

        var imported = FieldConnectionImportPolicy.Parse(json);

        Assert.Equal("http://192.168.5.11:8080/", imported.ApiBaseUrl);
        Assert.Equal("device-1", imported.DeviceId);
        Assert.Equal("secret-key", imported.DeviceKey);
        Assert.False(FieldConnectionImportPolicy.TryParse("not-json", out _));
        Assert.Throws<InvalidOperationException>(() => FieldConnectionImportPolicy.Parse("""{"schemaVersion":"legacy","deviceKey":"do-not-echo"}"""));
    }

    [Fact]
    public async Task SelectedTaskAndCentralPauseSurviveAProcessRestart()
    {
        var pause = new CentralPauseState("stop", DateTimeOffset.UtcNow);
        await _store.SaveSnapshotAsync("selected-task", JsonSerializer.Serialize("task-2"), CancellationToken.None);
        await _store.SaveSnapshotAsync("central-pause", JsonSerializer.Serialize(pause), CancellationToken.None);
        await _store.SaveSnapshotAsync("local-emergency-stop", JsonSerializer.Serialize(new LocalEmergencyStopState("现场风险", DateTimeOffset.UtcNow)), CancellationToken.None);

        var reopened = new SqliteOutboxStore(_databasePath);
        await reopened.InitializeAsync(CancellationToken.None);
        var selectedTask = await reopened.ReadSnapshotAsync("selected-task", CancellationToken.None);
        var centralPause = await reopened.ReadSnapshotAsync("central-pause", CancellationToken.None);
        var emergencyStop = await reopened.ReadSnapshotAsync("local-emergency-stop", CancellationToken.None);

        Assert.Equal("task-2", JsonSerializer.Deserialize<string>(selectedTask!.Json));
        Assert.Equal("stop", JsonSerializer.Deserialize<CentralPauseState>(centralPause!.Json)!.CommandType);
        Assert.Equal("现场风险", JsonSerializer.Deserialize<LocalEmergencyStopState>(emergencyStop!.Json)!.Reason);
    }

    [Fact]
    public void LocalEmergencyStopAugmentsButNeverClearsVendorSafetyState()
    {
        var healthy = FieldHardwareHealthFactory.ManualFallback() with { EmergencyStop = false };
        Assert.True(FieldHardwareHealthFactory.ApplyLocalEmergencyStop(healthy, true).EmergencyStop);
        var vendorStopped = healthy with { EmergencyStop = true };
        Assert.True(FieldHardwareHealthFactory.ApplyLocalEmergencyStop(vendorStopped, false).EmergencyStop);
    }

    [Fact]
    public void CompletionPolicyAcceptsCertifiedEvidenceAndFlagsLowConfidenceForReview()
    {
        var evidencePath = Path.Combine(Path.GetTempPath(), $"field-evidence-{Guid.NewGuid():N}.txt");
        File.WriteAllText(evidencePath, "timeline");
        try
        {
            using var empty = JsonDocument.Parse("{}");
            var scores = new[]
            {
                new FieldScore("连续双脚障碍跳", 4.2m, 0.93m),
                new FieldScore("侧向滑步", 3.8m, 0.72m)
            };
            var evidence = new[] { new LocalEvidence(evidencePath, "timeline.txt", "text/plain", "timeline", null, empty.RootElement.Clone()) };

            var assessment = CaptureCompletionPolicy.Evaluate(scores, evidence);

            Assert.True(assessment.CanSubmit);
            Assert.True(assessment.RequiresCentralReview);
            Assert.Empty(assessment.Blockers);
            Assert.Equal(new[] { "侧向滑步" }, assessment.LowConfidenceItems);
        }
        finally { File.Delete(evidencePath); }
    }

    [Fact]
    public void CompletionPolicyRejectsDuplicateUnsupportedOrMissingEvidence()
    {
        var scores = new[]
        {
            new FieldScore("连续双脚障碍跳", 4m, 0.9m),
            new FieldScore("连续双脚障碍跳", 6m, 1.2m),
            new FieldScore("自定义项目", 3m, 0.9m)
        };

        var assessment = CaptureCompletionPolicy.Evaluate(scores, []);

        Assert.False(assessment.CanSubmit);
        Assert.Contains(assessment.Blockers, item => item.Contains("重复", StringComparison.Ordinal));
        Assert.Contains(assessment.Blockers, item => item.Contains("未支持", StringComparison.Ordinal));
        Assert.Contains(assessment.Blockers, item => item.Contains("0 到 5", StringComparison.Ordinal));
        Assert.Contains(assessment.Blockers, item => item.Contains("置信度", StringComparison.Ordinal));
        Assert.Contains(assessment.Blockers, item => item.Contains("证据", StringComparison.Ordinal));
    }

    [Fact]
    public void CompletionPolicyRejectsScoresOutsideTheCurrentTaskScope()
    {
        var scores = new[] { new FieldScore("连续双脚障碍跳", 4m, 0.9m) };

        var assessment = CaptureCompletionPolicy.Evaluate(scores, [], ["连续双脚障碍跳", "侧向滑步"]);

        Assert.False(assessment.CanSubmit);
        Assert.Contains(assessment.Blockers, item => item.Contains("缺少 侧向滑步", StringComparison.Ordinal));
    }

    [Fact]
    public async Task EvidenceUploadSignsTheExactBinaryBodyAndVerifiesServerChecksum()
    {
        var path = Path.Combine(Path.GetTempPath(), $"field-evidence-{Guid.NewGuid():N}.txt");
        var bytes = Encoding.UTF8.GetBytes("timeline=field-session-1\nframes=300\n");
        await File.WriteAllBytesAsync(path, bytes);
        var checksum = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        var requests = 0;
        try
        {
            using var http = new HttpClient(new DelegateHandler(async (request, cancellationToken) =>
            {
                requests++;
                Assert.Equal("device-1", Assert.Single(request.Headers.GetValues("X-Device-Id")));
                Assert.True(request.Headers.Contains("X-Device-Signature"));
                Assert.False(request.Headers.Contains("X-Device-Key"));
                if (request.Method == HttpMethod.Post)
                {
                    Assert.Equal("/v1/field/files/presign", request.RequestUri!.AbsolutePath);
                    return JsonResponse(HttpStatusCode.Created, "{\"code\":\"CREATED\",\"message\":\"ok\",\"data\":{\"id\":\"file-1\",\"uploadUrl\":\"/v1/field/files/file-1/content\"}}");
                }
                var uploadedBytes = await request.Content!.ReadAsByteArrayAsync(cancellationToken);
                Assert.Equal(bytes, uploadedBytes);
                Assert.Equal(checksum, Assert.Single(request.Headers.GetValues("X-Device-Body-Hash")));
                Assert.Equal("text/plain", request.Content.Headers.ContentType!.MediaType);
                return JsonResponse(HttpStatusCode.OK, $"{{\"code\":\"OK\",\"message\":\"ok\",\"data\":{{\"id\":\"file-1\",\"checksumSha256\":\"{checksum}\"}}}}");
            })) { BaseAddress = new Uri("http://localhost:8080") };
            using var metadata = JsonDocument.Parse("{}");
            var api = new FieldApiClient(http, new DeviceCredentials("device-1", "device-secret"));
            var uploaded = await api.UploadEvidenceAsync(new PendingFieldEvidence(Guid.NewGuid(), "field-session-1", path, "timeline.txt", "text/plain", "timeline", checksum, metadata.RootElement.Clone()), CancellationToken.None);

            Assert.Equal("file-1", uploaded.FileId);
            Assert.Equal(checksum, uploaded.ChecksumSha256);
            Assert.Equal(2, requests);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public async Task OfflineSyncDrainsAnOlderBatchBeforeClaimingCompletionIsSynced()
    {
        var localEvidencePath = Path.Combine(Path.GetTempPath(), $"managed-field-evidence-{Guid.NewGuid():N}.txt");
        var bytes = Encoding.UTF8.GetBytes("timeline=field-session-drain\n");
        await File.WriteAllBytesAsync(localEvidencePath, bytes);
        var checksum = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        using var openPayload = JsonDocument.Parse("{\"clientSessionId\":\"field-session-drain\"}");
        var openEvent = new OutboxEvent(Guid.NewGuid(), "session.open", DateTimeOffset.UtcNow.AddSeconds(-2), openPayload.RootElement.Clone());
        await _store.EnqueueAsync(openEvent, CancellationToken.None);
        _ = await _store.TakeOrCreatePendingBatchAsync(200, CancellationToken.None);
        using var scores = JsonDocument.Parse("[{\"item\":\"连续双脚障碍跳\",\"score\":4,\"confidence\":0.9}]");
        using var empty = JsonDocument.Parse("{}");
        var completion = new PendingFieldCompletion(Guid.NewGuid(), "field-session-drain", "adapter/1.0", DateTimeOffset.UtcNow, scores.RootElement.Clone(), empty.RootElement.Clone());
        var evidence = new PendingFieldEvidence(Guid.NewGuid(), completion.SessionId, localEvidencePath, "timeline.txt", "text/plain", "timeline", checksum, empty.RootElement.Clone());
        await _store.SavePendingCompletionAsync(completion, new[] { evidence }, CancellationToken.None);
        var syncedEventTypes = new List<string[]>();

        try
        {
            using var http = new HttpClient(new DelegateHandler(async (request, cancellationToken) =>
            {
                if (request.RequestUri!.AbsolutePath == "/v1/field/files/presign")
                {
                    return JsonResponse(HttpStatusCode.Created, "{\"code\":\"CREATED\",\"message\":\"ok\",\"data\":{\"id\":\"file-drain\",\"uploadUrl\":\"/v1/field/files/file-drain/content\"}}");
                }
                if (request.Method == HttpMethod.Put)
                {
                    return JsonResponse(HttpStatusCode.OK, $"{{\"code\":\"OK\",\"message\":\"ok\",\"data\":{{\"id\":\"file-drain\",\"checksumSha256\":\"{checksum}\"}}}}");
                }
                using var requestDocument = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(cancellationToken));
                var eventTypes = requestDocument.RootElement.GetProperty("events").EnumerateArray().Select(item => item.GetProperty("eventType").GetString()!).ToArray();
                syncedEventTypes.Add(eventTypes);
                return JsonResponse(HttpStatusCode.OK, $"{{\"code\":\"OK\",\"message\":\"ok\",\"data\":{{\"accepted\":{eventTypes.Length},\"idempotent\":false}}}}");
            })) { BaseAddress = new Uri("http://localhost:8080") };
            var api = new FieldApiClient(http, new DeviceCredentials("device-1", "device-secret"));

            var allSynced = await new OfflineSyncService(api, _store).FlushAsync(CancellationToken.None);

            Assert.True(allSynced);
            Assert.Equal(2, syncedEventTypes.Count);
            Assert.Equal(new[] { "session.open" }, syncedEventTypes[0]);
            Assert.Equal(new[] { "session.complete" }, syncedEventTypes[1]);
            Assert.False(File.Exists(localEvidencePath));
            Assert.Equal(0, (await _store.GetStatusSummaryAsync(CancellationToken.None)).PendingCount);
        }
        finally { if (File.Exists(localEvidencePath)) File.Delete(localEvidencePath); }
    }

    [Fact]
    public async Task OfflineSyncCommitsAcceptedPrefixQuarantinesOnlyFailureAndContinuesWithUnprocessedEvents()
    {
        var firstId = Guid.NewGuid();
        var failedId = Guid.NewGuid();
        var finalId = Guid.NewGuid();
        foreach (var (id, status, version) in new[] { (firstId, "called", 1), (failedId, "checked_in", 1), (finalId, "checked_in", 2) })
        {
            using var payload = JsonDocument.Parse(JsonSerializer.Serialize(new { queueEntryId = "queue-partial", status, expectedVersion = version }));
            await _store.EnqueueAsync(new OutboxEvent(id, "queue.transition", DateTimeOffset.UtcNow, payload.RootElement.Clone()), CancellationToken.None);
        }
        Guid? originalBatchId = null;
        var requests = 0;
        using var http = new HttpClient(new DelegateHandler(async (request, cancellationToken) =>
        {
            requests++;
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(cancellationToken));
            var batchId = body.RootElement.GetProperty("clientBatchId").GetGuid();
            var eventIds = body.RootElement.GetProperty("events").EnumerateArray().Select(item => item.GetProperty("clientEventId").GetGuid()).ToArray();
            if (requests == 1)
            {
                originalBatchId = batchId;
                Assert.Equal(new[] { firstId, failedId, finalId }, eventIds);
                return JsonResponse(HttpStatusCode.Conflict, JsonSerializer.Serialize(new
                {
                    code = "FIELD_QUEUE_VERSION_CONFLICT",
                    message = "队列已被其他终端更新",
                    data = new { clientBatchId = batchId, acceptedEventIds = new[] { firstId }, failedEventId = failedId, unprocessedEventIds = new[] { finalId } }
                }));
            }
            Assert.NotEqual(originalBatchId, batchId);
            Assert.Equal(new[] { finalId }, eventIds);
            return JsonResponse(HttpStatusCode.OK, JsonSerializer.Serialize(new { code = "OK", message = "success", data = new { accepted = 1, idempotent = false } }));
        })) { BaseAddress = new Uri("http://localhost:8080") };

        var allSynced = await new OfflineSyncService(new FieldApiClient(http, new DeviceCredentials("device-1", "device-secret")), _store).FlushAsync(CancellationToken.None);

        Assert.False(allSynced);
        Assert.Equal(2, requests);
        Assert.Null(await _store.TakeOrCreatePendingBatchAsync(200, CancellationToken.None));
        var statusSummary = await _store.GetStatusSummaryAsync(CancellationToken.None);
        Assert.Equal(0, statusSummary.PendingCount);
        Assert.Equal(1, statusSummary.ConflictCount);
        var conflict = Assert.Single(await _store.GetConflictedQueueTransitionsAsync(CancellationToken.None));
        Assert.Equal("checked_in", conflict.Status);
        Assert.Equal(1, conflict.ExpectedVersion);
    }

    [Fact]
    public async Task CentralResolutionClearsOnlyMatchingLocalConflictsAndKeepsOriginalFact()
    {
        var resolvedEventId = Guid.NewGuid();
        using var payload = JsonDocument.Parse("{\"queueEntryId\":\"queue-resolved\",\"status\":\"called\",\"expectedVersion\":5}");
        await _store.EnqueueAsync(new OutboxEvent(resolvedEventId, "queue.transition", DateTimeOffset.UtcNow, payload.RootElement.Clone()), CancellationToken.None);
        await _store.MarkConflictAsync(new[] { resolvedEventId }, "FIELD_QUEUE_VERSION_CONFLICT", CancellationToken.None);
        var batchId = Guid.NewGuid();
        using var http = new HttpClient(new DelegateHandler((request, _) =>
        {
            Assert.Equal("/v1/field/sync/conflict-resolutions", request.RequestUri!.AbsolutePath);
            return Task.FromResult(JsonResponse(HttpStatusCode.OK, JsonSerializer.Serialize(new
            {
                code = "OK", message = "success",
                data = new[] { new { clientBatchId = batchId, eventIds = new[] { resolvedEventId }, resolutionNote = "已核对中央队列", resolvedAt = DateTimeOffset.UtcNow } }
            })));
        })) { BaseAddress = new Uri("http://localhost:8080") };

        var synced = await new OfflineSyncService(new FieldApiClient(http, new DeviceCredentials("device-1", "device-secret")), _store).FlushAsync(CancellationToken.None);

        Assert.True(synced);
        Assert.Equal(0, (await _store.GetStatusSummaryAsync(CancellationToken.None)).ConflictCount);
        Assert.Empty(await _store.GetConflictedQueueTransitionsAsync(CancellationToken.None));
        Assert.Null(await _store.TakeOrCreatePendingBatchAsync(200, CancellationToken.None));
    }

    [Fact]
    public void QueueChangeDetectorIgnoresInitialLoadAndExplainsCentralDispatchChanges()
    {
        var initial = new[]
        {
            Queue("queue-1", "student-1", "王小明", "station-a", "waiting", 1, 1),
            Queue("queue-2", "student-2", "王小雨", "station-a", "called", 2, 2)
        };

        var firstLoad = FieldQueueChangeDetector.Compare(null, initial);
        Assert.True(firstLoad.IsInitial);
        Assert.False(firstLoad.HasChanges);

        var refreshed = new[]
        {
            Queue("queue-1", "student-1", "王小明", "station-a", "called", 1, 2),
            Queue("queue-3", "student-3", "李小乐", "station-a", "waiting", 2, 1)
        };
        var delta = FieldQueueChangeDetector.Compare(initial, refreshed);

        Assert.False(delta.IsInitial);
        Assert.Equal(new[] { "李小乐" }, delta.AddedStudents);
        Assert.Equal(new[] { "王小雨" }, delta.RemovedStudents);
        Assert.Equal(new[] { "王小明" }, delta.UpdatedStudents);
        Assert.Contains("新增 1 人", delta.ToOperatorMessage());
        Assert.Contains("移出 1 人", delta.ToOperatorMessage());
        Assert.Contains("状态或顺序更新 1 人", delta.ToOperatorMessage());
    }

    [Fact]
    public void QueueAttentionFocusesAStudentJustCalledByCentralDispatch()
    {
        var previous = new[]
        {
            Queue("queue-1", "student-1", "王小明", "station-a", "waiting", 1, 1),
            Queue("queue-2", "student-2", "王小雨", "station-a", "waiting", 2, 1)
        };
        var current = new[]
        {
            Queue("queue-1", "student-1", "王小明", "station-a", "waiting", 1, 1),
            Queue("queue-2", "student-2", "王小雨", "station-a", "called", 2, 2)
        };

        var attention = FieldQueueAttentionPolicy.Select(previous, current, "student-1");

        Assert.True(attention.ChangedByCentral);
        Assert.Equal("student-2", attention.StudentId);
        Assert.Contains("后台已叫号：王小雨", attention.ToOperatorMessage());
    }

    [Fact]
    public void QueueAttentionPreservesAnExistingActiveStudentWithoutANewCentralChange()
    {
        var queue = new[]
        {
            Queue("queue-1", "student-1", "王小明", "station-a", "called", 1, 2),
            Queue("queue-2", "student-2", "王小雨", "station-a", "waiting", 2, 1)
        };

        var attention = FieldQueueAttentionPolicy.Select(queue, queue, "student-1");

        Assert.False(attention.ChangedByCentral);
        Assert.Equal("student-1", attention.StudentId);
        Assert.Null(attention.ToOperatorMessage());
    }

    [Fact]
    public void NextWaitingSelectionStaysAtThisStationAndHonorsPriorityThenQueueOrder()
    {
        var queue = new[]
        {
            Queue("queue-1", "student-1", "王小明", "station-a", "waiting", 1, 1),
            Queue("queue-2", "student-2", "王小雨", "station-b", "waiting", 1, 1) with { Priority = 9 },
            Queue("queue-3", "student-3", "王小强", "station-a", "completed", 2, 2) with { Priority = 8 },
            Queue("queue-4", "student-4", "王小兰", "station-a", "retest", 4, 3) with { Priority = 3 },
            Queue("queue-5", "student-5", "王小华", "station-a", "waiting", 3, 1) with { Priority = 3 }
        };

        var next = FieldQueueAttentionPolicy.SelectNextWaiting(queue, "station-a");

        Assert.NotNull(next);
        Assert.Equal("student-5", next.StudentId);
        Assert.Null(FieldQueueAttentionPolicy.SelectNextWaiting(queue, "station-missing"));
    }

    [Fact]
    public void DeviceRecallCommandResolvesTheExplicitQueueStudentInsteadOfTheCurrentSelection()
    {
        var queue = new[]
        {
            Queue("queue-1", "student-1", "王小明", "station-a", "waiting", 1, 1),
            Queue("queue-2", "student-2", "王小雨", "station-a", "called", 2, 2)
        };
        using var payload = JsonDocument.Parse("{\"queueEntryId\":\"queue-2\",\"studentId\":\"student-2\"}");

        var target = FieldDeviceCommandPolicy.ResolveQueueTarget(payload.RootElement, queue);

        Assert.NotNull(target);
        Assert.Equal("queue-2", target.Id);
        Assert.Equal("王小雨", target.StudentName);
    }

    [Fact]
    public void QueueVersionChainAdvancesEveryOfflineTransitionAndOnlyClearsAfterCentralAcknowledgement()
    {
        var entry = Queue("queue-version", "student-version", "王小明", "station-a", "waiting", 1, 7);
        var chain = new FieldQueueVersionChain();

        var callVersion = chain.GetExpectedVersion(entry);
        chain.MarkTransitionQueued(entry.Id, callVersion);
        var checkInVersion = chain.GetExpectedVersion(entry);
        chain.MarkTransitionQueued(entry.Id, checkInVersion);

        Assert.Equal(7, callVersion);
        Assert.Equal(8, checkInVersion);
        Assert.False(chain.TryReconcile(entry with { Status = "called", StateVersion = 8 }, "checked_in"));
        Assert.True(chain.TryReconcile(entry with { Status = "checked_in", StateVersion = 9 }, "checked_in"));
        Assert.False(chain.HasPending(entry.Id));
    }

    [Fact]
    public void OperatorWorkflowShowsOnlyActionsRelevantToTheCurrentStudentStage()
    {
        var waiting = FieldOperatorWorkflow.Describe("waiting", true, false, false, false, false, true, true, true);
        Assert.True(waiting.ShowCall);
        Assert.True(waiting.ShowAbsent);
        Assert.False(waiting.ShowCheckIn);
        Assert.Contains("叫号", waiting.ActionTitle);

        var called = FieldOperatorWorkflow.Describe("called", true, false, false, false, false, true, true, true);
        Assert.True(called.ShowCheckIn);
        Assert.False(called.ShowCall);
        Assert.Contains("核验身份", called.ActionTitle);

        var checkedIn = FieldOperatorWorkflow.Describe("checked_in", true, false, false, false, false, true, true, true);
        Assert.True(checkedIn.ShowStartCapture);
        Assert.False(checkedIn.ShowComplete);
        Assert.Contains("开始采集", checkedIn.ActionTitle);

        var capturing = FieldOperatorWorkflow.Describe("testing", true, false, false, true, false, true, true, true);
        Assert.True(capturing.ShowComplete);
        Assert.True(capturing.ShowRetest);
        Assert.False(capturing.ShowAbsent);
        Assert.Contains("核对设备成绩", capturing.ActionTitle);
    }

    [Fact]
    public void OperatorWorkflowExplainsSafetyLocksAndReadinessBlockers()
    {
        var blocked = FieldOperatorWorkflow.Describe("checked_in", true, false, false, false, false, true, false, true, "标定版本与中央配置不一致");
        Assert.True(blocked.ShowStartCapture);
        Assert.Contains("标定版本", blocked.ActionDetail);

        var waitingBlocked = FieldOperatorWorkflow.Describe("waiting", true, false, false, false, false, true, false, true, "标定版本与中央配置不一致");
        Assert.False(waitingBlocked.ShowCall);
        Assert.True(waitingBlocked.ShowAbsent);
        Assert.Contains("叫号条件", waitingBlocked.ActionTitle);
        Assert.Contains("标定版本", waitingBlocked.ActionDetail);

        var missingAdapter = FieldOperatorWorkflow.Describe("checked_in", true, false, false, false, false, true, false, false);
        Assert.Contains("采集设备", missingAdapter.ActionTitle);
        Assert.Contains("适配器 DLL", missingAdapter.ActionDetail);

        var emergency = FieldOperatorWorkflow.Describe("called", true, false, true, false, false, true, true, true);
        Assert.False(emergency.HasVisibleAction);
        Assert.Contains("紧急停止", emergency.ActionTitle);

        var interrupted = FieldOperatorWorkflow.Describe("testing", true, false, false, false, true, true, true, true);
        Assert.True(interrupted.ShowRecover);
        Assert.False(interrupted.ShowComplete);
        Assert.Contains("中断采集", interrupted.ActionTitle);
    }

    [Fact]
    public void ReadinessRecoveryPolicyAlwaysOffersTheNearestSafeOperatorAction()
    {
        var connection = FieldReadinessRecoveryPolicy.Describe(false, false, false, false, false, false, false);
        Assert.Equal("connection", connection.Action);
        Assert.Contains("中央连接", connection.Label);

        var noTask = FieldReadinessRecoveryPolicy.Describe(false, true, false, false, false, false, false);
        Assert.Equal("refresh", noTask.Action);
        Assert.Contains("任务和名单", noTask.Label);

        var missingAdapter = FieldReadinessRecoveryPolicy.Describe(true, true, false, false, false, true, false);
        Assert.Equal("adapter", missingAdapter.Action);
        Assert.Contains("采集设备", missingAdapter.Label);

        var failedReadiness = FieldReadinessRecoveryPolicy.Describe(true, true, false, false, true, true, false);
        Assert.Equal("refresh", failedReadiness.Action);
        Assert.Contains("开测检查", failedReadiness.Label);

        var maintenance = FieldReadinessRecoveryPolicy.Describe(true, true, false, false, true, true, false, "maintenance");
        Assert.Equal("refresh", maintenance.Action);
        Assert.Contains("测试点状态", maintenance.Label);
        Assert.Contains("后台", maintenance.Hint);

        var emergency = FieldReadinessRecoveryPolicy.Describe(true, false, true, true, false, false, false);
        Assert.Equal("emergency", emergency.Action);
        Assert.Contains("解除", emergency.Label);

        var ready = FieldReadinessRecoveryPolicy.Describe(true, true, false, false, true, true, true);
        Assert.False(ready.HasAction);
    }

    [Theory]
    [InlineData("paused", "暂停")]
    [InlineData("maintenance", "维护")]
    [InlineData("disabled", "停用")]
    [InlineData("offline", "恢复连接")]
    public void StationStatusPolicyExplainsWhyOperationsAreLocked(string status, string expected)
    {
        var presentation = FieldStationStatusPolicy.Describe(status);

        Assert.True(presentation.BlocksOperations);
        Assert.Contains(expected, presentation.Title);
        Assert.NotEmpty(presentation.RecoveryHint);
    }

    [Fact]
    public void OnlineStationStatusDoesNotAddAnOperatorLock()
    {
        var presentation = FieldStationStatusPolicy.Describe("online");

        Assert.False(presentation.BlocksOperations);
        Assert.Empty(presentation.RecoveryHint);
    }

    [Fact]
    public void StationStatusPolicyCarriesTheCentralOperatorReason()
    {
        var presentation = FieldStationStatusPolicy.Describe("maintenance", "二号相机更换数据线，预计 15:30 恢复");

        Assert.Contains("后台说明", presentation.Detail);
        Assert.Contains("预计 15:30 恢复", presentation.Detail);
    }

    [Fact]
    public void InterruptedCaptureIsPreservedWhenTheOriginalTaskIsNoLongerCurrent()
    {
        var interrupted = new InterruptedCaptureState(Guid.NewGuid(), "session-old", "queue-old", "student-old", "学生甲", "task-old", "adapter/1.0", DateTimeOffset.UtcNow);

        Assert.Equal(
            InterruptedCaptureDisposition.RetireOutsideCurrentTask,
            InterruptedCapturePolicy.Decide(interrupted, "task-new", null, hasPendingCompletion: false));
        Assert.Equal(
            InterruptedCaptureDisposition.RetireOutsideCurrentTask,
            InterruptedCapturePolicy.Decide(interrupted, "task-old", null, hasPendingCompletion: false));
        Assert.Equal(
            InterruptedCaptureDisposition.RecoverInCurrentTask,
            InterruptedCapturePolicy.Decide(interrupted, "task-old", "testing", hasPendingCompletion: false));
    }

    [Fact]
    public void InterruptedCaptureSnapshotCanOnlyBeDiscardedAfterADurableOrCentralResolution()
    {
        var interrupted = new InterruptedCaptureState(Guid.NewGuid(), "session-old", "queue-old", "student-old", "学生甲", "task-old", "adapter/1.0", DateTimeOffset.UtcNow);

        Assert.Equal(
            InterruptedCaptureDisposition.DiscardAfterDurableCompletion,
            InterruptedCapturePolicy.Decide(interrupted, "task-new", null, hasPendingCompletion: true));
        foreach (var status in new[] { "completed", "retest", "cancelled", "absent" })
        {
            Assert.Equal(
                InterruptedCaptureDisposition.DiscardAfterCentralResolution,
                InterruptedCapturePolicy.Decide(interrupted, "task-old", status, hasPendingCompletion: false));
        }
    }

    [Fact]
    public void QueueTimingHighlightsOverdueCallsAndLongWaitingStudents()
    {
        var recentCall = FieldQueueTimingPolicy.Describe("called", 75, false);
        Assert.False(recentCall.IsOverdue);
        Assert.Equal("叫号后 1 分钟", recentCall.Label);

        var overdueCall = FieldQueueTimingPolicy.Describe("called", 185, true);
        Assert.True(overdueCall.IsOverdue);
        Assert.Equal(3, overdueCall.ElapsedMinutes);
        Assert.Contains("到场超时", overdueCall.Label);

        var longWaiting = FieldQueueTimingPolicy.Describe("waiting", 15 * 60, false);
        Assert.True(longWaiting.IsOverdue);
        Assert.Contains("等待过久", longWaiting.Label);

        var severeWaiting = FieldQueueTimingPolicy.Describe("waiting", 31 * 60, false, "critical");
        Assert.True(severeWaiting.IsCritical);
        Assert.Contains("严重积压", severeWaiting.Label);
        Assert.True(FieldQueueTimingPolicy.OperationalPriority("called", overdueCall) < FieldQueueTimingPolicy.OperationalPriority("waiting", severeWaiting));

        var checkedIn = FieldQueueTimingPolicy.Describe("checked_in", 59, false);
        Assert.False(checkedIn.IsOverdue);
        Assert.Contains("不到 1 分钟", checkedIn.Label);
    }

    [Fact]
    public void CaptureEventsBecomeConciseOperatorProgressWithoutExposingArbitraryPayloads()
    {
        using var document = JsonDocument.Parse("""{"item":"侧向滑步","message":"请保持身体在采集区域内","current":2,"total":4,"confidence":0.92,"privateDiagnostic":"do-not-display"}""");
        var action = new CaptureAction(Guid.NewGuid(), 7, "rep.detected", new DateTimeOffset(2026, 8, 28, 1, 2, 3, TimeSpan.Zero), document.RootElement.Clone());

        var presentation = CaptureEventPresentationPolicy.Describe(action, 3);

        Assert.Contains("侧向滑步", presentation.Title);
        Assert.Contains("有效动作", presentation.Title);
        Assert.Contains("进度 2/4", presentation.Detail);
        Assert.Contains("置信度 92", presentation.Detail);
        Assert.Contains("第 3 条设备事件", presentation.Detail);
        Assert.DoesNotContain("do-not-display", presentation.Detail);
    }

    [Fact]
    public void ProtocolProgressTracksTheFixedLaneOrderAndPerItemState()
    {
        using var empty = JsonDocument.Parse("{}");
        using var startedPayload = JsonDocument.Parse("""{"item":"侧向滑步"}""");
        var protocol = new FieldAssessmentProtocol("protocol-1", "seven-action", "七项完整通道", "1.0.0", "", new[]
        {
            new FieldProtocolItem("连续双脚障碍跳", "连续双脚障碍跳", 1, true, empty.RootElement.Clone(), empty.RootElement.Clone()),
            new FieldProtocolItem("侧向滑步", "侧向滑步", 2, true, empty.RootElement.Clone(), empty.RootElement.Clone())
        });
        var progress = FieldProtocolProgressPolicy.Initialize(protocol, null);
        progress = FieldProtocolProgressPolicy.ApplyEvent(progress, new CaptureAction(Guid.NewGuid(), 1, "item.started", DateTimeOffset.UtcNow, startedPayload.RootElement.Clone()));
        progress = FieldProtocolProgressPolicy.ApplyScores(progress, new[] { new FieldScore("连续双脚障碍跳", 4.2m, 0.93m), new FieldScore("侧向滑步", 3.8m, 0.72m) });

        Assert.Equal(new[] { "连续双脚障碍跳", "侧向滑步" }, progress.Select(item => item.Code));
        Assert.Equal("completed", progress[0].Status);
        Assert.Equal("needs_review", progress[1].Status);
    }

    [Fact]
    public void ClientVersionUsesThePublishedAssemblyVersionInsteadOfAHardcodedHeartbeat()
    {
        Assert.Equal("field-client/0.4.2", FieldClientVersion.Format(new Version(0, 4, 2, 0)));
        Assert.Equal("field-client/2.1.0", FieldClientVersion.Format(new Version(2, 1)));
        Assert.Equal("field-client/unknown", FieldClientVersion.Format(null));
    }

    [Fact]
    public async Task PendingQueueVersionChainCanBeRestoredAndConflictsRemainInspectable()
    {
        using var calledPayload = JsonDocument.Parse("{\"queueEntryId\":\"queue-durable\",\"status\":\"called\",\"expectedVersion\":3}");
        using var checkedInPayload = JsonDocument.Parse("{\"queueEntryId\":\"queue-durable\",\"status\":\"checked_in\",\"expectedVersion\":4}");
        var called = new OutboxEvent(Guid.NewGuid(), "queue.transition", DateTimeOffset.UtcNow, calledPayload.RootElement.Clone());
        var checkedIn = new OutboxEvent(Guid.NewGuid(), "queue.transition", DateTimeOffset.UtcNow.AddMilliseconds(1), checkedInPayload.RootElement.Clone());
        await _store.EnqueueAsync(called, CancellationToken.None);
        await _store.EnqueueAsync(checkedIn, CancellationToken.None);

        var restored = await _store.GetPendingQueueTransitionsAsync(CancellationToken.None);

        Assert.Equal(new[] { 3, 4 }, restored.Select(item => item.ExpectedVersion));
        Assert.Equal("checked_in", restored[^1].Status);
        await _store.MarkConflictAsync(new[] { called.ClientEventId, checkedIn.ClientEventId }, "FIELD_QUEUE_VERSION_CONFLICT", CancellationToken.None);
        Assert.Empty(await _store.GetPendingQueueTransitionsAsync(CancellationToken.None));
        Assert.Equal(2, (await _store.GetConflictedQueueTransitionsAsync(CancellationToken.None)).Count);
    }

    private static QueueEntry Queue(string id, string studentId, string studentName, string stationId, string status, int order, int version) =>
        new(id, "task-1", studentId, stationId, status, 0, order, 0, version, studentName, "三年级2班", $"NO-{studentId}", "男", new DateOnly(2017, 5, 12), "三年级");

    private static HttpResponseMessage JsonResponse(HttpStatusCode statusCode, string json) => new(statusCode)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };

    private sealed class DelegateHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request, cancellationToken);
    }

    public sealed class TestCaptureAdapter : ICaptureAdapter, IFieldHardwareHealthProvider
    {
        public string AdapterName => "test-certified-adapter/1.0";
        public Task<CalibrationCheck> CheckCalibrationAsync(Calibration calibration, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<ICaptureRun> StartAsync(CaptureRequest request, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<FieldHardwareHealth> GetHealthAsync(Calibration? calibration, CancellationToken cancellationToken) => Task.FromResult(FieldHardwareHealthFactory.ManualFallback("test adapter"));
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}
