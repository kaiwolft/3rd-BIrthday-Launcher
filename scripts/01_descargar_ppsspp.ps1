# The 3rd Birthday - Paso 1: descargar PPSSPP (portable) dentro del proyecto
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $PSScriptRoot 'logs'
$desc = Join-Path $root 'descargas'
$dest = Join-Path $root 'PPSSPP'
New-Item -ItemType Directory -Force -Path $logs, $desc | Out-Null
Start-Transcript -Path (Join-Path $logs '01_descargar_ppsspp.log') -Force | Out-Null

# 1) Version mas reciente segun GitHub (si falla, probamos una lista conocida)
$versiones = @()
try {
  $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/hrydgard/ppsspp/releases/latest' -Headers @{ 'User-Agent' = 'T3B-Launcher' } -TimeoutSec 30
  $v = $rel.tag_name.TrimStart('v')
  Write-Host "Ultima version en GitHub: $v"
  $versiones += $v
} catch { Write-Host "No pude consultar GitHub: $($_.Exception.Message)" }
$versiones += @('1.20.4','1.20.3','1.20.2','1.20.1','1.20','1.19.3')
$versiones = $versiones | Select-Object -Unique

$zip = $null
foreach ($v in $versiones) {
  $carpeta = $v.Replace('.', '_')
  $url = "https://www.ppsspp.org/files/$carpeta/ppsspp_win.zip"
  $archivo = Join-Path $desc "ppsspp_win_$carpeta.zip"
  if ((Test-Path $archivo) -and (Get-Item $archivo).Length -gt 5MB) { $zip = $archivo; Write-Host "Ya descargado: $archivo"; break }
  Write-Host "Probando $url"
  try {
    Invoke-WebRequest -Uri $url -OutFile $archivo -UseBasicParsing -TimeoutSec 600 -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
    if ((Get-Item $archivo).Length -gt 5MB) { $zip = $archivo; Write-Host "Descargado PPSSPP $v"; Set-Content (Join-Path $desc 'ppsspp_version.txt') $v; break }
  } catch { Write-Host "  no disponible: $($_.Exception.Message)" }
  Remove-Item $archivo -ErrorAction SilentlyContinue
}
if (-not $zip) { Write-Host "ERROR: no pude descargar PPSSPP. Descargalo a mano de https://www.ppsspp.org/download y deja el zip en $desc" }
else {
  $sha = (Get-FileHash $zip -Algorithm SHA256).Hash
  Write-Host "SHA256 del zip: $sha"
  if (Test-Path (Join-Path $dest 'PPSSPPWindows64.exe')) { Write-Host "PPSSPP ya estaba extraido en $dest (no se sobreescribe la configuracion)." }
  else {
    Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
    Write-Host "Extraido en $dest"
  }
  # Modo portable: la memoria (partidas, texturas, cheats, config) vive en PPSSPP\memstick
  foreach ($d in 'memstick\PSP\SYSTEM','memstick\PSP\TEXTURES','memstick\PSP\Cheats','memstick\PSP\PLUGINS','memstick\PSP\SAVEDATA') {
    New-Item -ItemType Directory -Force -Path (Join-Path $dest $d) | Out-Null
  }
  Remove-Item (Join-Path $dest 'installed.txt') -ErrorAction SilentlyContinue
  Get-ChildItem $dest | Select-Object Name, Length | Format-Table -AutoSize | Out-String | Write-Host
}
Write-Host "`nLISTO. Ya puedes avisarle a Claude."
Stop-Transcript | Out-Null
