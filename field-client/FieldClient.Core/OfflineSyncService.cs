namespace Xiangshang.FieldClient;

public sealed class OfflineSyncService(FieldApiClient api, SqliteOutboxStore outbox)
{
    public async Task<bool> FlushAsync(CancellationToken cancellationToken)
    {
        var batch = await outbox.TakeOrCreatePendingBatchAsync(200, cancellationToken);
        if (batch is null) return true;
        try
        {
            await api.SyncAsync(new SyncBatch(batch.ClientBatchId, batch.Events), cancellationToken);
            await outbox.MarkSyncedAsync(batch.Events.Select(item => item.ClientEventId), cancellationToken);
            return true;
        }
        catch (FieldApiException error) when (error.Code == "FIELD_BATCH_IN_PROGRESS")
        {
            // The same durable batch is still being finalized by the central
            // service. Keep it untouched and retry with its original ID.
            return false;
        }
        catch (FieldApiException error) when ((int)error.StatusCode is >= 400 and < 500)
        {
            // A semantic conflict is visible to the operator; never retry it
            // indefinitely or silently discard the original local facts.
            await outbox.MarkConflictAsync(batch.Events.Select(item => item.ClientEventId), $"{error.Code}: {error.Message}", cancellationToken);
            return false;
        }
        catch (Exception error)
        {
            await outbox.MarkFailedAsync(batch.Events.Select(item => item.ClientEventId), error.Message, cancellationToken);
            return false;
        }
    }
}
