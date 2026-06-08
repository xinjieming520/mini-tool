# UV 环境管理工具 v2.1.0 (PowerShell Version)
# 功能：安装、更新、卸载 UV，配置镜像源和缓存路径。
# 仅支持 Windows 系统。

$DEFAULT_INDEX_URL = "https://pypi.tuna.tsinghua.edu.cn/simple"
$DEFAULT_PIP_INDEX_URL = "https://mirrors.aliyun.com/pypi/simple/"
$ENV_INDEX_KEY = "UV_DEFAULT_INDEX"
$ENV_CACHE_KEY = "UV_CACHE_DIR"
$DEFAULT_CACHE_DIR = "D:\AI\uv"

$MIRROR_PRESETS = @{
    "1" = @("清华大学", "https://pypi.tuna.tsinghua.edu.cn/simple")
    "2" = @("阿里云", "https://mirrors.aliyun.com/pypi/simple/")
    "3" = @("中国科学技术大学", "https://pypi.mirrors.ustc.edu.cn/simple/")
    "4" = @("腾讯云", "https://mirrors.cloud.tencent.com/pypi/simple")
    "5" = @("官方 PyPI", "https://pypi.org/simple")
}

function Get-UVVersion {
    try {
        $version = uv --version 2>$null
        if ($LASTEXITCODE -eq 0) { return ($version -replace 'uv ', '').Trim() }
    } catch {}
    return "未安装"
}

function Get-UVPath {
    $path = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($path) { return $path } else { return "未找到" }
}

function Refresh-Path {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = "$userPath;$machinePath"
}

function Broadcast-EnvChange {
    $signature = '[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);'
    $type = Add-Type -MemberDefinition $signature -Name "Win32" -Namespace "Env" -PassThru -ErrorAction SilentlyContinue
    if ($null -eq $type) { $type = [Env.Win32] }
    $result = [IntPtr]::Zero
    $type::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, "Environment", 0x0002, 5000, [out]$result) | Out-Null
}

function Set-PersistentEnvVar {
    param($Name, $Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Content -Path "Env:\$Name" -Value $Value
    Broadcast-EnvChange
    Write-Host "`n >> $Name = $Value" -ForegroundColor Cyan
    Write-Host " >> 配置完成。当前进程已生效，新开的终端也会自动生效。" -ForegroundColor Green
}

function Remove-PersistentEnvVar {
    param($Name)
    [Environment]::SetEnvironmentVariable($Name, $null, "User")
    if (Test-Path "Env:\$Name") { Remove-Item "Env:\$Name" }
    Broadcast-EnvChange
    Write-Host "`n >> 已从环境变量中移除 $Name" -ForegroundColor Yellow
}

function Display-Header {
    Clear-Host
    $uvVer = Get-UVVersion
    $uvPath = Get-UVPath
    $mirror = if ($env:UV_DEFAULT_INDEX) { $env:UV_DEFAULT_INDEX } else { "未设置 (使用默认)" }
    $cache = if ($env:UV_CACHE_DIR) { $env:UV_CACHE_DIR } else { "未设置 (使用默认)" }

    Write-Host @"

    ┌──────────────────────────────────────────────────────────────┐
    │                🚀 UV 环境管理工具 v2.2.0 (PS)                │
    └──────────────────────────────────────────────────────────────┘
"@ -ForegroundColor Cyan

    Write-Host "  [ 系统信息 ]" -ForegroundColor DarkGray
    Write-Host "  💻 操作系统: " -NoNewline; Write-Host "Windows $([Environment]::OSVersion.VersionString)" -ForegroundColor White
    $color = if ($uvVer -eq "未安装") { "Red" } else { "Green" }
    Write-Host "  🛠️  UV 版本:  " -NoNewline; Write-Host $uvVer -ForegroundColor $color
    Write-Host "  📂 UV 路径:  " -NoNewline; Write-Host $uvPath -ForegroundColor Gray
    Write-Host "  🌐 镜像源:   " -NoNewline; Write-Host $mirror -ForegroundColor Yellow
    Write-Host "  📦 缓存路径: " -NoNewline; Write-Host $cache -ForegroundColor Yellow
    Write-Host "  " + ("─" * 60) -ForegroundColor DarkGray
}

function Display-Menu {
    Write-Host "  [ 操作菜单 ]" -ForegroundColor DarkGray
    Write-Host "  1. 📥 安装 uv" -ForegroundColor White
    Write-Host "  2. 🔄 更新 uv" -ForegroundColor White
    Write-Host "  3. 🗑️ 卸载 uv" -ForegroundColor White
    Write-Host "  4. 🚀 配置镜像源" -ForegroundColor White
    Write-Host "  5. 💾 配置缓存路径" -ForegroundColor White
    Write-Host "  0. ❌ 退出程序" -ForegroundColor Red
    Write-Host "  " + ("─" * 60) -ForegroundColor DarkGray
}

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "`n >> $Message" -ForegroundColor $Color
}

function Install-UV {
    Display-Header
    Write-Host "  [ 安装 UV ]" -ForegroundColor Cyan
    Write-Host "  1. 官方脚本 (推荐)"
    Write-Host "  2. 使用 Pip"
    Write-Host "  3. 使用 Winget"
    Write-Host "  b. 返回主菜单"
    
    $choice = Read-Host "`n  请选择安装方式"
    if ($choice -eq "b") { return }

    Write-Status "正在准备安装..."
    switch ($choice) {
        "1" {
            powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
            Refresh-Path
        }
        "2" {
            $pipIndex = if ($env:UV_DEFAULT_INDEX) { $env:UV_DEFAULT_INDEX } else { $DEFAULT_PIP_INDEX_URL }
            python -m pip install --upgrade uv -i $pipIndex
        }
        "3" {
            winget install -e --id astral-sh.uv --accept-package-agreements --accept-source-agreements
        }
        Default { Write-Status "无效选择" "Red"; return }
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Status "UV 安装成功！" "Green"
    } else {
        Write-Status "安装过程可能未完全成功，请检查上方输出。" "Yellow"
    }
}

function Update-UV {
    if ((Get-UVVersion) -eq "未安装") {
        Write-Status "错误: UV 未安装，无法更新。" "Red"
        return
    }

    Display-Header
    Write-Host "  [ 更新 UV ]" -ForegroundColor Cyan
    Write-Host "  1. uv self update (内置)"
    Write-Host "  2. 重新运行官方脚本"
    Write-Host "  3. 使用 Pip 升级"
    Write-Host "  4. 使用 Winget 升级"
    Write-Host "  b. 返回主菜单"

    $choice = Read-Host "`n  请选择更新方式"
    if ($choice -eq "b") { return }

    Write-Status "正在检查更新..."
    switch ($choice) {
        "1" { uv self update }
        "2" { powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex" }
        "3" { 
            $pipIndex = if ($env:UV_DEFAULT_INDEX) { $env:UV_DEFAULT_INDEX } else { $DEFAULT_PIP_INDEX_URL }
            python -m pip install --upgrade uv -i $pipIndex 
        }
        "4" { winget upgrade -e --id astral-sh.uv --accept-package-agreements --accept-source-agreements }
        Default { Write-Status "无效选择" "Red"; return }
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Status "UV 更新流程执行完毕。" "Green"
    }
}

function Uninstall-UV {
    if ((Get-UVVersion) -eq "未安装") {
        Write-Status "UV 未安装，无需卸载。" "Yellow"
        return
    }

    Display-Header
    Write-Host "  [ 卸载 UV ]" -ForegroundColor Red
    Write-Host "  1. 清理官方二进制文件"
    Write-Host "  2. 使用 Pip 卸载"
    Write-Host "  3. 使用 Winget 卸载"
    Write-Host "  b. 返回主菜单"

    $choice = Read-Host "`n  请选择卸载方式"
    if ($choice -eq "b") { return }

    $success = $false
    switch ($choice) {
        "1" {
            $binDirs = @(Join-Path $HOME ".local\bin", Join-Path $HOME ".cargo\bin")
            $found = @()
            foreach ($dir in $binDirs) {
                foreach ($name in @("uv.exe", "uvx.exe", "uvw.exe")) {
                    $p = Join-Path $dir $name
                    if (Test-Path $p) { $found += $p }
                }
            }

            if ($found.Count -eq 0) {
                Write-Status "未找到官方路径下的二进制文件。" "Yellow"
                return
            }

            Write-Host "`n  以下文件将被永久删除：" -ForegroundColor Red
            $found | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
            $confirm = Read-Host "`n  确认删除吗？(y/N)"
            if ($confirm -eq "y") {
                foreach ($f in $found) { Remove-Item $f -Force }
                $success = $true
            }
        }
        "2" {
            python -m pip uninstall -y uv
            $success = ($LASTEXITCODE -eq 0)
        }
        "3" {
            winget uninstall -e --id astral-sh.uv
            $success = ($LASTEXITCODE -eq 0)
        }
        Default { Write-Status "无效选择" "Red"; return }
    }

    if ($success) {
        Write-Status "UV 已成功卸载。" "Green"
        $confirm = Read-Host "`n  是否同时清理环境变量 (镜像源与缓存路径)？(y/N)"
        if ($confirm -eq "y") {
            Remove-PersistentEnvVar $ENV_INDEX_KEY
            Remove-PersistentEnvVar $ENV_CACHE_KEY
        }
    }
}

function Configure-Index {
    Display-Header
    Write-Host "  [ 配置镜像源 ]" -ForegroundColor Cyan
    $MIRROR_PRESETS.Keys | Sort-Object | ForEach-Object {
        Write-Host "  $_. $($MIRROR_PRESETS[$_][0])" -ForegroundColor Gray
        Write-Host "     $($MIRROR_PRESETS[$_][1])" -ForegroundColor DarkGray
    }
    Write-Host "  0. 自定义 URL"
    Write-Host "  b. 返回主菜单"

    $choice = Read-Host "`n  请选择镜像源"
    if ($choice -eq "b") { return }

    $value = ""
    if ($choice -eq "0") {
        $value = Read-Host "  请输入镜像源 URL"
        if (-not $value) { return }
    } elseif ($MIRROR_PRESETS.ContainsKey($choice)) {
        $value = $MIRROR_PRESETS[$choice][1]
    } else {
        Write-Status "无效选择" "Red"; return
    }

    Set-PersistentEnvVar $ENV_INDEX_KEY $value
}

function Configure-Cache {
    Display-Header
    Write-Host "  [ 配置缓存路径 ]" -ForegroundColor Cyan
    $current = if ($env:UV_CACHE_DIR) { $env:UV_CACHE_DIR } else { $DEFAULT_CACHE_DIR }
    Write-Host "  当前路径: $current" -ForegroundColor Gray
    
    $value = Read-Host "`n  请输入新的缓存路径 (直接回车保持默认)"
    if ($null -eq $value -or $value -eq "") { $value = $current }

    if (-not (Test-Path $value)) {
        Write-Status "目录不存在，正在创建..."
        New-Item -ItemType Directory -Path $value -Force | Out-Null
    }

    Set-PersistentEnvVar $ENV_CACHE_KEY $value
}

# Main Loop
while ($true) {
    Display-Header
    Display-Menu
    $choice = Read-Host "  请键入选项 [0-5]"

    switch ($choice) {
        "1" { Install-UV }
        "2" { Update-UV }
        "3" { Uninstall-UV }
        "4" { Configure-Index }
        "5" { Configure-Cache }
        "0" { Write-Host "`n  🚀 感谢使用，再见！`n" -ForegroundColor Cyan; break }
        Default { Write-Status "无效选择，请重新输入" "Red" }
    }
    
    if ($choice -ne "0") {
        Write-Host "`n  按回车键返回主菜单..." -ForegroundColor DarkGray
        [void][System.Console]::ReadLine()
    }
}
