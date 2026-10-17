@echo off
title The 3rd Birthday - Crear parche nativo al espanol
echo Antes de seguir: copia tu ISO ORIGINAL americana y/o europea en la carpeta "originales".
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp003_crear_parche.ps1"
pause
