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
        if ($LASTEXITCODE -eq 0) { return $version }
    } catch {}
    return $null
}

function Get-UVPath {
    return Get-Command uv -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

function Refresh-Path {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = "$userPath;$machinePath"
}

function Broadcast-EnvChange {
    $signature = '[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);'
    $type = Add-Type -MemberDefinition $signature -Name "Win32" -Namespace "Env" -PassThru
    $result = [IntPtr]::Zero
    $type::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, "Environment", 0x0002, 5000, [out]$result)
}

function Set-PersistentEnvVar {
    param($Name, $Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Content -Path "Env:\$Name" -Value $Value
    Broadcast-EnvChange
    Write-Host "`n$Name = $Value" -ForegroundColor Cyan
    Write-Host "配置完成。当前进程已生效，新开的终端也会自动生效。" -ForegroundColor Green
}

function Remove-PersistentEnvVar {
    param($Name)
    [Environment]::SetEnvironmentVariable($Name, $null, "User")
    if (Test-Path "Env:\$Name") { Remove-Item "Env:\$Name" }
    Broadcast-EnvChange
    Write-Host "`n已从环境变量中移除 $Name" -ForegroundColor Yellow
}

function Display-Header {
    Clear-Host
    Write-Host "================================================================"
    Write-Host "             UV 环境管理工具 v2.1.0 (PS)"
    Write-Host "================================================================"
    Write-Host "操作系统: Windows $([Environment]::OSVersion.VersionString)"
    
    $uvVersion = Get-UVVersion
    Write-Host "UV 版本: $($uvVersion -replace 'uv ', '' -or '未安装')"
    Write-Host "UV 路径: $(Get-UVPath -or '未找到')"
    Write-Host "镜像源: $($env:UV_DEFAULT_INDEX -or '未设置')"
    Write-Host "缓存路径: $($env:UV_CACHE_DIR -or '未设置')"
    Write-Host "================================================================"
}

function Display-Menu {
    Write-Host "`n请选择要执行的操作："
    Write-Host "1. 安装 UV"
    Write-Host "2. 更新 UV"
    Write-Host "3. 卸载 UV"
    Write-Host "4. 配置镜像源"
    Write-Host "5. 配置缓存路径"
    Write-Host "0. 退出"
    Write-Host "----------------------------------------------------------------"
}

function Install-UV {
    Write-Host "`n选择安装方法："
    Write-Host "1. 官方安装脚本（推荐）"
    Write-Host "2. pip 安装"
    Write-Host "3. winget 安装"
    
    $choice = Read-Host "请选择 (1-3, 默认1)"
    if ($null -eq $choice -or $choice -eq "") { $choice = "1" }

    switch ($choice) {
        "1" {
            Write-Host "`n正在使用官方安装脚本安装 UV..."
            powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
            Refresh-Path
        }
        "2" {
            Write-Host "`n正在使用 pip 安装 UV..."
            $pipIndex = if ($env:UV_DEFAULT_INDEX) { $env:UV_DEFAULT_INDEX } else { $DEFAULT_PIP_INDEX_URL }
            python -m pip install --upgrade uv -i $pipIndex
        }
        "3" {
            Write-Host "`n正在使用 winget 安装 UV..."
            winget install -e --id astral-sh.uv --accept-package-agreements --accept-source-agreements
        }
        Default { Write-Host "无效选择" -ForegroundColor Red; return }
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nUV 安装成功" -ForegroundColor Green
    } else {
        Write-Host "`n安装过程中可能出现错误" -ForegroundColor Yellow
    }
}

function Update-UV {
    if (-not (Get-UVVersion)) {
        Write-Host "UV 未安装，请先安装" -ForegroundColor Yellow
        return
    }

    Write-Host "`n选择更新方法："
    Write-Host "1. uv self update (推荐)"
    Write-Host "2. 重新运行官方安装脚本"
    Write-Host "3. pip 升级"
    Write-Host "4. winget 升级"

    $choice = Read-Host "请选择 (1-4, 默认1)"
    if ($null -eq $choice -or $choice -eq "") { $choice = "1" }

    switch ($choice) {
        "1" { uv self update }
        "2" { powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex" }
        "3" { 
            $pipIndex = if ($env:UV_DEFAULT_INDEX) { $env:UV_DEFAULT_INDEX } else { $DEFAULT_PIP_INDEX_URL }
            python -m pip install --upgrade uv -i $pipIndex 
        }
        "4" { winget upgrade -e --id astral-sh.uv --accept-package-agreements --accept-source-agreements }
        Default { Write-Host "无效选择" -ForegroundColor Red; return }
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nUV 更新完成" -ForegroundColor Green
    }
}

function Uninstall-UV {
    if (-not (Get-UVVersion)) {
        Write-Host "UV 未安装" -ForegroundColor Yellow
        return
    }

    Write-Host "`n选择卸载方法："
    Write-Host "1. 删除官方安装器二进制文件"
    Write-Host "2. pip 卸载"
    Write-Host "3. winget 卸载"

    $choice = Read-Host "请选择 (1-3, 默认1)"
    if ($null -eq $choice -or $choice -eq "") { $choice = "1" }

    $success = $false
    switch ($choice) {
        "1" {
            $binDirs = @(
                Join-Path $HOME ".local\bin",
                Join-Path $HOME ".cargo\bin"
            )
            $found = @()
            foreach ($dir in $binDirs) {
                foreach ($name in @("uv.exe", "uvx.exe", "uvw.exe")) {
                    $p = Join-Path $dir $name
                    if (Test-Path $p) { $found += $p }
                }
            }

            if ($found.Count -eq 0) {
                Write-Host "未找到官方安装器位置的 UV 二进制文件。" -ForegroundColor Yellow
                return
            }

            Write-Host "`n将删除以下文件："
            $found | ForEach-Object { Write-Host "  $_" }
            $confirm = Read-Host "确认删除？(y/N)"
            if ($confirm -eq "y" -or $confirm -eq "yes") {
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
        Default { Write-Host "无效选择" -ForegroundColor Red; return }
    }

    if ($success) {
        Write-Host "`n卸载成功" -ForegroundColor Green
        $confirm = Read-Host "是否同时删除 UV 镜像源和缓存路径环境变量？(y/N)"
        if ($confirm -eq "y" -or $confirm -eq "yes") {
            Remove-PersistentEnvVar $ENV_INDEX_KEY
            Remove-PersistentEnvVar $ENV_CACHE_KEY
        }
    }
}

function Configure-Index {
    Write-Host "`n可选镜像源："
    $MIRROR_PRESETS.Keys | Sort-Object | ForEach-Object {
        Write-Host "$_. $($MIRROR_PRESETS[$_][0]): $($MIRROR_PRESETS[$_][1])"
    }
    Write-Host "0. 自定义"

    $choice = Read-Host "请选择镜像源 (默认1)"
    if ($null -eq $choice -or $choice -eq "") { $choice = "1" }

    $value = ""
    if ($choice -eq "0") {
        $value = Read-Host "请输入镜像源 URL"
        if (-not $value) { return }
    } elseif ($MIRROR_PRESETS.ContainsKey($choice)) {
        $value = $MIRROR_PRESETS[$choice][1]
    } else {
        Write-Host "无效选择" -ForegroundColor Red; return
    }

    Set-PersistentEnvVar $ENV_INDEX_KEY $value
}

function Configure-Cache {
    $current = if ($env:UV_CACHE_DIR) { $env:UV_CACHE_DIR } else { $DEFAULT_CACHE_DIR }
    $value = Read-Host "请输入 UV 缓存路径 (默认 $current)"
    if ($null -eq $value -or $value -eq "") { $value = $current }

    if (-not (Test-Path $value)) {
        New-Item -ItemType Directory -Path $value -Force | Out-Null
    }

    Set-PersistentEnvVar $ENV_CACHE_KEY $value
}

# Main Loop
while ($true) {
    Display-Header
    Display-Menu
    $choice = Read-Host "请输入选项 (0-5)"

    switch ($choice) {
        "1" { Install-UV }
        "2" { Update-UV }
        "3" { Uninstall-UV }
        "4" { Configure-Index }
        "5" { Configure-Cache }
        "0" { Write-Host "`n感谢使用 UV 环境管理工具"; break }
    }
    
    if ($choice -ne "0") {
        Write-Host "`n按回车键返回主菜单..."
        [void][System.Console]::ReadLine()
    }
}
