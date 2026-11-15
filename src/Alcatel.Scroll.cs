// Original Alcatel USB Desk code. Uses only Windows/.NET and the bundled ADB.
using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace Alcatel {
    public sealed class DisplaySize {
        public readonly int Width, Height;
        public DisplaySize(int width, int height) {
            if (width < 100 || height < 100 || width > 16384 || height > 16384)
                throw new ArgumentException("Invalid Android display size.");
            Width = width; Height = height;
        }
    }

    public sealed class Swipe {
        public readonly int X, StartY, EndY;
        public const int Duration = 140;
        public Swipe(int x, int startY, int endY) { X = x; StartY = startY; EndY = endY; }
    }

    public static class ScrollMath {
        public static DisplaySize ParseDisplay(string text) {
            Match m = Regex.Match(text, @"Viewport:\s*displayId=0\b[^\r\n]*logicalFrame=\[0,\s*0,\s*(\d+),\s*(\d+)\]");
            if (!m.Success)
                m = Regex.Match(text, @"Viewport[^\r\n]*displayId=0\b[^\r\n]*logicalFrame=Rect\(0,\s*0\s*-\s*(\d+),\s*(\d+)\)");
            if (!m.Success) throw new ArgumentException("Cannot read the default Android display viewport.");
            return new DisplaySize(Int32.Parse(m.Groups[1].Value), Int32.Parse(m.Groups[2].Value));
        }

        public static bool MapPointer(int clientWidth, int clientHeight, DisplaySize display,
                                      int x, int y, out double nx, out double ny) {
            nx = ny = 0;
            if (clientWidth <= 0 || clientHeight <= 0) return false;
            double scale = Math.Min((double)clientWidth / display.Width, (double)clientHeight / display.Height);
            double width = display.Width * scale, height = display.Height * scale;
            double left = (clientWidth - width) / 2, top = (clientHeight - height) / 2;
            if (x < left || x >= left + width || y < top || y >= top + height) return false;
            nx = (x - left) / width; ny = (y - top) / height;
            return true;
        }

        public static Swipe Plan(DisplaySize display, double nx, double ny, int notches) {
            if (notches == 0 || Double.IsNaN(nx) || Double.IsNaN(ny) || nx < 0 || nx > 1 || ny < 0 || ny > 1)
                throw new ArgumentException("Invalid wheel gesture.");
            double distance = Math.Min(0.42, 0.18 + 0.10 * (Math.Min(3, Math.Abs((long)notches)) - 1));
            // Wheel down => finger up => reveal content below. Stay clear of system bars.
            double start = notches < 0 ? Math.Max(0.12 + distance, Math.Min(0.88, ny))
                                      : Math.Min(0.88 - distance, Math.Max(0.12, ny));
            double end = start + (notches < 0 ? -distance : distance);
            return new Swipe((int)Math.Round(Math.Max(0.05, Math.Min(0.95, nx)) * (display.Width - 1)),
                             (int)Math.Round(start * (display.Height - 1)),
                             (int)Math.Round(end * (display.Height - 1)));
        }

        public static void ValidateSerial(string serial) {
            if (!Regex.IsMatch(serial ?? "", @"\A[A-Za-z0-9_.:-]+\z"))
                throw new ArgumentException("Invalid device serial.");
        }

        // scrcpy 5.0.1 control_msg.c: 32-byte INJECT_TOUCH_EVENT, network byte order.
        public static byte[] TouchPacket(DisplaySize display, int action, int x, int y) {
            if (action < 0 || action > 3 || x < 0 || x >= display.Width || y < 0 || y >= display.Height)
                throw new ArgumentException("Invalid touch packet.");
            byte[] bytes = new byte[32]; bytes[0] = 2; bytes[1] = (byte)action;
            for (int i = 2; i < 10; i++) bytes[i] = 255;
            bytes[9] = 254; // SC_POINTER_ID_GENERIC_FINGER (-2), no mouse buttons.
            WriteBig(bytes, 10, (uint)x, 4); WriteBig(bytes, 14, (uint)y, 4);
            WriteBig(bytes, 18, (uint)display.Width, 2); WriteBig(bytes, 20, (uint)display.Height, 2);
            if (action == 0 || action == 2) { bytes[22] = 255; bytes[23] = 255; }
            return bytes;
        }

        public static void WriteSwipe(Stream stream, DisplaySize display, Swipe swipe,
                                      Func<bool> cancelled, Action<int> delay) {
            if (cancelled()) return;
            int y = swipe.StartY;
            byte[] packet = TouchPacket(display, 0, swipe.X, y);
            stream.Write(packet, 0, packet.Length);
            bool completed = false;
            try {
                for (int step = 1; step <= 8; step++) {
                    delay(Swipe.Duration / 8);
                    if (cancelled()) return;
                    y = swipe.StartY + (swipe.EndY - swipe.StartY) * step / 8;
                    packet = TouchPacket(display, 2, swipe.X, y);
                    stream.Write(packet, 0, packet.Length);
                }
                completed = true;
            } finally {
                // Cancel interrupted gestures rather than accidentally turning them into taps.
                packet = TouchPacket(display, completed ? 1 : 3, swipe.X, y);
                stream.Write(packet, 0, packet.Length);
            }
        }
        private static void WriteBig(byte[] bytes, int offset, uint value, int count) {
            for (int i = count - 1; i >= 0; i--) { bytes[offset + i] = (byte)value; value >>= 8; }
        }
    }

    // A control-only instance of the already bundled scrcpy server. No video,
    // microphone, keyboard, clipboard synchronization, APK install or shell-input JVM per tick.
    public sealed class ScrcpyControl : IDisposable {
        private readonly string adb, serial, remote;
        private int port;
        private Process server;
        private bool serverStarted;
        private TcpClient client;
        private System.Threading.Tasks.Task<string> serverOutput, serverError;

        public ScrcpyControl(string adbPath, string deviceSerial, string version) {
            ScrollMath.ValidateSerial(deviceSerial);
            if (!Regex.IsMatch(version ?? "", @"\A\d+\.\d+\.\d+\z")) throw new ArgumentException("Invalid scrcpy version.");
            adb = adbPath; serial = deviceSerial;
            string id = (BitConverter.ToUInt32(Guid.NewGuid().ToByteArray(), 0) & 0x7FFFFFFF).ToString("x8");
            remote = "/data/local/tmp/alcatel-scroll-" + Guid.NewGuid().ToString("N") + ".jar";
            try {
                Command("push \"" + Path.Combine(Path.GetDirectoryName(adb), "scrcpy-server") + "\" " + remote);
                port = Int32.Parse(Command("forward tcp:0 localabstract:scrcpy_" + id).Trim());
                server = NewProcess("shell CLASSPATH=" + remote + " app_process / com.genymobile.scrcpy.Server " + version
                    + " scid=" + id + " video=false audio=false control=true tunnel_forward=true"
                    + " send_device_meta=false clipboard_autosync=false cleanup=false power_on=false");
                server.Start(); serverStarted = true;
                serverOutput = server.StandardOutput.ReadToEndAsync(); serverError = server.StandardError.ReadToEndAsync();
                DateTime deadline = DateTime.UtcNow.AddSeconds(8);
                Exception last = null;
                while (DateTime.UtcNow < deadline) {
                    if (server.HasExited) throw new IOException("Scroll server exited: " + serverError.Result + serverOutput.Result);
                    try {
                        client = new TcpClient(); client.NoDelay = true;
                        client.ReceiveTimeout = 500; client.SendTimeout = 1000;
                        client.Connect("127.0.0.1", port);
                        if (client.GetStream().ReadByte() != 0) throw new IOException("Scroll handshake not ready.");
                        return;
                    } catch (IOException error) { last = error; }
                    catch (SocketException error) { last = error; }
                    if (client != null) { client.Close(); client = null; }
                    Thread.Sleep(100);
                }
                throw new IOException("Cannot connect the scrcpy scroll control channel.", last);
            } catch { Dispose(); throw; }
        }

        private Process NewProcess(string args) {
            return new Process { StartInfo = new ProcessStartInfo(adb, "-s " + serial + " " + args) {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
            }};
        }

        private string Command(string args) {
            using (Process process = NewProcess(args)) {
                process.Start();
                var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(8000)) { process.Kill(); process.WaitForExit(); throw new TimeoutException("ADB control setup timed out."); }
                if (process.ExitCode != 0) throw new IOException("ADB control exit " + process.ExitCode + ": " + error.Result + output.Result);
                return output.Result;
            }
        }

        public void SendSwipe(DisplaySize display, Swipe swipe, Func<bool> cancelled) {
            ScrollMath.WriteSwipe(client.GetStream(), display, swipe, cancelled, Thread.Sleep);
        }

        public void Dispose() {
            if (client != null) { client.Close(); client = null; }
            if (server != null) {
                if (serverStarted && !server.WaitForExit(1500)) { server.Kill(); server.WaitForExit(); }
                server.Dispose(); server = null;
            }
            if (port != 0) {
                try { Command("forward --remove tcp:" + port); } catch (Exception error) { Console.Error.WriteLine("Scroll cleanup: " + error.Message); }
                port = 0;
            }
            try { Command("shell rm -f " + remote); } catch (Exception error) { Console.Error.WriteLine("Scroll cleanup: " + error.Message); }
        }
    }

    // Bounded pending work, with fractional/high-resolution wheel deltas retained.
    public sealed class WheelAccumulator {
        private int remainder, pending, direction;
        public void Add(int delta) {
            if (delta == 0) return;
            int sign = Math.Sign(delta);
            if (direction != sign) { remainder = pending = 0; direction = sign; }
            long sum = (long)remainder + delta;
            pending = (int)Math.Max(-3, Math.Min(3, pending + sum / 120));
            remainder = (int)(sum % 120);
        }
        public int Take() { int result = pending; pending = 0; return result; }
        public void Reset() { remainder = pending = direction = 0; }
    }

    public sealed class WheelScrollSession : IDisposable {
        [StructLayout(LayoutKind.Sequential)]
        private struct Point { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Rect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct MouseData {
            public Point Position;
            public uint Data, Flags, Time;
            public UIntPtr ExtraInfo;
        }
        private delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, HookProc callback, IntPtr module, uint thread);
        [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string name);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out Rect rect);
        [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr window, ref Point point);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

        private readonly Process mirror;
        private readonly string adb, serial, version;
        private readonly object gate = new object();
        private readonly AutoResetEvent signal = new AutoResetEvent(false);
        private readonly WheelAccumulator queue = new WheelAccumulator();
        private readonly HookProc callback;
        private readonly ApplicationContext context = new ApplicationContext();
        private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        private Thread worker;
        private IntPtr hook;
        private volatile bool stopping, failed;
        private volatile DisplaySize display;
        private volatile bool ready;
        private ScrcpyControl control;
        private Point pendingPoint;
        private DateTime pendingAt;
        private int previousWidth, previousHeight;
        private int refreshRequested;
        private DateTime displayAt;

        public WheelScrollSession(int processId, string scrcpy, string adbPath, string deviceSerial, string scrcpyVersion) {
            // Validate before starting a hook or any Android command.
            ScrollMath.ValidateSerial(deviceSerial);
            mirror = Process.GetProcessById(processId);
            IntPtr handle = mirror.Handle; // Pin the original process, including against PID reuse.
            if (!String.Equals(mirror.MainModule.FileName, scrcpy, StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("The scroll target is not this installation's scrcpy process.");
            adb = adbPath; serial = deviceSerial; version = scrcpyVersion;
            callback = OnMouse;
            timer.Interval = 250;
            timer.Tick += delegate {
                if (mirror.HasExited || failed) { context.ExitThread(); return; }
                mirror.Refresh();
                Rect rect;
                if (GetClientRect(mirror.MainWindowHandle, out rect)
                        && (rect.Right != previousWidth || rect.Bottom != previousHeight)) {
                    previousWidth = rect.Right; previousHeight = rect.Bottom;
                    Interlocked.Exchange(ref refreshRequested, 1); signal.Set();
                }
            };
        }

        public void Run() {
            try { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
            catch (EntryPointNotFoundException) { SetProcessDPIAware(); }
            hook = SetWindowsHookEx(14, callback, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            worker = new Thread(Work); worker.IsBackground = true; worker.Start();
            timer.Start();
            Application.Run(context);
            if (failed) throw new InvalidOperationException("Wheel scrolling stopped; see the preceding error.");
        }

        private static bool ModifiedOrDragging() {
            foreach (int key in new int[] { 1, 2, 4, 0x10, 0x11, 0x12, 0x5B, 0x5C })
                if (GetAsyncKeyState(key) < 0) return true;
            return false;
        }

        private bool Target(Point screen, out double nx, out double ny, out int width, out int height) {
            nx = ny = 0; width = height = 0;
            DisplaySize current = display;
            if (stopping || failed || !ready || current == null || mirror.HasExited || ModifiedOrDragging()) return false;
            IntPtr window = GetAncestor(WindowFromPoint(screen), 2);
            if (window == IntPtr.Zero || GetForegroundWindow() != window) return false;
            uint pid; GetWindowThreadProcessId(window, out pid);
            if (pid != mirror.Id) return false;
            Rect rect;
            if (!GetClientRect(window, out rect) || !ScreenToClient(window, ref screen)) return false;
            width = rect.Right - rect.Left; height = rect.Bottom - rect.Top;
            return ScrollMath.MapPointer(width, height, current, screen.X, screen.Y, out nx, out ny);
        }

        private IntPtr OnMouse(int code, IntPtr message, IntPtr data) {
            if (code >= 0 && message.ToInt64() == 0x020A) { // WM_MOUSEWHEEL only
                try {
                    MouseData mouse = (MouseData)Marshal.PtrToStructure(data, typeof(MouseData));
                    double nx, ny; int width, height;
                    if (Target(mouse.Position, out nx, out ny, out width, out height)) {
                        int delta = unchecked((short)(mouse.Data >> 16));
                        lock (gate) {
                            if ((DateTime.UtcNow - pendingAt).TotalMilliseconds > 750) queue.Reset();
                            queue.Add(delta); pendingPoint = mouse.Position; pendingAt = DateTime.UtcNow;
                        }
                        signal.Set();
                        return new IntPtr(1); // Prevent duplicate native scroll delivery.
                    }
                    lock (gate) { queue.Reset(); }
                } catch (Exception error) {
                    Console.Error.WriteLine("Wheel hook: " + error.Message);
                }
            }
            return CallNextHookEx(hook, code, message, data);
        }

        private string Command(string arguments) {
            using (Process process = new Process()) {
                process.StartInfo = new ProcessStartInfo(adb, arguments) {
                    UseShellExecute = false, CreateNoWindow = true,
                    RedirectStandardOutput = true, RedirectStandardError = true
                };
                process.Start();
                var output = process.StandardOutput.ReadToEndAsync();
                var error = process.StandardError.ReadToEndAsync();
                // Only this worker's own adb client is stopped on timeout, never the ADB server.
                if (!process.WaitForExit(3000)) {
                    process.Kill(); process.WaitForExit();
                    throw new TimeoutException("ADB scroll command timed out; check USB.");
                }
                if (process.ExitCode != 0) throw new InvalidOperationException("ADB exit " + process.ExitCode + " (" + arguments + "): " + error.Result + output.Result);
                return output.Result;
            }
        }

        private void RefreshDisplay() {
            display = ScrollMath.ParseDisplay(Command("-s " + serial + " shell dumpsys input"));
            displayAt = DateTime.UtcNow;
        }

        private void Work() {
            try {
                RefreshDisplay();
                control = new ScrcpyControl(adb, serial, version);
                ready = true;
                Console.WriteLine("Vertical wheel scrolling ready for phone process " + mirror.Id + ".");
                while (!stopping && !mirror.HasExited) {
                    if (!signal.WaitOne(1000)) continue;
                    if (Interlocked.Exchange(ref refreshRequested, 0) != 0) RefreshDisplay();
                    Thread.Sleep(35); // Coalesce a burst; never build an unbounded gesture backlog.
                    Point point; int steps; DateTime queued;
                    lock (gate) { steps = queue.Take(); point = pendingPoint; queued = pendingAt; }
                    if (steps == 0 || (DateTime.UtcNow - queued).TotalMilliseconds > 750) continue;
                    double nx, ny; int width, height;
                    if (!Target(point, out nx, out ny, out width, out height)) continue;
                    if ((DateTime.UtcNow - displayAt).TotalSeconds > 3) {
                        RefreshDisplay();
                        if (!Target(point, out nx, out ny, out width, out height)) continue;
                    }
                    Swipe swipe = ScrollMath.Plan(display, nx, ny, steps);
                    if (stopping || mirror.HasExited) break;
                    if ((DateTime.UtcNow - queued).TotalMilliseconds > 750) continue;
                    control.SendSwipe(display, swipe, delegate {
                        double tx, ty; int tw, th;
                        return !Target(point, out tx, out ty, out tw, out th);
                    });
                }
            } catch (Exception error) {
                Console.Error.WriteLine("Wheel scrolling: " + error);
                failed = true;
            } finally {
                ready = false;
                if (control != null) control.Dispose();
            }
        }

        public void Dispose() {
            stopping = true;
            if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
            timer.Stop(); timer.Dispose(); signal.Set();
            if (worker != null) worker.Join(); // Startup/ADB operations have bounded timeouts.
            signal.Dispose(); context.Dispose(); mirror.Dispose();
        }
    }
}
