namespace Xiangshang.FieldClient;

public sealed record FieldRosterStatus(string CoverageText, string EmptyTitle, string EmptyDetail);

public static class FieldRosterStatusPolicy
{
    public static FieldRosterStatus Describe(bool hasTask, bool hasStation, FieldQueueSummary? summary, int loadedStationStudents)
    {
        if (!hasTask)
            return new FieldRosterStatus("等待后台发布任务", "暂无测评任务", "请先在后台发布体测任务，再返回本站刷新任务和学生名单。");

        if (summary is null)
            return new FieldRosterStatus($"本站已加载 {Math.Max(0, loadedStationStudents)} 名学生", "本站暂无候测学生", "请在后台确认任务名单和测试点分流后刷新。");

        var coverage = $"本站 {summary.StationActiveCount} 人 · 任务 {summary.RosterCount} 人 · 未分配 {summary.UnassignedCount} 人";
        if (summary.RosterCount <= 0)
            return new FieldRosterStatus(coverage, "任务尚未添加学生", "请在后台为当前任务选择班级或学生，并生成候测名单。");
        if (!hasStation)
            return new FieldRosterStatus(coverage, "设备尚未绑定测试点", "请在后台把这台 Windows 场地端绑定到测试点，再刷新名单。");
        if (summary.StationActiveCount <= 0 && summary.UnassignedCount > 0)
            return new FieldRosterStatus(coverage, "本站尚未分配学生", $"任务已有 {summary.RosterCount} 名学生，其中 {summary.UnassignedCount} 人仍未分配；请在后台点击“生成 / 重新分流”。");
        if (summary.StationActiveCount <= 0 && summary.OtherStationCount > 0)
            return new FieldRosterStatus(coverage, "本站当前没有学生", $"当前 {summary.OtherStationCount} 名现场学生已分配到其他测试点；请在后台检查测试能力、容量或人工调整分配。");
        if (loadedStationStudents <= 0)
            return new FieldRosterStatus(coverage, "本站暂无待处理学生", "当前任务没有分配到本站的有效现场学生；如需补测，请先在后台安排补测。");
        return new FieldRosterStatus(coverage, "没有匹配的学生", "请调整搜索词或状态筛选。");
    }
}
