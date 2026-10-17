# Puente de mando para el launcher de The 3rd Birthday (basado en los de The Last Story y Pandora's Tower)
# - Lee el mando de Xbox (XInput) aunque otra ventana tenga el foco
# - Emite: COMBO (L3+R3, o ESC con el juego en primer plano), BTN A / B / UP / DOWN / LEFT / RIGHT (con repeticion)
# - Acepta por stdin: FOCUS <hwnd>, FOCUSPID <pid>, CLOSEPID <pid>, GAMEPID <pid>
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -TypeDefinition @"
using System;
using System.Threading;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
public static class TLSBridge {
  public static ConcurrentQueue<string> Cmds = new ConcurrentQueue<string>();
  public static void StartReader() {
    var t = new Thread(() => { string l; while ((l = Console.In.ReadLine()) != null) Cmds.Enqueue(l); Cmds.Enqueue("QUIT"); });
    t.IsBackground = true; t.Start();
  }
  [StructLayout(LayoutKind.Sequential)] public struct GP { public ushort b; public byte lt; public byte rt; public short lx; public short ly; public short rx; public short ry; }
  [StructLayout(LayoutKind.Sequential)] public struct ST { public uint pkt; public GP gp; }
  [DllImport("xinput1_4.dll")] public static extern int XInputGetState(int i, out ST s);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadImage(IntPtr inst, string name, uint type, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr SetClassLongPtr(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr h, string t);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  static IntPtr icoBig = IntPtr.Zero, icoSmall = IntPtr.Zero;
  // Ventana principal de PPSSPP (clase PPSSPPWnd) del proceso indicado
  public static IntPtr PPSSPPWindow(uint pid) {
    IntPtr h = IntPtr.Zero;
    while ((h = FindWindowEx(IntPtr.Zero, h, "PPSSPPWnd", null)) != IntPtr.Zero) { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) return h; }
    return IntPtr.Zero;
  }
  // Ventana del juego lista: visible, con tamaño real y PPSSPP en partida (WM_APP+0x3119)
  public static bool GameReady(uint pid) {
    IntPtr h = PPSSPPWindow(pid); if (h == IntPtr.Zero || !IsWindowVisible(h)) return false;
    RECT r; GetWindowRect(h, out r); if (r.R - r.L < 200) return false;
    return (SendMessage(h, 0xB119, IntPtr.Zero, IntPtr.Zero).ToInt64() & 0xFFFFFFFF) != 0;
  }
  // Trae al frente la ventana de PPSSPP (restaura si está minimizada; truco de TOPMOST para saltar el bloqueo de primer plano)
  public static bool ShowGame(uint pid) {
    IntPtr h = PPSSPPWindow(pid); if (h == IntPtr.Zero) return false;
    ShowWindow(h, 9);
    SetWindowPos(h, (IntPtr)(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
    Focus(h);
    SetWindowPos(h, (IntPtr)(-2), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
    return true;
  }
  // ---------- Cámara libre: escribe en la memoria del juego los ángulos que usa la rutina del truco "Camara libre"
  // (datos en 0x08800100: activo, cos/sin del giro, cos/sin de la inclinación). Ver PROYECTO_NOTAS.md.
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  public static class Cam {
    // Cámara "fija en el mundo": al mover el stick/ratón se toma la dirección actual del juego (publicada por la rutina en
    // 0x08800130) y desde ahí se gira; la rutina coloca el ojo en esa dirección conservando la distancia del juego.
    public static bool On; public static uint Pid; public static bool Mouse; public static double Sens = 0.5;
    public static bool InvX, InvY, PadInvY; public static int KUp, KDown, KLeft, KRight, DUp, DDown, DLeft, DRight, KAim;
    static IntPtr proc = IntPtr.Zero, wnd = IntPtr.Zero; static ulong mbase = 0;
    static bool active = false, recenter = false, mouseInit = false, r3Latch = false, r3Combo = false;
    static double yaw = 0, pitch = 0, idle = 0;
    static uint U(IntPtr r) { return (uint)(r.ToInt64() & 0xFFFFFFFF); }
    public static void Start(uint pid) { Pid = pid; On = true; proc = IntPtr.Zero; wnd = IntPtr.Zero; mbase = 0; active = false; recenter = false; mouseInit = false; }
    public static void Stop() { if (On) Write(0, 0, 0); On = false; }
    static bool Attach() {
      if (proc != IntPtr.Zero && wnd != IntPtr.Zero) return true;
      wnd = PPSSPPWindow(Pid); if (wnd == IntPtr.Zero) return false;
      mbase = ((ulong)U(SendMessage(wnd, 0xB118, IntPtr.Zero, (IntPtr)1)) << 32) | U(SendMessage(wnd, 0xB118, IntPtr.Zero, IntPtr.Zero));
      if (mbase == 0) { wnd = IntPtr.Zero; return false; }
      proc = OpenProcess(0x0008 | 0x0010 | 0x0020 | 0x0400, false, Pid);
      return proc != IntPtr.Zero;
    }
    // p = inclinación del ojo alrededor de Aya. Por debajo de PMIN el ojo no baja más (no atraviesa el suelo):
    // lo que sobra se convierte en "mirar arriba" subiendo el punto al que mira la cámara (+0x110).
    const double PMIN = -0.02;
    static double gdist = 400;
    static void Write(int enable, double y, double p) {
      if (!Attach()) return;
      double pe = Math.Max(p, PMIN), lift = p < PMIN ? gdist * Math.Tan(Math.Min(1.1, PMIN - p)) : 0;
      var b = new byte[20];
      BitConverter.GetBytes(enable).CopyTo(b, 0);
      BitConverter.GetBytes((float)(Math.Cos(pe) * Math.Sin(y))).CopyTo(b, 4);
      BitConverter.GetBytes((float)Math.Sin(pe)).CopyTo(b, 8);
      BitConverter.GetBytes((float)(Math.Cos(pe) * Math.Cos(y))).CopyTo(b, 12);
      BitConverter.GetBytes((float)lift).CopyTo(b, 16);
      IntPtr w; WriteProcessMemory(proc, (IntPtr)(long)(mbase + 0x08800100UL), b, (IntPtr)20, out w);
    }
    // dirección que el juego quiere poner (ojo - objetivo), publicada por la rutina cada fotograma
    static bool GameDir(out double gy, out double gp) {
      gy = 0; gp = 0; var b = new byte[12]; IntPtr r;
      if (!ReadProcessMemory(proc, (IntPtr)(long)(mbase + 0x08800130UL), b, (IntPtr)12, out r)) return false;
      double dx = BitConverter.ToSingle(b, 0), dy = BitConverter.ToSingle(b, 4), dz = BitConverter.ToSingle(b, 8);
      double h = Math.Sqrt(dx * dx + dz * dz); if (double.IsNaN(h) || h + Math.Abs(dy) < 1) return false;
      gy = Math.Atan2(dx, dz); gp = Math.Atan2(dy, h); gdist = Math.Sqrt(h * h + dy * dy); return true;
    }
    static double Dz(short v) { double x = v / 32767.0; double a = Math.Abs(x); if (a < 0.2) return 0; return Math.Sign(x) * (a - 0.2) / 0.8; }
    static double Wrap(double a) { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; }
    static bool K(int vk) { return vk != 0 && (GetAsyncKeyState(vk) & 0x8000) != 0; }
    // dt en segundos; stick derecho rx/ry, izquierdo lx/ly; raw = botones XInput reales (sin el stick izquierdo)
    public static void Update(double dt, short rx, short ry, short lx, short ly, ushort raw, byte lt) {
      if (!On || !Attach()) return;
      double gy, gp; bool hasGame = GameDir(out gy, out gp);
      bool fg = ForegroundPid() == Pid;
      // apuntando (LT, LB, clic derecho o su tecla): manda la cámara del juego (el modo apuntar usa otro controlador)
      bool aimNow = lt > 60 || (raw & 0x0100) != 0 || (fg && (K(0x02) || K(KAim)));
      if (aimNow) { active = false; recenter = false; idle = 0; mouseInit = false; Write(0, 0, 0); return; }
      double dyaw = 0, dpit = 0, spd = 1.2 + 2.6 * Sens;                    // rad/s con el stick al máximo
      double sx = Dz(rx), sy = Dz(ry);
      dyaw += sx * spd * dt;                                              // derecha = la vista gira a la derecha
      dpit += sy * spd * 0.7 * dt * (PadInvY ? -1 : 1);                   // eje vertical (invertido respecto a v2, a petición)
      if (fg && Mouse) {
        RECT r; GetClientRect(wnd, out r); var c = new POINT { X = (r.R - r.L) / 2, Y = (r.B - r.T) / 2 }; ClientToScreen(wnd, ref c);
        POINT m; GetCursorPos(out m);
        if (mouseInit) { double k = 0.0010 + 0.0060 * Sens; dyaw += (m.X - c.X) * k; dpit += -(m.Y - c.Y) * k * (InvY ? -1 : 1); }
        SetCursorPos(c.X, c.Y); mouseInit = true;
      } else mouseInit = false;
      if (fg && !Mouse) {
        double ks = spd * dt;
        if (K(KLeft)) dyaw -= ks; if (K(KRight)) dyaw += ks;
        if (K(KUp)) dpit += ks * 0.7 * (InvY ? -1 : 1); if (K(KDown)) dpit -= ks * 0.7 * (InvY ? -1 : 1);
      }
      if (InvX) dyaw = -dyaw;
      // cruceta (mando o sus teclas): es la cámara propia del juego -> se le devuelve el control
      bool dpad = (raw & 0x000F) != 0 || (fg && (K(DUp) || K(DDown) || K(DLeft) || K(DRight)));
      if (dpad) { active = false; recenter = false; idle = 0; }
      // R3 solo (sin L3) = volver detrás de Aya
      bool r3 = (raw & 0x0080) != 0, l3 = (raw & 0x0040) != 0;
      if (r3 && l3) r3Combo = true;
      if (r3) r3Latch = true; else if (r3Latch) { if (!r3Combo && active) recenter = true; r3Latch = false; r3Combo = false; }
      bool input = dyaw != 0 || dpit != 0;
      if (input && !dpad && hasGame) {
        if (!active) { yaw = gy; pitch = gp; active = true; }
        recenter = false; idle = 0;
        // la vista mira hacia -(ojo-objetivo): girar la vista a la derecha = mover el ojo en sentido contrario
        yaw = Wrap(yaw - dyaw); pitch = Math.Max(PMIN - 0.95, Math.Min(1.25, pitch - dpit));   // arriba = mirar arriba
      } else idle += dt;
      // sin tocar la cámara 3 s y caminando: vuelve poco a poco detrás de Aya
      double lm = Math.Sqrt(Dz(lx) * Dz(lx) + Dz(ly) * Dz(ly));
      if (active && idle > 3.0 && lm > 0.3) recenter = true;
      if (active && recenter && hasGame) {
        double f = 1 - Math.Pow(0.08, dt);                                 // ~90% del camino en 1 s
        yaw = Wrap(yaw + Wrap(gy - yaw) * f); pitch += (gp - pitch) * f;
        if (Math.Abs(Wrap(gy - yaw)) < 0.02 && Math.Abs(gp - pitch) < 0.02) { active = false; recenter = false; }
      }
      Write(active ? 1 : 0, yaw, pitch);
    }
  }
  // Pone el icono y el título del juego (PPSSPP cambia el título solo, por eso se repite cada segundo)
  public static bool Skin(uint pid, string ico, string title) {
    IntPtr h = PPSSPPWindow(pid); if (h == IntPtr.Zero) return false;
    if (icoBig == IntPtr.Zero) { icoBig = LoadImage(IntPtr.Zero, ico, 1, 256, 256, 0x10); icoSmall = LoadImage(IntPtr.Zero, ico, 1, 32, 32, 0x10); }
    if (icoBig != IntPtr.Zero) {
      if (SendMessage(h, 0x007F, (IntPtr)1, IntPtr.Zero) != icoBig) { SendMessage(h, 0x0080, (IntPtr)1, icoBig); SetClassLongPtr(h, -14, icoBig); }
      if (SendMessage(h, 0x007F, IntPtr.Zero, IntPtr.Zero) != icoSmall) { SendMessage(h, 0x0080, IntPtr.Zero, icoSmall); SetClassLongPtr(h, -34, icoSmall); }
    }
    var sb = new System.Text.StringBuilder(512); GetWindowText(h, sb, 512);
    if (sb.ToString() != title) SetWindowText(h, title);
    return true;
  }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  // Ventana sin bordes: la ventana visible mas grande del proceso (la del juego) sin marco y centrada
  public static bool Borderless(uint pid, int w, int h) {
    IntPtr best = IntPtr.Zero; long area = 0;
    EnumWindows((hw, l) => {
      uint p; GetWindowThreadProcessId(hw, out p);
      if (p == pid && IsWindowVisible(hw)) { RECT r; GetWindowRect(hw, out r); long a = (long)(r.R - r.L) * (r.B - r.T); if (a > area) { area = a; best = hw; } }
      return true; }, IntPtr.Zero);
    if (best == IntPtr.Zero) return false;
    long st = (long)GetWindowLongPtr(best, -16);
    st &= ~(0x00C00000L | 0x00040000L | 0x00080000L | 0x00020000L | 0x00010000L);   // sin titulo, borde, menu, minimizar, maximizar
    SetWindowLongPtr(best, -16, (IntPtr)st);
    long ex = (long)GetWindowLongPtr(best, -20);
    ex &= ~(0x00000001L | 0x00000200L | 0x00020000L | 0x00000100L);                  // sin bordes extendidos
    SetWindowLongPtr(best, -20, (IntPtr)ex);
    int sw = GetSystemMetrics(0), sh = GetSystemMetrics(1);
    if (w > sw || h > sh) { w = sw; h = sh; }
    SetWindowPos(best, IntPtr.Zero, (sw - w) / 2, (sh - h) / 2, w, h, 0x0020 | 0x0040 | 0x0004);   // FRAMECHANGED | SHOWWINDOW | NOZORDER
    return true;
  }
  public static uint ForegroundPid() { uint p = 0; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; }
  public static void Focus(IntPtr h) {
    if (h == IntPtr.Zero) return;
    keybd_event(0x12, 0, 0, UIntPtr.Zero);       // Alt: permite tomar el primer plano
    ShowWindow(h, 5); BringWindowToTop(h); SetForegroundWindow(h);
    keybd_event(0x12, 0, 2, UIntPtr.Zero);
  }
}
"@

# --- Volumen en vivo: volumen de Dolphin en el mezclador de Windows (Core Audio). Bloque aparte:
#     si no compila, el resto del puente sigue funcionando y el launcher usa el volumen de Dolphin.
$audioOk = $false
try {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace TLSAudio {
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo { }
  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
  }
  [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
  }
  [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionManager2 {
    [PreserveSig] int GetAudioSessionControl(IntPtr guid, int flags, out IntPtr ctl);
    [PreserveSig] int GetSimpleAudioVolume(IntPtr guid, int flags, out IntPtr vol);
    [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
  }
  [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionEnumerator {
    [PreserveSig] int GetCount(out int count);
    [PreserveSig] int GetSession(int index, out IAudioSessionControl2 session);
  }
  [Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionControl2 {
    [PreserveSig] int GetState(out int state);
    [PreserveSig] int GetDisplayName(out IntPtr name);
    [PreserveSig] int SetDisplayName(IntPtr name, IntPtr ctx);
    [PreserveSig] int GetIconPath(out IntPtr path);
    [PreserveSig] int SetIconPath(IntPtr path, IntPtr ctx);
    [PreserveSig] int GetGroupingParam(out Guid g);
    [PreserveSig] int SetGroupingParam(IntPtr g, IntPtr ctx);
    [PreserveSig] int RegisterAudioSessionNotification(IntPtr n);
    [PreserveSig] int UnregisterAudioSessionNotification(IntPtr n);
    [PreserveSig] int GetSessionIdentifier(out IntPtr id);
    [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
    [PreserveSig] int GetProcessId(out uint pid);
  }
  [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface ISimpleAudioVolume {
    [PreserveSig] int SetMasterVolume(float level, ref Guid ctx);
    [PreserveSig] int GetMasterVolume(out float level);
  }
  public static class Mixer {
    // Devuelve cuantas sesiones de audio del proceso se ajustaron (0 = aun no suena nada)
    public static int SetVolume(uint pid, float level) {
      int done = 0;
      try {
        IMMDeviceEnumerator en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorCo());
        IMMDevice dev;
        if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null) return 0;
        Guid iid = typeof(IAudioSessionManager2).GUID;
        object o;
        if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0 || o == null) return 0;
        IAudioSessionManager2 mgr = (IAudioSessionManager2)o;
        IAudioSessionEnumerator list;
        if (mgr.GetSessionEnumerator(out list) != 0 || list == null) return 0;
        int n; list.GetCount(out n);
        for (int i = 0; i < n; i++) {
          IAudioSessionControl2 ctl;
          if (list.GetSession(i, out ctl) != 0 || ctl == null) continue;
          uint p; ctl.GetProcessId(out p);
          if (p != pid) continue;
          ISimpleAudioVolume v = ctl as ISimpleAudioVolume;
          if (v == null) continue;
          Guid g = Guid.Empty;
          if (v.SetMasterVolume(level, ref g) == 0) done++;
        }
      } catch { }
      return done;
    }
  }
}
"@
  $audioOk = $true
} catch { $audioOk = $false }

[void][TLSBridge]::SetProcessDPIAware()   # coordenadas reales de pantalla (escalado de Windows)
[TLSBridge]::StartReader()
$prev = 0
$lastT = [DateTime]::Now
$comboLatch = $false
$gamePid = 0
$rep = @{ 1 = 0; 2 = 0; 4 = 0; 8 = 0 }
$f1Latch = $false
[Console]::Out.WriteLine('READY'); if ($audioOk) { [Console]::Out.WriteLine('AUDIO OK') } else { [Console]::Out.WriteLine('AUDIO NO') }; [Console]::Out.Flush()
$volPid = 0; $volTarget = -1; $volTick = 0; $volDone = $false
$skinPid = 0; $skinTick = 0
$waitPid = 0; $waitT0 = [DateTime]::Now
$skinIco = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\ui\assets\icon.ico'))

while ($true) {
  # --- comandos del launcher (sin bloquear)
  $line = $null
  while ([TLSBridge]::Cmds.TryDequeue([ref]$line)) {
    $p = $line.Split(' ')
    switch ($p[0]) {
      'FOCUS'    { [TLSBridge]::Focus([IntPtr][long]$p[1]) }
      'FOCUSPID' { if (-not [TLSBridge]::ShowGame([uint32]$p[1])) { $pr = Get-Process -Id ([int]$p[1]); if ($pr) { [TLSBridge]::Focus($pr.MainWindowHandle) } } }
      'WAITWIN'  { $waitPid = [uint32]$p[1]; $waitT0 = [DateTime]::Now }
      'CLOSEPID' { $pr = Get-Process -Id ([int]$p[1]); if ($pr) { [void]$pr.CloseMainWindow() } }
      'GAMEPID'  { $gamePid = [uint32]$p[1] }
      'VOLUME'   { $volPid = [uint32]$p[1]; $volTarget = [int]$p[2]; $volTick = 0; $volDone = $false }
      'BORDERLESS' { [void][TLSBridge]::Borderless([uint32]$p[1], [int]$p[2], [int]$p[3]) }
      'SKIN'     { $skinPid = [uint32]$p[1]; $skinTick = 0 }
      # FREECAM <pid> <raton 0/1> <sens 0-100> <invX> <invY raton/teclas> <invY stick> <vkArriba> <vkAbajo> <vkIzq> <vkDer>
      'FREECAM'  { [TLSBridge+Cam]::Mouse = ($p[2] -eq '1'); [TLSBridge+Cam]::Sens = [double]$p[3] / 100.0
                   [TLSBridge+Cam]::InvX = ($p[4] -eq '1'); [TLSBridge+Cam]::InvY = ($p[5] -eq '1'); [TLSBridge+Cam]::PadInvY = ($p[6] -eq '1')
                   [TLSBridge+Cam]::KUp = [int]$p[7]; [TLSBridge+Cam]::KDown = [int]$p[8]; [TLSBridge+Cam]::KLeft = [int]$p[9]; [TLSBridge+Cam]::KRight = [int]$p[10]
                   if ($p.Count -ge 15) { [TLSBridge+Cam]::DUp = [int]$p[11]; [TLSBridge+Cam]::DDown = [int]$p[12]; [TLSBridge+Cam]::DLeft = [int]$p[13]; [TLSBridge+Cam]::DRight = [int]$p[14] }
                   if ($p.Count -ge 16) { [TLSBridge+Cam]::KAim = [int]$p[15] }
                   [TLSBridge+Cam]::Start([uint32]$p[1]) }
      'FREECAMOFF' { [TLSBridge+Cam]::Stop() }
      'QUIT'     { [TLSBridge+Cam]::Stop(); exit 0 }
    }
  }
  # --- esperar a que la ventana del juego este lista (minimo 1 s para que PPSSPP termine de colocarla)
  if ($waitPid -ne 0 -and ([DateTime]::Now - $waitT0).TotalMilliseconds -gt 1000) {
    $ok = $false; try { $ok = [TLSBridge]::GameReady($waitPid) } catch {}
    if ($ok) { [Console]::Out.WriteLine('GAMEWIN'); $waitPid = 0 }
  }
  # --- icono y titulo del juego en la ventana de PPSSPP
  if ($skinPid -ne 0) { $skinTick--; if ($skinTick -le 0) { try { [void][TLSBridge]::Skin($skinPid, $skinIco, 'The 3rd Birthday') } catch {}; $skinTick = 33 } }
  # --- volumen en vivo
  if ($audioOk -and $volTarget -ge 0 -and $volPid -ne 0) {
    $volTick--
    if ($volTick -le 0) {
      $n = [TLSAudio.Mixer]::SetVolume($volPid, [float]($volTarget / 100.0))
      if ($n -gt 0 -and -not $volDone) { [Console]::Out.WriteLine('VOLSET ' + $volTarget); $volDone = $true }
      $volTick = 33
    }
  }
  # --- mando
  $b = 0; $craw = 0; $crx = 0; $cry = 0; $clx = 0; $cly = 0; $clt = 0; $cpad = $false
  for ($i = 0; $i -lt 4; $i++) {
    $s = New-Object TLSBridge+ST
    if ([TLSBridge]::XInputGetState($i, [ref]$s) -eq 0) {
      if (-not $cpad) { $crx = $s.gp.rx; $cry = $s.gp.ry; $clx = $s.gp.lx; $cly = $s.gp.ly; $clt = $s.gp.lt; $cpad = $true }
      $b = $b -bor $s.gp.b; $craw = $craw -bor $s.gp.b
      if ($s.gp.lx -lt -20000) { $b = $b -bor 0x0004 }
      if ($s.gp.lx -gt 20000)  { $b = $b -bor 0x0008 }
      if ($s.gp.ly -gt 20000)  { $b = $b -bor 0x0001 }
      if ($s.gp.ly -lt -20000) { $b = $b -bor 0x0002 }
    }
  }
  $both = (($b -band 0x00C0) -eq 0x00C0)
  if ($both -and -not $comboLatch) { [Console]::Out.WriteLine('COMBO'); $comboLatch = $true }
  if (-not $both) { $comboLatch = $false }
  # teclado: ESC con el juego delante = abrir la pausa del launcher (START del juego = ENTER)
  $f1 = (([TLSBridge]::GetAsyncKeyState(0x1B) -band 0x8000) -ne 0)
  if ($f1 -and -not $f1Latch -and $gamePid -ne 0 -and [TLSBridge]::ForegroundPid() -eq $gamePid) { [Console]::Out.WriteLine('COMBO KB') }
  $f1Latch = $f1
  $new = $b -band (-bnot $prev)
  # posicion PlayStation (occidente): aceptar = boton de abajo (A de Xbox), volver = boton derecho (B de Xbox)
  if ($new -band 0x1000) { [Console]::Out.WriteLine('BTN A') }
  if ($new -band 0x2000) { [Console]::Out.WriteLine('BTN B') }
  # direcciones: al pulsar y, si se mantienen, repetición (para mover la barra de volumen)
  $dirs = @(@(0x0001, 'UP'), @(0x0002, 'DOWN'), @(0x0004, 'LEFT'), @(0x0008, 'RIGHT'))
  foreach ($d in $dirs) {
    $m = $d[0]
    if ($new -band $m) { [Console]::Out.WriteLine('BTN ' + $d[1]); $rep[$m] = 14 }
    elseif ($b -band $m) { $rep[$m]--; if ($rep[$m] -le 0) { [Console]::Out.WriteLine('BTN ' + $d[1]); $rep[$m] = 4 } }
  }
  [Console]::Out.Flush()
  $prev = $b
  # --- camara libre (60 Hz)
  $nowT = [DateTime]::Now; $dt = ($nowT - $lastT).TotalSeconds; $lastT = $nowT; if ($dt -gt 0.1) { $dt = 0.1 }
  if ([TLSBridge+Cam]::On) { try { [TLSBridge+Cam]::Update($dt, [int16]$crx, [int16]$cry, [int16]$clx, [int16]$cly, [uint16]$craw, [byte]$clt) } catch {}; Start-Sleep -Milliseconds 14 }
  else { Start-Sleep -Milliseconds 30 }
}
