@echo off
rem Installs SR Tweak Menu into Saints Row 2: dinput8.dll next to SR2_pc.exe,
rem the menu's files in TweakMenu\SRTweakMenu. Your mod.ini is kept if you have one.
rem Usage: install.bat ["path to Saints Row 2"]   (default: Steam's folder)
setlocal
set "HERE=%~dp0"
set "GAME=%~1"
if "%GAME%"=="" set "GAME=C:\Program Files (x86)\Steam\steamapps\common\Saints Row 2"
if not exist "%GAME%\SR2_pc.exe" goto :no_game
if not exist "%HERE%build\dinput8.dll" goto :no_dll
if exist "%GAME%\dinput8.dll" fc /b "%GAME%\dinput8.dll" "%HERE%build\dinput8.dll" >nul || echo Replacing the dinput8.dll already in the game folder.
copy /y "%HERE%build\dinput8.dll" "%GAME%\dinput8.dll" >nul || goto :copy_failed
if not exist "%GAME%\TweakMenu\SRTweakMenu" mkdir "%GAME%\TweakMenu\SRTweakMenu"
copy /y "%HERE%SRTweakMenu\*.lua" "%GAME%\TweakMenu\SRTweakMenu\" >nul || goto :copy_failed
if not exist "%GAME%\TweakMenu\SRTweakMenu\data" mkdir "%GAME%\TweakMenu\SRTweakMenu\data"
copy /y "%HERE%SRTweakMenu\data\*.lua" "%GAME%\TweakMenu\SRTweakMenu\data\" >nul || goto :copy_failed
if not exist "%GAME%\TweakMenu\SRTweakMenu\mod.ini" copy "%HERE%SRTweakMenu\mod.ini" "%GAME%\TweakMenu\SRTweakMenu\" >nul
echo Installed. Start Saints Row 2 and press F5 in game.
exit /b 0
:no_game
echo Saints Row 2 not found in "%GAME%". Pass its folder: install.bat "D:\Games\Saints Row 2"
exit /b 1
:no_dll
echo build\dinput8.dll is missing: run host\build.bat first.
exit /b 1
:copy_failed
echo Copying failed (is the game running?).
exit /b 1
