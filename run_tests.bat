@echo off
rem Runs the headless test suite. Exit code is non-zero if any test fails.
set G=%USERPROFILE%\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe
set FAIL=0
for %%t in (polar_test tack_test rules_test controls_test session_test capsize_test tune_test race_test) do (
  "%G%" --headless --path "%~dp0." --script res://tests/%%t.gd
  if errorlevel 1 set FAIL=1
)
exit /b %FAIL%
