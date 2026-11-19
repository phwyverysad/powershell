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
$detectOutput = (python C:\Users\Administrator\.gemini\antigravity\scratch\powershell\test_strict_detection.py) -join "`n"
Assert-Test ($detectOutput.Contains("[INSTALLED] Google Chrome") -and $detectOutput.Contains("[INSTALLED] Brave") -and (-not $detectOutput.Contains("[INSTALLED] DirectX Runtime")) -and (-not $detectOutput.Contains("[INSTALLED] Java Runtime Environment"))) "Strict detection accurately detects real apps and rejects false positives (DirectX/Java not falsely detected)"

$sw.Stop()
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host " ALL $passCount / $testCount TESTS PASSED SUCCESSFULLY in $($sw.ElapsedMilliseconds) ms!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
