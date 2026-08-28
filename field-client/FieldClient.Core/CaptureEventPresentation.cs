using System.Globalization;
using System.Text.Json;

namespace Xiangshang.FieldClient;

public sealed record CaptureEventPresentation(
    string Title,
    string Detail,
    string EventType,
    long SequenceNo,
    DateTimeOffset HappenedAt);

/// <summary>
/// Converts vendor-neutral capture facts into concise operator-facing text.
/// Adapters remain free to add diagnostics, while the workstation only exposes
/// a small allow-list of non-sensitive progress fields.
/// </summary>
public static class CaptureEventPresentationPolicy
{
    public static CaptureEventPresentation Describe(CaptureAction action, int observedCount)
    {
        var payload = action.Payload;
        var item = ReadText(payload, "item", "itemName", "movement", "exercise");
        var message = ReadText(payload, "message", "instruction", "hint");
        var phase = ReadText(payload, "phase", "stage", "status");
        var title = EventTitle(action.EventType, item, phase);
        var details = new List<string>();

        if (!string.IsNullOrWhiteSpace(message)) details.Add(message!);
        if (TryReadNumber(payload, out var current, "current", "completed", "rep", "repetition")
            && TryReadNumber(payload, out var total, "total", "target") && total > 0)
            details.Add($"进度 {FormatNumber(current)}/{FormatNumber(total)}");
        else if (TryReadNumber(payload, out var progress, "progress", "percent"))
        {
            var percentage = progress <= 1 ? progress * 100 : progress;
            if (percentage is >= 0 and <= 100) details.Add($"进度 {percentage:0}%");
        }
        if (TryReadNumber(payload, out var confidence, "confidence") && confidence is >= 0 and <= 1)
            details.Add($"置信度 {confidence:P0}");

        details.Add($"第 {Math.Max(1, observedCount)} 条设备事件 · {action.HappenedAt.ToLocalTime():HH:mm:ss}");
        return new CaptureEventPresentation(title, string.Join(" · ", details), action.EventType, action.SequenceNo, action.HappenedAt);
    }

    private static string EventTitle(string? eventType, string? item, string? phase)
    {
        var type = String.IsNullOrWhiteSpace(eventType) ? "capture.event" : eventType.Trim().ToLowerInvariant();
        var label = type switch
        {
            "capture.started" or "session.started" => "采集设备已开始记录",
            "capture.ready" or "subject.ready" => "已识别学生，可以开始动作",
            "capture.completed" or "session.completed" => "设备采集已完成",
            "item.started" or "movement.started" or "exercise.started" => "项目采集开始",
            "item.completed" or "movement.completed" or "exercise.completed" => "项目采集完成",
            "rep.detected" or "repetition.detected" => "已识别一次有效动作",
            "quality.warning" or "capture.warning" => "采集质量提醒",
            "quality.recovered" => "采集质量已恢复",
            _ when type.Contains("warning", StringComparison.Ordinal) || type.Contains("error", StringComparison.Ordinal) => "设备反馈需要关注",
            _ => "收到采集设备反馈"
        };
        var context = !string.IsNullOrWhiteSpace(item) ? item : phase;
        return string.IsNullOrWhiteSpace(context) ? label : $"{context} · {label}";
    }

    private static string? ReadText(JsonElement payload, params string[] names)
    {
        if (payload.ValueKind != JsonValueKind.Object) return null;
        foreach (var name in names)
        {
            if (!payload.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String) continue;
            var text = value.GetString()?.Trim();
            if (!string.IsNullOrWhiteSpace(text)) return text.Length <= 120 ? text : text[..120];
        }
        return null;
    }

    private static bool TryReadNumber(JsonElement payload, out decimal number, params string[] names)
    {
        number = 0;
        if (payload.ValueKind != JsonValueKind.Object) return false;
        foreach (var name in names)
        {
            if (!payload.TryGetProperty(name, out var value)) continue;
            if (value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out number)) return true;
            if (value.ValueKind == JsonValueKind.String
                && decimal.TryParse(value.GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out number)) return true;
        }
        return false;
    }

    private static string FormatNumber(decimal value) => decimal.Truncate(value) == value
        ? value.ToString("0", CultureInfo.InvariantCulture)
        : value.ToString("0.##", CultureInfo.InvariantCulture);
}
