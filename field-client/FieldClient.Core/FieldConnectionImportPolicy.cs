using System.Text.Json;

namespace Xiangshang.FieldClient;

public sealed record FieldConnectionImport(string ApiBaseUrl, string DeviceId, string DeviceKey);

public static class FieldConnectionImportPolicy
{
    public const string SchemaVersion = "xiangshang-field-connection/v1";

    public static FieldConnectionImport Parse(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 4_096)
            throw new InvalidOperationException("剪贴板中没有有效的场地端接入信息。");
        try
        {
            using var document = JsonDocument.Parse(value);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || Read(root, "schemaVersion", 80) != SchemaVersion)
                throw new InvalidOperationException("接入信息格式不受支持，请在后台重新点击“一次复制三项接入信息”。");
            var apiBaseUrl = FieldClientConfiguration.ValidateApiBaseUrl(Read(root, "apiBaseUrl", 500)).ToString();
            var deviceId = Read(root, "deviceId", 200);
            var deviceKey = Read(root, "deviceKey", 1_024);
            return new FieldConnectionImport(apiBaseUrl, deviceId, deviceKey);
        }
        catch (JsonException)
        {
            throw new InvalidOperationException("接入信息格式不正确，请在后台重新复制后再试。");
        }
    }

    public static bool TryParse(string? value, out FieldConnectionImport? import)
    {
        try { import = Parse(value ?? string.Empty); return true; }
        catch (InvalidOperationException) { import = null; return false; }
    }

    private static string Read(JsonElement root, string property, int maxLength)
    {
        if (!root.TryGetProperty(property, out var value) || value.ValueKind != JsonValueKind.String)
            throw new InvalidOperationException("接入信息缺少必要字段，请在后台重新复制。");
        var text = value.GetString()?.Trim() ?? string.Empty;
        if (text.Length == 0 || text.Length > maxLength)
            throw new InvalidOperationException("接入信息字段无效，请在后台重新复制。");
        return text;
    }
}
