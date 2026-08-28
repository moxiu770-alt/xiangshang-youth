using System.Text.Json;

namespace Xiangshang.FieldClient;

public static class FieldDeviceCommandPolicy
{
    public static QueueEntry? ResolveQueueTarget(JsonElement payload, IReadOnlyList<QueueEntry> queue)
    {
        ArgumentNullException.ThrowIfNull(queue);
        if (payload.ValueKind != JsonValueKind.Object) return null;
        var queueEntryId = payload.TryGetProperty("queueEntryId", out var queueEntryValue) && queueEntryValue.ValueKind == JsonValueKind.String
            ? queueEntryValue.GetString()
            : null;
        if (!string.IsNullOrWhiteSpace(queueEntryId)) return queue.FirstOrDefault(item => item.Id == queueEntryId);
        var studentId = payload.TryGetProperty("studentId", out var studentValue) && studentValue.ValueKind == JsonValueKind.String
            ? studentValue.GetString()
            : null;
        return string.IsNullOrWhiteSpace(studentId) ? null : queue.FirstOrDefault(item => item.StudentId == studentId);
    }
}
