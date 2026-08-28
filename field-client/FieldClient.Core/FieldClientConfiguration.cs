using System.Text.Json;
using System.Security.Cryptography;

namespace Xiangshang.FieldClient;

public static class FieldClientConfiguration
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { WriteIndented = true };

    public static Uri ResolveApiBaseUrl(string? environmentValue, string configurationPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(configurationPath);
        if (!string.IsNullOrWhiteSpace(environmentValue))
        {
            return SaveApiBaseUrl(environmentValue, configurationPath);
        }

        return TryReadApiBaseUrl(configurationPath)
            ?? throw new InvalidOperationException("未找到中央服务地址。请打开客户端连接设置，填写后台服务地址后进行连接测试。");
    }

    public static Uri ValidateApiBaseUrl(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        if (!Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http"))
            throw new InvalidOperationException("中央服务地址必须是有效的 HTTP(S) 地址。");
        return new Uri(uri.GetLeftPart(UriPartial.Authority).TrimEnd('/') + "/", UriKind.Absolute);
    }

    public static Uri SaveApiBaseUrl(string value, string configurationPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(configurationPath);
        var uri = ValidateApiBaseUrl(value);
        var stored = ReadStoredConfiguration(configurationPath);
        WriteStoredConfiguration(configurationPath, new StoredConfiguration(uri.ToString(), stored?.CaptureAdapterAssembly, stored?.CaptureAdapterType, stored?.CaptureAdapterSha256));
        return uri;
    }

    public static Uri? TryReadApiBaseUrl(string configurationPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(configurationPath);
        if (!File.Exists(configurationPath)) return null;
        try
        {
            var stored = ReadStoredConfiguration(configurationPath);
            return string.IsNullOrWhiteSpace(stored?.ApiBaseUrl) ? null : ValidateApiBaseUrl(stored.ApiBaseUrl);
        }
        catch (JsonException) { return null; }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    public static CaptureAdapterConfiguration? TryReadCaptureAdapter(string configurationPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(configurationPath);
        try
        {
            var stored = ReadStoredConfiguration(configurationPath);
            return string.IsNullOrWhiteSpace(stored?.CaptureAdapterAssembly) || string.IsNullOrWhiteSpace(stored.CaptureAdapterType) || string.IsNullOrWhiteSpace(stored.CaptureAdapterSha256)
                ? null
                : new CaptureAdapterConfiguration(Path.GetFullPath(stored.CaptureAdapterAssembly), stored.CaptureAdapterType.Trim(), stored.CaptureAdapterSha256.Trim().ToLowerInvariant());
        }
        catch (JsonException) { return null; }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
        catch (ArgumentException) { return null; }
        catch (NotSupportedException) { return null; }
    }

    public static CaptureAdapterConfiguration SaveCaptureAdapter(string assemblyPath, string typeName, string configurationPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(configurationPath);
        var adapter = ValidateCaptureAdapter(assemblyPath, typeName);
        var stored = ReadStoredConfiguration(configurationPath);
        if (string.IsNullOrWhiteSpace(stored?.ApiBaseUrl))
            throw new InvalidOperationException("请先保存中央服务连接设置，再配置采集设备。");
        WriteStoredConfiguration(configurationPath, new StoredConfiguration(stored.ApiBaseUrl, adapter.AssemblyPath, adapter.TypeName, adapter.Sha256));
        return adapter;
    }

    public static void ClearCaptureAdapter(string configurationPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(configurationPath);
        var stored = ReadStoredConfiguration(configurationPath);
        if (string.IsNullOrWhiteSpace(stored?.ApiBaseUrl)) return;
        WriteStoredConfiguration(configurationPath, new StoredConfiguration(stored.ApiBaseUrl, null, null, null));
    }

    public static CaptureAdapterConfiguration ValidateCaptureAdapter(string assemblyPath, string typeName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(assemblyPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(typeName);
        var fullPath = Path.GetFullPath(assemblyPath.Trim());
        if (!string.Equals(Path.GetExtension(fullPath), ".dll", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("采集适配器必须是 DLL 文件。");
        if (!File.Exists(fullPath)) throw new FileNotFoundException("认证采集适配器文件不存在。", fullPath);
        return new CaptureAdapterConfiguration(fullPath, typeName.Trim(), ComputeFileSha256(fullPath));
    }

    public static string ComputeFileSha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static StoredConfiguration? ReadStoredConfiguration(string configurationPath)
    {
        if (!File.Exists(configurationPath)) return null;
        return JsonSerializer.Deserialize<StoredConfiguration>(File.ReadAllText(configurationPath), Json);
    }

    private static void WriteStoredConfiguration(string configurationPath, StoredConfiguration configuration)
    {
        var directory = Path.GetDirectoryName(configurationPath);
        if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
        File.WriteAllText(configurationPath, JsonSerializer.Serialize(configuration, Json));
    }

    private sealed record StoredConfiguration(string ApiBaseUrl, string? CaptureAdapterAssembly = null, string? CaptureAdapterType = null, string? CaptureAdapterSha256 = null);
}

public sealed record CaptureAdapterConfiguration(string AssemblyPath, string TypeName, string Sha256);
