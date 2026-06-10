# --- PowerShell 脚本逻辑开始 ---
$Host.UI.RawUI.WindowTitle = "MDTree - 开发者工具箱"
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$MDOutputFileName = "Project_Tree.md"
$HTMLOutputFileName = "Project_Tree.html"
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
            ("1", "增强目录树生成", "生成带大小/日期的 MD & HTML 视图"),
            ("2", "JSON 格式化/压缩", "美化或压缩本地 JSON 文件"),
            ("3", "图片转 Base64", "将图片转换为 Base64 编码文本"),
            ("0", "退出脚本", "关闭工具")
        )

        foreach ($i in $items) {
            $idx = $i[0].PadLeft(2)
            $name = $i[1]
            $visualWidth = 0
            foreach ($char in $name.ToCharArray()) { if ([int]$char -gt 255) { $visualWidth += 2 } else { $visualWidth += 1 } }
            $pad = 22 - $visualWidth
            $spaces = " " * ([Math]::Max(1, $pad))
            Write-Host "  $idx. " -NoNewline -ForegroundColor Cyan
            Write-Host "$name" -NoNewline -ForegroundColor Green
            Write-Host "$($spaces)$($i[2])" -ForegroundColor Gray
        }
        Write-Host "===================================================="

        $choice = (Read-Host "`n请选择功能序号").Trim()
        switch ($choice) {
            "1" { Start-TreeGen-Enhanced }
            "2" { Start-JsonTool }
            "3" { Convert-ImageToBase64 }
            "0" { exit }
            default { Write-Host "无效选择 [$choice]，请重试..." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# --- 增强型目录树逻辑 ---
function Get-FriendlySize($Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Generate-Tree-Enhanced {
    param ([string]$Path, [string]$Indent = "", [string[]]$IgnoreList = @())
    $TreeString = ""
    $Items = Get-ChildItem -Path $Path | Sort-Object PSIsContainer, Name -Descending
    foreach ($Item in $Items) {
        if ($Item.Name -eq $ScriptName -or $Item.Name -eq $MDOutputFileName -or $Item.Name -eq $HTMLOutputFileName -or $Item.Name -eq ".git") { continue }
        $isIgnored = $false
        foreach ($pattern in $IgnoreList) { if ($Item.Name -like $pattern -or $Item.Name -eq $pattern.TrimEnd('/')) { $isIgnored = $true; break } }
        if ($isIgnored) { continue }

        if ($Item.PSIsContainer) {
            $TreeString += "$Indent├── $($Item.Name)/`r`n"
            $TreeString += Generate-Tree-Enhanced -Path $Item.FullName -Indent ($Indent + "│   ") -IgnoreList $IgnoreList
        } else {
            $size = Get-FriendlySize $Item.Length
            $date = $Item.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            $TreeString += "$Indent└── $($Item.Name.PadRight(30)) | $($size.PadLeft(10)) | $date`r`n"
        }
    }
    return $TreeString
}

function Start-TreeGen-Enhanced {
    Show-Header "增强型目录结构生成"
    $targetPath = (Read-Host "请输入目标路径 (直接回车默认当前目录)").Trim()
    if (-not $targetPath) { $targetPath = (Get-Location).Path }
    if (-not (Test-Path $targetPath)) { Write-Host "错误：路径不存在！" -ForegroundColor Red; Pause-Menu; return }

    Write-Host "正在扫描并生成报表..." -ForegroundColor Gray
    try {
        $ignoreList = @()
        $giPath = Join-Path $targetPath ".gitignore"
        if (Test-Path $giPath) { $ignoreList = Get-Content $giPath | Where-Object { $_ -and $_ -notmatch '^#' } | ForEach-Object { $_.Trim() } }

        $TreeBody = Generate-Tree-Enhanced -Path $targetPath -IgnoreList $ignoreList
        $MDContent = "# 项目目录结构报表`r`n`r`n- **生成路径**: ``$targetPath`` `r`n- **生成时间**: $(Get-Date)`r`n`r`n| 文件名称 | 大小 | 修改日期 |`r`n| :--- | :---: | :--- |`r`n" + '```text' + "`r`n. (根目录)`r`n$TreeBody" + '```'
        $MDContent | Set-Content -Path (Join-Path $targetPath $MDOutputFileName) -Encoding UTF8
        $HTMLContent = "<html><head><meta charset='utf-8'><title>Project Tree</title><style>body{font-family:monospace;background:#1e1e1e;color:#d4d4d4;padding:20px;}pre{background:#252526;padding:15px;border-radius:5px;border:1px solid #333;}h2{color:#4ec9b0;}</style></head><body><h2>项目结构视图</h2><p>路径: $targetPath <br>时间: $(Get-Date)</p><pre>. (根目录)`n$TreeBody</pre></body></html>"
        $HTMLContent | Set-Content -Path (Join-Path $targetPath $HTMLOutputFileName) -Encoding UTF8
        Write-Host "`n[成功] 已生成 Markdown 与 HTML 报表。" -ForegroundColor Green
    } catch { Write-Host "`n[错误] 生成失败。" -ForegroundColor Red }
    Pause-Menu
}

# --- 图片转 Base64 ---
function Convert-ImageToBase64 {
    Show-Header "图片转 Base64"
    $filePath = (Read-Host "请输入图片文件完整路径").Trim()
    if (-not (Test-Path $filePath)) { Write-Host "错误：文件不存在！" -ForegroundColor Red; Pause-Menu; return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $base64 = [System.Convert]::ToBase64String($bytes)
        $ext = [System.IO.Path]::GetExtension($filePath).Replace(".", "")
        "![image](data:image/$ext;base64,$base64)" | Set-Clipboard
        Write-Host "`n[成功] 已转换为 Markdown 语法并复制到剪贴板！" -ForegroundColor Green
    } catch { Write-Host "`n[错误] 转换失败。" -ForegroundColor Red }
    Pause-Menu
}

# --- 原有 JSON 工具逻辑 ---
function Start-JsonTool {
    Show-Header "JSON 格式化/压缩"
    $filePath = (Read-Host "请输入 JSON 文件的完整路径").Trim()
    if (-not (Test-Path $filePath)) { Write-Host "错误：文件不存在！" -ForegroundColor Red; Pause-Menu; return }
    Write-Host "`n选择模式: 1. 美化 2. 压缩" -ForegroundColor Yellow
    $mode = Read-Host "请选择"
    try {
        $jsonObject = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        $result = if ($mode -eq "1") { $jsonObject | ConvertTo-Json -Depth 100 } else { $jsonObject | ConvertTo-Json -Compress }
        $suffix = if ($mode -eq "1") { ".formatted.json" } else { ".minified.json" }
        $newPath = [System.IO.Path]::ChangeExtension($filePath, $suffix)
        $result | Set-Content -Path $newPath -Encoding UTF8
        Write-Host "`n[成功] 保存至: $newPath" -ForegroundColor Green
    } catch { Write-Host "`n[错误] 处理失败。" -ForegroundColor Red }
    Pause-Menu
}

function Pause-Menu { Write-Host "`n按回车键返回主菜单..."; $null = Read-Host }

Main-Menu
