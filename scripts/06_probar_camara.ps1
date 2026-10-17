# The 3rd Birthday - Paso 6: probar la camara libre
# 1) Busca en la RAM las estructuras de camara por su "firma" (ojo, objetivo, inclinacion, angulo, distancia, campo de vision).
# 2) Prueba automatica: escribe un giro en cada copia y mide si la camara que se dibuja gira de verdad.
# 3) Modo libre: mueve la camara con el STICK DERECHO o con el teclado numerico (4/6 girar, 8/2 subir/bajar, 5 = centrar).
# Deja a Aya QUIETA durante la prueba automatica. Resultados en para_claude\camara\prueba_camara.txt
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $PSScriptRoot 'logs'
$out  = Join-Path $root 'para_claude\camara'
New-Item -ItemType Directory -Force -Path $logs, $out | Out-Null
Start-Transcript -Path (Join-Path $logs '06_probar_camara.log') -Force | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class T3BCam {
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
  [StructLayout(LayoutKind.Sequential)] public struct GP { public ushort b; public byte lt; public byte rt; public short lx; public short ly; public short rx; public short ry; }
  [StructLayout(LayoutKind.Sequential)] public struct ST { public uint pkt; public GP gp; }
  [DllImport("xinput1_4.dll")] static extern int XInputGetState(int i, out ST s);

  public static IntPtr Wnd; public static uint Pid; public static ulong Base; static IntPtr Proc;
  public const uint VIEW = 0x08C9B7C0;   // matriz de vista que se dibuja (ES/ULES01513); forward = +0x60/+0x64/+0x68
  static uint U(IntPtr r) { return (uint)(r.ToInt64() & 0xFFFFFFFF); }
  public static bool Connect() {
    Wnd = FindWindowEx(IntPtr.Zero, IntPtr.Zero, "PPSSPPWnd", null);
    if (Wnd == IntPtr.Zero) return false;
    GetWindowThreadProcessId(Wnd, out Pid);
    Base = ((ulong)U(SendMessage(Wnd, 0xB118, IntPtr.Zero, (IntPtr)1)) << 32) | U(SendMessage(Wnd, 0xB118, IntPtr.Zero, IntPtr.Zero));
    Proc = OpenProcess(0x0010 | 0x0020 | 0x0008 | 0x0400, false, Pid);   // READ | WRITE | OPERATION | QUERY
    return Base != 0 && Proc != IntPtr.Zero;
  }
  public static bool InGame() { return U(SendMessage(Wnd, 0xB119, IntPtr.Zero, IntPtr.Zero)) != 0; }
  public static string GameId() {
    var s = new System.Text.StringBuilder();
    for (int i = 0; i < 4; i++) { uint v = U(SendMessage(Wnd, 0xB11A, (IntPtr)i, IntPtr.Zero)); for (int b = 0; b < 4; b++) { char c = (char)((v >> (8 * b)) & 0xFF); if (c != 0) s.Append(c); } }
    return s.ToString();
  }
  public static byte[] Read(uint a, int n) { var b = new byte[n]; IntPtr r; ReadProcessMemory(Proc, (IntPtr)(long)(Base + a), b, (IntPtr)n, out r); return b; }
  public static float F(uint a) { return BitConverter.ToSingle(Read(a, 4), 0); }
  public static void W(uint a, float v) { var b = BitConverter.GetBytes(v); IntPtr w; WriteProcessMemory(Proc, (IntPtr)(long)(Base + a), b, (IntPtr)4, out w); }
  public static double ViewYaw() { var b = Read(VIEW + 0x60, 12); return Math.Atan2(BitConverter.ToSingle(b, 0), BitConverter.ToSingle(b, 8)); }
  public static double ViewPitch() { return Math.Asin(Math.Max(-1, Math.Min(1, F(VIEW + 0x64)))); }
  public static double Wrap(double x) { while (x > Math.PI) x -= 2 * Math.PI; while (x < -Math.PI) x += 2 * Math.PI; return x; }

  // Firma: ojo (-0x34), objetivo (-0x24), 1.0 (-0x10), inclinacion (-0x04), angulo (+0), distancia (+4), campo de vision (+0xC)
  public static List<uint> Scan() {
    var res = new List<uint>();
    uint start = 0x08800000; int size = 0x01800000;
    byte[] m = Read(start, size);
    for (int o = 0x40; o < size - 0x20; o += 4) {
      float yaw = BitConverter.ToSingle(m, o); if (!(yaw >= -3.2f && yaw <= 3.2f)) continue;
      float dist = BitConverter.ToSingle(m, o + 4); if (!(dist > 50f && dist < 5000f)) continue;
      float fov = BitConverter.ToSingle(m, o + 12); if (!(fov > 0.2f && fov < 1.6f)) continue;
      if (BitConverter.ToSingle(m, o - 0x10) != 1.0f) continue;
      float pit = BitConverter.ToSingle(m, o - 4); if (!(pit > -1.6f && pit < 1.6f)) continue;
      double ex = BitConverter.ToSingle(m, o - 0x34), ey = BitConverter.ToSingle(m, o - 0x30), ez = BitConverter.ToSingle(m, o - 0x2C);
      double tx = BitConverter.ToSingle(m, o - 0x24), ty = BitConverter.ToSingle(m, o - 0x20), tz = BitConverter.ToSingle(m, o - 0x1C);
      double d = Math.Sqrt((ex - tx) * (ex - tx) + (ey - ty) * (ey - ty) + (ez - tz) * (ez - tz));
      if (double.IsNaN(d) || Math.Abs(d - dist) > dist * 0.03) continue;
      res.Add(start + (uint)o);
    }
    return res;
  }
  public static void Pad(out double rx, out double ry) {
    rx = 0; ry = 0;
    for (int i = 0; i < 4; i++) { ST s; if (XInputGetState(i, out s) == 0) {
      double x = s.gp.rx / 32767.0, y = s.gp.ry / 32767.0;
      if (Math.Abs(x) > 0.18) rx = x; if (Math.Abs(y) > 0.18) ry = y; break; } }
  }
  public static bool Key(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
}
"@

$rep = New-Object System.Collections.Generic.List[string]
function Say($s, $c = 'Gray') { Write-Host $s -ForegroundColor $c; $rep.Add($s) }
function Beep([int]$f, [int]$ms) { try { [Console]::Beep($f, $ms) } catch {} }

Say '=== Prueba de camara libre - The 3rd Birthday ===' 'Red'
$ok = $false; for ($i = 0; $i -lt 60 -and -not $ok; $i++) { $ok = [T3BCam]::Connect(); if (-not $ok) { Start-Sleep -Milliseconds 500 } }
if (-not $ok) { Say 'ERROR: no encuentro PPSSPP. Abre el juego desde el launcher (en VENTANA) y vuelve a ejecutar.' 'Red'; Stop-Transcript | Out-Null; exit 1 }
Say ("PPSSPP pid {0} | juego {1}" -f [T3BCam]::Pid, [T3BCam]::GameId())
Say 'Pon el juego en primer plano con Aya QUIETA en una zona abierta. La prueba empieza en 5 s...' 'Yellow'
Start-Sleep -Seconds 5
while (-not [T3BCam]::InGame()) { Write-Host '  (el juego esta en pausa: vuelve a la ventana del juego)' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }

$c = [T3BCam]::Scan()
Say ("Estructuras de camara encontradas: {0}" -f $c.Count)
foreach ($a in $c) { Say ("  0x{0:X8}  angulo {1,7:N3}  incl {2,7:N3}  dist {3,7:N1}  fov {4:N3}" -f $a, [T3BCam]::F($a), [T3BCam]::F($a - 4), [T3BCam]::F($a + 4), [T3BCam]::F($a + 12)) }
Say ("Camara dibujada: angulo {0:N3}  incl {1:N3}" -f [T3BCam]::ViewYaw(), [T3BCam]::ViewPitch())
if ($c.Count -eq 0) { Say 'No encontre la camara (estas en una escena, menu o pausa?).' 'Red'; $rep | Set-Content (Join-Path $out 'prueba_camara.txt'); Stop-Transcript | Out-Null; exit 1 }

# --- prueba automatica: +0.6 rad (34 grados) escrito durante 0.5 s en cada copia
Say "`n--- Prueba automatica (no toques nada) ---" 'Cyan'
$best = $null; $bestScore = 0
foreach ($a in $c) {
  if (-not [T3BCam]::InGame()) { Say '  juego en pausa: prueba cancelada' 'Yellow'; break }
  $y0 = [T3BCam]::ViewYaw(); $v0 = [T3BCam]::F($a)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt 500) { [T3BCam]::W($a, [float]([T3BCam]::Wrap($v0 + 0.6))); Start-Sleep -Milliseconds 5 }
  $y1 = [T3BCam]::ViewYaw()
  Start-Sleep -Milliseconds 50; $vAfter = [T3BCam]::F($a)
  Start-Sleep -Milliseconds 1200
  $y2 = [T3BCam]::ViewYaw(); $v2 = [T3BCam]::F($a)
  $d1 = [T3BCam]::Wrap($y1 - $y0); $d2 = [T3BCam]::Wrap($y2 - $y0)
  Say ("  0x{0:X8}: camara giro {1,6:N3} mientras se escribia | 50 ms despues el valor era {2,6:N3} (escrito {3,6:N3}) | 1.2 s despues: giro {4,6:N3}, valor {5,6:N3}" -f $a, $d1, $vAfter, [T3BCam]::Wrap($v0 + 0.6), $d2, $v2)
  if ([Math]::Abs($d1) -gt $bestScore) { $bestScore = [Math]::Abs($d1); $best = $a }
  # devolver la camara a su sitio
  $sw.Restart(); while ($sw.ElapsedMilliseconds -lt 300) { [T3BCam]::W($a, $v0); Start-Sleep -Milliseconds 5 }
  Start-Sleep -Milliseconds 600
}
if ($bestScore -lt 0.2) { Say "`nNinguna copia mueve la camara directamente (el juego la recalcula). Envia este resultado a Claude." 'Yellow' }
else { Say ("`nLa camara la controla 0x{0:X8} (giro medido {1:N2} rad)." -f $best, $bestScore) 'Green' }
$rep | Set-Content (Join-Path $out 'prueba_camara.txt') -Encoding UTF8
Beep 1200 100

# --- modo libre
if ($best) {
  Say "`n--- MODO LIBRE: stick derecho o teclado numerico 4/6/8/2 (5 = soltar). ESC en esta ventana = salir ---" 'Cyan'
  $yawOff = 0.0; $pitOff = 0.0
  $lastWrite = $null; $lastPit = $null
  while ($true) {
    if ([Console]::KeyAvailable) { if ([Console]::ReadKey($true).Key -eq 'Escape') { break } }
    if (-not [T3BCam]::InGame()) { Start-Sleep -Milliseconds 100; continue }
    $rx = 0.0; $ry = 0.0; [T3BCam]::Pad([ref]$rx, [ref]$ry)
    if ([T3BCam]::Key(0x64)) { $rx = -1 }; if ([T3BCam]::Key(0x66)) { $rx = 1 }
    if ([T3BCam]::Key(0x68)) { $ry = 1 };  if ([T3BCam]::Key(0x62)) { $ry = -1 }
    if ([T3BCam]::Key(0x65)) { $yawOff = 0; $pitOff = 0 }
    $yawOff -= $rx * 0.045; $pitOff = [Math]::Max(-0.9, [Math]::Min(0.9, $pitOff + $ry * 0.03))
    # valor del juego: si cambio respecto a lo que escribimos, lo tomamos como nueva base
    $gy = [T3BCam]::F($best); $gp = [T3BCam]::F($best - 4)
    if ($lastWrite -ne $null -and [Math]::Abs($gy - $lastWrite) -lt 0.0001) { $gy = $baseYaw } else { $baseYaw = $gy }
    if ($lastPit -ne $null -and [Math]::Abs($gp - $lastPit) -lt 0.0001) { $gp = $basePit } else { $basePit = $gp }
    if ($yawOff -ne 0 -or $pitOff -ne 0) {
      $lastWrite = [float]([T3BCam]::Wrap($baseYaw + $yawOff)); [T3BCam]::W($best, $lastWrite)
      $lastPit = [float]($basePit + $pitOff); [T3BCam]::W($best - 4, $lastPit)
    } else { $lastWrite = $null; $lastPit = $null }
    Start-Sleep -Milliseconds 8
  }
}
Say 'Fin de la prueba. Ya puedes avisarle a Claude.' 'Green'
$rep | Set-Content (Join-Path $out 'prueba_camara.txt') -Encoding UTF8
Stop-Transcript | Out-Null
