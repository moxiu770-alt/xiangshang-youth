namespace Xiangshang.FieldClient;

public sealed record CaptureCompletionAssessment(
    bool CanSubmit,
    bool RequiresCentralReview,
    IReadOnlyList<string> Blockers,
    IReadOnlyList<string> LowConfidenceItems);

/// <summary>
/// Mirrors the central movement-score acceptance boundary before a capture is
/// placed in the durable outbox. Invalid adapter output remains a local,
/// operator-visible capture problem instead of becoming a sync conflict later.
/// </summary>
public static class CaptureCompletionPolicy
{
    public const decimal ReviewConfidenceThreshold = 0.8m;

    private static readonly HashSet<string> SupportedItems = new(StringComparer.Ordinal)
    {
        "连续双脚障碍跳",
        "侧向滑步",
        "倒退平衡",
        "接球-上手掷准",
        "手运球绕杆",
        "脚运球变向",
        "定点踢准"
    };

    public static CaptureCompletionAssessment Evaluate(
        IReadOnlyList<FieldScore> scores,
        IReadOnlyList<LocalEvidence> evidence,
        IReadOnlyList<string>? expectedItems = null)
    {
        var blockers = new List<string>();
        if (scores.Count is < 1 or > 7) blockers.Add("认证设备必须生成 1 到 7 项成绩");

        var duplicateItems = scores
            .GroupBy(item => item.Item, StringComparer.Ordinal)
            .Where(group => group.Count() > 1)
            .Select(group => group.Key)
            .ToArray();
        if (duplicateItems.Length > 0) blockers.Add($"成绩项目重复：{string.Join("、", duplicateItems)}");

        var unsupportedItems = scores
            .Where(item => !SupportedItems.Contains(item.Item))
            .Select(item => string.IsNullOrWhiteSpace(item.Item) ? "空项目" : item.Item)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (unsupportedItems.Length > 0) blockers.Add($"存在未支持的成绩项目：{string.Join("、", unsupportedItems)}");

        if (expectedItems is not null)
        {
            var expected = expectedItems.Where(SupportedItems.Contains).Distinct(StringComparer.Ordinal).ToArray();
            var actual = scores.Select(item => item.Item).Distinct(StringComparer.Ordinal).ToArray();
            var missing = expected.Where(item => !actual.Contains(item, StringComparer.Ordinal)).ToArray();
            var unexpected = actual.Where(item => !expected.Contains(item, StringComparer.Ordinal)).ToArray();
            if (expected.Length != expectedItems.Count || expected.Length == 0)
                blockers.Add("中央任务的测评项目配置不合法，请联系后台管理员");
            else if (missing.Length > 0 || unexpected.Length > 0)
            {
                var details = new List<string>();
                if (missing.Length > 0) details.Add($"缺少 {string.Join("、", missing)}");
                if (unexpected.Length > 0) details.Add($"超出任务 {string.Join("、", unexpected)}");
                blockers.Add($"设备成绩与当前任务不一致：{string.Join("；", details)}");
            }
        }

        if (scores.Any(item => item.Score is < 0 or > 5)) blockers.Add("成绩必须在 0 到 5 分之间");
        if (scores.Any(item => item.Confidence is < 0 or > 1)) blockers.Add("成绩置信度必须在 0 到 1 之间");

        if (evidence.Count == 0) blockers.Add("认证设备没有生成可复核证据");
        else if (evidence.Any(item => string.IsNullOrWhiteSpace(item.LocalPath) || !File.Exists(item.LocalPath)))
            blockers.Add("至少一份本地证据文件不存在");

        var lowConfidenceItems = scores
            .Where(item => item.Confidence < ReviewConfidenceThreshold)
            .Select(item => item.Item)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        return new CaptureCompletionAssessment(
            blockers.Count == 0,
            blockers.Count == 0 && lowConfidenceItems.Length > 0,
            blockers,
            lowConfidenceItems);
    }
}
