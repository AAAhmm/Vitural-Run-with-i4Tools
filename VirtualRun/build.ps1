<#
.SYNOPSIS
    Build VirtualRun.exe - C# launcher with embedded PowerShell script
.DESCRIPTION
    Compiles Launcher.cs + VirtualRun.ps1 into a single EXE that:
    - Self-elevates to administrator (UAC prompt)
    - Extracts and runs the PowerShell script
    - No external dependencies at runtime
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Ps1File    = Join-Path $ScriptDir "VirtualRun.ps1"
$CsFile     = Join-Path $ScriptDir "Launcher.cs"
$Manifest   = Join-Path $ScriptDir "app.manifest"
$OutputFile = Join-Path $ScriptDir "VirtualRun.exe"
$CscExe     = "C:\WINDOWS\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

Write-Host "===== Building VirtualRun.exe =====" -ForegroundColor Cyan

foreach ($f in @($Ps1File, $CsFile, $Manifest)) {
    if (-not (Test-Path $f)) {
        Write-Host "  ERROR: Missing $f" -ForegroundColor Red
        exit 1
    }
}
if (-not (Test-Path $CscExe)) {
    # Fallback to 32-bit csc
    $CscExe = "C:\WINDOWS\Microsoft.NET\Framework\v4.0.30319\csc.exe"
    if (-not (Test-Path $CscExe)) {
        Write-Host "  ERROR: csc.exe not found" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  Source: $Ps1File" -ForegroundColor DarkGray
Write-Host "  Output: $OutputFile" -ForegroundColor DarkGray

if (Test-Path $OutputFile) {
    Write-Host "  Removing old EXE..." -ForegroundColor Yellow
    Remove-Item $OutputFile -Force
}

Write-Host "  Compiling..." -ForegroundColor Yellow

$result = & $CscExe /nologo /target:exe /out:$OutputFile /win32manifest:$Manifest /resource:$Ps1File,VirtualRun.VirtualRun.ps1 /reference:System.dll /reference:System.Security.dll $CsFile 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  COMPILE ERROR:" -ForegroundColor Red
    Write-Host $result
    exit 1
}

if (Test-Path $OutputFile) {
    $size = (Get-Item $OutputFile).Length
    Write-Host "  Done: $OutputFile ($([Math]::Round($size/1KB,1)) KB)" -ForegroundColor Green
    Write-Host ""
    Write-Host "VirtualRun.exe is standalone. Double-click to launch." -ForegroundColor Cyan
    Write-Host "Calibration saves to data\ folder alongside the EXE."
} else {
    Write-Host "  ERROR: EXE not created" -ForegroundColor Red
    exit 1
}
