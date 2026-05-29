<#
.SYNOPSIS
    i4Tools Virtual Location - Track Running Generator v3.0
.DESCRIPTION
    Self-contained. No external files needed at runtime.
    Generates realistic clockwise running paths around athletic tracks.
#>

param([switch]$Calibrate, [switch]$Test)

# Ensure UTF-8 console output for Chinese characters
chcp 65001 >$null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Determine base directory (works in both .ps1 and .exe modes)
$ScriptDir = if ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    [System.IO.Path]::GetDirectoryName([System.Reflection.Assembly]::GetEntryAssembly().Location)
}
$DataDir   = Join-Path $ScriptDir "data"
$CalFile   = Join-Path $DataDir "VirtualRun.cal.json"

# Ensure data directory exists
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }

# Compile the C# Windows API wrapper (embedded)
$CsCode = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class I4W
{
    // Window
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out I4R r);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder t, int max);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    // Input - legacy APIs (NOT blocked by UIPI, unlike SendInput)
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out I4P p);
    [DllImport("user32.dll")] static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k);

    // Clipboard
    [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr h);
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint f, IntPtr m);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint f, int b);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr m);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr m);

    // Constants
    public const int SW_MINIMIZE = 6, SW_RESTORE = 9;
    public const int VK_CTRL = 0x11, VK_A = 0x41, VK_V = 0x56, VK_ESC = 0x1B, VK_RETURN = 0x0D, VK_MENU = 0x12;
    const uint MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004;
    const uint MOUSEEVENTF_MOVE = 0x0001;
    const uint KEYEVENTF_KEYUP = 0x0002;
    const uint GMEM_MOVEABLE = 0x0002, CF_UNICODETEXT = 13;

    public static void MoveAndClick(int x, int y)
    {
        SetCursorPos(x, y);
        Thread.Sleep(15);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(30);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(40);
    }

    static void PressKey(int vk)
    {
        byte scan = (byte)MapVirtualKey((uint)vk, 0);
        keybd_event((byte)vk, scan, 0, UIntPtr.Zero);
        Thread.Sleep(20);
        keybd_event((byte)vk, scan, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(20);
    }

    public static void SendCtrlA()
    {
        byte ctrlScan = (byte)MapVirtualKey(VK_CTRL, 0);
        byte aScan = (byte)MapVirtualKey(VK_A, 0);
        keybd_event((byte)VK_CTRL, ctrlScan, 0, UIntPtr.Zero);
        Thread.Sleep(10);
        keybd_event((byte)VK_A, aScan, 0, UIntPtr.Zero);
        Thread.Sleep(10);
        keybd_event((byte)VK_A, aScan, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(10);
        keybd_event((byte)VK_CTRL, ctrlScan, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(30);
    }

    public static void SendCtrlV()
    {
        byte ctrlScan = (byte)MapVirtualKey(VK_CTRL, 0);
        byte vScan = (byte)MapVirtualKey(VK_V, 0);
        keybd_event((byte)VK_CTRL, ctrlScan, 0, UIntPtr.Zero);
        Thread.Sleep(10);
        keybd_event((byte)VK_V, vScan, 0, UIntPtr.Zero);
        Thread.Sleep(10);
        keybd_event((byte)VK_V, vScan, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(10);
        keybd_event((byte)VK_CTRL, ctrlScan, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(30);
    }

    public static void ClickSelectPaste(int x, int y)
    {
        MoveAndClick(x, y);
        Thread.Sleep(150);
        SendCtrlA();
        Thread.Sleep(80);
        SendCtrlV();
        Thread.Sleep(100);
    }

    public static bool SetClip(string text)
    {
        IntPtr hMem = IntPtr.Zero;
        try
        {
            if (!OpenClipboard(IntPtr.Zero)) return false;
            EmptyClipboard();
            byte[] bytes = System.Text.Encoding.Unicode.GetBytes(text + "\0");
            hMem = GlobalAlloc(GMEM_MOVEABLE, bytes.Length);
            if (hMem == IntPtr.Zero) { CloseClipboard(); return false; }
            IntPtr p = GlobalLock(hMem);
            Marshal.Copy(bytes, 0, p, bytes.Length);
            GlobalUnlock(hMem);
            SetClipboardData(CF_UNICODETEXT, hMem);
            CloseClipboard();
            return true;
        }
        catch { try { CloseClipboard(); } catch { } return false; }
    }

    public static void ForceSetForeground(IntPtr h)
    {
        byte altScan = (byte)MapVirtualKey(VK_MENU, 0);
        keybd_event((byte)VK_MENU, altScan, 0, UIntPtr.Zero);
        Thread.Sleep(20);
        SetForegroundWindow(h);
        Thread.Sleep(20);
        keybd_event((byte)VK_MENU, altScan, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(100);
    }

    public static IntPtr WaitForPopup(IntPtr mainHwnd, int timeoutMs = 8000)
    {
        uint i4Pid = 0;
        GetWindowThreadProcessId(mainHwnd, out i4Pid);

        var before = new System.Collections.Generic.HashSet<IntPtr>();
        EnumWindows(delegate(IntPtr w, IntPtr lp)
        {
            if (IsWindowVisible(w)) before.Add(w);
            return true;
        }, IntPtr.Zero);

        int elapsed = 0;
        while (elapsed < timeoutMs)
        {
            IntPtr found = IntPtr.Zero;
            EnumWindows(delegate(IntPtr w, IntPtr lp)
            {
                if (IsWindowVisible(w) && !before.Contains(w))
                {
                    uint pid = 0;
                    GetWindowThreadProcessId(w, out pid);
                    if (pid == i4Pid)
                    {
                        I4R r;
                        if (GetWindowRect(w, out r))
                        {
                            int ww = r.R - r.L, wh = r.B - r.T;
                            if (ww > 100 && wh > 60 && ww < 800 && wh < 600)
                            {
                                found = w;
                                return false;
                            }
                        }
                    }
                }
                return true;
            }, IntPtr.Zero);

            if (found != IntPtr.Zero) return found;

            Thread.Sleep(150);
            elapsed += 150;
        }
        return IntPtr.Zero;
    }

    public static IntPtr FindI4ToolsWindow()
    {
        IntPtr h = FindWindow(null, "爱思助手");
        if (h != IntPtr.Zero && IsWindowVisible(h))
        {
            I4R r;
            GetWindowRect(h, out r);
            if (r.R - r.L > 200 && r.B - r.T > 200)
                return h;
        }

        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr w, IntPtr lp)
        {
            var sb = new System.Text.StringBuilder(256);
            GetWindowText(w, sb, 256);
            string title = sb.ToString();
            if (title.Contains("爱思助手") || title.Contains("i4Tools"))
            {
                I4R r;
                GetWindowRect(w, out r);
                int ww = r.R - r.L, wh = r.B - r.T;
                if (IsWindowVisible(w) && ww > 200 && wh > 200)
                {
                    found = w;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);

        return found;
    }
}

public struct I4R { public int L, T, R, B; }
public struct I4P { public int X, Y; }
'@
Add-Type -TypeDefinition $CsCode

# ============================================================
# CONFIGURATION
# ============================================================

$CampusConfig = @{
    "1" = @{
        Name    = "城南书院校区"
        Address = "长沙市天心区书院路356号"
        # Track corners (clockwise: BR→TR→TL→BL) + curve apexes
        BR_Lat = 28.18051835; BR_Lng = 112.97948421  # 右下
        TR_Lat = 28.18118303; TR_Lng = 112.98013099  # 右上
        TL_Lat = 28.18143377; TL_Lng = 112.97967734  # 左上
        BL_Lat = 28.18071736; BL_Lng = 112.97912488  # 左下
        TV_Lat = 28.18144969; TV_Lng = 112.97998277  # 上顶点 (top curve apex)
        BV_Lat = 28.18051039; BV_Lng = 112.97919226  # 下顶点 (bottom curve apex)
    }
    "2" = @{
        Name    = "东方红校区"
        Address = "长沙市岳麓区枫林三路1015号"
        BR_Lat = 28.19838742; BR_Lng = 112.87333594  # 右下
        TR_Lat = 28.19942604; TR_Lng = 112.87306644  # 右上
        TL_Lat = 28.19932258; TL_Lng = 112.87240619  # 左上
        BL_Lat = 28.19812478; BL_Lng = 112.87270263  # 左下
        TV_Lat = 28.19955736; TV_Lng = 112.87277450  # 上顶点
        BV_Lat = 28.19811682; BV_Lng = 112.87316975  # 下顶点
    }
}

$PointsPerLap  = 80
$PaceSecPerKm  = 180     # 3:00/km
$WobbleStdDev  = 0.6     # lateral deviation (meters)
$WobbleSmooth  = 0.89    # persistence: 0=random, 1=linear (0.89 ≈ 6pt half-life)
$PaceVarPct    = 0.3     # pace micro-variation percent

# ============================================================
# HELPER FUNCTIONS
# ============================================================

function Get-Normal {
    $u1 = Get-Random -Min 0.0001 -Max 1.0
    $u2 = Get-Random -Min 0.0001 -Max 1.0
    return [Math]::Sqrt(-2 * [Math]::Log($u1)) * [Math]::Sin(2 * [Math]::PI * $u2)
}

function Get-Wobble($n, $sd, $sm) {
    # Single AR(1) wobble tuned for visible natural weaving.
    # With smooth=0.89 half-life ≈ 6 points (≈5.5s), a 20pt straight
    # sees 3-4 direction changes — looks like a real runner adjusting
    # lateral position, not a mechanical straight line.
    $w = New-Object double[] $n
    $w[0] = (Get-Normal) * $sd * 0.2
    for ($i = 1; $i -lt $n; $i++) {
        $innov = (Get-Normal) * $sd * [Math]::Sqrt(1 - $sm * $sm)
        $w[$i] = $sm * $w[$i-1] + $innov
        $lim = 2.5 * $sd
        if ($w[$i] -gt $lim)  { $w[$i] = $lim }
        if ($w[$i] -lt -$lim) { $w[$i] = -$lim }
    }
    return $w
}

function Get-Path($cam, $n, $wob, $noShuffle) {
    # Build path from 6 calibrated track points.
    # Clockwise: BR→TR (right straight) → TR→上顶点→TL (top arc) →
    #            TL→BL (left straight) → BL→下顶点→BR (bottom arc).
    # $noShuffle: skip random starting point (for multi-lap continuation)
    $br = @{Lat=$cam.BR_Lat; Lng=$cam.BR_Lng}
    $tr = @{Lat=$cam.TR_Lat; Lng=$cam.TR_Lng}
    $tl = @{Lat=$cam.TL_Lat; Lng=$cam.TL_Lng}
    $bl = @{Lat=$cam.BL_Lat; Lng=$cam.BL_Lng}
    $tv = @{Lat=$cam.TV_Lat; Lng=$cam.TV_Lng}  # 上顶点
    $bv = @{Lat=$cam.BV_Lat; Lng=$cam.BV_Lng}  # 下顶点

    $avgLat = ($br.Lat + $tr.Lat + $tl.Lat + $bl.Lat) / 4.0
    $cos    = [Math]::Cos($avgLat * [Math]::PI / 180.0)
    $mdLat  = 111320.0
    $mdLng  = 111320.0 * $cos

    # Convert lat/lng → meters relative to BR
    function ToM($p) {
        @{ X = ($p.Lng - $br.Lng) * $mdLng
           Y = ($p.Lat - $br.Lat) * $mdLat }
    }
    $brM = @{X=0.0; Y=0.0}
    $trM = ToM $tr; $tlM = ToM $tl; $blM = ToM $bl
    $tvM = ToM $tv; $bvM = ToM $bv

    # --- Fit circle through 3 points, return center, R, angles ---
    function FitArc($a, $v, $c) {
        # a=start, v=vertex(apex), c=end  (in meters)
        $ax=$a.X; $ay=$a.Y; $vx=$v.X; $vy=$v.Y; $cx=$c.X; $cy=$c.Y
        $d = 2*($ax*($vy-$cy) + $vx*($cy-$ay) + $cx*($ay-$vy))
        if ([Math]::Abs($d) -lt 0.001) { $d = 0.001 }
        $ax2=$ax*$ax+$ay*$ay; $vx2=$vx*$vx+$vy*$vy; $cx2=$cx*$cx+$cy*$cy
        $ux = ($ax2*($vy-$cy) + $vx2*($cy-$ay) + $cx2*($ay-$vy)) / $d
        $uy = ($ax2*($cx-$vx) + $vx2*($ax-$cx) + $cx2*($vx-$ax)) / $d
        $r  = [Math]::Sqrt(($ax-$ux)*($ax-$ux) + ($ay-$uy)*($ay-$uy))

        $aAng = [Math]::Atan2($ay-$uy, $ax-$ux)
        $vAng = [Math]::Atan2($vy-$uy, $vx-$ux)
        $cAng = [Math]::Atan2($cy-$uy, $cx-$ux)

        # Sweep from a→c that passes through v
        $cw  = $cAng - $aAng
        if ($cw -gt 0) { $cw -= 2*[Math]::PI }
        $ccw = $cAng - $aAng
        if ($ccw -lt 0) { $ccw += 2*[Math]::PI }

        # Check which direction contains the vertex angle
        $dCw = $aAng - $vAng
        if ($dCw -lt 0) { $dCw += 2*[Math]::PI }
        $dCcw = $vAng - $aAng
        if ($dCcw -lt 0) { $dCcw += 2*[Math]::PI }

        if ($dCw -lt [Math]::Abs($cw) + 0.01) {
            return @{ CX=$ux; CY=$uy; R=$r; Start=$aAng; Sweep=$cw }
        } else {
            return @{ CX=$ux; CY=$uy; R=$r; Start=$aAng; Sweep=$ccw }
        }
    }

    # Fit top & bottom arcs through their apex vertices
    $topArc = FitArc $trM $tvM $tlM
    $botArc = FitArc $blM $bvM $brM

    # segment lengths
    function SegLen($a, $b) {
        $dx = $b.X - $a.X; $dy = $b.Y - $a.Y
        [Math]::Sqrt($dx*$dx + $dy*$dy)
    }
    $lenRS = SegLen $brM $trM
    $lenTC = [Math]::Abs($topArc.Sweep) * $topArc.R
    $lenLS = SegLen $tlM $blM
    $lenBC = [Math]::Abs($botArc.Sweep) * $botArc.R
    $total = $lenRS + $lenTC + $lenLS + $lenBC

    # points per segment
    $nRS = [Math]::Max(3, [int]($n * $lenRS / $total))
    $nTC = [Math]::Max(4, [int]($n * $lenTC / $total))
    $nLS = [Math]::Max(3, [int]($n * $lenLS / $total))
    $nBC = $n - $nRS - $nTC - $nLS

    # ---- build path ----
    $path = @()
    $idx  = 0

    # Helper: lat/lng from meter coords
    function ToLL($mx, $my) {
        @{ Lat = $br.Lat + ($my - $brM.Y) / $mdLat
           Lng = $br.Lng + ($mx - $brM.X) / $mdLng }
    }

    # Segment 1: right straight BR→TR
    for ($i = 0; $i -lt $nRS; $i++) {
        $t = $i / $nRS
        $mx = $brM.X + $t * ($trM.X - $brM.X)
        $my = $brM.Y + $t * ($trM.Y - $brM.Y)
        $sdx = $trM.X - $brM.X; $sdy = $trM.Y - $brM.Y
        $sl  = [Math]::Sqrt($sdx*$sdx + $sdy*$sdy)
        $nx  = if ($sl -gt 0.001) { $sdy / $sl } else { 0 }
        $ny  = if ($sl -gt 0.001) { -$sdx / $sl } else { 0 }
        $ww  = $wob[$idx]
        $ll  = ToLL ($mx + $ww*$nx) ($my + $ww*$ny)
        $path += @{ Lat = $ll.Lat; Lng = $ll.Lng }
        $idx++
    }

    # Segment 2: top arc TR→上顶点→TL (through apex)
    for ($i = 0; $i -lt $nTC; $i++) {
        $t   = $i / $nTC
        $ang = $topArc.Start + $t * $topArc.Sweep
        $mx  = $topArc.CX + $topArc.R * [Math]::Cos($ang)
        $my  = $topArc.CY + $topArc.R * [Math]::Sin($ang)
        $nx  = [Math]::Cos($ang)
        $ny  = [Math]::Sin($ang)
        $ww  = $wob[$idx]
        $ll  = ToLL ($mx + $ww*$nx) ($my + $ww*$ny)
        $path += @{ Lat = $ll.Lat; Lng = $ll.Lng }
        $idx++
    }

    # Segment 3: left straight TL→BL
    for ($i = 0; $i -lt $nLS; $i++) {
        $t = $i / $nLS
        $mx = $tlM.X + $t * ($blM.X - $tlM.X)
        $my = $tlM.Y + $t * ($blM.Y - $tlM.Y)
        $sdx = $blM.X - $tlM.X; $sdy = $blM.Y - $tlM.Y
        $sl  = [Math]::Sqrt($sdx*$sdx + $sdy*$sdy)
        $nx  = if ($sl -gt 0.001) { $sdy / $sl } else { 0 }
        $ny  = if ($sl -gt 0.001) { -$sdx / $sl } else { 0 }
        $ww  = $wob[$idx]
        $ll  = ToLL ($mx + $ww*$nx) ($my + $ww*$ny)
        $path += @{ Lat = $ll.Lat; Lng = $ll.Lng }
        $idx++
    }

    # Segment 4: bottom arc BL→下顶点→BR (through apex)
    for ($i = 0; $i -lt $nBC; $i++) {
        $t   = $i / $nBC
        $ang = $botArc.Start + $t * $botArc.Sweep
        $mx  = $botArc.CX + $botArc.R * [Math]::Cos($ang)
        $my  = $botArc.CY + $botArc.R * [Math]::Sin($ang)
        $nx  = [Math]::Cos($ang)
        $ny  = [Math]::Sin($ang)
        $ww  = $wob[$idx]
        $ll  = ToLL ($mx + $ww*$nx) ($my + $ww*$ny)
        $path += @{ Lat = $ll.Lat; Lng = $ll.Lng }
        $idx++
    }

    # Random starting point (skip for continuation laps)
    if (-not $noShuffle) {
        $si = Get-Random -Min 0 -Max $path.Count
        $path = $path[$si..($path.Count-1)] + $path[0..($si-1)]
    }

    return $path
}

function Is-ESC   { ([I4W]::GetAsyncKeyState([I4W]::VK_ESC) -band 0x8000) -ne 0 }
function Is-Enter { ([I4W]::GetAsyncKeyState([I4W]::VK_RETURN) -band 0x8000) -ne 0 }

function Wait-KeyRelease {
    while (([I4W]::GetAsyncKeyState([I4W]::VK_RETURN) -band 0x8000) -ne 0) {
        Start-Sleep -Milliseconds 50
    }
}

# ============================================================
# CALIBRATION
# ============================================================

function Invoke-Calibration {
    Write-Host "`n===== INTERACTIVE CALIBRATION =====" -ForegroundColor Cyan
    Write-Host @"

Move mouse to each target and press ENTER to record:

  1. Latitude input field (纬度输入框)
  2. Longitude input field (经度输入框)
  3. Confirm button (修改虚拟定位)
  4. Popup confirm button (弹窗确认按钮)

"@ -ForegroundColor Yellow

    $p = Get-Process i4Tools -ErrorAction SilentlyContinue
    if (-not $p) {
        Write-Host "ERROR: i4Tools not running! Start i4Tools first." -ForegroundColor Red
        return $null
    }

    $hw = [I4W]::FindI4ToolsWindow()
    if ($hw -eq [IntPtr]::Zero) { Write-Host "ERROR: Cannot find visible i4Tools window!" -ForegroundColor Red; return $null }
    [I4W]::ForceSetForeground($hw) | Out-Null
    Start-Sleep -Milliseconds 300

    $wr = New-Object I4R
    [I4W]::GetWindowRect($hw, [ref]$wr)
    $ww = $wr.R - $wr.L; $wh = $wr.B - $wr.T
    Write-Host "Window: ${ww}x${wh} at ($($wr.L),$($wr.T))`n" -ForegroundColor DarkGray

    $fields = @("Latitude", "Longitude", "Confirm", "Confirm2")
    $labels = @(
        "Latitude input field / 纬度输入框",
        "Longitude input field / 经度输入框",
        "Confirm button / 修改虚拟定位",
        "Popup confirm button / 弹窗确认按钮"
    )
    $cal = @{}

    for ($i = 0; $i -lt $fields.Count; $i++) {
        $name = $fields[$i]; $label = $labels[$i]
        Write-Host "[$($i+1)/4] $label" -ForegroundColor Green
        Write-Host "      Move mouse cursor there and press ENTER..." -ForegroundColor Yellow

        Wait-KeyRelease
        while (-not (Is-Enter)) {
            Start-Sleep -Milliseconds 50
            if (Is-ESC) { Write-Host "`nCancelled." -ForegroundColor Red; return $null }
        }
        Wait-KeyRelease

        $cp = New-Object I4P
        [I4W]::GetCursorPos([ref]$cp)
        $rx = $cp.X - $wr.L; $ry = $cp.Y - $wr.T

        if ($rx -lt 0 -or $ry -lt 0 -or $rx -gt $ww -or $ry -gt $wh) {
            Write-Host "      WARNING: ($rx,$ry) is OUTSIDE window!" -ForegroundColor Red
        }

        $cal[$name] = @{ RX = $rx; RY = $ry }
        Write-Host "      Recorded: ($rx, $ry)`n" -ForegroundColor Cyan
    }

    $data = @{
        WindowW = $ww; WindowH = $wh
        LatRX   = $cal["Latitude"].RX;  LatRY   = $cal["Latitude"].RY
        LngRX   = $cal["Longitude"].RX; LngRY   = $cal["Longitude"].RY
        ConfRX  = $cal["Confirm"].RX;   ConfRY  = $cal["Confirm"].RY
        Conf2RX = $cal["Confirm2"].RX;  Conf2RY = $cal["Confirm2"].RY
        Created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $data | ConvertTo-Json | Out-File -FilePath $CalFile -Encoding UTF8
    Write-Host "Calibration saved: $CalFile" -ForegroundColor Green
    return $data
}

# ============================================================
# LOAD CALIBRATION
# ============================================================

function Get-Calibration {
    if ($Calibrate) { return Invoke-Calibration }

    if (Test-Path $CalFile) {
        try {
            $s = Get-Content $CalFile -Raw -Encoding UTF8 | ConvertFrom-Json
            return @{
                WindowW = $s.WindowW; WindowH = $s.WindowH
                LatRX = $s.LatRX; LatRY = $s.LatRY
                LngRX = $s.LngRX; LngRY = $s.LngRY
                ConfRX = $s.ConfRX; ConfRY = $s.ConfRY
                Conf2RX = $s.Conf2RX; Conf2RY = $s.Conf2RY
            }
        } catch {
            Write-Host "Failed to load calibration." -ForegroundColor Yellow
        }
    }
    return Invoke-Calibration
}

# ============================================================
# TEST MODE
# ============================================================

function Invoke-Test($cal, $hw, $wr) {
    Write-Host "`n===== TEST =====" -ForegroundColor Cyan
    $lx = $wr.L + $cal.LatRX;  $ly = $wr.T + $cal.LatRY
    $gx = $wr.L + $cal.LngRX;  $gy = $wr.T + $cal.LngRY
    $cx = $wr.L + $cal.ConfRX; $cy = $wr.T + $cal.ConfRY
    $c2x = $wr.L + $cal.Conf2RX; $c2y = $wr.T + $cal.Conf2RY

    [I4W]::ForceSetForeground($hw) | Out-Null
    Start-Sleep -Milliseconds 200

    [I4W]::SetClip("28.100000")
    [I4W]::ClickSelectPaste($lx, $ly)
    Start-Sleep -Milliseconds 150

    [I4W]::SetClip("112.900000")
    [I4W]::ClickSelectPaste($gx, $gy)
    Start-Sleep -Milliseconds 150

    [I4W]::MoveAndClick($cx, $cy)
    Start-Sleep -Milliseconds 500
    [I4W]::MoveAndClick($c2x, $c2y)
    Write-Host "Sent test coords: 28.100000, 112.900000" -ForegroundColor Cyan
    $ok = Read-Host "Did it work? (Y/N)"
    return ($ok -eq "Y" -or $ok -eq "y" -or $ok -eq "")
}

# ============================================================
# MAIN
# ============================================================

$ErrorActionPreference = "Stop"

function Pause-Exit($msg, $color = "Red") {
    Write-Host "`n$msg" -ForegroundColor $color
    Write-Host "Press Enter to exit..."
    Read-Host
    exit 1
}

try {
    Clear-Host
    Write-Host @"

  ==========================================
    Track Running Virtual Location v3.0
    i4Tools Automation
  ==========================================

"@ -ForegroundColor Cyan

    # Get calibration
    $cal = Get-Calibration
    if (-not $cal) { Pause-Exit "Calibration failed. Make sure i4Tools is running." }

    # Get i4Tools window
    $hw = [I4W]::FindI4ToolsWindow()
    if ($hw -eq [IntPtr]::Zero) { Pause-Exit "i4Tools window not found! Start i4Tools first." }
$wr = New-Object I4R; [I4W]::GetWindowRect($hw, [ref]$wr)
$ww = $wr.R - $wr.L; $wh = $wr.B - $wr.T

# Handle window resize
if ([Math]::Abs($ww - $cal.WindowW) -gt 50 -or [Math]::Abs($wh - $cal.WindowH) -gt 50) {
    Write-Host "`nWindow size changed. Scaling calibration..." -ForegroundColor Yellow
    $sx = $ww / $cal.WindowW; $sy = $wh / $cal.WindowH
    $cal.LatRX  = [int]($cal.LatRX  * $sx); $cal.LatRY  = [int]($cal.LatRY  * $sy)
    $cal.LngRX  = [int]($cal.LngRX  * $sx); $cal.LngRY  = [int]($cal.LngRY  * $sy)
    $cal.ConfRX  = [int]($cal.ConfRX  * $sx); $cal.ConfRY  = [int]($cal.ConfRY  * $sy)
    $cal.Conf2RX = [int]($cal.Conf2RX * $sx); $cal.Conf2RY = [int]($cal.Conf2RY * $sy)
    $cal.WindowW = $ww; $cal.WindowH = $wh
}

$lx  = $wr.L + $cal.LatRX;   $ly  = $wr.T + $cal.LatRY
$gx  = $wr.L + $cal.LngRX;   $gy  = $wr.T + $cal.LngRY
$cx  = $wr.L + $cal.ConfRX;  $cy  = $wr.T + $cal.ConfRY
$c2x = $wr.L + $cal.Conf2RX; $c2y = $wr.T + $cal.Conf2RY

Write-Host "Window: ${ww}x${wh}  Targets: Lat($lx,$ly) Lng($gx,$gy) Btn($cx,$cy) Btn2($c2x,$c2y)" -ForegroundColor DarkGray

# Test mode
if ($Test) {
    $ok = Invoke-Test $cal $hw $wr
    if (-not $ok) {
        Write-Host "Test failed. Recalibrate." -ForegroundColor Red
        $cal = Invoke-Calibration
        if (-not $cal) { exit 1 }
    }
}

# Select campus
Write-Host "`nSelect campus:" -ForegroundColor Yellow
Write-Host "  [1] 城南书院校区 (Tianxin, Changsha)"
Write-Host "  [2] 东方红校区 (Yuelu, Changsha)`n"
$ch = Read-Host "Enter 1 or 2"
if (-not $CampusConfig.ContainsKey($ch)) { Write-Host "Invalid!" -ForegroundColor Red; exit 1 }
$cam = $CampusConfig[$ch]
Write-Host "`nSelected: $($cam.Name) - $($cam.Address)" -ForegroundColor Green

# Show params
Write-Host "`nParameters:" -ForegroundColor Yellow
Write-Host "  Track points (BR/TR/TV/TL/BL/BV):"
Write-Host "    BR: $($cam.BR_Lat), $($cam.BR_Lng)"
Write-Host "    TR: $($cam.TR_Lat), $($cam.TR_Lng)"
Write-Host "    TV: $($cam.TV_Lat), $($cam.TV_Lng)  (上顶点)"
Write-Host "    TL: $($cam.TL_Lat), $($cam.TL_Lng)"
Write-Host "    BL: $($cam.BL_Lat), $($cam.BL_Lng)"
Write-Host "    BV: $($cam.BV_Lat), $($cam.BV_Lng)  (下顶点)"
Write-Host "  Points:   $PointsPerLap/lap | Pace: $PaceSecPerKm s/km"
Write-Host "  Wobble: +/-$([Math]::Round($WobbleStdDev*3,1))m"

# Distance input
Write-Host "`nEnter target distance (km):" -ForegroundColor Yellow
$distKm = Read-Host "Distance (km)"
try { $distKm = [double]$distKm } catch { Write-Host "Invalid distance!" -ForegroundColor Red; exit 1 }
if ($distKm -le 0) { Write-Host "Distance must be > 0!" -ForegroundColor Red; exit 1 }

# Measure lap perimeter (clean path, no wobble)
Write-Host "`nMeasuring lap distance..." -ForegroundColor Cyan
$zeroWob = New-Object double[] $PointsPerLap
for ($i = 0; $i -lt $PointsPerLap; $i++) { $zeroWob[$i] = 0.0 }
$cleanPath = Get-Path $cam $PointsPerLap $zeroWob $true

$avgLat = ($cam.BR_Lat + $cam.TR_Lat + $cam.TL_Lat + $cam.BL_Lat) / 4.0
$cosLat = [Math]::Cos($avgLat * [Math]::PI / 180.0)
$lapM = 0.0
for ($i = 0; $i -lt $cleanPath.Count; $i++) {
    $j = ($i + 1) % $cleanPath.Count
    $dLat = ($cleanPath[$j].Lat - $cleanPath[$i].Lat) * 111320.0
    $dLng = ($cleanPath[$j].Lng - $cleanPath[$i].Lng) * 111320.0 * $cosLat
    $lapM += [Math]::Sqrt($dLat*$dLat + $dLng*$dLng)
}

$targetM = $distKm * 1000.0
$totalLaps = $targetM / $lapM
$totalPts = [int]($totalLaps * $PointsPerLap) + $PointsPerLap

# Pace-based interval
$pacePerPt = $PaceSecPerKm * ($lapM / $PointsPerLap) / 1000.0

# Generate multi-lap wobble + pace variations
Write-Host "Generating realistic movement for $totalPts points..." -ForegroundColor Cyan
$allWob = Get-Wobble $totalPts $WobbleStdDev $WobbleSmooth

# Pace micro-variations (AR1, very subtle ~0.3% std dev)
$paceVars = New-Object double[] $totalPts
$paceVars[0] = (Get-Normal) * ($PaceVarPct / 100.0) * 0.15
for ($j = 1; $j -lt $totalPts; $j++) {
    $inn = (Get-Normal) * ($PaceVarPct / 100.0) * [Math]::Sqrt(1 - 0.88 * 0.88)
    $paceVars[$j] = 0.88 * $paceVars[$j-1] + $inn
}

# Build multi-lap path (all laps unshuffled for continuity)
Write-Host "Building $([Math]::Round($totalLaps,1)) laps ($([Math]::Round($targetM,0))m)..." -ForegroundColor Cyan
$path = New-Object System.Collections.Generic.List[object]
$fullLaps = [int]$totalLaps + 1
for ($lap = 0; $lap -lt $fullLaps; $lap++) {
    $start = $lap * $PointsPerLap
    $wobSlice = $allWob[$start..($start + $PointsPerLap - 1)]
    $lapPath = Get-Path $cam $PointsPerLap $wobSlice $true  # all laps unshuffled
    $path.AddRange($lapPath)
}
# Trim to exact point count
$exactPts = [int]($totalLaps * $PointsPerLap)
while ($path.Count -gt $exactPts) { $path.RemoveAt($path.Count - 1) }

# Apply random start to the entire continuous path (not per-lap)
$si = Get-Random -Min 0 -Max $path.Count
$path = $path[$si..($path.Count-1)] + $path[0..($si-1)]

Write-Host "Lap: $([Math]::Round($lapM,1))m | Total: $distKm km | Points: $($path.Count) | Interval: $([Math]::Round($pacePerPt,2))s" -ForegroundColor Green

# Preview
Write-Host "`nPreview:" -ForegroundColor Yellow
for ($i = 0; $i -lt [Math]::Min(3, $path.Count); $i++) {
    Write-Host ("  [{0:D2}] {1:F6}, {2:F6}" -f $i, $path[$i].Lat, $path[$i].Lng)
}
Write-Host "  ..."
Write-Host ("  [{0:D2}] {1:F6}, {2:F6}" -f ($path.Count-1), $path[-1].Lat, $path[-1].Lng)

Write-Host "`nStarting in 3s... (ESC to stop anytime)" -ForegroundColor Yellow
Start-Sleep -Seconds 3

# ===== RUN =====
# Bring i4Tools to foreground first, THEN minimize console (i4Tools stays on top)
[I4W]::ForceSetForeground($hw) | Out-Null
Start-Sleep -Milliseconds 200
$consoleHwnd = [I4W]::GetConsoleWindow()
[I4W]::ShowWindow($consoleHwnd, [I4W]::SW_MINIMIZE) | Out-Null
Start-Sleep -Milliseconds 100

$t0 = Get-Date
$targetPts = $path.Count
$paceAccum = 0.0

for ($i = 0; $i -lt $targetPts; $i++) {
    if (Is-ESC) {
        Write-Host "`nSTOPPED by user (ESC)." -ForegroundColor Yellow
        break
    }

    $pt = $path[$i]
    $ls = $pt.Lat.ToString("F6")
    $gs = $pt.Lng.ToString("F6")

    try {
        [I4W]::SetClip($ls)
        [I4W]::ClickSelectPaste($lx, $ly)
        Start-Sleep -Milliseconds 80
        if (Is-ESC) { Write-Host "`nSTOPPED." -ForegroundColor Yellow; break }

        [I4W]::SetClip($gs)
        [I4W]::ClickSelectPaste($gx, $gy)
        Start-Sleep -Milliseconds 80
        if (Is-ESC) { Write-Host "`nSTOPPED." -ForegroundColor Yellow; break }

        [I4W]::MoveAndClick($cx, $cy)

        $popup = [I4W]::WaitForPopup($hw, 8000)
        if ($popup -ne [IntPtr]::Zero) {
            [I4W]::MoveAndClick($c2x, $c2y)
        } else {
            [I4W]::MoveAndClick($c2x, $c2y)
        }

        $el = (Get-Date) - $t0
        $distDone = ($i + 1.0) / $PointsPerLap * $lapM / 1000.0
        $pct = [Math]::Min(100, [int](($i+1.0)/$targetPts*100))
        Write-Host ("[{0:D5}/{1:D5}] {2:F6},{3:F6} [{4}%] {5:F2}km {6:mm\:ss}" -f ($i+1), $targetPts, $pt.Lat, $pt.Lng, $pct, $distDone, $el)
    } catch {
        Write-Host "  err: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    # Pace-accurate timing with micro-variations
    $paceAccum += $pacePerPt * (1.0 + $paceVars[$i])
    $targetTime = $t0.AddSeconds($paceAccum)
    while ((Get-Date) -lt $targetTime) {
        Start-Sleep -Milliseconds 50
        if (Is-ESC) { break }
    }
    if (Is-ESC) {
        Write-Host "`nSTOPPED by user (ESC)." -ForegroundColor Yellow
        break
    }
}

    $tt = (Get-Date) - $t0
    [I4W]::ShowWindow($consoleHwnd, 9) | Out-Null

    Write-Host "`n===== DONE =====" -ForegroundColor Green
    $distDone = ($i) * $lapM / $PointsPerLap / 1000.0
    $paceActual = if ($distDone -gt 0) { [Math]::Round($tt.TotalSeconds / $distDone, 1) } else { 0 }
    Write-Host "Distance: $([Math]::Round($distDone,2))km | Time: $($tt.ToString('mm\:ss')) | Pace: ${paceActual}s/km" -ForegroundColor Cyan

} catch {
    Write-Host "`n===== ERROR =====" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkYellow
    try { if ($consoleHwnd) { [I4W]::ShowWindow($consoleHwnd, 9) | Out-Null } } catch { }
} finally {
    Write-Host "`nPress Enter to exit..."
    Read-Host
}
