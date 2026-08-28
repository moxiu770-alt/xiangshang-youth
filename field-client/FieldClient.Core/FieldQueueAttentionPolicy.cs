namespace Xiangshang.FieldClient;

public sealed record FieldQueueAttention(string? StudentId, string? StudentName, string? Status, bool ChangedByCentral)
{
    public string? ToOperatorMessage() => Status switch
    {
        "called" when ChangedByCentral => $"后台已叫号：{StudentName}。已自动定位，请当面核验身份后签到。",
        "checked_in" when ChangedByCentral => $"后台已更新：{StudentName} 已签到。已自动定位，请确认现场状态后继续。",
        "testing" when ChangedByCentral => $"后台已更新：{StudentName} 显示测试中。已自动定位；如本机没有活动采集，请先核查，避免重复测试。",
        _ => null
    };
}

public static class FieldQueueAttentionPolicy
{
    private static readonly string[] ActivePriority = ["testing", "checked_in", "called"];

    public static FieldQueueAttention Select(
        IReadOnlyList<QueueEntry>? previous,
        IReadOnlyList<QueueEntry> current,
        string? selectedStudentId)
    {
        ArgumentNullException.ThrowIfNull(current);
        var previousById = previous?.ToDictionary(item => item.Id, StringComparer.Ordinal)
            ?? new Dictionary<string, QueueEntry>(StringComparer.Ordinal);

        foreach (var status in ActivePriority)
        {
            var changed = current
                .Where(item => item.Status == status)
                .OrderBy(item => item.QueueOrder)
                .FirstOrDefault(item => previousById.TryGetValue(item.Id, out var old) && old.Status != status);
            if (changed is not null) return new FieldQueueAttention(changed.StudentId, changed.StudentName, changed.Status, true);
        }

        var selected = current.FirstOrDefault(item => item.StudentId == selectedStudentId);
        if (selected is not null && ActivePriority.Contains(selected.Status))
            return new FieldQueueAttention(selected.StudentId, selected.StudentName, selected.Status, false);

        foreach (var status in ActivePriority)
        {
            var active = current.Where(item => item.Status == status).OrderBy(item => item.QueueOrder).FirstOrDefault();
            if (active is not null) return new FieldQueueAttention(active.StudentId, active.StudentName, active.Status, false);
        }

        return new FieldQueueAttention(selected?.StudentId, selected?.StudentName, selected?.Status, false);
    }

    public static QueueEntry? SelectNextWaiting(IReadOnlyList<QueueEntry> current, string? stationId)
    {
        ArgumentNullException.ThrowIfNull(current);
        return current
            .Where(item => item.Status is "waiting" or "retest")
            .Where(item => string.IsNullOrWhiteSpace(stationId) || string.Equals(item.StationId, stationId, StringComparison.Ordinal))
            .OrderByDescending(item => item.Priority)
            .ThenBy(item => item.QueueOrder)
            .FirstOrDefault();
    }
}
