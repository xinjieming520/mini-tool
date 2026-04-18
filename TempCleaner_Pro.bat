@echo off
title TempCleaner_Pro
color 0A

:: 获取脚本所在目录并创建日志文件夹
set "script_dir=%~dp0"
set "log_dir=%script_dir%log"
if not exist "%log_dir%" mkdir "%log_dir%"
set "log_file=%log_dir%\temp_clean_%date:~0,4%%date:~5,2%%date:~8,2%.log"

:: 修复日期格式（将.替换为-，避免文件名异常）
set "log_date=%date:~0,4%-%date:~5,2%-%date:~8,2%"
set "log_file=%log_dir%\temp_clean_%log_date%.log"

echo ========================================
echo        TempCleaner_Pro
echo ========================================
echo.
echo 日志保存位置：%log_dir%
echo.
echo 正在清理用户临时文件 (%temp%)...
echo.

:: 写入日志头
echo ======================================== >> "%log_file%"
echo 清理时间：%date% %time% >> "%log_file%"
echo ======================================== >> "%log_file%"

:: ========== 清理用户临时文件 ==========
call :GetCurrentTime
echo [%current_time%] 开始清理用户临时文件 >> "%log_file%"

cd /d "%temp%" 2>nul
if errorlevel 1 (
    call :GetCurrentTime
    echo [%current_time%] 错误：无法访问临时文件夹 >> "%log_file%"
    echo 错误：无法访问临时文件夹！
    pause
    exit /b
)

:: 使用更可靠的统计方法（统计文件数，不含文件夹）
set "file_count_before=0"
for /f %%a in ('dir /a-d /b 2^>nul ^| find /c /v ""') do set file_count_before=%%a
if "%file_count_before%"=="" set file_count_before=0

:: 清理文件（不删除文件夹本身）
del /f /s /q *.* >nul 2>&1

:: 清理空文件夹
for /d %%i in (*) do rmdir /s /q "%%i" 2>nul

:: 统计清理后的文件数量
set "file_count_after=0"
for /f %%a in ('dir /a-d /b 2^>nul ^| find /c /v ""') do set file_count_after=%%a
if "%file_count_after%"=="" set file_count_after=0

:: 计算实际删除的文件数
set /a deleted_count=%file_count_before% - %file_count_after%

call :GetCurrentTime
echo [%current_time%] 用户临时文件清理完成 >> "%log_file%"
echo [%current_time%] 清理前: %file_count_before% 个文件 >> "%log_file%"
echo [%current_time%] 清理后: %file_count_after% 个文件 >> "%log_file%"
echo [%current_time%] 实际删除: %deleted_count% 个文件 >> "%log_file%"

echo [成功] 用户临时文件已清理！ (删除了 %deleted_count% 个文件)
echo.

:: ========== 清理系统临时文件 ==========
echo 正在清理系统临时文件...

if exist "C:\Windows\Temp" (
    call :GetCurrentTime
    echo [%current_time%] 开始清理系统临时文件 >> "%log_file%"
    
    cd /d "C:\Windows\Temp" 2>nul
    
    :: 统计清理前的文件数量
    set "sys_count_before=0"
    for /f %%a in ('dir /a-d /b 2^>nul ^| find /c /v ""') do set sys_count_before=%%a
    if "%sys_count_before%"=="" set sys_count_before=0
    
    :: 清理
    del /f /s /q *.* >nul 2>&1
    for /d %%i in (*) do rmdir /s /q "%%i" 2>nul
    
    :: 统计清理后的文件数量
    set "sys_count_after=0"
    for /f %%a in ('dir /a-d /b 2^>nul ^| find /c /v ""') do set sys_count_after=%%a
    if "%sys_count_after%"=="" set sys_count_after=0
    
    set /a sys_deleted=%sys_count_before% - %sys_count_after%
    
    call :GetCurrentTime
    echo [%current_time%] 系统临时文件清理完成 >> "%log_file%"
    echo [%current_time%] 清理前: %sys_count_before% 个文件 >> "%log_file%"
    echo [%current_time%] 清理后: %sys_count_after% 个文件 >> "%log_file%"
    echo [%current_time%] 实际删除: %sys_deleted% 个文件 >> "%log_file%"
    
    echo [成功] 系统临时文件已清理！ (删除了 %sys_deleted% 个文件)
) else (
    call :GetCurrentTime
    echo [%current_time%] 跳过：系统临时文件夹不存在 >> "%log_file%"
    echo [提示] 系统临时文件夹不存在
)

echo.
echo ========================================
echo           清理完成！
echo ========================================
echo.
echo 日志已保存到：%log_file%
echo.
echo 提示：无法删除的文件正在被系统使用，这是正常的。
echo.

:: 写入日志尾
echo ======================================== >> "%log_file%"
echo 清理结束时间：%date% %time% >> "%log_file%"
echo. >> "%log_file%"

pause
exit /b

:: ========== 获取精确时间的子程序 ==========
:GetCurrentTime
set "current_time=%time%"
:: 统一时间格式为 时:分:秒.毫秒
for /f "tokens=1-4 delims=:.," %%a in ("%current_time%") do (
    set "h=%%a"
    set "m=%%b"
    set "s=%%c"
    set "ms=%%d"
)
if "%ms%"=="" set ms=00
if %ms% lss 10 set ms=0%ms%
set "current_time=%h%:%m%:%s%.%ms%"
goto :eof