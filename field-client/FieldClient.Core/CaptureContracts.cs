using System.Text.Json;

namespace Xiangshang.FieldClient;

/// <summary>
/// Hardware is intentionally isolated here.  A camera/reader vendor adapter
/// must emit replayable facts; it must not write scores directly to the API.
/// </summary>
public interface ICaptureAdapter : IAsyncDisposable
{
    string AdapterName { get; }
    Task<CalibrationCheck> CheckCalibrationAsync(Calibration calibration, CancellationToken cancellationToken);
    Task<ICaptureRun> StartAsync(CaptureRequest request, CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
}

public sealed record CalibrationCheck(bool Passed, string Message, JsonElement Diagnostics);
public sealed record CaptureRequest(string SessionId, QueueEntry Student, FieldTask Task, Calibration? Calibration);

public interface ICaptureRun : IAsyncDisposable
{
    IAsyncEnumerable<CaptureAction> Events(CancellationToken cancellationToken);
    Task<IReadOnlyList<FieldScore>> GetScoresAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<LocalEvidence>> GetEvidenceAsync(CancellationToken cancellationToken);
}

public sealed record LocalEvidence(string LocalPath, string FileName, string ContentType, string EvidenceType, string? ChecksumSha256, JsonElement? Metadata = null);
