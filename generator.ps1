# --- PowerShell 核心逻辑 ---
$Host.UI.RawUI.WindowTitle = "Generator"
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$GENERATE_COUNT = 3  # 默认生成数量

function Show-Header($Title) {
    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "          $Title" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
}

function Main-Menu {
    while ($true) {
        Show-Header "开发者工具箱 - 主菜单"
        
        # 定义菜单项: 序号, 名称, 说明
        $items = @(
            ("1",  "生成UUID(v4)",      "标准v4格式，自动复制"),
            ("2",  "生成随机密码",       "支持自定义长度与字符集"),
            ("3",  "获取时间戳(Unix)",   "获取秒与毫秒级时间戳"),
            ("4",  "生成随机数",         "自定义范围内的随机数值"),
            ("5",  "Base64编码/解码",   "UTF-8文本双向转换"),
            ("6",  "文本哈希计算",       "计算MD5与SHA256值"),
            ("7",  "本机内外网IP",      "查询网卡信息与公网IP(v4/v6)"),
            ("8",  "本地端口占用检查",   "查看本地端口及关联进程"),
            ("9",  "Cron表达式解释",    "解析5位标准Cron含义"),
            ("10", "颜色代码转换",       "HEX与RGB颜色互转"),
            ("11", "修改生成数量",       "当前设置: $GENERATE_COUNT 条"),
            ("0",  "退出脚本",           "关闭工具箱")
        )

        foreach ($i in $items) {
            $idx = $i[0].PadLeft(2)
            $name = $i[1]
            
            # 精确计算视觉宽度 (中文字符计 2 个单位，英文字符计 1 个单位)
            $visualWidth = 0
            foreach ($char in $name.ToCharArray()) {
                if ([int]$char -gt 255) { $visualWidth += 2 } else { $visualWidth += 1 }
            }
            
            # 设置对齐基准宽度
            $pad = 20 - $visualWidth
            if ($pad -lt 1) { $pad = 1 }
            $spaces = " " * $pad
            
            Write-Host "  $idx. " -NoNewline -ForegroundColor Cyan
            Write-Host "$name" -NoNewline -ForegroundColor Green
            Write-Host "$($spaces)" -NoNewline
            Write-Host "$($i[2])" -ForegroundColor Gray
        }

        Write-Host "===================================================="
        
        $choice = (Read-Host "`n请选择功能序号").Trim()
        switch ($choice) {
            "1" { Generate-UUIDs }
            "2" { Generate-Passwords }
            "3" { Get-Timestamps }
            "4" { Generate-RandomNumbers }
            "5" { Base64-Codec }
            "6" { Text-Hasher }
            "7" { Get-IPAddresses }
            "8" { Test-LocalPort }
            "9" { Explain-CronExpression }
            "10" { Convert-ColorCode }
            "11" { Set-Count }
            "0" { exit }
            default { Write-Host "无效选择 [$choice]，请重新输入..." -ForegroundColor Red; Start-Sleep -Seconds 1 }
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

function Get-IPAddresses {
    Show-Header "本机内外网 IP 获取"
    Write-Host "正在查询，请稍候..." -ForegroundColor Gray
    
    # 内网 IP (显示网卡名称)
    $localIPs = Get-NetIPAddress | 
                Where-Object { $_.InterfaceAlias -notmatch 'Loopback|VirtualBox|VMware' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike 'fe80*' } | 
                Select-Object IPAddress, AddressFamily, InterfaceAlias
    
    Write-Host "`n内网地址:" -ForegroundColor Yellow
    if ($localIPs) {
        foreach ($ip in $localIPs) { 
            $type = if ($ip.AddressFamily -eq 'IPv6') { "[IPv6]" } else { "[IPv4]" }
            $alias = "($($ip.InterfaceAlias))"
            Write-Host "  $($type.PadRight(6)) $($ip.IPAddress.PadRight(40)) $($alias)" -ForegroundColor Green 
        }
    } else {
        Write-Host "  未找到有效的内网地址。" -ForegroundColor Gray
    }

    # 外网 IP (支持 IPv4 和 IPv6)
    $publicIPv4 = $null
    $publicIPv6 = $null
    
    $v4Urls = @("https://api4.ipify.org", "https://ifconfig.me/ip")
    $v6Urls = @("https://api6.ipify.org", "https://v6.ident.me")
    
    # 尝试获取 IPv4
    foreach ($url in $v4Urls) {
        try {
            $publicIPv4 = (Invoke-RestMethod -Uri $url -TimeoutSec 2).Trim()
            if ($publicIPv4 -match '^\d+\.\d+\.\d+\.\d+$') { break }
        } catch { continue }
    }

    # 尝试获取 IPv6
    foreach ($url in $v6Urls) {
        try {
            $publicIPv6 = (Invoke-RestMethod -Uri $url -TimeoutSec 2).Trim()
            if ($publicIPv6 -match ':') { break }
        } catch { continue }
    }

    Write-Host "`n外网地址:" -ForegroundColor Yellow
    if ($publicIPv4) {
        Write-Host "  [IPv4] $publicIPv4" -ForegroundColor Green
        $publicIPv4 | Set-Clipboard
    } else {
        Write-Host "  [IPv4] 获取失败" -ForegroundColor Red
    }

    if ($publicIPv6) {
        Write-Host "  [IPv6] $publicIPv6" -ForegroundColor Green
        if (-not $publicIPv4) { $publicIPv6 | Set-Clipboard }
    } else {
        Write-Host "  [IPv6] 未检测到或获取失败" -ForegroundColor Gray
    }

    if ($publicIPv4 -or $publicIPv6) {
        Write-Host "`n[提示] IPv4 (或 IPv6) 已复制到剪贴板。" -ForegroundColor Gray
    }
    
    Pause-Menu
}

function Test-LocalPort {
    Show-Header "本地端口占用检查"
    $portInput = (Read-Host "请输入要检查的本地端口号").Trim()
    
    if ($portInput -match '^\d+$') {
        $port = [int]$portInput
        Write-Host "`n正在检查本地端口 $port ..." -ForegroundColor Gray
        
        # 获取连接信息
        $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($connection) {
            $pid = $connection.OwningProcess
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "未知进程" }
            
            Write-Host "  [占用] 端口 $port 正在被使用。" -ForegroundColor Yellow
            Write-Host "  进程名称: " -NoNewline; Write-Host $procName -ForegroundColor Green
            Write-Host "  进程 PID: " -NoNewline; Write-Host $pid -ForegroundColor Green
            
            # 提示是否解除占用
            $confirm = Read-Host "`n是否终止该进程以释放端口? (Y/N)"
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                try {
                    Stop-Process -Id $pid -Force -ErrorAction Stop
                    Write-Host "  [成功] 进程已终止，端口 $port 已释放。" -ForegroundColor Green
                } catch {
                    Write-Host "  [失败] 无法终止进程。请尝试以管理员权限运行脚本。" -ForegroundColor Red
                }
            } else {
                $pid.ToString() | Set-Clipboard
                Write-Host "  [提示] 操作已取消。PID 已复制到剪贴板。" -ForegroundColor Gray
            }
        } else {
            Write-Host "  [可用] 端口 $port 目前未被占用。" -ForegroundColor Green
        }
    } else {
        Write-Host "无效的端口号。" -ForegroundColor Red
    }
    Pause-Menu
}

function Explain-CronExpression {
    Show-Header "Cron 表达式解释器 (基础)"
    Write-Host "标准格式: [分] [时] [日] [月] [周]" -ForegroundColor Gray
    $cron = (Read-Host "请输入 Cron 表达式").Trim()
    $parts = $cron -split '\s+'
    
    if ($parts.Length -eq 5) {
        $labels = @("分钟", "小时", "日期", "月份", "周几")
        Write-Host "`n解析结果:" -ForegroundColor Yellow
        for ($i=0; $i -lt 5; $i++) {
            $val = $parts[$i]
            $desc = switch ($val) {
                "*" { "每$($labels[$i])" }
                { $_ -match '^\*/(\d+)$' } { "每隔 $($Matches[1]) $($labels[$i])" }
                { $_ -match '^\d+(,\d+)*$' } { "特定$($labels[$i]): $val" }
                { $_ -match '^(\d+)-(\d+)$' } { "从 $($Matches[1]) 到 $($Matches[2]) $($labels[$i])" }
                default { $val }
            }
            Write-Host "  $($labels[$i].PadRight(4)): $desc" -ForegroundColor Green
        }
    } else {
        Write-Host "错误：无效的 Cron 格式（需 5 位参数）。" -ForegroundColor Red
    }
    Pause-Menu
}

function Convert-ColorCode {
    Show-Header "颜色代码转换 (HEX/RGB)"
    Write-Host "  1. HEX -> RGB (例如 #FFFFFF)"
    Write-Host "  2. RGB -> HEX (例如 255,255,255)"
    $mode = Read-Host "`n请选择模式"
    
    if ($mode -eq "1") {
        $hex = (Read-Host "请输入 HEX 代码").Trim().Replace("#", "")
        if ($hex.Length -eq 6) {
            $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
            $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
            $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
            $res = "rgb($r, $g, $b)"
            Write-Host "`n转换结果: $res" -ForegroundColor Green
            $res | Set-Clipboard
        } else { Write-Host "格式不正确。" -ForegroundColor Red }
    } elseif ($mode -eq "2") {
        $rgb = (Read-Host "请输入 RGB 值 (逗号分隔)").Trim()
        if ($rgb -match '^(\d+)\s*,\s*(\d+)\s*,\s*(\d+)$') {
            $res = "#{0:X2}{1:X2}{2:X2}" -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]
            Write-Host "`n转换结果: $res" -ForegroundColor Green
            $res | Set-Clipboard
        } else { Write-Host "格式不正确。" -ForegroundColor Red }
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