@echo off
if /I "%~1"=="--version" (
  echo machinecontext-probe 1.2.3
  exit /b 0
)
exit /b 2
