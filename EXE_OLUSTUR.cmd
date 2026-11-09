@echo off
setlocal
chcp 65001 >nul
set "UB_BUILD_DIR=%~dp0"
echo usersbackup v3.0 - EXE olusturuluyor...
echo.
powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -Command "$ErrorActionPreference='Stop'; $dir=$env:UB_BUILD_DIR; Import-Module ps2exe -ErrorAction Stop; Invoke-ps2exe -inputFile (Join-Path $dir 'usersbackup.ps1') -outputFile (Join-Path $dir 'usersbackup.exe') -noConsole -STA -DPIAware -iconFile (Join-Path $dir 'usersbackup.ico') -title 'usersbackup' -product 'usersbackup' -description 'Portable Windows user backup and restore' -version '3.0.0.0'"
if errorlevel 1 (
  echo.
  echo EXE olusturulamadi. Windows PowerShell 5.1 ve ps2exe kurulumunu kontrol edin.
  echo Gerekiyorsa: Install-Module ps2exe -Scope CurrentUser -Force
) else (
  echo.
  echo EXE hazir: %UB_BUILD_DIR%usersbackup.exe
  echo Yalnizca bu EXE dosyasini harici SSD'ye kopyalayabilirsiniz.
)
echo.
pause
