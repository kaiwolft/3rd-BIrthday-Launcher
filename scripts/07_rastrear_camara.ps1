# The 3rd Birthday - Paso 7: rastrear QUE codigo del juego escribe la camara (para la camara libre)
# Usa el depurador local de PPSSPP (WebSocket en 127.0.0.1) solo durante esta prueba:
#   - 1a vez: activa "RemoteDebuggerOnStartup" en ppsspp.ini y te pide reiniciar el juego.
#   - Pone vigilancia de ESCRITURA en el ojo/objetivo/angulo de la camara, anota que instrucciones (PC) escriben,
#     y para cada una toma una "foto" de los registros de la CPU. Al terminar, desactiva el depurador.
# Resultados: para_claude\camara\rastreo.json y rastreo.txt
param([switch]$Apuntar)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $PSScriptRoot 'logs'
$out  = Join-Path $root 'para_claude\camara'
$ini  = Join-Path $root 'PPSSPP\memstick\PSP\SYSTEM\ppsspp.ini'
$PORT = 45690
$flag = Join-Path $root 'launcher\data\depurador.on'
New-Item -ItemType Directory -Force -Path $logs, $out | Out-Null
Start-Transcript -Path (Join-Path $logs '07_rastrear_camara.log') -Force | Out-Null

function Set-IniGeneral([hashtable]$kv) {
  $lines = [Collections.Generic.List[string]](Get-Content -LiteralPath $ini -Encoding UTF8)
  $g = $lines.FindIndex([Predicate[string]]{ param($l) $l.Trim() -eq '[General]' })
  if ($g -lt 0) { $lines.Insert(0, '[General]'); $g = 0 }
  $end = $lines.FindIndex($g + 1, [Predicate[string]]{ param($l) $l.Trim().StartsWith('[') }); if ($end -lt 0) { $end = $lines.Count }
  foreach ($k in $kv.Keys) {
    $i = -1; for ($j = $g + 1; $j -lt $end; $j++) { if ($lines[$j].Split('=')[0].Trim() -eq $k) { $i = $j; break } }
    if ($i -ge 0) { $lines[$i] = "$k = $($kv[$k])" } else { $lines.Insert($end, "$k = $($kv[$k])"); $end++ }
  }
  [IO.File]::WriteAllLines($ini, $lines, (New-Object Text.UTF8Encoding($false)))
}

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Threading;
using System.Net.WebSockets;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class T3BDbg {
  // ---------- WebSocket sincrono
  static ClientWebSocket ws;
  public static bool Connect(string url) {
    try { ws = new ClientWebSocket(); ws.Options.AddSubProtocol("debugger.ppsspp.org");
      ws.ConnectAsync(new Uri(url), CancellationToken.None).Wait(3000); return ws.State == WebSocketState.Open; } catch { return false; }
  }
  public static void Send(string s) { var b = Encoding.UTF8.GetBytes(s); ws.SendAsync(new ArraySegment<byte>(b), WebSocketMessageType.Text, true, CancellationToken.None).Wait(); }
  static System.Threading.Tasks.Task<WebSocketReceiveResult> pending; static byte[] rbuf = new byte[1 << 20]; static StringBuilder acc = new StringBuilder();
  public static string Recv(int ms) {
    var until = DateTime.Now.AddMilliseconds(ms);
    while (true) {
      if (pending == null) pending = ws.ReceiveAsync(new ArraySegment<byte>(rbuf), CancellationToken.None);
      int left = (int)(until - DateTime.Now).TotalMilliseconds; if (left < 0) left = 0;
      if (!pending.Wait(left)) return null;
      var r = pending.Result; pending = null;
      acc.Append(Encoding.UTF8.GetString(rbuf, 0, r.Count));
      if (r.EndOfMessage) { var s = acc.ToString(); acc.Clear(); return s; }
    }
  }
  public static void Close() { try { ws.Abort(); } catch { } }
  // ---------- memoria por ReadProcessMemory (rapido, para buscar la camara)
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static IntPtr Proc, Wnd; static ulong Base;
  static uint U(IntPtr r) { return (uint)(r.ToInt64() & 0xFFFFFFFF); }
  public static bool Attach() {
    Wnd = FindWindowEx(IntPtr.Zero, IntPtr.Zero, "PPSSPPWnd", null); if (Wnd == IntPtr.Zero) return false;
    uint pid; GetWindowThreadProcessId(Wnd, out pid);
    Base = ((ulong)U(SendMessage(Wnd, 0xB118, IntPtr.Zero, (IntPtr)1)) << 32) | U(SendMessage(Wnd, 0xB118, IntPtr.Zero, IntPtr.Zero));
    Proc = OpenProcess(0x0010 | 0x0400, false, pid); return Base != 0 && Proc != IntPtr.Zero;
  }
  public static bool InGame() { return U(SendMessage(Wnd, 0xB119, IntPtr.Zero, IntPtr.Zero)) != 0; }
  public static byte[] Read(uint a, int n) { var b = new byte[n]; IntPtr r; ReadProcessMemory(Proc, (IntPtr)(long)(Base + a), b, (IntPtr)n, out r); return b; }
  public static float F(uint a) { return BitConverter.ToSingle(Read(a, 4), 0); }
  public static double ViewYaw() { var b = Read(0x08C9B820, 12); return Math.Atan2(BitConverter.ToSingle(b, 0), BitConverter.ToSingle(b, 8)); }
  public static List<uint> Scan() {
    var res = new List<uint>(); uint start = 0x08800000; int size = 0x01800000; byte[] m = Read(start, size);
    for (int o = 0x40; o < size - 0x20; o += 4) {
      float yaw = BitConverter.ToSingle(m, o); if (!(yaw >= -3.2f && yaw <= 3.2f)) continue;
      float dist = BitConverter.ToSingle(m, o + 4); if (!(dist > 50f && dist < 5000f)) continue;
      float fov = BitConverter.ToSingle(m, o + 12); if (!(fov > 0.2f && fov < 1.6f)) continue;
      if (BitConverter.ToSingle(m, o - 0x10) != 1.0f) continue;
      double ex = BitConverter.ToSingle(m, o - 0x34), ey = BitConverter.ToSingle(m, o - 0x30), ez = BitConverter.ToSingle(m, o - 0x2C);
      double tx = BitConverter.ToSingle(m, o - 0x24), ty = BitConverter.ToSingle(m, o - 0x20), tz = BitConverter.ToSingle(m, o - 0x1C);
      double d = Math.Sqrt((ex - tx) * (ex - tx) + (ey - ty) * (ey - ty) + (ez - tz) * (ez - tz));
      if (double.IsNaN(d) || Math.Abs(d - dist) > dist * 0.03) continue;
      res.Add(start + (uint)o);
    }
    return res;
  }
}
"@

$rep = New-Object System.Collections.Generic.List[string]
function Say($s, $c = 'Gray') { Write-Host $s -ForegroundColor $c; $rep.Add($s) }
function Beep([int]$f, [int]$ms) { try { [Console]::Beep($f, $ms) } catch {} }
function Req($obj) { [T3BDbg]::Send(($obj | ConvertTo-Json -Compress -Depth 5)) }
function Restore() { try { Remove-Item $flag -ErrorAction SilentlyContinue; Set-IniGeneral @{ RemoteDebuggerOnStartup = 'False' }; Say 'Depurador de PPSSPP desactivado para la proxima partida.' } catch {} }

Say '=== Rastreo de la camara - The 3rd Birthday ===' 'Red'
if (-not (Test-Path $ini)) { Say "No encuentro $ini (abre el juego una vez desde el launcher)." 'Red'; Stop-Transcript | Out-Null; exit 1 }
# Puertos donde escucha PPSSPP (el depurador puede quedar en un puerto al azar si el 45690 estaba ocupado)
$ports = New-Object System.Collections.Generic.List[int]
$ports.Add($PORT)
$proc = Get-Process -Name 'PPSSPPWindows64', 'PPSSPPWindows' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
  try { Get-NetTCPConnection -State Listen -OwningProcess $proc.Id -ErrorAction Stop | ForEach-Object { if (-not $ports.Contains([int]$_.LocalPort)) { $ports.Add([int]$_.LocalPort) } } }
  catch { netstat -ano | Select-String 'LISTENING' | ForEach-Object { $f = ($_ -split '\s+') | Where-Object { $_ }; if ($f[-1] -eq "$($proc.Id)") { $pt = [int]($f[1] -split ':')[-1]; if (-not $ports.Contains($pt)) { $ports.Add($pt) } } } }
}
try { $iniPort = (Select-String -LiteralPath $ini -Pattern '^\s*RemoteISOPort\s*=\s*(\d+)').Matches[0].Groups[1].Value; if ($iniPort -and -not $ports.Contains([int]$iniPort)) { $ports.Add([int]$iniPort) } } catch {}
$connected = $false
foreach ($pt in $ports) { if ($pt -gt 0 -and [T3BDbg]::Connect("ws://127.0.0.1:$pt/debugger")) { $connected = $true; Say "Conectado al depurador de PPSSPP (puerto $pt)." 'Green'; break } }
if ($proc -and -not $connected) { Say ("PPSSPP esta abierto pero no pude conectar (puertos probados: {0})." -f ($ports -join ', ')) 'Yellow' }
if (-not $connected) {
  Set-IniGeneral @{ RemoteDebuggerOnStartup = 'True'; RemoteISOPort = "$PORT" }
  New-Item -ItemType Directory -Force -Path (Split-Path $flag) | Out-Null; Set-Content $flag 'rastreo de camara en curso'
  Say 'He activado el depurador local de PPSSPP.' 'Yellow'
  Say '  1) CIERRA el juego (PPSSPP) y vuelve a abrirlo desde el launcher (en VENTANA).' 'Yellow'
  Say '  2) Si Windows pregunta por el firewall, puedes darle a CANCELAR: solo se usa en este PC.' 'Yellow'
  Say '  3) Entra a una zona jugable y vuelve a ejecutar este script.' 'Yellow'
  Stop-Transcript | Out-Null; exit 0
}
Req @{ event = 'version'; name = 't3b-launcher'; version = '1.0' }
if (-not [T3BDbg]::Attach()) { Say 'No pude leer la memoria de PPSSPP.' 'Red'; [T3BDbg]::Close(); Restore; Stop-Transcript | Out-Null; exit 1 }

if ($Apuntar) { Say 'Conectado. Pon el juego en primer plano y MANTEN L (apuntar) desde ya y durante toda la prueba. Empiezo en 6 s...' 'Yellow' }
else { Say 'Conectado. Pon el juego en primer plano (en partida, con Aya en una zona abierta). Empiezo en 6 s...' 'Yellow' }
Beep 880 120; Start-Sleep -Seconds 6
while (-not [T3BDbg]::InGame()) { Write-Host '  (juego en pausa: vuelve a la ventana del juego)' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }

$yawNow = [T3BDbg]::ViewYaw()
$cams = @([T3BDbg]::Scan() | Where-Object { [Math]::Abs([T3BDbg]::F($_) - $yawNow) -lt 0.05 })
Say ("Camaras activas: {0}" -f (($cams | ForEach-Object { '0x{0:X8}' -f $_ }) -join ', '))
if ($cams.Count -eq 0) { Say 'No encontre la camara activa.' 'Red'; [T3BDbg]::Close(); Restore; Stop-Transcript | Out-Null; exit 1 }
if ($Apuntar) {
  $d = [T3BDbg]::F($cams[0] + 4)
  if ([Math]::Abs($d - 1000) -gt 1) { Say ("OJO: la camara no esta en modo apuntar (distancia {0:N0}). Manten L apuntando." -f $d) 'Yellow' } else { Say 'Modo apuntar detectado.' 'Green' }
}

# --- fase 1: vigilancia sin pausar (solo anota). Campos: ojo (-0x34, 12 B), objetivo (-0x24, 12 B), inclinacion+angulo (-0x4, 8 B)
$watch = @()
foreach ($c in $cams) { $watch += @{ a = [uint32]($c - 0x34); n = 12; k = 'ojo' }, @{ a = [uint32]($c - 0x24); n = 12; k = 'objetivo' }, @{ a = [uint32]($c - 4); n = 8; k = 'angulos' } }
$fmt = 'PC={pc:x} RA={ra:x} SP={sp:x} A0={a0:x} A1={a1:x} A2={a2:x} S0={s0:x} S1={s1:x} S2={s2:x} S3={s3:x} V0={v0:x}'
foreach ($w in $watch) { Req @{ event = 'memory.breakpoint.add'; address = $w.a; size = $w.n; enabled = $false; log = $true; write = $true; read = $false; change = $false; logFormat = $fmt } }
if ($Apuntar) { Say "`nFASE 1 (10 s): SIGUE APUNTANDO (L) y gira la mira despacio a izquierda y derecha con el stick izquierdo." 'Cyan' }
else { Say "`nFASE 1 (10 s): GIRA a Aya despacio con el stick izquierdo y camina un poco, con el juego en primer plano." 'Cyan' }
Beep 1200 120
$hits = @{}; $raw = New-Object System.Collections.Generic.List[string]
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt 10000) {
  $m = [T3BDbg]::Recv(200); if (-not $m) { continue }
  if ($m -notmatch '"event":"log"') { continue }
  if ($m -match 'CHK (\w+?)(\d+)\(.*?\) at ([0-9a-fA-F]{8}).*?PC=(?:0x)?([0-9a-fA-F]+) RA=(?:0x)?([0-9a-fA-F]+)') {
    $key = ('{0:x8}' -f [Convert]::ToUInt32($matches[4], 16)) + ' ' + $matches[1] + $matches[2] + ' -> ' + $matches[3] + ' (RA ' + $matches[5] + ')'
    if ($hits.ContainsKey($key)) { $hits[$key]++ } else { $hits[$key] = 1; if ($raw.Count -lt 400) { $raw.Add($m) } }
  }
}
foreach ($w in $watch) { Req @{ event = 'memory.breakpoint.remove'; address = $w.a; size = $w.n } }
Start-Sleep -Milliseconds 300; while ([T3BDbg]::Recv(50)) { }
Say ("Escrituras distintas: {0}" -f $hits.Count)
$pcs = @{}
foreach ($k in ($hits.Keys | Sort-Object)) { Say ("  PC {0}  x{1}" -f $k, $hits[$k]); $pcs[$k.Split(' ')[0]] = $k.Split(' ')[3] }

# --- fase 2: para cada instruccion distinta, una pausa breve para leer registros
Say "`nFASE 2: foto de registros por cada instruccion (el juego se pausa un instante varias veces)." 'Cyan'
$regs = @{}
foreach ($pc in ($pcs.Keys | Select-Object -First 24)) {
  $addr = [Convert]::ToUInt32($pcs[$pc], 16)
  Req @{ event = 'cpu.breakpoint.add'; address = [Convert]::ToUInt32($pc, 16); enabled = $true }
  $got = $null; $sw.Restart()
  while ($sw.ElapsedMilliseconds -lt 4000) {
    $m = [T3BDbg]::Recv(200); if (-not $m) { continue }
    if ($m -match '"event":"cpu.stepping"') {
      Req @{ event = 'cpu.getAllRegs' }
      $t2 = [Diagnostics.Stopwatch]::StartNew()
      while ($t2.ElapsedMilliseconds -lt 2000) { $r = [T3BDbg]::Recv(200); if ($r -and $r -match '"event":"cpu.getAllRegs"') { $got = $r; break } }
      break
    }
  }
  Req @{ event = 'cpu.breakpoint.remove'; address = [Convert]::ToUInt32($pc, 16) }
  Req @{ event = 'cpu.resume' }
  Start-Sleep -Milliseconds 150; while ([T3BDbg]::Recv(30)) { }
  if ($got) { $regs[$pc] = ($got | ConvertFrom-Json); Say "  PC $pc : registros OK" 'Green' } else { Say "  PC $pc : no se detuvo (no se volvio a ejecutar)" 'Yellow' }
}
Req @{ event = 'cpu.resume' }

$res = [ordered]@{ fecha = (Get-Date -Format s); camaras = @($cams | ForEach-Object { '0x{0:X8}' -f $_ }); escrituras = $hits; registros = $regs; muestras = $raw }
$nombre = $(if ($Apuntar) { 'rastreo_apuntado' } else { 'rastreo' })
($res | ConvertTo-Json -Depth 8) | Set-Content (Join-Path $out "$nombre.json") -Encoding UTF8
[T3BDbg]::Close()
Restore
$rep | Set-Content (Join-Path $out "$nombre.txt") -Encoding UTF8
Beep 1400 80; Beep 1700 120
Say "`nLISTO. Resultados en para_claude\camara\$nombre.json. Ya puedes avisarle a Claude." 'Green'
Stop-Transcript | Out-Null
