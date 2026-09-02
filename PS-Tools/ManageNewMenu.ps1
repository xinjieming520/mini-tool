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
# 打开方式管理（清理扩展名右键「打开方式」菜单中的残留/多余条目）
#
# 程序卸载后若没清干净登记，右键「打开方式」仍会列出它。管理三类来源：
#   [推荐] 扩展名键下的 OpenWithProgids —— 值名是 ProgID（安装程序写入）
#   [历史] FileExts\OpenWithList —— 曾用于打开该类型文件的程序 MRU（HKCU）
#   [注册] Classes\Applications\xxx.exe —— 全局登记的可打开该类型的应用
# 检测原理：ProgID / 应用的 shell\open\command 指向的可执行文件是否仍存在。
# 安全原则：仅删除用户明确选中的项；绝不碰 FileExts\UserChoice（默认程序）。
# ----------------------------------------------------------------------------

# 从 "C:\...\app.exe" "%1" / app.exe "%1" / 裸程序名 解析出真实存在的 exe 路径
function Resolve-AppExecutable {
    param([string]$InputText)

    if ([string]::IsNullOrWhiteSpace($InputText)) { return $null }
    # command 里常含 %SystemRoot% 这类环境变量，先展开再解析
    $text = [Environment]::ExpandEnvironmentVariables($InputText.Trim())

    if ($text.StartsWith('"')) {
        $m = [regex]::Match($text, '^"([^"]+)"')
        if ($m.Success) { $text = $m.Groups[1].Value }
    } elseif ($text.Contains(' ') -or $text.Contains("`t")) {
        $m = [regex]::Match($text, '^(\S+)')
        if ($m.Success) { $text = $m.Groups[1].Value }
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($text.Contains('\') -or $text.Contains('/') -or $text.Contains(':')) {
        # 完整路径
        $candidates.Add($text)
        if (-not [System.IO.Path]::HasExtension($text)) { $candidates.Add($text + '.exe') }
    } else {
        # 裸程序名：App Paths 全局注册（优先）→ PATH 兜底
        $name = $text
        if (-not [System.IO.Path]::HasExtension($name)) { $name += '.exe' }
        foreach ($base in @([Microsoft.Win32.Registry]::LocalMachine, [Microsoft.Win32.Registry]::CurrentUser)) {
            $ap = $null
            try {
                $ap = $base.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$name")
                if ($null -ne $ap) {
                    $val = [string]$ap.GetValue('')
                    if (-not [string]::IsNullOrWhiteSpace($val)) { $candidates.Add($val) }
                }
            } catch { } finally {
                if ($null -ne $ap) { $ap.Close() }
            }
        }
        foreach ($dir in ($env:PATH -split ';')) {
            if (-not [string]::IsNullOrWhiteSpace($dir)) { $candidates.Add((Join-Path $dir $name)) }
        }
    }

    foreach ($c in $candidates) {
        $p = [Environment]::ExpandEnvironmentVariables($c.Trim())
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
    }
    return $null
}

# 读取 exe 文件的版本信息（文件说明），用于友好显示名
function Get-FileVersionName {
    param([string]$Path)
    if (-not $Path) { return $null }
    try {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        if (-not [string]::IsNullOrWhiteSpace($vi.FileDescription)) { return $vi.FileDescription }
        if (-not [string]::IsNullOrWhiteSpace($vi.ProductName))    { return $vi.ProductName }
    } catch { }
    return $null
}

# 取 ProgID 的友好显示名（FriendlyTypeName / 默认描述）
function Get-ProgIdDisplayName {
    param($HkcrKey, [string]$ProgId)

    if ([string]::IsNullOrWhiteSpace($ProgId) -or $null -eq $HkcrKey) { return $ProgId }
    $key = $null
    try {
        $key = $HkcrKey.OpenSubKey($ProgId)
        if ($null -eq $key) { return $ProgId }
        $name = Resolve-IndirectString ([string]$key.GetValue('FriendlyTypeName'))
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = Resolve-IndirectString ([string]$key.GetValue(''))
        }
        if ([string]::IsNullOrWhiteSpace($name)) { return $ProgId }
        return $name
    } catch {
        return $ProgId
    } finally {
        if ($null -ne $key) { $key.Close() }
    }
}

# 枚举 [推荐] 来源：扩展名键 OpenWithProgids 中的建议 ProgID
function Get-OpenWithProgidRows {
    param([string]$Extension)

    $progIds = @{}
    foreach ($scope in @('HKCU', 'HKLM')) {
        $base = $null; $classes = $null; $extKey = $null; $owpKey = $null
        try {
            $base    = Get-BaseKey -Scope $scope
            $classes = $base.OpenSubKey($script:ClassesPath)
            if ($null -eq $classes) { continue }
            $extKey  = $classes.OpenSubKey($Extension)
            if ($null -eq $extKey)  { continue }
            $owpKey  = $extKey.OpenSubKey('OpenWithProgids')
            if ($null -eq $owpKey)  { continue }
            foreach ($vn in $owpKey.GetValueNames()) {
                if (-not [string]::IsNullOrEmpty($vn) -and -not $progIds.ContainsKey($vn)) {
                    $progIds[$vn] = $true
                }
            }
        } catch { } finally {
            if ($null -ne $owpKey)  { $owpKey.Close()  }
            if ($null -ne $extKey)  { $extKey.Close()  }
            if ($null -ne $classes) { $classes.Close() }
            if ($null -ne $base)    { $base.Close()    }
        }
    }

    if ($progIds.Count -eq 0) { return }

    $hkcr = $null
    try {
        $hkcr = Get-BaseKey -Scope 'HKCR'
        foreach ($progId in $progIds.Keys) {
            $display = Get-ProgIdDisplayName -HkcrKey $hkcr -ProgId $progId

            $progKey = $null
            $pExists = $false
            try {
                $progKey = $hkcr.OpenSubKey($progId)
                $pExists = ($null -ne $progKey)
            } finally {
                if ($null -ne $progKey) { $progKey.Close() }
            }

            $status = 'ok'; $statusText = '有效'
            if (-not $pExists) {
                $status = 'gone'; $statusText = '悬空（ProgID 已不存在）'
            } else {
                $cmdKey = $null; $cmd = $null
                try {
                    $cmdKey = $hkcr.OpenSubKey("$progId\shell\open\command")
                    if ($null -ne $cmdKey) { $cmd = [string]$cmdKey.GetValue('') }
                } catch { } finally {
                    if ($null -ne $cmdKey) { $cmdKey.Close() }
                }
                if ($null -eq (Resolve-AppExecutable -InputText $cmd)) {
                    $status = 'gone'; $statusText = '已卸载（程序不存在）'
                }
            }

            [PSCustomObject]@{
                Source = '推荐'; Kind = 'Progid'; Arg = $progId
                Name = $display; Detail = "ProgID: $progId"
                Status = $status; StatusText = $statusText
            }
        }
    } finally {
        if ($null -ne $hkcr) { $hkcr.Close() }
    }
}

# 枚举 [历史] 来源：FileExts 中曾用于打开该类型的程序（MRU）
function Get-OpenWithHistoryRows {
    param([string]$Extension)

    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\OpenWithList")
        if ($null -eq $key) { return }

        foreach ($vn in $key.GetValueNames()) {
            if ([string]::IsNullOrEmpty($vn) -or $vn -eq 'MRUList') { continue }
            $exeName = [string]$key.GetValue($vn)
            $exePath = Resolve-AppExecutable -InputText $exeName

            $display = $exeName
            $detail  = ''
            $status  = 'ok'
            $statusText = '有效'
            if ($exePath) {
                $fd = Get-FileVersionName -Path $exePath
                if ($fd) { $display = "$fd ($exeName)" }
                $detail = $exePath
            } elseif ($exeName.Contains('!')) {
                # 形如 "Microsoft.WindowsNotepad_xxx!App" —— UWP/商店应用标识，
                # 无法用 exe 判定其是否存在，不作"残留"误报，仅提示。
                $status = 'other'; $statusText = '应用条目（非可执行登记）'
                $detail = 'UWP/商店应用标识，暂不判定是否残留'
            } else {
                $status = 'gone'; $statusText = '已卸载（程序不存在）'
                $detail = '未能解析到该程序'
            }

            [PSCustomObject]@{
                Source = '历史'; Kind = 'History'; Arg = $vn
                Name = $display; Detail = $detail
                Status = $status; StatusText = $statusText
            }
        }
    } catch { } finally {
        if ($null -ne $key) { $key.Close() }
    }
}

# 枚举 [注册] 来源：全局登记的 Applications\xxx.exe 候选应用
# 仅列出「已卸载的残留」或「显式声明支持该扩展名」的应用，避免把
# 对任意文件都生效的通用候选全列出来造成误删。
function Get-ApplicationRows {
    param([string]$Extension)

    $apps = @{}
    foreach ($scope in @('HKCU', 'HKLM')) {
        $base = $null; $classes = $null; $appsKey = $null
        try {
            $base    = Get-BaseKey -Scope $scope
            $classes = $base.OpenSubKey($script:ClassesPath)
            if ($null -eq $classes) { continue }
            $appsKey = $classes.OpenSubKey('Applications')
            if ($null -eq $appsKey) { continue }
            foreach ($n in $appsKey.GetSubKeyNames()) {
                if (-not $apps.ContainsKey($n)) { $apps[$n] = $scope }
            }
        } catch { } finally {
            if ($null -ne $appsKey) { $appsKey.Close() }
            if ($null -ne $classes) { $classes.Close() }
            if ($null -ne $base)    { $base.Close()    }
        }
    }

    if ($apps.Count -eq 0) { return }

    $hkcr = $null
    try {
        $hkcr = Get-BaseKey -Scope 'HKCR'
        foreach ($app in $apps.Keys) {
            # 读取合并视图下的友好名 / 打开命令 / SupportedTypes
            $friendly = $null
            $appKey = $null
            try {
                $appKey = $hkcr.OpenSubKey("Applications\$app")
                if ($null -ne $appKey) {
                    $friendly = Resolve-IndirectString ([string]$appKey.GetValue('FriendlyAppName'))
                }
            } catch { } finally {
                if ($null -ne $appKey) { $appKey.Close() }
            }

            $cmdKey = $null; $cmd = $null
            $hasCmd = $false
            try {
                $cmdKey = $hkcr.OpenSubKey("Applications\$app\shell\open\command")
                if ($null -ne $cmdKey) {
                    $cmd = [string]$cmdKey.GetValue('')
                    $hasCmd = $true
                }
            } catch { } finally {
                if ($null -ne $cmdKey) { $cmdKey.Close() }
            }

            $stKey = $null
            $explicit = $false
            try {
                $stKey = $hkcr.OpenSubKey("Applications\$app\SupportedTypes")
                if ($null -ne $stKey) { $explicit = ($null -ne $stKey.GetValue($Extension)) }
            } catch { } finally {
                if ($null -ne $stKey) { $stKey.Close() }
            }

            # 没有 shell\open\command 的登记是历史遗留空壳（系统里大量 cmd.exe、
            # regedit.exe 等），Explorer 无法调用，不会出现在打开方式菜单——
            # 不列为残留，避免误报和误删。
            if (-not $hasCmd) { continue }

            $exePath = Resolve-AppExecutable -InputText $cmd
            if ($exePath) {
                # 程序仍存在：仅当它显式声明支持该扩展名才列出（用于去掉某项推荐）
                if (-not $explicit) { continue }
                $status = 'ok'; $statusText = '有效（该类型的候选）'
            } else {
                # 程序已消失：整键删除才是对「残留」的正确处理
                $status = 'gone'; $statusText = '已卸载（残留登记）'
            }

            if (-not $friendly) { $friendly = Get-FileVersionName -Path $exePath }
            if (-not $friendly) { $friendly = $app.TrimEnd('.exe') }

            $kind = if ($status -eq 'gone') { 'AppAll' } else { 'AppType' }
            [PSCustomObject]@{
                Source = '注册'; Kind = $kind; Arg = $app
                Name = $friendly; Detail = "登记键: Applications\$app"
                Status = $status; StatusText = $statusText
            }
        }
    } finally {
        if ($null -ne $hkcr) { $hkcr.Close() }
    }
}

# 删除单个条目（按来源类型分发到具体删除函数）
function Invoke-RemoveOpenWithRow {
    param([string]$Extension, $Row)

    switch ($Row.Kind) {
        'Progid'  { return (Remove-OpenWithProgidItem -Extension $Extension -ProgId $Row.Arg) }
        'History' { return (Remove-OpenWithHistoryItem -Extension $Extension -ValueName $Row.Arg) }
        'AppAll'  { return (Remove-ApplicationItem -Extension $Extension -AppName $Row.Arg -RemoveWholeApp) }
        'AppType' { return (Remove-ApplicationItem -Extension $Extension -AppName $Row.Arg) }
    }
    return $false
}

function Get-OpenWithRemoveExplain {
    param([string]$Extension, $Row)

    switch ($Row.Kind) {
        'Progid'  { return "从 $Extension\OpenWithProgids 移除建议项 $($Row.Arg)（HKCU/HKLM 均处理）" }
        'History' { return "从打开历史 FileExts\$Extension\OpenWithList 移除「$($Row.Name)」" }
        'AppAll'  { return "删除已卸载程序的全局登记 Classes\Applications\$($Row.Arg)（HKCU/HKLM）" }
        'AppType' { return "移除 $($Row.Arg) 对 $Extension 的支持声明（SupportedTypes）" }
    }
    return ''
}

# 删除 OpenWithProgids 中的某个建议 ProgID（两个 hive 都清理，删后清空键）
function Remove-OpenWithProgidItem {
    param([string]$Extension, [string]$ProgId)

    $ok = $false
    foreach ($scope in @('HKLM', 'HKCU')) {
        $base = $null; $classes = $null; $extKey = $null; $owpKey = $null
        try {
            $base    = Get-BaseKey -Scope $scope
            $classes = $base.OpenSubKey($script:ClassesPath, $true)
            if ($null -eq $classes) { continue }
            $extKey  = $classes.OpenSubKey($Extension, $true)
            if ($null -eq $extKey)  { continue }
            $owpKey  = $extKey.OpenSubKey('OpenWithProgids', $true)
            if ($null -eq $owpKey)  { continue }

            if ($owpKey.GetValueNames() -contains $ProgId) {
                $owpKey.DeleteValue($ProgId, $false)
                $ok = $true
            }
            if ($owpKey.ValueCount -eq 0 -and $owpKey.SubKeyCount -eq 0) {
                $extKey.DeleteSubKey('OpenWithProgids', $false)
            }
        } catch { } finally {
            if ($null -ne $owpKey)  { $owpKey.Close()  }
            if ($null -ne $extKey)  { $extKey.Close()  }
            if ($null -ne $classes) { $classes.Close() }
            if ($null -ne $base)    { $base.Close()    }
        }
    }
    return $ok
}

# 删除打开历史 OpenWithList 中的某个值，并同步修正 MRUList
function Remove-OpenWithHistoryItem {
    param([string]$Extension, [string]$ValueName)

    $folder = "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension"
    $key = $null
    $parent = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$folder\OpenWithList", $true)
        if ($null -eq $key) { return $false }

        if ($key.GetValueNames() -contains $ValueName) {
            $key.DeleteValue($ValueName, $false)
        }
        $mru = [string]$key.GetValue('MRUList')
        if (-not [string]::IsNullOrEmpty($mru)) {
            $mru2 = $mru -replace [regex]::Escape($ValueName.Substring(0, 1)), ''
            if ($mru2) {
                $key.SetValue('MRUList', $mru2, [Microsoft.Win32.RegistryValueKind]::String)
            } else {
                $key.DeleteValue('MRUList', $false)
            }
        }
        # 列表已空则连键一起删除，避免空残留
        if ($key.GetValueNames().Count -eq 0) {
            $key.Close(); $key = $null
            $parent = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($folder, $true)
            if ($null -ne $parent) { $parent.DeleteSubKey('OpenWithList', $false) }
        }
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $key)    { $key.Close()    }
        if ($null -ne $parent) { $parent.Close() }
    }
}

# 删除 Applications 登记：
#   -RemoveWholeApp → 应用已卸载，整个登记键删除
#   不带该开关      → 应用仍有效，仅去掉对该扩展名的支持声明
function Remove-ApplicationItem {
    param([string]$Extension, [string]$AppName, [switch]$RemoveWholeApp)

    $ok = $false
    foreach ($scope in @('HKLM', 'HKCU')) {
        $base = $null; $classes = $null; $appKey = $null; $stKey = $null
        try {
            $base    = Get-BaseKey -Scope $scope
            $classes = $base.OpenSubKey($script:ClassesPath, $true)
            if ($null -eq $classes) { continue }

            if ($RemoveWholeApp) {
                $appPath = "Applications\$AppName"
                $appKey = $classes.OpenSubKey($appPath)
                if ($null -ne $appKey) {
                    $classes.DeleteSubKeyTree($appPath, $false)
                    $ok = $true
                }
                continue
            }

            $appKey = $classes.OpenSubKey("Applications\$AppName", $true)
            if ($null -eq $appKey) { continue }
            $stKey = $appKey.OpenSubKey('SupportedTypes', $true)
            if ($null -eq $stKey)  { continue }

            if ($stKey.GetValueNames() -contains $Extension) {
                $stKey.DeleteValue($Extension, $false)
                $ok = $true
            }
            if ($stKey.ValueCount -eq 0 -and $stKey.SubKeyCount -eq 0) {
                $appKey.DeleteSubKey('SupportedTypes', $false)
            }
        } catch { } finally {
            if ($null -ne $stKey)  { $stKey.Close()  }
            if ($null -ne $appKey) { $appKey.Close() }
            if ($null -ne $classes) { $classes.Close() }
            if ($null -ne $base)    { $base.Close()    }
        }
    }
    return $ok
}

# 主流程：输入扩展名 → 列出三类打开方式条目 → 选择删除
function Manage-OpenWithMenu {
    Show-Header '管理扩展名的打开方式'
    Write-Host '作用：查看/移除某扩展名右键菜单「打开方式」中的条目。' -ForegroundColor DarkGray
    Write-Host '      红色「已卸载/悬空」= 程序卸载后的残留，可放心清理。' -ForegroundColor DarkGray
    Write-Host '      绿色「有效」= 程序仍安装，删除会移除它的打开方式候选（酌情操作）。' -ForegroundColor DarkGray

    $ext = (Read-Host '请输入文件后缀名 (例如 .jpg / .docx)').Trim()
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

    Write-Host "正在扫描 $ext 的打开方式条目..." -ForegroundColor Yellow

    $rows = @(Get-OpenWithProgidRows -Extension $ext) +
            @(Get-OpenWithHistoryRows -Extension $ext) +
            @(Get-ApplicationRows -Extension $ext)

    if ($rows.Count -eq 0) {
        Write-Host "`nℹ️  未找到 $ext 的打开方式条目（无推荐 ProgID、无使用历史、无注册候选）。" -ForegroundColor Gray
        Wait-Return
        return
    }

    Write-Host "`n找到 $($rows.Count) 个打开方式条目：" -ForegroundColor Cyan
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        $name = $r.Name
        if ($name.Length -gt 42) { $name = $name.Substring(0, 39) + '...' }
        $color = switch ($r.Status) { 'gone' { 'Red' } 'ok' { 'DarkGreen' } default { 'Yellow' } }
        Write-Host (" [{0,2}] [{1}] {2}" -f ($i + 1), $r.Source, $name) -NoNewline -ForegroundColor White
        Write-Host ('   ' + $r.StatusText) -ForegroundColor $color
        if ($r.Detail) {
            Write-Host ("        └ $($r.Detail)") -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host '输入要移除的序号（多个用逗号或空格分隔），0 取消：' -ForegroundColor Yellow
    $selection = (Read-Host '请选择').Trim()
    if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq '0') {
        Write-Host '已取消操作。' -ForegroundColor Gray
        Wait-Return
        return
    }

    $picks = @($selection -split '[\s,，]+' |
        Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ } |
        Sort-Object -Unique)
    if ($picks.Count -eq 0 -or ($picks | Where-Object { $_ -lt 1 -or $_ -gt $rows.Count }).Count -gt 0) {
        Write-Host '❌ 无效的序号输入。' -ForegroundColor Red
        Wait-Return
        return
    }

    Write-Host "`n即将移除以下 $($picks.Count) 项：" -ForegroundColor Yellow
    foreach ($p in $picks) {
        $r = $rows[$p - 1]
        $color = switch ($r.Status) { 'gone' { 'Red' } default { 'Yellow' } }
        Write-Host "  [$($r.Source)] $($r.Name)  ($($r.StatusText))" -ForegroundColor $color
        Write-Host ("     → " + (Get-OpenWithRemoveExplain -Extension $ext -Row $r)) -ForegroundColor DarkGray
    }

    $confirm = (Read-Host "`n确认删除？输入 y 确认，其它任意键取消").Trim()
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Host '已取消操作。' -ForegroundColor Gray
        Wait-Return
        return
    }

    $okCount = 0
    $failNames = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $picks) {
        $r = $rows[$p - 1]
        if (Invoke-RemoveOpenWithRow -Extension $ext -Row $r) {
            $okCount++
        } else {
            $failNames.Add($r.Name)
        }
    }

    Write-Host ''
    if ($okCount -gt 0) {
        Update-Explorer
        Write-Host "✅ 已移除 $okCount 项。" -ForegroundColor Green
        Write-Host '   若右键菜单未立即刷新，请重启资源管理器。' -ForegroundColor DarkGray
    }
    if ($failNames.Count -gt 0) {
        Write-Host "⚠️  以下 $($failNames.Count) 项删除失败（可能无权限或已被移除）：" -ForegroundColor Red
        Write-Host "   $($failNames -join '、')" -ForegroundColor Red
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
    Write-Host '  3. 管理扩展名的打开方式（清理残留）' -ForegroundColor Cyan
    Write-Host '  0. 退出脚本' -ForegroundColor Gray
    Write-Host '========================================' -ForegroundColor Cyan

    $choice = (Read-Host '请输入你的选择').Trim()

    switch ($choice) {
        '1' { Add-NewMenuItem }
        '2' { Remove-NewMenuItem }
        '3' { Manage-OpenWithMenu }
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
