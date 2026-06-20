# Test-PSModules.ps1 使用说明

## 📌 工具简介

`Test-PSModules.ps1` 是一个**通用 PowerShell 脚本/模块自动测试工具**，支持两种运行模式：

| 模式 | 说明 |
|------|------|
| **自动模式** | 直接运行脚本，自动检测当前目录结构并完成测试 |
| **手动模式** | 通过参数指定测试目标，适合 CI 或精确测试 |

---

## 📂 推荐目录结构

将本工具放在独立目录，供多个项目共用：

```
PS-Tools/
└── Test-PSModules/
    ├── Test-PSModules.ps1   ← 测试工具主脚本
    └── README.md             ← 本文档
```

在其他项目中通过相对路径调用，例如：
```powershell
# 在 CFmg 项目中调用
..\PS-Tools\Test-PSModules\Test-PSModules.ps1
```

---

## 🚀 快速开始

### 自动模式（推荐）

直接运行脚本，无需任何参数：

```powershell
cd D:\myproject\Cloudflare_xxx\CFmg
D:\myproject\AIscript\PS-Tools\Test-PSModules\Test-PSModules.ps1
```

脚本会自动检测当前目录，按以下优先级测试：

```
检测到「主脚本 + modules 目录」
  → 测试主脚本语法 → 按引用顺序测试各模块 → 尝试加载模块
      ↓
检测到「只有 modules 目录」
  → 测试目录下所有 .ps1 文件 → 尝试加载
      ↓
检测到「只有主脚本」
  → 测试主脚本语法
      ↓
以上都没有
  → 测试当前目录所有 .ps1 文件（排除自身）
```

---

## ⚙️ 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `-File` | 字符串 | 测试单个 `.ps1` 文件路径 |
| `-MainScript` | 字符串 | 主脚本路径（自动解析 dot-source 引用） |
| `-ModuleDir` | 字符串 | 模块目录路径（测试目录下所有 `.ps1` 文件） |
| `-CheckFunctions` | 字符串数组 | 要检查是否可用的函数名列表 |
| `-VerboseOutput` | 开关 | 显示所有输出（包括 Info 级别） |
| `-Auto` | 开关 | 强制使用自动检测模式 |

### 使用示例

```powershell
# 示例 1：测试单个文件
.\Test-PSModules.ps1 -File "D:\path\to\script.ps1"

# 示例 2：测试模块目录
.\Test-PSModules.ps1 -ModuleDir "D:\path\to\modules"

# 示例 3：测试主脚本并解析其模块引用
.\Test-PSModules.ps1 -MainScript "main.ps1" -ModuleDir "modules"

# 示例 4：检查指定函数是否可用
.\Test-PSModules.ps1 -ModuleDir "modules" -CheckFunctions @("Get-Data", "Set-Config")

# 示例 5：详细输出模式
.\Test-PSModules.ps1 -VerboseOutput
```

---

## 🔧 配置说明

脚本顶部有一个配置变量，可直接修改：

```powershell
# =========================================================
# 配置区域 - 可直接修改以下变量控制脚本行为
# =========================================================

$ReportEnabled = $true   # 是否生成测试报告（保存至当前目录 test_result.txt）
```

| 值 | 行为 |
|-----|------|
| `$true`（默认） | 测试完成后生成 `test_result.txt` 报告文件 |
| `$false` | 不生成报告文件，只输出到控制台 |

---

## 📊 测试报告说明

运行完成后，会在**当前目录**生成 `test_result.txt`，内容结构如下：

```
========================================
  PowerShell 脚本/模块测试报告
  时间: 2026-06-20 10:30:00
========================================

测试结果统计：
  ✅ 通过: 8
  ❌ 失败: 0
  ⚠️ 警告: 1
  ℹ️ 信息: 5

总体结果: ✅ 所有测试通过！

========================================
详细日志：
========================================

[10:30:00] ℹ️ 自动检测: 主脚本 = cf_manager.ps1, 模块目录 = modules
[10:30:00] ✅ 语法检查通过: cf_manager.ps1
[10:30:00] ℹ️ 解析主脚本中的模块引用...
...
```

---

## 📋 测试项目说明

工具会自动执行以下测试：

| 测试项 | 说明 |
|--------|------|
| **语法检查** | 使用 PowerShell AST 解析器检查 `.ps1` 文件语法 |
| **模块加载** | 通过 dot-source 加载模块，检查是否有运行时错误 |
| **函数可用性** | 检查指定函数是否已被正确加载（需配合 `-CheckFunctions`） |

---

## ⏸️ 暂停功能

脚本运行完成后会**自动暂停**，显示以下提示：

```
========================================
  ✅ 所有测试通过！按任意键退出...
========================================
```

按任意键才会退出，方便查看测试结果。

根据测试结果，提示颜色不同：
- 🟢 绿色：所有测试通过
- 🔴 红色：测试失败
- 🟡 黄色：测试未完成

---

## 🔍 自动检测规则

### 主脚本识别规则

脚本会按以下顺序查找主脚本：

1. 文件名匹配：`cf_manager.ps1` / `main.ps1` / `start.ps1` / `app.ps1` / `script.ps1`
2. 内容匹配：包含 dot-source（`. xxx.ps1`）引用的 `.ps1` 文件

### 模块目录识别规则

脚本会按以下顺序查找模块目录：

1. 目录名匹配：`modules` / `module` / `Modules` / `Module`
2. 目录内包含 `.ps1` 文件

---

## 🛠️ 进阶用法

### 在 CI 中使用

若要集成到 CI 流程中，可配合 `-Auto` 参数使用：

```powershell
# CI 脚本示例
$tool = "D:\myproject\AIscript\PS-Tools\Test-PSModules\Test-PSModules.ps1"
& $tool -Auto -VerboseOutput

if ($LASTEXITCODE -ne 0) {
    Write-Error "测试失败，请检查 test_result.txt"
    exit 1
}
```

### 只检查语法不加载模块

使用 `-File` 或 `-ModuleDir` 参数但不检查函数：

```powershell
# 只做语法检查
.\Test-PSModules.ps1 -ModuleDir "modules"
```

---

## ❓ 常见问题

### Q：脚本运行后没有生成 `test_result.txt`？

**A：** 请检查脚本顶部的 `$ReportEnabled` 变量是否设置为 `$true`。

### Q：自动模式没有检测到我的项目结构？

**A：** 可手动指定参数，或调整项目目录结构以符合自动检测规则。

### Q：暂停功能在某些环境下不生效？

**A：** 暂停功能依赖 `$host.UI.RawUI.ReadKey`，在部分非交互式环境（如某些 CI）中可能无效，此时脚本会继续执行完毕并退出。

---

## 📝 更新日志

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0 | 2026-06-20 | 初始版本，支持自动/手动模式、报告生成、暂停功能 |
| v1.1 | 2026-06-20 | 修复 PowerShell 作用域 Bug（报告永不生成问题） |
| v1.2 | 2026-06-20 | 新增 `$ReportEnabled` 配置变量，移至独立目录 |

---

## 📄 授权

本工具为通用 PowerShell 测试脚本，可自由修改和使用。
