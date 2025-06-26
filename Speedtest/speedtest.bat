@echo off
REM Batch helper for PRTG EXE/Script Advanced sensor
REM Runs the PowerShell script with all arguments passed by PRTG

REM Ensure PowerShell path is correct for 64-bit execution
REM Use System32 (not SysNative) so it works for both manual and PRTG SYSTEM runs

%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File "%~dp0speedtest.ps1" %*