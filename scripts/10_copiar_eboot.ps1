# The 3rd Birthday - Paso 10: copiar el ejecutable (EBOOT.BIN) de tus ISOs para adaptar la camara libre a cada version
# Solo lee las ISOs (no modifica nada). Deja los archivos en para_claude\eboot\
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $PSScriptRoot 'logs'
$dst  = Join-Path $root 'para_claude\eboot'
New-Item -ItemType Directory -Force -Path $logs, $dst | Out-Null
Start-Transcript -Path (Join-Path $logs '10_copiar_eboot.log') -Force | Out-Null

function Read-Bytes($fs, [long]$offset, [int]$count) {
  $buf = New-Object byte[] $count
  [void]$fs.Seek($offset, 'Begin')
  $n = 0; while ($n -lt $count) { $r = $fs.Read($buf, $n, $count - $n); if ($r -le 0) { break }; $n += $r }
  return ,$buf
}
function U32($b, $o) { return [BitConverter]::ToUInt32($b, $o) }
function U16($b, $o) { return [BitConverter]::ToUInt16($b, $o) }

function Get-Entries($fs, [long]$lba, [long]$size, [string]$path, $list) {
  $data = Read-Bytes $fs ($lba * 2048) ([int]$size)
  $i = 0
  while ($i -lt $size) {
    $len = $data[$i]
    if ($len -eq 0) { $i = [int](([math]::Floor($i / 2048) + 1) * 2048); continue }
    $elba  = U32 $data ($i + 2)
    $esize = U32 $data ($i + 10)
    $flags = $data[$i + 25]
    $nlen  = $data[$i + 32]
    $name  = [Text.Encoding]::ASCII.GetString($data, $i + 33, $nlen)
    if (-not ($nlen -eq 1 -and ($data[$i + 33] -eq 0 -or $data[$i + 33] -eq 1))) {
      $name = $name -replace ';1$', ''
      $rel = if ($path) { "$path/$name" } else { $name }
      if ($flags -band 2) { Get-Entries $fs $elba $esize $rel $list }
      else { $list.Add([pscustomobject]@{ Ruta = $rel; LBA = $elba; Tamano = [long]$esize }) }
    }
    $i += $len
  }
}

function Read-SFO([byte[]]$b) {
  $r = @{}
  if ($b.Length -lt 20 -or [Text.Encoding]::ASCII.GetString($b, 1, 3) -ne 'PSF') { return $r }
  $keyT = U32 $b 8; $datT = U32 $b 12; $cnt = U32 $b 16
  for ($k = 0; $k -lt $cnt; $k++) {
    $e = 20 + 16 * $k
    $ko = U16 $b $e; $fmt = U16 $b ($e + 2); $len = U32 $b ($e + 4); $doff = U32 $b ($e + 12)
    $ks = $keyT + $ko; $ke = $ks; while ($b[$ke] -ne 0) { $ke++ }
    $key = [Text.Encoding]::ASCII.GetString($b, $ks, $ke - $ks)
    if ($fmt -eq 0x0404) { $val = U32 $b ($datT + $doff) }
    else { $val = [Text.Encoding]::UTF8.GetString($b, $datT + $doff, $len).TrimEnd([char]0) }
    $r[$key] = $val
  }
  return $r
}

$isos = Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.iso |
  Where-Object { $_.FullName -notlike (Join-Path $root 'extraido*') -and $_.FullName -notlike (Join-Path $root 'PPSSPP*') -and $_.FullName -notlike (Join-Path $root 'cache*') }
if (-not $isos) { Write-Host 'No encontre ninguna ISO en la carpeta del proyecto.' }
foreach ($iso in $isos) {
  Write-Host "`n== $($iso.FullName)"
  $fs = [IO.File]::Open($iso.FullName, 'Open', 'Read', 'Read')
  try {
    $pvd = Read-Bytes $fs (16 * 2048) 2048
    if ([Text.Encoding]::ASCII.GetString($pvd, 1, 5) -ne 'CD001') { Write-Host '  No es una ISO9660 (CSO/CHD no soportado), la salto.'; continue }
    $list = New-Object 'System.Collections.Generic.List[object]'
    Get-Entries $fs (U32 $pvd 158) (U32 $pvd 166) '' $list
    $sfoE = $list | Where-Object { $_.Ruta -eq 'PSP_GAME/PARAM.SFO' } | Select-Object -First 1
    $sfo = @{}; if ($sfoE) { $sfo = Read-SFO (Read-Bytes $fs ($sfoE.LBA * 2048) ([int]$sfoE.Tamano)) }
    $id = if ($sfo['DISC_ID']) { $sfo['DISC_ID'] } else { 'DESCONOCIDO' }
    Write-Host "  Juego: $id  $($sfo['TITLE'])"
    foreach ($name in 'EBOOT.BIN', 'EBOOT.OLD') {
      $e = $list | Where-Object { $_.Ruta -eq "PSP_GAME/SYSDIR/$name" } | Select-Object -First 1
      if (-not $e) { continue }
      $out = Join-Path $dst ("{0}_{1}_{2}" -f $id, $iso.Length, $name)
      [IO.File]::WriteAllBytes($out, (Read-Bytes $fs ($e.LBA * 2048) ([int]$e.Tamano)))
      Write-Host ("  Copiado {0} ({1:N0} bytes) -> {2}" -f $name, $e.Tamano, $out)
    }
  } finally { $fs.Close() }
}
Write-Host "`nListo. Avisale a Claude."
Stop-Transcript | Out-Null
