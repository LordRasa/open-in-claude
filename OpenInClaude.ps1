<#
    Open in Claude — portable folder launcher
    Pick a folder (modern native picker, drag-drop, or a recent) and open it as a new
    Claude Desktop "Code" session via the claude://code/new?folder= deep link.

    Stack: Windows PowerShell 5.1 + WPF. No install required.
    Run:   double-click "Open in Claude.cmd"   (or: powershell -Sta -ExecutionPolicy Bypass -File OpenInClaude.ps1)
#>

trap {
    "$(Get-Date -Format o)`n$($_ | Out-String)`n$($_.ScriptStackTrace)" |
        Set-Content -LiteralPath (Join-Path $env:TEMP 'OpenInClaude-error.log') -Encoding UTF8
    break
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# Hide our OWN console window (brief flash only). Reliable alternative to launcher flags like
# -WindowStyle Hidden, which also suppress the WPF window. No-op under ps2exe -noConsole.
Add-Type -Namespace OIC -Name Win -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
$__console = [OIC.Win]::GetConsoleWindow()
if (-not $env:OIC_TEST -and $__console -ne [System.IntPtr]::Zero) { [OIC.Win]::ShowWindow($__console, 0) | Out-Null }

# Modern native folder picker (IFileOpenDialog) — the same dialog the Claude Desktop app uses.
$script:HasModernPicker = $true
try {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace OICShell {
    [ComImport, Guid("d57c7288-d4ad-4768-be02-9d969532d960"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileOpenDialog {
        [PreserveSig] int Show(IntPtr parent);                                   // IModalWindow
        void SetFileTypes(uint c, IntPtr rg);                                    // IFileDialog ...
        void SetFileTypeIndex(uint i);
        void GetFileTypeIndex(out uint i);
        void Advise(IntPtr p, out uint c);
        void Unadvise(uint c);
        void SetOptions(uint fos);
        void GetOptions(out uint fos);
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem psi);
        void GetCurrentSelection(out IShellItem psi);
        void SetFileName(string n);
        void GetFileName(out string n);
        void SetTitle(string t);
        void SetOkButtonLabel(string t);
        void SetFileNameLabel(string t);
        void GetResult(out IShellItem psi);
        void AddPlace(IShellItem psi, int loc);
        void SetDefaultExtension(string e);
        void Close(int hr);
        void SetClientGuid(ref Guid g);
        void ClearClientData();
        void SetFilter(IntPtr f);
        void GetResults(out IntPtr e);                                           // IFileOpenDialog
        void GetSelectedItems(out IntPtr e);
    }
    [ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItem {
        void BindToHandler(IntPtr bc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem psi);
        void GetDisplayName(uint sigdn, [MarshalAs(UnmanagedType.LPWStr)] out string name);
        void GetAttributes(uint mask, out uint attribs);
        void Compare(IShellItem psi, uint hint, out int order);
    }
    [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
    internal class FileOpenDialogRCW { }
    public static class FolderPicker {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHCreateItemFromParsingName(string path, IntPtr bc, ref Guid riid, out IShellItem item);
        public static string Pick(IntPtr owner, string initial) {
            var dlg = (IFileOpenDialog)new FileOpenDialogRCW();
            uint opts; dlg.GetOptions(out opts);
            dlg.SetOptions(opts | 0x20 | 0x40);   // FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM
            dlg.SetTitle("Choose a folder to open in Claude");
            if (!string.IsNullOrEmpty(initial)) {
                try {
                    Guid g = typeof(IShellItem).GUID; IShellItem si;
                    if (SHCreateItemFromParsingName(initial, IntPtr.Zero, ref g, out si) == 0) dlg.SetFolder(si);
                } catch { }
            }
            if (dlg.Show(owner) != 0) return null;     // cancelled
            IShellItem item; dlg.GetResult(out item);
            string path; item.GetDisplayName(0x80058000, out path);  // SIGDN_FILESYSPATH
            return path;
        }
    }
}
'@
} catch { $script:HasModernPicker = $false }

# ---------------------------------------------------------------- recents store
$script:AppDataDir  = Join-Path $env:APPDATA 'OpenInClaude'
$script:RecentsFile = Join-Path $script:AppDataDir 'recents.json'
$script:MaxRecents  = 8

function Get-Recents {
    if (-not (Test-Path -LiteralPath $script:RecentsFile)) { return @() }
    try {
        $data = Get-Content -LiteralPath $script:RecentsFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        @($data) | Where-Object { $_ -and $_.FullPath -and (Test-Path -LiteralPath $_.FullPath -PathType Container) }
    } catch { @() }
}
function Add-Recent([string]$path) {
    $existing = @(Get-Recents | Where-Object { $_.FullPath -ne $path })
    $entry = [pscustomobject]@{ FullPath = $path; Name = (Split-Path -Leaf $path); LastUsed = (Get-Date).ToString('o') }
    $list  = @($entry) + $existing | Select-Object -First $script:MaxRecents
    if (-not (Test-Path -LiteralPath $script:AppDataDir)) { New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null }
    ($list | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $script:RecentsFile -Encoding UTF8
}
function Remove-Recent([string]$path) {
    $all = if (Test-Path -LiteralPath $script:RecentsFile) {
        try { @(Get-Content -LiteralPath $script:RecentsFile -Raw | ConvertFrom-Json) } catch { @() }
    } else { @() }
    $filtered = @($all | Where-Object { $_.FullPath -ne $path })
    if (-not (Test-Path -LiteralPath $script:AppDataDir)) { New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null }
    $json = if ($filtered.Count -gt 0) { $filtered | ConvertTo-Json -Depth 4 } else { '[]' }
    $json | Set-Content -LiteralPath $script:RecentsFile -Encoding UTF8
}

# ---------------------------------------------------------------- XAML (UI)
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Open in Claude" Width="460" Height="448"
        WindowStyle="None" Background="#262624"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        AllowDrop="True" FontFamily="Segoe UI" SnapsToDevicePixels="True">

  <Window.Resources>
    <SolidColorBrush x:Key="Card"     Color="#262624"/>
    <SolidColorBrush x:Key="Input"    Color="#30302E"/>
    <SolidColorBrush x:Key="Border"   Color="#3C3B38"/>
    <SolidColorBrush x:Key="TextPri"  Color="#F2EEE5"/>
    <SolidColorBrush x:Key="TextMut"  Color="#9B978C"/>
    <SolidColorBrush x:Key="Accent"   Color="#D97757"/>
    <SolidColorBrush x:Key="AccentHi" Color="#E08763"/>
    <SolidColorBrush x:Key="AccentLo" Color="#C4663F"/>
    <SolidColorBrush x:Key="OnAccent" Color="#1F1E1D"/>

    <!-- Lucide icon geometries (24x24 stroke paths) -->
    <Geometry x:Key="IcoFolderPlus">M12 10v6 M9 13h6 M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z</Geometry>
    <Geometry x:Key="IcoFolder">M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z</Geometry>
    <Geometry x:Key="IcoArrow">M5 12h14 M12 5l7 7-7 7</Geometry>
    <Geometry x:Key="IcoX">m6 6 12 12 M18 6 6 18</Geometry>
    <Geometry x:Key="IcoClock">M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0 M12 6v6l4 2</Geometry>
    <Geometry x:Key="IcoPointer">M4.037 4.688a.495.495 0 0 1 .651-.651l16 6.5a.5.5 0 0 1-.063.947l-6.124 1.58a2 2 0 0 0-1.438 1.435l-1.579 6.126a.5.5 0 0 1-.947.063z</Geometry>
    <Geometry x:Key="IcoTrash2">M3 6h18 M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6 M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2 M10 11v6 M14 11v6</Geometry>

    <Style x:Key="Ico" TargetType="Path">
      <Setter Property="StrokeThickness" Value="2"/>
      <Setter Property="StrokeStartLineCap" Value="Round"/>
      <Setter Property="StrokeEndLineCap" Value="Round"/>
      <Setter Property="StrokeLineJoin" Value="Round"/>
      <Setter Property="Fill" Value="{x:Null}"/>
    </Style>

    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource OnAccent}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{StaticResource Accent}" CornerRadius="8" Padding="16,9">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource AccentHi}"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource AccentLo}"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Background" Value="{StaticResource Input}"/>
                <Setter Property="Foreground" Value="{StaticResource TextMut}"/>
                <Setter Property="Cursor" Value="Arrow"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource TextPri}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="8" Padding="14,9"
                    BorderBrush="{StaticResource Border}" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource Input}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Close" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource TextMut}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="6" Width="28" Height="28">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource Input}"/>
                <Setter Property="Foreground" Value="{StaticResource TextPri}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="RecentList" TargetType="ListBox">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/>
    </Style>
    <Style x:Key="RecentItem" TargetType="ListBoxItem">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="b" Background="Transparent" CornerRadius="8" Padding="10,7" Margin="0,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource Input}"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource Input}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="RecentDelete" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="4" Padding="2">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource Border}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ScrollBar">
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Vertical">
          <Setter Property="Width" Value="12"/>
          <Setter Property="MinWidth" Value="12"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Grid Width="12">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="14"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="14"/>
                  </Grid.RowDefinitions>
                  <RepeatButton Grid.Row="0" Command="ScrollBar.LineUpCommand" Background="Transparent" BorderThickness="0" Focusable="False">
                    <Path Data="M0,6 L4,0 L8,6 Z" Fill="#6E6D6A" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </RepeatButton>
                  <Track Grid.Row="1" x:Name="PART_Track" IsDirectionReversed="True">
                    <Track.DecreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageUpCommand" Background="Transparent" BorderThickness="0" Focusable="False" Opacity="0"/>
                    </Track.DecreaseRepeatButton>
                    <Track.Thumb>
                      <Thumb>
                        <Thumb.Template>
                          <ControlTemplate TargetType="Thumb">
                            <Border Background="#5C5B58" CornerRadius="3" Margin="3,0"/>
                          </ControlTemplate>
                        </Thumb.Template>
                      </Thumb>
                    </Track.Thumb>
                    <Track.IncreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageDownCommand" Background="Transparent" BorderThickness="0" Focusable="False" Opacity="0"/>
                    </Track.IncreaseRepeatButton>
                  </Track>
                  <RepeatButton Grid.Row="2" Command="ScrollBar.LineDownCommand" Background="Transparent" BorderThickness="0" Focusable="False">
                    <Path Data="M0,0 L8,0 L4,6 Z" Fill="#6E6D6A" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </RepeatButton>
                </Grid>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Border Background="{StaticResource Card}" BorderBrush="{StaticResource Border}" BorderThickness="1">
    <Grid Margin="22,16,22,20">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- header -->
      <Grid Grid.Row="0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Viewbox Grid.Column="0" Width="19" Height="19" Margin="0,0,9,0" VerticalAlignment="Center">
          <Grid Width="24" Height="24"><Path Style="{StaticResource Ico}" Data="{StaticResource IcoFolderPlus}" Stroke="{StaticResource Accent}"/></Grid>
        </Viewbox>
        <TextBlock Grid.Column="1" Text="Open a folder in Claude" Foreground="{StaticResource TextPri}" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <Button x:Name="BtnClose" Grid.Column="2">
          <Button.Style><StaticResource ResourceKey="Close"/></Button.Style>
          <Viewbox Width="16" Height="16"><Grid Width="24" Height="24"><Path Style="{StaticResource Ico}" Data="{StaticResource IcoX}" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/></Grid></Viewbox>
        </Button>
      </Grid>

      <!-- subtitle -->
      <TextBlock Grid.Row="1" Text="Pick any folder and open it as a new &lt;/&gt; Code session's folder inside Claude Desktop." Foreground="{StaticResource TextMut}" FontSize="11.5" Margin="0,6,32,0" TextWrapping="Wrap"/>

      <!-- path field -->
      <Border Grid.Row="2" Background="{StaticResource Input}" CornerRadius="8" BorderBrush="{StaticResource Border}" BorderThickness="1" Padding="12,10" Margin="0,16,0,0">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Viewbox Grid.Column="0" Width="16" Height="16" Margin="0,0,9,0" VerticalAlignment="Center">
            <Grid Width="24" Height="24"><Path Style="{StaticResource Ico}" Data="{StaticResource IcoPointer}" Stroke="{StaticResource TextMut}"/></Grid>
          </Viewbox>
          <TextBlock x:Name="TxtPath" Grid.Column="1" Text="Drag a folder here, or choose one&#x2026;" Foreground="{StaticResource TextMut}" FontSize="12.5" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
        </Grid>
      </Border>

      <!-- buttons -->
      <Grid Grid.Row="3" Margin="0,12,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Button x:Name="BtnChoose" Grid.Column="0" Style="{StaticResource Ghost}">
          <StackPanel Orientation="Horizontal">
            <Viewbox Width="16" Height="16" Margin="0,0,8,0"><Grid Width="24" Height="24"><Path Style="{StaticResource Ico}" Data="{StaticResource IcoFolder}" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/></Grid></Viewbox>
            <TextBlock Text="Choose folder" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnOpen" Grid.Column="2" Style="{StaticResource Primary}" IsEnabled="False">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="Open in Claude" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <Viewbox Width="16" Height="16"><Grid Width="24" Height="24"><Path Style="{StaticResource Ico}" Data="{StaticResource IcoArrow}" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/></Grid></Viewbox>
          </StackPanel>
        </Button>
      </Grid>

      <Border Grid.Row="4" Height="1" Background="{StaticResource Border}" Margin="0,18,0,0"/>
      <TextBlock Grid.Row="5" Text="RECENT" Foreground="{StaticResource TextMut}" FontSize="10.5" FontWeight="SemiBold" Margin="2,16,0,6"/>

      <Grid Grid.Row="6">
        <ListBox x:Name="LstRecent" Style="{StaticResource RecentList}" ItemContainerStyle="{StaticResource RecentItem}">
          <ListBox.ItemTemplate>
            <DataTemplate>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <Viewbox Grid.Column="0" Width="15" Height="15" Margin="0,0,10,0" VerticalAlignment="Center"><Grid Width="24" Height="24"><Path Style="{StaticResource Ico}" Data="{StaticResource IcoClock}" Stroke="{StaticResource TextMut}"/></Grid></Viewbox>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                  <TextBlock Text="{Binding Name}" Foreground="{StaticResource TextPri}" FontSize="12.5"/>
                  <TextBlock Text="{Binding FullPath}" Foreground="{StaticResource TextMut}" FontSize="10.5" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <Button Grid.Column="2" Style="{StaticResource RecentDelete}" Tag="delete" Margin="8,0,0,0" VerticalAlignment="Center">
                  <Viewbox Width="14" Height="14"><Grid Width="24" Height="24"><Path Style="{StaticResource Ico}" Data="{StaticResource IcoTrash2}" Stroke="{StaticResource TextMut}"/></Grid></Viewbox>
                </Button>
              </Grid>
            </DataTemplate>
          </ListBox.ItemTemplate>
        </ListBox>
        <TextBlock x:Name="TxtEmpty" Text="No recent folders yet." Foreground="{StaticResource TextMut}" FontSize="12" Margin="2,4,0,0" Visibility="Collapsed"/>
      </Grid>

      <TextBlock x:Name="TxtStatus" Grid.Row="7" Text="" Foreground="{StaticResource Accent}" FontSize="11.5" Margin="2,12,0,0"/>
    </Grid>
  </Border>
</Window>
'@

# ---------------------------------------------------------------- load window
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$TxtPath   = $window.FindName('TxtPath')
$BtnChoose = $window.FindName('BtnChoose')
$BtnOpen   = $window.FindName('BtnOpen')
$BtnClose  = $window.FindName('BtnClose')
$LstRecent = $window.FindName('LstRecent')
$TxtEmpty  = $window.FindName('TxtEmpty')
$TxtStatus = $window.FindName('TxtStatus')

$script:SelectedPath = $null

function Set-SelectedPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $script:SelectedPath = $path.TrimEnd('\')
    $TxtPath.Text = $script:SelectedPath
    $TxtPath.Foreground = $window.FindResource('TextPri')
    $BtnOpen.IsEnabled = $true
    $TxtStatus.Text = ''
}
function Refresh-Recents {
    $items = @(Get-Recents)
    $LstRecent.ItemsSource = $items
    $TxtEmpty.Visibility = if ($items.Count -eq 0) { 'Visible' } else { 'Collapsed' }
}
function Invoke-OpenFolder([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $path = $path.TrimEnd('\')
    Start-Process ('claude://code/new?folder=' + [uri]::EscapeDataString($path))
    Add-Recent $path
    Refresh-Recents
    $TxtStatus.Text = [char]0x2713 + "  Opened  '$(Split-Path -Leaf $path)'  in Claude"
}

# ---------------------------------------------------------------- events
$BtnClose.Add_Click({ $window.Close() })

# whole-window drag (clicks on buttons/list handle themselves and won't drag)
$window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })

$BtnChoose.Add_Click({
    $handle = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
    $picked = $null
    if ($script:HasModernPicker) {
        try { $picked = [OICShell.FolderPicker]::Pick($handle, $script:SelectedPath) } catch { $script:HasModernPicker = $false }
    }
    if (-not $script:HasModernPicker) {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Choose a folder to open in Claude'
        if ($script:SelectedPath) { $dlg.SelectedPath = $script:SelectedPath }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $picked = $dlg.SelectedPath }
    }
    if ($picked) { Set-SelectedPath $picked }
})

$BtnOpen.Add_Click({ Invoke-OpenFolder $script:SelectedPath })

$window.Add_DragOver({
    param($s,$e)
    $e.Effects = if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { [Windows.DragDropEffects]::Copy } else { [Windows.DragDropEffects]::None }
    $e.Handled = $true
})
$window.Add_Drop({
    param($s,$e)
    foreach ($p in $e.Data.GetData([Windows.DataFormats]::FileDrop)) {
        if (Test-Path -LiteralPath $p -PathType Container) { Set-SelectedPath $p; break }
    }
})

$LstRecent.Add_SelectionChanged({ if ($LstRecent.SelectedItem) { Set-SelectedPath $LstRecent.SelectedItem.FullPath } })
$LstRecent.Add_MouseDoubleClick({ if ($LstRecent.SelectedItem) { Invoke-OpenFolder $LstRecent.SelectedItem.FullPath } })
$window.Add_KeyDown({ param($s,$e) if ($e.Key -eq 'Escape') { $window.Close() } })
$LstRecent.AddHandler(
    [System.Windows.Controls.Button]::ClickEvent,
    [System.Windows.RoutedEventHandler]{
        param($s, $e)
        $src = $e.OriginalSource
        while ($src -ne $null -and -not ($src -is [System.Windows.Controls.Button])) {
            $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src)
        }
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'delete') {
            $item = $src.DataContext
            if ($item -and $item.FullPath) {
                Remove-Recent $item.FullPath
                Refresh-Recents
                $e.Handled = $true
            }
        }
    }
)

# ---------------------------------------------------------------- go
Refresh-Recents
if (-not $env:OIC_TEST) { $window.ShowDialog() | Out-Null }
else { Write-Host 'OIC_TEST: built OK; modernPicker =' $script:HasModernPicker '; controls:' (($TxtPath,$BtnOpen,$LstRecent) | ForEach-Object { $_ -ne $null }) }
