namespace Xiangshang.FieldClient;

/// <summary>
/// Tracks the next central queue version expected by locally queued transitions.
/// The chain stays in memory while the outbox is pending and is rebuilt from the
/// durable SQLite outbox after a client restart.
/// </summary>
public sealed class FieldQueueVersionChain
{
    private readonly Dictionary<string, int> _nextExpectedVersions = new(StringComparer.Ordinal);

    public IReadOnlyCollection<string> QueueEntryIds => _nextExpectedVersions.Keys;

    public int GetExpectedVersion(QueueEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);
        return _nextExpectedVersions.TryGetValue(entry.Id, out var version) ? version : entry.StateVersion;
    }

    public void MarkTransitionQueued(string queueEntryId, int expectedVersion)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(queueEntryId);
        if (expectedVersion < 1) throw new ArgumentOutOfRangeException(nameof(expectedVersion));
        if (_nextExpectedVersions.TryGetValue(queueEntryId, out var nextExpected) && nextExpected != expectedVersion)
        {
            throw new InvalidOperationException($"队列 {queueEntryId} 的本地版本链不连续：应为 {nextExpected}，实际为 {expectedVersion}。");
        }
        _nextExpectedVersions[queueEntryId] = checked(expectedVersion + 1);
    }

    public void RestoreTransition(string queueEntryId, int expectedVersion)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(queueEntryId);
        if (expectedVersion < 1) return;
        var followingVersion = checked(expectedVersion + 1);
        if (!_nextExpectedVersions.TryGetValue(queueEntryId, out var current) || followingVersion > current)
        {
            _nextExpectedVersions[queueEntryId] = followingVersion;
        }
    }

    public bool HasPending(string queueEntryId) => _nextExpectedVersions.ContainsKey(queueEntryId);

    public bool TryReconcile(QueueEntry centralEntry, string optimisticStatus)
    {
        ArgumentNullException.ThrowIfNull(centralEntry);
        if (!_nextExpectedVersions.TryGetValue(centralEntry.Id, out var nextExpected)) return false;
        if (!string.Equals(centralEntry.Status, optimisticStatus, StringComparison.Ordinal) || centralEntry.StateVersion < nextExpected) return false;
        _nextExpectedVersions.Remove(centralEntry.Id);
        return true;
    }

    public void Remove(string queueEntryId) => _nextExpectedVersions.Remove(queueEntryId);

    public void Clear() => _nextExpectedVersions.Clear();
}
