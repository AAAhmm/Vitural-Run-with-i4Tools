@echo off
:: Auto-elevate to administrator (required for i4Tools input automation)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
chcp 65001 >nul 2>&1
title VirtualRun - i4Tools Track Runner
echo.
echo   =====================================
echo     Track Running Virtual Location v2
echo     i4Tools Automation
echo   =====================================
echo.
echo   Setup phase will ask for campus selection.
echo   Then console minimizes - i4Tools stays active.
echo   Close this window from taskbar to stop.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0VirtualRun.ps1" %*
pause
