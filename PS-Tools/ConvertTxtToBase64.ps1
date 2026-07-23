# ConvertTxtToBase64.ps1
# 功能：列出当前目录下所有TXT文件，经用户确认后转换为Base64编码格式并另存

# 设置脚本运行目录为当前所在目录
$scriptDir = Get-Location
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "      TXT文件 Base64 转换工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "当前工作目录: $scriptDir`n" -ForegroundColor White

# 获取当前目录下所有txt文件
$txtFiles = Get-ChildItem -Path $scriptDir -Filter "*.txt" -File

if ($txtFiles.Count -eq 0) {
    Write-Host "当前目录下没有找到TXT文件。" -ForegroundColor Yellow
    Read-Host "`n按回车键退出"
    exit
}

# 列出所有TXT文件
Write-Host "找到以下 $($txtFiles.Count) 个TXT文件：" -ForegroundColor Green
Write-Host "----------------------------------------" -ForegroundColor DarkGray

$index = 0
$fileList = @()
foreach ($file in $txtFiles) {
    $index++
    $fileSize = [math]::Round($file.Length / 1KB, 2)
    Write-Host "  [$index] $($file.Name)  (大小: $fileSize KB)" -ForegroundColor White
    $fileList += $file
}

Write-Host "----------------------------------------" -ForegroundColor DarkGray
Write-Host "`n请选择要转换的文件：" -ForegroundColor Yellow
Write-Host "  [A] 转换全部文件" -ForegroundColor White
Write-Host "  [数字] 输入序号转换单个文件" -ForegroundColor White
Write-Host "  [Q] 退出不转换" -ForegroundColor White
Write-Host ""

# 获取用户输入
$userChoice = Read-Host "请输入选择 (A/数字/Q)"

# 处理用户选择
$selectedFiles = @()

if ($userChoice -eq "Q" -or $userChoice -eq "q") {
    Write-Host "`n已取消操作，未转换任何文件。" -ForegroundColor Yellow
    Read-Host "按回车键退出"
    exit
}
elseif ($userChoice -eq "A" -or $userChoice -eq "a") {
    $selectedFiles = $fileList
    Write-Host "`n已选择全部 $($selectedFiles.Count) 个文件" -ForegroundColor Green
}
else {
    # 尝试将输入转换为数字
    $numChoice = 0
    if ([int]::TryParse($userChoice, [ref]$numChoice)) {
        if ($numChoice -ge 1 -and $numChoice -le $fileList.Count) {
            $selectedFiles = @($fileList[$numChoice - 1])
            Write-Host "`n已选择: $($selectedFiles[0].Name)" -ForegroundColor Green
        } else {
            Write-Host "`n无效的序号，请输入 1 到 $($fileList.Count) 之间的数字。" -ForegroundColor Red
            Read-Host "按回车键退出"
            exit
        }
    } else {
        Write-Host "`n无效输入，请输入 A、数字序号 或 Q。" -ForegroundColor Red
        Read-Host "按回车键退出"
        exit
    }
}

# 二次确认
Write-Host "`n即将转换以下文件：" -ForegroundColor Yellow
foreach ($file in $selectedFiles) {
    Write-Host "  - $($file.Name)" -ForegroundColor White
}
$confirm = Read-Host "`n确认转换吗？(Y/N)"

if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "`n已取消操作，未转换任何文件。" -ForegroundColor Yellow
    Read-Host "按回车键退出"
    exit
}

# 开始转换
Write-Host "`n开始转换..." -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor DarkGray

$successCount = 0
$failCount = 0

foreach ($file in $selectedFiles) {
    try {
        # 读取文件全部内容（UTF8编码）
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        
        # 转换为Base64（UTF8字节）
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        $base64 = [System.Convert]::ToBase64String($bytes)
        
        # 生成输出文件名（在原文件名后加 _base64）
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $outputFileName = "$baseName`_base64.txt"
        $outputPath = Join-Path -Path $scriptDir -ChildPath $outputFileName
        
        # 写入Base64内容到新文件（纯文本，不带BOM）
        [System.IO.File]::WriteAllText($outputPath, $base64, [System.Text.Encoding]::UTF8)
        
        # 计算文件大小
        $outputSize = [math]::Round((Get-Item $outputPath).Length / 1KB, 2)
        Write-Host "  ✓ $($file.Name) -> $outputFileName ($outputSize KB)" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "  ✗ $($file.Name) 转换失败: $_" -ForegroundColor Red
        $failCount++
    }
}

# 输出汇总信息
Write-Host "----------------------------------------" -ForegroundColor DarkGray
Write-Host "========== 转换完成 ==========" -ForegroundColor Cyan
Write-Host "成功: $successCount 个" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "失败: $failCount 个" -ForegroundColor Red
}

Read-Host "`n按回车键退出"