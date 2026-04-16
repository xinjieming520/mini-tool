@echo off
title Python脚本运行器
setlocal enabledelayedexpansion

:MAIN
cls
:: 获取当前目录下的.py文件
set count=0
set "file_list="
echo 正在扫描当前目录中的Python脚本...
echo.

for %%f in (*.py) do (
    set /a count+=1
    set "file_!count!=%%f"
    set "file_list=!file_list! %%f"
)

:: 检查是否找到脚本文件
if !count!==0 (
    echo 当前目录：%cd%
    echo [错误]：未找到任何Python脚本文件！
    echo [检查]：支持的文件类型：.py
    echo.
    echo 按回车退出...
    pause >nul
    goto EXIT
)

:: 如果只有一个文件，直接运行
if !count!==1 (
    set selected_file=!file_1!
    echo 检测到当前目录只有一个Python脚本：
    echo   !selected_file!
    echo.
    echo 将直接运行此文件...
    echo.
    goto RUN_SCRIPT
)

:: 显示文件列表（仅当有多个文件时）
cls
echo 可运行的Python脚本：
echo -------------------------------
for /l %%i in (1,1,!count!) do (
    echo   %%i. !file_%%i!
)
echo   0. 退出
echo -------------------------------

:: 用户输入选择脚本
:SELECT_SCRIPT
echo 请输入脚本序号(1-!count!), 直接回车默认选择1：
set /p choice=请选择：
if "!choice!"=="" (
    set choice=1
    set valid=1
    set selected_file=!file_1!
    goto RUN_SCRIPT
)
if /i "!choice!"=="0" goto EXIT

:: 验证输入是否为数字且有效
set valid=0
for /l %%i in (1,1,!count!) do (
    if "!choice!"=="%%i" (
        set valid=1
        set selected_file=!file_%%i!
    )
)
if !valid!==0 (
    cls
    echo 错误：无效的选择！
    echo 按任意键重新选择...
    pause >nul
    goto MAIN
)
goto RUN_SCRIPT

:RUN_SCRIPT
:: 设置默认运行环境
set "python_cmd=python"
:: 检查选择的命令是否存在
where !python_cmd! >nul 2>&1
if errorlevel 1 (
    cls
    echo 错误：命令 "!python_cmd!" 未找到。请确保已安装并添加到PATH。
    echo 按任意键返回主菜单...
    pause >nul
    goto MAIN
)

cls
echo ========================================
echo 正在运行：!selected_file!
echo ========================================
echo.
!python_cmd! "!selected_file!"
set run_error=!errorlevel!
echo.
echo ========================================
if !run_error! neq 0 (
    echo 错误：运行失败（错误代码: !run_error!）
    echo 请检查环境和 !selected_file! 文件
) else (
    echo 脚本运行完成
)
echo ========================================
echo.

:: 询问是否继续运行其他脚本（默认n）
set "continue="
set /p continue=是否继续运行其他脚本？(Y/n, 默认Y)：
if /i "!continue!"=="y" goto MAIN
if /i "!continue!"=="" goto MAIN
goto EXIT

:EXIT
cls
echo.
echo 感谢使用！再见！
echo.
timeout /t 1 >nul
exit