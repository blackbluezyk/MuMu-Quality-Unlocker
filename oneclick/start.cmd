@echo off
setlocal
if exist "%~dp0MuMuLocalQuality.exe" (
  start "" "%~dp0MuMuLocalQuality.exe"
) else (
  echo MuMuLocalQuality.exe is missing. Extract the complete ZIP first.
  pause
  exit /b 1
)
