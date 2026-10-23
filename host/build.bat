@echo off
rem Builds dinput8.dll (32-bit) with the Visual Studio 2022 C++ tools.
rem Usage: build.bat [install]   - "install" also copies it into the game folder
rem (set SR2_PATH to your Saints Row 2 folder if it isn't Steam's default).
setlocal
set "HERE=%~dp0"
set "LUA=%HERE%..\third_party\lua-5.4.9\src"
set "OUT=%HERE%..\build"
if "%SR2_PATH%"=="" set "SR2_PATH=C:\Program Files (x86)\Steam\steamapps\common\Saints Row 2"

where cl >nul 2>nul && goto :have_cl
set "VSDIR="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto :no_vswhere
for /f "usebackq delims=" %%i in (`call "%%VSWHERE%%" -latest -products * -property installationPath`) do set "VSDIR=%%i"
:no_vswhere
if "%VSDIR%"=="" if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools" set "VSDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools"
if "%VSDIR%"=="" if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community" set "VSDIR=%ProgramFiles%\Microsoft Visual Studio\2022\Community"
if not exist "%VSDIR%\VC\Auxiliary\Build\vcvars32.bat" goto :no_vs
call "%VSDIR%\VC\Auxiliary\Build\vcvars32.bat" >nul 2>nul
:have_cl

if not exist "%OUT%\obj" mkdir "%OUT%\obj"
pushd "%OUT%\obj"
del /q *.obj 2>nul
set "LUA_SRC="
for %%f in ("%LUA%\*.c") do if /i not "%%~nf"=="lua" if /i not "%%~nf"=="luac" call set "LUA_SRC=%%LUA_SRC%% "%%f""
cl /nologo /c /O2 /MT /W1 /TC %LUA_SRC% >nul || goto :fail
cl /nologo /c /O2 /MT /W3 /TC /I"%LUA%" "%HERE%host.c" || goto :fail
link /nologo /DLL /OUT:"%OUT%\dinput8.dll" /DEF:"%HERE%dinput8.def" /SAFESEH:NO *.obj user32.lib kernel32.lib || goto :fail
popd
echo Built %OUT%\dinput8.dll
if /i not "%~1"=="install" exit /b 0
copy /y "%OUT%\dinput8.dll" "%SR2_PATH%\dinput8.dll" >nul || goto :copy_failed
echo Installed into %SR2_PATH%
exit /b 0

:no_vs
echo Visual Studio 2022 C++ tools not found (install "Desktop development with C++").
exit /b 1
:copy_failed
echo Couldn't copy into "%SR2_PATH%" (is the game running?)
exit /b 1
:fail
popd
echo Build failed
exit /b 1
