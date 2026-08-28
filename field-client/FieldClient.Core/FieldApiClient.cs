using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Xiangshang.FieldClient;

public sealed class FieldApiClient(HttpClient http, DeviceCredentials credentials)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private HttpRequestMessage Request(HttpMethod method, string path, object? body = null)
    {
        var request = new HttpRequestMessage(method, path);
        var payload = body is null ? Array.Empty<byte>() : JsonSerializer.SerializeToUtf8Bytes(body, Json);
        var signed = FieldDeviceRequestSigner.Sign(credentials, method.Method, path, DateTimeOffset.UtcNow, RandomNumberGenerator.GetBytes(16), payload);
        request.Headers.Add("X-Device-Id", credentials.DeviceId);
        request.Headers.Add("X-Device-Timestamp", signed.Timestamp);
        request.Headers.Add("X-Device-Nonce", signed.Nonce);
        request.Headers.Add("X-Device-Body-Hash", signed.BodyHash);
        request.Headers.Add("X-Device-Signature", signed.Signature);
        if (body is not null) {
            request.Content = new ByteArrayContent(payload);
            request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        }
        return request;
    }

    private HttpRequestMessage RequestBytes(HttpMethod method, string path, byte[] payload, string contentType)
    {
        var request = new HttpRequestMessage(method, path);
        var signed = FieldDeviceRequestSigner.Sign(credentials, method.Method, path, DateTimeOffset.UtcNow, RandomNumberGenerator.GetBytes(16), payload);
        request.Headers.Add("X-Device-Id", credentials.DeviceId);
        request.Headers.Add("X-Device-Timestamp", signed.Timestamp);
        request.Headers.Add("X-Device-Nonce", signed.Nonce);
        request.Headers.Add("X-Device-Body-Hash", signed.BodyHash);
        request.Headers.Add("X-Device-Signature", signed.Signature);
        request.Content = new ByteArrayContent(payload);
        request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(contentType);
        return request;
    }

    public async Task<FieldBootstrap> GetBootstrapAsync(string? taskId, CancellationToken cancellationToken)
    {
        var suffix = string.IsNullOrWhiteSpace(taskId) ? string.Empty : $"?taskId={Uri.EscapeDataString(taskId)}";
        using var response = await http.SendAsync(Request(HttpMethod.Get, $"/v1/field/bootstrap{suffix}"), cancellationToken);
        return await ReadDataAsync<FieldBootstrap>(response, cancellationToken);
    }

    public async Task HeartbeatAsync(object health, string softwareVersion, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(Request(HttpMethod.Post, "/v1/field/heartbeat", new { health, softwareVersion }), cancellationToken);
        _ = await ReadDataAsync<JsonElement>(response, cancellationToken);
    }

    public async Task<IReadOnlyList<DeviceCommand>> GetCommandsAsync(CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(Request(HttpMethod.Get, "/v1/field/commands"), cancellationToken);
        var result = await ReadDataAsync<DeviceCommandsResponse>(response, cancellationToken);
        return result.Commands;
    }

    public async Task AcknowledgeCommandAsync(string commandId, bool failed, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(Request(HttpMethod.Post, $"/v1/field/commands/{Uri.EscapeDataString(commandId)}/ack", new { failed }), cancellationToken);
        _ = await ReadDataAsync<JsonElement>(response, cancellationToken);
    }

    public async Task<JsonElement> OpenSessionAsync(object request, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(Request(HttpMethod.Post, "/v1/field/sessions", request), cancellationToken);
        return await ReadDataAsync<JsonElement>(response, cancellationToken);
    }

    public async Task<SyncResult> SyncAsync(SyncBatch batch, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(Request(HttpMethod.Post, "/v1/field/sync/batches", new
        {
            clientBatchId = batch.ClientBatchId,
            events = batch.Events.Select(item => new { clientEventId = item.ClientEventId, eventType = item.EventType, happenedAt = item.HappenedAt, payload = item.Payload })
        }), cancellationToken);
        var raw = await ReadDataAsync<JsonElement>(response, cancellationToken);
        return new SyncResult(batch.ClientBatchId, raw.GetProperty("accepted").GetInt32(), raw.TryGetProperty("idempotent", out var idempotent) && idempotent.GetBoolean(), raw);
    }

    public async Task<IReadOnlyList<FieldSyncConflictResolution>> GetConflictResolutionsAsync(CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(Request(HttpMethod.Get, "/v1/field/sync/conflict-resolutions"), cancellationToken);
        return await ReadDataAsync<IReadOnlyList<FieldSyncConflictResolution>>(response, cancellationToken);
    }

    public async Task<UploadedFieldEvidence> UploadEvidenceAsync(PendingFieldEvidence evidence, CancellationToken cancellationToken)
    {
        if (!File.Exists(evidence.LocalPath)) throw new FileNotFoundException("本地证据文件不存在，不能提交成绩。", evidence.LocalPath);
        var file = new FileInfo(evidence.LocalPath);
        if (file.Length > 20 * 1024 * 1024) throw new InvalidDataException("单个证据文件不能超过 20MB。");
        if (file.Length > int.MaxValue) throw new InvalidDataException("证据文件过大。");

        var payload = await File.ReadAllBytesAsync(evidence.LocalPath, cancellationToken);
        var localChecksum = Convert.ToHexString(SHA256.HashData(payload)).ToLowerInvariant();
        if (!string.IsNullOrWhiteSpace(evidence.ChecksumSha256) && !string.Equals(evidence.ChecksumSha256, localChecksum, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("证据文件校验值与采集设备声明不一致，已停止上传。");
        }

        using var presignResponse = await http.SendAsync(Request(HttpMethod.Post, "/v1/field/files/presign", new
        {
            evidence.FileName,
            evidence.ContentType,
            fileSize = payload.Length
        }), cancellationToken);
        var presign = await ReadDataAsync<FilePresignResponse>(presignResponse, cancellationToken);
        if (!presign.UploadUrl.StartsWith("/v1/field/files/", StringComparison.Ordinal)) throw new InvalidDataException("服务端返回了无效的证据上传地址。");

        using var uploadResponse = await http.SendAsync(RequestBytes(HttpMethod.Put, presign.UploadUrl, payload, evidence.ContentType), cancellationToken);
        var uploaded = await ReadDataAsync<FileUploadResponse>(uploadResponse, cancellationToken);
        if (!string.Equals(uploaded.Id, presign.Id, StringComparison.Ordinal) || !string.Equals(uploaded.ChecksumSha256, localChecksum, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("服务端证据校验结果与本地文件不一致。");
        }
        return new UploadedFieldEvidence(uploaded.Id, uploaded.ChecksumSha256);
    }

    private static async Task<T> ReadDataAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken) where T : notnull
    {
        var envelope = await response.Content.ReadFromJsonAsync<ApiEnvelope<T>>(Json, cancellationToken);
        if (!response.IsSuccessStatusCode || envelope is null || envelope.Data is null)
        {
            var message = envelope?.Message ?? $"HTTP {(int)response.StatusCode}";
            JsonElement? errorData = null;
            if (envelope is not null && envelope.Data is JsonElement data) errorData = data.Clone();
            throw new FieldApiException(response.StatusCode, envelope?.Code ?? "FIELD_API_ERROR", message, errorData);
        }
        return envelope.Data;
    }

    private sealed record ApiEnvelope<T>(string Code, string Message, T Data) where T : notnull;
    private sealed record DeviceCommandsResponse(IReadOnlyList<DeviceCommand> Commands);
    private sealed record FilePresignResponse(string Id, string UploadUrl);
    private sealed record FileUploadResponse(string Id, string ChecksumSha256);
}

public sealed record FieldDeviceRequestSignature(string Timestamp, string Nonce, string BodyHash, string Signature);

public static class FieldDeviceRequestSigner
{
    public static FieldDeviceRequestSignature Sign(DeviceCredentials credentials, string method, string path, DateTimeOffset now, byte[] nonceBytes, byte[]? body = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(credentials.DeviceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(credentials.DeviceKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(method);
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        if (nonceBytes.Length < 16) throw new ArgumentException("设备请求随机数至少需要 128 位。", nameof(nonceBytes));
        var timestamp = now.ToUnixTimeMilliseconds().ToString(System.Globalization.CultureInfo.InvariantCulture);
        var nonce = Convert.ToHexString(nonceBytes).ToLowerInvariant();
        var bodyHash = Convert.ToHexString(SHA256.HashData(body ?? Array.Empty<byte>())).ToLowerInvariant();
        var canonicalRequest = $"{method.ToUpperInvariant()}\n{path}\n{timestamp}\n{nonce}\n{bodyHash}";
        using var signer = new HMACSHA256(Encoding.UTF8.GetBytes(credentials.DeviceKey));
        return new FieldDeviceRequestSignature(timestamp, nonce, bodyHash, Convert.ToHexString(signer.ComputeHash(Encoding.UTF8.GetBytes(canonicalRequest))).ToLowerInvariant());
    }
}

public sealed class FieldApiException(System.Net.HttpStatusCode statusCode, string code, string message, JsonElement? data = null) : Exception(message)
{
    public System.Net.HttpStatusCode StatusCode { get; } = statusCode;
    public string Code { get; } = code;
    public JsonElement? ErrorData { get; } = data;
}
