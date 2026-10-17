@echo off
title The 3rd Birthday - Pasos 1 y 2
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp001_descargar_ppsspp.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp002_extraer_juegos.ps1"
echo.
echo TODO LISTO. Ya puedes avisarle a Claude.
pause
