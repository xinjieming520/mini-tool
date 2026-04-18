<# :
@echo off
title TempCleaner_Pro - 高级深度清理版
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content '%~f0') -join [Environment]::NewLine)"
exit /b
#>

# --- PowerShell 脚本逻辑开始 ---
$ErrorActionPreference = "SilentlyContinue"
$Global:TotalDeleted = 0

function Clean-Routine($Path, $Name) {
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[任务] 正在处理: " -NoNewline; Write-Host $Name -ForegroundColor White -BackgroundColor Blue
    
    # 解析路径（确保处理了环境变量）
    $targetPath = [System.Environment]::ExpandEnvironmentVariables($Path)
    
    if (-not (Test-Path $targetPath)) {
        Write-Host "   [跳过] 路径不存在" -ForegroundColor Gray
        return
    }

    Write-Host "   目标路径: $targetPath" -ForegroundColor Gray
    
    # 统计清理前的项目总数
    $itemsBefore = (Get-ChildItem -Path $targetPath -Recurse -Force).Count
    Write-Host "   分析中... 发现 $itemsBefore 个项目" -ForegroundColor Gray
    
    # 执行清理
    Write-Host "   正在执行清理..." -ForegroundColor DarkYellow
    Get-ChildItem -Path $targetPath -Force | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 统计清理后的剩余数
    $itemsAfter = (Get-ChildItem -Path $targetPath -Recurse -Force).Count
    $deletedCount = [Math]::Max(0, $itemsBefore - $itemsAfter)
    $Global:TotalDeleted += $deletedCount

    # 详细结果输出
    Write-Host "   清理结果: " -NoNewline
    Write-Host "之前 ($itemsBefore) -> 之后 ($itemsAfter)" -ForegroundColor Gray
    
    if ($deletedCount -gt 0) {
        Write-Host "   [成功] 本次释放了 $deletedCount 个项目！" -ForegroundColor Green
    } else {
        Write-Host "   [提示] 没有可清理的项目或正在被占用。" -ForegroundColor Yellow
    }
}

# 1. 界面头部
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "               TempCleaner_Pro (高级深度清理)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 2. 权限检查
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [! 警告] 未以管理员身份运行。更新缓存、预取文件等系统路径将无法清理！" -ForegroundColor Black -BackgroundColor Yellow
    Write-Host ""
}

# 3. 执行清理清单
Clean-Routine -Path "$env:TEMP" -Name "用户临时文件"
Clean-Routine -Path "C:\Windows\Temp" -Name "系统临时文件"
Clean-Routine -Path "C:\Windows\Prefetch" -Name "系统预取文件 (Prefetch)"
Clean-Routine -Path "C:\Windows\SoftwareDistribution\Download" -Name "Windows 更新下载缓存"
Clean-Routine -Path "$env:LOCALAPPDATA\CrashDumps" -Name "程序崩溃转储 (Crash Dumps)"
Clean-Routine -Path "$env:APPDATA\Microsoft\Windows\Recent" -Name "最近访问的项目记录"
Clean-Routine -Path "C:\Windows\Logs" -Name "系统运行日志"

# 4. 总结面板
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "`n========================= 清理总结 =========================" -ForegroundColor Cyan
Write-Host "   任务完成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "   累计释放项目: " -NoNewline; Write-Host "$Global:TotalDeleted 个" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "`n清理完成。建议定期以管理员权限运行本脚本。"
Write-Host "按下回车键退出..."
Read-Host
