# The 3rd Birthday - Paso 3: crear el parche nativo al espanol (xdelta) a partir de tus ISOs originales
# Pon tu ISO original americana (ULUS-10567) y/o europea (ULES-01513) en la carpeta "originales\".
# Resultado: parche\T3B_ES_desde_<DISC_ID>.xdelta + parche\receta.json (lo que usara el launcher).
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$root  = Split-Path -Parent $PSScriptRoot
$logs  = Join-Path $PSScriptRoot 'logs'
$herr  = Join-Path $root 'herramientas'
$orig  = Join-Path $root 'originales'
$par   = Join-Path $root 'parche'
$tmp   = Join-Path $root 'cache'
$pc    = Join-Path $root 'para_claude'
New-Item -ItemType Directory -Force -Path $logs, $herr, $orig, $par, $tmp, $pc | Out-Null
Start-Transcript -Path (Join-Path $logs '03_crear_parche.log') -Force | Out-Null

# Volcados conocidos (Redump, tomados de PPSSPP\assets\redump.csv)
$conocidas = @{
  '47A7CB8E9E73D8AABEF8139DB7EE522B' = @{ id = 'ULUS10567'; region = 'USA (original)' }
  'D7C2309DA1FB349B8DFCE11F1B6C90A7' = @{ id = 'ULES01513'; region = 'Europa (original)' }
  '688CC34138A19441044BCE3D3A4C429B' = @{ id = 'ULJM05798'; region = 'Japon (original, v1.01)' }
  'C0E56A15C0D92450BDB1BE09426B7300' = @{ id = 'ES_UNDUB'; region = 'Espanol parcheado (UNDUB, base ULES01513)' }
}

# 1) xdelta3 (portable, dentro del proyecto)
$xd = Join-Path $herr 'xdelta3.exe'
if (-not (Test-Path $xd)) {
  $zip = Join-Path $herr 'xdelta3.zip'
  $urls = @('https://github.com/jmacd/xdelta-gpl/releases/download/v3.1.0/xdelta3-3.1.0-x86_64.exe.zip')
  try {
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/jmacd/xdelta-gpl/releases' -Headers @{ 'User-Agent' = 'T3B-Launcher' } -TimeoutSec 30
    $urls += ($rel | ForEach-Object { $_.assets } | Where-Object { $_.name -match 'x86_64\.exe\.zip$' } | Select-Object -ExpandProperty browser_download_url)
  } catch { Write-Host "No pude consultar GitHub (sigo con la URL conocida)." }
  foreach ($u in ($urls | Select-Object -Unique)) {
    Write-Host "Descargando xdelta3: $u"
    try { Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -TimeoutSec 300; break } catch { Write-Host "  fallo: $($_.Exception.Message)" }
  }
  if (Test-Path $zip) {
    $tx = Join-Path $herr 'xdelta_tmp'
    Expand-Archive -LiteralPath $zip -DestinationPath $tx -Force
    $exe = Get-ChildItem $tx -Recurse -Filter *.exe | Select-Object -First 1
    if ($exe) { Move-Item $exe.FullName $xd -Force }
    Remove-Item $tx, $zip -Recurse -Force -ErrorAction SilentlyContinue
  }
}
if (-not (Test-Path $xd)) { Write-Host "ERROR: no tengo xdelta3.exe. Descargalo de https://github.com/jmacd/xdelta-gpl/releases y dejalo como $xd"; Stop-Transcript | Out-Null; exit 1 }
Write-Host "xdelta3: $xd"
& $xd -V 2>&1 | Select-Object -First 1 | Write-Host

# 2) ISO en espanol (destino del parche)
Write-Host "`nBuscando la ISO en espanol..."
$es = Get-ChildItem -LiteralPath (Join-Path $root 'The 3rd Birthday(PSP)') -Recurse -File -Filter *.iso -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $es) { Write-Host 'ERROR: no encuentro la ISO en espanol en "The 3rd Birthday(PSP)\juego\".'; Stop-Transcript | Out-Null; exit 1 }
$esMd5 = (Get-FileHash -LiteralPath $es.FullName -Algorithm MD5).Hash
Write-Host "ISO espanol: $($es.FullName)`n  MD5 $esMd5  ($($es.Length) bytes)"

# 3) ISOs originales
$cands = Get-ChildItem -LiteralPath $orig -File -Filter *.iso -ErrorAction SilentlyContinue
if (-not $cands) {
  Write-Host "`nNo hay ISOs en $orig"
  Write-Host 'Copia ahi tu ISO ORIGINAL americana (ULUS-10567) y/o europea (ULES-01513), en formato .iso (no .cso/.chd), y vuelve a ejecutar.'
  Stop-Transcript | Out-Null; exit 0
}

$receta = [ordered]@{
  juego = 'The 3rd Birthday'; creado = (Get-Date -Format s)
  destino = [ordered]@{ md5 = $esMd5; bytes = $es.Length; descripcion = 'Traduccion al espanol (UNDUB) - creditos en README' }
  fuentes = @()
}
foreach ($iso in $cands) {
  Write-Host "`n================ $($iso.Name)"
  $md5 = (Get-FileHash -LiteralPath $iso.FullName -Algorithm MD5).Hash
  $k = $conocidas[$md5]
  if (-not $k) { Write-Host "  MD5 $md5 NO coincide con ningun volcado Redump conocido (puede estar modificada o mal volcada). La salto."; continue }
  Write-Host "  MD5 $md5 -> $($k.region)"
  if ($k.id -eq 'ES_UNDUB') { Write-Host '  Esta ya es la version en espanol, la salto.'; continue }
  if ($k.id -eq 'ULJM05798') { Write-Host '  Japonesa: se usara mas adelante para voces/undub, no para el parche de textos. La salto.'; continue }

  $out = Join-Path $par ("T3B_ES_desde_{0}.xdelta" -f $k.id)
  Write-Host "  Creando parche (puede tardar varios minutos y usar ~2 GB de RAM)..."
  $t = Measure-Command { & $xd -e -f -9 -S djw -B 1073741824 -s $iso.FullName $es.FullName $out 2>&1 | Write-Host }
  if (-not (Test-Path $out)) { Write-Host '  ERROR creando el parche.'; continue }
  Write-Host ("  Parche: {0:N1} MB en {1:N0} s" -f ((Get-Item $out).Length / 1MB), $t.TotalSeconds)

  Write-Host '  Verificando (aplico el parche y comparo MD5)...'
  $prueba = Join-Path $tmp 'verificacion.iso'
  & $xd -d -f -B 1073741824 -s $iso.FullName $out $prueba 2>&1 | Write-Host
  $vMd5 = if (Test-Path $prueba) { (Get-FileHash -LiteralPath $prueba -Algorithm MD5).Hash } else { 'NINGUNO' }
  Remove-Item $prueba -ErrorAction SilentlyContinue
  $ok = ($vMd5 -eq $esMd5)
  Write-Host ("  Verificacion: {0}" -f $(if ($ok) { 'CORRECTA' } else { "FALLO (salio $vMd5)" }))
  $receta.fuentes += [ordered]@{
    disc_id = $k.id; region = $k.region; md5_origen = $md5; bytes_origen = $iso.Length
    parche = (Split-Path -Leaf $out); md5_parche = (Get-FileHash -LiteralPath $out -Algorithm MD5).Hash
    bytes_parche = (Get-Item $out).Length; verificado = $ok
  }
}
$json = $receta | ConvertTo-Json -Depth 5
Set-Content (Join-Path $par 'receta.json') $json -Encoding UTF8
Set-Content (Join-Path $pc 'receta.json') $json -Encoding UTF8
Write-Host "`n$json"
Write-Host "`nLISTO. Ya puedes avisarle a Claude."
Stop-Transcript | Out-Null
