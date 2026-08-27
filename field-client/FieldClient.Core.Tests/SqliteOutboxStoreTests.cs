using Microsoft.Data.Sqlite;
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
    public void DeviceCredentialsRequireBothEnvironmentPartsOrAValidSecureStoreFallback()
    {
        Assert.Throws<InvalidOperationException>(() => DeviceCredentialSource.Resolve("device-1", null, () => new DeviceCredentials("stored", "key")));
        var environment = DeviceCredentialSource.Resolve("device-1", "environment-key", () => new DeviceCredentials("stored", "key"));
        Assert.Equal("device-1", environment.DeviceId);
        Assert.Equal("environment-key", environment.DeviceKey);
        var secureStore = DeviceCredentialSource.Resolve(null, null, () => new DeviceCredentials("stored-device", "stored-key"));
        Assert.Equal("stored-device", secureStore.DeviceId);
        if (!OperatingSystem.IsWindows()) Assert.Null(WindowsCredentialStore.TryReadDeviceCredentials("XiangshangField:NoCredentialExpectedOnNonWindows"));
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
}
