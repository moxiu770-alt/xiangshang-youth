using System.Reflection;

namespace Xiangshang.FieldClient;

/// <summary>
/// Loads a vendor capture package without giving the WPF shell knowledge of a
/// particular camera SDK. The package path and type are deployment settings;
/// no adapter is silently substituted when loading fails.
/// </summary>
public sealed class CaptureAdapterHost : IAsyncDisposable
{
    private readonly ICaptureAdapter? _adapter;
    private readonly IFieldHardwareHealthProvider? _healthProvider;

    private CaptureAdapterHost(ICaptureAdapter? adapter, IFieldHardwareHealthProvider? healthProvider, string? unavailableReason)
    {
        _adapter = adapter;
        _healthProvider = healthProvider;
        UnavailableReason = unavailableReason;
    }

    public bool IsAvailable => _adapter is not null && _healthProvider is not null;
    public string? AdapterName => _adapter?.AdapterName;
    public string? UnavailableReason { get; }

    public static CaptureAdapterHost LoadFromEnvironment()
    {
        var assemblyPath = Environment.GetEnvironmentVariable("FIELD_CAPTURE_ADAPTER_ASSEMBLY");
        var typeName = Environment.GetEnvironmentVariable("FIELD_CAPTURE_ADAPTER_TYPE");
        return Load(assemblyPath, typeName);
    }

    public static CaptureAdapterHost LoadFromConfiguration(string configurationPath)
    {
        var environmentAssembly = Environment.GetEnvironmentVariable("FIELD_CAPTURE_ADAPTER_ASSEMBLY");
        var environmentType = Environment.GetEnvironmentVariable("FIELD_CAPTURE_ADAPTER_TYPE");
        if (!string.IsNullOrWhiteSpace(environmentAssembly) || !string.IsNullOrWhiteSpace(environmentType))
        {
            if (string.IsNullOrWhiteSpace(environmentAssembly) || string.IsNullOrWhiteSpace(environmentType))
                return new CaptureAdapterHost(null, null, "采集适配器环境变量不完整，路径和类型必须同时配置");
            return Load(environmentAssembly, environmentType);
        }
        var stored = FieldClientConfiguration.TryReadCaptureAdapter(configurationPath);
        if (stored is null) return new CaptureAdapterHost(null, null, "未配置认证采集适配器，请点击右侧开测条件中的“接入采集设备”完成设置");
        try
        {
            var actualSha256 = FieldClientConfiguration.ComputeFileSha256(stored.AssemblyPath);
            if (!string.Equals(actualSha256, stored.Sha256, StringComparison.OrdinalIgnoreCase))
                return new CaptureAdapterHost(null, null, "认证采集适配器文件已发生变化，请在“采集设备”中重新识别并确认");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return new CaptureAdapterHost(null, null, $"无法校验认证采集适配器：{error.Message}");
        }
        return Load(stored.AssemblyPath, stored.TypeName);
    }

    public static IReadOnlyList<string> DiscoverAdapterTypes(string assemblyPath)
    {
        var fullPath = Path.GetFullPath(assemblyPath);
        if (!File.Exists(fullPath)) throw new FileNotFoundException("认证采集适配器文件不存在", fullPath);
        try
        {
            return Assembly.LoadFrom(fullPath).GetTypes()
                .Where(type => !type.IsAbstract && !type.IsInterface && typeof(ICaptureAdapter).IsAssignableFrom(type) && typeof(IFieldHardwareHealthProvider).IsAssignableFrom(type) && type.GetConstructor(Type.EmptyTypes) is not null)
                .Select(type => type.FullName!)
                .OrderBy(name => name, StringComparer.Ordinal)
                .ToArray();
        }
        catch (ReflectionTypeLoadException error)
        {
            var detail = error.LoaderExceptions.FirstOrDefault()?.Message ?? error.Message;
            throw new InvalidOperationException($"无法读取采集适配器类型：{detail}", error);
        }
    }

    public static CaptureAdapterHost Load(string? assemblyPath, string? typeName)
    {
        if (string.IsNullOrWhiteSpace(assemblyPath) || string.IsNullOrWhiteSpace(typeName))
            return new CaptureAdapterHost(null, null, "未配置认证采集适配器");
        try
        {
            var fullPath = Path.GetFullPath(assemblyPath);
            if (!File.Exists(fullPath)) return new CaptureAdapterHost(null, null, "认证采集适配器文件不存在");
            var type = Assembly.LoadFrom(fullPath).GetType(typeName, throwOnError: false, ignoreCase: false);
            if (type is null || type.IsAbstract || !typeof(ICaptureAdapter).IsAssignableFrom(type))
                return new CaptureAdapterHost(null, null, "认证采集适配器类型无效");
            if (Activator.CreateInstance(type) is not ICaptureAdapter adapter)
                return new CaptureAdapterHost(null, null, "无法初始化认证采集适配器");
            if (adapter is not IFieldHardwareHealthProvider healthProvider)
            {
                adapter.DisposeAsync().AsTask().GetAwaiter().GetResult();
                return new CaptureAdapterHost(null, null, "认证采集适配器未实现设备自检接口");
            }
            return new CaptureAdapterHost(adapter, healthProvider, null);
        }
        catch (Exception error) when (error is FileNotFoundException or FileLoadException or BadImageFormatException or MissingMethodException or TargetInvocationException)
        {
            return new CaptureAdapterHost(null, null, $"认证采集适配器加载失败：{error.GetBaseException().Message}");
        }
    }

    public Task<FieldHardwareHealth> GetHealthAsync(Calibration? calibration, CancellationToken cancellationToken) =>
        _healthProvider?.GetHealthAsync(calibration, cancellationToken)
        ?? Task.FromResult(FieldHardwareHealthFactory.ManualFallback(UnavailableReason));

    public Task<CalibrationCheck> CheckCalibrationAsync(Calibration calibration, CancellationToken cancellationToken)
    {
        if (_adapter is null) throw new InvalidOperationException(UnavailableReason ?? "认证采集适配器不可用");
        return _adapter.CheckCalibrationAsync(calibration, cancellationToken);
    }

    public Task<ICaptureRun> StartAsync(CaptureRequest request, CancellationToken cancellationToken)
    {
        if (_adapter is null) throw new InvalidOperationException(UnavailableReason ?? "认证采集适配器不可用");
        return _adapter.StartAsync(request, cancellationToken);
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        if (_adapter is null) throw new InvalidOperationException(UnavailableReason ?? "认证采集适配器不可用");
        return _adapter.StopAsync(cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        if (_adapter is not null) await _adapter.DisposeAsync();
    }
}

/// <summary>Implemented by every certified adapter so the central readiness gate receives real diagnostics.</summary>
public interface IFieldHardwareHealthProvider
{
    Task<FieldHardwareHealth> GetHealthAsync(Calibration? calibration, CancellationToken cancellationToken);
}
