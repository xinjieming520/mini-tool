# ================================================
#          公网 IP 查询工具
# ================================================

Clear-Host

Write-Host "正在查询公网 IP 信息..." -ForegroundColor Cyan
Write-Host ("═" * 60) -ForegroundColor DarkGray

Write-Host ""

# IPv4
Write-Host "IPv4 地址  " -NoNewline -ForegroundColor White
try {
    $ipv4 = curl.exe -s --connect-timeout 6 --max-time 8 v4.api.ipinfo.io/ip
    if ($ipv4) {
        Write-Host $ipv4 -ForegroundColor Green
    } else {
        Write-Host "获取失败" -ForegroundColor Yellow
    }
} catch {
    Write-Host "获取失败" -ForegroundColor Red
}

# IPv6
Write-Host "IPv6 地址  " -NoNewline -ForegroundColor White
try {
    $ipv6 = curl.exe -s --connect-timeout 6 --max-time 8 v6.api.ipinfo.io/ip
    if ($ipv6) {
        Write-Host $ipv6 -ForegroundColor Green
    } else {
        Write-Host "未检测到 IPv6" -ForegroundColor Yellow
    }
} catch {
    Write-Host "未检测到 IPv6" -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("═" * 60) -ForegroundColor DarkGray
Write-Host ""

Write-Host "查询时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

Write-Host "按任意键退出..." -ForegroundColor Cyan -NoNewline
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")