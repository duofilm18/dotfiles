using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Threading;

namespace CpuUsageWidget;

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private readonly string _settingsPath;
    private readonly WidgetSettings _settings;
    private readonly DispatcherTimer _timer;
    private readonly PerformanceCounter _cpuCounter;
    private NetworkSnapshot _previousNetwork;
    private DateTime _previousSampleTime;

    private string _planText = string.Empty;
    private string _cpuText = "--";
    private string _ramText = "--";
    private string _downText = "--";
    private string _upText = "--";
    private string _titleText = "SYSTEM USAGE";
    private string _cpuCompactText = "--";
    private string _ramCompactText = "--";
    private string _downCompactText = "--";
    private string _upCompactText = "--";
    private double _titleFontSize = 16;
    private double _metaFontSize = 11;
    private double _metricFontSize = 14;
    private double _compactKeyFontSize = 13;
    private double _compactValueFontSize = 13;
    private double _labelColumnWidth = 60;
    private double _headerGap = 10;
    private Thickness _outerPadding = new(14);
    private Visibility _planVisibility = Visibility.Visible;
    private Visibility _fullVisibility = Visibility.Visible;
    private Visibility _compactVisibility = Visibility.Collapsed;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;

        _settingsPath = Path.Combine(AppContext.BaseDirectory, "settings.txt");
        _settings = WidgetSettings.Load(_settingsPath);

        _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
        _ = _cpuCounter.NextValue();

        _previousNetwork = NetworkSnapshot.Capture();
        _previousSampleTime = DateTime.UtcNow;

        PlanText = $"Plan {(int)_settings.DownloadMbps}/{(int)_settings.UploadMbps} Mbps";

        Loaded += OnLoaded;
        Closing += OnClosing;
        SizeChanged += OnSizeChanged;

        _timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(1)
        };
        _timer.Tick += (_, _) => RefreshStats();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string PlanText
    {
        get => _planText;
        set => SetField(ref _planText, value);
    }

    public string CpuText
    {
        get => _cpuText;
        set => SetField(ref _cpuText, value);
    }

    public string RamText
    {
        get => _ramText;
        set => SetField(ref _ramText, value);
    }

    public string DownText
    {
        get => _downText;
        set => SetField(ref _downText, value);
    }

    public string UpText
    {
        get => _upText;
        set => SetField(ref _upText, value);
    }

    public string TitleText
    {
        get => _titleText;
        set => SetField(ref _titleText, value);
    }

    public string CpuCompactText
    {
        get => _cpuCompactText;
        set => SetField(ref _cpuCompactText, value);
    }

    public string RamCompactText
    {
        get => _ramCompactText;
        set => SetField(ref _ramCompactText, value);
    }

    public string DownCompactText
    {
        get => _downCompactText;
        set => SetField(ref _downCompactText, value);
    }

    public string UpCompactText
    {
        get => _upCompactText;
        set => SetField(ref _upCompactText, value);
    }

    public double TitleFontSize
    {
        get => _titleFontSize;
        set => SetField(ref _titleFontSize, value);
    }

    public double MetaFontSize
    {
        get => _metaFontSize;
        set => SetField(ref _metaFontSize, value);
    }

    public double MetricFontSize
    {
        get => _metricFontSize;
        set => SetField(ref _metricFontSize, value);
    }

    public double CompactKeyFontSize
    {
        get => _compactKeyFontSize;
        set => SetField(ref _compactKeyFontSize, value);
    }

    public double CompactValueFontSize
    {
        get => _compactValueFontSize;
        set => SetField(ref _compactValueFontSize, value);
    }

    public double LabelColumnWidth
    {
        get => _labelColumnWidth;
        set => SetField(ref _labelColumnWidth, value);
    }

    public double HeaderGap
    {
        get => _headerGap;
        set => SetField(ref _headerGap, value);
    }

    public Thickness OuterPadding
    {
        get => _outerPadding;
        set => SetField(ref _outerPadding, value);
    }

    public Visibility PlanVisibility
    {
        get => _planVisibility;
        set => SetField(ref _planVisibility, value);
    }

    public Visibility FullVisibility
    {
        get => _fullVisibility;
        set => SetField(ref _fullVisibility, value);
    }

    public Visibility CompactVisibility
    {
        get => _compactVisibility;
        set => SetField(ref _compactVisibility, value);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        ApplySavedSize();
        PlaceWindow();
        ApplyPinnedState();
        BuildContextMenu();
        ApplyLayoutMode();
        _timer.Start();
        RefreshStats();
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        _timer.Stop();
        _cpuCounter.Dispose();
        SaveWindowState();
    }

    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (!IsLoaded)
        {
            return;
        }

        ApplyLayoutMode();
        SaveWindowState();
    }

    private void PlaceWindow()
    {
        var area = SystemParameters.WorkArea;
        var defaultLeft = area.Right - Width - 18;
        var defaultTop = area.Bottom - Height - 18;

        if (_settings.PosX >= 0 && _settings.PosY >= 0)
        {
            Left = Math.Clamp(_settings.PosX, area.Left, area.Right - Width);
            Top = Math.Clamp(_settings.PosY, area.Top, area.Bottom - Height);
            return;
        }

        Left = defaultLeft;
        Top = defaultTop;
    }

    private void ApplySavedSize()
    {
        if (_settings.WindowWidth > 0)
        {
            Width = Math.Max(MinWidth, _settings.WindowWidth);
        }

        if (_settings.WindowHeight > 0)
        {
            Height = Math.Max(MinHeight, _settings.WindowHeight);
        }
    }

    private void RefreshStats()
    {
        try
        {
            if (_settings.Pinned)
            {
                ApplyPinnedState();
            }

            var cpu = (int)Math.Round(_cpuCounter.NextValue(), 0);
            var ram = RamSnapshot.Capture();
            var currentNetwork = NetworkSnapshot.Capture();
            var now = DateTime.UtcNow;
            var elapsed = Math.Max((now - _previousSampleTime).TotalSeconds, 1);

            var downRate = Math.Max((currentNetwork.ReceivedBytes - _previousNetwork.ReceivedBytes) / elapsed, 0);
            var upRate = Math.Max((currentNetwork.SentBytes - _previousNetwork.SentBytes) / elapsed, 0);

            CpuText = $"{cpu,3}%";
            RamText = $"{ram.UsedPercent,4}% ({ram.UsedGb:N1}/{ram.TotalGb:N1} GB)";
            DownText = FormatRateWithUsage(downRate, _settings.DownloadMbps);
            UpText = FormatRateWithUsage(upRate, _settings.UploadMbps);
            CpuCompactText = $"{cpu}%";
            RamCompactText = $"{ram.UsedPercent}%";
            DownCompactText = FormatCompactRate(downRate);
            UpCompactText = FormatCompactRate(upRate);

            _previousNetwork = currentNetwork;
            _previousSampleTime = now;
        }
        catch
        {
            CpuText = "ERR";
            RamText = "ERR";
            DownText = "ERR";
            UpText = "ERR";
            CpuCompactText = "ERR";
            RamCompactText = "ERR";
            DownCompactText = "ERR";
            UpCompactText = "ERR";
        }
    }

    private void BuildContextMenu()
    {
        var menu = new System.Windows.Controls.ContextMenu();

        var pinItem = new System.Windows.Controls.MenuItem();
        void UpdatePinHeader() => pinItem.Header = _settings.Pinned ? "Unpin from top" : "Pin to top";
        UpdatePinHeader();
        pinItem.Click += (_, _) =>
        {
            _settings.Pinned = !_settings.Pinned;
            ApplyPinnedState();
            SaveWindowState();
            UpdatePinHeader();
        };

        var lockItem = new System.Windows.Controls.MenuItem();
        void UpdateLockHeader() => lockItem.Header = _settings.Locked ? "Unlock position" : "Lock position";
        UpdateLockHeader();
        lockItem.Click += (_, _) =>
        {
            _settings.Locked = !_settings.Locked;
            SaveWindowState();
            UpdateLockHeader();
        };

        var exitItem = new System.Windows.Controls.MenuItem { Header = "Exit" };
        exitItem.Click += (_, _) => Close();

        menu.Items.Add(pinItem);
        menu.Items.Add(lockItem);
        menu.Items.Add(new System.Windows.Controls.Separator());
        menu.Items.Add(exitItem);
        ContextMenu = menu;
    }

    private void SaveWindowState()
    {
        _settings.PosX = (int)Math.Round(Left, 0);
        _settings.PosY = (int)Math.Round(Top, 0);
        _settings.WindowWidth = (int)Math.Round(Width, 0);
        _settings.WindowHeight = (int)Math.Round(Height, 0);
        _settings.Save(_settingsPath);
    }

    private void ApplyLayoutMode()
    {
        var isUltraCompact = Width < 185 || Height < 112;
        var isCompact = !isUltraCompact && (Width < 235 || Height < 145);

        if (isUltraCompact)
        {
            TitleText = "SYS";
            TitleFontSize = 12;
            MetaFontSize = 9;
            MetricFontSize = 11;
            CompactKeyFontSize = 11;
            CompactValueFontSize = 11;
            LabelColumnWidth = 46;
            HeaderGap = 6;
            OuterPadding = new Thickness(9, 8, 9, 8);
            PlanVisibility = Visibility.Collapsed;
            FullVisibility = Visibility.Collapsed;
            CompactVisibility = Visibility.Visible;
            return;
        }

        if (isCompact)
        {
            TitleText = "SYSTEM";
            TitleFontSize = 14;
            MetaFontSize = 10;
            MetricFontSize = 12;
            CompactKeyFontSize = 12;
            CompactValueFontSize = 12;
            LabelColumnWidth = 52;
            HeaderGap = 8;
            OuterPadding = new Thickness(11, 10, 11, 10);
            PlanVisibility = Visibility.Collapsed;
            FullVisibility = Visibility.Visible;
            CompactVisibility = Visibility.Collapsed;
            return;
        }

        TitleText = "SYSTEM USAGE";
        TitleFontSize = 16;
        MetaFontSize = 11;
        MetricFontSize = 14;
        CompactKeyFontSize = 13;
        CompactValueFontSize = 13;
        LabelColumnWidth = 60;
        HeaderGap = 10;
        OuterPadding = new Thickness(14);
        PlanVisibility = Visibility.Visible;
        FullVisibility = Visibility.Visible;
        CompactVisibility = Visibility.Collapsed;
    }

    private void ApplyPinnedState()
    {
        Topmost = _settings.Pinned;
    }

    private static string FormatRateWithUsage(double bytesPerSecond, double limitMbps)
    {
        var rateText = FormatRate(bytesPerSecond);
        if (limitMbps <= 0)
        {
            return rateText;
        }

        var currentMbps = (bytesPerSecond * 8) / 1024d / 1024d;
        var usagePercent = Math.Max((int)Math.Round((currentMbps / limitMbps) * 100, 0), 0);
        return $"{rateText} ({usagePercent}%)";
    }

    private static string FormatRate(double bytesPerSecond)
    {
        if (bytesPerSecond < 1024)
        {
            return $"{bytesPerSecond:N0} B/s";
        }

        if (bytesPerSecond < 1024 * 1024)
        {
            return $"{bytesPerSecond / 1024d:N1} KB/s";
        }

        if (bytesPerSecond < 1024 * 1024 * 1024)
        {
            return $"{bytesPerSecond / 1024d / 1024d:N1} MB/s";
        }

        return $"{bytesPerSecond / 1024d / 1024d / 1024d:N2} GB/s";
    }

    private static string FormatCompactRate(double bytesPerSecond)
    {
        if (bytesPerSecond < 1024 * 1024)
        {
            return $"{bytesPerSecond / 1024d:N0}K";
        }

        if (bytesPerSecond < 1024 * 1024 * 1024)
        {
            return $"{bytesPerSecond / 1024d / 1024d:N1}M";
        }

        return $"{bytesPerSecond / 1024d / 1024d / 1024d:N1}G";
    }

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (Equals(field, value))
        {
            return;
        }

        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

internal sealed class WidgetSettings
{
    public double DownloadMbps { get; set; } = 500;
    public double UploadMbps { get; set; } = 500;
    public bool Pinned { get; set; } = true;
    public bool Locked { get; set; }
    public int PosX { get; set; } = -1;
    public int PosY { get; set; } = -1;
    public int WindowWidth { get; set; } = 270;
    public int WindowHeight { get; set; } = 176;

    public static WidgetSettings Load(string path)
    {
        var settings = new WidgetSettings();
        if (!File.Exists(path))
        {
            return settings;
        }

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (string.IsNullOrWhiteSpace(line) || line.StartsWith('#'))
            {
                continue;
            }

            var parts = line.Split('=', 2);
            if (parts.Length != 2)
            {
                continue;
            }

            var key = parts[0].Trim().ToLowerInvariant();
            var value = parts[1].Trim();

            switch (key)
            {
                case "download_mbps" when double.TryParse(value, CultureInfo.InvariantCulture, out var down) && down > 0:
                    settings.DownloadMbps = down;
                    break;
                case "upload_mbps" when double.TryParse(value, CultureInfo.InvariantCulture, out var up) && up > 0:
                    settings.UploadMbps = up;
                    break;
                case "pinned" when bool.TryParse(value, out var pinned):
                    settings.Pinned = pinned;
                    break;
                case "locked" when bool.TryParse(value, out var locked):
                    settings.Locked = locked;
                    break;
                case "pos_x" when int.TryParse(value, CultureInfo.InvariantCulture, out var x):
                    settings.PosX = x;
                    break;
                case "pos_y" when int.TryParse(value, CultureInfo.InvariantCulture, out var y):
                    settings.PosY = y;
                    break;
                case "window_width" when int.TryParse(value, CultureInfo.InvariantCulture, out var width) && width > 0:
                    settings.WindowWidth = width;
                    break;
                case "window_height" when int.TryParse(value, CultureInfo.InvariantCulture, out var height) && height > 0:
                    settings.WindowHeight = height;
                    break;
            }
        }

        return settings;
    }

    public void Save(string path)
    {
        var lines = new[]
        {
            "# Network plan limits for usage percentage",
            $"download_mbps={DownloadMbps.ToString(CultureInfo.InvariantCulture)}",
            $"upload_mbps={UploadMbps.ToString(CultureInfo.InvariantCulture)}",
            $"pinned={Pinned.ToString().ToLowerInvariant()}",
            $"locked={Locked.ToString().ToLowerInvariant()}",
            $"pos_x={PosX}",
            $"pos_y={PosY}",
            $"window_width={WindowWidth}",
            $"window_height={WindowHeight}"
        };

        File.WriteAllLines(path, lines);
    }
}

internal readonly record struct RamSnapshot(double TotalGb, double UsedGb, int UsedPercent)
{
    public static RamSnapshot Capture()
    {
        var info = new Microsoft.VisualBasic.Devices.ComputerInfo();
        var totalGb = Math.Round(info.TotalPhysicalMemory / 1024d / 1024d / 1024d, 1);
        var freeGb = Math.Round(info.AvailablePhysicalMemory / 1024d / 1024d / 1024d, 1);
        var usedGb = Math.Round(totalGb - freeGb, 1);
        var usedPercent = totalGb <= 0 ? 0 : (int)Math.Round((usedGb / totalGb) * 100, 0);
        return new RamSnapshot(totalGb, usedGb, usedPercent);
    }
}

internal readonly record struct NetworkSnapshot(long ReceivedBytes, long SentBytes)
{
    public static NetworkSnapshot Capture()
    {
        var interfaces = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up &&
                        n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                        n.NetworkInterfaceType != NetworkInterfaceType.Tunnel);

        long received = 0;
        long sent = 0;

        foreach (var nic in interfaces)
        {
            var stats = nic.GetIPv4Statistics();
            received += stats.BytesReceived;
            sent += stats.BytesSent;
        }

        return new NetworkSnapshot(received, sent);
    }
}
