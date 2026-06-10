# --- PowerShell 脚本逻辑开始 ---
$Host.UI.RawUI.WindowTitle = "TempCleaner_Pro - 高级系统清理工具"
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Global:TotalDeleted = 0

function Clean-Routine($Path, $Name) {
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[状态] 正在处理: " -NoNewline; Write-Host $Name -ForegroundColor White -BackgroundColor Blue
    
    # 扩展路径（确保支持环境变量路径）
    $targetPath = [System.Environment]::ExpandEnvironmentVariables($Path)
    
    if (-not (Test-Path $targetPath)) {
        Write-Host "   [跳过] 路径不存在或无权访问" -ForegroundColor Gray
        return
    }

    Write-Host "   目标路径: $targetPath" -ForegroundColor Gray
    
    # 统计清理前的项目总数
    $itemsBefore = (Get-ChildItem -Path $targetPath -Recurse -Force).Count
    Write-Host "   扫描中... 发现 $itemsBefore 个项目" -ForegroundColor Gray
    
    # 执行清理
    Write-Host "   正在执行清理..." -ForegroundColor DarkYellow
    Get-ChildItem -Path $targetPath -Force | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 统计清理后的剩余项
    $itemsAfter = (Get-ChildItem -Path $targetPath -Recurse -Force).Count
    $deletedCount = [Math]::Max(0, $itemsBefore - $itemsAfter)
    $Global:TotalDeleted += $deletedCount

    # 详细结果反馈
    Write-Host "   清理完成: " -NoNewline
    Write-Host "之前 ($itemsBefore) -> 之后 ($itemsAfter)" -ForegroundColor Gray
    
    if ($deletedCount -gt 0) {
        Write-Host "   [成功] 累计释放了 $deletedCount 个项目。" -ForegroundColor Green
    } else {
        Write-Host "   [提示] 没有可清理的项目，或项目正被占用。" -ForegroundColor Yellow
    }
}

# 1. 绘制头部
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "               TempCleaner_Pro (高级系统清理)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 2. 权限检查
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [! 警告] 未以管理员权限运行！某些系统文件夹将无法清理。" -ForegroundColor Black -BackgroundColor Yellow
    Write-Host ""
}

# 3. 执行清理清单
Clean-Routine -Path "$env:TEMP" -Name "用户临时文件"
Clean-Routine -Path "C:\Windows\Temp" -Name "系统临时文件"
Clean-Routine -Path "C:\Windows\Prefetch" -Name "系统预取文件 (Prefetch)"
Clean-Routine -Path "C:\Windows\SoftwareDistribution\Download" -Name "Windows 更新下载缓存"
Clean-Routine -Path "$env:LOCALAPPDATA\CrashDumps" -Name "程序崩溃转储 (Crash Dumps)"
Clean-Routine -Path "$env:APPDATA\Microsoft\Windows\Recent" -Name "最近使用的项目记录"
Clean-Routine -Path "C:\Windows\Logs" -Name "系统运行日志"

# 4. 总结报告
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "`n========================= 清理总结 =========================" -ForegroundColor Cyan
Write-Host "   扫描完成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "   累计释放项目: " -NoNewline; Write-Host "$Global:TotalDeleted 个" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "`n清理完成。建议定期以管理员权限运行此脚本。"
Write-Host "按回车键退出..."
Read-Host
