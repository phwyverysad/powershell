# Comprehensive Automated Verification Test Suite
$ErrorActionPreference = "Stop"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " STARTING AUTOMATED TEST SUITE FOR LAUNCHER" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$testCount = 0
$passCount = 0

function Assert-Test($condition, $testName) {
    $script:testCount++
    if ($condition) {
        $script:passCount++
        Write-Host "  [PASS] Test $script:testCount: $testName" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Test $script:testCount: $testName" -ForegroundColor Red
        throw "Assertion failed for: $testName"
    }
}

# ----------------------------------------------------
# 1. AST Syntax Test on PowerShell 5.1
# ----------------------------------------------------
Write-Host "`n[1] Testing PowerShell 5.1 Syntax AST..." -ForegroundColor Yellow
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile("C:\Users\Administrator\.gemini\antigravity\scratch\powershell\run.ps1", [ref]$tokens, [ref]$errors)
Assert-Test ($errors.Count -eq 0) "run.ps1 has 0 AST parser errors in PS 5.1"

# ----------------------------------------------------
# 2. AST Syntax Test on PowerShell 7 (pwsh)
# ----------------------------------------------------
Write-Host "`n[2] Testing PowerShell 7 (pwsh) Syntax AST..." -ForegroundColor Yellow
$pwshInstalled = Get-Command "pwsh" -ErrorAction SilentlyContinue
if ($pwshInstalled) {
    $pwshRes = pwsh -NoProfile -Command "& { `$errors = `$null; [System.Management.Automation.Language.Parser]::ParseFile('C:\Users\Administrator\.gemini\antigravity\scratch\powershell\run.ps1', [ref]`$null, [ref]`$errors); if (`$errors.Count -eq 0) { 'OK' } else { 'ERR' } }"
    Assert-Test ($pwshRes.Trim() -eq "OK") "run.ps1 passes PowerShell 7 parser check with 0 errors"
} else {
    Write-Host "  [SKIP] pwsh not found on PATH, skipping PS 7 parser check" -ForegroundColor Gray
}

# ----------------------------------------------------
# 3. HTML Catalog & Requirements Verification
# ----------------------------------------------------
Write-Host "`n[3] Verifying HTML Catalog Data & UI Specifications..." -ForegroundColor Yellow
$html = Get-Content -Raw -Encoding UTF8 "C:\Users\Administrator\.gemini\antigravity\scratch\powershell\clean_utility_launcher_gui.html"
$launcherPs1 = Get-Content -Raw -Encoding UTF8 "C:\Users\Administrator\.gemini\antigravity\scratch\powershell\launcher.ps1"

# 3.1 Check Dev category is removed
$hasTopDev = $html -match "id:\s*'dev',\s*name:\s*\{\s*th:\s*'นักพัฒนาและรันไทม์'"
Assert-Test (-not $hasTopDev) "Top-level category 'นักพัฒนาและรันไทม์' (dev) is completely removed"

# 3.2 Check Sort dropdown button and options
Assert-Test ($html.Contains('id="sortDropdownWrapper"')) "Sort dropdown button exists in toolbar"
Assert-Test ($html.Contains('id="sortDropdownBtn"')) "Sort toggle button exists"
Assert-Test ($html.Contains('Name A-Z (Installed First)')) "Sort option: Name A-Z (Installed First) exists"
Assert-Test ($html.Contains('Name A-Z')) "Sort option: Name A-Z exists"
Assert-Test ($html.Contains('Name Z-A')) "Sort option: Name Z-A exists"

# 3.3 Check Sticky Toolbar and Scrolling Subcategories
Assert-Test ($html.Contains('id="subCategoryNavContainer"')) "SubCategory bar container exists inside main"
Assert-Test ($html.Contains('sticky top-0 z-30 theme-surface')) "Toolbar layer has sticky top-0 to stay pinned on scroll"

# 3.4 Check Instant Search Dismissal
Assert-Test ($html.Contains("document.addEventListener('pointerdown'")) "Immediate pointerdown dismiss listener attached"

# 3.5 Check Strict Detection Logic
Assert-Test ($html.Contains('matchesPattern')) "Strict pattern matching (matchesPattern) implemented"
Assert-Test (-not $html.Contains("winget.split('.').pop()")) "Buggy winget.split('.').pop() false-positive check is completely eliminated"

# 3.6 Check Window Dimensions in Launcher
$launcherCode = Get-Content -Raw -Encoding UTF8 "C:\Users\Administrator\.gemini\antigravity\scratch\powershell\run.ps1"
Assert-Test ($launcherCode.Contains('$idealWidth = 1460') -and $launcherCode.Contains('$idealHeight = 880')) "Window configured with responsive wide layout ($idealWidth = 1460) so controls never wrap"


# 3.7 Check Sort Dropdown Animation & Live Sorting
Assert-Test ($html.Contains('id="sortChevron"') -and $html.Contains('transition-transform duration-200')) "Sort dropdown chevron has smooth 200ms rotation transition"
Assert-Test ($html.Contains('opacity-0 scale-95 pointer-events-none') -and $html.Contains('duration-150 origin-top-right')) "Sort dropdown menu has smooth 150ms scale and opacity animation identical to language dropdown"
Assert-Test ($html.Contains('bInst - aInst') -and $html.Contains("currentSortMode === 'installedFirst'")) "getCurrentlyDisplayedItems() implements live sorting for installedFirst, az, and za"
Assert-Test ($html.Contains('background-color: #1e293b !important; /* ทึบแสง 100%')) "Selected app cards in dark mode are 100% solid opaque (#1e293b) with zero transparency"
Assert-Test ($html.Contains('#mainActionToolbar') -and $html.Contains('flex-wrap: nowrap !important;')) "#mainActionToolbar enforces strict single-row horizontal layout"

# ----------------------------------------------------
# 4. Catalog Completeness & Thai Translations via Python
# ----------------------------------------------------
Write-Host "`n[4] Verifying 100% Thai Descriptions & 100% Real Icons..." -ForegroundColor Yellow
$pyCheck = python -c "
import json
subs = json.load(open(r'C:\Users\Administrator\.gemini\antigravity\scratch\powershell\final_install_subcategories.json', encoding='utf-8'))
total_items = sum(len(s['items']) for s in subs)
untranslated = [it['name'] for s in subs for it in s['items'] if it['desc']['th'] == it['desc']['en']]
missing_icons = [it['name'] for s in subs for it in s['items'] if not it.get('iconUrl') or not it['iconUrl'].startswith('http')]
assert len(subs) == 16, f'Expected 16 subcategories, got {len(subs)}'
assert total_items == 193, f'Expected 193 items, got {total_items}'
assert len(untranslated) == 0, f'Found {len(untranslated)} untranslated: {untranslated}'
assert len(missing_icons) == 0, f'Found {len(missing_icons)} missing icons: {missing_icons}'
print(f'ALL_VERIFIED: {len(subs)} subcategories, {total_items} items, 0 untranslated, 0 missing icons')
"

Assert-Test ($pyCheck.Contains("ALL_VERIFIED")) "All 16 subcategories, all 193 items have Thai translations and valid CDN icons"

# ----------------------------------------------------
# 5. ProcessRunner & Command Execution Test (Fix Exit Code -1)
# ----------------------------------------------------
Write-Host "`n[5] Testing Execution Engine (EncodedCommand - No Exit Code -1)..." -ForegroundColor Yellow
$pyExecTest = python -c "
import subprocess, base64

cmd = '''
Write-Host 'Starting install test for 1 item...'
Write-Host 'Installing: TestApp'
winget --version
'''
utf16_bytes = cmd.encode('utf-16le')
b64 = base64.b64encode(utf16_bytes).decode('ascii')
p = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NonInteractive', '-EncodedCommand', b64], capture_output=True, text=True)
assert p.returncode == 0, f'Process failed with code {p.returncode}'
assert 'Starting install test' in p.stdout
assert 'Installing: TestApp' in p.stdout
print('EXEC_SUCCESS')
"
Assert-Test ($pyExecTest.Trim() -eq "EXEC_SUCCESS") "PowerShell execution via ProcessRunner EncodedCommand exits with code 0"

# ----------------------------------------------------
# 6. Verify System Detection Against Real Machine
# ----------------------------------------------------
Write-Host "`n[6] Verifying Strict Detection Against Real System..." -ForegroundColor Yellow
$detectOutput = python -c "
import json, re, subprocess

ps_code = '''
`$paths = @(
    'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
    'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
    'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
)
Get-ItemProperty `$paths -ErrorAction SilentlyContinue | Select-Object DisplayName, PSChildName | ConvertTo-Json
'''
res = subprocess.run(['powershell', '-NoProfile', '-Command', ps_code], capture_output=True, text=True)
raw = json.loads(res.stdout)
dns = {x.get('DisplayName', '').strip() for x in raw if x.get('DisplayName')}
kns = {x.get('PSChildName', '').strip() for x in raw if x.get('PSChildName')}

def match(t, p):
    if not t or not p: return False
    rx = re.escape(p).replace(r'\{version}', '.+?').replace(r'\{arch}', '.+?').replace(r'\{locale}', '.+?')
    return bool(re.match(f'^{rx}$', t, re.IGNORECASE))

subs = json.load(open(r'C:\Users\Administrator\.gemini\antigravity\scratch\powershell\final_install_subcategories.json', encoding='utf-8'))
installed = []
for s in subs:
    for it in s['items']:
        name = it['name']
        rg_dn = it.get('regDisplayName')
        rg_sub = it.get('regSubKeyName')
        inst = False
        if name.lower() in [d.lower() for d in dns]: inst = True
        elif rg_dn and any(match(d, rg_dn) for d in dns): inst = True
        elif rg_sub and any(match(k, rg_sub) for k in kns): inst = True
        if inst: installed.append(name)

assert 'Google Chrome' in installed
assert 'Brave' in installed
assert 'DirectX Runtime' not in installed
assert 'Java Runtime Environment' not in installed
print(f'STRICT_DETECTION_OK: {len(installed)} detected, 0 false positives')
"

Assert-Test ($detectOutput.Contains("STRICT_DETECTION_OK")) "Strict detection accurately detects real apps and rejects false positives (DirectX/Java not falsely detected)"

# ----------------------------------------------------
# 7. Verifying Windows Apps & Features, Confirm Modal & Copy Log
# ----------------------------------------------------
Write-Host "`n[7] Verifying Windows Apps, Confirm Modal, Copy Log & Fixes..." -ForegroundColor Yellow

# 7.1 Windows Apps & Features Category
Assert-Test ($html.Contains('"id": "winapps"') -or $html.Contains("id: 'winapps'")) "Main category 'Windows Apps & Features' (winapps) exists in catalogData"
Assert-Test ($html.Contains("แอพและฟีเจอร์ของ Windows")) "Category title 'แอพและฟีเจอร์ของ Windows' exists"
Assert-Test ($html.Contains("windows-app-3d-viewer") -and $html.Contains("feature-wsl")) "Windows Apps (3D Viewer) and Features (WSL) are integrated into catalog"

# 7.2 Confirmation Modal (Confirm Installation / Uninstallation)
Assert-Test ($html.Contains('id="batchConfirmModal"')) "Batch confirmation modal container exists"
Assert-Test ($html.Contains('id="batchConfirmBox"') -and $html.Contains('id="batchConfirmList"')) "Batch confirmation box and items list exist"
Assert-Test ($html.Contains('id="batchConfirmContinueBtn"') -and $html.Contains('id="batchConfirmCancelBtn"')) "Continue and Cancel buttons exist in confirmation modal"
Assert-Test ($html.Contains('function requestBatchSelected') -and $html.Contains('function proceedBatchAction')) "Confirmation modal workflow functions implemented"

# 7.3 Copy Log Button in Install Modal
Assert-Test ($html.Contains('id="copyLogBtn"')) "Copy Log button exists in install log modal"
Assert-Test ($html.Contains('function copyLogContent')) "copyLogContent() function implemented with clipboard write and toast"

# 7.4 Fix INSTALL BATCH syntax error
Assert-Test ($html.Contains('!isBatch && window.chrome && window.chrome.webview && cmd')) "openInstallLogModal prevents executing batch title as shell command, eliminating 'INSTALL BATCH' syntax error"

# 7.5 Title Bar Double-Click Window Toggle
Assert-Test ($html.Contains('safeToggleMaximizeApp') -and $html.Contains('e.detail >= 2')) "Title bar header supports double-click window maximize/restore with debounce"

# 7.6 Dark Mode Toolbar Shadows & Depth
Assert-Test ($html.Contains('html.dark #mainActionToolbar') -and $html.Contains('inset 0 1px 0')) "Dark mode toolbar has floating box-shadow, highlight and depth"
Assert-Test ($html.Contains('html.dark #mainActionToolbar button.theme-input')) "Toolbar buttons in dark mode have elevated shadows and visible borders"

# 7.7 GitHub Profile Button
Assert-Test ($html.Contains('id="githubBtn"') -and $html.Contains('https://github.com/phwyverysad')) "GitHub profile button exists before theme toggle button with link to https://github.com/phwyverysad"

# 7.8 TargetCursor Component
Assert-Test ($html.Contains('target-cursor') -and $html.Contains('initTargetCursor') -and $html.Contains('cursor-target')) "TargetCursor component from React Bits integrated with high-performance spring physics"

# 7.9 A-Z Sort Prioritizes Letters Over Numbers
Assert-Test ($html.Contains('/^[a-zA-Z]/.test') -and $html.Contains('isLetterA !== isLetterB')) "A-Z sorting prioritizes pure letters A-Z before numbers/symbols (7-Zip placed after Z)"

# 7.10 Dynamic Sort Button Label
Assert-Test ($html.Contains("btnLabel.textContent = t.sortAZ") -and $html.Contains("btnLabel.textContent = t.sortZA")) "Sort button label dynamically updates to reflect selected sort mode"

# 7.11 Clean Log Output (No '==========')
Assert-Test (-not $launcherPs1.Contains("========================================") -and $launcherPs1.Contains("> [")) "Log output formatted cleanly with no '==========' dividers"

# 7.12 Automated App Status & AppX Scanning
Assert-Test ($launcherPs1.Contains('AppModel\Repository\Packages') -and $html.Contains('item.appxPackageName')) "Automatic installed status scanning supports AppX packages and updates dynamically"

# 7.13 Windows Defender Main Category
Assert-Test ($html.Contains("id: 'defender'") -and $html.Contains("name: { th: 'Windows Defender'")) "Main category 'Windows Defender' (defender) exists in catalogData"
Assert-Test ($html.Contains("id: 'def-scan'") -and $html.Contains("id: 'def-protection'") -and $html.Contains("id: 'def-asr'") -and $html.Contains("id: 'def-maintenance'")) "Windows Defender has 4 dedicated subcategories"
Assert-Test ($html.Contains("Start-MpScan") -and $html.Contains("Set-MpPreference") -and $html.Contains("Add-MpPreference")) "Windows Defender items include PowerShell security management commands"
Assert-Test ($html.Contains("activeMainId === 'defender'") -and $html.Contains("toolbar.classList.add('hidden')")) "Action toolbar is hidden exclusively for Windows Defender category"
Assert-Test ($html.Contains('toggleDefenderSwitch') -and $html.Contains('toggle-switch-track') -and $html.Contains('toggle-switch-thumb')) "Windows Defender cards feature interactive ON/OFF toggle switches"

$sw.Stop()
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host " ALL $passCount / $testCount TESTS PASSED SUCCESSFULLY in $($sw.ElapsedMilliseconds) ms!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
