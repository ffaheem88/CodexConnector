@echo off
REM CodexConnector - Wrapper to call the PowerShell script on Windows
REM Usage: codex-review [OPTIONS] [CUSTOM_PROMPT]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-review.ps1" %*
