<#
================================================================================
  yt-dlp GUI - Modern PowerShell Frontend
================================================================================
  A complete, production-ready graphical interface for yt-dlp.
  Compatible with Windows PowerShell 5.1 and later.
  
  Features:
  - Automatic dependency management (Chocolatey, yt-dlp, FFmpeg)
  - Modern dark theme WPF interface
  - Non-blocking background downloads
  - Metadata retrieval and format selection
  - Real-time progress tracking
  - Download history and configuration persistence
================================================================================
#>

#Requires -Version 5.1

# ==============================================================================
# Initialization & Configuration
# ==============================================================================

# Load required WPF and Forms assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# Define application data paths
$script:AppDataPath = Join-Path $env:APPDATA "YtDlpGui"
$script:ConfigPath = Join-Path $script:AppDataPath "config.json"
$script:HistoryPath = Join-Path $script:AppDataPath "history.json"

# Create app data folder if it doesn't exist
if (-not (Test-Path $script:AppDataPath)) {
    New-Item -Path $script:AppDataPath -ItemType Directory -Force | Out-Null
}

# ==============================================================================
# Helper Functions
# ==============================================================================

function Convert-SizeToBytes {
    param([string]$sizeStr)
    if ($sizeStr -match "(?<val>[\d\.]+)(?<unit>\w+)") {
        $val = [double]$matches['val']
        $unit = $matches['unit'].ToLower()
        switch ($unit) {
            'b' { return $val }
            'kib' { return $val * 1KB }
            'mib' { return $val * 1MB }
            'gib' { return $val * 1GB }
            'kb' { return $val * 1KB }
            'mb' { return $val * 1MB }
            'gb' { return $val * 1GB }
            default { return $val }
        }
    }
    return 0
}

function Format-Size {
    param([long]$bytes)
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Refresh-EnvironmentVariables {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Test-Executable {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

function Load-Config {
    if (Test-Path $script:ConfigPath) {
        try {
            return Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
        }
        catch {
            # Corrupted config, return defaults
        }
    }
    return @{
        LastFolder  = Join-Path $env:USERPROFILE "Downloads"
        WindowSize  = @{ Width = 800; Height = 600 }
        WindowPos   = @{ Left = 100; Top = 100 }
        AlwaysOnTop = $false
    }
}

function Save-Config {
    $config = @{
        LastFolder  = $TxtFolder.Text
        WindowSize  = @{ Width = $Window.Width; Height = $Window.Height }
        WindowPos   = @{ Left = $Window.Left; Top = $Window.Top }
        AlwaysOnTop = $ChkAlwaysOnTop.IsChecked
    }
    $config | ConvertTo-Json | Set-Content $script:ConfigPath -Force
}

function Add-History {
    param([string]$url, [string]$title)
    $history = @()
    if (Test-Path $script:HistoryPath) {
        try {
            $history = Get-Content $script:HistoryPath -Raw | ConvertFrom-Json
            if ($history -isnot [System.Array]) { $history = @($history) }
        }
        catch {
            $history = @()
        }
    }
    $history += @{
        Url   = $url
        Title = $title
        Date  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    # Keep last 50 items
    if ($history.Count -gt 50) {
        $history = $history[-50..-1]
    }
    $history | ConvertTo-Json | Set-Content $script:HistoryPath -Force
}

# ==============================================================================
# Dependency Management
# ==============================================================================

function Install-WithProgress {
    param([string]$name, [string]$chocoPkg, [scriptblock]$uiUpdater)
    
    $dialog = $null
    $txtOutput = $null
    $dispatcher = $Window.Dispatcher
    
    $dispatcher.Invoke([Action] {
            $dialog = New-Object System.Windows.Window
            $dialog.Title = "Installing $name"
            $dialog.Width = 500
            $dialog.Height = 300
            $dialog.Background = "#121212"
            $dialog.WindowStartupLocation = "CenterScreen"
            $dialog.Topmost = $true
        
            $grid = New-Object System.Windows.Controls.Grid
            $grid.Margin = "20"
        
            $row1 = New-Object System.Windows.Controls.RowDefinition
            $row1.Height = "Auto"
            $row2 = New-Object System.Windows.Controls.RowDefinition
            $row2.Height = "*"
            $grid.RowDefinitions.Add($row1)
            $grid.RowDefinitions.Add($row2)
        
            $txtStatus = New-Object System.Windows.Controls.TextBlock
            $txtStatus.Text = "Installing $name..."
            $txtStatus.FontSize = 16
            $txtStatus.Foreground = "#E0E0E0"
            $txtStatus.Margin = "0,0,0,10"
            [System.Windows.Controls.Grid]::SetRow($txtStatus, 0)
            $grid.Children.Add($txtStatus)
        
            $txtOutput = New-Object System.Windows.Controls.TextBox
            $txtOutput.IsReadOnly = $true
            $txtOutput.Background = "#1E1E1E"
            $txtOutput.Foreground = "#E0E0E0"
            $txtOutput.TextWrapping = "Wrap"
            $txtOutput.VerticalScrollBarVisibility = "Auto"
            [System.Windows.Controls.Grid]::SetRow($txtOutput, 1)
            $grid.Children.Add($txtOutput)
        
            $dialog.Content = $grid
            $dialog.Show()
        })
    
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = "choco"
    $p.StartInfo.Arguments = "install $chocoPkg -y"
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.CreateNoWindow = $true
    $p.Start() | Out-Null
    
    while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        $capturedLine = $line
        $capturedTxtOutput = $txtOutput
        $dispatcher.Invoke([Action] {
                $capturedTxtOutput.AppendText("$capturedLine`r`n")
                $capturedTxtOutput.ScrollToEnd()
            })
    }
    $p.WaitForExit()
    
    $dispatcher.Invoke([Action] {
            $dialog.Close()
        })
    
    Refresh-EnvironmentVariables
    return ($p.ExitCode -eq 0)
}

function Install-Chocolatey {
    $dialog = $null
    $txtOutput = $null
    $dispatcher = $Window.Dispatcher
    
    $dispatcher.Invoke([Action] {
            $dialog = New-Object System.Windows.Window
            $dialog.Title = "Installing Chocolatey"
            $dialog.Width = 500
            $dialog.Height = 300
            $dialog.Background = "#121212"
            $dialog.WindowStartupLocation = "CenterScreen"
            $dialog.Topmost = $true
        
            $grid = New-Object System.Windows.Controls.Grid
            $grid.Margin = "20"
        
            $row1 = New-Object System.Windows.Controls.RowDefinition
            $row1.Height = "Auto"
            $row2 = New-Object System.Windows.Controls.RowDefinition
            $row2.Height = "*"
            $grid.RowDefinitions.Add($row1)
            $grid.RowDefinitions.Add($row2)
        
            $txtStatus = New-Object System.Windows.Controls.TextBlock
            $txtStatus.Text = "Installing Chocolatey..."
            $txtStatus.FontSize = 16
            $txtStatus.Foreground = "#E0E0E0"
            $txtStatus.Margin = "0,0,0,10"
            [System.Windows.Controls.Grid]::SetRow($txtStatus, 0)
            $grid.Children.Add($txtStatus)
        
            $txtOutput = New-Object System.Windows.Controls.TextBox
            $txtOutput.IsReadOnly = $true
            $txtOutput.Background = "#1E1E1E"
            $txtOutput.Foreground = "#E0E0E0"
            $txtOutput.TextWrapping = "Wrap"
            $txtOutput.VerticalScrollBarVisibility = "Auto"
            [System.Windows.Controls.Grid]::SetRow($txtOutput, 1)
            $grid.Children.Add($txtOutput)
        
            $dialog.Content = $grid
            $dialog.Show()
        })
    
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = "powershell.exe"
    $p.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))`""
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.CreateNoWindow = $true
    $p.Start() | Out-Null
    
    while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        $capturedLine = $line
        $capturedTxtOutput = $txtOutput
        $dispatcher.Invoke([Action] {
                $capturedTxtOutput.AppendText("$capturedLine`r`n")
                $capturedTxtOutput.ScrollToEnd()
            })
    }
    $p.WaitForExit()
    
    $dispatcher.Invoke([Action] {
            $dialog.Close()
        })
    
    Refresh-EnvironmentVariables
    return ($p.ExitCode -eq 0)
}

function Start-DependencyCheck {
    $TxtStatusBar.Text = "Checking dependencies..."
    
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $script:RunspacePool
    $ps.AddScript({
            param($dispatcher, $txtStatusBar, $window)
        
            function Test-Exe($name) {
                $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
            }
        
            function Install-WithProgress-RS($name, $chocoPkg) {
                $dialog = $null
                $txtOutput = $null
            
                $dispatcher.Invoke([Action] {
                        $dialog = New-Object System.Windows.Window
                        $dialog.Title = "Installing $name"
                        $dialog.Width = 500
                        $dialog.Height = 300
                        $dialog.Background = "#121212"
                        $dialog.WindowStartupLocation = "CenterScreen"
                        $dialog.Topmost = $true
                
                        $grid = New-Object System.Windows.Controls.Grid
                        $grid.Margin = "20"
                
                        $row1 = New-Object System.Windows.Controls.RowDefinition
                        $row1.Height = "Auto"
                        $row2 = New-Object System.Windows.Controls.RowDefinition
                        $row2.Height = "*"
                        $grid.RowDefinitions.Add($row1)
                        $grid.RowDefinitions.Add($row2)
                
                        $txtStatus = New-Object System.Windows.Controls.TextBlock
                        $txtStatus.Text = "Installing $name..."
                        $txtStatus.FontSize = 16
                        $txtStatus.Foreground = "#E0E0E0"
                        $txtStatus.Margin = "0,0,0,10"
                        [System.Windows.Controls.Grid]::SetRow($txtStatus, 0)
                        $grid.Children.Add($txtStatus)
                
                        $txtOutput = New-Object System.Windows.Controls.TextBox
                        $txtOutput.IsReadOnly = $true
                        $txtOutput.Background = "#1E1E1E"
                        $txtOutput.Foreground = "#E0E0E0"
                        $txtOutput.TextWrapping = "Wrap"
                        $txtOutput.VerticalScrollBarVisibility = "Auto"
                        [System.Windows.Controls.Grid]::SetRow($txtOutput, 1)
                        $grid.Children.Add($txtOutput)
                
                        $dialog.Content = $grid
                        $dialog.Show()
                    })
            
                $p = New-Object System.Diagnostics.Process
                $p.StartInfo.FileName = "choco"
                $p.StartInfo.Arguments = "install $chocoPkg -y"
                $p.StartInfo.UseShellExecute = $false
                $p.StartInfo.RedirectStandardOutput = $true
                $p.StartInfo.RedirectStandardError = $true
                $p.StartInfo.CreateNoWindow = $true
                $p.Start() | Out-Null
            
                while (-not $p.StandardOutput.EndOfStream) {
                    $line = $p.StandardOutput.ReadLine()
                    $capturedLine = $line
                    $capturedTxtOutput = $txtOutput
                    $dispatcher.Invoke([Action] {
                            $capturedTxtOutput.AppendText("$capturedLine`r`n")
                            $capturedTxtOutput.ScrollToEnd()
                        })
                }
                $p.WaitForExit()
            
                $dispatcher.Invoke([Action] {
                        $dialog.Close()
                    })
            
                Refresh-EnvironmentVariables
                return ($p.ExitCode -eq 0)
            }
        
            function Install-Chocolatey-RS {
                $dialog = $null
                $txtOutput = $null
            
                $dispatcher.Invoke([Action] {
                        $dialog = New-Object System.Windows.Window
                        $dialog.Title = "Installing Chocolatey"
                        $dialog.Width = 500
                        $dialog.Height = 300
                        $dialog.Background = "#121212"
                        $dialog.WindowStartupLocation = "CenterScreen"
                        $dialog.Topmost = $true
                
                        $grid = New-Object System.Windows.Controls.Grid
                        $grid.Margin = "20"
                
                        $row1 = New-Object System.Windows.Controls.RowDefinition
                        $row1.Height = "Auto"
                        $row2 = New-Object System.Windows.Controls.RowDefinition
                        $row2.Height = "*"
                        $grid.RowDefinitions.Add($row1)
                        $grid.RowDefinitions.Add($row2)
                
                        $txtStatus = New-Object System.Windows.Controls.TextBlock
                        $txtStatus.Text = "Installing Chocolatey..."
                        $txtStatus.FontSize = 16
                        $txtStatus.Foreground = "#E0E0E0"
                        $txtStatus.Margin = "0,0,0,10"
                        [System.Windows.Controls.Grid]::SetRow($txtStatus, 0)
                        $grid.Children.Add($txtStatus)
                
                        $txtOutput = New-Object System.Windows.Controls.TextBox
                        $txtOutput.IsReadOnly = $true
                        $txtOutput.Background = "#1E1E1E"
                        $txtOutput.Foreground = "#E0E0E0"
                        $txtOutput.TextWrapping = "Wrap"
                        $txtOutput.VerticalScrollBarVisibility = "Auto"
                        [System.Windows.Controls.Grid]::SetRow($txtOutput, 1)
                        $grid.Children.Add($txtOutput)
                
                        $dialog.Content = $grid
                        $dialog.Show()
                    })
            
                $p = New-Object System.Diagnostics.Process
                $p.StartInfo.FileName = "powershell.exe"
                $p.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))`""
                $p.StartInfo.UseShellExecute = $false
                $p.StartInfo.RedirectStandardOutput = $true
                $p.StartInfo.RedirectStandardError = $true
                $p.StartInfo.CreateNoWindow = $true
                $p.Start() | Out-Null
            
                while (-not $p.StandardOutput.EndOfStream) {
                    $line = $p.StandardOutput.ReadLine()
                    $capturedLine = $line
                    $capturedTxtOutput = $txtOutput
                    $dispatcher.Invoke([Action] {
                            $capturedTxtOutput.AppendText("$capturedLine`r`n")
                            $capturedTxtOutput.ScrollToEnd()
                        })
                }
                $p.WaitForExit()
            
                $dispatcher.Invoke([Action] {
                        $dialog.Close()
                    })
            
                Refresh-EnvironmentVariables
                return ($p.ExitCode -eq 0)
            }
        
            # Check Chocolatey
            if (-not (Test-Exe "choco")) {
                $result = $dispatcher.Invoke([Func[Object]] {
                        return [System.Windows.MessageBox]::Show("Chocolatey is required to install application dependencies.`n`nWould you like to install Chocolatey now?", "Missing Dependency", 'YesNo', 'Question')
                    })
                if ($result -eq 'Yes') {
                    if (-not (Install-Chocolatey-RS)) {
                        $dispatcher.Invoke([Action] {
                                [System.Windows.MessageBox]::Show("Failed to install Chocolatey.", "Error", 'OK', 'Error')
                            })
                        return $false
                    }
                }
                else {
                    return $false
                }
            }
        
            # Check yt-dlp
            if (-not (Test-Exe "yt-dlp")) {
                $result = $dispatcher.Invoke([Func[Object]] {
                        return [System.Windows.MessageBox]::Show("yt-dlp is not installed.`n`nInstall now?", "Missing Dependency", 'YesNo', 'Question')
                    })
                if ($result -eq 'Yes') {
                    if (-not (Install-WithProgress-RS "yt-dlp" "yt-dlp")) {
                        $dispatcher.Invoke([Action] {
                                [System.Windows.MessageBox]::Show("Failed to install yt-dlp.", "Error", 'OK', 'Error')
                            })
                        return $false
                    }
                }
                else {
                    return $false
                }
            }
        
            # Check FFmpeg
            if (-not (Test-Exe "ffmpeg")) {
                $result = $dispatcher.Invoke([Func[Object]] {
                        return [System.Windows.MessageBox]::Show("FFmpeg is not installed.`n`nInstall now?", "Missing Dependency", 'YesNo', 'Question')
                    })
                if ($result -eq 'Yes') {
                    if (-not (Install-WithProgress-RS "FFmpeg" "ffmpeg")) {
                        $dispatcher.Invoke([Action] {
                                [System.Windows.MessageBox]::Show("Failed to install FFmpeg.", "Error", 'OK', 'Error')
                            })
                        return $false
                    }
                }
                else {
                    return $false
                }
            }
        
            $dispatcher.Invoke([Action] {
                    $txtStatusBar.Text = "Ready"
                })
            return $true
        }) | Out-Null
    $ps.AddArgument($Window.Dispatcher)
    $ps.AddArgument($Window.FindName("TxtStatusBar"))
    $ps.AddArgument($Window)
    
    $handle = $ps.BeginInvoke()
    
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Add_Tick({
            if ($handle.IsCompleted) {
                $timer.Stop()
                $success = $ps.EndInvoke($handle)
                if (-not $success) {
                    [System.Windows.MessageBox]::Show("Application cannot continue without required dependencies.", "Error", 'OK', 'Error')
                    $Window.Close()
                }
            }
        })
    $timer.Start()
}

# ==============================================================================
# UI Definition (XAML)
# ==============================================================================

$ResourceXaml = @"
<Window.Resources>
    <Style TargetType="Button">
        <Setter Property="Background" Value="#BB86FC"/>
        <Setter Property="Foreground" Value="#121212"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Padding" Value="15,8"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
        <Style.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#9965F4"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
                <Setter Property="Background" Value="#7743D1"/>
            </Trigger>
        </Style.Triggers>
    </Style>
    <Style TargetType="TextBox">
        <Setter Property="Background" Value="#1E1E1E"/>
        <Setter Property="Foreground" Value="#E0E0E0"/>
        <Setter Property="BorderBrush" Value="#333333"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="5"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="TextBox">
                    <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
                        <ScrollViewer x:Name="PART_ContentHost" Margin="2"/>
                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="ProgressBar">
        <Setter Property="Background" Value="#1E1E1E"/>
        <Setter Property="Foreground" Value="#03DAC6"/>
        <Setter Property="Height" Value="20"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ProgressBar">
                    <Border Background="{TemplateBinding Background}" CornerRadius="10">
                        <Grid>
                            <Border Background="{TemplateBinding Foreground}" CornerRadius="10" x:Name="PART_Indicator" HorizontalAlignment="Left"/>
                        </Grid>
                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</Window.Resources>
"@

$MainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="yt-dlp GUI" Height="600" Width="800"
        Background="#121212" Foreground="#E0E0E0"
        WindowStartupLocation="CenterScreen">
    $ResourceXaml
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- URL Input -->
        <Grid Grid.Row="0" Margin="0,0,0,20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="TxtUrl" Grid.Column="0" Margin="0,0,10,0" VerticalAlignment="Center"/>
            <Button x:Name="BtnPaste" Grid.Column="1" Content="Paste" Margin="0,0,5,0"/>
            <Button x:Name="BtnClear" Grid.Column="2" Content="Clear" Margin="0,0,5,0"/>
            <Button x:Name="BtnDownload" Grid.Column="3" Content="Download"/>
        </Grid>

        <!-- Folder Selection -->
        <Grid Grid.Row="1" Margin="0,0,0,20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Save to:" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <TextBox x:Name="TxtFolder" Grid.Column="1" IsReadOnly="True" Margin="0,0,10,0" VerticalAlignment="Center"/>
            <Button x:Name="BtnBrowse" Grid.Column="2" Content="Browse" Margin="0,0,5,0"/>
            <Button x:Name="BtnOpenFolder" Grid.Column="3" Content="Open Folder"/>
        </Grid>

        <!-- Main Content -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <!-- Thumbnail & Info -->
            <Border Grid.Column="0" Background="#1E1E1E" CornerRadius="10" Padding="10" Margin="0,0,20,0">
                <StackPanel Width="300">
                    <Image x:Name="ImgThumbnail" Height="168" Stretch="Uniform" Margin="0,0,0,10"/>
                    <TextBlock x:Name="TxtTitle" FontSize="16" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,5"/>
                    <TextBlock x:Name="TxtChannel" FontSize="14" Foreground="#AAAAAA" Margin="0,0,0,5"/>
                    <TextBlock x:Name="TxtDuration" FontSize="14" Foreground="#AAAAAA" Margin="0,0,0,5"/>
                    <TextBlock x:Name="TxtUploadDate" FontSize="14" Foreground="#AAAAAA" Margin="0,0,0,5"/>
                    <TextBlock x:Name="TxtFileSize" FontSize="14" Foreground="#AAAAAA" Margin="0,0,0,5"/>
                    <Button x:Name="BtnCopyTitle" Content="Copy Title" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
            </Border>

            <!-- Progress & Status -->
            <Border Grid.Column="1" Background="#1E1E1E" CornerRadius="10" Padding="20">
                <StackPanel>
                    <TextBlock Text="Download Progress" FontSize="18" FontWeight="Bold" Margin="0,0,0,20"/>
                    <ProgressBar x:Name="PbDownload" Value="0" Maximum="100" Margin="0,0,0,10"/>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock x:Name="TxtPercent" Grid.Column="0" Text="0%" FontSize="14"/>
                        <TextBlock x:Name="TxtSpeed" Grid.Column="1" Text="Speed: -" FontSize="14" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="TxtEta" Grid.Column="2" Text="ETA: -" FontSize="14" HorizontalAlignment="Right"/>
                    </Grid>
                    <Grid Margin="0,0,0,20">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock x:Name="TxtDownloaded" Grid.Column="0" Text="Downloaded: 0 MB" FontSize="14"/>
                        <TextBlock x:Name="TxtTotalSize" Grid.Column="1" Text="Total: -" FontSize="14" HorizontalAlignment="Right"/>
                    </Grid>
                    <TextBlock x:Name="TxtStatus" Text="Ready" FontSize="14" Foreground="#AAAAAA" Margin="0,0,0,20"/>
                    <Button x:Name="BtnCancel" Content="Cancel" Visibility="Collapsed" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>
        </Grid>

        <!-- Status Bar -->
        <Grid Grid.Row="3" Margin="0,20,0,0">
            <TextBlock x:Name="TxtStatusBar" Text="Status: Idle" Foreground="#AAAAAA"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <CheckBox x:Name="ChkAlwaysOnTop" Content="Always on Top" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <Button x:Name="BtnHistory" Content="History" Margin="0,0,5,0"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

$FormatXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select Format" Height="400" Width="500"
        Background="#121212" Foreground="#E0E0E0"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    $ResourceXaml
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="Select Format" FontSize="20" FontWeight="Bold" Margin="0,0,0,20"/>
        
        <Grid Grid.Row="1" Margin="0,0,0,20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                <TextBlock Text="Video" FontSize="16" Margin="0,0,0,10"/>
                <ListBox x:Name="LstVideo" Height="200" Background="#1E1E1E" Foreground="#E0E0E0"/>
            </StackPanel>
            
            <StackPanel Grid.Column="1" Margin="10,0,0,0">
                <TextBlock Text="Audio" FontSize="16" Margin="0,0,0,10"/>
                <ListBox x:Name="LstAudio" Height="200" Background="#1E1E1E" Foreground="#E0E0E0"/>
            </StackPanel>
        </Grid>
        
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnCancelFormat" Content="Cancel" Margin="0,0,10,0"/>
            <Button x:Name="BtnOkFormat" Content="Download"/>
        </StackPanel>
    </Grid>
</Window>
"@

$HistoryXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Download History" Height="400" Width="500"
        Background="#121212" Foreground="#E0E0E0"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    $ResourceXaml
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Download History" FontSize="20" FontWeight="Bold" Margin="0,0,0,20"/>
        <ListBox x:Name="LstHistory" Grid.Row="1" Margin="0,0,0,20" Background="#1E1E1E" Foreground="#E0E0E0"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnClearHistory" Content="Clear History" Margin="0,0,10,0"/>
            <Button x:Name="BtnCloseHistory" Content="Close"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Convert-XamlToObject {
    param([string]$Xaml)
    
    # Remove x:Class attribute to avoid errors
    $Xaml = $Xaml -replace 'x:Class="[^"]*"', ''
    
    $xml = New-Object System.Xml.XmlDocument
    $xml.LoadXml($Xaml)
    $reader = New-Object System.Xml.XmlNodeReader $xml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    
    # Find named elements and set them as script variables.
    # Use an XmlNamespaceManager to resolve the x: prefix used in x:Name attributes.
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsMgr.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml")
    $xml.SelectNodes("//*[@x:Name]", $nsMgr) | ForEach-Object {
        $name = $_.GetAttribute("Name", "http://schemas.microsoft.com/winfx/2006/xaml")
        if ($name) {
            $element = $window.FindName($name)
            if ($element) {
                Set-Variable -Name $name -Value $element -Scope Script
            }
        }
    }
    return $window
}

# ==============================================================================
# Runspace & Background Tasks
# ==============================================================================

$script:RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, 5)
$script:RunspacePool.ApartmentState = "STA"
$script:RunspacePool.Open()

$script:DownloadState = @{ Cancelled = $false; Process = $null }
$script:DownloadHandle = $null
$script:DownloadPS = $null

# ==============================================================================
# Dialog Functions
# ==============================================================================

function Show-FormatDialog {
    param($metadata)
    
    $dialog = Convert-XamlToObject $FormatXaml
    $dialog.Owner = $Window
    
    # Populate Video options
    $videoOptions = @("Best Quality")
    $availableRes = $metadata.formats | Where-Object { $_.height } | Select-Object -ExpandProperty height -Unique | Sort-Object -Descending
    foreach ($res in @(2160, 1440, 1080, 720, 480, 360)) {
        if ($availableRes -contains $res) {
            $videoOptions += "${res}p"
        }
    }
    $LstVideo.ItemsSource = $videoOptions
    $LstVideo.SelectedIndex = 0
    
    # Populate Audio options
    $audioOptions = @("Original Audio", "MP3 320 kbps", "MP3 256 kbps", "MP3 192 kbps", "MP3 128 kbps")
    $LstAudio.ItemsSource = $audioOptions
    $LstAudio.SelectedIndex = 0
    
    $script:FormatDialogResult = $null
    
    $BtnOkFormat.Add_Click({
            $script:FormatDialogResult = @{
                Video = $LstVideo.SelectedItem
                Audio = $LstAudio.SelectedItem
            }
            $dialog.Close()
        })
    
    $BtnCancelFormat.Add_Click({
            $dialog.Close()
        })
    
    $dialog.ShowDialog() | Out-Null
    
    return $script:FormatDialogResult
}

function Show-HistoryDialog {
    $dialog = Convert-XamlToObject $HistoryXaml
    $dialog.Owner = $Window
    
    $history = @()
    if (Test-Path $script:HistoryPath) {
        try {
            $history = Get-Content $script:HistoryPath -Raw | ConvertFrom-Json
            if ($history -isnot [System.Array]) { $history = @($history) }
        }
        catch {
            $history = @()
        }
    }
    
    $LstHistory.ItemsSource = ($history | ForEach-Object { "$($_.Date) - $($_.Title)" })
    
    $LstHistory.Add_MouseDoubleClick({
            if ($LstHistory.SelectedIndex -ge 0) {
                $selected = $history[$LstHistory.SelectedIndex]
                $TxtUrl.Text = $selected.Url
                $dialog.Close()
            }
        })
    
    $BtnClearHistory.Add_Click({
            if (Test-Path $script:HistoryPath) {
                Remove-Item $script:HistoryPath -Force
            }
            $LstHistory.ItemsSource = @()
            $TxtStatusBar.Text = "History cleared."
        })
    
    $BtnCloseHistory.Add_Click({
            $dialog.Close()
        })
    
    $dialog.ShowDialog() | Out-Null
}

# ==============================================================================
# Download Logic
# ==============================================================================

function Start-Download {
    param($url, $formatSelection, $metadata)
    
    $folder = $TxtFolder.Text
    $videoFormat = $formatSelection.Video
    $audioFormat = $formatSelection.Audio
    
    $ytArgs = @()
    $ytArgs += "-o"
    $ytArgs += "`"$folder\%(title)s.%(ext)s`""
    
    if ($videoFormat -eq "Best Quality") {
        $ytArgs += "-f"
        $ytArgs += "bestvideo+bestaudio/best"
    }
    else {
        $res = $videoFormat -replace 'p', ''
        $ytArgs += "-f"
        $ytArgs += "bestvideo[height<=$res]+bestaudio/best[height<=$res]"
    }
    
    if ($audioFormat -ne "Original Audio") {
        $ytArgs += "-x"
        $ytArgs += "--audio-format"
        $ytArgs += "mp3"
        $bitrate = $audioFormat -replace 'MP3 ', '' -replace ' kbps', ''
        $ytArgs += "--postprocessor-args"
        $ytArgs += "`"ffmpeg:-b:a ${bitrate}k`""
    }
    
    $ytArgs += "--newline"
    $ytArgs += "--no-warnings"
    $ytArgs += "`"$url`""
    
    $BtnDownload.IsEnabled = $false
    $BtnCancel.Visibility = "Visible"
    $TxtStatusBar.Text = "Downloading..."
    $script:DownloadState.Cancelled = $false
    
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $script:RunspacePool
    $ps.AddScript({
            param($arguments, $dispatcher, $uiElements, $state, $folder, $title)
        
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo.FileName = "yt-dlp"
            $p.StartInfo.Arguments = $arguments -join ' '
            $p.StartInfo.UseShellExecute = $false
            $p.StartInfo.RedirectStandardOutput = $true
            $p.StartInfo.RedirectStandardError = $true
            $p.StartInfo.CreateNoWindow = $true
            $p.Start() | Out-Null
        
            $state.Process = $p
        
            while (-not $p.StandardOutput.EndOfStream) {
                if ($state.Cancelled) {
                    $p.Kill()
                    break
                }
                $line = $p.StandardOutput.ReadLine()
            
                # Parse progress
                if ($line -match "^\[download\]\s+(?<percent>\d+(?:\.\d+)?)%\s+of\s+(?:~)?(?<total>[\d\.]+\w+)\s+at\s+(?<speed>[\d\.]+\w+/s)\s+ETA\s+(?<eta>\S+)") {
                    $percent = [math]::Round([double]$matches['percent'])
                    $total = $matches['total']
                    $speed = $matches['speed']
                    $eta = $matches['eta']
                
                    $totalBytes = Convert-SizeToBytes $total
                    $downloadedBytes = [math]::Round(($percent / 100) * $totalBytes)
                    $downloadedSize = Format-Size $downloadedBytes
                
                    $dispatcher.Invoke([Action] {
                            param($p, $t, $s, $e, $d)
                            $uiElements.PbDownload.Value = $p
                            $uiElements.TxtPercent.Text = "$p%"
                            $uiElements.TxtSpeed.Text = "Speed: $s"
                            $uiElements.TxtEta.Text = "ETA: $e"
                            $uiElements.TxtTotalSize.Text = "Total: $t"
                            $uiElements.TxtDownloaded.Text = "Downloaded: $d"
                        }, $percent, $total, $speed, $eta, $downloadedSize)
                }
                elseif ($line -match "^\[download\]\s+100%") {
                    $dispatcher.Invoke([Action] {
                            $uiElements.PbDownload.Value = 100
                            $uiElements.TxtPercent.Text = "100%"
                        })
                }
                elseif ($line -match "^\[download\]\s+Destination:\s+(.+)") {
                    $dispatcher.Invoke([Action] {
                            param($status)
                            $uiElements.TxtStatus.Text = "Downloading: $status"
                        }, $matches[1])
                }
                elseif ($line -match "^\[Merger\]\s+(.+)") {
                    $dispatcher.Invoke([Action] {
                            param($status)
                            $uiElements.TxtStatus.Text = "Merging: $status"
                        }, $matches[1])
                }
                elseif ($line -match "^\[ffmpeg\]\s+(.+)") {
                    $dispatcher.Invoke([Action] {
                            param($status)
                            $uiElements.TxtStatus.Text = "Converting: $status"
                        }, $matches[1])
                }
                elseif ($line -match "ERROR:\s+(.+)") {
                    $dispatcher.Invoke([Action] {
                            param($err)
                            [System.Windows.MessageBox]::Show($err, "Error", 'OK', 'Error')
                        }, $matches[1])
                    break
                }
            }
        
            $p.WaitForExit()
        
            $dispatcher.Invoke([Action] {
                    if ($state.Cancelled) {
                        $uiElements.TxtStatus.Text = "Cancelled"
                        $uiElements.TxtStatusBar.Text = "Cancelled"
                    }
                    elseif ($p.ExitCode -eq 0) {
                        $uiElements.TxtStatus.Text = "Download Complete"
                        $uiElements.TxtStatusBar.Text = "Ready"
                        $uiElements.PbDownload.Value = 100
                        $uiElements.TxtPercent.Text = "100%"
                
                        Add-History $url $title
                
                        $result = [System.Windows.MessageBox]::Show("Download Complete!`n`nOpen file location?", "Success", 'YesNo', 'Information')
                        if ($result -eq 'Yes') {
                            $file = Get-ChildItem -Path $folder -Filter "$title.*" -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($file) {
                                Start-Process explorer.exe "/select,`"$($file.FullName)`""
                            }
                            else {
                                Start-Process explorer.exe $folder
                            }
                        }
                    }
                    else {
                        $uiElements.TxtStatus.Text = "Failed"
                        $uiElements.TxtStatusBar.Text = "Failed"
                    }
                    $uiElements.BtnDownload.IsEnabled = $true
                    $uiElements.BtnCancel.Visibility = "Collapsed"
                })
        }) | Out-Null
    $ps.AddArgument($ytArgs)
    $ps.AddArgument($Window.Dispatcher)
    
    $uiElements = @{
        PbDownload    = $Window.FindName("PbDownload")
        TxtPercent    = $Window.FindName("TxtPercent")
        TxtSpeed      = $Window.FindName("TxtSpeed")
        TxtEta        = $Window.FindName("TxtEta")
        TxtTotalSize  = $Window.FindName("TxtTotalSize")
        TxtDownloaded = $Window.FindName("TxtDownloaded")
        TxtStatus     = $Window.FindName("TxtStatus")
        TxtStatusBar  = $Window.FindName("TxtStatusBar")
        BtnDownload   = $Window.FindName("BtnDownload")
        BtnCancel     = $Window.FindName("BtnCancel")
    }
    $ps.AddArgument($uiElements)
    $ps.AddArgument($script:DownloadState)
    $ps.AddArgument($folder)
    $ps.AddArgument($metadata.title)
    
    $handle = $ps.BeginInvoke()
    $script:DownloadHandle = $handle
    $script:DownloadPS = $ps
}

# ==============================================================================
# Main Execution
# ==============================================================================

# Parse Main XAML
$Window = Convert-XamlToObject $MainXaml

# Apply configuration
$config = Load-Config
$Window.Left = $config.WindowPos.Left
$Window.Top = $config.WindowPos.Top
$Window.Width = $config.WindowSize.Width
$Window.Height = $config.WindowSize.Height
$TxtFolder.Text = $config.LastFolder
$ChkAlwaysOnTop.IsChecked = $config.AlwaysOnTop
$Window.Topmost = $config.AlwaysOnTop

# Wire up event handlers
$BtnPaste.Add_Click({
        if ([System.Windows.Clipboard]::ContainsText()) {
            $TxtUrl.Text = [System.Windows.Clipboard]::GetText()
        }
    })

$BtnClear.Add_Click({
        $TxtUrl.Text = ""
    })

$BtnBrowse.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.SelectedPath = $TxtFolder.Text
        $dialog.Description = "Select Download Folder"
        if ($dialog.ShowDialog() -eq 'OK') {
            $TxtFolder.Text = $dialog.SelectedPath
        }
    })

$BtnOpenFolder.Add_Click({
        if (Test-Path $TxtFolder.Text) {
            Start-Process explorer.exe $TxtFolder.Text
        }
    })

$BtnDownload.Add_Click({
        $url = $TxtUrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($url)) {
            [System.Windows.MessageBox]::Show("Please enter a valid URL.", "Error", 'OK', 'Warning')
            return
        }
    
        $BtnDownload.IsEnabled = $false
        $TxtStatusBar.Text = "Fetching metadata..."
    
        # Synchronized hashtable so the background runspace can pass results to the main thread
        $script:MetaFetchResult = [hashtable]::Synchronized(@{
            Done     = $false
            Metadata = $null
            Error    = $null
            Url      = $url
        })
    
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $script:RunspacePool
        $ps.AddScript({
                param($url, $result)
            
                $p = New-Object System.Diagnostics.Process
                $p.StartInfo.FileName = "yt-dlp"
                $p.StartInfo.Arguments = "-J --no-warnings `"$url`""
                $p.StartInfo.UseShellExecute = $false
                $p.StartInfo.RedirectStandardOutput = $true
                $p.StartInfo.RedirectStandardError = $true
                $p.StartInfo.CreateNoWindow = $true
                $p.Start() | Out-Null
            
                $output = $p.StandardOutput.ReadToEnd()
                $err    = $p.StandardError.ReadToEnd()
                $p.WaitForExit()
            
                if ($p.ExitCode -ne 0) {
                    $result.Error = $err
                    $result.Done  = $true
                    return
                }
            
                try {
                    $result.Metadata = $output | ConvertFrom-Json
                }
                catch {
                    $result.Error = "Failed to parse metadata: $($_.Exception.Message)"
                }
                $result.Done = $true
            }) | Out-Null
        $ps.AddArgument($url)
        $ps.AddArgument($script:MetaFetchResult)
        $ps.BeginInvoke() | Out-Null
    
        # Poll on the main (UI) thread — safe to call any PowerShell function here
        $metaTimer = New-Object System.Windows.Threading.DispatcherTimer
        $metaTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $capturedUrl = $url
        $metaTimer.Add_Tick({
                if (-not $script:MetaFetchResult.Done) { return }
                $metaTimer.Stop()
            
                if ($script:MetaFetchResult.Error) {
                    [System.Windows.MessageBox]::Show(
                        "Failed to fetch metadata:`n$($script:MetaFetchResult.Error)",
                        "Error", 'OK', 'Error')
                    $TxtStatusBar.Text    = "Ready"
                    $BtnDownload.IsEnabled = $true
                    return
                }
            
                $meta = $script:MetaFetchResult.Metadata
            
                # Update info panel (main thread, fully safe)
                $TxtTitle.Text   = $meta.title
                $TxtChannel.Text = "Channel: $($meta.channel)"
            
                if ($meta.duration) {
                    $dur = [TimeSpan]::FromSeconds($meta.duration)
                    $TxtDuration.Text = "Duration: $($dur.ToString('hh\:mm\:ss'))"
                }
                else {
                    $TxtDuration.Text = "Duration: Unknown"
                }
            
                $TxtUploadDate.Text = "Upload Date: $($meta.upload_date)"
            
                if ($meta.filesize) {
                    $TxtFileSize.Text = "Size: $([math]::Round($meta.filesize / 1MB, 2)) MB"
                }
                else {
                    $TxtFileSize.Text = "Size: Unknown"
                }
            
                # Load thumbnail (network + bitmap — run in a separate runspace, update image on UI thread)
                if ($meta.thumbnail) {
                    $thumbUrl  = $meta.thumbnail
                    $imgCtrl   = $ImgThumbnail
                    $thumbPS   = [PowerShell]::Create()
                    $thumbPS.RunspacePool = $script:RunspacePool
                    $thumbPS.AddScript({
                            param($url)
                            try {
                                $wc   = New-Object System.Net.WebClient
                                return $wc.DownloadData($url)
                            }
                            catch { return $null }
                        }) | Out-Null
                    $thumbPS.AddArgument($thumbUrl)
                    $thumbHandle = $thumbPS.BeginInvoke()
            
                    $thumbTimer = New-Object System.Windows.Threading.DispatcherTimer
                    $thumbTimer.Interval = [TimeSpan]::FromMilliseconds(200)
                    $thumbTimer.Add_Tick({
                            if (-not $thumbHandle.IsCompleted) { return }
                            $thumbTimer.Stop()
                            $imageData = $thumbPS.EndInvoke($thumbHandle)
                            if ($imageData) {
                                try {
                                    $ms     = New-Object System.IO.MemoryStream (, $imageData)
                                    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                                    $bitmap.BeginInit()
                                    $bitmap.StreamSource  = $ms
                                    $bitmap.CacheOption   = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                                    $bitmap.EndInit()
                                    $bitmap.Freeze()
                                    $imgCtrl.Source = $bitmap
                                }
                                catch { }
                            }
                        })
                    $thumbTimer.Start()
                }
            
                $TxtStatusBar.Text = "Ready"
            
                # Show format-selection dialog — safe because we are on the main UI thread
                $formatResult = Show-FormatDialog $meta
                if ($formatResult) {
                    Start-Download $capturedUrl $formatResult $meta
                }
                else {
                    $BtnDownload.IsEnabled = $true
                }
            })
        $metaTimer.Start()
    })

$BtnCancel.Add_Click({
        if ($script:DownloadState) {
            $script:DownloadState.Cancelled = $true
            if ($script:DownloadPS) {
                $script:DownloadPS.Stop()
            }
        }
    })

$BtnCopyTitle.Add_Click({
        if ($TxtTitle.Text) {
            [System.Windows.Clipboard]::SetText($TxtTitle.Text)
            $TxtStatusBar.Text = "Title copied to clipboard."
        }
    })

$ChkAlwaysOnTop.Add_Checked({
        $Window.Topmost = $true
    })

$ChkAlwaysOnTop.Add_Unchecked({
        $Window.Topmost = $false
    })

$BtnHistory.Add_Click({
        Show-HistoryDialog
    })

# Drag and Drop
$Window.AllowDrop = $true
$Window.Add_Drop({
        param($sender, $e)
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::Text)) {
            $url = $e.Data.GetData([System.Windows.DataFormats]::Text)
            $TxtUrl.Text = $url
        }
        elseif ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
            if ($files.Count -gt 0) {
                $TxtUrl.Text = $files[0]
            }
        }
    })

$Window.Add_DragOver({
        param($sender, $e)
        $e.Effects = [System.Windows.DragDropEffects]::Copy
        $e.Handled = $true
    })

# Clipboard auto-detection
$clipboardTimer = New-Object System.Windows.Threading.DispatcherTimer
$clipboardTimer.Interval = [TimeSpan]::FromSeconds(2)
$lastClipboard = ""
$clipboardTimer.Add_Tick({
        if ([System.Windows.Clipboard]::ContainsText()) {
            $text = [System.Windows.Clipboard]::GetText()
            if ($text -ne $lastClipboard -and $text -match "^(https?://)?(www\.)?(youtube\.com|youtu\.be)/.+") {
                $lastClipboard = $text
                if ([string]::IsNullOrWhiteSpace($TxtUrl.Text)) {
                    $TxtUrl.Text = $text
                    $TxtStatusBar.Text = "YouTube link detected from clipboard."
                }
            }
        }
    })
$clipboardTimer.Start()

# Save config on closing
$Window.Add_Closing({
        Save-Config
        $script:RunspacePool.Close()
    })

# Start dependency check after window is loaded (register BEFORE Show)
$Window.Add_Loaded({
        Start-DependencyCheck
    })

# Start WPF message loop (ShowDialog blocks until window closes)
$app = New-Object System.Windows.Application
$app.Run($Window) | Out-Null


