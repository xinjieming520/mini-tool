# --- PowerShell 脚本逻辑开始 ---
$Host.UI.RawUI.WindowTitle = "MDTree - 开发者工具"
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$OutputFileName = "Project_Tree.md"
$ScriptName = $MyInvocation.MyCommand.Name

function Show-Header($Title) {
    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "          $Title" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
}

function Main-Menu {
    while ($true) {
        Show-Header "MDTree 开发者辅助工具"
        
        $items = @(
            ("1", "生成目录树", "扫描指定路径并生成 Markdown 结构"),
            ("2", "JSON 格式化/压缩", "美化或压缩本地 JSON 文件"),
            ("0", "退出脚本", "关闭工具")
        )

        foreach ($i in $items) {
            $idx = $i[0].PadLeft(2)
            $name = $i[1]
            $visualWidth = 0
            foreach ($char in $name.ToCharArray()) {
                if ([int]$char -gt 255) { $visualWidth += 2 } else { $visualWidth += 1 }
            }
            $pad = 22 - $visualWidth
            $spaces = " " * ([Math]::Max(1, $pad))
            
            Write-Host "  $idx. " -NoNewline -ForegroundColor Cyan
            Write-Host "$name" -NoNewline -ForegroundColor Green
            Write-Host "$($spaces)$($i[2])" -ForegroundColor Gray
        }
        Write-Host "===================================================="

        $choice = (Read-Host "`n请选择功能序号").Trim()
        switch ($choice) {
            "1" { Start-TreeGen }
            "2" { Start-JsonTool }
            "0" { exit }
            default { Write-Host "无效选择 [$choice]，请重试..." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# --- 目录树生成逻辑 ---
function Generate-Tree-Logic {
    param (
        [string]$Path, 
        [string]$Indent = "", 
        [string]$BaseScript, 
        [string]$BaseOutput,
        [string[]]$IgnoreList = @()
    )
    $TreeString = ""
    $Items = Get-ChildItem -Path $Path | Sort-Object PSIsContainer, Name -Descending
    
    foreach ($Item in $Items) {
        # 基础过滤 (脚本自身, 输出文件, .git 目录)
        if ($Item.Name -eq $BaseScript -or $Item.Name -eq $BaseOutput -or $Item.Name -eq ".git") { continue }
        
        # .gitignore 模式匹配 (简单通配符支持)
        $isIgnored = $false
        foreach ($pattern in $IgnoreList) {
            if ($Item.Name -like $pattern -or $Item.Name -eq $pattern.TrimEnd('/')) {
                $isIgnored = $true
                break
            }
        }
        if ($isIgnored) { continue }

        if ($Item.PSIsContainer) {
            $TreeString += "$Indent├── $($Item.Name)/`r`n"
            $TreeString += Generate-Tree-Logic -Path $Item.FullName -Indent ($Indent + "│   ") -BaseScript $BaseScript -BaseOutput $BaseOutput -IgnoreList $IgnoreList
        } else {
            $TreeString += "$Indent└── $($Item.Name)`r`n"
        }
    }
    return $TreeString
}

function Start-TreeGen {
    Show-Header "生成目录结构树"
    $targetPath = (Read-Host "请输入目标路径 (直接回车默认当前目录)").Trim()
    if (-not $targetPath) { $targetPath = (Get-Location).Path }
    
    if (-not (Test-Path $targetPath)) {
        Write-Host "错误：路径不存在！" -ForegroundColor Red
        Pause-Menu; return
    }

    Write-Host "正在生成，请稍候..." -ForegroundColor Gray
    try {
        # 加载 .gitignore 规则
        $ignoreList = @()
        $giPath = Join-Path $targetPath ".gitignore"
        if (Test-Path $giPath) {
            $ignoreList = Get-Content $giPath | Where-Object { $_ -and $_ -notmatch '^#' } | ForEach-Object { $_.Trim() }
        }

        $Content = "# 目录结构视图`r`n`r`n- **生成路径**: ``" + $targetPath + "`` `r`n`r`n"
        $Content += '```text' + "`r`n. (根目录)`r`n"
        $Content += Generate-Tree-Logic -Path $targetPath -BaseScript $ScriptName -BaseOutput $OutputFileName -IgnoreList $ignoreList
        $Content += '```'
        
        $finalOutputPath = Join-Path $targetPath $OutputFileName
        $Content | Set-Content -Path $finalOutputPath -Encoding UTF8
        Write-Host "`n[成功] 目录树已生成至: $finalOutputPath" -ForegroundColor Green
    } catch {
        Write-Host "`n[错误] 生成失败: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Menu
}

# --- JSON 工具逻辑 ---
function Start-JsonTool {
    Show-Header "JSON 格式化/压缩"
    $filePath = (Read-Host "请输入 JSON 文件的完整路径").Trim()
    if (-not (Test-Path $filePath)) {
        Write-Host "错误：文件不存在！" -ForegroundColor Red
        Pause-Menu; return
    }

    Write-Host "`n选择模式:" -ForegroundColor Yellow
    Write-Host "  1. 格式化 (美化)"
    Write-Host "  2. 压缩 (Minify)"
    $mode = Read-Host "请选择"

    try {
        $rawJson = Get-Content -Path $filePath -Raw -ErrorAction Stop
        $jsonObject = $rawJson | ConvertFrom-Json
        
        if ($mode -eq "1") {
            $result = $jsonObject | ConvertTo-Json -Depth 100
            $suffix = ".formatted.json"
        } else {
            $result = $jsonObject | ConvertTo-Json -Compress
            $suffix = ".minified.json"
        }
        
        # 构造新文件名，避免覆盖
        $newPath = [System.IO.Path]::ChangeExtension($filePath, $suffix)
        $result | Set-Content -Path $newPath -Encoding UTF8
        Write-Host "`n[成功] 处理完成！" -ForegroundColor Green
        Write-Host "保存位置: $newPath" -ForegroundColor Gray
    } catch {
        Write-Host "`n[错误] 处理失败，请确保文件是有效的 JSON 格式。" -ForegroundColor Red
    }
    Pause-Menu
}

function Pause-Menu {
    Write-Host "`n按回车键返回主菜单..."
    $null = Read-Host
}

# 启动程序
Main-Menu
