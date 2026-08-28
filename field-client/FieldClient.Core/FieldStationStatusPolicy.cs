namespace Xiangshang.FieldClient;

public sealed record FieldStationStatusPresentation(
    bool BlocksOperations,
    string Title,
    string Detail,
    string RecoveryHint);

public static class FieldStationStatusPolicy
{
    public static FieldStationStatusPresentation Describe(string? status, string? statusReason = null)
    {
        var reason = string.IsNullOrWhiteSpace(statusReason) ? null : statusReason.Trim();
        FieldStationStatusPresentation presentation = status switch
        {
            "online" => new FieldStationStatusPresentation(false, "场地已就绪", "测试点在线。", string.Empty),
            "paused" => new(true, "测试点已暂停", "后台保留了本站设备和学生队列，但已暂停新的叫号、签到和采集。", "由后台填写恢复原因并将测试点改为“恢复待连接”，本站会在下一次心跳后自动上线。"),
            "maintenance" => new(true, "测试点处于维护中", "后台已将本站切换为维护状态，当前仅可查看名单和同步已有记录。", "相机、网络和采集主机检修完成后，由后台将测试点改为“恢复待连接”。"),
            "disabled" => new(true, "测试点已停用", "本站已从正式现场流程中停用，客户端不会继续叫号、签到或采集。", "如需重新启用，请由管理员在后台确认设备和队列后恢复测试点。"),
            "offline" => new(true, "测试点正在恢复连接", "中央仍将本站标记为离线，当前不会开放新的现场操作。", "保持中央连接，下一次有效设备心跳会自动将测试点恢复在线。"),
            _ => new(true, "设备尚未绑定有效测试点", "当前没有可用的测试点运行状态，客户端不会开始正式现场操作。", "请在后台绑定测试点并确认设备连接。")
        };
        return reason is null || status == "online"
            ? presentation
            : presentation with { Detail = $"后台说明：{reason}。{presentation.Detail}" };
    }
}
