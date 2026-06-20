@echo off
chcp 65001 >nul 2>&1

REM 设置中央工具路径（只需修改此处即可更新工具版本）
set "TOOL_PATH=D:\myproject\AIscript\PS-Tools\Test-PSModules\Test-PSModules.ps1"

REM 获取当前 .bat 文件所在目录（报告将生成在此处）
set "CURRENT_DIR=%~dp0"
set "CURRENT_DIR=%CURRENT_DIR:~0,-1%"

echo ========================================
echo   PowerShell 脚本/模块自动测试工具
echo ========================================
echo.
echo 工具路径: %TOOL_PATH%
echo 当前目录: %CURRENT_DIR%
echo.

REM 检查工具是否存在
if not exist "%TOOL_PATH%" (
    echo [错误] 找不到测试工具！
    echo 请确认 TOOL_PATH 设置正确：
    echo   %TOOL_PATH%
    echo.
    pause
    exit /b 1
)

REM 切换到 .bat 所在目录（确保报告生成在正确位置）
cd /d "%CURRENT_DIR%"

echo 开始测试...
echo.

REM 运行测试工具（设置 UTF-8 输出编码，避免乱码）
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '%TOOL_PATH%' -Auto -VerboseOutput; if ($LASTEXITCODE -ne 0) { pause; exit $LASTEXITCODE }"

REM 报告生成提示
if exist "%CURRENT_DIR%\test_result.txt" (
    echo.
    echo ========================================
    echo   测试报告已生成：
    echo   %CURRENT_DIR%\test_result.txt
    echo ========================================
)

echo.
pause
