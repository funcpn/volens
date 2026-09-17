: << 'CMDBLOCK'
@echo off
REM Polyglot dispatcher: cmd.exe runs the batch section below on Windows,
REM while a POSIX shell treats it as a heredoc and runs the section after
REM CMDBLOCK. Codex evaluates hook commands through PowerShell on Windows,
REM which cannot execute volens-sync.sh directly; Claude Code never reaches
REM this file, because hooks/hooks.json declares "shell": "bash".
REM
REM Kept LF-only by .gitattributes, and committed 755: bash resolves a file
REM with no shebang through an ENOEXEC fallback, which a missing executable
REM bit defeats.
setlocal
set "HOOK_DIR=%~dp0"
set "SCRIPT=%HOOK_DIR%volens-sync.sh"
set "SCRIPT=%SCRIPT:\=/%"
set "BASH="

REM 1. Git for Windows in its default locations.
call :probe "%ProgramFiles%\Git\bin\bash.exe"
call :probe "%ProgramFiles(x86)%\Git\bin\bash.exe"

REM 2. Derived from the git on PATH, which covers non-default install drives
REM    (D:\git\Git\cmd\git.exe -> D:\git\Git\bin\bash.exe).
if not defined BASH for /f "delims=" %%G in ('where git 2^>nul') do call :probe "%%~dpGbash.exe"
if not defined BASH for /f "delims=" %%G in ('where git 2^>nul') do call :probe "%%~dpG..\bin\bash.exe"

REM 3. Whatever else answers to bash on PATH. :probe rejects the WSL
REM    launchers in System32 and WindowsApps, which are named bash.exe but
REM    cannot run a script.
if not defined BASH for /f "delims=" %%B in ('where bash 2^>nul') do call :probe "%%~B"

if not defined BASH (
    echo {"systemMessage":"volens: sync hook skipped - no usable Git Bash found on this machine, so docs/DESIGN.md will not be synced automatically"}
    exit /b 0
)

"%BASH%" "%SCRIPT%" %*
exit /b %ERRORLEVEL%

:probe
REM Accept the first candidate that exists and actually runs.
if defined BASH exit /b 0
if "%~1"=="" exit /b 0
REM Land the candidate in a variable first. An argument reference is not a
REM variable name, so the variable-substring form does not apply to it - and
REM cmd aborts the whole file at parse time when it meets one here, so the hook
REM never runs at all. Measured on Windows 11 with a two-line repro, 2026-09-17.
set "CAND=%~1"
if not "%CAND:WindowsApps=%"=="%CAND%" exit /b 0
if not "%CAND:System32=%"=="%CAND%" exit /b 0
if not exist "%CAND%" exit /b 0
"%CAND%" --version >nul 2>nul
if errorlevel 1 exit /b 0
set "BASH=%CAND%"
exit /b 0
CMDBLOCK

# Unix: Codex runs this file as the hook command, and bash executes it as a
# script after the heredoc above. Nothing to dispatch - hand over to the
# shared logic with the event name intact.
exec bash "$(dirname "$0")/volens-sync.sh" "$@"
