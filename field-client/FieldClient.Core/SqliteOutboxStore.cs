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

    public async Task<IReadOnlyList<OutboxEvent>> TakePendingAsync(int limit, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var command = connection.CreateCommand();
        command.CommandText = "SELECT client_event_id,event_type,happened_at,payload_json FROM outbox_events WHERE state='pending' ORDER BY created_at LIMIT $limit";
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
            existing.CommandText = "SELECT sync_batch_id FROM outbox_events WHERE state='pending' AND sync_batch_id IS NOT NULL ORDER BY created_at LIMIT 1";
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
                  ORDER BY created_at LIMIT $limit
                )
                """;
            assign.Parameters.AddWithValue("$batch", batchId);
            assign.Parameters.AddWithValue("$limit", boundedLimit);
            await assign.ExecuteNonQueryAsync(cancellationToken);
        }

        var events = new List<OutboxEvent>();
        var read = connection.CreateCommand();
        read.Transaction = transaction;
        read.CommandText = "SELECT client_event_id,event_type,happened_at,payload_json FROM outbox_events WHERE state='pending' AND sync_batch_id=$batch ORDER BY created_at LIMIT $limit";
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

    public async Task<OutboxConflictSummary> GetConflictSummaryAsync(CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var count = connection.CreateCommand();
        count.CommandText = "SELECT COUNT(*) FROM outbox_events WHERE state='conflict'";
        var total = Convert.ToInt32(await count.ExecuteScalarAsync(cancellationToken));
        if (total == 0) return new OutboxConflictSummary(0, null);
        var latest = connection.CreateCommand();
        latest.CommandText = "SELECT last_error FROM outbox_events WHERE state='conflict' ORDER BY created_at DESC LIMIT 1";
        return new OutboxConflictSummary(total, (string?)await latest.ExecuteScalarAsync(cancellationToken));
    }
}
