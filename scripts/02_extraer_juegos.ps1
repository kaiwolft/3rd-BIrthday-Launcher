# The 3rd Birthday - Paso 2: identificar y extraer las ISOs de PSP (lector ISO9660 propio, guarda LBA de cada archivo)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $PSScriptRoot 'logs'
$out  = Join-Path $root 'extraido'
$pc   = Join-Path $root 'para_claude'
New-Item -ItemType Directory -Force -Path $logs, $out, $pc | Out-Null
Start-Transcript -Path (Join-Path $logs '02_extraer_juegos.log') -Force | Out-Null

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
  Where-Object { $_.FullName -notlike "$out*" -and $_.FullName -notlike (Join-Path $root 'PPSSPP*') -and $_.FullName -notlike (Join-Path $root 'cache*') }
$drive = (Get-Item $root).PSDrive
Write-Host ("Espacio libre en {0}: {1:N1} GB" -f $drive.Name, ($drive.Free / 1GB))
$resumen = @()

foreach ($iso in $isos) {
  Write-Host "`n================ $($iso.FullName)"
  Write-Host ("Tamano: {0:N0} bytes" -f $iso.Length)
  $fs = [IO.File]::Open($iso.FullName, 'Open', 'Read', 'Read')
  try {
    $pvd = Read-Bytes $fs (16 * 2048) 2048
    if ([Text.Encoding]::ASCII.GetString($pvd, 1, 5) -ne 'CD001') { Write-Host 'ERROR: no es una ISO9660 valida (CSO/CHD no soportado aqui)'; continue }
    $volId  = [Text.Encoding]::ASCII.GetString($pvd, 40, 32).Trim()
    $sector = U32 $pvd 80
    $rootLba = U32 $pvd (156 + 2); $rootSize = U32 $pvd (156 + 10)
    $list = New-Object 'System.Collections.Generic.List[object]'
    Get-Entries $fs $rootLba $rootSize '' $list
    $sfoE = $list | Where-Object { $_.Ruta -eq 'PSP_GAME/PARAM.SFO' } | Select-Object -First 1
    $sfo = @{}
    if ($sfoE) { $sfo = Read-SFO (Read-Bytes $fs ($sfoE.LBA * 2048) ([int]$sfoE.Tamano)) }
    $discId = if ($sfo['DISC_ID']) { $sfo['DISC_ID'] } else { 'DESCONOCIDO' }
    Write-Host "Volumen: $volId  | Sectores: $sector | Archivos: $($list.Count)"
    $sfo.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ("  SFO {0,-16} = {1}" -f $_.Name, $_.Value) }

    $base = ($iso.BaseName -replace '[^A-Za-z0-9\-]+', '_').Trim('_')
    $tag  = "{0}__{1}" -f $discId, $base
    $dest = Join-Path $out $tag
    $marca = Join-Path $dest '.extraccion_completa'
    if (Test-Path $marca) { Write-Host "Ya extraido en $dest, lo salto." }
    else {
      Write-Host "Extrayendo a $dest ..."
      $buf = New-Object byte[] (4MB)
      foreach ($e in $list) {
        $target = Join-Path $dest ($e.Ruta -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        $o = [IO.File]::Create($target)
        [void]$fs.Seek([long]$e.LBA * 2048, 'Begin')
        $left = [long]$e.Tamano
        while ($left -gt 0) {
          $r = $fs.Read($buf, 0, [int][math]::Min($buf.Length, $left)); if ($r -le 0) { break }
          $o.Write($buf, 0, $r); $left -= $r
        }
        $o.Close()
      }
      Set-Content $marca (Get-Date -Format s)
    }
  } finally { $fs.Close() }

  Write-Host 'Calculando hashes de la ISO (MD5/SHA1/CRC compatible Redump) ...'
  $md5  = (Get-FileHash -LiteralPath $iso.FullName -Algorithm MD5).Hash
  $sha1 = (Get-FileHash -LiteralPath $iso.FullName -Algorithm SHA1).Hash
  Write-Host "MD5 : $md5"; Write-Host "SHA1: $sha1"

  # Inventario: ruta, LBA, tamano, MD5
  $lista = Join-Path $logs "lista_$tag.tsv"
  $lineas = foreach ($e in ($list | Sort-Object LBA)) {
    $f = Join-Path $dest ($e.Ruta -replace '/', '\')
    $h = (Get-FileHash -LiteralPath $f -Algorithm MD5).Hash
    "{0}`t{1}`t{2}`t{3}" -f $e.Ruta, $e.LBA, $e.Tamano, $h
  }
  @("ruta`tlba`ttamano`tmd5") + $lineas | Set-Content -Path $lista -Encoding UTF8
  Write-Host "Inventario: $($list.Count) archivos -> $lista"
  $list | Group-Object { [IO.Path]::GetExtension($_.Ruta).ToLower() } | Sort-Object Count -Descending | Select-Object -First 25 |
    ForEach-Object { Write-Host ("  {0,-10} {1,6} archivos  {2,10:N1} MB" -f $_.Name, $_.Count, (($_.Group | Measure-Object Tamano -Sum).Sum / 1MB)) }

  # Copias pequenas para analizar: PARAM.SFO, iconos, fondo, sonido de menu, UMD_DATA, inventario
  $pcd = Join-Path $pc $tag
  New-Item -ItemType Directory -Force -Path $pcd | Out-Null
  foreach ($n in 'UMD_DATA.BIN', 'PSP_GAME\PARAM.SFO', 'PSP_GAME\ICON0.PNG', 'PSP_GAME\ICON1.PMF', 'PSP_GAME\PIC0.PNG', 'PSP_GAME\PIC1.PNG', 'PSP_GAME\SND0.AT3') {
    $f = Join-Path $dest $n; if (Test-Path $f) { Copy-Item $f $pcd -Force }
  }
  Copy-Item $lista $pcd -Force
  # Ejecutables y archivos pequenos de sistema (cabeceras para ver si el EBOOT esta cifrado)
  Get-ChildItem (Join-Path $dest 'PSP_GAME\SYSDIR') -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 40MB } | Copy-Item -Destination $pcd -Force
  $info = [ordered]@{ iso = $iso.FullName; tag = $tag; disc_id = $discId; titulo = $sfo['TITLE']; version = $sfo['DISC_VERSION']; app_ver = $sfo['APP_VER']; volumen = $volId; sectores = $sector; archivos = $list.Count; bytes = $iso.Length; md5 = $md5; sha1 = $sha1 }
  ($info | ConvertTo-Json) | Set-Content (Join-Path $pcd 'info.json') -Encoding UTF8
  $resumen += [pscustomobject]$info
}

$resumen | ConvertTo-Json | Set-Content (Join-Path $pc 'resumen_isos.json') -Encoding UTF8
$resumen | Format-Table disc_id, titulo, version, archivos, md5 -AutoSize | Out-String | Write-Host
$drive = (Get-Item $root).PSDrive
Write-Host ("Espacio libre restante: {0:N1} GB" -f ($drive.Free / 1GB))
Write-Host "`nLISTO. Ya puedes avisarle a Claude."
Stop-Transcript | Out-Null
