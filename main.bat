@echo off
chcp 65001

set MAIN_EXIST=0
set APP_EXIST=0

if exist "main.py" set MAIN_EXIST=1
if exist "app.py" set APP_EXIST=1

:: Check if both files exist
if %MAIN_EXIST%==1 if %APP_EXIST%==1 goto BOTH_FOUND
if %MAIN_EXIST%==1 if %APP_EXIST%==0 goto RUN_MAIN
if %MAIN_EXIST%==0 if %APP_EXIST%==1 goto RUN_APP

:: Both files don't exist
echo Error: Could not find main.py or app.py in the current directory.
echo Please make sure you run this script in the directory containing these files.
pause
exit /b 1

:BOTH_FOUND
echo Found both main.py and app.py.
echo Please select which file to run:
echo 1. main.py
echo 2. app.py
choice /c 12 /m "Enter your choice"
if errorlevel 2 goto RUN_APP
if errorlevel 1 goto RUN_MAIN

:RUN_MAIN
echo Running main.py ...
python main.py
goto END

:RUN_APP
echo Running app.py ...
python app.py
goto END

:END
echo Program exited.
pause