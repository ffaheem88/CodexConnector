@echo off
REM CodexConnector - Wrapper to call the PowerShell script on Windows
REM Usage: codex-review [OPTIONS] [CUSTOM_PROMPT]

REM Translate --flags to PowerShell -flags
set "ARGS=%*"
if defined ARGS (
    set "ARGS=%ARGS:--help=-Help%"
    set "ARGS=%ARGS:--model=-Model%"
    set "ARGS=%ARGS:--action=-Action%"
    set "ARGS=%ARGS:--mode=-Mode%"
    set "ARGS=%ARGS:--base=-Base%"
    set "ARGS=%ARGS:--commit=-Commit%"
    set "ARGS=%ARGS:--file=-File%"
    set "ARGS=%ARGS:--dir=-Dir%"
    set "ARGS=%ARGS:--verbose=-VerboseOutput%"
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-review.ps1" %ARGS%
