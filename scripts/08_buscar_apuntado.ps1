# The 3rd Birthday - Paso 8: buscar la direccion de APUNTADO de Aya (para mover la camara al apuntar)
# 1) Mientras apuntas (L) y giras DESPACIO a izquierda y derecha, sigue en vivo los valores de memoria que giran igual que la camara.
# 2) Prueba cada candidato escribiendo un giro y midiendo si la camara/mira gira de verdad.
# 3) Busca punteros fijos hacia el mejor candidato.  Resultado: para_claude\camara\apuntado.txt
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $PSScriptRoot 'logs'
$out  = Join-Path $root 'para_claude\camara'
New-Item -ItemType Directory -Force -Path $logs, $out | Out-Null
Start-Transcript -Path (Join-Path $logs '08_buscar_apuntado.log') -Force | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class T3BAim {
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
  static IntPtr Proc, Wnd; static ulong Base;
  public const uint START = 0x08800000; public const int SIZE = 0x01800000;
  static uint U(IntPtr r) { return (uint)(r.ToInt64() & 0xFFFFFFFF); }
  public static bool Attach() {
    Wnd = FindWindowEx(IntPtr.Zero, IntPtr.Zero, "PPSSPPWnd", null); if (Wnd == IntPtr.Zero) return false;
    uint pid; GetWindowThreadProcessId(Wnd, out pid);
    Base = ((ulong)U(SendMessage(Wnd, 0xB118, IntPtr.Zero, (IntPtr)1)) << 32) | U(SendMessage(Wnd, 0xB118, IntPtr.Zero, IntPtr.Zero));
    Proc = OpenProcess(0x0008 | 0x0010 | 0x0020 | 0x0400, false, pid); return Base != 0 && Proc != IntPtr.Zero;
  }
  public static bool InGame() { return U(SendMessage(Wnd, 0xB119, IntPtr.Zero, IntPtr.Zero)) != 0; }
  public static byte[] Read(uint a, int n) { var b = new byte[n]; IntPtr r; ReadProcessMemory(Proc, (IntPtr)(long)(Base + a), b, (IntPtr)n, out r); return b; }
  public static float F(uint a) { return BitConverter.ToSingle(Read(a, 4), 0); }
  public static uint W32(uint a) { return BitConverter.ToUInt32(Read(a, 4), 0); }
  public static void W(uint a, float v) { var b = BitConverter.GetBytes(v); IntPtr w; WriteProcessMemory(Proc, (IntPtr)(long)(Base + a), b, (IntPtr)4, out w); }
  public static double Wrap(double x) { return Math.IEEERemainder(x, 2 * Math.PI); }
  // camara dibujada (matriz de vista ES): forward en 0x08C9B820..828; fov en la estructura no hace falta
  public static double ViewYaw() { var b = Read(0x08C9B820, 12); return Math.Atan2(BitConverter.ToSingle(b, 0), BitConverter.ToSingle(b, 8)); }
  // apuntando = la matriz de proyeccion cambia; usamos la distancia ojo-objetivo de la camara dibujada (1000 al apuntar)
  public static bool Aiming() {
    return AimFlagAddr != 0 && Math.Abs(F(AimFlagAddr) - 1000f) < 1f;
  }
  public static uint AimFlagAddr = 0;
  // estructuras de camara (firma) -> la que coincide con la vista; su distancia (+4) vale 1000 al apuntar
  public static uint FindCamDist() {
    double y = ViewYaw(); byte[] m = Read(START, SIZE);
    for (int o = 0x40; o < SIZE - 0x20; o += 4) {
      float yaw = BitConverter.ToSingle(m, o); if (!(Math.Abs(yaw - y) < 0.01)) continue;
      float dist = BitConverter.ToSingle(m, o + 4); if (!(dist > 50f && dist < 900f)) continue;   // sin apuntar (al apuntar vale 1000)
      float fov = BitConverter.ToSingle(m, o + 12); if (!(fov > 0.2f && fov < 1.6f)) continue;
      if (BitConverter.ToSingle(m, o - 0x10) != 1.0f) continue;
      return START + (uint)o + 4;
    }
    return 0;
  }
  // ---- seguimiento: valores que giran igual (o al reves, en rad o grados) que la camara
  static float[] off; static byte[] mode; static bool[] alive; public static int Alive;
  public static void Begin() {
    double y = ViewYaw(); byte[] m = Read(START, SIZE); int n = SIZE / 4;
    off = new float[n * 4]; mode = new byte[n]; alive = new bool[n]; Alive = 0;
    for (int i = 0; i < n; i++) {
      float v = BitConverter.ToSingle(m, i * 4);
      float av = Math.Abs(v);
      if (float.IsNaN(v) || av > 360f || av < 1e-4f) continue;          // ceros, diminutos y no-angulos fuera
      byte md = 0; if (av <= 6.3f) md |= 3; if (av >= 0.01f) md |= 12; if (md == 0) continue;
      alive[i] = true; Alive++;
      off[i * 4 + 0] = (float)Wrap(v - y); off[i * 4 + 1] = (float)Wrap(v + y);
      off[i * 4 + 2] = (float)Wrap(v * Math.PI / 180 - y); off[i * 4 + 3] = (float)Wrap(v * Math.PI / 180 + y);
      mode[i] = md;
    }
  }
  public static void Step() {
    double y = ViewYaw(); byte[] m = Read(START, SIZE); int n = SIZE / 4; Alive = 0;
    for (int i = 0; i < n; i++) {
      if (!alive[i]) continue;
      float v = BitConverter.ToSingle(m, i * 4);
      if (float.IsNaN(v) || float.IsInfinity(v)) { alive[i] = false; continue; }
      double d = v * Math.PI / 180; byte md = mode[i];
      if ((md & 1) != 0 && Math.Abs(Wrap(v - y - off[i * 4 + 0])) > 0.06) md &= 0xFE;
      if ((md & 2) != 0 && Math.Abs(Wrap(v + y - off[i * 4 + 1])) > 0.06) md &= 0xFD;
      if ((md & 4) != 0 && Math.Abs(Wrap(d - y - off[i * 4 + 2])) > 0.06) md &= 0xFB;
      if ((md & 8) != 0 && Math.Abs(Wrap(d + y - off[i * 4 + 3])) > 0.06) md &= 0xF7;
      mode[i] = md; if (md == 0) alive[i] = false; else Alive++;
    }
  }
  public static List<uint> Survivors(int max) { var r = new List<uint>(); for (int i = 0; i < alive.Length && r.Count < max; i++) if (alive[i]) r.Add(START + (uint)i * 4); return r; }
  public static int Mode(uint a) { return mode[(a - START) / 4]; }
  // copia del angulo dentro de una estructura de camara (no sirve: el juego la recalcula)
  public static bool IsCamCopy(uint a) { float d = F(a + 4), one = F(a - 0x10); return d > 50f && d < 5000f && one == 1.0f; }
  // punteros fijos (zona del ejecutable) que apuntan cerca del candidato
  public static List<string> Pointers(uint a) {
    var r = new List<string>(); byte[] m = Read(0x08804000, 0x004B0000);
    for (int o = 0; o < m.Length; o += 4) { uint p = BitConverter.ToUInt32(m, o); if (p <= a && a - p < 0x800) r.Add(string.Format("0x{0:X8} -> 0x{1:X8} (+0x{2:X})", 0x08804000 + o, p, a - p)); if (r.Count > 30) break; }
    return r;
  }
}
"@

$rep = New-Object System.Collections.Generic.List[string]
function Say($s, $c = 'Gray') { Write-Host $s -ForegroundColor $c; $rep.Add($s) }
function Beep([int]$f, [int]$ms) { try { [Console]::Beep($f, $ms) } catch {} }
function Save { $rep | Set-Content (Join-Path $out 'apuntado.txt') -Encoding UTF8 }

Say '=== Buscar el apuntado - The 3rd Birthday (v2, rapido) ===' 'Red'
$ok = $false; for ($i = 0; $i -lt 60 -and -not $ok; $i++) { $ok = [T3BAim]::Attach(); if (-not $ok) { Start-Sleep -Milliseconds 500 } }
if (-not $ok) { Say 'ERROR: no encuentro PPSSPP. Abre el juego (version Espanol) y vuelve a ejecutar.' 'Red'; Save; Stop-Transcript | Out-Null; exit 1 }
Say 'Pon el juego al frente, en una zona abierta, SIN apuntar todavia. Empiezo en 5 s...' 'Yellow'
Start-Sleep -Seconds 5
while (-not [T3BAim]::InGame()) { Start-Sleep -Milliseconds 300 }
$camDist = [T3BAim]::FindCamDist()
if ($camDist -eq 0) { Say 'No encontre la camara (estas en una escena o menu?).' 'Red'; Save; Stop-Transcript | Out-Null; exit 1 }
[T3BAim]::AimFlagAddr = $camDist
Say ("Camara: distancia en 0x{0:X8} = {1:N1}" -f $camDist, [T3BAim]::F($camDist))

Say "`nAHORA: MANTEN L (apuntar) y gira DESPACIO a la izquierda y a la derecha con el stick izquierdo durante 15 s." 'Cyan'
Beep 1000 150
$t0 = [Diagnostics.Stopwatch]::StartNew()
while (-not [T3BAim]::Aiming() -and $t0.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 50 }
if (-not [T3BAim]::Aiming()) { Say 'No detecte que apuntaras (la distancia de la camara no paso a 1000).' 'Red'; Save; Stop-Transcript | Out-Null; exit 1 }
Say 'Apuntando detectado: siguiendo valores...' 'Green'
[T3BAim]::Begin(); Say ("  candidatos iniciales: {0:N0}" -f [T3BAim]::Alive)
$yMin = [T3BAim]::ViewYaw(); $yMax = $yMin; $prevY = $yMin; $span = 0.0
$aimTime = 0.0; $samples = 0; $last = [Diagnostics.Stopwatch]::StartNew(); $tick = [Diagnostics.Stopwatch]::StartNew()
while ($aimTime -lt 15) {
  $dt = $last.Elapsed.TotalSeconds; $last.Restart()
  if (-not [T3BAim]::Aiming() -or -not [T3BAim]::InGame()) {
    if ($tick.ElapsedMilliseconds -gt 1000) { Write-Host '  (manten L apuntando con el juego al frente)' -ForegroundColor Yellow; $tick.Restart() }
    Start-Sleep -Milliseconds 60; continue
  }
  $sw1 = [Diagnostics.Stopwatch]::StartNew(); [T3BAim]::Step(); $samples++; $aimTime += $dt
  if ($samples -eq 1) { Write-Host ("  primera pasada: {0} ms" -f $sw1.ElapsedMilliseconds) }
  $y = [T3BAim]::ViewYaw(); $span += [Math]::Abs([T3BAim]::Wrap($y - $prevY)); $prevY = $y
  if ($tick.ElapsedMilliseconds -gt 1000) { Write-Host ("  {0,5:N1} s apuntando | giro acumulado {1,5:N2} rad | candidatos {2:N0}" -f $aimTime, $span, [T3BAim]::Alive); $tick.Restart() }
}
Beep 1300 120
Say ("Muestras {0}, giro acumulado {1:N2} rad, candidatos finales {2}" -f $samples, $span, [T3BAim]::Alive)
if ($span -lt 1.0) { Say 'Giraste poco: vuelve a ejecutar y gira mas (izquierda y derecha).' 'Yellow' }
$cands = @([T3BAim]::Survivors(400) | Where-Object { -not [T3BAim]::IsCamCopy($_) } | Select-Object -First 80)
foreach ($a in $cands) { Say ("  0x{0:X8} = {1,10:N4} (modo {2})" -f $a, [T3BAim]::F($a), [T3BAim]::Mode($a)) }

Say "`nPRUEBA: sigue APUNTANDO (manten L) pero SIN mover el stick. Pruebo cada candidato..." 'Cyan'
Beep 1000 150; Start-Sleep -Seconds 3
$best = $null; $bestScore = 0.0
foreach ($a in ($cands | Select-Object -First 60)) {
  while (-not [T3BAim]::Aiming()) { Write-Host '  (manten L para seguir)' -ForegroundColor Yellow; Start-Sleep -Milliseconds 400 }
  $mode = [T3BAim]::Mode($a); $deg = ($mode -band 12) -ne 0 -and ($mode -band 3) -eq 0
  $v0 = [T3BAim]::F($a); $y0 = [T3BAim]::ViewYaw()
  $delta = if ($deg) { 30.0 } else { 0.5 }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt 350) { [T3BAim]::W($a, [float]($v0 + $delta)); Start-Sleep -Milliseconds 5 }
  $y1 = [T3BAim]::ViewYaw(); $vAfter = [T3BAim]::F($a)
  Start-Sleep -Milliseconds 250; $vKeep = [T3BAim]::F($a); $y2 = [T3BAim]::ViewYaw()
  $d = [Math]::Abs([T3BAim]::Wrap($y1 - $y0))
  $keeps = [Math]::Abs($vKeep - ($v0 + $delta)) -lt 0.01
  Say ("  0x{0:X8}: camara giro {1,6:N3} | 250 ms despues: valor {2} | giro mantenido {3,6:N3}" -f $a, $d, $(if ($keeps) { 'SE QUEDA' } else { 'el juego lo cambio' }), [Math]::Abs([T3BAim]::Wrap($y2 - $y0)))
  $score = $d + $(if ($keeps) { 0.3 } else { 0 })
  if ($d -gt 0.15 -and $score -gt $bestScore) { $bestScore = $score; $best = $a }
  # devolver
  $sw.Restart(); while ($sw.ElapsedMilliseconds -lt 200) { [T3BAim]::W($a, $v0); Start-Sleep -Milliseconds 5 }
  Start-Sleep -Milliseconds 200
}
if ($best) {
  Say ("`nEl apuntado lo controla 0x{0:X8} (modo {1})." -f $best, [T3BAim]::Mode($best)) 'Green'
  Say 'Punteros fijos cercanos:'
  foreach ($p in [T3BAim]::Pointers($best)) { Say "  $p" }
} else { Say "`nNinguno movio la camara al escribirlo. Envia este resultado a Claude." 'Yellow' }
Save
Say "`nLISTO. Resultado en para_claude\camara\apuntado.txt. Ya puedes avisarle a Claude." 'Green'
Save
Stop-Transcript | Out-Null
