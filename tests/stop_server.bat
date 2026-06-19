@echo off
set MORROWIND_APPLICATION=Morrowind.exe
taskkill /im %MORROWIND_APPLICATION%
timeout /t 5
tasklist | find "%MORROWIND_APPLICATION%"
if not errorlevel 1 taskkill /im %MORROWIND_APPLICATION% /f
