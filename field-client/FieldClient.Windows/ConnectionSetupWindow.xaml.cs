using System.Net.Http;

namespace Xiangshang.FieldClient.Windows;

public partial class ConnectionSetupWindow : System.Windows.Window
{
    private readonly string _configurationPath;
    private readonly DeviceCredentials? _existingCredentials;

    public Uri? SavedApiBaseUri { get; private set; }
    public DeviceCredentials? SavedCredentials { get; private set; }

    public ConnectionSetupWindow(string configurationPath, Uri? existingApiBaseUri = null, DeviceCredentials? existingCredentials = null, string? initialError = null)
    {
        InitializeComponent();
        _configurationPath = configurationPath;
        _existingCredentials = existingCredentials;
        ApiBaseUrlTextBox.Text = existingApiBaseUri?.ToString() ?? string.Empty;
        DeviceIdTextBox.Text = existingCredentials?.DeviceId ?? string.Empty;
        DeviceKeyHint.Text = existingCredentials is null
            ? "密钥仅在后台注册或轮换时显示一次。"
            : "已存在安全保存的密钥；留空可继续沿用，轮换后请填写新密钥。";
        if (!string.IsNullOrWhiteSpace(initialError))
        {
            if (existingApiBaseUri is null || existingCredentials is null)
                ShowInfo("首次连接：请在后台打开对应设备，复制三项接入信息，然后点击上方“从剪贴板粘贴”。");
            else ShowError(initialError);
        }
    }

    private async void SaveButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        ErrorPanel.Visibility = System.Windows.Visibility.Collapsed;
        InfoPanel.Visibility = System.Windows.Visibility.Collapsed;
        SaveButton.IsEnabled = false;
        SaveButton.Content = "正在测试…";
        ConnectionTestStatus.Text = "正在验证中央服务和设备身份…";
        ConnectionTestStatus.Foreground = (System.Windows.Media.Brush)FindResource("Blue");
        try
        {
            var baseUri = FieldClientConfiguration.ValidateApiBaseUrl(ApiBaseUrlTextBox.Text);
            var deviceId = DeviceIdTextBox.Text.Trim();
            var deviceKey = DeviceKeyPasswordBox.Password.Trim();
            if (string.IsNullOrWhiteSpace(deviceId)) throw new InvalidOperationException("请填写后台返回的设备 ID。");
            if (string.IsNullOrWhiteSpace(deviceKey)) deviceKey = _existingCredentials?.DeviceKey ?? string.Empty;
            if (string.IsNullOrWhiteSpace(deviceKey)) throw new InvalidOperationException("请填写后台仅显示一次的设备密钥。");
            var credentials = new DeviceCredentials(deviceId, deviceKey);

            using var http = new HttpClient { BaseAddress = baseUri, Timeout = TimeSpan.FromSeconds(10) };
            var api = new FieldApiClient(http, credentials);
            _ = await api.GetBootstrapAsync(null, CancellationToken.None);

            SavedApiBaseUri = FieldClientConfiguration.SaveApiBaseUrl(baseUri.ToString(), _configurationPath);
            WindowsCredentialStore.SaveDeviceCredentials(credentials);
            SavedCredentials = credentials;
            ClearMatchingImportedClipboard(credentials, SavedApiBaseUri);
            DialogResult = true;
        }
        catch (TaskCanceledException)
        {
            ShowError("连接测试超时。请确认服务器已经启动、地址可从这台 Windows 电脑访问，并检查防火墙是否允许 8080 端口。");
        }
        catch (HttpRequestException error)
        {
            ShowError($"无法访问中央服务：{error.Message}\n\n请确认没有填写 localhost，并检查服务器地址、局域网和防火墙。");
        }
        catch (FieldApiException error) when (error.StatusCode is System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden)
        {
            ShowError("设备身份验证失败。请在后台打开这台设备并轮换密钥，然后重新复制三项接入信息。");
        }
        catch (Exception error)
        {
            ShowError($"连接测试未通过：{error.Message}\n\n请核对服务器地址、设备 ID 和最新密钥；如果后台刚轮换过密钥，旧密钥已经失效。");
        }
        finally
        {
            SaveButton.IsEnabled = true;
            SaveButton.Content = "测试并保存";
        }
    }

    private void ShowError(string message)
    {
        InfoPanel.Visibility = System.Windows.Visibility.Collapsed;
        ErrorText.Text = message;
        ErrorPanel.Visibility = System.Windows.Visibility.Visible;
        ConnectionTestStatus.Text = "连接未通过，请按上方提示处理";
        ConnectionTestStatus.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(178, 44, 44));
    }

    private void ShowInfo(string message)
    {
        ErrorPanel.Visibility = System.Windows.Visibility.Collapsed;
        InfoText.Text = message;
        InfoPanel.Visibility = System.Windows.Visibility.Visible;
        ConnectionTestStatus.Text = "接入信息填写完成后再测试并保存";
        ConnectionTestStatus.Foreground = (System.Windows.Media.Brush)FindResource("Muted");
    }

    private void PasteConnectionButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        ErrorPanel.Visibility = System.Windows.Visibility.Collapsed;
        try
        {
            var value = System.Windows.Clipboard.ContainsText() ? System.Windows.Clipboard.GetText() : string.Empty;
            var import = FieldConnectionImportPolicy.Parse(value);
            ApiBaseUrlTextBox.Text = import.ApiBaseUrl;
            DeviceIdTextBox.Text = import.DeviceId;
            DeviceKeyPasswordBox.Password = import.DeviceKey;
            DeviceKeyHint.Text = "三项接入信息已填入；点击“测试并保存”后会清除匹配的密钥剪贴板内容。";
            ShowInfo("三项接入信息已自动填入。现在点击“测试并保存”，成功后会直接进入本站学生名单。");
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.ExternalException)
        {
            ShowError(error is InvalidOperationException ? error.Message : "无法读取 Windows 剪贴板，请返回后台重新复制后再试。");
        }
    }

    private static void ClearMatchingImportedClipboard(DeviceCredentials credentials, Uri apiBaseUri)
    {
        try
        {
            if (!System.Windows.Clipboard.ContainsText()) return;
            if (!FieldConnectionImportPolicy.TryParse(System.Windows.Clipboard.GetText(), out var import) || import is null) return;
            if (string.Equals(import.DeviceId, credentials.DeviceId, StringComparison.Ordinal)
                && string.Equals(import.DeviceKey, credentials.DeviceKey, StringComparison.Ordinal)
                && FieldClientConfiguration.ValidateApiBaseUrl(import.ApiBaseUrl) == apiBaseUri)
                System.Windows.Clipboard.Clear();
        }
        catch (System.Runtime.InteropServices.ExternalException) { }
    }

    private void CancelButton_Click(object sender, System.Windows.RoutedEventArgs e) => DialogResult = false;
}
