# All-in-One Utility Launcher
# Repository: https://github.com/phwyverysad/powershell.git
# Execution: irm https://raw.githubusercontent.com/phwyverysad/powershell/main/run.ps1 | iex

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Web

if (-not ([System.Management.Automation.PSTypeName]'WinUtil.ProcessRunner').Type) {
    $csharpCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32;

namespace WinUtil {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X, Y;
    }

    public static class LauncherWinUtil {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

        [DllImport("gdi32.dll")]
        public static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int cx, int cy);

        [DllImport("user32.dll")]
        public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);

        [DllImport("user32.dll")]
        public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern bool GetCursorPos(out POINT lpPoint);
    }

    public static class AppScanner {
        public static string GetInstalledAppsBase64() {
            HashSet<string> displayNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            HashSet<string> keyNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            RegistryKey[] hives = new RegistryKey[] { Registry.LocalMachine, Registry.LocalMachine, Registry.CurrentUser };
            string[] paths = new string[] {
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
            };

            for (int i = 0; i < hives.Length; i++) {
                try {
                    using (RegistryKey key = hives[i].OpenSubKey(paths[i])) {
                        if (key == null) continue;
                        string[] subKeyNames = key.GetSubKeyNames();
                        for (int j = 0; j < subKeyNames.Length; j++) {
                            string subName = subKeyNames[j];
                            if (!string.IsNullOrEmpty(subName)) {
                                keyNames.Add(subName);
                            }
                            try {
                                using (RegistryKey subKey = key.OpenSubKey(subName)) {
                                    if (subKey == null) continue;
                                    object disp = subKey.GetValue("DisplayName");
                                    if (disp != null) {
                                        string dispStr = disp.ToString().Trim();
                                        if (!string.IsNullOrEmpty(dispStr)) {
                                            displayNames.Add(dispStr);
                                        }
                                    }
                                }
                            } catch {}
                        }
                    }
                } catch {}
            }

            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            sb.Append((char)123).Append((char)34).Append("displayNames").Append((char)34).Append((char)58).Append((char)91);
            bool first = true;
            foreach (string dn in displayNames) {
                if (!first) sb.Append(',');
                first = false;
                sb.Append((char)34);
                for (int c = 0; c < dn.Length; c++) {
                    char ch = dn[c];
                    if (ch == (char)92) { sb.Append((char)92); sb.Append((char)92); }
                    else if (ch == (char)34) { sb.Append((char)92); sb.Append((char)34); }
                    else if (ch == (char)13) { sb.Append((char)92); sb.Append('r'); }
                    else if (ch == (char)10) { sb.Append((char)92); sb.Append('n'); }
                    else if (ch == (char)9) { sb.Append((char)92); sb.Append('t'); }
                    else if ((int)ch < 32) { sb.Append(' '); }
                    else { sb.Append(ch); }
                }
                sb.Append((char)34);
            }

            sb.Append((char)93).Append((char)44).Append((char)34).Append("keyNames").Append((char)34).Append((char)58).Append((char)91);
            first = true;
            foreach (string kn in keyNames) {
                if (!first) sb.Append(',');
                first = false;
                sb.Append((char)34);
                for (int c = 0; c < kn.Length; c++) {
                    char ch = kn[c];
                    if (ch == (char)92) { sb.Append((char)92); sb.Append((char)92); }
                    else if (ch == (char)34) { sb.Append((char)92); sb.Append((char)34); }
                    else if (ch == (char)13) { sb.Append((char)92); sb.Append('r'); }
                    else if (ch == (char)10) { sb.Append((char)92); sb.Append('n'); }
                    else if (ch == (char)9) { sb.Append((char)92); sb.Append('t'); }
                    else if ((int)ch < 32) { sb.Append(' '); }
                    else { sb.Append(ch); }
                }
                sb.Append((char)34);
            }
            sb.Append((char)93).Append((char)125);

            byte[] bytes = System.Text.Encoding.UTF8.GetBytes(sb.ToString());
            return Convert.ToBase64String(bytes);
        }
    }

    public static class ProcessRunner {
        public static Process CurrentProcess = null;
        public static ConcurrentQueue<string> OutputQueue = new ConcurrentQueue<string>();
        public static bool IsRunning = false;
        public static bool HasExited = false;
        public static int ExitCode = 0;
        private static readonly object _lock = new object();

        public static void Stop() {
            lock (_lock) {
                try {
                    if (CurrentProcess != null && !CurrentProcess.HasExited) {
                        CurrentProcess.Kill();
                    }
                } catch {}
                CurrentProcess = null;
                IsRunning = false;
            }
        }

        public static void Start(string command) {
            Stop();
            string dummy;
            while (OutputQueue.TryDequeue(out dummy)) {}

            IsRunning = true;
            HasExited = false;
            ExitCode = 0;

            ThreadPool.QueueUserWorkItem(state => {
                try {
                    byte[] cmdBytes = System.Text.Encoding.Unicode.GetBytes(command);
                    string b64Cmd = Convert.ToBase64String(cmdBytes);

                    var psi = new ProcessStartInfo {
                        FileName = "powershell.exe",
                        Arguments = "-NoProfile -ExecutionPolicy Bypass -NonInteractive -EncodedCommand " + b64Cmd,
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true,
                        StandardOutputEncoding = System.Text.Encoding.UTF8,
                        StandardErrorEncoding = System.Text.Encoding.UTF8
                    };

                    var proc = new Process { StartInfo = psi };
                    lock (_lock) {
                        CurrentProcess = proc;
                    }

                    proc.OutputDataReceived += (s, e) => {
                        if (e.Data != null) {
                            string d = e.Data;
                            if (!d.StartsWith("#< CLIXML")) {
                                OutputQueue.Enqueue(d);
                            }
                        }
                    };

                    proc.ErrorDataReceived += (s, e) => {
                        if (e.Data != null) {
                            string d = e.Data;
                            if (!d.StartsWith("#< CLIXML") && !d.StartsWith("<Objs") && !d.EndsWith("</Objs>")) {
                                OutputQueue.Enqueue("[ERR] " + d);
                            }
                        }
                    };

                    proc.Start();
                    proc.BeginOutputReadLine();
                    proc.BeginErrorReadLine();
                    proc.WaitForExit();

                    ExitCode = proc.ExitCode;
                } catch (Exception ex) {
                    OutputQueue.Enqueue("[ERR] " + ex.Message);
                    ExitCode = -1;
                } finally {
                    HasExited = true;
                    IsRunning = false;
                    lock (_lock) {
                        CurrentProcess = null;
                    }
                }
            });
        }

        public static bool TryDequeue(out string line) {
            return OutputQueue.TryDequeue(out line);
        }
    }

}
'@
    Add-Type -TypeDefinition $csharpCode
}

function Start-LauncherApp {
    $cacheDir = Join-Path $env:LOCALAPPDATA "PowerShellLauncher"
    $binDir = Join-Path $cacheDir "bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    $repoBaseUrl = "https://raw.githubusercontent.com/phwyverysad/powershell/main"
    $files = @(
        @{ Name = "Microsoft.Web.WebView2.Core.dll"; Url = "$repoBaseUrl/bin/Microsoft.Web.WebView2.Core.dll" },
        @{ Name = "Microsoft.Web.WebView2.Wpf.dll";  Url = "$repoBaseUrl/bin/Microsoft.Web.WebView2.Wpf.dll" },
        @{ Name = "WebView2Loader.dll";              Url = "$repoBaseUrl/bin/WebView2Loader.dll" }
    )

    foreach ($f in $files) {
        $dest = Join-Path $binDir $f.Name
        if (-not (Test-Path $dest)) {
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                $wc.DownloadFile($f.Url, $dest)
            } catch {
                Write-Error "Failed to download $($f.Name): $_"
                return
            }
        }
    }

    $coreDllPath = Join-Path $binDir "Microsoft.Web.WebView2.Core.dll"
    $wpfDllPath = Join-Path $binDir "Microsoft.Web.WebView2.Wpf.dll"
    [System.Reflection.Assembly]::LoadFrom($coreDllPath) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($wpfDllPath) | Out-Null

    # Decompress embedded HTML payload
    $b64 = "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"
    $bytes = [System.Convert]::FromBase64String($b64)
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $sr = New-Object System.IO.StreamReader($gz, [System.Text.Encoding]::UTF8)
    $htmlContent = $sr.ReadToEnd()
    $sr.Close()
    $gz.Close()
    $ms.Close()

    # Always overwrite cached HTML to guarantee fresh execution
    $cacheHtml = Join-Path $cacheDir "clean_utility_launcher_gui.html"
    try {
        [System.IO.File]::WriteAllText($cacheHtml, $htmlContent, [System.Text.Encoding]::UTF8)
    } catch {}

    $env:WEBVIEW2_USER_DATA_FOLDER = Join-Path $cacheDir "WebView2Data"

    # WPF Window configuration: Non-topmost, custom clean chrome, rounded region
    $window = New-Object System.Windows.Window
    $window.Title = "All-in-One Launcher"
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $idealWidth = 1460
    $idealHeight = 880
    $window.Width = [Math]::Min($idealWidth, [Math]::Max(1100, $workArea.Width - 40))
    $window.Height = [Math]::Min($idealHeight, [Math]::Max(700, $workArea.Height - 40))
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $window.WindowStyle = "None"
    $window.AllowsTransparency = $false
    $window.Background = [System.Windows.Media.Brushes]::White
    $window.WindowStartupLocation = "CenterScreen"
    $window.ResizeMode = "NoResize"
    $window.Topmost = $false

    try {
        $chrome = New-Object System.Windows.Shell.WindowChrome -ErrorAction SilentlyContinue
        if ($chrome) {
            $chrome.CaptionHeight = 0
            $chrome.ResizeBorderThickness = New-Object System.Windows.Thickness(0)
            $chrome.GlassFrameThickness = New-Object System.Windows.Thickness(0)
            $chrome.CornerRadius = New-Object System.Windows.CornerRadius(0)
            [System.Windows.Shell.WindowChrome]::SetWindowChrome($window, $chrome)
        }
    } catch {}

    $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
    $window.Content = $wv

    $script:isMaximized = $false
    $script:normalLeft = 0
    $script:normalTop = 0
    $script:normalWidth = $window.Width
    $script:normalHeight = $window.Height
    $script:logTimer = $null

    function script:Update-WindowRegion([bool]$maximized) {
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
            if ($hwnd -ne [System.IntPtr]::Zero) {
                if ($maximized) {
                    [WinUtil.LauncherWinUtil]::SetWindowRgn($hwnd, [System.IntPtr]::Zero, $true) | Out-Null
                } else {
                    $rect = New-Object WinUtil.LauncherWinUtil+RECT
                    [WinUtil.LauncherWinUtil]::GetClientRect($hwnd, [ref]$rect)
                    $w = $rect.Right - $rect.Left
                    $h = $rect.Bottom - $rect.Top
                    if ($w -gt 50 -and $h -gt 50) {
                        $rgn = [WinUtil.LauncherWinUtil]::CreateRoundRectRgn(0, 0, $w + 1, $h + 1, 22, 22)
                        [WinUtil.LauncherWinUtil]::SetWindowRgn($hwnd, $rgn, $true) | Out-Null
                    }
                }
            }
        } catch {}
    }

    $window.Add_Loaded({
        try {
            $script:normalLeft = $window.Left
            $script:normalTop = $window.Top
            $script:normalWidth = $window.ActualWidth
            $script:normalHeight = $window.ActualHeight
            script:Update-WindowRegion $false
            $window.Activate()
            [void]$wv.EnsureCoreWebView2Async()
        } catch {}
    })

    $window.Add_LocationChanged({
        if (-not $script:isMaximized) {
            $script:normalLeft = $window.Left
            $script:normalTop = $window.Top
        }
    })

    $window.Add_StateChanged({
        if ($window.WindowState -eq "Normal" -and -not $script:isMaximized) {
            script:Update-WindowRegion $false
        }
    })

    $wv.Add_CoreWebView2InitializationCompleted({
        param($s, $e)
        if ($e.IsSuccess) {
            try { $wv.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $false } catch {}
            $wv.CoreWebView2.add_NavigationCompleted({
                param($s3, $e3)
                try {
                    $b64 = [WinUtil.AppScanner]::GetInstalledAppsBase64()
                    $wv.ExecuteScriptAsync("window.setInstalledRegistryBase64 && window.setInstalledRegistryBase64('$b64');") | Out-Null
                } catch {}
            })

            $wv.CoreWebView2.add_WebMessageReceived({
                param($s2, $e2)
                try {
                    $json = $e2.WebMessageAsJson
                    $payload = $json | ConvertFrom-Json

                    switch ($payload.type) {
                        "drag" {
                            $window.Dispatcher.Invoke([Action]{
                                try {
                                    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
                                    if ($script:isMaximized) {
                                        $script:isMaximized = $false
                                        $window.Width = $script:normalWidth
                                        $window.Height = $script:normalHeight
                                        $pt = New-Object WinUtil.LauncherWinUtil+POINT
                                        [WinUtil.LauncherWinUtil]::GetCursorPos([ref]$pt)
                                        $window.Left = [Math]::Max(0, [int]($pt.X - ($script:normalWidth / 2)))
                                        $window.Top = [Math]::Max(0, [int]($pt.Y - 20))
                                        script:Update-WindowRegion $false
                                        $wv.ExecuteScriptAsync("window.setWindowState && window.setWindowState(false);") | Out-Null
                                    }
                                    [WinUtil.LauncherWinUtil]::ReleaseCapture()
                                    [WinUtil.LauncherWinUtil]::SendMessage($hwnd, 0xA1, 2, 0)
                                } catch {}
                            })
                        }
                        "minimize" {
                            $window.Dispatcher.Invoke([Action]{
                                $window.WindowState = "Minimized"
                            })
                        }
                        "maximize" {
                            $window.Dispatcher.Invoke([Action]{
                                $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
                                if ($script:isMaximized) {
                                    $script:isMaximized = $false
                                    $window.Left = $script:normalLeft
                                    $window.Top = $script:normalTop
                                    $window.Width = $script:normalWidth
                                    $window.Height = $script:normalHeight
                                    script:Update-WindowRegion $false
                                    $wv.ExecuteScriptAsync("window.setWindowState && window.setWindowState(false);") | Out-Null
                                } else {
                                    $script:normalLeft = $window.Left
                                    $script:normalTop = $window.Top
                                    $script:normalWidth = $window.ActualWidth
                                    $script:normalHeight = $window.ActualHeight
                                    $script:isMaximized = $true
                                    script:Update-WindowRegion $true
                                    $work = [System.Windows.SystemParameters]::WorkArea
                                    $window.Left = $work.Left
                                    $window.Top = $work.Top
                                    $window.Width = $work.Width
                                    $window.Height = $work.Height
                                    $wv.ExecuteScriptAsync("window.setWindowState && window.setWindowState(true);") | Out-Null
                                }
                            })
                        }
                        "close" {
                            $window.Dispatcher.Invoke([Action]{
                                if ($script:logTimer) { $script:logTimer.Stop() }
                                [WinUtil.ProcessRunner]::Stop()
                                $window.Close()
                            })
                        }
                        "cancel" {
                            if ($script:logTimer) { $script:logTimer.Stop() }
                            [WinUtil.ProcessRunner]::Stop()
                        }
                        "open_url" {
                            $url = $payload.url
                            if ($url -match "^https?://") {
                                $psi = New-Object System.Diagnostics.ProcessStartInfo($url)
                                $psi.UseShellExecute = $true
                                [System.Diagnostics.Process]::Start($psi) | Out-Null
                            }
                        }
                        "batch_run" {
                            $mode = $payload.mode
                            $items = $payload.items
                            if (-not $items -or $items.Count -eq 0) { return }

                            $cmdList = @()
                            $total = $items.Count
                            for ($i = 0; $i -lt $total; $i++) {
                                $item = $items[$i]
                                $stepNum = $i + 1
                                $appName = $item.name
                                $pkgId = $item.wingetId

                                if ($mode -eq "uninstall") {
                                    $uninstCmd = if ($pkgId) { "winget uninstall -e --id $pkgId" } else { "winget uninstall `"$appName`"" }
                                    $cmdList += "Write-Host '`n========================================' -ForegroundColor Yellow"
                                    $cmdList += "Write-Host '[$stepNum/$total] Uninstalling: $appName' -ForegroundColor Yellow"
                                    $cmdList += "Write-Host 'Command: $uninstCmd' -ForegroundColor DarkGray"
                                    $cmdList += "Write-Host '========================================' -ForegroundColor Yellow"
                                    $cmdList += $uninstCmd
                                } else {
                                    $installCmd = if ($item.cmd) { $item.cmd } else { "winget install -e --id $pkgId" }
                                    if ($installCmd -match "^winget\s+install" -and $installCmd -notmatch "--accept-source-agreements") {
                                        $installCmd = "$installCmd --accept-source-agreements --accept-package-agreements"
                                    }
                                    $cmdList += "Write-Host '`n========================================' -ForegroundColor Cyan"
                                    $cmdList += "Write-Host '[$stepNum/$total] Installing: $appName' -ForegroundColor Green"
                                    $cmdList += "Write-Host 'Command: $installCmd' -ForegroundColor DarkGray"
                                    $cmdList += "Write-Host '========================================' -ForegroundColor Cyan"
                                    $cmdList += $installCmd
                                }
                            }
                            $fullBatchCmd = $cmdList -join "; "

                            $safeMode = [System.Web.HttpUtility]::JavaScriptStringEncode($mode)
                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(10, 'Processing batch ($total items)...');") | Out-Null
                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('Starting $safeMode batch for $total items...', false);") | Out-Null

                            [WinUtil.ProcessRunner]::Start($fullBatchCmd)

                            if ($script:logTimer) { $script:logTimer.Stop() }
                            $script:logTimer = New-Object System.Windows.Threading.DispatcherTimer
                            $script:logTimer.Interval = [TimeSpan]::FromMilliseconds(50)
                            $script:logTimer.Add_Tick({
                                $line = ""
                                while ([WinUtil.ProcessRunner]::TryDequeue([ref]$line)) {
                                    if ($line) {
                                        $isErr = $line.StartsWith("[ERR] ")
                                        $cleanLine = if ($isErr) { $line.Substring(6) } else { $line }
                                        $safeLine = [System.Web.HttpUtility]::JavaScriptStringEncode($cleanLine)
                                        $isErrStr = if ($isErr) { "true" } else { "false" }
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('$safeLine', $isErrStr);") | Out-Null
                                    }
                                }

                                if ([WinUtil.ProcessRunner]::HasExited -and -not [WinUtil.ProcessRunner]::IsRunning) {
                                    $script:logTimer.Stop()
                                    $exitCode = [WinUtil.ProcessRunner]::ExitCode
                                    $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(100, '');") | Out-Null
                                    if ($exitCode -eq 0) {
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(true, 'Batch $safeMode finished successfully');") | Out-Null
                                    } else {
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(false, 'Batch completed with exit code $exitCode');") | Out-Null
                                    }

                                    try {
                                        $reB64 = [WinUtil.AppScanner]::GetInstalledAppsBase64()
                                        $wv.ExecuteScriptAsync("window.setInstalledRegistryBase64 && window.setInstalledRegistryBase64('$reB64');") | Out-Null
                                    } catch {}
                                }
                            })
                            $script:logTimer.Start()
                        }
                        "run" {
                            $cmd = $payload.cmd
                            $appName = $payload.appName

                            if ($cmd -match "^winget\s+install" -and $cmd -notmatch "--accept-source-agreements") {
                                $cmd = "$cmd --accept-source-agreements --accept-package-agreements"
                            }

                            $safeApp = [System.Web.HttpUtility]::JavaScriptStringEncode($appName)
                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(15, 'Starting...');") | Out-Null
                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('Starting: $safeApp', false);") | Out-Null

                            [WinUtil.ProcessRunner]::Start($cmd)

                            if ($script:logTimer) { $script:logTimer.Stop() }
                            $script:logTimer = New-Object System.Windows.Threading.DispatcherTimer
                            $script:logTimer.Interval = [TimeSpan]::FromMilliseconds(50)
                            $script:logTimer.Add_Tick({
                                $line = ""
                                while ([WinUtil.ProcessRunner]::TryDequeue([ref]$line)) {
                                    if ($line) {
                                        $isErr = $line.StartsWith("[ERR] ")
                                        $cleanLine = if ($isErr) { $line.Substring(6) } else { $line }
                                        $safeLine = [System.Web.HttpUtility]::JavaScriptStringEncode($cleanLine)
                                        $isErrStr = if ($isErr) { "true" } else { "false" }
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('$safeLine', $isErrStr);") | Out-Null
                                    }
                                }

                                if ([WinUtil.ProcessRunner]::HasExited -and -not [WinUtil.ProcessRunner]::IsRunning) {
                                    $script:logTimer.Stop()
                                    $exitCode = [WinUtil.ProcessRunner]::ExitCode
                                    $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(100, '');") | Out-Null
                                    if ($exitCode -eq 0) {
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(true, 'Installation finished (ExitCode: 0)');") | Out-Null
                                    } else {
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(false, 'Command finished with exit code $exitCode');") | Out-Null
                                    }

                                    try {
                                        $reB64 = [WinUtil.AppScanner]::GetInstalledAppsBase64()
                                        $wv.ExecuteScriptAsync("window.setInstalledRegistryBase64 && window.setInstalledRegistryBase64('$reB64');") | Out-Null
                                    } catch {}
                                }
                            })
                            $script:logTimer.Start()
                        }
                    }
                } catch {}
            })

            $wv.NavigateToString($htmlContent)
        }
    })

    $window.ShowDialog() | Out-Null
}

Start-LauncherApp
