@echo off
rem Installs SR Tweak Menu into Saints Row 2: dinput8.dll next to SR2_pc.exe (or
rem scripts\SRTweakMenu.asi when an ASI loader is already the game's dinput8.dll),
rem the menu's files in TweakMenu\SRTweakMenu, the HUD textures in
rem Mods\SRTweakMenu\HUD. Your mod.ini is kept if you have one.
rem Usage: install.bat ["path to Saints Row 2"]   (default: Steam's folder)
setlocal
set "HERE=%~dp0"
set "GAME=%~1"
if "%GAME%"=="" set "GAME=C:\Program Files (x86)\Steam\steamapps\common\Saints Row 2"
if not exist "%GAME%\SR2_pc.exe" goto :no_game
if not exist "%HERE%build\dinput8.dll" goto :no_dll
rem Another dinput8.dll in the game folder (Ultimate ASI Loader and the like) stays:
rem the menu goes in as scripts\SRTweakMenu.asi, which the loader loads.
set "MODE=dll"
if exist "%GAME%\dinput8.dll" findstr /m /c:"SR2 Tweak Menu host" "%GAME%\dinput8.dll" >nul || set "MODE=asi"
if not exist "%GAME%\dinput8.dll" set "MODE=dll"
if "%MODE%"=="asi" goto :as_asi
copy /y "%HERE%build\dinput8.dll" "%GAME%\dinput8.dll" >nul || goto :copy_failed
if exist "%GAME%\scripts\SRTweakMenu.asi" del "%GAME%\scripts\SRTweakMenu.asi"
goto :menu_files
:as_asi
if not exist "%GAME%\scripts" mkdir "%GAME%\scripts"
copy /y "%HERE%build\SRTweakMenu.asi" "%GAME%\scripts\SRTweakMenu.asi" >nul || goto :copy_failed
echo The game folder has another dinput8.dll (an ASI loader): installed as scripts\SRTweakMenu.asi.
:menu_files
if not exist "%GAME%\TweakMenu\SRTweakMenu" mkdir "%GAME%\TweakMenu\SRTweakMenu"
copy /y "%HERE%SRTweakMenu\*.lua" "%GAME%\TweakMenu\SRTweakMenu\" >nul || goto :copy_failed
if not exist "%GAME%\TweakMenu\SRTweakMenu\data" mkdir "%GAME%\TweakMenu\SRTweakMenu\data"
copy /y "%HERE%SRTweakMenu\data\*.lua" "%GAME%\TweakMenu\SRTweakMenu\data\" >nul || goto :copy_failed
rem Parked modules (the SR1 animation import) stay out of the game folder.
if exist "%GAME%\TweakMenu\SRTweakMenu\sr1_gait.lua" del "%GAME%\TweakMenu\SRTweakMenu\sr1_gait.lua"
if exist "%GAME%\TweakMenu\SRTweakMenu\prone_kick.lua" del "%GAME%\TweakMenu\SRTweakMenu\prone_kick.lua"
rem HUD textures (the HUD styles and weapon wheel load them with peg_load('srt_hud')).
if not exist "%GAME%\Mods\SRTweakMenu\HUD" mkdir "%GAME%\Mods\SRTweakMenu\HUD"
copy /y "%HERE%SRTweakMenu\assets\HUD\srt_hud.peg_pc" "%GAME%\Mods\SRTweakMenu\HUD\" >nul || goto :copy_failed
copy /y "%HERE%SRTweakMenu\assets\HUD\srt_hud.g_peg_pc" "%GAME%\Mods\SRTweakMenu\HUD\" >nul || goto :copy_failed
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
