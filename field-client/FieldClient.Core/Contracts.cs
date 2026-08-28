using System.Text.Json;

namespace Xiangshang.FieldClient;

public sealed record DeviceCredentials(string DeviceId, string DeviceKey);

public sealed record FieldBootstrap(
    DateTimeOffset ServerTime,
    FieldDevice Device,
    FieldStation? Station,
    Calibration? Calibration,
    FieldReadiness Readiness,
    FieldTask? Task,
    IReadOnlyList<FieldTaskOption>? AvailableTasks,
    IReadOnlyList<QueueEntry> Queue,
    IReadOnlyList<AssessmentStandard> Standards,
    IReadOnlyList<DeviceCommand> Commands,
    FieldQueueSummary? QueueSummary = null,
    FieldAssessmentProtocol? Protocol = null);

public sealed record FieldDevice(string Id, string Code, string Name, string Type, string SoftwareVersion, string? ControlState);
public sealed record FieldStation(string Id, string StationCode, string Name, string? ItemCode, int QueueCapacity, string Status, DateTimeOffset? LastSeenAt, string? StatusReason = null, DateTimeOffset? StatusChangedAt = null);
public sealed record Calibration(string Version, string ChecksumSha256, JsonElement Config, DateTimeOffset EffectiveAt);
public sealed record FieldReadiness(bool Ready, string? StationStatus, string? CalibrationVersion, IReadOnlyList<string> Blockers, IReadOnlyList<FieldReadinessCheck>? Checks = null);
public sealed record FieldReadinessCheck(string Key, string Category, string Label, string Status, string Detail, string Remediation, JsonElement? MeasuredValue = null);
public sealed record FieldTask(string Id, string Title, DateOnly TestDate, string Location, IReadOnlyList<string> Items, string RuleVersion, string Status);
public sealed record FieldAssessmentProtocol(string Id, string Code, string Name, string Version, string Description, IReadOnlyList<FieldProtocolItem> Items);
public sealed record FieldProtocolItem(string Code, string Name, int SequenceNo, bool Required, JsonElement SensorProfile, JsonElement RuleConfig);
public sealed record FieldTaskOption(string Id, string Title, DateOnly TestDate, string Location, int TotalCount, int CompletedCount)
{
    public string TimingLabel
    {
        get
        {
            var today = DateOnly.FromDateTime(DateTime.Today);
            return TestDate == today ? "今天" : TestDate < today ? "已延期" : "待开始";
        }
    }

    public string DisplayName => $"[{TimingLabel}] {Title} · {TestDate:yyyy-MM-dd} · {CompletedCount}/{TotalCount}";
}
public sealed record FieldQueueSummary(
    int RosterCount,
    int QueuedCount,
    int ActiveQueueCount,
    int StationAssignedCount,
    int StationActiveCount,
    int UnassignedCount,
    int OtherStationCount);
public sealed record AssessmentStandard(string? Id, string StandardVersion, string? SchoolId, string? GradeId, string Region, bool PovertyArea, DateOnly EffectiveDate, JsonElement RuleConfig, JsonElement ReportConfig, JsonElement CourseConfig, string Source, JsonElement AppliesTo);
public sealed record QueueEntry(
    string Id,
    string TaskId,
    string StudentId,
    string? StationId,
    string Status,
    int Priority,
    int QueueOrder,
    int RetestCount,
    int StateVersion,
    string StudentName,
    string ClassName,
    string? StudentNo,
    string? Gender,
    DateOnly? BirthDate,
    string? GradeName,
    int StateAgeSeconds = 0,
    bool CalledOverdue = false,
    DateTimeOffset? LastCalledAt = null,
    DateTimeOffset? UpdatedAt = null,
    string? TimingSeverity = null,
    string? Note = null,
    string? ActiveSessionId = null,
    int CaptureEventCount = 0,
    DateTimeOffset? CaptureStartedAt = null,
    DateTimeOffset? LastCaptureEventAt = null,
    string? LatestCaptureEventType = null,
    JsonElement? LatestCapturePayload = null);
public sealed record DeviceCommand(string Id, string CommandType, JsonElement Payload, string Status, DateTimeOffset CreatedAt, DateTimeOffset? ExpiresAt);

public sealed record CaptureAction(Guid ClientEventId, long SequenceNo, string EventType, DateTimeOffset HappenedAt, JsonElement Payload);
public sealed record FieldScore(string Item, decimal Score, decimal Confidence, string? Note = null, JsonElement? Evidence = null);
public sealed record EvidenceReference(string FileId, string EvidenceType, string? ChecksumSha256, JsonElement? Metadata = null);

public sealed record OutboxEvent(Guid ClientEventId, string EventType, DateTimeOffset HappenedAt, JsonElement Payload);
public sealed record SyncBatch(Guid ClientBatchId, IReadOnlyList<OutboxEvent> Events);
public sealed record PendingSyncBatch(Guid ClientBatchId, IReadOnlyList<OutboxEvent> Events);
public sealed record OutboxConflictSummary(int Count, string? LastError);
public sealed record LocalQueueTransition(string QueueEntryId, string Status, int ExpectedVersion);
public sealed record FieldSyncConflictResolution(Guid ClientBatchId, IReadOnlyList<Guid> EventIds, string? ResolutionNote, DateTimeOffset ResolvedAt);
public sealed record SyncResult(Guid ClientBatchId, int Accepted, bool Idempotent, JsonElement Raw);
public sealed record PendingFieldCompletion(Guid ClientEventId, string SessionId, string AlgorithmVersion, DateTimeOffset EndedAt, JsonElement Scores, JsonElement Summary);
public sealed record PendingFieldEvidence(Guid Id, string SessionId, string LocalPath, string FileName, string ContentType, string EvidenceType, string? ChecksumSha256, JsonElement Metadata, string State = "pending", string? ServerFileId = null);
public sealed record UploadedFieldEvidence(string FileId, string ChecksumSha256);
public sealed record InterruptedCaptureState(Guid OpenEventId, string ClientSessionId, string QueueEntryId, string StudentId, string StudentName, string TaskId, string AdapterName, DateTimeOffset StartedAt);
public sealed record CentralPauseState(string CommandType, DateTimeOffset PausedAt);
public sealed record LocalEmergencyStopState(string Reason, DateTimeOffset TriggeredAt);
