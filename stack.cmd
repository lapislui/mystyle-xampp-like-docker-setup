@echo off
setlocal

if not exist "%~dp0stack.sh" (
    echo stack.sh was not found next to stack.cmd.
    echo Keep both files in the same folder.
    exit /b 1
)

if defined GIT_BASH if exist "%GIT_BASH%" goto find_args

set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if exist "%GIT_BASH%" goto find_args

set "GIT_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if exist "%GIT_BASH%" goto find_args

set "GIT_BASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if exist "%GIT_BASH%" goto find_args

echo Git Bash was not found.
echo Install Git for Windows from https://git-scm.com/download/win
echo or set GIT_BASH to the full path of bash.exe.
exit /b 1

:find_args
rem --reinstall / --no-reinstall answer the Moodle repair prompt of "up" from the
rem command line, which is more reliable than typing at the prompt in cmd.
set "ARGS="
:parse
if "%~1"=="" goto run
if /i "%~1"=="--reinstall" (
    set "MOODLE_REINSTALL=1"
    shift
    goto parse
)
if /i "%~1"=="--no-reinstall" (
    set "MOODLE_REINSTALL=0"
    shift
    goto parse
)
set "ARGS=%ARGS% "%~1""
shift
goto parse

:run
set "STACK_WRAPPER=stack.cmd"
"%GIT_BASH%" "%~dp0stack.sh" %ARGS%
exit /b %ERRORLEVEL%
