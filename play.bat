@echo off
rem Launch the Snipe sim with Godot 4.7.2 from the desktop, borderless full screen (windowed full
rem screen, not exclusive). Tests and screenshot scripts start windowed as before.
start "" "%USERPROFILE%\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." --fullscreen
