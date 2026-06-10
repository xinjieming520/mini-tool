# --- PowerShell 脚本逻辑开始 ---
$OutputFileName = "目录结构.md"
$CurrentDir = Get-Location
$ScriptName = $MyInvocation.MyCommand.Name

# 设置控制台输出编码为 UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Generate-Tree {
    param (
        [string]$Path,
        [string]$Indent = ""
    )
    
    $TreeString = ""
    # 获取当前目录下的所有项，优先排列文件夹，然后按名称排序
    $Items = Get-ChildItem -Path $Path | Sort-Object PSIsContainer, Name -Descending
    
    foreach ($Item in $Items) {
        # 排除脚本自身和生成的输出文件
        if ($Item.Name -eq $ScriptName -or $Item.Name -eq $OutputFileName) { continue }
        
        if ($Item.PSIsContainer) {
            # 写入文件夹名称
            $TreeString += "$Indent├── $($Item.Name)/`r`n"
            # 递归处理子文件夹
            $TreeString += Generate-Tree -Path $Item.FullName -Indent ($Indent + "│   ")
        } else {
            # 写入文件名称
            $TreeString += "$Indent└── $($Item.Name)`r`n"
        }
    }
    return $TreeString
}

try {
    Write-Host "正在生成目录结构..." -ForegroundColor Gray
    
    $Content = "# 目录结构视图`r`n`r`n"
    $Content += "- **生成路径**: ``$($CurrentDir.Path)`` `r`n`r`n"
    $Content += '```text' + "`r`n"
    $Content += ". (根目录)`r`n"
    $Content += Generate-Tree -Path $CurrentDir.Path
    $Content += '```'
    
    # 写入文件，确保使用 UTF8 编码
    $Content | Set-Content -Path (Join-Path $CurrentDir.Path $OutputFileName) -Encoding UTF8
    
    Write-Host "生成成功！请查看文件: $OutputFileName" -ForegroundColor Green
} catch {
    Write-Host "发生错误: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n按回车键退出..."
$null = Read-Host
