# ============================================================================
#  Windows 右键「新建」菜单 管理工具
#
#  设计要点：
#   - 全程使用 .NET RegistryKey API（异常可被 try/catch 捕获，且支持 Registry64 视图）
#   - 默认写入 HKCU\Software\Classes（仅当前用户，免管理员）；管理员可写入 HKLM
#   - 显示名称：写入 ShellNew\MenuText，并在扩展名无关联时新建独立命名空间的 ProgID
#     （实测仅写 MenuText 不生效——新建菜单要求条目具备文件类型关联）
#   - 绝不覆盖已有关联：扩展名已有 ProgID 时原样保留，避免破坏系统类型描述
# ============================================================================

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = "NewMenu Manager - 右键新建菜单管理工具" } catch {}

$script:ClassesPath   = 'Software\Classes'
$script:RegistryView  = [Microsoft.Win32.RegistryView]::Registry64
$script:ShellApiType  = $null
$script:ShellApiTried = $false

# 自建 ProgID 的命名空间前缀。不能用 "<扩展名>file"（实测 .png/.bat/.html/.js/.xml
# 等 9 个常见扩展名会与系统已有 ProgID 撞名并被覆盖），改用独立前缀避免冲突。
$script:ProgIdPrefix  = 'NewMenuMgr.'

# ShellNew 中表示"建文件方式"的值，互斥。写入新策略前必须先清空，
# 否则旧的 NullFile 会让新设的 FileName/Data 被系统忽略。
$script:StrategyValues = @('NullFile', 'FileName', 'Data', 'Command', 'Handler', 'Directory')

# ----------------------------------------------------------------------------
# 基础工具
# ----------------------------------------------------------------------------

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 用 Registry64 打开根键，避免 32 位 PowerShell 被重定向到 Wow6432Node
# （Explorer 是 64 位进程，写进 Wow6432Node 的项它看不到）
function Get-BaseKey {
    param([ValidateSet('HKCU', 'HKLM', 'HKCR')][string]$Scope)

    switch ($Scope) {
        'HKLM' { $hive = [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKCR' { $hive = [Microsoft.Win32.RegistryHive]::ClassesRoot  }
        default { $hive = [Microsoft.Win32.RegistryHive]::CurrentUser }
    }
    return [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $script:RegistryView)
}

# 惰性编译 P/Invoke 辅助（失败则静默降级，不阻断脚本）
function Get-ShellApi {
    if (-not $script:ShellApiTried) {
        $script:ShellApiTried = $true
        try {
            $script:ShellApiType = Add-Type -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
public static extern int SHLoadIndirectString(string pszSource, System.Text.StringBuilder pszOutBuf, uint cchOutBuf, IntPtr pvReserved);
'@ -Name 'ShellApi' -Namespace 'NewMenuMgr' -PassThru -ErrorAction Stop
        } catch {
            $script:ShellApiType = $null
        }
    }
    return $script:ShellApiType
}

# 解析 "@shell32.dll,-30318" 这类间接字符串为实际文本
function Resolve-IndirectString {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if (-not $Text.StartsWith('@')) { return $Text }

    $api = Get-ShellApi
    if ($null -eq $api) { return $Text }

    try {
        $sb = New-Object System.Text.StringBuilder 1024
        $hr = $api::SHLoadIndirectString($Text, $sb, [uint32]$sb.Capacity, [IntPtr]::Zero)
        if ($hr -eq 0) {
            $resolved = $sb.ToString()
            if (-not [string]::IsNullOrWhiteSpace($resolved)) { return $resolved }
        }
    } catch {}
    return $Text
}

function Update-Explorer {
    $api = Get-ShellApi
    if ($null -eq $api) { return }
    try {
        # SHCNE_ASSOCCHANGED | SHCNF_FLUSH
        $api::SHChangeNotify([uint32]0x08000000, [uint32]0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
    } catch {}
}

function Show-Header {
    param([string]$Title)
    Clear-Host
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host "  $Title"                                 -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
}

function Wait-Return {
    Read-Host "`n按回车键返回主菜单" | Out-Null
}

# ----------------------------------------------------------------------------
# 扫描
# ----------------------------------------------------------------------------

function Get-ShellNewStrategy {
    param($ShellNewKey)

    $fileName = $ShellNewKey.GetValue('FileName')
    if ($null -ne $ShellNewKey.GetValue('NullFile')) { return 'NullFile（空白文件）' }
    if ($null -ne $fileName)                         { return "FileName（模板: $fileName）" }
    if ($null -ne $ShellNewKey.GetValue('Data'))     { return 'Data（二进制内容）' }
    if ($null -ne $ShellNewKey.GetValue('Command'))  { return 'Command（执行命令）' }
    if ($null -ne $ShellNewKey.GetValue('Handler'))  { return 'Handler（COM 处理器）' }
    return '(未识别)'
}

# 新建菜单显示名的解析顺序：
#   1) ShellNew\MenuText  —— Windows 自身用于指定新建菜单文案
#   2) ProgID 的 FriendlyTypeName
#   3) ProgID 的默认值（文件类型描述）
#   4) 兜底：扩展名本身
function Get-MenuDisplayName {
    param($ExtKey, $ShellNewKey, $ClassesKey, $HkcrKey, [string]$Extension)

    $mt = Resolve-IndirectString ($ShellNewKey.GetValue('MenuText'))
    if (-not [string]::IsNullOrWhiteSpace($mt)) { return $mt }

    # 扩展名关联（ProgID）优先从 HKCR 合并视图读取：
    # 实测 .md 的关联在 HKCU、而 ShellNew 在 HKLM，此时只读当前 hive 的
    # 扩展名键会拿到空 ProgID，导致显示名退化成扩展名本身。
    $progId = $null
    if ($null -ne $HkcrKey) {
        $mergedExt = $null
        try {
            $mergedExt = $HkcrKey.OpenSubKey($Extension)
            if ($null -ne $mergedExt) { $progId = $mergedExt.GetValue('') }
        } catch {
            $progId = $null
        } finally {
            if ($null -ne $mergedExt) { $mergedExt.Close() }
        }
    }
    if (-not $progId) { $progId = $ExtKey.GetValue('') }

    if ($progId) {
        foreach ($source in @($HkcrKey, $ClassesKey)) {
            if ($null -eq $source) { continue }
            $progKey = $null
            try {
                $progKey = $source.OpenSubKey($progId)
                if ($null -eq $progKey) { continue }

                $ft = Resolve-IndirectString ($progKey.GetValue('FriendlyTypeName'))
                if (-not [string]::IsNullOrWhiteSpace($ft)) { return $ft }

                $dn = Resolve-IndirectString ($progKey.GetValue(''))
                if (-not [string]::IsNullOrWhiteSpace($dn)) { return $dn }
            } catch {
                continue
            } finally {
                if ($null -ne $progKey) { $progKey.Close() }
            }
        }
    }
    return $Extension
}

function Get-NewMenuItems {
    Write-Host '正在扫描新建菜单项...' -ForegroundColor Yellow

    # 扩展名过滤：必须以点开头，且不含路径/通配符/空白字符。
    # 不能再用 -like "*.*"，否则会把 7-Zip.7z、3DVIAPlayer.Document 这类
    # ProgID 误当成扩展名（实测本机 7600 个"带点"键里只有 1383 个是真扩展名）。
    $extPattern = '^\.[^\\/:*?"<>|\s]+$'

    $list = New-Object 'System.Collections.Generic.List[object]'
    $hkcr = $null
    try {
        $hkcr = Get-BaseKey -Scope 'HKCR'

        foreach ($scope in @('HKCU', 'HKLM')) {
            $base    = $null
            $classes = $null
            try {
                $base    = Get-BaseKey -Scope $scope
                $classes = $base.OpenSubKey($script:ClassesPath)
                if ($null -eq $classes) { continue }

                foreach ($extName in $classes.GetSubKeyNames()) {
                    if ($extName -notmatch $extPattern) { continue }

                    $extKey = $null
                    $snKey  = $null
                    try {
                        $extKey = $classes.OpenSubKey($extName)
                        if ($null -eq $extKey) { continue }
                        $snKey = $extKey.OpenSubKey('ShellNew')
                        if ($null -eq $snKey) { continue }

                        $list.Add([PSCustomObject]@{
                            Extension   = $extName
                            DisplayName = Get-MenuDisplayName -ExtKey $extKey -ShellNewKey $snKey -ClassesKey $classes -HkcrKey $hkcr -Extension $extName
                            Strategy    = Get-ShellNewStrategy -ShellNewKey $snKey
                            Scope       = $scope
                        })
                    } catch {
                        continue
                    } finally {
                        if ($null -ne $snKey)  { $snKey.Close()  }
                        if ($null -ne $extKey) { $extKey.Close() }
                    }
                }
            } catch {
                continue
            } finally {
                if ($null -ne $classes) { $classes.Close() }
                if ($null -ne $base)    { $base.Close()    }
            }
        }
    } finally {
        if ($null -ne $hkcr) { $hkcr.Close() }
    }

    return ,$list.ToArray()
}

# ----------------------------------------------------------------------------
# 添加
# ----------------------------------------------------------------------------

function Add-NewMenuItem {
    Show-Header '添加新建菜单项'

    $ext = (Read-Host '请输入文件后缀名 (例如 .txt / .md)').Trim()
    if ([string]::IsNullOrWhiteSpace($ext)) {
        Write-Host '❌ 后缀名不能为空。' -ForegroundColor Red
        Wait-Return
        return
    }
    if (-not $ext.StartsWith('.')) { $ext = '.' + $ext }
    if ($ext -notmatch '^\.[^\\/:*?"<>|\s]+$') {
        Write-Host "❌ 后缀名不合法: $ext（不能包含空白或 \ / : * ? `" < > |）" -ForegroundColor Red
        Wait-Return
        return
    }

    $displayName = (Read-Host '请输入菜单中显示的名称 (例如 Markdown 文档)').Trim()
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        Write-Host '❌ 显示名称不能为空。' -ForegroundColor Red
        Wait-Return
        return
    }

    $templatePath = (Read-Host '模板文件绝对路径 (直接回车则创建空白文件)').Trim()

    # ---- 选择写入位置 ----
    $scope = 'HKCU'
    Write-Host ''
    if (Test-IsAdmin) {
        Write-Host '写入位置：' -ForegroundColor Cyan
        Write-Host '  [1] 仅当前用户  HKCU\Software\Classes  (推荐，不影响其他用户)' -ForegroundColor Green
        Write-Host '  [2] 所有用户    HKLM\Software\Classes  (需管理员，已具备)'       -ForegroundColor Yellow
        $pick = (Read-Host '请选择 (默认 1)').Trim()
        if ($pick -eq '2') { $scope = 'HKLM' }
    } else {
        Write-Host 'ℹ️  当前非管理员，将写入 HKCU（仅当前用户生效，无需管理员）。' -ForegroundColor Yellow
        Write-Host '    若需对所有用户生效，请以管理员身份重新运行本脚本。' -ForegroundColor DarkGray
    }
    Write-Host ''

    # ---- 校验模板 ----
    $useTemplate = $false
    if (-not [string]::IsNullOrWhiteSpace($templatePath)) {
        if (Test-Path -LiteralPath $templatePath -PathType Leaf) {
            $useTemplate = $true
        } else {
            Write-Host "⚠️  模板文件不存在，将改为创建空白文件。" -ForegroundColor Red
        }
    }

    # ---- 写入 ----
    $base        = $null
    $classes     = $null
    $snKey       = $null
    $hkcr        = $null
    $ok          = $false
    $assocStatus = 'unknown'   # created / existing
    $createdId   = $null
    try {
        $base    = Get-BaseKey -Scope $scope
        $classes = $base.CreateSubKey($script:ClassesPath)   # 无权限时抛 UnauthorizedAccessException
        if ($null -eq $classes) { throw "无法打开 $scope\$script:ClassesPath" }

        $snKey = $classes.CreateSubKey("$ext\ShellNew")
        if ($null -eq $snKey) { throw "无法创建 $ext\ShellNew" }

        # 清空旧的建文件方式，避免残留的 NullFile 让新策略失效
        foreach ($v in $script:StrategyValues) { $snKey.DeleteValue($v, $false) }

        if ($useTemplate) {
            $snKey.SetValue('FileName', $templatePath, [Microsoft.Win32.RegistryValueKind]::String)
        } else {
            $snKey.SetValue('NullFile', '', [Microsoft.Win32.RegistryValueKind]::String)
        }
        # MenuText 是 Windows 自身用于新建菜单文案的值（.lnk/.contact 在用）。
        # 实测仅靠它不足以让条目出现，但作为显示名的补充手段一并写入。
        $snKey.SetValue('MenuText', $displayName, [Microsoft.Win32.RegistryValueKind]::String)

        # ---- 关键：建立文件类型关联 ----
        # MS 文档（Extending the New Submenu）明确要求条目必须具备文件类型关联；
        # 实测本机所有生效的 NullFile 条目都有 ProgID，唯一无关联的条目不在菜单中显示。
        # 因此：扩展名当前无关联时，新建一个独立命名空间的 ProgID 并指向它。
        # 已有关联则原样保留，绝不覆盖（否则会破坏系统类型描述与打开方式）。
        $existingAssoc = $null
        $mergedExt     = $null
        $hkcr          = Get-BaseKey -Scope 'HKCR'
        try {
            $mergedExt = $hkcr.OpenSubKey($ext)
            if ($null -ne $mergedExt) { $existingAssoc = $mergedExt.GetValue('') }
        } catch {
            $existingAssoc = $null
        } finally {
            if ($null -ne $mergedExt) { $mergedExt.Close() }
        }

        if ([string]::IsNullOrWhiteSpace($existingAssoc)) {
            $progId  = $script:ProgIdPrefix + $ext.TrimStart('.')
            $progKey = $null
            $extKey  = $null
            try {
                $progKey = $classes.CreateSubKey($progId)
                if ($null -eq $progKey) { throw "无法创建 ProgID $progId" }
                $progKey.SetValue('', $displayName, [Microsoft.Win32.RegistryValueKind]::String)

                $extKey = $classes.CreateSubKey($ext)
                if ($null -eq $extKey) { throw "无法打开 $ext" }
                $extKey.SetValue('', $progId, [Microsoft.Win32.RegistryValueKind]::String)

                $assocStatus = 'created'
                $createdId   = $progId
            } finally {
                if ($null -ne $progKey) { $progKey.Close() }
                if ($null -ne $extKey)  { $extKey.Close()  }
            }
        } else {
            $assocStatus = 'existing'
        }
        $ok = $true
    } catch {
        Write-Host "❌ 添加失败: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception -is [System.UnauthorizedAccessException]) {
            Write-Host '   提示：写入 HKLM 需要管理员权限，请以管理员身份运行。' -ForegroundColor Yellow
        }
    } finally {
        if ($null -ne $snKey)   { $snKey.Close()   }
        if ($null -ne $classes) { $classes.Close() }
        if ($null -ne $base)    { $base.Close()    }
        if ($null -ne $hkcr)    { $hkcr.Close()    }
    }

    if ($ok) {
        Update-Explorer
        Write-Host "✅ 已添加 [$displayName] ($ext) 到新建菜单。" -ForegroundColor Green
        Write-Host "   位置: $scope\$script:ClassesPath\$ext\ShellNew" -ForegroundColor Gray
        if ($assocStatus -eq 'created') {
            Write-Host "   已新建文件类型关联: $ext -> $createdId（该扩展名原本无关联）" -ForegroundColor Gray
        } elseif ($assocStatus -eq 'existing') {
            Write-Host '   ⚠️  该扩展名已有关联类型，为免破坏打开方式未做改动。' -ForegroundColor Yellow
            Write-Host '      菜单显示名可能沿用现有类型名。' -ForegroundColor Yellow
        }
        Write-Host '   若菜单未立即刷新，请重启资源管理器或注销重登录。' -ForegroundColor DarkGray
    }

    Wait-Return
}

# ----------------------------------------------------------------------------
# 移除
# ----------------------------------------------------------------------------

function Remove-NewMenuItem {
    Show-Header '移除新建菜单项'

    $items = Get-NewMenuItems

    if ($null -eq $items -or $items.Count -eq 0) {
        Write-Host '⚠️  没有找到任何新建菜单项。' -ForegroundColor Gray
        Wait-Return
        return
    }

    Write-Host "`n当前新建菜单列表：" -ForegroundColor Cyan
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $scopeLabel = if ($it.Scope -eq 'HKLM') { '所有用户' } else { '当前用户' }
        Write-Host (" [{0,2}] {1,-14} {2,-28} [{3}] {4}" -f `
            ($i + 1), $it.Extension, $it.DisplayName, $scopeLabel, $it.Strategy) -ForegroundColor White
    }
    Write-Host ''

    $selection = (Read-Host '请输入要移除的序号 (输入 0 取消)').Trim()

    if ($selection -eq '0') {
        Write-Host '已取消操作。' -ForegroundColor Gray
        Wait-Return
        return
    }
    if ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $items.Count) {
        Write-Host '❌ 无效的序号输入。' -ForegroundColor Red
        Wait-Return
        return
    }

    $target = $items[[int]$selection - 1]
    $scopeLabel = if ($target.Scope -eq 'HKLM') { '所有用户' } else { '当前用户' }

    Write-Host ''
    Write-Host "即将移除: $($target.Extension)  [$($target.DisplayName)]  作用域: $scopeLabel" -ForegroundColor Yellow
    $confirm = (Read-Host '确认删除？输入 y 确认，其它任意键取消').Trim()
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Host '已取消操作。' -ForegroundColor Gray
        Wait-Return
        return
    }

    $base         = $null
    $classes      = $null
    $extKey       = $null
    $ok           = $false
    $removedAssoc = $null
    try {
        $base    = Get-BaseKey -Scope $target.Scope
        $classes = $base.OpenSubKey($script:ClassesPath, $true)
        if ($null -eq $classes) {
            Write-Host "❌ 移除失败：无法打开 $($target.Scope)\$script:ClassesPath（可能需要管理员权限）。" -ForegroundColor Red
            Wait-Return
            return
        }

        $extKey = $classes.OpenSubKey($target.Extension, $true)
        if ($null -eq $extKey) {
            Write-Host "❌ 移除失败：无法打开 $($target.Extension)（可能需要管理员权限）。" -ForegroundColor Red
            Wait-Return
            return
        }

        $extKey.DeleteSubKeyTree('ShellNew')

        # 若关联是本脚本自建的（NewMenuMgr. 命名空间），一并清理，避免留下悬空的类型关联。
        # 只认自己的前缀，绝不触碰系统或第三方 ProgID。
        $assoc = [string]$extKey.GetValue('')
        if ($assoc -and $assoc.StartsWith($script:ProgIdPrefix)) {
            $extKey.DeleteValue('', $false)
            $classes.DeleteSubKeyTree($assoc, $false)
            $removedAssoc = $assoc
        }
        $ok = $true
    } catch {
        Write-Host "❌ 移除失败: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        if ($null -ne $extKey)  { $extKey.Close()  }
        if ($null -ne $classes) { $classes.Close() }
        if ($null -ne $base)    { $base.Close()    }
    }

    if ($ok) {
        Update-Explorer
        Write-Host "✅ 已移除 [$($target.Extension)] 的新建菜单项。" -ForegroundColor Green
        if ($removedAssoc) {
            Write-Host "   已一并清理自建的文件类型关联: $removedAssoc" -ForegroundColor Gray
        } else {
            Write-Host '   文件类型关联未改动（非本脚本创建）。' -ForegroundColor Gray
        }
    }

    Wait-Return
}

# ----------------------------------------------------------------------------
# 主循环
# ----------------------------------------------------------------------------

do {
    Show-Header 'Windows 右键新建菜单 管理工具'

    if (Test-IsAdmin) {
        Write-Host '  权限: 管理员（可写入「所有用户」）' -ForegroundColor Green
    } else {
        Write-Host '  权限: 标准用户（仅可写入「当前用户」，已足够）' -ForegroundColor Yellow
    }
    Write-Host '  默认写入 HKCU\Software\Classes；扩展名无关联时会自动建立，已有则保留。' -ForegroundColor DarkGray
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '  1. 添加新建菜单项' -ForegroundColor Green
    Write-Host '  2. 查看 / 移除新建菜单项' -ForegroundColor Yellow
    Write-Host '  0. 退出脚本' -ForegroundColor Gray
    Write-Host '========================================' -ForegroundColor Cyan

    $choice = (Read-Host '请输入你的选择').Trim()

    switch ($choice) {
        '1' { Add-NewMenuItem }
        '2' { Remove-NewMenuItem }
        '0' {
            Write-Host '正在退出...' -ForegroundColor Cyan
            exit 0
        }
        default {
            Write-Host '❌ 无效的输入，请重新选择。' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
