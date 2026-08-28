namespace Xiangshang.FieldClient;

public sealed record FieldReadinessRecoveryPresentation(string Action, string Label, string Hint)
{
    public bool HasAction => Action != "none";
}

public static class FieldReadinessRecoveryPolicy
{
    public static FieldReadinessRecoveryPresentation Describe(
        bool hasTask,
        bool connected,
        bool pausedByCentral,
        bool emergencyStopped,
        bool adapterAvailable,
        bool stationTaskCompatible,
        bool readinessReady,
        string? stationStatus = null)
    {
        if (emergencyStopped)
            return Action("emergency", "解除本地急停", "仅在现场风险已经排除后解除");
        if (pausedByCentral)
            return Action("refresh", "刷新后台状态", "后台恢复现场后，重新读取控制状态");
        if (!connected)
            return Action("connection", "检查中央连接", "核对服务器地址、设备 ID 和最新密钥");
        if (!hasTask)
            return Action("refresh", "刷新任务和名单", "后台发布任务后在这里重新读取");
        if (stationStatus is "paused" or "maintenance" or "disabled")
            return Action("refresh", "刷新测试点状态", FieldStationStatusPolicy.Describe(stationStatus).RecoveryHint);
        if (stationStatus == "offline")
            return Action("refresh", "等待并刷新连接", FieldStationStatusPolicy.Describe(stationStatus).RecoveryHint);
        if (!adapterAvailable)
            return Action("adapter", "接入采集设备", "选择项目交付方提供的厂商适配器 DLL");
        if (!stationTaskCompatible)
            return Action("refresh", "刷新后台配置", "后台修正测试点能力后重新读取");
        if (!readinessReady)
            return Action("refresh", "重新执行开测检查", "重新上报设备自检并读取中央门禁结果");
        return Action("none", string.Empty, string.Empty);
    }

    private static FieldReadinessRecoveryPresentation Action(string action, string label, string hint) => new(action, label, hint);
}
