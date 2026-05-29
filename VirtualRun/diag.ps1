# Diagnostic: test input against i4Tools step by step
Add-Type -Path (Join-Path $PSScriptRoot "I4Win.cs")

$p = Get-Process i4Tools -ErrorAction SilentlyContinue
if (-not $p) { Write-Host "i4Tools not running!" -ForegroundColor Red; exit 1 }
$hw = [I4W]::FindI4ToolsWindow()
$r = New-Object I4R; [I4W]::GetWindowRect($hw, [ref]$r)

Write-Host "i4Tools: $hw at ($($r.L),$($r.T)) size $($r.R-$r.L)x$($r.B-$r.T)" -ForegroundColor Cyan

# Step 1: clipboard
Write-Host "`n[1] Testing clipboard..." -ForegroundColor Yellow
$ok = [I4W]::SetClip("28.654321")
Write-Host "    SetClip: $(if($ok){'OK'}else{'FAIL'})"
# Verify by reading clipboard via PowerShell
$clip = Get-Clipboard -ErrorAction SilentlyContinue
Write-Host "    Verify: get-clipboard = '$clip'"

# Step 2: click test (no i4Tools needed - just move cursor somewhere visible)
Write-Host "`n[2] Testing mouse click (watch the cursor)..." -ForegroundColor Yellow
Write-Host "    Moving cursor to ($($r.L+200), $($r.T+200)) and clicking..." -ForegroundColor Cyan
[I4W]::MoveAndClick($r.L+200, $r.T+200)
Write-Host "    Done. Cursor should have moved and clicked."

# Step 3: bring i4Tools to front
Write-Host "`n[3] Bringing i4Tools to foreground..." -ForegroundColor Yellow
[I4W]::ForceSetForeground($hw) | Out-Null
Start-Sleep -Milliseconds 500
$fg = [I4W]::GetForegroundWindow()
Write-Host "    Foreground = $fg (i4Tools = $hw) -> $(if($fg -eq $hw){'OK'}else{'FAIL - window may not accept input'})"

# Step 4: send keyboard while i4Tools is focused
Write-Host "`n[4] Testing keyboard..." -ForegroundColor Yellow
Write-Host "    Move cursor manually to i4Tools input field, then press Enter..."
Read-Host
Write-Host "    Sending Ctrl+A to test..."
[I4W]::SendCtrlA()
Write-Host "    Done. Did the field content get selected?"

Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host "If step 4 didn't work, i4Tools may require admin-level input."
Write-Host "Try: right-click VirtualRun.bat -> Run as Administrator"
Read-Host "Press Enter"
