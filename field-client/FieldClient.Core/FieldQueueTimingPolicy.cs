namespace Xiangshang.FieldClient;

public sealed record FieldQueueTiming(string Label, string Severity, int ElapsedMinutes)
{
    public bool IsOverdue => Severity is "warning" or "critical";
    public bool IsCritical => Severity == "critical";
}

public static class FieldQueueTimingPolicy
{
    private const int LongWaitingSeconds = 15 * 60;

    public static FieldQueueTiming Describe(string? status, int stateAgeSeconds, bool calledOverdue, string? centralSeverity = null)
    {
        var seconds = Math.Max(0, stateAgeSeconds);
        var minutes = seconds / 60;
        var duration = minutes < 1 ? "不到 1 分钟" : $"{minutes} 分钟";
        var fallbackSeverity = calledOverdue && status == "called" || status is "waiting" or "retest" && seconds >= 30 * 60
            ? "critical"
            : status is "waiting" or "retest" && seconds >= LongWaitingSeconds ? "warning" : "normal";
        var severity = centralSeverity is "normal" or "warning" or "critical" ? centralSeverity : fallbackSeverity;
        var severeWaiting = status is "waiting" or "retest" && severity == "critical";
        var longWaiting = status is "waiting" or "retest" && severity == "warning";

        return status switch
        {
            "called" => new FieldQueueTiming(severity == "critical" ? $"叫号后 {duration} · 到场超时" : $"叫号后 {duration}", severity, minutes),
            "checked_in" => new FieldQueueTiming($"签到后 {duration}", "normal", minutes),
            "testing" => new FieldQueueTiming($"采集 {duration}", "normal", minutes),
            "retest" => new FieldQueueTiming(severeWaiting ? $"补测候测 {duration} · 严重积压" : longWaiting ? $"补测候测 {duration} · 等待过久" : $"补测候测 {duration}", severity, minutes),
            "waiting" => new FieldQueueTiming(severeWaiting ? $"候测 {duration} · 严重积压" : longWaiting ? $"候测 {duration} · 等待过久" : $"候测 {duration}", severity, minutes),
            _ => new FieldQueueTiming($"状态保持 {duration}", "normal", minutes)
        };
    }

    public static int OperationalPriority(string? status, FieldQueueTiming timing) => status switch
    {
        "testing" => 0,
        "checked_in" => 10,
        "called" when timing.IsCritical => 20,
        "called" => 30,
        "retest" when timing.IsCritical => 40,
        "waiting" when timing.IsCritical => 50,
        "retest" when timing.IsOverdue => 60,
        "waiting" when timing.IsOverdue => 70,
        "retest" => 80,
        "waiting" => 90,
        _ => 100
    };
}
