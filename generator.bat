@echo off
setlocal enabledelayedexpansion

:: ========== 配置区域 ==========
set GENERATE_COUNT=3
:: ==============================

:MAIN_MENU
cls
echo ========================================
echo              主菜单
echo ========================================
echo   1. 生成UUID
echo   2. 生成密码
echo   3. 时间戳
echo   4. 随机数
echo   0. 结束脚本
echo ========================================
echo.
set "menu_choice="
set /p "menu_choice=请选择: "

if "%menu_choice%"=="1" goto UUID_MENU
if "%menu_choice%"=="2" goto PASSWORD_MENU
if "%menu_choice%"=="3" goto TIMESTAMP_MENU
if "%menu_choice%"=="4" goto RANDOM_MENU
if "%menu_choice%"=="0" (
    echo.
    echo 程序已结束。
    timeout /t 1 /nobreak >nul
    exit /b 0
)

echo 无效选择，请重新输入！
timeout /t 1 /nobreak >nul
goto MAIN_MENU

:UUID_MENU
cls
echo ========================================
echo           生成UUID (不含数字0,4)
echo ========================================

:UUID_LOOP
echo.
echo 按回车键生成%GENERATE_COUNT%个随机UUID，输入0返回主菜单
set "input="
set /p "input=^> "

if "%input%"=="0" goto MAIN_MENU

echo.

for /l %%i in (1,1,%GENERATE_COUNT%) do (
    call :GenerateUUID
    echo !UUID!
)

goto UUID_LOOP

:PASSWORD_MENU
cls
echo ========================================
echo           生成密码
echo ========================================

:PASSWORD_INPUT
echo.
set "password_length="
set /p "password_length=请输入密码位数 (8-64): "
if "%password_length%"=="" goto PASSWORD_INPUT
if %password_length% lss 8 (
    echo 密码位数不能小于8！
    timeout /t 1 /nobreak >nul
    goto PASSWORD_INPUT
)
if %password_length% gtr 64 (
    echo 密码位数不能大于64！
    timeout /t 1 /nobreak >nul
    goto PASSWORD_INPUT
)

goto PASSWORD_LOOP

:PASSWORD_LOOP
echo.
echo 当前密码位数: %password_length% 位
echo 按回车键生成%GENERATE_COUNT%个密码，输入0返回主菜单，输入6重新设置位数
set "input="
set /p "input=^> "

if "%input%"=="0" goto MAIN_MENU
if "%input%"=="6" goto PASSWORD_INPUT

echo.

for /l %%i in (1,1,%GENERATE_COUNT%) do (
    call :GeneratePassword %password_length%
    echo !PASSWORD!
)

goto PASSWORD_LOOP

:GenerateUUID
:: 使用PowerShell生成标准UUID v4
for /f "delims=" %%u in ('powershell -command "[guid]::NewGuid().ToString()"') do set "UUID=%%u"

:: 将UUID中所有数字4和0替换为8
set "UUID=%UUID:4=8%"
set "UUID=%UUID:0=8%"

goto :eof

:GeneratePassword
set "length=%1"
set "PASSWORD="

:: 使用PowerShell生成随机密码
for /f "delims=" %%p in ('powershell -command "$chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%%^&*()-_=+[]{}|;:'',.<>?/'; -join ((1..%length%) | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })"') do set "PASSWORD=%%p"

goto :eof

:TIMESTAMP_MENU
cls
echo ========================================
echo           时间戳工具
echo ========================================

:TIMESTAMP_LOOP
echo.
echo 按回车键获取当前时间戳，输入0返回主菜单
set "input="
set /p "input=^> "

if "%input%"=="0" goto MAIN_MENU

call :GetTimestamp
echo 当前时间: !TIMESTAMP!
echo Unix时间戳: !UNIX_TIMESTAMP!

goto TIMESTAMP_LOOP

:RANDOM_MENU
cls
echo ========================================
echo           随机数生成
echo ========================================

:RANDOM_INPUT_MIN
echo.
set "random_min="
set /p "random_min=请输入最小值: "
if "%random_min%"=="" goto RANDOM_INPUT_MIN

:RANDOM_INPUT_MAX
set "random_max="
set /p "random_max=请输入最大值: "
if "%random_max%"=="" goto RANDOM_INPUT_MAX
if %random_max% leq %random_min% (
    echo 最大值必须大于最小值！
    timeout /t 1 /nobreak >nul
    goto RANDOM_INPUT_MAX
)

:RANDOM_LOOP
echo.
echo 范围: %random_min% - %random_max%
echo 按回车键生成%GENERATE_COUNT%组随机数，输入0返回主菜单，输入6重新设置范围
set "input="
set /p "input=^> "

if "%input%"=="0" goto MAIN_MENU
if "%input%"=="6" goto RANDOM_INPUT_MIN

for /l %%i in (1,1,%GENERATE_COUNT%) do (
    call :GetRandom %random_min% %random_max%
    echo 第%%i组: !RANDOM_NUM!
)

goto RANDOM_LOOP

:GetTimestamp
for /f "delims=" %%t in ('powershell -command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') do set "TIMESTAMP=%%t"
for /f "delims=" %%u in ('powershell -command "$epoch = New-Object DateTime(1970,1,1,0,0,0,[DateTimeKind]::Utc); [int]((Get-Date).ToUniversalTime() - $epoch).TotalSeconds"') do set "UNIX_TIMESTAMP=%%u"
goto :eof

:GetRandom
set /a "RANDOM_NUM=!RANDOM! %% (%2 - %1 + 1) + %1"
goto :eof
