try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]3072 -bor [System.Net.SecurityProtocolType]768 -bor [System.Net.SecurityProtocolType]192
} catch {}

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# Hide PowerShell console window immediately
try {
    if (-not ([System.Management.Automation.PSTypeName]'WinUtil.LauncherWinUtil').Type) {
        Add-Type -Name LauncherWinUtil -Namespace WinUtil -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("gdi32.dll")]
public static extern System.IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int cx, int cy);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int SetWindowRgn(System.IntPtr hWnd, System.IntPtr hRgn, bool bRedraw);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ReleaseCapture();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr SendMessage(System.IntPtr hWnd, int Msg, System.IntPtr wParam, System.IntPtr lParam);
"@ -ErrorAction SilentlyContinue
    }
    $ch = [WinUtil.LauncherWinUtil]::GetConsoleWindow()
    if ($ch -and $ch -ne [System.IntPtr]::Zero) {
        [void][WinUtil.LauncherWinUtil]::ShowWindow($ch, 0)
    }
} catch {}

function Start-LauncherApp {
    $repoBaseUrl = "https://raw.githubusercontent.com/phwyverysad/powershell/main"
    $cacheDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, "PowerShellLauncher")
    $binDir   = [System.IO.Path]::Combine($cacheDir, "bin")

    if (-not [System.IO.Directory]::Exists($binDir)) {
        [void][System.IO.Directory]::CreateDirectory($binDir)
    }

    $localBin = $null
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "bin\Microsoft.Web.WebView2.Wpf.dll"))) {
        $localBin = (Join-Path $PSScriptRoot "bin")
    }
    if (-not $localBin -and (Test-Path ".\bin\Microsoft.Web.WebView2.Wpf.dll")) {
        $localBin = (Resolve-Path ".\bin").Path
    }

    $activeBinDir = if ($localBin) { $localBin } else { $binDir }

    $dlls = @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.Wpf.dll", "WebView2Loader.dll")
    foreach ($dll in $dlls) {
        $dest = Join-Path $activeBinDir $dll
        if (-not [System.IO.File]::Exists($dest)) {
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                $wc.DownloadFile("$repoBaseUrl/bin/$dll", $dest)
            } catch {}
        }
    }

    $htmlContent = $null
    $localHtml = $null
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "clean_utility_launcher_gui.html"))) {
        $localHtml = (Join-Path $PSScriptRoot "clean_utility_launcher_gui.html")
    }
    if (-not $localHtml -and (Test-Path ".\clean_utility_launcher_gui.html")) {
        $localHtml = (Resolve-Path ".\clean_utility_launcher_gui.html").Path
    }

    if ($localHtml) {
        $htmlContent = [System.IO.File]::ReadAllText($localHtml, [System.Text.Encoding]::UTF8)
    } else {
        $cacheHtml = Join-Path $cacheDir "clean_utility_launcher_gui.html"
        if (-not [System.IO.File]::Exists($cacheHtml)) {
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                $wc.DownloadFile("$repoBaseUrl/clean_utility_launcher_gui.html", $cacheHtml)
            } catch {}
        }
        if ([System.IO.File]::Exists($cacheHtml)) {
            $htmlContent = [System.IO.File]::ReadAllText($cacheHtml, [System.Text.Encoding]::UTF8)
        }
    }

    if (-not $htmlContent) {
        $htmlContent = "<html><body style='background:#fbfbfb;color:#0f172a;font-family:sans-serif;'><div style='padding:24px;'>Cannot load GUI template. Check internet connection.</div></body></html>"
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Web
    [System.Reflection.Assembly]::LoadFrom((Join-Path $activeBinDir "Microsoft.Web.WebView2.Core.dll")) | Out-Null
    [System.Reflection.Assembly]::LoadFrom((Join-Path $activeBinDir "Microsoft.Web.WebView2.Wpf.dll")) | Out-Null

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

    # Apply WindowChrome to strip any black OS borders
    $chrome = New-Object System.Windows.Shell.WindowChrome
    $chrome.CaptionHeight = 0
    $chrome.ResizeBorderThickness = New-Object System.Windows.Thickness(0)
    $chrome.GlassFrameThickness = New-Object System.Windows.Thickness(0)
    $chrome.CornerRadius = New-Object System.Windows.CornerRadius(0)
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($window, $chrome)

    $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
    $window.Content = $wv

    $script:activeProcess = $null

    # Helper function to apply or clear rounded corners
    function script:Update-WindowRegion {
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
            if ($hwnd -ne [System.IntPtr]::Zero) {
                if ($window.WindowState -eq "Maximized") {
                    [WinUtil.LauncherWinUtil]::SetWindowRgn($hwnd, [System.IntPtr]::Zero, $true)
                } else {
                    $w = [int]$window.ActualWidth
                    $h = [int]$window.ActualHeight
                    if ($w -gt 50 -and $h -gt 50) {
                        $rgn = [WinUtil.LauncherWinUtil]::CreateRoundRectRgn(0, 0, $w, $h, 24, 24)
                        [WinUtil.LauncherWinUtil]::SetWindowRgn($hwnd, $rgn, $true)
                    }
                }
            }
        } catch {}
    }

    $window.Add_SizeChanged({
        script:Update-WindowRegion
    })

    $wv.Add_CoreWebView2InitializationCompleted({
        param($s, $e)
        if ($e.IsSuccess) {
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
                                if ($window.WindowState -eq "Maximized") {
                                    $window.WindowState = "Normal"
                                } else {
                                    $window.WindowState = "Maximized"
                                }
                            })
                        }
                        "close" {
                            $window.Dispatcher.Invoke([Action]{
                                if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
                                    try { $script:activeProcess.Kill() } catch {}
                                }
                                $window.Close()
                            })
                        }
                        "cancel" {
                            if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
                                try { $script:activeProcess.Kill() } catch {}
                                $script:activeProcess = $null
                            }
                        }
                        "run" {
                            $cmd = $payload.cmd
                            $appName = $payload.appName

                            [System.Threading.ThreadPool]::QueueUserWorkItem({
                                param($state)
                                try {
                                    $safeApp = [System.Web.HttpUtility]::JavaScriptStringEncode($appName)
                                    $window.Dispatcher.Invoke([Action]{
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(15, '');") | Out-Null
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('Starting: $safeApp', false);") | Out-Null
                                    })

                                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                                    $psi.FileName = "powershell.exe"
                                    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
                                    $psi.UseShellExecute = $false
                                    $psi.RedirectStandardOutput = $true
                                    $psi.RedirectStandardError = $true
                                    $psi.CreateNoWindow = $true

                                    $proc = [System.Diagnostics.Process]::Start($psi)
                                    $script:activeProcess = $proc

                                    $window.Dispatcher.Invoke([Action]{
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(35, '');") | Out-Null
                                    })

                                    while (-not $proc.HasExited) {
                                        $line = $proc.StandardOutput.ReadLine()
                                        if ($line) {
                                            $clean = $line.Trim()
                                            if ($clean) {
                                                $safe = [System.Web.HttpUtility]::JavaScriptStringEncode($clean)
                                                $window.Dispatcher.Invoke([Action]{
                                                    $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('$safe', false);") | Out-Null
                                                })
                                            }
                                        } else {
                                            [System.Threading.Thread]::Sleep(40)
                                        }
                                    }

                                    $remOut = $proc.StandardOutput.ReadToEnd()
                                    if ($remOut) {
                                        foreach ($l in ($remOut -split "`r?`n")) {
                                            $clean = $l.Trim()
                                            if ($clean) {
                                                $safe = [System.Web.HttpUtility]::JavaScriptStringEncode($clean)
                                                $window.Dispatcher.Invoke([Action]{
                                                    $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('$safe', false);") | Out-Null
                                                })
                                            }
                                        }
                                    }

                                    $errOut = $proc.StandardError.ReadToEnd()
                                    if ($errOut) {
                                        foreach ($l in ($errOut -split "`r?`n")) {
                                            $clean = $l.Trim()
                                            if ($clean) {
                                                $safe = [System.Web.HttpUtility]::JavaScriptStringEncode($clean)
                                                $window.Dispatcher.Invoke([Action]{
                                                    $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('$safe', false);") | Out-Null
                                                })
                                            }
                                        }
                                    }

                                    $exitCode = $proc.ExitCode
                                    $script:activeProcess = $null

                                    $window.Dispatcher.Invoke([Action]{
                                        if ($exitCode -eq 0) {
                                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(true, '');") | Out-Null
                                        } else {
                                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(false, 'Exit Code: $exitCode');") | Out-Null
                                        }
                                    })
                                } catch {
                                    $script:activeProcess = $null
                                    $errText = [System.Web.HttpUtility]::JavaScriptStringEncode($_.Exception.Message)
                                    $window.Dispatcher.Invoke([Action]{
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('Error: $errText', false);") | Out-Null
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(false, 'Failed');") | Out-Null
                                    })
                                }
                            })
                        }
                    }
                } catch {}
            })

            $wv.NavigateToString($htmlContent)
        }
    })

    $window.Add_Loaded({
        [void]$wv.EnsureCoreWebView2Async()
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
            if ($hwnd -ne [System.IntPtr]::Zero) {
                script:Update-WindowRegion
                [void][WinUtil.LauncherWinUtil]::ShowWindow($hwnd, 5)
                [void][WinUtil.LauncherWinUtil]::SetForegroundWindow($hwnd)
            }
            $window.Activate()
        } catch {}
    })

    $window.ShowDialog() | Out-Null
}

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    $t = New-Object System.Threading.Thread([System.Threading.ThreadStart]{ Start-LauncherApp })
    $t.SetApartmentState([System.Threading.ApartmentState]::STA)
    $t.Start()
    $t.Join()
} else {
    Start-LauncherApp
}
