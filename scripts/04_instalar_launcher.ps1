# The 3rd Birthday - Paso 4: instalar el launcher (Electron) reutilizando el motor del launcher de Pandora's Tower
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$lau  = Join-Path $root 'launcher'
$herr = Join-Path $root 'herramientas'
$logs = Join-Path $PSScriptRoot 'logs'
$pt   = 'D:\PROYECTOS\Proyecto Pandoras Tower\launcher'
$exeName = 'The3rdBirthday.exe'
New-Item -ItemType Directory -Force -Path $logs, $herr | Out-Null
Start-Transcript -Path (Join-Path $logs '04_instalar_launcher.log') -Force | Out-Null
try {
  if (Get-Process ($exeName -replace '\.exe$','') -ErrorAction SilentlyContinue) { throw 'Cierra el launcher de The 3rd Birthday antes de seguir.' }
  if (-not (Test-Path (Join-Path $pt 'PandorasTower.exe'))) { throw "No encuentro el launcher de Pandora's Tower en $pt" }

  Write-Host "=== 1. Motor Electron (desde $pt)"
  $n = 0
  Get-ChildItem $pt -File | Where-Object { $_.Name -notin @('PandorasTower.exe') } | ForEach-Object { Copy-Item $_.FullName (Join-Path $lau $_.Name) -Force; $n++ }
  Copy-Item (Join-Path $pt 'PandorasTower.exe') (Join-Path $lau $exeName) -Force
  robocopy (Join-Path $pt 'locales') (Join-Path $lau 'locales') /E /NFL /NDL /NJH /NJS /NP | Out-Null
  Get-ChildItem (Join-Path $pt 'resources') | Where-Object { $_.Name -ne 'app' } | ForEach-Object {
    if ($_.PSIsContainer) { robocopy $_.FullName (Join-Path $lau "resources\$($_.Name)") /E /NFL /NDL /NJH /NJS /NP | Out-Null }
    else { Copy-Item $_.FullName (Join-Path $lau "resources\$($_.Name)") -Force } }
  Write-Host "  $n archivos + $exeName + locales"

  Write-Host "`n=== 2. Tipografias (Google Fonts, licencias OFL/Apache)"
  $fonts = Join-Path $lau 'ui\fonts'
  New-Item -ItemType Directory -Force -Path $fonts | Out-Null
  $lista = @{
    'SpecialElite-Regular.ttf'  = 'apache/specialelite/SpecialElite-Regular.ttf'
    'ShareTechMono-Regular.ttf' = 'ofl/sharetechmono/ShareTechMono-Regular.ttf'
    'Barlow-Regular.ttf'        = 'ofl/barlow/Barlow-Regular.ttf'
    'Barlow-Medium.ttf'         = 'ofl/barlow/Barlow-Medium.ttf'
    'Barlow-SemiBold.ttf'       = 'ofl/barlow/Barlow-SemiBold.ttf'
  }
  foreach ($f in $lista.Keys) {
    $dst = Join-Path $fonts $f
    if ((Test-Path $dst) -and (Get-Item $dst).Length -gt 10KB) { Write-Host "  ya estaba: $f"; continue }
    try { Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/google/fonts/main/" + $lista[$f]) -OutFile $dst -UseBasicParsing -TimeoutSec 60; Write-Host "  OK  $f" }
    catch { Write-Host "  no se pudo bajar $f (se usara una fuente de Windows parecida)" -ForegroundColor Yellow; Remove-Item $dst -ErrorAction SilentlyContinue }
  }

  Write-Host "`n=== 3. Icono y nombre del ejecutable"
  $rc = Join-Path $herr 'rcedit-x64.exe'
  if (-not (Test-Path $rc)) {
    try { Invoke-WebRequest -Uri 'https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe' -OutFile $rc -UseBasicParsing -TimeoutSec 120 }
    catch { Write-Host "  no pude descargar rcedit: $($_.Exception.Message)" -ForegroundColor Yellow }
  }
  if (Test-Path $rc) {
    & $rc (Join-Path $lau $exeName) --set-icon (Join-Path $lau 'ui\assets\icon.ico') `
      --set-version-string 'ProductName' 'The 3rd Birthday' --set-version-string 'FileDescription' "The 3rd Birthday - Dionixu's Launcher" `
      --set-version-string 'CompanyName' 'Dionixu' --set-version-string 'OriginalFilename' $exeName --set-version-string 'InternalName' 'The3rdBirthday'
    if ($LASTEXITCODE -eq 0) { Write-Host '  icono y nombre cambiados' } else { Write-Host "  rcedit termino con codigo $LASTEXITCODE" -ForegroundColor Yellow }
  }

  Write-Host "`n=== 4. Carpetas de mods y del juego"
  $mods = Join-Path $root 'mods'
  New-Item -ItemType Directory -Force -Path $mods, (Join-Path $root 'juego'), (Join-Path $lau 'data') | Out-Null
  $leeme = @"
MODS DE THE 3RD BIRTHDAY
========================
Cada mod es una carpeta dentro de mods\ con un archivo mod.json y una o mas de estas partes:

  textures\      Texturas de reemplazo de PPSSPP (con su textures.ini). Se copian a TEXTURES\<ID>\mods\<mod>
  cheats.ini     Codigos CWCheat (formato de PPSSPP: _C1 Nombre / _L 0x........ 0x........)
  plugin\        Un plugin de PPSSPP (carpeta con plugin.ini y el .prx)
  ppsspp.ini     Ajustes de PPSSPP que el mod necesita (solo las secciones y claves a cambiar)

mod.json de ejemplo:
  { "name": "Mi mod", "description": "Que hace", "author": "Tu nombre", "version": "1.0", "enabled": false }

Los mods se activan o desactivan en el launcher: EXTRAS > MODS. Se aplican solos al iniciar el juego.
Para crear texturas: CONFIGURACION > GRAFICOS > Volcar texturas = SI, juega, y las encontraras en
PPSSPP\memstick\PSP\TEXTURES\<ID>\new\
"@
  Set-Content (Join-Path $mods 'LEEME.txt') $leeme -Encoding UTF8
  Set-Content (Join-Path $root 'juego\LEEME.txt') "Pon aqui tu ISO de The 3rd Birthday (USA ULUS-10567, Europa ULES-01513 o Japon ULJM-05798).`r`nLa version en espanol se crea sola desde la americana o la europea." -Encoding UTF8

  Write-Host "`n=== 5. Comprobando"
  foreach ($f in @($exeName, 'resources\app\main.js', 'resources\app\preload.js', 'resources\app\bridge.ps1', 'ui\index.html', 'ui\exit.html', 'ui\toast.html', 'ui\assets\icon.ico', 'ui\assets\bg_babel.jpg')) {
    if (-not (Test-Path (Join-Path $lau $f))) { throw "Falta: launcher\$f" } }
  foreach ($f in @('PPSSPP\PPSSPPWindows64.exe', 'herramientas\xdelta3.exe', 'parche\receta.json')) {
    if (Test-Path (Join-Path $root $f)) { Write-Host "  OK     $f" } else { Write-Host "  FALTA  $f" -ForegroundColor Yellow } }
  Get-ChildItem (Join-Path $root 'parche') -Filter *.xdelta -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("  OK     parche\{0} ({1:N0} MB)" -f $_.Name, ($_.Length / 1MB)) }

  Write-Host "`n=== 6. Accesos directos"
  $ws = New-Object -ComObject WScript.Shell
  foreach ($dst in @((Join-Path $root 'THE 3RD BIRTHDAY.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) 'The 3rd Birthday.lnk'))) {
    $s = $ws.CreateShortcut($dst)
    $s.TargetPath = Join-Path $lau $exeName
    $s.WorkingDirectory = $lau
    $s.IconLocation = (Join-Path $lau 'ui\assets\icon.ico') + ',0'
    $s.Description = "The 3rd Birthday - Dionixu's Launcher"
    $s.Save(); Write-Host "  $dst"
  }
  Write-Host "`nLISTO. Abre el juego con el acceso directo THE 3RD BIRTHDAY y avisale a Claude."
} catch {
  Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
}
Stop-Transcript | Out-Null
