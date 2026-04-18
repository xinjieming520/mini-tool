<# :
@echo off
title 开发者实用工具箱 - Generator Pro
:: 以绕过策略的方式启动内部 PowerShell 脚本
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content '%~f0' -Encoding UTF8) -join [Environment]::NewLine)"
exit /b
#>

# --- PowerShell 核心逻辑 ---
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$GENERATE_COUNT = 3  # 默认生成数量

function Show-Header($Title) {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "          $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Main-Menu {
    while ($true) {
        Show-Header "开发者工具箱 Pro - 主菜单"
        Write-Host "  1. 生成 UUID (v4)"
        Write-Host "  2. 生成随机密码"
        Write-Host "  3. 获取时间戳 (Unix)"
        Write-Host "  4. 生成随机数"
        Write-Host "  5. Base64 编码/解码"
        Write-Host "  6. 文本哈希 (MD5/SHA256)"
        Write-Host "  7. 修改生成数量 (当前: $GENERATE_COUNT)"
        Write-Host "  0. 退出脚本"
        Write-Host "========================================"
        
        $choice = Read-Host "`n请选择"
        switch ($choice) {
            "1" { Generate-UUIDs }
            "2" { Generate-Passwords }
            "3" { Get-Timestamps }
            "4" { Generate-RandomNumbers }
            "5" { Base64-Codec }
            "6" { Text-Hasher }
            "7" { Set-Count }
            "0" { exit }
            default { Write-Host "无效选择，请重试..." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

function Generate-UUIDs {
    Show-Header "生成 UUID (标准 v4)"
    $results = for ($i=1; $i -le $GENERATE_COUNT; $i++) {
        $u = [guid]::NewGuid().ToString()
        Write-Host "  $u" -ForegroundColor Green
        $u
    }
    $results[0] | Set-Clipboard
    Write-Host "`n[提示] 第一条 UUID 已自动复制到剪贴板。" -ForegroundColor Gray
    Pause-Menu
}

function Generate-Passwords {
    Show-Header "生成随机密码"
    $inputLen = (Read-Host "请输入密码长度 (默认 16, 范围 8-128)").Trim()
    $passwordLength = 16
    if ($inputLen -match '^\d+$') {
        $val = [int]$inputLen
        if ($val -ge 8 -and $val -le 128) { $passwordLength = $val }
    }
    
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?"
    $results = for ($i=1; $i -le $GENERATE_COUNT; $i++) {
        $pass = -join ((1..$passwordLength) | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
        Write-Host "  $pass" -ForegroundColor Green
        $pass
    }
    $results[0] | Set-Clipboard
    Write-Host "`n[提示] 第一条密码已自动复制到剪贴板。" -ForegroundColor Gray
    Pause-Menu
}

function Base64-Codec {
    Show-Header "Base64 编解码"
    Write-Host "  1. 文本 -> Base64 (编码)"
    Write-Host "  2. Base64 -> 文本 (解码)"
    $mode = Read-Host "`n请选择模式 (1 或 2)"
    $text = Read-Host "请输入内容"
    if (-not $text) { return }

    try {
        if ($mode -eq "1") {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
            $res = [System.Convert]::ToBase64String($bytes)
            Write-Host "`n编码结果: " -NoNewline; Write-Host $res -ForegroundColor Green
            $res | Set-Clipboard
        } else {
            $bytes = [System.Convert]::FromBase64String($text)
            $res = [System.Text.Encoding]::UTF8.GetString($bytes)
            Write-Host "`n解码结果: " -NoNewline; Write-Host $res -ForegroundColor Green
            $res | Set-Clipboard
        }
        Write-Host "[提示] 结果已复制到剪贴板。" -ForegroundColor Gray
    } catch {
        Write-Host "`n[错误] 编解码失败，请检查输入格式。" -ForegroundColor Red
    }
    Pause-Menu
}

function Text-Hasher {
    Show-Header "文本哈希计算 (UTF-8)"
    $text = Read-Host "请输入要计算的文本"
    if (-not $text) { return }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    
    $getHashStr = {
        param($alg, $data)
        $hashBytes = $alg.ComputeHash($data)
        return -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
    }

    $hMD5 = &$getHashStr $md5 $bytes
    $hSHA = &$getHashStr $sha256 $bytes

    Write-Host "`nMD5:    " -NoNewline; Write-Host $hMD5 -ForegroundColor Green
    Write-Host "SHA256: " -NoNewline; Write-Host $hSHA -ForegroundColor Green
    
    $hSHA | Set-Clipboard
    Write-Host "`n[提示] SHA256 结果已复制到剪贴板。" -ForegroundColor Gray
    Pause-Menu
}

function Get-Timestamps {
    Show-Header "时间戳获取"
    $now = Get-Date
    $unix = [int]([DateTimeOffset]$now).ToUnixTimeSeconds()
    $unixMs = [long]([DateTimeOffset]$now).ToUnixTimeMilliseconds()
    
    Write-Host "`n本地时间: " -NoNewline; Write-Host $now.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Green
    Write-Host "Unix 秒:  " -NoNewline; Write-Host $unix -ForegroundColor Green
    Write-Host "Unix 毫秒: " -NoNewline; Write-Host $unixMs -ForegroundColor Green
    
    $unix.ToString() | Set-Clipboard
    Write-Host "`n[提示] Unix 秒戳已复制到剪贴板。" -ForegroundColor Gray
    Pause-Menu
}

function Generate-RandomNumbers {
    Show-Header "生成随机数"
    $rawMin = (Read-Host "请输入最小值 (默认 1)").Trim()
    $rawMax = (Read-Host "请输入最大值 (默认 100)").Trim()
    
    $nMin = if ($rawMin -match '^-?\d+$') { [long]$rawMin } else { 1 }
    $nMax = if ($rawMax -match '^-?\d+$') { [long]$rawMax } else { 100 }
    
    if ($nMax -le $nMin) { 
        Write-Host "错误：最大值必须大于最小值！" -ForegroundColor Red
        Start-Sleep -Seconds 1; return 
    }

    Write-Host "`n范围 [$nMin - $nMax] 内的 $GENERATE_COUNT 个随机数:" -ForegroundColor Yellow
    for ($i=1; $i -le $GENERATE_COUNT; $i++) {
        $num = Get-Random -Minimum $nMin -Maximum ($nMax + 1)
        Write-Host "  第 $i 个: " -NoNewline; Write-Host $num -ForegroundColor Green
    }
    Pause-Menu
}

function Set-Count {
    $count = (Read-Host "请输入每次生成的数量 (当前: $GENERATE_COUNT)").Trim()
    if ($count -match '^\d+$' -and [int]$count -gt 0) {
        $script:GENERATE_COUNT = [int]$count
        Write-Host "设置成功！" -ForegroundColor Green
    } else {
        Write-Host "输入无效。" -ForegroundColor Red
    }
    Start-Sleep -Seconds 1
}

function Pause-Menu {
    Write-Host "`n按任意键返回主菜单..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# 启动主菜单
Main-Menu
