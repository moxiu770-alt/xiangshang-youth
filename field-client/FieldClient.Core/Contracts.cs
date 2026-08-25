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
    IReadOnlyList<QueueEntry> Queue,
    IReadOnlyList<AssessmentStandard> Standards,
    IReadOnlyList<DeviceCommand> Commands);

public sealed record FieldDevice(string Id, string Code, string Name, string Type, string SoftwareVersion);
public sealed record FieldStation(string Id, string StationCode, string Name, string? ItemCode, int QueueCapacity, string Status, DateTimeOffset? LastSeenAt);
public sealed record Calibration(string Version, string ChecksumSha256, JsonElement Config, DateTimeOffset EffectiveAt);
public sealed record FieldReadiness(bool Ready, string? StationStatus, string? CalibrationVersion, IReadOnlyList<string> Blockers);
public sealed record FieldTask(string Id, string Title, DateOnly TestDate, string Location, IReadOnlyList<string> Items, string RuleVersion, string Status);
public sealed record AssessmentStandard(string? Id, string StandardVersion, string? SchoolId, string? GradeId, string Region, bool PovertyArea, DateOnly EffectiveDate, JsonElement RuleConfig, JsonElement ReportConfig, JsonElement CourseConfig, string Source, JsonElement AppliesTo);
public sealed record QueueEntry(string Id, string TaskId, string StudentId, string? StationId, string Status, int Priority, int QueueOrder, int RetestCount, int StateVersion, string StudentName, string ClassName);
public sealed record DeviceCommand(string Id, string CommandType, JsonElement Payload, string Status, DateTimeOffset CreatedAt, DateTimeOffset? ExpiresAt);

public sealed record CaptureAction(Guid ClientEventId, long SequenceNo, string EventType, DateTimeOffset HappenedAt, JsonElement Payload);
public sealed record FieldScore(string Item, decimal Score, decimal Confidence, string? Note = null, JsonElement? Evidence = null);
public sealed record EvidenceReference(string FileId, string EvidenceType, string? ChecksumSha256, JsonElement? Metadata = null);

public sealed record OutboxEvent(Guid ClientEventId, string EventType, DateTimeOffset HappenedAt, JsonElement Payload);
public sealed record SyncBatch(Guid ClientBatchId, IReadOnlyList<OutboxEvent> Events);
public sealed record PendingSyncBatch(Guid ClientBatchId, IReadOnlyList<OutboxEvent> Events);
public sealed record OutboxConflictSummary(int Count, string? LastError);
public sealed record SyncResult(Guid ClientBatchId, int Accepted, bool Idempotent, JsonElement Raw);
