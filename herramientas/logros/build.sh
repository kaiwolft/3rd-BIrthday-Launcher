#!/bin/sh
# Compila t3b_logros (motor de logros sin conexion) para Linux y Windows con rcheevos v11.6.0.
#   sh herramientas/logros/build.sh <carpeta_salida>
# Linux: gcc. Windows: x86_64-w64-mingw32-gcc (paquete gcc-mingw-w64-x86-64 en Ubuntu/Debian).
set -e
H=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$H/bin}
mkdir -p "$OUT"
TMP=$(mktemp -d)
git clone -q --depth 1 --branch v11.6.0 https://github.com/RetroAchievements/rcheevos.git "$TMP/rc"
SRC="$TMP/rc/src/rcheevos/*.c $TMP/rc/src/rc_compat.c $TMP/rc/src/rc_util.c $TMP/rc/src/rhash/md5.c"
F="-O2 -std=gnu11 -w -DRC_DISABLE_LUA -I$TMP/rc/include -I$TMP/rc/src"
gcc $F -o "$OUT/t3b_logros" "$H/t3b_logros.c" $SRC -lpthread -lm
strip "$OUT/t3b_logros"
if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
  x86_64-w64-mingw32-gcc $F -s -static -o "$OUT/t3b_logros.exe" "$H/t3b_logros.c" $SRC
fi
rm -rf "$TMP"
ls -la "$OUT"
