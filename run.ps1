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
