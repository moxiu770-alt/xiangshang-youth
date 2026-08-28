namespace Xiangshang.FieldClient;

/// <summary>
/// Canonical heartbeat payload for the formal visual-testing gate. Vendor
/// adapters populate the same contract; a manual fallback is deliberately
/// reported as not eligible so it cannot be mistaken for calibrated scoring.
/// </summary>
public sealed record FieldHardwareHealth(
    string SchemaVersion,
    FieldSelfTest SelfTest,
    FieldCaptureHealth Capture,
    FieldStorageHealth Storage,
    FieldCalibrationHealth Calibration,
    bool EmergencyStop = false);

public sealed record FieldSelfTest(bool Passed, DateTimeOffset CompletedAt, string? Message = null);
public sealed record FieldCaptureHealth(bool AdapterReady, string? AdapterName, int DepthCameraCount, int RgbCameraCount, bool GpuReady, decimal? FrameSyncOffsetMs);
public sealed record FieldStorageHealth(long FreeMb);
public sealed record FieldCalibrationHealth(bool Passed, string? Version, string? ChecksumSha256, decimal? ErrorCm);

public static class FieldHardwareHealthFactory
{
    public static FieldHardwareHealth ApplyLocalEmergencyStop(FieldHardwareHealth health, bool localEmergencyStop) =>
        health with { EmergencyStop = health.EmergencyStop || localEmergencyStop };

    public static FieldHardwareHealth ManualFallback(string? reason = null)
    {
        var freeMb = 0L;
        try
        {
            var root = Path.GetPathRoot(AppContext.BaseDirectory);
            if (!string.IsNullOrWhiteSpace(root)) freeMb = new DriveInfo(root).AvailableFreeSpace / 1_024 / 1_024;
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }

        return new FieldHardwareHealth(
            "field-health/v1",
            new FieldSelfTest(false, DateTimeOffset.UtcNow, reason ?? "未加载经认证的视觉采集适配器"),
            new FieldCaptureHealth(false, "manual-fallback", 0, 0, false, null),
            new FieldStorageHealth(freeMb),
            new FieldCalibrationHealth(false, null, null, null));
    }
}
