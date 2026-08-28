using System.Text.Json;

namespace Xiangshang.FieldClient;

public sealed class OfflineSyncService(FieldApiClient api, SqliteOutboxStore outbox)
{
    public async Task<bool> FlushAsync(CancellationToken cancellationToken)
    {
        var hadSemanticConflict = false;
        var localStatus = await outbox.GetStatusSummaryAsync(cancellationToken);
        if (localStatus.ConflictCount > 0)
        {
            var resolutions = await api.GetConflictResolutionsAsync(cancellationToken);
            foreach (var resolution in resolutions)
            {
                await outbox.ResolveConflictsAsync(resolution.EventIds, $"后台已确认：{resolution.ResolutionNote ?? "未填写处理说明"}", cancellationToken);
            }
        }
        // Drain several bounded chunks so a pre-existing session.open batch
        // cannot make the UI claim success while session.complete is still local.
        for (var round = 0; round < 20; round++)
        {
            var pendingEvidence = await outbox.TakePendingEvidenceAsync(30, cancellationToken);
            foreach (var evidence in pendingEvidence)
            {
                try
                {
                    var uploaded = await api.UploadEvidenceAsync(evidence, cancellationToken);
                    await outbox.MarkEvidenceUploadedAsync(evidence.Id, uploaded, cancellationToken);
                }
                catch (FieldApiException error) when ((int)error.StatusCode is >= 400 and < 500)
                {
                    await outbox.MarkEvidenceFailedAsync(evidence.Id, $"{error.Code}: {error.Message}", conflict: true, cancellationToken);
                    return false;
                }
                catch (Exception error) when (error is FileNotFoundException or InvalidDataException or FormatException)
                {
                    await outbox.MarkEvidenceFailedAsync(evidence.Id, error.Message, conflict: true, cancellationToken);
                    return false;
                }
                catch (Exception error)
                {
                    await outbox.MarkEvidenceFailedAsync(evidence.Id, error.Message, conflict: false, cancellationToken);
                    return false;
                }
            }

            var readyCompletions = await outbox.TakeReadyCompletionsAsync(30, cancellationToken);
            foreach (var completion in readyCompletions)
            {
                var evidence = await outbox.GetUploadedEvidenceAsync(completion.SessionId, cancellationToken);
                using var document = JsonDocument.Parse(JsonSerializer.Serialize(new
                {
                    sessionId = completion.SessionId,
                    algorithmVersion = completion.AlgorithmVersion,
                    endedAt = completion.EndedAt,
                    scores = completion.Scores,
                    evidence = evidence.Select(item => new
                    {
                        fileId = item.FileId,
                        evidenceType = item.EvidenceType,
                        checksumSha256 = item.ChecksumSha256,
                        metadata = item.Metadata
                    }),
                    summary = completion.Summary
                }));
                await outbox.EnqueueCompletionAsync(completion, new OutboxEvent(
                    completion.ClientEventId,
                    "session.complete",
                    completion.EndedAt,
                    document.RootElement.Clone()), cancellationToken);
            }

            var batch = await outbox.TakeOrCreatePendingBatchAsync(200, cancellationToken);
            if (batch is null)
            {
                if (pendingEvidence.Count == 30 || readyCompletions.Count == 30) continue;
                return !hadSemanticConflict;
            }
            try
            {
                await api.SyncAsync(new SyncBatch(batch.ClientBatchId, batch.Events), cancellationToken);
                var eventIds = batch.Events.Select(item => item.ClientEventId).ToArray();
                DeleteManagedEvidence(await outbox.CommitSyncedEventsAsync(eventIds, cancellationToken));
            }
            catch (FieldApiException error) when (error.Code == "FIELD_BATCH_IN_PROGRESS")
            {
                // The same durable batch is still being finalized by the central
                // service. Keep it untouched and retry with its original ID.
                return false;
            }
            catch (FieldApiException error) when ((int)error.StatusCode is >= 400 and < 500)
            {
                if (TryReadPartialFailure(error, batch, out var partial))
                {
                    DeleteManagedEvidence(await outbox.ApplyPartialBatchFailureAsync(
                        partial.AcceptedEventIds,
                        partial.FailedEventId,
                        partial.UnprocessedEventIds,
                        $"{error.Code}: {error.Message}（同步批次 {batch.ClientBatchId:N}，事件 {partial.FailedEventId:N}）",
                        cancellationToken));
                    hadSemanticConflict = true;
                    continue;
                }
                // A semantic conflict is visible to the operator; never retry it
                // indefinitely or silently discard the original local facts.
                await outbox.MarkConflictAsync(batch.Events.Select(item => item.ClientEventId), $"{error.Code}: {error.Message}（同步批次 {batch.ClientBatchId:N}）", cancellationToken);
                return false;
            }
            catch (Exception error)
            {
                await outbox.MarkFailedAsync(batch.Events.Select(item => item.ClientEventId), error.Message, cancellationToken);
                return false;
            }
        }
        return false;
    }

    private static bool TryReadPartialFailure(FieldApiException error, PendingSyncBatch batch, out PartialFailureReceipt receipt)
    {
        receipt = default!;
        if (error.ErrorData is not JsonElement data || data.ValueKind != JsonValueKind.Object ||
            !data.TryGetProperty("clientBatchId", out var batchIdValue) || !Guid.TryParse(batchIdValue.GetString(), out var batchId) || batchId != batch.ClientBatchId ||
            !data.TryGetProperty("acceptedEventIds", out var acceptedValue) || !TryReadGuidArray(acceptedValue, out var accepted) ||
            !data.TryGetProperty("failedEventId", out var failedValue) || !Guid.TryParse(failedValue.GetString(), out var failed) ||
            !data.TryGetProperty("unprocessedEventIds", out var unprocessedValue) || !TryReadGuidArray(unprocessedValue, out var unprocessed)) return false;

        var ordered = batch.Events.Select(item => item.ClientEventId).ToArray();
        if (accepted.Length >= ordered.Length || !accepted.SequenceEqual(ordered.Take(accepted.Length)) ||
            failed != ordered[accepted.Length] || !unprocessed.SequenceEqual(ordered.Skip(accepted.Length + 1))) return false;
        receipt = new PartialFailureReceipt(accepted, failed, unprocessed);
        return true;
    }

    private static bool TryReadGuidArray(JsonElement value, out Guid[] result)
    {
        result = [];
        if (value.ValueKind != JsonValueKind.Array) return false;
        var parsed = new List<Guid>();
        foreach (var item in value.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String || !Guid.TryParse(item.GetString(), out var id)) return false;
            parsed.Add(id);
        }
        result = parsed.ToArray();
        return true;
    }

    private static void DeleteManagedEvidence(IEnumerable<string> paths)
    {
        foreach (var localPath in paths)
        {
            try { if (File.Exists(localPath)) File.Delete(localPath); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private sealed record PartialFailureReceipt(IReadOnlyList<Guid> AcceptedEventIds, Guid FailedEventId, IReadOnlyList<Guid> UnprocessedEventIds);
}
