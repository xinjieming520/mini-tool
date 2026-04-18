<# :
@echo off
title TempCleaner_Pro - PowerShell 深度清理
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content '%~f0') -join [Environment]::NewLine)"
exit /b
#>

# --- PowerShell 脚本逻辑开始 ---
$ErrorActionPreference = "SilentlyContinue"
$Global:TotalDeleted = 0

function Clean-Routine($Path, $Name) {
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[任务] 正在处理: " -NoNewline; Write-Host $Name -ForegroundColor White -BackgroundColor Blue
    
    if (-not (Test-Path $Path)) {
        Write-Host "   [跳过] 路径不存在: $Path" -ForegroundColor Red
        return
    }

    Write-Host "   目标路径: $Path" -ForegroundColor Gray
    
    # 统计清理前的项目总数
    $itemsBefore = (Get-ChildItem -Path $Path -Recurse -Force).Count
    Write-Host "   分析中... 发现 $itemsBefore 个项目" -ForegroundColor Gray
    
    # 执行清理
    Write-Host "   正在执行删除指令..." -ForegroundColor DarkYellow
    Get-ChildItem -Path $Path -Force | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 统计清理后的剩余数
    $itemsAfter = (Get-ChildItem -Path $Path -Recurse -Force).Count
    $deletedCount = [Math]::Max(0, $itemsBefore - $itemsAfter)
    $Global:TotalDeleted += $deletedCount

    # 详细结果输出
    Write-Host "   清理完成: " -NoNewline
    Write-Host "之前 ($itemsBefore) " -ForegroundColor Gray -NoNewline
    Write-Host "-> " -NoNewline
    Write-Host "之后 ($itemsAfter)" -ForegroundColor Gray
    
    if ($deletedCount -gt 0) {
        Write-Host "   [成功] 本次释放了 $deletedCount 个项目！" -ForegroundColor Green
    } else {
        Write-Host "   [提示] 没有可清理的项目或项目正被占用。" -ForegroundColor Yellow
    }
}

# 1. 界面头部
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "               TempCleaner_Pro (PowerShell 核心)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 2. 权限检查
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [! 警告] 未以管理员身份运行，系统级别文件可能无法完全删除。" -ForegroundColor Black -BackgroundColor Yellow
    Write-Host ""
}

# 3. 执行清理
Clean-Routine -Path $env:TEMP -Name "用户临时文件"
Clean-Routine -Path "C:\Windows\Temp" -Name "系统临时文件"

# 4. 总结面板
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "`n========================= 清理总结 =========================" -ForegroundColor Cyan
Write-Host "   任务完成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "   累计释放项目: " -NoNewline; Write-Host "$Global:TotalDeleted 个" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "`n按下回车键退出..."
Read-Host
