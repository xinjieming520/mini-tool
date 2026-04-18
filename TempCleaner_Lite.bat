@echo off
title 临时文件清理工具
color 0A

:: 获取脚本所在目录并创建日志文件夹
set "log_dir=%~dp0log"
if not exist "%log_dir%" mkdir "%log_dir%"
set "log_file=%log_dir%\temp_clean_%date:~0,4%%date:~5,2%%date:~8,2%.log"

:: 写入日志头
echo ======================================== >> "%log_file%"
echo 清理时间：%date% %time% >> "%log_file%"
echo ======================================== >> "%log_file%"

echo ========================================
echo        临时文件清理工具
echo ========================================
echo.
echo 日志保存位置：%log_dir%
echo.

:: 清理用户临时文件
echo 正在清理用户临时文件...
echo [%time%] 开始清理用户临时文件 >> "%log_file%"
cd /d "%temp%" 2>nul
if errorlevel 1 (
    echo 错误：无法访问临时文件夹！
    echo [%time%] 错误：无法访问临时文件夹 >> "%log_file%"
    pause
    exit /b
)
del /f /s /q *.* >nul 2>&1
for /d %%i in (*) do rmdir /s /q "%%i" >nul 2>&1
echo [%time%] 用户临时文件清理完成 >> "%log_file%"
echo [成功] 用户临时文件已清理！

:: 清理系统临时文件
echo 正在清理系统临时文件...
if exist "C:\Windows\Temp" (
    echo [%time%] 开始清理系统临时文件 >> "%log_file%"
    cd /d "C:\Windows\Temp" 2>nul
    del /f /s /q *.* >nul 2>&1
    for /d %%i in (*) do rmdir /s /q "%%i" >nul 2>&1
    echo [%time%] 系统临时文件清理完成 >> "%log_file%"
    echo [成功] 系统临时文件已清理！
) else (
    echo [%time%] 系统临时文件夹不存在 >> "%log_file%"
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
echo 清理结束时间：%date% %time% >> "%log_file%"
echo. >> "%log_file%"

pause