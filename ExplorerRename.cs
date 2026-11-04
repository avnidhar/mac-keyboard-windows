using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Forms;

public static class ExplorerRename {
    delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
    static HookProc callback = Hook;
    static IntPtr hook;
    static volatile Context context = new Context();
    static bool swallowReturnUp;
    sealed class Context { public IntPtr window, focus; public bool rename; public long tick; }
    [StructLayout(LayoutKind.Sequential)] struct GUIINFO {
        public int size; public uint flags; public IntPtr active, focus, capture, menu, move, caret;
        public int left, top, right, bottom;
    }
    [StructLayout(LayoutKind.Sequential)] struct KEYEVENT { public uint key, scan, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION data; }
    [StructLayout(LayoutKind.Explicit)] struct UNION {
        [FieldOffset(0)] public KEYBOARD keyboard;
        [FieldOffset(0)] public MOUSE mouse;
    }
    [StructLayout(LayoutKind.Sequential)] struct KEYBOARD { public ushort key, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread, ref GUIINFO info);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int size);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int type, HookProc proc, IntPtr module, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr value, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] input, int size);

    static string Class(IntPtr window) {
        var name = new StringBuilder(256); GetClassName(window, name, name.Capacity); return name.ToString();
    }
    static IntPtr Focus(IntPtr window) {
        uint pid; uint thread = GetWindowThreadProcessId(window, out pid);
        var info = new GUIINFO(); info.size = Marshal.SizeOf(typeof(GUIINFO));
        return GetGUIThreadInfo(thread, ref info) ? info.focus : IntPtr.Zero;
    }
    static bool Explorer(IntPtr window) {
        string name = Class(window);
        if (name != "CabinetWClass" && name != "ExploreWClass") return false;
        uint pid; GetWindowThreadProcessId(window, out pid);
        try { return Process.GetProcessById((int)pid).ProcessName.Equals("explorer", StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }
    static bool ItemList(AutomationElement element) {
        // Address/search/rename fields must retain Enter. Only Explorer's item list qualifies.
        for (int depth=0; element != null && depth<12; depth++) {
            var info = element.Current;
            if (info.ControlType == ControlType.Edit || info.ControlType == ControlType.Menu ||
                info.ControlType == ControlType.MenuItem) return false;
            if (info.AutomationId == "ItemsView" || info.ClassName == "UIItemsView") return true;
            element = TreeWalker.ControlViewWalker.GetParent(element);
        }
        return false;
    }
    static Context Observe() {
        var result = new Context(); result.window = GetForegroundWindow();
        result.focus = Focus(result.window); result.tick = Environment.TickCount & Int32.MaxValue;
        if (!Explorer(result.window) || result.focus == IntPtr.Zero) return result;
        if (Class(result.focus).IndexOf("Edit", StringComparison.OrdinalIgnoreCase) >= 0) return result;
        try {
            AutomationElement focused = AutomationElement.FocusedElement;
            result.rename = focused != null && ItemList(focused);
        } catch { result.rename = false; }
        return result;
    }
    static bool Modifiers() {
        foreach (int key in new int[] {16,17,18,91,92}) if ((GetAsyncKeyState(key)&0x8000)!=0) return true;
        return false;
    }
    static INPUT F2(bool up) {
        return new INPUT {type=1, data=new UNION {keyboard=new KEYBOARD {key=113,flags=up?2u:0u}}};
    }
    static IntPtr Hook(int code, IntPtr message, IntPtr data) {
        if (code >= 0) {
            var key = (KEYEVENT)Marshal.PtrToStructure(data, typeof(KEYEVENT));
            if (key.key == 13 && (key.flags & 16) == 0) {
                bool down = message.ToInt64()==0x100 || message.ToInt64()==0x104;
                bool up = message.ToInt64()==0x101 || message.ToInt64()==0x105;
                if (up && swallowReturnUp) { swallowReturnUp=false; return new IntPtr(1); }
                if (down && swallowReturnUp) return new IntPtr(1);
                var latest = context;
                long age = ((Environment.TickCount & Int32.MaxValue) - latest.tick + Int32.MaxValue) % Int32.MaxValue;
                if (down && !Modifiers() && latest.rename && age < 600 &&
                    latest.window == GetForegroundWindow() && latest.focus == Focus(latest.window)) {
                    swallowReturnUp=true;
                    INPUT[] input = { F2(false), F2(true) };
                    if (SendInput(2,input,Marshal.SizeOf(typeof(INPUT))) == 2) return new IntPtr(1);
                    swallowReturnUp=false;
                }
            }
        }
        return CallNextHookEx(hook,code,message,data);
    }
    [STAThread] public static int Main(string[] args) {
        if (args.Length == 1 && args[0] == "--inspect") {
            var value=Observe();
            Console.WriteLine("Foreground class: " + Class(value.window));
            Console.WriteLine("Focus class: " + Class(value.focus));
            Console.WriteLine("File list focused: " + value.rename);
            Console.WriteLine("Input size: " + Marshal.SizeOf(typeof(INPUT)));
            return 0;
        }
        bool created;
        using (var singleton = new Mutex(true,"Local\\MacKeyboardExplorerRename",out created)) {
            if (!created) return 0;
            var worker = new Thread(delegate() {
                while (true) { try { context=Observe(); } catch {} Thread.Sleep(100); }
            });
            worker.IsBackground=true; worker.SetApartmentState(ApartmentState.MTA); worker.Start();
            hook=SetWindowsHookEx(13,callback,GetModuleHandle(null),0);
            if (hook == IntPtr.Zero) return 1;
            try { Application.Run(); } finally { UnhookWindowsHookEx(hook); }
        }
        return 0;
    }
}
