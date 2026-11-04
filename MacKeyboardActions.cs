using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class MacKeyboardActions {
    delegate bool EnumProc(IntPtr hwnd, IntPtr parameter);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint command);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint process);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr hwnd, int command);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr hwnd);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, INPUT[] input, int size);
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTUNION data; }
    [StructLayout(LayoutKind.Explicit)] struct INPUTUNION {
        [FieldOffset(0)] public KEYBDINPUT keyboard;
        [FieldOffset(0)] public MOUSEINPUT mouse;
    }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort key, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int x, y; public uint data, flags, time; public UIntPtr extra; }

    static string AppKey(IntPtr hwnd) {
        uint id; GetWindowThreadProcessId(hwnd, out id);
        try {
            var process = Process.GetProcessById((int)id);
            // Different hosted UWP apps must not be grouped together.
            if (process.ProcessName.Equals("ApplicationFrameHost", StringComparison.OrdinalIgnoreCase)) return "host:" + id;
            try { return process.MainModule.FileName; }
            catch { return process.ProcessName; }
        } catch { return null; }
    }
    static bool Candidate(IntPtr hwnd) {
        int cloaked;
        return IsWindowVisible(hwnd) && GetWindow(hwnd, 4) == IntPtr.Zero && GetWindowTextLength(hwnd) > 0 &&
            (DwmGetWindowAttribute(hwnd, 14, out cloaked, sizeof(int)) != 0 || cloaked == 0);
    }
    static List<IntPtr> AppWindows(IntPtr foreground) {
        string app = AppKey(foreground);
        var windows = new List<IntPtr>();
        if (app == null) return windows;
        EnumWindows(delegate(IntPtr hwnd, IntPtr unused) {
            if (Candidate(hwnd) && String.Equals(app, AppKey(hwnd), StringComparison.OrdinalIgnoreCase)) windows.Add(hwnd);
            return true;
        }, IntPtr.Zero);
        windows.Sort(delegate(IntPtr a, IntPtr b) { return a.ToInt64().CompareTo(b.ToInt64()); });
        return windows;
    }
    static INPUT Key(ushort key, bool up) {
        return new INPUT { type=1, data=new INPUTUNION { keyboard=new KEYBDINPUT { key=key, flags=up ? 2u : 0u } } };
    }
    static bool ModifiersHeld() {
        foreach (int key in new int[] { 16, 17, 18, 91, 92 }) if ((GetAsyncKeyState(key) & 0x8000) != 0) return true;
        return false;
    }
    public static int Main(string[] args) {
        if (args.Length != 1) return 2;
        IntPtr foreground = GetForegroundWindow();
        if (args[0] == "inspect") {
            var windows = AppWindows(foreground);
            Console.WriteLine("Input structure size: " + Marshal.SizeOf(typeof(INPUT)));
            Console.WriteLine("Foreground application: " + AppKey(foreground));
            Console.WriteLine("Matching windows: " + windows.Count);
            return 0;
        }
        if (args[0] == "cycle") {
            var windows = AppWindows(foreground);
            if (windows.Count < 2) return 0;
            int index = windows.IndexOf(foreground);
            IntPtr next = windows[(index + 1) % windows.Count];
            if (IsIconic(next)) ShowWindowAsync(next, 9);
            return SetForegroundWindow(next) ? 0 : 1;
        }
        if (args[0] == "delete-line") {
            // Do not inject editing keys while Command is still held, or into a different app.
            var wait = Stopwatch.StartNew();
            while (ModifiersHeld() && wait.ElapsedMilliseconds < 5000) Thread.Sleep(10);
            if (ModifiersHeld() || foreground != GetForegroundWindow()) return 1;
            INPUT[] sequence = { Key(16,false), Key(36,false), Key(36,true), Key(16,true), Key(8,false), Key(8,true) };
            return SendInput((uint)sequence.Length, sequence, Marshal.SizeOf(typeof(INPUT))) == sequence.Length ? 0 : 1;
        }
        return 2;
    }
}
