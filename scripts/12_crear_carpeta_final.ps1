# The 3rd Birthday - Paso 12: carpeta final portatil (launcher + PPSSPP + juego) en
#   F:\Juegos de DIonis Con launcher personalizado\The 3rd Birthday (Dionixu's Launcher)   (si no hay disco F:, usa E:)
# - Copia: launcher, PPSSPP (con tus partidas y ajustes), xdelta3, parche, version en espanol ya creada (cache),
#   tus ISOs (americana y japonesa) en juego\, mods, arte y scripts de Steam.
# - No copia: registros, cache de Chromium, volcados de texturas (TEXTURES\*\new), cache de shaders.
# - Agrega The 3rd Birthday al AGREGAR_A_STEAM de la carpeta de arriba (arte en steam_arte\t3b_*.png).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$disco = if (Test-Path 'F:\') { 'F' } elseif (Test-Path 'E:\') { 'E' } else { $null }
$base = "${disco}:\Juegos de DIonis Con launcher personalizado"
$dst  = Join-Path $base "The 3rd Birthday (Dionixu's Launcher)"
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'logs') | Out-Null
Start-Transcript -Path (Join-Path $PSScriptRoot 'logs\12_carpeta_final.log') -Force | Out-Null
function RC($src, $to, [string[]]$xd = @(), [string[]]$xf = @()) {
  $a = @($src, $to, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/MT:8')
  if ($xd.Count) { $a += '/XD'; $a += $xd }
  if ($xf.Count) { $a += '/XF'; $a += $xf }
  & robocopy @a | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy fallo copiando $src (codigo $LASTEXITCODE)" }
}
try {
  $usa = Join-Path $root 'originales\3rd Birthday, The (USA).iso'
  $jap = Join-Path $root '3rd Birthday, The (Japan).iso'
  foreach ($f in @('launcher\The3rdBirthday.exe', 'launcher\resources\app\main.js', 'PPSSPP\PPSSPPWindows64.exe', 'herramientas\xdelta3.exe',
                   'parche\T3B_ES_desde_ULUS10567.xdelta', 'parche\receta.json', 'steam\AGREGAR_A_STEAM.ps1')) {
    if (-not (Test-Path (Join-Path $root $f))) { throw "Falta $f" } }
  if (Get-Process -Name The3rdBirthday, PPSSPPWindows64 -ErrorAction SilentlyContinue) { throw 'Cierra el launcher y el juego antes de continuar.' }
  if (-not $disco) { throw 'No encuentro el disco F: (ni E:)' }
  Write-Host ("Destino: {0}`nEspacio libre en ${disco}: {1:N1} GB (se necesitan unos 5 GB)`n" -f $dst, ((Get-PSDrive $disco).Free / 1GB))
  New-Item -ItemType Directory -Force -Path $dst | Out-Null

  Write-Host '=== 1. Launcher'
  $L = Join-Path $root 'launcher'
  RC $L (Join-Path $dst 'launcher') @((Join-Path $L 'data\chromium')) @('*.log', 'depurador.on', 'isos.json', 'ui_firma.txt')

  Write-Host '=== 2. PPSSPP (partidas, ajustes, texturas de botones)'
  $P = Join-Path $root 'PPSSPP'
  $xd = @((Join-Path $P 'memstick\PSP\PPSSPP_STATE\shaders'), (Join-Path $P 'memstick\PSP\SYSTEM\CACHE'), (Join-Path $P 'memstick\PSP\SYSTEM\DUMP'))
  Get-ChildItem (Join-Path $P 'memstick\PSP\TEXTURES') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $xd += (Join-Path $_.FullName 'new') }
  RC $P (Join-Path $dst 'PPSSPP') $xd @('*.log')

  Write-Host '=== 3. Herramientas, parche y mods'
  RC (Join-Path $root 'herramientas') (Join-Path $dst 'herramientas') @((Join-Path $root 'herramientas\texturas'), (Join-Path $root 'herramientas\camara'))
  RC (Join-Path $root 'parche') (Join-Path $dst 'parche') @((Join-Path $root 'parche\partes'))
  New-Item -ItemType Directory -Force -Path (Join-Path $dst 'mods'), (Join-Path $dst 'cache'), (Join-Path $dst 'juego') | Out-Null
  if (Test-Path (Join-Path $root 'mods')) { RC (Join-Path $root 'mods') (Join-Path $dst 'mods') }

  Write-Host '=== 4. Juego: tus ISOs y la version en espanol ya creada'
  $isos = @()
  # solo los archivos de las ISOs (sin /E: no se copia la carpeta que las contiene)
  foreach ($i in @($usa, $jap)) {
    if (Test-Path -LiteralPath $i) { & robocopy (Split-Path $i) (Join-Path $dst 'juego') (Split-Path $i -Leaf) /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
      Write-Host "  $(Split-Path $i -Leaf)"; $isos += (Join-Path $dst ('juego\' + (Split-Path $i -Leaf))) }
  }
  $es = Join-Path $root 'cache\T3B_ES.iso'
  if (Test-Path $es) { & robocopy (Join-Path $root 'cache') (Join-Path $dst 'cache') 'T3B_ES.iso' /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null; $isos += (Join-Path $dst 'cache\T3B_ES.iso'); Write-Host '  T3B_ES.iso (espanol UNDUB)' }
  # huellas MD5 ya calculadas (asi el launcher no vuelve a leer 4 GB): mismas fechas y tamanos que el original
  $old = @{}
  try { (Get-Content (Join-Path $L 'data\isos.json') -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $old[(Split-Path $_.Name -Leaf).ToLower()] = $_.Value } } catch {}
  $new = [ordered]@{}
  foreach ($i in $isos) { $o = $old[(Split-Path $i -Leaf).ToLower()]; $fi = Get-Item -LiteralPath $i
    if ($o -and $o.size -eq $fi.Length) { $new[$i.ToLower()] = [ordered]@{ size = $fi.Length; mtime = $o.mtime; md5 = $o.md5 } } }
  ($new | ConvertTo-Json) | Set-Content (Join-Path $dst 'launcher\data\isos.json') -Encoding UTF8

  Write-Host "`n=== 5. Steam, accesos directos y LEEME"
  RC (Join-Path $root 'steam\arte') (Join-Path $dst 'steam\arte')
  foreach ($f in @('AGREGAR_A_STEAM.bat', 'AGREGAR_A_STEAM.ps1', 'agregar_a_steam.sh', 'agregar_a_steam.py', 'LEEME - README.txt')) {
    if (Test-Path (Join-Path $root "steam\$f")) { Copy-Item (Join-Path $root "steam\$f") (Join-Path $dst $f) -Force } }
  # arte para el AGREGAR_A_STEAM general de la carpeta de arriba
  $sa = Join-Path $base 'steam_arte'; New-Item -ItemType Directory -Force -Path $sa | Out-Null
  foreach ($k in @('p', 'wide', 'hero', 'logo')) { Copy-Item (Join-Path $root "steam\arte\$k.png") (Join-Path $sa "t3b_$k.png") -Force }
  $act = @'
@echo off
set "T3ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$r=$env:T3ROOT.TrimEnd('\'); $l=Join-Path $r 'launcher'; $ws=New-Object -ComObject WScript.Shell; foreach($d in @((Join-Path $r 'THE 3RD BIRTHDAY.lnk'),(Join-Path ([Environment]::GetFolderPath('Desktop')) 'The 3rd Birthday.lnk'))){ $s=$ws.CreateShortcut($d); $s.TargetPath=Join-Path $l 'The3rdBirthday.exe'; $s.WorkingDirectory=$l; $s.IconLocation=(Join-Path $l 'ui\assets\icon.ico')+',0'; $s.Description='The 3rd Birthday - Dionixu''s Launcher'; $s.Save() }; Write-Host 'Accesos directos actualizados.'"
pause
'@
  Set-Content -LiteralPath (Join-Path $dst 'ACTUALIZAR ACCESOS DIRECTOS.bat') -Value $act -Encoding ASCII
  $leeme = @"
THE 3RD BIRTHDAY - DIONIXU'S LAUNCHER
=====================================
Abrir el juego: THE 3RD BIRTHDAY (acceso directo) o launcher\The3rdBirthday.exe

Esta carpeta es portatil: muevela a donde quieras (otro disco, otra PC).
Despues de moverla, ejecuta "ACTUALIZAR ACCESOS DIRECTOS.bat" y, si lo tienes en Steam,
vuelve a ejecutar AGREGAR_A_STEAM.bat (en esta carpeta o en la de arriba).

Contenido
  launcher\      Launcher (ajustes en launcher\data\config.json)
  PPSSPP\        Emulador portable: partidas en memstick\PSP\SAVEDATA, texturas HD y botones en memstick\PSP\TEXTURES
  juego\         Tus ISOs: americana (ingles) y japonesa
  cache\         T3B_ES.iso: version en espanol con voces japonesas (creada con el parche)
  parche\        Parche al espanol (por si borras cache\)
  herramientas\  xdelta3
  mods\          Tus mods (texturas, trucos, ajustes)

En el juego: ESC o L3 + R3 = menu de pausa (volver al launcher). F12 = menu de PPSSPP.
"@
  Set-Content -LiteralPath (Join-Path $dst 'LEEME.txt') -Value $leeme -Encoding UTF8
  $ws = New-Object -ComObject WScript.Shell
  $lau = Join-Path $dst 'launcher'
  foreach ($d in @((Join-Path $dst 'THE 3RD BIRTHDAY.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) 'The 3rd Birthday.lnk'))) {
    $s = $ws.CreateShortcut($d); $s.TargetPath = Join-Path $lau 'The3rdBirthday.exe'; $s.WorkingDirectory = $lau
    $s.IconLocation = (Join-Path $lau 'ui\assets\icon.ico') + ',0'; $s.Description = "The 3rd Birthday - Dionixu's Launcher"; $s.Save()
    Write-Host "  $d" }

  $size = (Get-ChildItem -LiteralPath $dst -Recurse -File -Force | Measure-Object Length -Sum).Sum
  Write-Host ("`nLISTO: {0}`nTamano: {1:N1} GB" -f $dst, ($size / 1GB))
  Write-Host "`nPara agregarlo a Steam con su arte: ejecuta '$base\AGREGAR_A_STEAM.bat' (agrega todos tus juegos) o el AGREGAR_A_STEAM.bat de la carpeta del juego."
} catch {
  Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
}
Stop-Transcript | Out-Null
Read-Host 'Presiona Enter para cerrar'
