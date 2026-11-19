import os
import gzip
import base64

html_file = r"C:\Users\Administrator\.gemini\antigravity\scratch\powershell\clean_utility_launcher_gui.html"
with open(html_file, "r", encoding="utf-8") as f:
    html_text = f.read()

# GZip compress HTML
raw_bytes = html_text.encode("utf-8")
gz_bytes = gzip.compress(raw_bytes, compresslevel=9)
b64_str = base64.b64encode(gz_bytes).decode("ascii")

ps1_content = f'''# All-in-One Utility Launcher
# Repository: https://github.com/phwyverysad/powershell.git
# Execution: irm https://raw.githubusercontent.com/phwyverysad/powershell/main/run.ps1 | iex

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Web

if (-not ([System.Management.Automation.PSTypeName]'WinUtil.ProcessRunner').Type) {{
    $csharpCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32;

namespace WinUtil {{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {{
        public int Left, Top, Right, Bottom;
    }}
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {{
        public int X, Y;
    }}

    public static class LauncherWinUtil {{
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
    }}

    public static class AppScanner {{
        public static string GetInstalledAppsBase64() {{
            HashSet<string> displayNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            HashSet<string> keyNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            RegistryKey[] hives = new RegistryKey[] {{ Registry.LocalMachine, Registry.LocalMachine, Registry.CurrentUser }};
            string[] paths = new string[] {{
                @"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                @"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                @"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
            }};

            for (int i = 0; i < hives.Length; i++) {{
                try {{
                    using (RegistryKey key = hives[i].OpenSubKey(paths[i])) {{
                        if (key == null) continue;
                        string[] subKeyNames = key.GetSubKeyNames();
                        for (int j = 0; j < subKeyNames.Length; j++) {{
                            string subName = subKeyNames[j];
                            if (!string.IsNullOrEmpty(subName)) {{
                                keyNames.Add(subName);
                            }}
                            try {{
                                using (RegistryKey subKey = key.OpenSubKey(subName)) {{
                                    if (subKey == null) continue;
                                    object disp = subKey.GetValue("DisplayName");
                                    if (disp != null) {{
                                        string dispStr = disp.ToString().Trim();
                                        if (!string.IsNullOrEmpty(dispStr)) {{
                                            displayNames.Add(dispStr);
                                        }}
                                    }}
                                }}
                            }} catch {{}}
                        }}
                    }}
                }} catch {{}}
            }}

            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            sb.Append((char)123).Append((char)34).Append("displayNames").Append((char)34).Append((char)58).Append((char)91);
            bool first = true;
            foreach (string dn in displayNames) {{
                if (!first) sb.Append(',');
                first = false;
                sb.Append((char)34);
                for (int c = 0; c < dn.Length; c++) {{
                    char ch = dn[c];
                    if (ch == (char)92) {{ sb.Append((char)92); sb.Append((char)92); }}
                    else if (ch == (char)34) {{ sb.Append((char)92); sb.Append((char)34); }}
                    else if (ch == (char)13) {{ sb.Append((char)92); sb.Append('r'); }}
                    else if (ch == (char)10) {{ sb.Append((char)92); sb.Append('n'); }}
                    else if (ch == (char)9) {{ sb.Append((char)92); sb.Append('t'); }}
                    else if ((int)ch < 32) {{ sb.Append(' '); }}
                    else {{ sb.Append(ch); }}
                }}
                sb.Append((char)34);
            }}

            sb.Append((char)93).Append((char)44).Append((char)34).Append("keyNames").Append((char)34).Append((char)58).Append((char)91);
            first = true;
            foreach (string kn in keyNames) {{
                if (!first) sb.Append(',');
                first = false;
                sb.Append((char)34);
                for (int c = 0; c < kn.Length; c++) {{
                    char ch = kn[c];
                    if (ch == (char)92) {{ sb.Append((char)92); sb.Append((char)92); }}
                    else if (ch == (char)34) {{ sb.Append((char)92); sb.Append((char)34); }}
                    else if (ch == (char)13) {{ sb.Append((char)92); sb.Append('r'); }}
                    else if (ch == (char)10) {{ sb.Append((char)92); sb.Append('n'); }}
                    else if (ch == (char)9) {{ sb.Append((char)92); sb.Append('t'); }}
                    else if ((int)ch < 32) {{ sb.Append(' '); }}
                    else {{ sb.Append(ch); }}
                }}
                sb.Append((char)34);
            }}
            sb.Append((char)93).Append((char)125);

            byte[] bytes = System.Text.Encoding.UTF8.GetBytes(sb.ToString());
            return Convert.ToBase64String(bytes);
        }}
    }}

    public static class ProcessRunner {{
        public static Process CurrentProcess = null;
        public static ConcurrentQueue<string> OutputQueue = new ConcurrentQueue<string>();
        public static bool IsRunning = false;
        public static bool HasExited = false;
        public static int ExitCode = 0;
        private static readonly object _lock = new object();

        public static void Stop() {{
            lock (_lock) {{
                try {{
                    if (CurrentProcess != null && !CurrentProcess.HasExited) {{
                        CurrentProcess.Kill();
                    }}
                }} catch {{}}
                CurrentProcess = null;
                IsRunning = false;
            }}
        }}

        public static void Start(string command) {{
            Stop();
            string dummy;
            while (OutputQueue.TryDequeue(out dummy)) {{}}

            IsRunning = true;
            HasExited = false;
            ExitCode = 0;

            ThreadPool.QueueUserWorkItem(state => {{
                try {{
                    byte[] cmdBytes = System.Text.Encoding.Unicode.GetBytes(command);
                    string b64Cmd = Convert.ToBase64String(cmdBytes);

                    var psi = new ProcessStartInfo {{
                        FileName = "powershell.exe",
                        Arguments = "-NoProfile -ExecutionPolicy Bypass -NonInteractive -EncodedCommand " + b64Cmd,
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true,
                        StandardOutputEncoding = System.Text.Encoding.UTF8,
                        StandardErrorEncoding = System.Text.Encoding.UTF8
                    }};

                    var proc = new Process {{ StartInfo = psi }};
                    lock (_lock) {{
                        CurrentProcess = proc;
                    }}

                    proc.OutputDataReceived += (s, e) => {{
                        if (e.Data != null) {{
                            string d = e.Data;
                            if (!d.StartsWith("#< CLIXML")) {{
                                OutputQueue.Enqueue(d);
                            }}
                        }}
                    }};

                    proc.ErrorDataReceived += (s, e) => {{
                        if (e.Data != null) {{
                            string d = e.Data;
                            if (!d.StartsWith("#< CLIXML") && !d.StartsWith("<Objs") && !d.EndsWith("</Objs>")) {{
                                OutputQueue.Enqueue("[ERR] " + d);
                            }}
                        }}
                    }};

                    proc.Start();
                    proc.BeginOutputReadLine();
                    proc.BeginErrorReadLine();
                    proc.WaitForExit();

                    ExitCode = proc.ExitCode;
                }} catch (Exception ex) {{
                    OutputQueue.Enqueue("[ERR] " + ex.Message);
                    ExitCode = -1;
                }} finally {{
                    HasExited = true;
                    IsRunning = false;
                    lock (_lock) {{
                        CurrentProcess = null;
                    }}
                }}
            }});
        }}

        public static bool TryDequeue(out string line) {{
            return OutputQueue.TryDequeue(out line);
        }}
    }}

}}
'@
    Add-Type -TypeDefinition $csharpCode
}}

function Start-LauncherApp {{
    $cacheDir = Join-Path $env:LOCALAPPDATA "PowerShellLauncher"
    $binDir = Join-Path $cacheDir "bin"
    if (-not (Test-Path $binDir)) {{
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }}

    $repoBaseUrl = "https://raw.githubusercontent.com/phwyverysad/powershell/main"
    $files = @(
        @{{ Name = "Microsoft.Web.WebView2.Core.dll"; Url = "$repoBaseUrl/bin/Microsoft.Web.WebView2.Core.dll" }},
        @{{ Name = "Microsoft.Web.WebView2.Wpf.dll";  Url = "$repoBaseUrl/bin/Microsoft.Web.WebView2.Wpf.dll" }},
        @{{ Name = "WebView2Loader.dll";              Url = "$repoBaseUrl/bin/WebView2Loader.dll" }}
    )

    foreach ($f in $files) {{
        $dest = Join-Path $binDir $f.Name
        if (-not (Test-Path $dest)) {{
            try {{
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                $wc.DownloadFile($f.Url, $dest)
            }} catch {{
                Write-Error "Failed to download $($f.Name): $_"
                return
            }}
        }}
    }}

    $coreDllPath = Join-Path $binDir "Microsoft.Web.WebView2.Core.dll"
    $wpfDllPath = Join-Path $binDir "Microsoft.Web.WebView2.Wpf.dll"
    [System.Reflection.Assembly]::LoadFrom($coreDllPath) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($wpfDllPath) | Out-Null

    # Decompress embedded HTML payload
    $b64 = "{b64_str}"
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
    try {{
        [System.IO.File]::WriteAllText($cacheHtml, $htmlContent, [System.Text.Encoding]::UTF8)
    }} catch {{}}

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

    try {{
        $chrome = New-Object System.Windows.Shell.WindowChrome -ErrorAction SilentlyContinue
        if ($chrome) {{
            $chrome.CaptionHeight = 0
            $chrome.ResizeBorderThickness = New-Object System.Windows.Thickness(0)
            $chrome.GlassFrameThickness = New-Object System.Windows.Thickness(0)
            $chrome.CornerRadius = New-Object System.Windows.CornerRadius(0)
            [System.Windows.Shell.WindowChrome]::SetWindowChrome($window, $chrome)
        }}
    }} catch {{}}

    $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
    $window.Content = $wv

    $script:isMaximized = $false
    $script:normalLeft = 0
    $script:normalTop = 0
    $script:normalWidth = 1380
    $script:normalHeight = 840
    $script:logTimer = $null

    function script:Update-WindowRegion([bool]$maximized) {{
        try {{
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
            if ($hwnd -ne [System.IntPtr]::Zero) {{
                if ($maximized) {{
                    [WinUtil.LauncherWinUtil]::SetWindowRgn($hwnd, [System.IntPtr]::Zero, $true) | Out-Null
                }} else {{
                    $rect = New-Object WinUtil.LauncherWinUtil+RECT
                    [WinUtil.LauncherWinUtil]::GetClientRect($hwnd, [ref]$rect)
                    $w = $rect.Right - $rect.Left
                    $h = $rect.Bottom - $rect.Top
                    if ($w -gt 50 -and $h -gt 50) {{
                        $rgn = [WinUtil.LauncherWinUtil]::CreateRoundRectRgn(0, 0, $w + 1, $h + 1, 22, 22)
                        [WinUtil.LauncherWinUtil]::SetWindowRgn($hwnd, $rgn, $true) | Out-Null
                    }}
                }}
            }}
        }} catch {{}}
    }}

    $window.Add_Loaded({{
        try {{
            $script:normalLeft = $window.Left
            $script:normalTop = $window.Top
            $script:normalWidth = $window.ActualWidth
            $script:normalHeight = $window.ActualHeight
            script:Update-WindowRegion $false
            $window.Activate()
            [void]$wv.EnsureCoreWebView2Async()
        }} catch {{}}
    }})

    $window.Add_LocationChanged({{
        if (-not $script:isMaximized) {{
            $script:normalLeft = $window.Left
            $script:normalTop = $window.Top
        }}
    }})

    $window.Add_StateChanged({{
        if ($window.WindowState -eq "Normal" -and -not $script:isMaximized) {{
            script:Update-WindowRegion $false
        }}
    }})

    $wv.Add_CoreWebView2InitializationCompleted({{
        param($s, $e)
        if ($e.IsSuccess) {{
            try {{ $wv.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $false }} catch {{}}
            $wv.CoreWebView2.add_NavigationCompleted({{
                param($s3, $e3)
                try {{
                    $b64 = [WinUtil.AppScanner]::GetInstalledAppsBase64()
                    $wv.ExecuteScriptAsync("window.setInstalledRegistryBase64 && window.setInstalledRegistryBase64('$b64');") | Out-Null
                }} catch {{}}
            }})

            $wv.CoreWebView2.add_WebMessageReceived({{
                param($s2, $e2)
                try {{
                    $json = $e2.WebMessageAsJson
                    $payload = $json | ConvertFrom-Json

                    switch ($payload.type) {{
                        "drag" {{
                            $window.Dispatcher.Invoke([Action]{{
                                try {{
                                    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
                                    if ($script:isMaximized) {{
                                        $script:isMaximized = $false
                                        $window.Width = $script:normalWidth
                                        $window.Height = $script:normalHeight
                                        $pt = New-Object WinUtil.LauncherWinUtil+POINT
                                        [WinUtil.LauncherWinUtil]::GetCursorPos([ref]$pt)
                                        $window.Left = [Math]::Max(0, [int]($pt.X - ($script:normalWidth / 2)))
                                        $window.Top = [Math]::Max(0, [int]($pt.Y - 20))
                                        script:Update-WindowRegion $false
                                        $wv.ExecuteScriptAsync("window.setWindowState && window.setWindowState(false);") | Out-Null
                                    }}
                                    [WinUtil.LauncherWinUtil]::ReleaseCapture()
                                    [WinUtil.LauncherWinUtil]::SendMessage($hwnd, 0xA1, 2, 0)
                                }} catch {{}}
                            }})
                        }}
                        "minimize" {{
                            $window.Dispatcher.Invoke([Action]{{
                                $window.WindowState = "Minimized"
                            }})
                        }}
                        "maximize" {{
                            $window.Dispatcher.Invoke([Action]{{
                                $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
                                if ($script:isMaximized) {{
                                    $script:isMaximized = $false
                                    $window.Left = $script:normalLeft
                                    $window.Top = $script:normalTop
                                    $window.Width = $script:normalWidth
                                    $window.Height = $script:normalHeight
                                    script:Update-WindowRegion $false
                                    $wv.ExecuteScriptAsync("window.setWindowState && window.setWindowState(false);") | Out-Null
                                }} else {{
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
                                }}
                            }})
                        }}
                        "close" {{
                            $window.Dispatcher.Invoke([Action]{{
                                if ($script:logTimer) {{ $script:logTimer.Stop() }}
                                [WinUtil.ProcessRunner]::Stop()
                                $window.Close()
                            }})
                        }}
                        "cancel" {{
                            if ($script:logTimer) {{ $script:logTimer.Stop() }}
                            [WinUtil.ProcessRunner]::Stop()
                        }}
                        "open_url" {{
                            $url = $payload.url
                            if ($url -match "^https?://") {{
                                $psi = New-Object System.Diagnostics.ProcessStartInfo($url)
                                $psi.UseShellExecute = $true
                                [System.Diagnostics.Process]::Start($psi) | Out-Null
                            }}
                        }}
                        "batch_run" {{
                            $mode = $payload.mode
                            $items = $payload.items
                            if (-not $items -or $items.Count -eq 0) {{ return }}

                            $cmdList = @()
                            $total = $items.Count
                            for ($i = 0; $i -lt $total; $i++) {{
                                $item = $items[$i]
                                $stepNum = $i + 1
                                $appName = $item.name
                                $pkgId = $item.wingetId

                                if ($mode -eq "uninstall") {{
                                    $uninstCmd = if ($pkgId) {{ "winget uninstall -e --id $pkgId" }} else {{ "winget uninstall `"$appName`"" }}
                                    $cmdList += "Write-Host '`n========================================' -ForegroundColor Yellow"
                                    $cmdList += "Write-Host '[$stepNum/$total] Uninstalling: $appName' -ForegroundColor Yellow"
                                    $cmdList += "Write-Host 'Command: $uninstCmd' -ForegroundColor DarkGray"
                                    $cmdList += "Write-Host '========================================' -ForegroundColor Yellow"
                                    $cmdList += $uninstCmd
                                }} else {{
                                    $installCmd = if ($item.cmd) {{ $item.cmd }} else {{ "winget install -e --id $pkgId" }}
                                    if ($installCmd -match "^winget\\s+install" -and $installCmd -notmatch "--accept-source-agreements") {{
                                        $installCmd = "$installCmd --accept-source-agreements --accept-package-agreements"
                                    }}
                                    $cmdList += "Write-Host '`n========================================' -ForegroundColor Cyan"
                                    $cmdList += "Write-Host '[$stepNum/$total] Installing: $appName' -ForegroundColor Green"
                                    $cmdList += "Write-Host 'Command: $installCmd' -ForegroundColor DarkGray"
                                    $cmdList += "Write-Host '========================================' -ForegroundColor Cyan"
                                    $cmdList += $installCmd
                                }}
                            }}
                            $fullBatchCmd = $cmdList -join "; "

                            $safeMode = [System.Web.HttpUtility]::JavaScriptStringEncode($mode)
                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(10, 'Processing batch ($total items)...');") | Out-Null
                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('Starting $safeMode batch for $total items...', false);") | Out-Null

                            [WinUtil.ProcessRunner]::Start($fullBatchCmd)

                            if ($script:logTimer) {{ $script:logTimer.Stop() }}
                            $script:logTimer = New-Object System.Windows.Threading.DispatcherTimer
                            $script:logTimer.Interval = [TimeSpan]::FromMilliseconds(50)
                            $script:logTimer.Add_Tick({{
                                $line = ""
                                while ([WinUtil.ProcessRunner]::TryDequeue([ref]$line)) {{
                                    if ($line) {{
                                        $isErr = $line.StartsWith("[ERR] ")
                                        $cleanLine = if ($isErr) {{ $line.Substring(6) }} else {{ $line }}
                                        $safeLine = [System.Web.HttpUtility]::JavaScriptStringEncode($cleanLine)
                                        $isErrStr = if ($isErr) {{ "true" }} else {{ "false" }}
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('$safeLine', $isErrStr);") | Out-Null
                                    }}
                                }}

                                if ([WinUtil.ProcessRunner]::HasExited -and -not [WinUtil.ProcessRunner]::IsRunning) {{
                                    $script:logTimer.Stop()
                                    $exitCode = [WinUtil.ProcessRunner]::ExitCode
                                    $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(100, '');") | Out-Null
                                    if ($exitCode -eq 0) {{
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(true, 'Batch $safeMode finished successfully');") | Out-Null
                                    }} else {{
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(false, 'Batch completed with exit code $exitCode');") | Out-Null
                                    }}

                                    try {{
                                        $reB64 = [WinUtil.AppScanner]::GetInstalledAppsBase64()
                                        $wv.ExecuteScriptAsync("window.setInstalledRegistryBase64 && window.setInstalledRegistryBase64('$reB64');") | Out-Null
                                    }} catch {{}}
                                }}
                            }})
                            $script:logTimer.Start()
                        }}
                        "run" {{
                            $cmd = $payload.cmd
                            $appName = $payload.appName

                            if ($cmd -match "^winget\\s+install" -and $cmd -notmatch "--accept-source-agreements") {{
                                $cmd = "$cmd --accept-source-agreements --accept-package-agreements"
                            }}

                            $safeApp = [System.Web.HttpUtility]::JavaScriptStringEncode($appName)
                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(15, 'Starting...');") | Out-Null
                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('Starting: $safeApp', false);") | Out-Null

                            [WinUtil.ProcessRunner]::Start($cmd)

                            if ($script:logTimer) {{ $script:logTimer.Stop() }}
                            $script:logTimer = New-Object System.Windows.Threading.DispatcherTimer
                            $script:logTimer.Interval = [TimeSpan]::FromMilliseconds(50)
                            $script:logTimer.Add_Tick({{
                                $line = ""
                                while ([WinUtil.ProcessRunner]::TryDequeue([ref]$line)) {{
                                    if ($line) {{
                                        $isErr = $line.StartsWith("[ERR] ")
                                        $cleanLine = if ($isErr) {{ $line.Substring(6) }} else {{ $line }}
                                        $safeLine = [System.Web.HttpUtility]::JavaScriptStringEncode($cleanLine)
                                        $isErrStr = if ($isErr) {{ "true" }} else {{ "false" }}
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('$safeLine', $isErrStr);") | Out-Null
                                    }}
                                }}

                                if ([WinUtil.ProcessRunner]::HasExited -and -not [WinUtil.ProcessRunner]::IsRunning) {{
                                    $script:logTimer.Stop()
                                    $exitCode = [WinUtil.ProcessRunner]::ExitCode
                                    $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(100, '');") | Out-Null
                                    if ($exitCode -eq 0) {{
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(true, 'Installation finished (ExitCode: 0)');") | Out-Null
                                    }} else {{
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(false, 'Command finished with exit code $exitCode');") | Out-Null
                                    }}

                                    try {{
                                        $reB64 = [WinUtil.AppScanner]::GetInstalledAppsBase64()
                                        $wv.ExecuteScriptAsync("window.setInstalledRegistryBase64 && window.setInstalledRegistryBase64('$reB64');") | Out-Null
                                    }} catch {{}}
                                }}
                            }})
                            $script:logTimer.Start()
                        }}
                    }}
                }} catch {{}}
            }})

            $wv.NavigateToString($htmlContent)
        }}
    }})

    $window.ShowDialog() | Out-Null
}}

Start-LauncherApp
'''

out_launcher = r"C:\Users\Administrator\.gemini\antigravity\scratch\powershell\launcher.ps1"
out_run = r"C:\Users\Administrator\.gemini\antigravity\scratch\powershell\run.ps1"

with open(out_launcher, "w", encoding="utf-8") as f:
    f.write(ps1_content)

with open(out_run, "w", encoding="utf-8") as f:
    f.write(ps1_content)

print(f"launcher.ps1 ({os.path.getsize(out_launcher)} bytes) and run.ps1 generated successfully!")
