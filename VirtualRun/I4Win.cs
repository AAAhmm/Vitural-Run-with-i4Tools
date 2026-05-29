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

    // ============================================================
    // PUBLIC
    // ============================================================

    /// <summary>Move cursor to screen position and left-click</summary>
    public static void MoveAndClick(int x, int y)
    {
        SetCursorPos(x, y);
        Thread.Sleep(15);
        // mouse_event uses the current cursor position for clicks
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(30);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(40);
    }

    /// <summary>Press and release a key (with proper scan code)</summary>
    static void PressKey(int vk)
    {
        byte scan = (byte)MapVirtualKey((uint)vk, 0);
        keybd_event((byte)vk, scan, 0, UIntPtr.Zero);
        Thread.Sleep(20);
        keybd_event((byte)vk, scan, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(20);
    }

    /// <summary>Send Ctrl+A to the foreground window</summary>
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

    /// <summary>Send Ctrl+V to the foreground window</summary>
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

    /// <summary>Click into field, then Ctrl+A + Ctrl+V</summary>
    public static void ClickSelectPaste(int x, int y)
    {
        MoveAndClick(x, y);
        Thread.Sleep(150);  // Qt fields need more time to gain focus
        SendCtrlA();
        Thread.Sleep(80);
        SendCtrlV();
        Thread.Sleep(100);
    }

    /// <summary>Set clipboard text (UTF-16) via Win32 API</summary>
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

    /// <summary>
    /// Bring window to foreground reliably via Alt-key hack.
    /// Windows normally blocks SetForegroundWindow from non-foreground processes;
    /// simulating an Alt key press first tricks the system into allowing it.
    /// </summary>
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

    /// <summary>
    /// Wait for a popup dialog to appear from the same process as mainHwnd.
    /// Returns the popup handle, or IntPtr.Zero on timeout.
    /// </summary>
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

    /// <summary>
    /// Find the ACTUAL visible i4Tools window.
    /// Process.MainWindowHandle often returns a hidden off-screen window.
    /// </summary>
    public static IntPtr FindI4ToolsWindow()
    {
        // First try: find by exact title
        IntPtr h = FindWindow(null, "爱思助手");
        if (h != IntPtr.Zero && IsWindowVisible(h))
        {
            I4R r;
            GetWindowRect(h, out r);
            if (r.R - r.L > 200 && r.B - r.T > 200) // must be reasonably sized
                return h;
        }

        // Second try: enumerate all windows looking for i4Tools
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
                // Filter out tiny/hidden helper windows
                if (IsWindowVisible(w) && ww > 200 && wh > 200)
                {
                    found = w;
                    return false; // stop enumeration
                }
            }
            return true; // continue
        }, IntPtr.Zero);

        return found;
    }
}

public struct I4R { public int L, T, R, B; }
public struct I4P { public int X, Y; }
