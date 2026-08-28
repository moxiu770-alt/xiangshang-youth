namespace Xiangshang.FieldClient;

public static class FieldClientVersion
{
    public static string Format(Version? version)
    {
        if (version is null || version.Major < 0 || version.Minor < 0) return "field-client/unknown";
        return $"field-client/{version.Major}.{version.Minor}.{Math.Max(0, version.Build)}";
    }
}
