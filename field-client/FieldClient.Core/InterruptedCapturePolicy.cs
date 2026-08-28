namespace Xiangshang.FieldClient;

public enum InterruptedCaptureDisposition
{
    RecoverInCurrentTask,
    RetireOutsideCurrentTask,
    DiscardAfterDurableCompletion,
    DiscardAfterCentralResolution
}

public static class InterruptedCapturePolicy
{
    private static readonly HashSet<string> CentralTerminalStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "completed", "retest", "cancelled", "absent"
    };

    public static InterruptedCaptureDisposition Decide(
        InterruptedCaptureState interrupted,
        string? currentTaskId,
        string? centralQueueStatus,
        bool hasPendingCompletion)
    {
        ArgumentNullException.ThrowIfNull(interrupted);
        if (hasPendingCompletion) return InterruptedCaptureDisposition.DiscardAfterDurableCompletion;
        if (!string.Equals(interrupted.TaskId, currentTaskId, StringComparison.Ordinal) || string.IsNullOrWhiteSpace(centralQueueStatus))
            return InterruptedCaptureDisposition.RetireOutsideCurrentTask;
        return CentralTerminalStatuses.Contains(centralQueueStatus)
            ? InterruptedCaptureDisposition.DiscardAfterCentralResolution
            : InterruptedCaptureDisposition.RecoverInCurrentTask;
    }
}
