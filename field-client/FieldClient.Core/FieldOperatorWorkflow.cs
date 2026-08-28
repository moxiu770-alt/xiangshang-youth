namespace Xiangshang.FieldClient;

public sealed record FieldOperatorWorkflowPresentation(
    string ActionTitle,
    string ActionDetail,
    string StageIcon,
    string StageTitle,
    string StageDetail,
    bool ShowCall,
    bool ShowCheckIn,
    bool ShowStartCapture,
    bool ShowComplete,
    bool ShowRetest,
    bool ShowRecover,
    bool ShowAbsent)
{
    public bool HasVisibleAction => ShowCall || ShowCheckIn || ShowStartCapture || ShowComplete || ShowRetest || ShowRecover || ShowAbsent;
}

public static class FieldOperatorWorkflow
{
    public static FieldOperatorWorkflowPresentation Describe(
        string? status,
        bool hasStudent,
        bool pausedByCentral,
        bool emergencyStopped,
        bool activeCapture,
        bool interruptedCapture,
        bool connectionAllowsCapture,
        bool readinessReady,
        bool adapterAvailable,
        string? firstBlocker = null)
    {
        if (emergencyStopped)
        {
            return State("现场已紧急停止", "排除风险并解除本地急停后，才能继续学生操作。", "!", "操作已锁定", "当前不会开始新的叫号、签到或采集。", false, false, false, false, false, false, false);
        }
        if (pausedByCentral)
        {
            return State("中央管理端已暂停现场", "请等待后台恢复指令；本机记录和学生名单不会丢失。", "Ⅱ", "现场已暂停", "恢复前不能开始新的学生操作。", false, false, false, false, false, interruptedCapture, false);
        }
        if (interruptedCapture)
        {
            return State("先处理中断采集", "关闭无法恢复的旧会话并自动安排补测，再继续其他学生。", "!", "检测到异常中断", "原设备采集上下文不能安全恢复，本次不会生成成绩。", false, false, false, false, false, true, false);
        }
        if (activeCapture)
        {
            return State("完成动作后核对设备成绩", "提交前会展示逐项成绩、置信度和证据数量；异常时直接安排补测。", "3", "正在认证采集", "保持学生在采集区域内，等待设备完成当前动作。", false, false, false, true, true, false, false);
        }
        if (!hasStudent)
        {
            return State("先选择一名学生", "从左侧候测队列选择学生；默认会定位到当前筛选中的第一位。", "·", "等待选择学生", "学生姓名、班级和学籍身份会显示在上方。", false, false, false, false, false, false, false);
        }

        return status switch
        {
            "waiting" => WaitingForCall(false, connectionAllowsCapture, readinessReady, adapterAvailable, firstBlocker),
            "retest" => WaitingForCall(true, connectionAllowsCapture, readinessReady, adapterAvailable, firstBlocker),
            "called" => State("下一步：核验身份并签到", "当面核对姓名、班级、学籍号、性别和出生日期，确认本人后继续。", "2", "学生已叫号", "点击“核验并签到”会再次弹出完整身份信息。", false, true, false, false, false, false, true),
            "checked_in" => CheckedIn(connectionAllowsCapture, readinessReady, adapterAvailable, firstBlocker),
            "testing" => State("测试状态需要核对", "中央名单仍显示测试中，但本机没有活动采集；请刷新名单或在后台核查会话。", "!", "等待状态核对", "不要为该学生重复开始新的采集。", false, false, false, false, false, false, false),
            "completed" => State("本次测试已提交", "选择下一名候测学生继续；成绩和证据可在后台采集记录中查看。", "✓", "测试已完成", "本机不会重复提交该学生成绩。", false, false, false, false, false, false, false),
            "absent" => State("学生已标记缺席", "如需恢复候测或安排补测，请由后台调度人员处理。", "—", "本次不再叫号", "选择下一名学生继续。", false, false, false, false, false, false, false),
            "paused" => State("学生流程已暂停", "请在后台核对暂停原因并恢复候测，再继续现场操作。", "Ⅱ", "学生流程暂停", "当前不会开始采集。", false, false, false, false, false, false, false),
            "skipped" or "cancelled" => State("该学生已移出当前流程", "如需重新加入，请由后台恢复候测或安排补测。", "—", "当前无需操作", "选择下一名学生继续。", false, false, false, false, false, false, false),
            _ => State("当前状态暂不可操作", "刷新中央名单；若状态仍不明确，请在后台场地中控核查。", "?", "等待状态确认", "不要绕过中央队列直接开始采集。", false, false, false, false, false, false, false)
        };
    }

    private static FieldOperatorWorkflowPresentation WaitingForCall(bool retest, bool connected, bool ready, bool adapterAvailable, string? firstBlocker)
    {
        if (!connected) return State("等待中央服务恢复", "恢复连接并重新确认测试点状态后才能叫号；当前仍可记录学生缺席。", "·", retest ? "补测尚未叫号" : "学生正在候测", "不要让学生进入尚未确认的测试点。", false, false, false, false, false, false, true);
        if (!adapterAvailable) return State("采集设备尚未接入", "点击右侧开测条件中的“接入采集设备”，选择厂商适配器；通过自检前不会开放叫号。", "·", retest ? "补测尚未叫号" : "学生正在候测", "先完成设备接入，再通知学生前往测试点。", false, false, false, false, false, false, true);
        if (!ready) return State("测试点尚未具备叫号条件", string.IsNullOrWhiteSpace(firstBlocker) ? "请按右侧开测检查逐项处理。" : firstBlocker, "·", retest ? "补测尚未叫号" : "学生正在候测", "开测检查通过后会自动开放叫号。", false, false, false, false, false, false, true);
        return retest
            ? State("下一步：重新叫号", "该学生正在补测队列；设备与现场条件已通过，请重新核对身份。", "1", "等待补测", "重新叫号后仍需完成身份核验。", true, false, false, false, false, false, true)
            : State("下一步：叫号", "叫号后请让学生到本站，并当面核对姓名、班级和学籍信息。", "1", "学生正在候测", "确认学生已到场后点击“叫号”。", true, false, false, false, false, false, true);
    }

    private static FieldOperatorWorkflowPresentation CheckedIn(bool connected, bool ready, bool adapterAvailable, string? firstBlocker)
    {
        if (!connected) return State("等待中央服务恢复", "签到已保存在本机；恢复连接并重新确认开测条件后才能正式采集。", "2", "学生已签到", "离线状态不会放开正式采集。", false, false, true, false, false, false, true);
        if (!adapterAvailable) return State("采集设备尚未接入", "学生已签到；点击右侧开测条件中的“接入采集设备”，选择项目交付方提供的适配器 DLL。", "2", "学生已签到", "适配器加载并通过硬件自检后才能开始。", false, false, true, false, false, false, true);
        if (!ready) return State("开测条件尚未通过", string.IsNullOrWhiteSpace(firstBlocker) ? "请按右侧开测检查逐项处理。" : firstBlocker, "2", "学生已签到", "条件恢复后“开始采集”会自动启用。", false, false, true, false, false, false, true);
        return State("下一步：开始采集", "确认采集区域无其他人员、设备画面正常后开始正式测试。", "3", "可以开始采集", "点击“开始采集”，随后按项目要求完成动作。", false, false, true, false, false, false, true);
    }

    private static FieldOperatorWorkflowPresentation State(
        string actionTitle, string actionDetail, string stageIcon, string stageTitle, string stageDetail,
        bool call, bool checkIn, bool start, bool complete, bool retest, bool recover, bool absent) =>
        new(actionTitle, actionDetail, stageIcon, stageTitle, stageDetail, call, checkIn, start, complete, retest, recover, absent);
}
