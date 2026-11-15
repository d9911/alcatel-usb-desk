using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace Alcatel.Desktop {
    public sealed class SmoothLabel : Label {
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            using (Brush brush = new SolidBrush(ForeColor))
            using (StringFormat format = new StringFormat()) {
                format.LineAlignment = StringAlignment.Center;
                format.Trimming = StringTrimming.EllipsisCharacter;
                e.Graphics.DrawString(Text, Font, brush, ClientRectangle, format);
            }
        }
    }
    public static class Shapes {
        public static GraphicsPath Round(Rectangle rect, int radius) {
            GraphicsPath path = new GraphicsPath();
            int d = Math.Max(1, Math.Min(radius * 2, Math.Min(rect.Width, rect.Height)));
            path.AddArc(rect.Left, rect.Top, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Top, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure(); return path;
        }
    }

    public sealed class Card : Panel {
        public Card() {
            DoubleBuffered = true; BackColor = Color.White; Padding = new Padding(20);
        }
        protected override void OnSizeChanged(EventArgs e) {
            base.OnSizeChanged(e);
            if (Width < 2 || Height < 2) return;
            using (GraphicsPath path = Shapes.Round(ClientRectangle, 14)) {
                Region old = Region; Region = new Region(path); if (old != null) old.Dispose();
            }
        }
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = Shapes.Round(new Rectangle(0, 0, Width - 1, Height - 1), 14))
            using (Pen pen = new Pen(Color.FromArgb(223, 228, 232))) e.Graphics.DrawPath(pen, path);
        }
    }

    public sealed class ActionButton : Button {
        public bool Primary { get; set; }
        private bool hover, pressed;
        public ActionButton() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0;
            Cursor = Cursors.Hand; Height = 42; Margin = new Padding(0, 0, 8, 0);
            UseCompatibleTextRendering = false;
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = pressed = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { pressed = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnPaint(PaintEventArgs e) {
            Control parent = Parent;
            while (parent != null && parent.BackColor.A == 0) parent = parent.Parent;
            e.Graphics.Clear(parent == null ? Color.White : parent.BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Color fill = Primary ? Color.FromArgb(29, 104, 99) : Color.FromArgb(246, 248, 249);
            if (!Enabled) fill = Color.FromArgb(238, 241, 243);
            else if (pressed) fill = Primary ? Color.FromArgb(22, 81, 77) : Color.FromArgb(224, 231, 234);
            else if (hover) fill = Primary ? Color.FromArgb(24, 91, 86) : Color.FromArgb(234, 239, 241);
            using (GraphicsPath path = Shapes.Round(new Rectangle(0, 0, Width - 1, Height - 1), 9))
            using (Brush brush = new SolidBrush(fill))
            using (Pen pen = new Pen(Primary && Enabled ? fill : Color.FromArgb(220, 226, 230))) {
                e.Graphics.FillPath(brush, path); e.Graphics.DrawPath(pen, path);
            }
            Color ink = !Enabled ? Color.FromArgb(146, 157, 165) : Primary ? Color.White : Color.FromArgb(38, 52, 62);
            e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            using (Brush text = new SolidBrush(ink))
            using (StringFormat format = new StringFormat()) {
                format.Alignment = format.LineAlignment = StringAlignment.Center;
                format.Trimming = StringTrimming.EllipsisCharacter;
                format.FormatFlags = StringFormatFlags.NoWrap;
                e.Graphics.DrawString(Text, Font, text, ClientRectangle, format);
            }
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -5, -5), ink, fill);
        }
    }

    public sealed class LogLine {
        public readonly string Source, Text;
        public LogLine(string source, string text) { Source = source; Text = text; }
    }

    public sealed class LogFeed {
        private sealed class Tail {
            public string Path, Source;
            public long Offset;
            public Decoder Decoder = Encoding.UTF8.GetDecoder();
            public string Pending = "";
        }
        private readonly string root;
        private readonly List<Tail> tails = new List<Tail>();
        public LogFeed(string directory) { root = System.IO.Path.GetFullPath(directory).TrimEnd(System.IO.Path.DirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar; }
        public void Attach(string path, string source) {
            string full = System.IO.Path.GetFullPath(path);
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Log file must stay inside the application's log directory.");
            foreach (Tail tail in tails) if (tail.Path == full) return;
            tails.Add(new Tail { Path = full, Source = source });
        }
        public LogLine[] Poll() {
            List<LogLine> lines = new List<LogLine>();
            foreach (Tail tail in tails) {
                if (!File.Exists(tail.Path)) continue;
                try {
                    using (FileStream stream = new FileStream(tail.Path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
                        if (stream.Length < tail.Offset) { tail.Offset = 0; tail.Pending = ""; tail.Decoder.Reset(); }
                        stream.Position = tail.Offset;
                        byte[] bytes = new byte[16384]; int count = stream.Read(bytes, 0, bytes.Length);
                        tail.Offset += count;
                        char[] chars = new char[Encoding.UTF8.GetMaxCharCount(count)];
                        int used = tail.Decoder.GetChars(bytes, 0, count, chars, 0, false);
                        string text = tail.Pending + new string(chars, 0, used);
                        string[] parts = text.Split('\n');
                        for (int i = 0; i < parts.Length - 1; i++) Add(lines, tail.Source, parts[i].TrimEnd('\r'));
                        tail.Pending = parts[parts.Length - 1];
                        if (tail.Pending.Length > 8192) { Add(lines, tail.Source, tail.Pending); tail.Pending = ""; }
                    }
                } catch (IOException) { /* A writer can briefly replace/lock its log; retry next tick. */ }
            }
            return lines.ToArray();
        }
        private static void Add(List<LogLine> lines, string source, string text) {
            text = Regex.Replace(text, @"\x1B\[[0-?]*[ -/]*[@-~]", "");
            if (!String.IsNullOrWhiteSpace(text)) lines.Add(new LogLine(source, text));
        }
    }
}
