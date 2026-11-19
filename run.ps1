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
        public static string[] GetInstalledDisplayNames() {
            HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
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
                            try {
                                using (RegistryKey subKey = key.OpenSubKey(subName)) {
                                    if (subKey == null) continue;
                                    names.Add(subName);
                                    object disp = subKey.GetValue("DisplayName");
                                    if (disp != null) {
                                        string dispStr = disp.ToString();
                                        if (!string.IsNullOrEmpty(dispStr)) {
                                            names.Add(dispStr);
                                        }
                                    }
                                }
                            } catch {}
                        }
                    }
                } catch {}
            }
            string[] result = new string[names.Count];
            names.CopyTo(result);
            return result;
        }

        public static string GetInstalledAppsBase64() {
            string[] names = GetInstalledDisplayNames();
            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            sb.Append('[');
            bool first = true;
            for (int i = 0; i < names.Length; i++) {
                string n = names[i];
                if (string.IsNullOrEmpty(n)) continue;
                if (!first) sb.Append(',');
                first = false;
                sb.Append((char)34);
                for (int c = 0; c < n.Length; c++) {
                    char ch = n[c];
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
            sb.Append(']');
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
                    var psi = new ProcessStartInfo {
                        FileName = "powershell.exe",
                        Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"" + command.Replace("\"", "\\\"") + "\"",
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    };

                    var proc = new Process { StartInfo = psi };
                    lock (_lock) {
                        CurrentProcess = proc;
                    }

                    proc.OutputDataReceived += (s, e) => {
                        if (e.Data != null) OutputQueue.Enqueue(e.Data);
                    };

                    proc.ErrorDataReceived += (s, e) => {
                        if (e.Data != null) OutputQueue.Enqueue("[ERR] " + e.Data);
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
    $window.Width = 1180
    $window.Height = 740
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
    $script:normalWidth = 1180
    $script:normalHeight = 740
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

    $app = New-Object System.Windows.Application
    $app.Run($window) | Out-Null
}

Start-LauncherApp
