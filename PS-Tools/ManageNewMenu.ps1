# 设置控制台编码，防止中文乱码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 使用底层 .NET API 极速扫描新建菜单项
function Get-NewMenuItems {
    Write-Host "正在扫描当前新建菜单项..." -ForegroundColor Yellow
    
    $items = @()
    # 直接使用 .NET 底层 API，绕过 PowerShell 的 Get-ChildItem，实现毫秒级扫描
    $hkcr = [Microsoft.Win32.Registry]::ClassesRoot
    $extNames = $hkcr.GetSubKeyNames() | Where-Object { $_ -like "*.*" }
    
    foreach ($extName in $extNames) {
        try {
            $extKey = $hkcr.OpenSubKey($extName)
            if ($null -eq $extKey) { continue }
            
            # 检查是否存在 ShellNew 子键
            $shellNewKey = $extKey.OpenSubKey("ShellNew")
            if ($null -ne $shellNewKey) {
                $displayName = "未命名"
                
                # 获取后缀对应的 ClassID，再获取显示名称
                $classId = $extKey.GetValue("")
                if ($classId) {
                    $classKey = $hkcr.OpenSubKey($classId)
                    if ($null -ne $classKey) {
                        $name = $classKey.GetValue("")
                        if (-not [string]::IsNullOrWhiteSpace($name)) { $displayName = $name }
                        $classKey.Close()
                    }
                }
                
                $items += [PSCustomObject]@{
                    Extension = $extName
                    DisplayName = $displayName
                    RegPath = "Registry::HKEY_CLASSES_ROOT\$extName\ShellNew"
                }
                $shellNewKey.Close()
            }
            $extKey.Close()
        } catch {
            # 忽略无权限或已损坏的注册表项，继续扫描
            continue
        }
    }
    return $items
}

# 添加新建菜单项的通用函数
function Add-NewMenuItem {
    Clear-Host
    Write-Host "=== ➕ 添加新建菜单项 ===" -ForegroundColor Cyan
    
    $ext = Read-Host "请输入文件后缀名 (例如: .txt 或 .md)"
    $displayName = Read-Host "请输入右键菜单中显示的名称 (例如: Markdown 文档)"
    $templatePath = Read-Host "请输入模板文件的绝对路径 (直接回车则创建空白文件)"
    
    if (-not $ext.StartsWith(".")) { $ext = ".$ext" }
    
    $regPath = "Registry::HKEY_CLASSES_ROOT\$ext\ShellNew"
    $classId = $ext.TrimStart(".") + "file"
    
    try {
        New-Item -Path $regPath -Force | Out-Null
        
        if ([string]::IsNullOrWhiteSpace($templatePath)) {
            New-ItemProperty -Path $regPath -Name "NullFile" -Value "" -PropertyType String -Force | Out-Null
        } else {
            if (Test-Path $templatePath) {
                New-ItemProperty -Path $regPath -Name "FileName" -Value $templatePath -PropertyType String -Force | Out-Null
            } else {
                Write-Host "⚠️ 警告: 模板文件路径不存在，将改为创建空白文件！" -ForegroundColor Red
                New-ItemProperty -Path $regPath -Name "NullFile" -Value "" -PropertyType String -Force | Out-Null
            }
        }
        
        $classRegPath = "Registry::HKEY_CLASSES_ROOT\$classId"
        New-Item -Path $classRegPath -Force | Out-Null
        Set-ItemProperty -Path $classRegPath -Name "(default)" -Value $displayName -Force
        
        Write-Host "✅ 成功添加 [$displayName] 到新建菜单！" -ForegroundColor Green
    } catch {
        Write-Host "❌ 添加失败: $_" -ForegroundColor Red
    }
    
    Read-Host "按回车键返回主菜单"
}

# 移除新建菜单项的交互函数
function Remove-NewMenuItem {
    Clear-Host
    Write-Host "=== ➖ 移除新建菜单项 ===" -ForegroundColor Yellow
    
    $items = Get-NewMenuItems
    
    if ($items.Count -eq 0) {
        Write-Host "⚠️ 当前系统中没有找到任何自定义的新建菜单项。" -ForegroundColor Gray
        Read-Host "按回车键返回主菜单"
        return
    }
    
    Write-Host "`n当前新建菜单列表：" -ForegroundColor Cyan
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host (" [{0}] {1,-15} ({2})" -f ($i+1), $items[$i].Extension, $items[$i].DisplayName) -ForegroundColor White
    }
    Write-Host ""
    
    $selection = Read-Host "请输入要移除的序号 (输入 0 取消)"
    
    if ($selection -eq "0") {
        Write-Host "已取消操作。" -ForegroundColor Gray
    } elseif ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $items.Count) {
        $target = $items[[int]$selection - 1]
        try {
            Remove-Item -Path $target.RegPath -Force -Recurse
            Write-Host "✅ 成功移除 [$($target.Extension)] 的新建菜单项！" -ForegroundColor Green
        } catch {
            Write-Host "❌ 移除失败: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ 无效的序号输入，请重新选择。" -ForegroundColor Red
    }
    
    Read-Host "按回车键返回主菜单"
}

# 主交互循环
do {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Windows 右键新建菜单 通用管理工具    " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "1. ➕ 添加新建菜单项" -ForegroundColor Green
    Write-Host "2. ➖ 移除新建菜单项" -ForegroundColor Red
    Write-Host "0. 🚪 退出脚本" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan
    
    $choice = Read-Host "请输入你的选择"
    
    switch ($choice) {
        "1" { Add-NewMenuItem }
        "2" { Remove-NewMenuItem }
        "0" { 
            Write-Host "正在退出..." -ForegroundColor Cyan
            exit 
        }
        default { 
            Write-Host "❌ 无效的输入，请重新选择。" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)