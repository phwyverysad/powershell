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
    $window.Width = 1380
    $window.Height = 840
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
    $script:normalWidth = 1380
    $script:normalHeight = 840
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
