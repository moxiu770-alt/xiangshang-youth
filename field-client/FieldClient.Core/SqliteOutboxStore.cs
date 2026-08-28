using Microsoft.Data.Sqlite;
using System.Text.Json;

namespace Xiangshang.FieldClient;

/// <summary>Durable outbox: only this store owns reconnect retries.</summary>
public sealed class SqliteOutboxStore(string databasePath)
{
    private readonly string _connectionString = new SqliteConnectionStringBuilder { DataSource = databasePath, Mode = SqliteOpenMode.ReadWriteCreate }.ToString();

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode=WAL;
            PRAGMA foreign_keys=ON;
            CREATE TABLE IF NOT EXISTS outbox_events (
              client_event_id TEXT PRIMARY KEY,
              event_type TEXT NOT NULL,
              happened_at TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              state TEXT NOT NULL DEFAULT 'pending',
              sync_batch_id TEXT,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS field_snapshots (
              key TEXT PRIMARY KEY,
              json TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS pending_field_completions (
              session_id TEXT PRIMARY KEY,
              client_event_id TEXT NOT NULL UNIQUE,
              algorithm_version TEXT NOT NULL,
              ended_at TEXT NOT NULL,
              scores_json TEXT NOT NULL,
              summary_json TEXT NOT NULL,
              state TEXT NOT NULL DEFAULT 'pending',
              last_error TEXT,
              created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS pending_field_evidence (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL REFERENCES pending_field_completions(session_id) ON DELETE CASCADE,
              local_path TEXT NOT NULL,
              file_name TEXT NOT NULL,
              content_type TEXT NOT NULL,
              evidence_type TEXT NOT NULL,
              checksum_sha256 TEXT,
              metadata_json TEXT NOT NULL,
              server_file_id TEXT,
              server_checksum_sha256 TEXT,
              state TEXT NOT NULL DEFAULT 'pending',
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_pending_field_evidence_state ON pending_field_evidence(state, created_at);
            """;
        await command.ExecuteNonQueryAsync(cancellationToken);
        // Existing field terminals upgrade in place before the new index is
        // created; otherwise an old database would not yet have the column.
        var hasBatchColumn = false;
        var columns = connection.CreateCommand();
        columns.CommandText = "PRAGMA table_info(outbox_events)";
        await using (var reader = await columns.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                if (string.Equals(reader.GetString(1), "sync_batch_id", StringComparison.OrdinalIgnoreCase)) hasBatchColumn = true;
            }
        }
        if (!hasBatchColumn)
        {
            var migration = connection.CreateCommand();
            migration.CommandText = "ALTER TABLE outbox_events ADD COLUMN sync_batch_id TEXT";
            await migration.ExecuteNonQueryAsync(cancellationToken);
        }
        var index = connection.CreateCommand();
        index.CommandText = "CREATE INDEX IF NOT EXISTS idx_outbox_events_pending_batch ON outbox_events(state, sync_batch_id, created_at)";
        await index.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task EnqueueAsync(OutboxEvent item, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "INSERT OR IGNORE INTO outbox_events(client_event_id,event_type,happened_at,payload_json,created_at) VALUES($id,$type,$at,$payload,$created)";
        command.Parameters.AddWithValue("$id", item.ClientEventId.ToString());
        command.Parameters.AddWithValue("$type", item.EventType);
        command.Parameters.AddWithValue("$at", item.HappenedAt.ToString("O"));
        command.Parameters.AddWithValue("$payload", item.Payload.GetRawText());
        command.Parameters.AddWithValue("$created", DateTimeOffset.UtcNow.ToString("O"));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<LocalQueueTransition>> GetPendingQueueTransitionsAsync(CancellationToken cancellationToken) =>
        await ReadQueueTransitionsAsync("pending", cancellationToken);

    public async Task<IReadOnlyList<LocalQueueTransition>> GetConflictedQueueTransitionsAsync(CancellationToken cancellationToken) =>
        await ReadQueueTransitionsAsync("conflict", cancellationToken);

    private async Task<IReadOnlyList<LocalQueueTransition>> ReadQueueTransitionsAsync(string state, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "SELECT payload_json FROM outbox_events WHERE state=$state AND event_type='queue.transition' ORDER BY rowid";
        command.Parameters.AddWithValue("$state", state);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var result = new List<LocalQueueTransition>();
        while (await reader.ReadAsync(cancellationToken))
        {
            try
            {
                using var payload = JsonDocument.Parse(reader.GetString(0));
                var root = payload.RootElement;
                var queueEntryId = root.TryGetProperty("queueEntryId", out var id) ? id.GetString() : null;
                var status = root.TryGetProperty("status", out var queueStatus) ? queueStatus.GetString() : null;
                if (string.IsNullOrWhiteSpace(queueEntryId) || string.IsNullOrWhiteSpace(status) ||
                    !root.TryGetProperty("expectedVersion", out var version) || !version.TryGetInt32(out var expectedVersion) || expectedVersion < 1) continue;
                result.Add(new LocalQueueTransition(queueEntryId, status, expectedVersion));
            }
            catch (JsonException)
            {
                // Invalid legacy rows remain available for conflict inspection,
                // but must never influence the optimistic queue shown to staff.
            }
        }
        return result;
    }

    public async Task SavePendingCompletionAsync(PendingFieldCompletion completion, IReadOnlyList<PendingFieldEvidence> evidence, CancellationToken cancellationToken)
    {
        if (evidence.Any(item => item.SessionId != completion.SessionId)) throw new ArgumentException("证据必须属于同一客户端会话。", nameof(evidence));
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        var saveCompletion = connection.CreateCommand();
        saveCompletion.Transaction = transaction;
        saveCompletion.CommandText = """
            INSERT OR IGNORE INTO pending_field_completions(session_id,client_event_id,algorithm_version,ended_at,scores_json,summary_json,created_at)
            VALUES($session,$event,$algorithm,$ended,$scores,$summary,$created)
            """;
        saveCompletion.Parameters.AddWithValue("$session", completion.SessionId);
        saveCompletion.Parameters.AddWithValue("$event", completion.ClientEventId.ToString());
        saveCompletion.Parameters.AddWithValue("$algorithm", completion.AlgorithmVersion);
        saveCompletion.Parameters.AddWithValue("$ended", completion.EndedAt.ToString("O"));
        saveCompletion.Parameters.AddWithValue("$scores", completion.Scores.GetRawText());
        saveCompletion.Parameters.AddWithValue("$summary", completion.Summary.GetRawText());
        saveCompletion.Parameters.AddWithValue("$created", DateTimeOffset.UtcNow.ToString("O"));
        await saveCompletion.ExecuteNonQueryAsync(cancellationToken);
        foreach (var item in evidence)
        {
            var saveEvidence = connection.CreateCommand();
            saveEvidence.Transaction = transaction;
            saveEvidence.CommandText = """
                INSERT OR IGNORE INTO pending_field_evidence(id,session_id,local_path,file_name,content_type,evidence_type,checksum_sha256,metadata_json,created_at)
                VALUES($id,$session,$path,$name,$contentType,$evidenceType,$checksum,$metadata,$created)
                """;
            saveEvidence.Parameters.AddWithValue("$id", item.Id.ToString());
            saveEvidence.Parameters.AddWithValue("$session", item.SessionId);
            saveEvidence.Parameters.AddWithValue("$path", item.LocalPath);
            saveEvidence.Parameters.AddWithValue("$name", item.FileName);
            saveEvidence.Parameters.AddWithValue("$contentType", item.ContentType);
            saveEvidence.Parameters.AddWithValue("$evidenceType", item.EvidenceType);
            saveEvidence.Parameters.AddWithValue("$checksum", (object?)item.ChecksumSha256 ?? DBNull.Value);
            saveEvidence.Parameters.AddWithValue("$metadata", item.Metadata.GetRawText());
            saveEvidence.Parameters.AddWithValue("$created", DateTimeOffset.UtcNow.ToString("O"));
            await saveEvidence.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<PendingFieldEvidence>> TakePendingEvidenceAsync(int limit, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "SELECT id,session_id,local_path,file_name,content_type,evidence_type,checksum_sha256,metadata_json,state,server_file_id FROM pending_field_evidence WHERE state='pending' ORDER BY rowid LIMIT $limit";
        command.Parameters.AddWithValue("$limit", Math.Clamp(limit, 1, 30));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var result = new List<PendingFieldEvidence>();
        while (await reader.ReadAsync(cancellationToken))
        {
            using var metadata = JsonDocument.Parse(reader.GetString(7));
            result.Add(new PendingFieldEvidence(Guid.Parse(reader.GetString(0)), reader.GetString(1), reader.GetString(2), reader.GetString(3), reader.GetString(4), reader.GetString(5), reader.IsDBNull(6) ? null : reader.GetString(6), metadata.RootElement.Clone(), reader.GetString(8), reader.IsDBNull(9) ? null : reader.GetString(9)));
        }
        return result;
    }

    public async Task MarkEvidenceUploadedAsync(Guid id, UploadedFieldEvidence uploaded, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "UPDATE pending_field_evidence SET state='uploaded',server_file_id=$file,server_checksum_sha256=$checksum,attempts=attempts+1,last_error=NULL WHERE id=$id";
        command.Parameters.AddWithValue("$id", id.ToString());
        command.Parameters.AddWithValue("$file", uploaded.FileId);
        command.Parameters.AddWithValue("$checksum", uploaded.ChecksumSha256);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task MarkEvidenceFailedAsync(Guid id, string error, bool conflict, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "UPDATE pending_field_evidence SET state=$state,attempts=attempts+1,last_error=$error WHERE id=$id";
        command.Parameters.AddWithValue("$id", id.ToString());
        command.Parameters.AddWithValue("$state", conflict ? "conflict" : "pending");
        command.Parameters.AddWithValue("$error", error[..Math.Min(error.Length, 1000)]);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<PendingFieldCompletion>> TakeReadyCompletionsAsync(int limit, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = """
            SELECT session_id,client_event_id,algorithm_version,ended_at,scores_json,summary_json
            FROM pending_field_completions c
            WHERE c.state='pending' AND NOT EXISTS(
              SELECT 1 FROM pending_field_evidence e WHERE e.session_id=c.session_id AND e.state<>'uploaded'
            ) ORDER BY c.rowid LIMIT $limit
            """;
        command.Parameters.AddWithValue("$limit", Math.Clamp(limit, 1, 30));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var result = new List<PendingFieldCompletion>();
        while (await reader.ReadAsync(cancellationToken))
        {
            using var scores = JsonDocument.Parse(reader.GetString(4));
            using var summary = JsonDocument.Parse(reader.GetString(5));
            result.Add(new PendingFieldCompletion(Guid.Parse(reader.GetString(1)), reader.GetString(0), reader.GetString(2), DateTimeOffset.Parse(reader.GetString(3)), scores.RootElement.Clone(), summary.RootElement.Clone()));
        }
        return result;
    }

    public async Task<IReadOnlyList<EvidenceReference>> GetUploadedEvidenceAsync(string sessionId, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "SELECT server_file_id,evidence_type,COALESCE(server_checksum_sha256,checksum_sha256),metadata_json FROM pending_field_evidence WHERE session_id=$session AND state='uploaded' ORDER BY rowid";
        command.Parameters.AddWithValue("$session", sessionId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var result = new List<EvidenceReference>();
        while (await reader.ReadAsync(cancellationToken))
        {
            using var metadata = JsonDocument.Parse(reader.GetString(3));
            result.Add(new EvidenceReference(reader.GetString(0), reader.GetString(1), reader.IsDBNull(2) ? null : reader.GetString(2), metadata.RootElement.Clone()));
        }
        return result;
    }

    public async Task EnqueueCompletionAsync(PendingFieldCompletion completion, OutboxEvent item, CancellationToken cancellationToken)
    {
        if (item.ClientEventId != completion.ClientEventId) throw new ArgumentException("完成事件 ID 与待完成记录不一致。", nameof(item));
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        var enqueue = connection.CreateCommand();
        enqueue.Transaction = transaction;
        enqueue.CommandText = "INSERT OR IGNORE INTO outbox_events(client_event_id,event_type,happened_at,payload_json,created_at) VALUES($id,$type,$at,$payload,$created)";
        enqueue.Parameters.AddWithValue("$id", item.ClientEventId.ToString());
        enqueue.Parameters.AddWithValue("$type", item.EventType);
        enqueue.Parameters.AddWithValue("$at", item.HappenedAt.ToString("O"));
        enqueue.Parameters.AddWithValue("$payload", item.Payload.GetRawText());
        enqueue.Parameters.AddWithValue("$created", DateTimeOffset.UtcNow.ToString("O"));
        await enqueue.ExecuteNonQueryAsync(cancellationToken);
        var update = connection.CreateCommand();
        update.Transaction = transaction;
        update.CommandText = "UPDATE pending_field_completions SET state='enqueued',last_error=NULL WHERE session_id=$session AND client_event_id=$event";
        update.Parameters.AddWithValue("$session", completion.SessionId);
        update.Parameters.AddWithValue("$event", completion.ClientEventId.ToString());
        await update.ExecuteNonQueryAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<string>> FinalizeSyncedCompletionsAsync(IEnumerable<Guid> eventIds, CancellationToken cancellationToken)
    {
        var ids = eventIds.Select(id => id.ToString()).ToArray();
        if (ids.Length == 0) return [];
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        var paths = await FinalizeCompletionRowsAsync(connection, transaction, ids, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return paths;
    }

    private static async Task<List<string>> FinalizeCompletionRowsAsync(SqliteConnection connection, SqliteTransaction transaction, IReadOnlyList<string> eventIds, CancellationToken cancellationToken)
    {
        var paths = new List<string>();
        foreach (var id in eventIds)
        {
            var read = connection.CreateCommand();
            read.Transaction = transaction;
            read.CommandText = "SELECT e.local_path FROM pending_field_evidence e JOIN pending_field_completions c ON c.session_id=e.session_id WHERE c.client_event_id=$event";
            read.Parameters.AddWithValue("$event", id);
            await using (var reader = await read.ExecuteReaderAsync(cancellationToken)) while (await reader.ReadAsync(cancellationToken)) paths.Add(reader.GetString(0));
            var delete = connection.CreateCommand();
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM pending_field_completions WHERE client_event_id=$event";
            delete.Parameters.AddWithValue("$event", id);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }
        return paths;
    }

    public async Task SaveSnapshotAsync(string key, string json, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentException.ThrowIfNullOrWhiteSpace(json);
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO field_snapshots(key,json,updated_at) VALUES($key,$json,$updated)
            ON CONFLICT(key) DO UPDATE SET json=excluded.json,updated_at=excluded.updated_at
            """;
        command.Parameters.AddWithValue("$key", key);
        command.Parameters.AddWithValue("$json", json);
        command.Parameters.AddWithValue("$updated", DateTimeOffset.UtcNow.ToString("O"));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<FieldSnapshot?> ReadSnapshotAsync(string key, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "SELECT json,updated_at FROM field_snapshots WHERE key=$key";
        command.Parameters.AddWithValue("$key", key);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        return new FieldSnapshot(reader.GetString(0), DateTimeOffset.Parse(reader.GetString(1)));
    }

    public async Task DeleteSnapshotAsync(string key, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM field_snapshots WHERE key=$key";
        command.Parameters.AddWithValue("$key", key);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<bool> HasPendingCompletionAsync(string sessionId, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sessionId);
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "SELECT EXISTS(SELECT 1 FROM pending_field_completions WHERE session_id=$session)";
        command.Parameters.AddWithValue("$session", sessionId);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken)) == 1;
    }

    public async Task<IReadOnlyList<OutboxEvent>> TakePendingAsync(int limit, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "SELECT client_event_id,event_type,happened_at,payload_json FROM outbox_events WHERE state='pending' ORDER BY rowid LIMIT $limit";
        command.Parameters.AddWithValue("$limit", Math.Clamp(limit, 1, 200));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var result = new List<OutboxEvent>();
        while (await reader.ReadAsync(cancellationToken))
        {
            using var document = JsonDocument.Parse(reader.GetString(3));
            result.Add(new OutboxEvent(Guid.Parse(reader.GetString(0)), reader.GetString(1), DateTimeOffset.Parse(reader.GetString(2)), document.RootElement.Clone()));
        }
        return result;
    }

    /// <summary>
    /// Returns a durable logical batch. A retry of the same locally pending
    /// facts therefore reuses its clientBatchId and can consume the central
    /// service's cached receipt after a response was lost on the network.
    /// </summary>
    public async Task<PendingSyncBatch?> TakeOrCreatePendingBatchAsync(int limit, CancellationToken cancellationToken)
    {
        var boundedLimit = Math.Clamp(limit, 1, 200);
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        using var transaction = connection.BeginTransaction();

        string? batchId;
        {
            var existing = connection.CreateCommand();
            existing.Transaction = transaction;
            existing.CommandText = "SELECT sync_batch_id FROM outbox_events WHERE state='pending' AND sync_batch_id IS NOT NULL ORDER BY rowid LIMIT 1";
            batchId = (string?)await existing.ExecuteScalarAsync(cancellationToken);
        }

        if (batchId is null)
        {
            batchId = Guid.NewGuid().ToString();
            var assign = connection.CreateCommand();
            assign.Transaction = transaction;
            assign.CommandText = """
                UPDATE outbox_events SET sync_batch_id=$batch
                WHERE client_event_id IN (
                  SELECT client_event_id FROM outbox_events
                  WHERE state='pending' AND sync_batch_id IS NULL
                  ORDER BY rowid LIMIT $limit
                )
                """;
            assign.Parameters.AddWithValue("$batch", batchId);
            assign.Parameters.AddWithValue("$limit", boundedLimit);
            await assign.ExecuteNonQueryAsync(cancellationToken);
        }

        var events = new List<OutboxEvent>();
        var read = connection.CreateCommand();
        read.Transaction = transaction;
        read.CommandText = "SELECT client_event_id,event_type,happened_at,payload_json FROM outbox_events WHERE state='pending' AND sync_batch_id=$batch ORDER BY rowid LIMIT $limit";
        read.Parameters.AddWithValue("$batch", batchId);
        read.Parameters.AddWithValue("$limit", boundedLimit);
        await using (var reader = await read.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                using var document = JsonDocument.Parse(reader.GetString(3));
                events.Add(new OutboxEvent(Guid.Parse(reader.GetString(0)), reader.GetString(1), DateTimeOffset.Parse(reader.GetString(2)), document.RootElement.Clone()));
            }
        }
        await transaction.CommitAsync(cancellationToken);
        return events.Count == 0 ? null : new PendingSyncBatch(Guid.Parse(batchId), events);
    }

    public async Task MarkSyncedAsync(IEnumerable<Guid> eventIds, CancellationToken cancellationToken)
    {
        var ids = eventIds.Select(id => id.ToString()).ToArray();
        if (ids.Length == 0) return;
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        foreach (var id in ids)
        {
            var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "UPDATE outbox_events SET state='synced',attempts=attempts+1,last_error=NULL WHERE client_event_id=$id";
            command.Parameters.AddWithValue("$id", id);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<string>> CommitSyncedEventsAsync(IEnumerable<Guid> eventIds, CancellationToken cancellationToken)
    {
        var ids = eventIds.Select(id => id.ToString()).Distinct(StringComparer.Ordinal).ToArray();
        if (ids.Length == 0) return [];
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        foreach (var id in ids)
        {
            var update = connection.CreateCommand();
            update.Transaction = transaction;
            update.CommandText = "UPDATE outbox_events SET state='synced',attempts=attempts+1,last_error=NULL WHERE client_event_id=$id";
            update.Parameters.AddWithValue("$id", id);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }
        var paths = await FinalizeCompletionRowsAsync(connection, transaction, ids, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return paths;
    }

    public async Task<IReadOnlyList<string>> ApplyPartialBatchFailureAsync(
        IEnumerable<Guid> acceptedEventIds,
        Guid failedEventId,
        IEnumerable<Guid> unprocessedEventIds,
        string error,
        CancellationToken cancellationToken)
    {
        var accepted = acceptedEventIds.Distinct().ToArray();
        var unprocessed = unprocessedEventIds.Distinct().ToArray();
        var allIds = accepted.Append(failedEventId).Concat(unprocessed).ToArray();
        if (allIds.Distinct().Count() != allIds.Length) throw new ArgumentException("部分同步回执包含重复事件 ID。");
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        foreach (var id in accepted)
        {
            var update = connection.CreateCommand();
            update.Transaction = transaction;
            update.CommandText = "UPDATE outbox_events SET state='synced',attempts=attempts+1,last_error=NULL WHERE client_event_id=$id";
            update.Parameters.AddWithValue("$id", id.ToString());
            await update.ExecuteNonQueryAsync(cancellationToken);
        }
        var conflict = connection.CreateCommand();
        conflict.Transaction = transaction;
        conflict.CommandText = "UPDATE outbox_events SET state='conflict',attempts=attempts+1,last_error=$error WHERE client_event_id=$id";
        conflict.Parameters.AddWithValue("$id", failedEventId.ToString());
        conflict.Parameters.AddWithValue("$error", error[..Math.Min(error.Length, 1000)]);
        await conflict.ExecuteNonQueryAsync(cancellationToken);
        foreach (var id in unprocessed)
        {
            var release = connection.CreateCommand();
            release.Transaction = transaction;
            release.CommandText = "UPDATE outbox_events SET sync_batch_id=NULL,last_error=NULL WHERE client_event_id=$id AND state='pending'";
            release.Parameters.AddWithValue("$id", id.ToString());
            await release.ExecuteNonQueryAsync(cancellationToken);
        }
        var paths = await FinalizeCompletionRowsAsync(connection, transaction, accepted.Select(id => id.ToString()).ToArray(), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return paths;
    }

    public async Task MarkFailedAsync(IEnumerable<Guid> eventIds, string error, CancellationToken cancellationToken)
    {
        var ids = eventIds.Select(id => id.ToString()).ToArray();
        if (ids.Length == 0) return;
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        foreach (var id in ids)
        {
            var command = connection.CreateCommand();
            command.CommandText = "UPDATE outbox_events SET attempts=attempts+1,last_error=$error WHERE client_event_id=$id";
            command.Parameters.AddWithValue("$id", id);
            command.Parameters.AddWithValue("$error", error[..Math.Min(error.Length, 1000)]);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    public async Task MarkConflictAsync(IEnumerable<Guid> eventIds, string error, CancellationToken cancellationToken)
    {
        var ids = eventIds.Select(id => id.ToString()).ToArray();
        if (ids.Length == 0) return;
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        foreach (var id in ids)
        {
            var command = connection.CreateCommand();
            command.CommandText = "UPDATE outbox_events SET state='conflict',attempts=attempts+1,last_error=$error WHERE client_event_id=$id";
            command.Parameters.AddWithValue("$id", id);
            command.Parameters.AddWithValue("$error", error[..Math.Min(error.Length, 1000)]);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    public async Task<int> ResolveConflictsAsync(IEnumerable<Guid> eventIds, string resolutionNote, CancellationToken cancellationToken)
    {
        var ids = eventIds.Distinct().Select(id => id.ToString()).ToArray();
        if (ids.Length == 0) return 0;
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        var changed = 0;
        foreach (var id in ids)
        {
            var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "UPDATE outbox_events SET state='resolved',last_error=$note WHERE client_event_id=$id AND state='conflict'";
            command.Parameters.AddWithValue("$id", id);
            command.Parameters.AddWithValue("$note", resolutionNote[..Math.Min(resolutionNote.Length, 1000)]);
            changed += await command.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        return changed;
    }

    public async Task<OutboxConflictSummary> GetConflictSummaryAsync(CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var count = connection.CreateCommand();
        count.CommandText = "SELECT (SELECT COUNT(*) FROM outbox_events WHERE state='conflict') + (SELECT COUNT(*) FROM pending_field_evidence WHERE state='conflict')";
        var total = Convert.ToInt32(await count.ExecuteScalarAsync(cancellationToken));
        if (total == 0) return new OutboxConflictSummary(0, null);
        var latest = connection.CreateCommand();
        latest.CommandText = """
            SELECT last_error FROM (
              SELECT last_error,created_at FROM outbox_events WHERE state='conflict'
              UNION ALL
              SELECT last_error,created_at FROM pending_field_evidence WHERE state='conflict'
            ) ORDER BY created_at DESC LIMIT 1
            """;
        return new OutboxConflictSummary(total, (string?)await latest.ExecuteScalarAsync(cancellationToken));
    }

    public async Task<OutboxStatusSummary> GetStatusSummaryAsync(CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = """
            SELECT
              (SELECT COUNT(*) FROM outbox_events WHERE state='pending')
                + (SELECT COUNT(*) FROM pending_field_evidence WHERE state='pending')
                + (SELECT COUNT(*) FROM pending_field_completions WHERE state='pending'),
              (SELECT COUNT(*) FROM outbox_events WHERE state='conflict')
                + (SELECT COUNT(*) FROM pending_field_evidence WHERE state='conflict')
            """;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return new OutboxStatusSummary(0, 0);
        return new OutboxStatusSummary(reader.GetInt32(0), reader.GetInt32(1));
    }
}

public sealed record FieldSnapshot(string Json, DateTimeOffset UpdatedAt);
public sealed record OutboxStatusSummary(int PendingCount, int ConflictCount);
