# =========================================================
# Test-PSModules.ps1 - 通用 PowerShell 脚本/模块自动测试工具
# 自动模式：直接运行脚本，自动检测并测试当前项目
# 手动模式：使用参数指定测试目标和选项
# =========================================================

[CmdletBinding()]
param(
    [string]$File = "",           # 要测试的单个 .ps1 文件路径
    [string]$MainScript = "",    # 主脚本路径（会自动加载并测试其中 dot-source 的模块）
    [string]$ModuleDir = "",    # 模块目录路径（测试目录下所有 .ps1 文件）
    [string[]]$CheckFunctions = @(),  # 要检查是否可用的函数名列表
    [switch]$VerboseOutput,      # 显示详细输出
    [switch]$Auto                # 自动模式（默认开启，除非指定了其他参数）
)

# 如果指定了任何具体参数，则关闭自动模式
if ($File -or $MainScript -or $ModuleDir -or $CheckFunctions.Count -gt 0) {
    $Auto = $false
} else {
    $Auto = $true
}

$ErrorActionPreference = "Continue"
$allGood = $true
$script:results = @()
$autoModeUsed = $false

# =========================================================
# 配置区域 - 可直接修改以下变量控制脚本行为
# =========================================================

$ReportEnabled = $true   # 是否生成测试报告（保存至当前目录 test_result.txt）

function Add-Result {
    param($Msg, $Level = "Info")
    $time = Get-Date -Format "HH:mm:ss"
    $icon = switch ($Level) {
        "Pass"   { "✅" }
        "Fail"   { "❌" }
        "Warn"   { "⚠️" }
        "Info"   { "ℹ️" }
        default   { "  " }
    }
    $line = "[$time] $icon $Msg"
    $script:results += [PSCustomObject]@{ Time = $time; Level = $Level; Message = $Msg; Line = $line }
    $color = switch ($Level) { "Pass" { "Green" } "Fail" { "Red" } "Warn" { "Yellow" } default { "Gray" } }
    Write-Host $line -ForegroundColor $color
}

function Test-Syntax {
    param($FilePath)
    $errors = @()
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$null, [ref]$errors)
        if ($errors.Count -gt 0) {
            Add-Result "语法错误: $(Split-Path $FilePath -Leaf)" "Fail"
            foreach ($err in $errors) {
                Add-Result "  行 $($err.Extent.StartLineNumber): $($err.Message)" "Fail"
            }
            return $false
        } else {
            Add-Result "语法检查通过: $(Split-Path $FilePath -Leaf)" "Pass"
            return $true
        }
    } catch {
        Add-Result "解析失败: $FilePath — $_" "Fail"
        return $false
    }
}

function Test-ModuleLoad {
    param($FilePath)
    try {
        . $FilePath
        Add-Result "加载成功: $(Split-Path $FilePath -Leaf)" "Pass"
        return $true
    } catch {
        Add-Result "加载失败: $(Split-Path $FilePath -Leaf) — $_" "Fail"
        return $false
    }
}

function Find-DotSourceFiles {
    param($MainScriptPath)
    $mainContent = Get-Content $MainScriptPath -Raw
    $dotSourceFiles = @()
    $mainDir = Split-Path $MainScriptPath

    # 逐行解析 dot-source 引用，完全避免正则引号转义问题
    $lines = $mainContent -split "`r?`n"
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        # 跳过注释行（# 在行首，允许前面有空白）
        if ($trimmed -match '^\s*#') { continue }

        # 只处理以 "." 开头后跟空白的行（dot-source）
        if ($trimmed -notmatch '^\.\s') { continue }

        # 去掉开头的 "." 和空白，得到路径部分
        $afterDot = ($trimmed -replace '^\.\s*', '').Trim()
        # 去掉行末注释（# 后面的内容）
        if ($afterDot -match '#') {
            $afterDot = ($afterDot -split '#')[0]
        }
        # 去掉末尾分号及以后内容（如行末分号注释）
        if ($afterDot -match ';') {
            $afterDot = ($afterDot -split ';')[0]
        }
        $afterDot = $afterDot.Trim()
        if (-not $afterDot) { continue }

        # ── 情况 A：Join-Path 表达式 ──
        # 例如：. (Join-Path $ModuleDir "WranglerCore.ps1")
        if ($afterDot -match 'Join-Path') {
            # 用简单字符串提取 .ps1 文件名，完全不用正则引号
            # 先找第一个双引号或单引号后的内容
            $startIdx = $afterDot.IndexOf('"')
            if ($startIdx -lt 0) { $startIdx = $afterDot.IndexOf("'") }
            if ($startIdx -ge 0) {
                $rest = $afterDot.Substring($startIdx + 1)
                # 找闭合引号
                $endIdx = $rest.IndexOf('"')
                if ($endIdx -lt 0) { $endIdx = $rest.IndexOf("'") }
                if ($endIdx -ge 0) {
                    $fileName = $rest.Substring(0, $endIdx)
                    if ($fileName -match '\.ps1$') {
                        # 在主脚本所在目录及其子目录中查找该文件
                        $found = $false
                        $searchDirs = @($mainDir)
                        foreach ($sub in @('modules', 'module', 'Modules', 'Module')) {
                            $searchDirs += Join-Path $mainDir $sub
                        }
                        foreach ($d in $searchDirs) {
                            $tryPath = Join-Path $d $fileName
                            if (Test-Path $tryPath) {
                                $absPath = Resolve-Path $tryPath | Select-Object -ExpandProperty Path
                                if ($dotSourceFiles -notcontains $absPath) {
                                    $dotSourceFiles += $absPath
                                }
                                $found = $true
                                break
                            }
                        }
                    }
                }
            }
            continue
        }

        # ── 情况 B：字面路径（如 . "path.ps1" 或 . path.ps1）──
        # 去掉首尾引号（不用正则，用简单替换）
        $pathPart = $afterDot
        $pathPart = $pathPart -replace '"', '' -replace "'", ''
        $pathPart = $pathPart.Trim()
        if (-not $pathPart) { continue }

        try {
            if (-not [System.IO.Path]::IsPathRooted($pathPart)) {
                $refPath = Join-Path $mainDir $pathPart
            } else {
                $refPath = $pathPart
            }
            if (Test-Path $refPath) {
                $refPath = Resolve-Path $refPath | Select-Object -ExpandProperty Path
                if ($dotSourceFiles -notcontains $refPath) {
                    $dotSourceFiles += $refPath
                }
            }
        } catch {
            # 路径含有非法字符时跳过，继续处理下一行
            continue
        }
    }
    return $dotSourceFiles
}

# =========================================================
# 自动检测逻辑
# =========================================================

if ($Auto) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  PowerShell 脚本/模块自动测试工具" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "自动检测项目中..." -ForegroundColor Yellow
    Write-Host ""
    
    $autoModeUsed = $true
    $currentDir = Get-Location | Select-Object -ExpandProperty Path
    
    # 检测策略 1：查找主脚本 + modules 目录
    $candidates = @("cf_manager.ps1", "main.ps1", "start.ps1", "app.ps1", "script.ps1")
    $foundMain = $null
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $currentDir $c)) {
            $foundMain = Join-Path $currentDir $c
            break
        }
    }
    
    # 如果没找到常见名称，查找包含 dot-source 的 .ps1 文件
    if (-not $foundMain) {
        $psFiles = Get-ChildItem -Path $currentDir -Filter "*.ps1" -File
        foreach ($f in $psFiles) {
            $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match '\.\s+') {
                $foundMain = $f.FullName
                break
            }
        }
    }
    
    # 检测 modules 目录
    $foundModuleDir = $null
    $moduleDirCandidates = @("modules", "module", "Modules", "Module")
    foreach ($d in $moduleDirCandidates) {
        $p = Join-Path $currentDir $d
        if (Test-Path $p) {
            $foundModuleDir = $p
            break
        }
    }
    
    # 执行自动测试
    if ($foundMain -and $foundModuleDir) {
        # 模式 A：主脚本 + 模块目录
        Add-Result "自动检测: 主脚本 = $(Split-Path $foundMain -Leaf), 模块目录 = $(Split-Path $foundModuleDir -Leaf)" "Info"
        Write-Host ""
        
        # 测试主脚本语法
        $ok = Test-Syntax $foundMain
        if (-not $ok) { $allGood = $false }
        
        # 解析主脚本中的 dot-source 引用
        Write-Host ""
        Add-Result "解析主脚本中的模块引用..." "Info"
        $dotSourceFiles = Find-DotSourceFiles $foundMain
        
        if ($dotSourceFiles.Count -eq 0) {
            Add-Result "未在主脚本中发现 dot-source 引用，改为测试整个模块目录" "Warn"
            # 回退：测试整个 modules 目录
            $psFiles = Get-ChildItem -Path $foundModuleDir -Filter "*.ps1" | Sort-Object Name
            Write-Host ""
            Add-Result "找到 $($psFiles.Count) 个 .ps1 文件" "Info"
            Write-Host ""
            foreach ($f in $psFiles) {
                $ok = Test-Syntax $f.FullName
                if (-not $ok) { $allGood = $false }
            }
            Write-Host ""
            Add-Result "尝试加载所有模块..." "Info"
            foreach ($f in $psFiles) {
                $ok = Test-ModuleLoad $f.FullName
                if (-not $ok) { $allGood = $false }
            }
        } else {
            # 找到 dot-source 引用，按引用顺序测试
            Add-Result "发现 $($dotSourceFiles.Count) 个模块引用" "Info"
            Write-Host ""
            foreach ($f in $dotSourceFiles) {
                $ok = Test-Syntax $f
                if (-not $ok) { $allGood = $false }
            }
            Write-Host ""
            Add-Result "尝试按顺序加载模块..." "Info"
            foreach ($f in $dotSourceFiles) {
                $ok = Test-ModuleLoad $f
                if (-not $ok) { $allGood = $false }
            }
        }
        
    } elseif ($foundModuleDir) {
        # 模式 B：只有模块目录
        Add-Result "自动检测: 模块目录 = $(Split-Path $foundModuleDir -Leaf)" "Info"
        Write-Host ""
        $psFiles = Get-ChildItem -Path $foundModuleDir -Filter "*.ps1" | Sort-Object Name
        if ($psFiles.Count -eq 0) {
            Add-Result "目录中没有找到 .ps1 文件" "Warn"
        } else {
            Add-Result "找到 $($psFiles.Count) 个 .ps1 文件" "Info"
            Write-Host ""
            foreach ($f in $psFiles) {
                $ok = Test-Syntax $f.FullName
                if (-not $ok) { $allGood = $false }
            }
            Write-Host ""
            Add-Result "尝试加载所有模块..." "Info"
            foreach ($f in $psFiles) {
                $ok = Test-ModuleLoad $f.FullName
                if (-not $ok) { $allGood = $false }
            }
        }
    } elseif ($foundMain) {
        # 模式 C：只有主脚本
        Add-Result "自动检测: 主脚本 = $(Split-Path $foundMain -Leaf)" "Info"
        Write-Host ""
        $ok = Test-Syntax $foundMain
        if (-not $ok) { $allGood = $false }
    } else {
        # 模式 D：测试当前目录所有 .ps1 文件
        $psFiles = Get-ChildItem -Path $currentDir -Filter "*.ps1" -File | Where-Object { $_.Name -ne "Test-PSModules.ps1" } | Sort-Object Name
        if ($psFiles.Count -eq 0) {
            Add-Result "当前目录中没有找到 .ps1 文件" "Warn"
            Write-Host ""
            Write-Host "提示：请将脚本放在当前目录，或指定 -MainScript / -ModuleDir 参数" -ForegroundColor Yellow
            Write-Host ""
            $allGood = $null
        } else {
            Add-Result "自动检测: 当前目录 .ps1 文件（共 $($psFiles.Count) 个）" "Info"
            Write-Host ""
            foreach ($f in $psFiles) {
                $ok = Test-Syntax $f.FullName
                if (-not $ok) { $allGood = $false }
            }
        }
    }
}

# =========================================================
# 手动模式（指定了参数）
# =========================================================

if (-not $autoModeUsed) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  PowerShell 脚本/模块测试工具" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # 模式 1：测试单个文件
    if ($File -and (Test-Path $File)) {
        Add-Result "模式: 测试单个文件 — $(Resolve-Path $File)" "Info"
        Write-Host ""
        $ok = Test-Syntax $File
        if (-not $ok) { $allGood = $false }
    }
    
    # 模式 2：测试目录下所有 .ps1 文件
    if ($ModuleDir -and (Test-Path $ModuleDir)) {
        Add-Result "模式: 测试模块目录 — $(Resolve-Path $ModuleDir)" "Info"
        Write-Host ""
        $psFiles = Get-ChildItem -Path $ModuleDir -Filter "*.ps1" | Sort-Object Name
        if ($psFiles.Count -eq 0) {
            Add-Result "目录中没有找到 .ps1 文件" "Warn"
        } else {
            Add-Result "找到 $($psFiles.Count) 个 .ps1 文件" "Info"
            Write-Host ""
            foreach ($f in $psFiles) {
                $ok = Test-Syntax $f.FullName
                if (-not $ok) { $allGood = $false }
            }
            Write-Host ""
            Add-Result "尝试加载所有模块..." "Info"
            foreach ($f in $psFiles) {
                $ok = Test-ModuleLoad $f.FullName
                if (-not $ok) { $allGood = $false }
            }
        }
    }
    
    # 模式 3：测试主脚本（自动解析其中的 dot-source 调用）
    if ($MainScript -and (Test-Path $MainScript)) {
        Add-Result "模式: 测试主脚本 — $(Resolve-Path $MainScript)" "Info"
        Write-Host ""
        
        # 先测试主脚本语法
        $ok = Test-Syntax $MainScript
        if (-not $ok) { $allGood = $false }
        
        # 解析主脚本中的 dot-source 调用
        Write-Host ""
        Add-Result "解析主脚本中的模块引用..." "Info"
        $dotSourceFiles = Find-DotSourceFiles $MainScript
        
        if ($dotSourceFiles.Count -eq 0) {
            Add-Result "未在主脚本中发现 dot-source 引用" "Warn"
        } else {
            Write-Host ""
            Add-Result "发现 $($dotSourceFiles.Count) 个模块引用" "Info"
            Write-Host ""
            foreach ($f in $dotSourceFiles) {
                $ok = Test-Syntax $f
                if (-not $ok) { $allGood = $false }
            }
            Write-Host ""
            Add-Result "尝试按顺序加载模块..." "Info"
            foreach ($f in $dotSourceFiles) {
                $ok = Test-ModuleLoad $f
                if (-not $ok) { $allGood = $false }
            }
        }
    }
    
    # 检查指定函数是否可用
    if ($CheckFunctions.Count -gt 0) {
        Write-Host ""
        Add-Result "检查指定函数是否可用..." "Info"
        foreach ($func in $CheckFunctions) {
            if (Get-Command $func -ErrorAction SilentlyContinue) {
                Add-Result "  函数可用: $func" "Pass"
            } else {
                Add-Result "  函数不可用: $func" "Fail"
                $allGood = $false
            }
        }
    }
}

# 总结
if ($allGood -ne $null) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    $passCount = ($script:results | Where-Object { $_.Level -eq "Pass" }).Count
    $failCount = ($script:results | Where-Object { $_.Level -eq "Fail" }).Count
    $warnCount = ($script:results | Where-Object { $_.Level -eq "Warn" }).Count
    Add-Result "测试结果: $passCount 通过, $failCount 失败, $warnCount 警告" "Info"
    if ($allGood) {
        Write-Host "  ✅ 所有测试通过！" -ForegroundColor Green
    } else {
        Write-Host "  ❌ 存在问题，请检查上述错误" -ForegroundColor Red
    }
    Write-Host "========================================" -ForegroundColor Cyan
}

# =========================================================
# 用法提示（无参数时显示）
# =========================================================

if (-not $autoModeUsed -and -not $File -and -not $ModuleDir -and -not $MainScript) {
    Write-Host ""
    Write-Host "用法：" -ForegroundColor Yellow
    Write-Host "  自动模式（直接运行）：" -ForegroundColor Cyan
    Write-Host "    .\Test-PSModules.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  手动模式（指定参数）：" -ForegroundColor Cyan
    Write-Host "    .\Test-PSModules.ps1 -File ""path\to\script.ps1""" -ForegroundColor Gray
    Write-Host "    .\Test-PSModules.ps1 -ModuleDir ""path\to\modules""" -ForegroundColor Gray
    Write-Host "    .\Test-PSModules.ps1 -MainScript ""main.ps1"" -ModuleDir ""modules""" -ForegroundColor Gray
    Write-Host ""
    Write-Host "参数说明：" -ForegroundColor Cyan
    Write-Host "  -File           要测试的单个 .ps1 文件路径" -ForegroundColor Gray
    Write-Host "  -MainScript     主脚本路径（自动解析 dot-source 引用）" -ForegroundColor Gray
    Write-Host "  -ModuleDir      模块目录（测试目录下所有 .ps1 文件）" -ForegroundColor Gray
    Write-Host "  -CheckFunctions 要检查是否可用的函数名列表" -ForegroundColor Gray
    Write-Host "  -VerboseOutput  显示所有输出（包括 Info 级别）" -ForegroundColor Gray
    Write-Host "  -Auto            强制使用自动检测模式" -ForegroundColor Gray
    Write-Host ""
    Write-Host "配置说明：" -ForegroundColor Cyan
    Write-Host "  脚本顶部 `$ReportEnabled` 变量控制是否生成报告" -ForegroundColor Gray
    Write-Host "  设置为 `$false` 可禁用报告生成" -ForegroundColor Gray
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Cyan
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# =========================================================
# 生成结果报告
# =========================================================

if ($ReportEnabled -and $script:results.Count -gt 0) {
    $outFile = Join-Path (Get-Location) "test_result.txt"
    $reportLines = @()
    $reportLines += "========================================"
    $reportLines += "  PowerShell 脚本/模块测试报告"
    $reportLines += "  时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $reportLines += "========================================"
    $reportLines += ""
    
    # 统计
    $passCount = ($script:results | Where-Object { $_.Level -eq "Pass" }).Count
    $failCount = ($script:results | Where-Object { $_.Level -eq "Fail" }).Count
    $warnCount = ($script:results | Where-Object { $_.Level -eq "Warn" }).Count
    $infoCount = ($script:results | Where-Object { $_.Level -eq "Info" }).Count
    
    $reportLines += "测试结果统计："
    $reportLines += "  ✅ 通过: $passCount"
    $reportLines += "  ❌ 失败: $failCount"
    $reportLines += "  ⚠️ 警告: $warnCount"
    $reportLines += "  ℹ️ 信息: $infoCount"
    $reportLines += ""
    
    if ($allGood -eq $true) {
        $reportLines += "总体结果: ✅ 所有测试通过！"
    } elseif ($allGood -eq $false) {
        $reportLines += "总体结果: ❌ 存在问题，请检查上述错误"
    } else {
        $reportLines += "总体结果: ⚠️ 未完成测试"
    }
    $reportLines += ""
    $reportLines += "========================================"
    $reportLines += "详细日志："
    $reportLines += "========================================"
    $reportLines += ""
    
    # 详细日志
    foreach ($r in $script:results) {
        $reportLines += $r.Line
    }
    
    $reportLines += ""
    $reportLines += "========================================"
    $reportLines += "  报告结束"
    $reportLines += "========================================"
    
    # 保存报告
    $reportLines | Out-File $outFile -Encoding UTF8
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  测试报告已生成" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  详细结果已保存至:" -ForegroundColor Gray
    Write-Host "  $outFile" -ForegroundColor Yellow
    Write-Host ""
    
    # 如果有失败，显示失败详情
    if ($failCount -gt 0) {
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "  失败详情：" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        $failResults = $script:results | Where-Object { $_.Level -eq "Fail" }
        foreach ($r in $failResults) {
            Write-Host "  $($r.Line)" -ForegroundColor Red
        }
        Write-Host ""
    }
}

# 暂停功能
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($allGood -eq $true) {
    Write-Host "  ✅ 所有测试通过！按任意键退出..." -ForegroundColor Green
} elseif ($allGood -eq $false) {
    Write-Host "  ❌ 测试失败！按任意键退出..." -ForegroundColor Red
} else {
    Write-Host "  测试未完成。按任意键退出..." -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

