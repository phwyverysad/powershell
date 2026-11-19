<#
    .SYNOPSIS
    All-in-One Utility Launcher (Transparent Modern Desktop GUI)
    Run directly via:
    irm https://raw.githubusercontent.com/phwyverysad/powershell/main/launcher.ps1 | iex
#>

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]3072 -bor [System.Net.SecurityProtocolType]768 -bor [System.Net.SecurityProtocolType]192
} catch {}

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# ซ่อนหน้าต่าง PowerShell Console ทันทีที่เริ่มต้นทำงาน
try {
    if (-not ([System.Management.Automation.PSTypeName]'WinUtil.LauncherWinUtil').Type) {
        Add-Type -Name LauncherWinUtil -Namespace WinUtil -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
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

    # ตรวจสอบหาไฟล์ Binaries ในโฟลเดอร์ปัจจุบันก่อน ถ้าไม่มีให้ใช้ใน Cache
    $localBin = $null
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "bin\Microsoft.Web.WebView2.Wpf.dll"))) {
        $localBin = (Join-Path $PSScriptRoot "bin")
    }
    if (-not $localBin -and (Test-Path ".\bin\Microsoft.Web.WebView2.Wpf.dll")) {
        $localBin = (Resolve-Path ".\bin").Path
    }

    $activeBinDir = if ($localBin) { $localBin } else { $binDir }

    # รายการ DLLs ของ WebView2 ที่จำเป็น
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

    # ค้นหาไฟล์ HTML
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
        $htmlContent = "<html><body style='background:transparent;color:white;font-family:sans-serif;'><div style='background:#1e1f22;padding:24px;border-radius:16px;'>Cannot load GUI template. Check internet connection.</div></body></html>"
    }

    # โหลดไลบรารี WPF และ WebView2
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Web
    [System.Reflection.Assembly]::LoadFrom((Join-Path $activeBinDir "Microsoft.Web.WebView2.Core.dll")) | Out-Null
    [System.Reflection.Assembly]::LoadFrom((Join-Path $activeBinDir "Microsoft.Web.WebView2.Wpf.dll")) | Out-Null

    $env:WEBVIEW2_USER_DATA_FOLDER = Join-Path $cacheDir "WebView2Data"

    # สร้างหน้าต่าง WPF แบบโปร่งใสสมบูรณ์ (ไม่มีกรอบเดิมของ OS)
    $window = New-Object System.Windows.Window
    $window.Title = "All-in-One Launcher"
    $window.Width = 1180
    $window.Height = 740
    $window.WindowStyle = "None"
    $window.AllowsTransparency = $true
    $window.Background = [System.Windows.Media.Brushes]::Transparent
    $window.WindowStartupLocation = "CenterScreen"
    $window.ResizeMode = "CanResize"

    # สร้าง Control WebView2 ที่ตั้งค่าพื้นหลังเป็น Transparent
    $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
    $wv.DefaultBackgroundColor = [System.Drawing.Color]::Transparent
    $window.Content = $wv

    $script:activeProcess = $null

    # ผูกคำสั่งจาก JavaScript (WebMessage) สู่ระบบ Windows
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
                                try { $window.DragMove() } catch {}
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
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(15, 'กำลังเตรียมสภาพแวดล้อม...');") | Out-Null
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('เริ่มดำเนินการ: $safeApp', false);") | Out-Null
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
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setProgress(35, 'กำลังรันคำสั่ง...');") | Out-Null
                                    })

                                    # สตรีมข้อความ Output แบบเรียลไทม์
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

                                    # อ่านข้อความที่เหลือทั้งหมด
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
                                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(true, 'ดำเนินการติดตั้งสำเร็จ');") | Out-Null
                                        } else {
                                            $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(false, 'คำสั่งเสร็จสิ้นด้วย Exit Code: $exitCode');") | Out-Null
                                        }
                                    })
                                } catch {
                                    $script:activeProcess = $null
                                    $errText = [System.Web.HttpUtility]::JavaScriptStringEncode($_.Exception.Message)
                                    $window.Dispatcher.Invoke([Action]{
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.appendLog('Error: $errText', false);") | Out-Null
                                        $wv.ExecuteScriptAsync("window.desktopBridge && window.desktopBridge.setComplete(false, 'เกิดข้อผิดพลาดในการประมวลผล');") | Out-Null
                                    })
                                }
                            })
                        }
                    }
                } catch {}
            })

            # นำทางเข้าสู่หน้าเว็บ UI
            $wv.NavigateToString($htmlContent)
        }
    })

    $window.Add_Loaded({
        [void]$wv.EnsureCoreWebView2Async()
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
            if ($hwnd -ne [System.IntPtr]::Zero) {
                [void][WinUtil.LauncherWinUtil]::SetForegroundWindow($hwnd)
            }
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
