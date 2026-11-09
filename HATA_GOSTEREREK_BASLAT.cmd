@echo off
setlocal
chcp 65001 >nul
title usersbackup v3.0.1 - Hata Tespiti
echo ===========================================
echo usersbackup v3 - Hata Gosteren Baslatici
echo ===========================================
echo.
echo Bu pencere hata olsa bile kapanmayacak.
echo Kaynak: "%~dp0usersbackup.ps1"
echo.
if not exist "%~dp0usersbackup.ps1" (
  echo HATA: usersbackup.ps1 ayni klasorde bulunamadi.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -STA -NoExit -File "%~dp0usersbackup.ps1"
