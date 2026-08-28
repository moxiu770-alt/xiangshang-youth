namespace Xiangshang.FieldClient;

public sealed record FieldQueueDelta(
    bool IsInitial,
    IReadOnlyList<string> AddedStudents,
    IReadOnlyList<string> RemovedStudents,
    IReadOnlyList<string> UpdatedStudents)
{
    public bool HasChanges => AddedStudents.Count > 0 || RemovedStudents.Count > 0 || UpdatedStudents.Count > 0;

    public string ToOperatorMessage()
    {
        var changes = new List<string>();
        if (AddedStudents.Count > 0) changes.Add($"新增 {AddedStudents.Count} 人（{Preview(AddedStudents)}）");
        if (RemovedStudents.Count > 0) changes.Add($"移出 {RemovedStudents.Count} 人（{Preview(RemovedStudents)}）");
        if (UpdatedStudents.Count > 0) changes.Add($"状态或顺序更新 {UpdatedStudents.Count} 人（{Preview(UpdatedStudents)}）");
        return HasChanges ? $"后台调度已同步：{string.Join("；", changes)}。请按最新名单操作。" : "候测名单没有变化。";
    }

    private static string Preview(IReadOnlyList<string> names) =>
        string.Join("、", names.Take(3)) + (names.Count > 3 ? "等" : string.Empty);
}

public static class FieldQueueChangeDetector
{
    public static FieldQueueDelta Compare(IReadOnlyList<QueueEntry>? previous, IReadOnlyList<QueueEntry> current)
    {
        ArgumentNullException.ThrowIfNull(current);
        if (previous is null) return new FieldQueueDelta(true, [], [], []);

        var previousById = previous.ToDictionary(item => item.Id, StringComparer.Ordinal);
        var currentById = current.ToDictionary(item => item.Id, StringComparer.Ordinal);
        var added = current.Where(item => !previousById.ContainsKey(item.Id)).Select(item => item.StudentName).ToArray();
        var removed = previous.Where(item => !currentById.ContainsKey(item.Id)).Select(item => item.StudentName).ToArray();
        var updated = current.Where(item => previousById.TryGetValue(item.Id, out var old) && Changed(old, item)).Select(item => item.StudentName).ToArray();
        return new FieldQueueDelta(false, added, removed, updated);
    }

    private static bool Changed(QueueEntry previous, QueueEntry current) =>
        previous.StateVersion != current.StateVersion ||
        previous.Status != current.Status ||
        previous.StationId != current.StationId ||
        previous.QueueOrder != current.QueueOrder ||
        previous.Priority != current.Priority;
}
