using System.Text.Json;

namespace Xiangshang.FieldClient;

public sealed record FieldProtocolItemProgress(string Code, string Name, int SequenceNo, bool Required, string Status);

public static class FieldProtocolProgressPolicy
{
    public static IReadOnlyList<FieldProtocolItemProgress> Initialize(FieldAssessmentProtocol? protocol, FieldTask? task)
    {
        if (protocol?.Items is { Count: > 0 })
        {
            return protocol.Items.OrderBy(item => item.SequenceNo)
                .Select(item => new FieldProtocolItemProgress(item.Code, item.Name, item.SequenceNo, item.Required, "pending"))
                .ToArray();
        }
        return (task?.Items ?? []).Select((name, index) => new FieldProtocolItemProgress(name, name, index + 1, true, "pending")).ToArray();
    }

    public static IReadOnlyList<FieldProtocolItemProgress> ApplyEvent(IReadOnlyList<FieldProtocolItemProgress> progress, CaptureAction action)
    {
        var status = EventStatus(action.EventType);
        var itemCode = ReadText(action.Payload, "item", "itemCode", "itemName", "movement", "exercise");
        if (status is null || string.IsNullOrWhiteSpace(itemCode)) return progress;
        return progress.Select(item => string.Equals(item.Code, itemCode, StringComparison.Ordinal) || string.Equals(item.Name, itemCode, StringComparison.Ordinal)
            ? item with { Status = status }
            : item).ToArray();
    }

    public static IReadOnlyList<FieldProtocolItemProgress> ApplyScores(IReadOnlyList<FieldProtocolItemProgress> progress, IReadOnlyList<FieldScore> scores)
    {
        var scoreByItem = scores.ToDictionary(item => item.Item, StringComparer.Ordinal);
        return progress.Select(item => scoreByItem.TryGetValue(item.Code, out var score)
            ? item with { Status = score.Confidence < CaptureCompletionPolicy.ReviewConfidenceThreshold ? "needs_review" : "completed" }
            : item).ToArray();
    }

    private static string? EventStatus(string? eventType) => String.IsNullOrWhiteSpace(eventType) ? null : eventType.Trim().ToLowerInvariant() switch
    {
        "item.started" or "movement.started" or "exercise.started" => "running",
        "item.completed" or "movement.completed" or "exercise.completed" => "completed",
        "item.review_required" or "movement.review_required" or "quality.review_required" => "needs_review",
        "item.retest" or "movement.retest" or "exercise.retest" => "retest",
        _ => null
    };

    private static string? ReadText(JsonElement payload, params string[] names)
    {
        if (payload.ValueKind != JsonValueKind.Object) return null;
        foreach (var name in names)
        {
            if (payload.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(value.GetString())) return value.GetString()!.Trim();
        }
        return null;
    }
}
