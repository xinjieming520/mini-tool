# --- PowerShell 脚本逻辑开始 ---
$Host.UI.RawUI.WindowTitle = "TempCleaner_Pro - 安全专家清理工具"
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Global:TotalDeleted = 0

# 默认只清理 1 天前的文件，防止误伤正在运行的安装程序
$DaysToKeep = 1
$CutoffDate = (Get-Date).AddDays(-$DaysToKeep)

function Clean-Routine($Path, $Name, $Exclude = @(), $IgnoreAge = $false) {
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[状态] 正在处理: " -NoNewline; Write-Host $Name -ForegroundColor White -BackgroundColor Blue
    
    $targetPath = [System.Environment]::ExpandEnvironmentVariables($Path)
    if (-not (Test-Path $targetPath)) {
        Write-Host "   [跳过] 路径不存在或无权访问" -ForegroundColor Gray
        return
    }

    Write-Host "   目标路径: $targetPath" -ForegroundColor Gray
    
    # 扫描可清理项
    $items = Get-ChildItem -Path $targetPath -Force -Recurse | Where-Object {
        $item = $_
        $isExcluded = $false
        foreach ($ex in $Exclude) { if ($item.FullName -like "*$ex*") { $isExcluded = $true; break } }
        
        # 核心逻辑：如果是文件夹，只在它本身不是排除项时继续；如果是文件，检查日期
        $ageOk = $IgnoreAge -or ($item.LastWriteTime -lt $CutoffDate)
        
        (-not $isExcluded) -and $ageOk
    }

    $itemsBefore = ($items).Count
    Write-Host "   扫描中... 发现 $itemsBefore 个安全清理项" -ForegroundColor Gray
    
    # 执行清理
    $items | ForEach-Object {
        if (-not $_.PSIsContainer) {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    # 第二遍清理空文件夹
    Get-ChildItem -Path $targetPath -Force -Recurse | Where-Object { $_.PSIsContainer -and (Get-ChildItem -Path $_.FullName).Count -eq 0 } | Remove-Item -Recurse -Force

    $itemsAfter = (Get-ChildItem -Path $targetPath -Recurse -Force | Where-Object { 
        $item = $_
        $isExcluded = $false
        foreach ($ex in $Exclude) { if ($item.FullName -like "*$ex*") { $isExcluded = $true; break } }
        (-not $isExcluded)
    }).Count
    
    $deletedCount = [Math]::Max(0, $itemsBefore - ($itemsAfter - (Get-ChildItem -Path $targetPath -Recurse -Force).Count))
    # 简化统计：直接以成功删除的计数为准
    $Global:TotalDeleted += $itemsBefore

    Write-Host "   清理完成。" -ForegroundColor Gray
    if ($itemsBefore -gt 0) {
        Write-Host "   [成功] 计划清理了 $itemsBefore 个项目。" -ForegroundColor Green
    } else {
        Write-Host "   [提示] 没有满足时间条件的项目。" -ForegroundColor Yellow
    }
}

# 1. 绘制头部
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "               TempCleaner_Pro (安全清理专家)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " [规则] 当前设置为只清理 $($DaysToKeep) 天前的文件，确保系统安全。" -ForegroundColor Gray
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
Clean-Routine -Path "C:\Windows\Prefetch" -Name "系统预取文件"
Clean-Routine -Path "C:\Windows\SoftwareDistribution\Download" -Name "Windows 更新下载缓存"
Clean-Routine -Path "$env:LOCALAPPDATA\CrashDumps" -Name "程序崩溃转储" -IgnoreAge $true

# 关键修复：保护固定快捷方式 + 保护终端历史记录
$recentExclude = @("AutomaticDestinations", "CustomDestinations")
Clean-Routine -Path "$env:APPDATA\Microsoft\Windows\Recent" -Name "最近使用的项目记录" -Exclude $recentExclude -IgnoreAge $true

# 保护 PowerShell 历史记录
$logsExclude = @("ConsoleHost_history.txt")
Clean-Routine -Path "C:\Windows\Logs" -Name "系统运行日志" -Exclude $logsExclude

# 4. 总结报告
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "`n========================= 清理总结 =========================" -ForegroundColor Cyan
Write-Host "   扫描完成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "   清理项目总数: " -NoNewline; Write-Host "$Global:TotalDeleted 个" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "`n清理完成。所有 24 小时内修改过的文件已被保留。"
Write-Host "按回车键退出..."
$null = Read-Host
