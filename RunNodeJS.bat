@echo off
title Node 脚本启动器
setlocal enabledelayedexpansion

echo ========================================
echo         Node 脚本启动器
echo ========================================
echo.

:: 检查 Node.js 是否安装
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo [错误] Node.js 未安装或不在系统路径中
    echo.
    echo 请从以下地址安装 Node.js：
    echo   https://nodejs.org/
    echo.
    echo 安装完成后，请重新运行此脚本
    echo.
    pause
    exit /b 1
)

:: 检查 nodemon 是否安装（可选）
set use_nodemon=0
where nodemon >nul 2>nul
if %errorlevel% equ 0 (
    set use_nodemon=1
)

:: 扫描当前目录下的所有脚本文件（支持 .js, .mjs, .cjs）
echo 正在扫描当前目录中的脚本文件...
echo.

set file_count=0

:: 收集所有 Node.js 支持的脚本文件
for %%i in (*.js *.mjs *.cjs) do (
    set /a file_count+=1
    set file_!file_count!=%%i
)

:: 检查是否找到脚本文件
if %file_count% equ 0 (
    echo 当前目录：%cd%
    echo [错误]：未找到任何脚本文件！
    echo [检查]：支持的文件类型：.js .mjs .cjs
    
    pause
    exit /b 1
)

:: 如果只有一个文件，直接运行
if %file_count% equ 1 (
    set selected_file=!file_1!
    echo 检测到当前目录只有一个脚本文件：
    echo   !selected_file!
    echo.
    echo 将直接运行此文件...
    echo.
    goto run_script
)

:: 显示文件列表（仅当有多个文件时）
echo 找到 %file_count% 个脚本文件：
echo.
echo ----------------------------------------
for /l %%i in (1,1,%file_count%) do (
    echo   [%%i] !file_%%i!
)
echo   [0] 退出脚本
echo ----------------------------------------
echo.

:: 让用户选择要运行的文件
:select_file
set /p file_choice="请输入文件编号（0-%file_count%），默认[1]："

:: 如果用户直接按回车，使用默认选择（第一个文件）
if "%file_choice%"=="" (
    set file_choice=1
    goto run_script
)

:: 检查输入是否为数字
set "is_num="
for /l %%i in (0,1,9) do if "%file_choice%"=="%%i" set is_num=1
if not defined is_num (
    echo 输入无效，请输入数字 0 到 %file_count%
    goto select_file
)

:: 检查数字是否在有效范围内
if %file_choice% lss 0 (
    echo 编号无效，请输入 0 到 %file_count% 之间的数字
    goto select_file
)
if %file_choice% gtr %file_count% (
    echo 编号无效，请输入 0 到 %file_count% 之间的数字
    goto select_file
)

:: 处理退出选项
if %file_choice% equ 0 (
    echo.
    echo 已退出脚本启动器
    pause
    exit /b 0
)

:run_script
:: 获取选中的文件名（如果还没设置）
if not defined selected_file (
    set selected_file=!file_%file_choice%!
)
echo.
echo ========================================
echo 已选中：!selected_file!
echo ========================================
echo.

:: 根据 nodemon 是否可用选择启动方式
if %use_nodemon% equ 1 (
    echo 使用 nodemon 启动（支持热重载）...
    echo 按 Ctrl+C 可停止
    echo ========================================
    echo.
    nodemon "!selected_file!"
) else (
    echo 使用 node 启动...
    echo 提示：安装 nodemon 可获得热重载功能
    echo       npm install -g nodemon
    echo 按 Ctrl+C 可停止
    echo ========================================
    echo.
    node "!selected_file!"
)

:: 如果程序退出，暂停查看结果
echo.
echo [信息] 脚本已停止运行
pause
exit /b 0