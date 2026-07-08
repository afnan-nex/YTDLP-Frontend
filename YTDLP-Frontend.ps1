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
    }
}

function Save-Config {
    $config = @{
        LastFolder  = $TxtFolder.Text
        WindowSize  = @{ Width = $Window.Width; Height = $Window.Height }
        WindowPos   = @{ Left = $Window.Left; Top = $Window.Top }
    }
    $config | ConvertTo-Json | Set-Content $script:ConfigPath -Force
}

# ==============================================================================
# Dependency Management
# ==============================================================================

function Install-Choco {
    Write-Host "=========================================="
    Write-Host "Installing Chocolatey"
    Write-Host "=========================================="
    Write-Host "Launching installation in a new window..."
    
    # Added 'refreshenv' to the end of the command chain so the new window recognizes 'choco' instantly
    $chocoCmd = 'echo Installing Chocolatey... && powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString(''https://community.chocolatey.org/install.ps1''))" && echo. && echo Refreshing environment variables... && call refreshenv && echo Chocolatey installation completed. && pause'
    
    Start-Process cmd -ArgumentList "/k", $chocoCmd
}

function Install-YTDLP {
    Write-Host "=========================================="
    Write-Host "Installing yt-dlp"
    Write-Host "=========================================="
    Write-Host "Launching installation in a new window..."
    $ytdlpCmd = 'call refreshenv && echo Installing yt-dlp via Chocolatey... && choco install yt-dlp -y && echo. && echo yt-dlp installation completed. && pause'
    
    Start-Process cmd -ArgumentList "/k", $ytdlpCmd
}

function Install-FFmpeg {
    Write-Host "=========================================="
    Write-Host "Installing FFmpeg"
    Write-Host "=========================================="
    Write-Host "Launching installation in a new window..."
    $ffmpegCmd = 'call refreshenv && echo Installing FFmpeg via Chocolatey... && choco install ffmpeg -y && echo. && echo FFmpeg installation completed. && pause'
    Start-Process cmd -ArgumentList "/k", $ffmpegCmd
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
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- URL Input -->
        <Grid Grid.Row="0" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="TxtUrl" Grid.Column="0" Margin="0,0,10,0" VerticalAlignment="Center"/>
            <Button x:Name="BtnPaste" Grid.Column="1" Content="Paste" Margin="0,0,5,0"/>
            <Button x:Name="BtnClear" Grid.Column="2" Content="Clear" Margin="0,0,5,0"/>
            <Button x:Name="BtnFetchInfo" Grid.Column="3" Content="Fetch Info" Margin="0,0,5,0"/>
            <Button x:Name="BtnDownload" Grid.Column="4" Content="Download"/>
        </Grid>

        <!-- Format Selection -->
        <Grid Grid.Row="1" Margin="0,0,0,20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Video Format:" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <ComboBox x:Name="CmbVideo" Grid.Column="1" Margin="0,0,20,0" VerticalAlignment="Center" Padding="5">
                <ComboBoxItem Content="Best Quality" IsSelected="True"/>
                <ComboBoxItem Content="1080p"/>
                <ComboBoxItem Content="720p"/>
                <ComboBoxItem Content="480p"/>
                <ComboBoxItem Content="360p"/>
            </ComboBox>
            <TextBlock Grid.Column="2" Text="Audio Format:" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <ComboBox x:Name="CmbAudio" Grid.Column="3" Margin="0,0,0,0" VerticalAlignment="Center" Padding="5">
                <ComboBoxItem Content="Original Audio" IsSelected="True"/>
                <ComboBoxItem Content="MP3 320 kbps"/>
                <ComboBoxItem Content="MP3 256 kbps"/>
                <ComboBoxItem Content="MP3 192 kbps"/>
                <ComboBoxItem Content="MP3 128 kbps"/>
            </ComboBox>
        </Grid>

        <!-- Folder Selection -->
        <Grid Grid.Row="2" Margin="0,0,0,20">
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
        <Grid Grid.Row="3">
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
        <Grid Grid.Row="4" Margin="0,20,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" x:Name="TxtStatusBar" Text="Ready" Foreground="#AAAAAA" VerticalAlignment="Center"/>
            <Button Grid.Column="1" x:Name="BtnHelp" Content="?" Style="{x:Null}" Background="Transparent" Foreground="#BB86FC" BorderThickness="0" FontSize="20" FontWeight="Bold" HorizontalAlignment="Right" VerticalAlignment="Center" Cursor="Hand" Margin="0,0,5,0" Padding="10,0"/>
        </Grid>
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

$InstallXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Install Dependencies" Height="250" Width="300"
        Background="#121212" Foreground="#E0E0E0"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    $ResourceXaml
    <Grid Margin="20">
        <StackPanel VerticalAlignment="Center">
            <TextBlock Text="Install Dependencies" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,20"/>
            <Button x:Name="BtnInstallChoco" Content="Install Chocolatey" Margin="0,0,0,10"/>
            <Button x:Name="BtnInstallYtdlp" Content="Install yt-dlp" Margin="0,0,0,10"/>
            <Button x:Name="BtnInstallFfmpeg" Content="Install FFmpeg" Margin="0,0,0,10"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-InstallDialog {
    $script:InstallDialog = Convert-XamlToObject $InstallXaml
    $script:InstallDialog.Owner = $Window
    
    $script:BtnInstallChoco.Add_Click({ Install-Choco })
    $script:BtnInstallYtdlp.Add_Click({ Install-YTDLP })
    $script:BtnInstallFfmpeg.Add_Click({ Install-FFmpeg })
    
    $script:InstallDialog.ShowDialog() | Out-Null
}

$script:RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, 5)
$script:RunspacePool.ApartmentState = "STA"
$script:RunspacePool.Open()

$script:DownloadState = @{ Cancelled = $false; Process = $null }
$script:DownloadHandle = $null
$script:DownloadPS = $null

# ==============================================================================
# Download Logic
# ==============================================================================

function Start-Download {
    param($url, $formatSelection, $metadata)
    
    $folder = $TxtFolder.Text
    $videoFormat = $formatSelection.Video
    $audioFormat = $formatSelection.Audio
    
    $qualities = @()
    if ($videoFormat -ne "Best Quality") { $qualities += "($($videoFormat -replace 'p',''))" }
    if ($audioFormat -ne "Original Audio") { $qualities += "($($audioFormat -replace ' kbps',''))" }
    $qualitySuffix = if ($qualities.Count -gt 0) { " " + ($qualities -join " ") } else { "" }

    $cleanTitleWildcard = if ([string]::IsNullOrWhiteSpace($metadata.title)) { "Unknown Video" } else { $metadata.title -replace '[<>:"/\\|?*]', '?' }

    $exactExists = Get-ChildItem -LiteralPath $folder -Filter "$cleanTitleWildcard$qualitySuffix.*" -ErrorAction SilentlyContinue
    $nSuffix = ""

    if ($exactExists) {
        $n = 1
        while ($true) {
            $testExists = Get-ChildItem -LiteralPath $folder -Filter "$cleanTitleWildcard$qualitySuffix ($n).*" -ErrorAction SilentlyContinue
            if (-not $testExists) {
                $nSuffix = " ($n)"
                break
            }
            $n++
        }
    }

    $ytArgs = @()
    $ytArgs += "-o"
    $ytArgs += "`"$folder\%(title)s$qualitySuffix$nSuffix.%(ext)s`""
    
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
                
                    $c_pct   = $percent
                    $c_total = $total
                    $c_speed = $speed
                    $c_eta   = $eta
                    $c_dl    = $downloadedSize
                    $c_ui    = $uiElements
                    $dispatcher.Invoke([Action] {
                            $c_ui.PbDownload.Value        = $c_pct
                            $c_ui.TxtPercent.Text         = "$c_pct%"
                            $c_ui.TxtSpeed.Text           = "Speed: $c_speed"
                            $c_ui.TxtEta.Text             = "ETA: $c_eta"
                            $c_ui.TxtTotalSize.Text       = "Total: $c_total"
                            $c_ui.TxtDownloaded.Text      = "Downloaded: $c_dl"
                        })
                }
                elseif ($line -match "^\[download\]\s+100%") {
                    $dispatcher.Invoke([Action] {
                            $uiElements.PbDownload.Value = 100
                            $uiElements.TxtPercent.Text = "100%"
                        })
                }
                elseif ($line -match "^\[download\]\s+Destination:\s+(.+)") {
                    $c_status = $matches[1]; $c_ui = $uiElements
                    $dispatcher.Invoke([Action] {
                            $c_ui.TxtStatus.Text = "Downloading: $c_status"
                        })
                }
                elseif ($line -match "^\[Merger\]\s+(.+)") {
                    $c_status = $matches[1]; $c_ui = $uiElements
                    $dispatcher.Invoke([Action] {
                            $c_ui.TxtStatus.Text = "Merging: $c_status"
                        })
                }
                elseif ($line -match "^\[ffmpeg\]\s+(.+)") {
                    $c_status = $matches[1]; $c_ui = $uiElements
                    $dispatcher.Invoke([Action] {
                            $c_ui.TxtStatus.Text = "Converting: $c_status"
                        })
                }
                elseif ($line -match "ERROR:\s+(.+)") {
                    $c_err = $matches[1]
                    $c_ui  = $uiElements
                    $dispatcher.Invoke([Action] {
                            $c_ui.TxtStatus.Text = "Error: $c_err"
                            $c_ui.TxtStatusBar.Text = "Error: $c_err"
                        })
                    break
                }
            }
        
            $p.WaitForExit()
        
            $c_ui     = $uiElements
            $c_state  = $state
            $c_exit   = $p.ExitCode
            $c_folder = $folder
            $c_title  = $title
            $c_url    = $url
            $dispatcher.Invoke([Action] {
                    if ($c_state.Cancelled) {
                        $c_ui.TxtStatus.Text    = 'Cancelled'
                        $c_ui.TxtStatusBar.Text = 'Cancelled'
                    }
                    elseif ($c_exit -eq 0) {
                        $c_ui.TxtStatus.Text    = 'Download Complete'
                        $c_ui.TxtStatusBar.Text = 'Ready'
                        $c_ui.PbDownload.Value  = 100
                        $c_ui.TxtPercent.Text   = '100%'
                        Add-History $c_url $c_title
                    }
                    else {
                        $c_ui.TxtStatus.Text    = 'Failed'
                        $c_ui.TxtStatusBar.Text = 'Failed'
                    }
                    $c_ui.BtnDownload.IsEnabled      = $true
                    $c_ui.BtnCancel.Visibility       = 'Collapsed'
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
# WindowPos/WindowSize may be PSCustomObject (from JSON) or hashtable (defaults)
$_left   = if ($config.WindowPos)  { $config.WindowPos.Left }   else { 100 }
$_top    = if ($config.WindowPos)  { $config.WindowPos.Top }    else { 100 }
$_width  = if ($config.WindowSize) { $config.WindowSize.Width }  else { 800 }
$_height = if ($config.WindowSize) { $config.WindowSize.Height } else { 600 }
$Window.Left   = $_left
$Window.Top    = $_top
$Window.Width  = $_width
$Window.Height = $_height
# Default save folder — always fall back to Downloads if empty/missing
$_folder = if ($config.LastFolder) { $config.LastFolder } else { Join-Path $env:USERPROFILE 'Downloads' }
if (-not (Test-Path $_folder)) { $_folder = Join-Path $env:USERPROFILE 'Downloads' }
$TxtFolder.Text = $_folder


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

$BtnFetchInfo.Add_Click({
        $url = $TxtUrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($url)) {
            [System.Windows.MessageBox]::Show("Please enter a valid URL.", "Error", 'OK', 'Warning')
            return
        }
    
        $BtnFetchInfo.IsEnabled = $false
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
                    $BtnFetchInfo.IsEnabled = $true
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
            
                # Update format combo boxes
                $videoOptions = [System.Collections.Generic.List[string]]::new()
                $videoOptions.Add('Best Quality')
                if ($meta -and $meta.formats) {
                    $availableRes = $meta.formats |
                        Where-Object { $_.height } |
                        Select-Object -ExpandProperty height -Unique |
                        Sort-Object -Descending
                    foreach ($res in @(2160, 1440, 1080, 720, 480, 360)) {
                        if ($availableRes -contains $res) { $videoOptions.Add("${res}p") }
                    }
                }
                $CmbVideo.ItemsSource = $videoOptions
                $CmbVideo.SelectedIndex = 0
                
                $BtnFetchInfo.IsEnabled = $true
            })
        $metaTimer.Start()
    })

$BtnDownload.Add_Click({
        $url = $TxtUrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($url)) {
            [System.Windows.MessageBox]::Show("Please enter a valid URL.", "Error", 'OK', 'Warning')
            return
        }
        
        $vSel = $CmbVideo.SelectedItem
        $videoFormat = if ($vSel -is [System.Windows.Controls.ComboBoxItem]) { $vSel.Content } else { $vSel }
        $aSel = $CmbAudio.SelectedItem
        $audioFormat = if ($aSel -is [System.Windows.Controls.ComboBoxItem]) { $aSel.Content } else { $aSel }
        
        $formatSelection = @{
            Video = $videoFormat
            Audio = $audioFormat
        }
        $title = if ([string]::IsNullOrWhiteSpace($TxtTitle.Text)) { "Unknown Video" } else { $TxtTitle.Text }
        $metadata = @{ title = $title }
        
        Start-Download $url $formatSelection $metadata
    })

$BtnCancel.Add_Click({
        if ($script:DownloadState) {
            $script:DownloadState.Cancelled = $true
            if ($script:DownloadPS) {
                $script:DownloadPS.Stop()
            }
        }
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

# Clipboard auto-detection removed — paste only via Paste button

# Save config on closing
$Window.Add_Closing({
        Save-Config
        $script:RunspacePool.Close()
    })

$BtnHelp.Add_Click({
        Show-InstallDialog
    })

# Start WPF message loop (ShowDialog blocks until window closes)
$app = New-Object System.Windows.Application
$app.Run($Window) | Out-Null


