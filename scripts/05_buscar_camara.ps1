# The 3rd Birthday - Paso 5: buscar la camara en la memoria del juego (para la camara libre)
# Lee la RAM del juego desde PPSSPP (sin red: PPSSPP para Windows entrega la direccion de su memoria
# con el mensaje WM_APP+0x3118, el mismo que usan herramientas como Cheat Engine). Solo LEE, no modifica nada.
# Uso: abre el juego desde el launcher, entra a una zona jugable y ejecuta este script. Pulsa F7 en cada paso.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $PSScriptRoot 'logs'
$out  = Join-Path $root 'para_claude\camara'
New-Item -ItemType Directory -Force -Path $logs, $out | Out-Null
Start-Transcript -Path (Join-Path $logs '05_buscar_camara.log') -Force | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class T3BMem {
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  // Ventana principal de PPSSPP (clase PPSSPPWnd). El null se pasa desde C#: PowerShell lo convertiria en "" y no encontraria nada.
  public static IntPtr FindPPSSPP() { return FindWindowEx(IntPtr.Zero, IntPtr.Zero, "PPSSPPWnd", null); }
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static uint U(IntPtr r) { return (uint)(r.ToInt64() & 0xFFFFFFFF); }
  public static ulong Base(IntPtr h) {
    ulong lo = U(SendMessage(h, 0xB118, IntPtr.Zero, IntPtr.Zero));
    ulong hi = U(SendMessage(h, 0xB118, IntPtr.Zero, (IntPtr)1));
    return (hi << 32) | lo;
  }
  public static bool InGame(IntPtr h) { return U(SendMessage(h, 0xB119, IntPtr.Zero, IntPtr.Zero)) != 0; }
  public static string GameId(IntPtr h) {
    var s = new System.Text.StringBuilder();
    for (int i = 0; i < 4; i++) { uint v = U(SendMessage(h, 0xB11A, (IntPtr)i, IntPtr.Zero)); for (int b = 0; b < 4; b++) { char c = (char)((v >> (8 * b)) & 0xFF); if (c != 0) s.Append(c); } }
    return s.ToString();
  }
  // Copia [psp, psp+size) de la memoria emulada a un archivo. Devuelve los bytes leidos.
  public static long Dump(uint pid, ulong baseAddr, uint psp, int size, string file) {
    IntPtr p = OpenProcess(0x0010 | 0x0400, false, pid);   // VM_READ | QUERY_INFORMATION
    if (p == IntPtr.Zero) throw new Exception("No pude abrir el proceso de PPSSPP (OpenProcess)");
    long total = 0;
    try {
      using (var fs = new FileStream(file, FileMode.Create, FileAccess.Write)) {
        byte[] buf = new byte[1 << 20];
        for (int off = 0; off < size; off += buf.Length) {
          int n = Math.Min(buf.Length, size - off);
          IntPtr got;
          if (!ReadProcessMemory(p, (IntPtr)(long)(baseAddr + psp + (ulong)off), buf, (IntPtr)n, out got)) Array.Clear(buf, 0, n);
          fs.Write(buf, 0, n); total += got.ToInt64();
        }
      }
    } finally { CloseHandle(p); }
    return total;
  }
}
"@

function Beep([int]$f, [int]$ms) { try { [Console]::Beep($f, $ms) } catch {} }

Write-Host '=== Buscador de camara - The 3rd Birthday ===' -ForegroundColor Red
Write-Host 'Buscando PPSSPP...'
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60 -and $h -eq [IntPtr]::Zero; $i++) { $h = [T3BMem]::FindPPSSPP(); if ($h -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 500 } }
if ($h -eq [IntPtr]::Zero) { Write-Host 'ERROR: PPSSPP no esta abierto. Abre el juego desde el launcher y vuelve a ejecutar.' -ForegroundColor Red; Stop-Transcript | Out-Null; exit 1 }
[uint32]$ppid = 0; [void][T3BMem]::GetWindowThreadProcessId($h, [ref]$ppid)
$base = [T3BMem]::Base($h)
$gid = [T3BMem]::GameId($h)
Write-Host ("PPSSPP pid {0} | base 0x{1:X} | juego {2} | en partida: {3}" -f $ppid, $base, $gid, [T3BMem]::InGame($h))
if ($base -eq 0) { Write-Host 'ERROR: PPSSPP no devolvio la direccion de memoria (version demasiado antigua?).' -ForegroundColor Red; Stop-Transcript | Out-Null; exit 1 }

# Memoria de usuario de la PSP: 0x08800000 - 0x0A000000 (24 MB)
$PSP = [uint32]0x08800000; $SIZE = 0x01800000
$pasos = @(
  @('01_quieta',        'Aya QUIETA en una zona abierta. No toques nada.'),
  @('02_quieta_otra',   'Sigue sin tocar NADA (igual que el paso 1).'),
  @('03_derecha_90',    'Gira a Aya unos 90 grados a la DERECHA, espera a que la camara se coloque detras y suelta el stick.'),
  @('04_derecha_180',   'Otros 90 grados a la DERECHA (ya mira al lado contrario que en el paso 1). Suelta el stick.'),
  @('05_como_paso1',    'Vuelve a mirar en la MISMA direccion que en el paso 1. Suelta el stick.'),
  @('06_camina',        'Camina unos pasos HACIA DELANTE sin girar y quedate quieta.'),
  @('07_apunta_frente', 'MANTEN L (apuntar) mirando al frente, sin mover la mira.'),
  @('08_apunta_izq',    'Sigue apuntando y mueve la mira hacia la IZQUIERDA. Quedate quieta apuntando.'),
  @('09_apunta_arriba', 'Sigue apuntando y mira hacia ARRIBA.'),
  @('10_apunta_abajo',  'Sigue apuntando y mira hacia ABAJO.')
)
Write-Host ''
Write-Host 'COMO FUNCIONA:' -ForegroundColor Yellow
Write-Host '  - Pon el juego en VENTANA para poder leer esto (o ten esta ventana en otro monitor).'
Write-Host '  - Haz lo que pide cada paso DENTRO DEL JUEGO y pulsa F7 con el juego en primer plano (si el juego esta en pausa no se guarda).'
Write-Host '  - Un pitido = foto guardada. F6 = repetir el paso anterior. ESC en esta ventana = terminar.'
Write-Host ''
foreach ($p in $pasos) { Write-Host ("  {0}  {1}" -f $p[0].Substring(0,2), $p[1]) }
Write-Host ''

$meta = [ordered]@{ juego = $gid; base = ('0x{0:X}' -f $base); psp_inicio = '0x08800000'; tamano = $SIZE; fecha = (Get-Date -Format s); pasos = @() }
$i = 0; $f7 = $false; $f6 = $false
Write-Host ("PASO {0}: {1}" -f ($i + 1), $pasos[$i][1]) -ForegroundColor Cyan
Beep 880 120
while ($i -lt $pasos.Count) {
  Start-Sleep -Milliseconds 30
  if ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true); if ($k.Key -eq 'Escape') { break } }
  $n7 = ([T3BMem]::GetAsyncKeyState(0x76) -band 0x8000) -ne 0
  $n6 = ([T3BMem]::GetAsyncKeyState(0x75) -band 0x8000) -ne 0
  if ($n6 -and -not $f6 -and $i -gt 0) { $i--; Write-Host ("Repetir -> PASO {0}: {1}" -f ($i + 1), $pasos[$i][1]) -ForegroundColor Cyan; Beep 500 150 }
  if ($n7 -and -not $f7) {
    if (-not [T3BMem]::InGame($h)) { Write-Host '  (el juego no esta en marcha o esta en pausa: vuelve al juego y pulsa F7)' -ForegroundColor Yellow; Beep 300 250 }
    else {
      $file = Join-Path $out ($pasos[$i][0] + '.bin')
      $t = Measure-Command { $got = [T3BMem]::Dump($ppid, $base, $PSP, $SIZE, $file) }
      Write-Host ("  guardado {0} ({1:N0} bytes, {2:N0} ms)" -f (Split-Path -Leaf $file), $got, $t.TotalMilliseconds) -ForegroundColor Green
      $meta.pasos = @($meta.pasos | Where-Object { $_.id -ne $pasos[$i][0] })
      $meta.pasos += ,([ordered]@{ id = $pasos[$i][0]; texto = $pasos[$i][1]; hora = (Get-Date -Format 'HH:mm:ss.fff') })
      Beep 1200 90
      $i++
      if ($i -lt $pasos.Count) { Write-Host ("PASO {0}: {1}" -f ($i + 1), $pasos[$i][1]) -ForegroundColor Cyan }
    }
  }
  $f7 = $n7; $f6 = $n6
}
($meta | ConvertTo-Json -Depth 4) | Set-Content (Join-Path $out 'pasos.json') -Encoding UTF8
Beep 1400 80; Beep 1700 120
Write-Host "`nLISTO ($($meta.pasos.Count) fotos en para_claude\camara). Ya puedes avisarle a Claude." -ForegroundColor Green
Stop-Transcript | Out-Null
