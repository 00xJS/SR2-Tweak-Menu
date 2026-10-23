@echo off
rem Builds build\lua.exe (for tools\offline_test.lua) from third_party\lua-5.4.9.
setlocal
set "LUA=%~dp0..\third_party\lua-5.4.9\src"
set "OUT=%~dp0..\build"
where cl >nul 2>nul || call "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat" >nul 2>nul
if not exist "%OUT%\luaexe" mkdir "%OUT%\luaexe"
pushd "%OUT%\luaexe"
set "SRC="
for %%f in ("%LUA%\*.c") do if /i not "%%~nf"=="luac" call set "SRC=%%SRC%% "%%f""
cl /nologo /O2 /MT /W1 /Fe"%OUT%\lua.exe" %SRC% >nul || (popd & echo lua.exe build failed & exit /b 1)
popd
echo Built %OUT%\lua.exe
