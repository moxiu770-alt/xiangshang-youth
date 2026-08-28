using System.IO;

namespace Xiangshang.FieldClient.Windows;

public partial class CaptureAdapterSetupWindow : System.Windows.Window
{
    private readonly string _configurationPath;

    public string? SavedAdapterName { get; private set; }
    public bool AdapterRemoved { get; private set; }

    public CaptureAdapterSetupWindow(string configurationPath)
    {
        InitializeComponent();
        _configurationPath = configurationPath;
        var existing = FieldClientConfiguration.TryReadCaptureAdapter(configurationPath);
        AssemblyPathTextBox.Text = existing?.AssemblyPath ?? string.Empty;
        RemoveButton.IsEnabled = existing is not null;
        if (existing is not null)
        {
            TryDiscoverTypes(existing.TypeName);
            StatusText.Text = $"当前已保存：{existing.TypeName}\nSHA-256 {existing.Sha256}\n{existing.AssemblyPath}";
        }
    }

    private void BrowseButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "选择认证采集适配器",
            Filter = "采集适配器 (*.dll)|*.dll",
            CheckFileExists = true,
            Multiselect = false
        };
        var bundledAdapterDirectory = Path.Combine(AppContext.BaseDirectory, "采集适配器");
        if (Directory.Exists(bundledAdapterDirectory)) dialog.InitialDirectory = bundledAdapterDirectory;
        if (dialog.ShowDialog(this) != true) return;
        AssemblyPathTextBox.Text = dialog.FileName;
        TryDiscoverTypes();
    }

    private void DiscoverButton_Click(object sender, System.Windows.RoutedEventArgs e) => TryDiscoverTypes();

    private void TryDiscoverTypes(string? preferredType = null)
    {
        try
        {
            var types = CaptureAdapterHost.DiscoverAdapterTypes(AssemblyPathTextBox.Text.Trim());
            AdapterTypeComboBox.ItemsSource = types;
            AdapterTypeComboBox.SelectedItem = preferredType is not null && types.Contains(preferredType, StringComparer.Ordinal) ? preferredType : types.FirstOrDefault();
            if (types.Count == 0) throw new InvalidOperationException("DLL 中没有找到同时实现采集与设备自检接口的公开适配器类型。");
            ShowStatus($"已识别 {types.Count} 个适配器：请选择后点击“测试并保存”。", false);
        }
        catch (Exception error)
        {
            AdapterTypeComboBox.ItemsSource = null;
            ShowStatus($"识别失败：{error.GetBaseException().Message}", true);
        }
    }

    private async void SaveButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        SaveButton.IsEnabled = false;
        SaveButton.Content = "正在测试…";
        try
        {
            var assemblyPath = AssemblyPathTextBox.Text.Trim();
            var typeName = AdapterTypeComboBox.SelectedItem as string;
            if (string.IsNullOrWhiteSpace(typeName))
            {
                TryDiscoverTypes();
                typeName = AdapterTypeComboBox.SelectedItem as string;
            }
            if (string.IsNullOrWhiteSpace(typeName)) throw new InvalidOperationException("请选择识别到的认证适配器类型。");
            await using var host = CaptureAdapterHost.Load(assemblyPath, typeName);
            if (!host.IsAvailable) throw new InvalidOperationException(host.UnavailableReason ?? "认证采集适配器无法加载。");
            FieldClientConfiguration.SaveCaptureAdapter(assemblyPath, typeName, _configurationPath);
            SavedAdapterName = host.AdapterName ?? typeName;
            AdapterRemoved = false;
            DialogResult = true;
        }
        catch (Exception error)
        {
            ShowStatus($"测试未通过：{error.GetBaseException().Message}\n\n请确认 DLL 与当前客户端架构匹配，依赖文件也位于同一目录。", true);
        }
        finally
        {
            SaveButton.IsEnabled = true;
            SaveButton.Content = "测试并保存";
        }
    }

    private void RemoveButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        var confirmation = System.Windows.MessageBox.Show(this, "确认移除当前采集适配器配置？移除后仍可查看和调度学生，但不能开始正式采集。", "移除采集设备", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Warning);
        if (confirmation != System.Windows.MessageBoxResult.Yes) return;
        FieldClientConfiguration.ClearCaptureAdapter(_configurationPath);
        SavedAdapterName = null;
        AdapterRemoved = true;
        DialogResult = true;
    }

    private void ShowStatus(string message, bool error)
    {
        StatusText.Text = message;
        StatusText.Foreground = new System.Windows.Media.SolidColorBrush(error ? System.Windows.Media.Color.FromRgb(178, 44, 44) : System.Windows.Media.Color.FromRgb(40, 95, 159));
        StatusPanel.Background = new System.Windows.Media.SolidColorBrush(error ? System.Windows.Media.Color.FromRgb(255, 240, 240) : System.Windows.Media.Color.FromRgb(234, 243, 255));
        StatusPanel.BorderBrush = new System.Windows.Media.SolidColorBrush(error ? System.Windows.Media.Color.FromRgb(241, 198, 198) : System.Windows.Media.Color.FromRgb(201, 220, 247));
    }

    private void CancelButton_Click(object sender, System.Windows.RoutedEventArgs e) => DialogResult = false;
}
