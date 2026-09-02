# 实用 bat 与 PowerShell 小工具集

存放日常高频使用的批量脚本工具：运行 Python / Node 脚本、开静态文件服务、查公网 IP、
清理系统垃圾、管理 Windows 右键「新建」菜单等。以 `.bat` 作为入口，核心逻辑在 `.ps1` / 直接命令中。

## 目录结构

```text
RunPython/
├── RunNodeJS-HTTP.bat                 # Node http-server 静态文件服务
├── RunNodeJS.bat                      # Node 脚本启动器
├── RunPython-HTTP.bat                 # Python http.server 静态文件服务
├── RunPython[python].bat              # Python 脚本运行器（系统 python）
├── RunPython[uv].bat                  # Python 脚本运行器（uv 环境）
├── PS-Tools/                          # PowerShell 工具集（脚本自带中文交互菜单）
│   ├── generator.ps1                  # 开发者工具箱（UUID/密码/哈希/端口等）
│   ├── MDTree.ps1                     # MDTree 开发者辅助工具
│   ├── ManageNewMenu.ps1              # Windows 右键「新建」菜单管理工具
│   ├── Get-IP.ps1                     # 公网 IP 查询（Invoke-RestMethod 版）
│   ├── Get-IP-curl.ps1                # 公网 IP 查询（curl.exe 版）
│   ├── ConvertTxtToBase64.ps1         # TXT 文件批量转 Base64
│   ├── TempCleaner_Pro.ps1            # Windows 系统垃圾安全清理
│   └── Test-PSModules/                # PowerShell 脚本/模块自动测试工具
│       ├── Test-PSModules.ps1         # 主脚本（自动/手动两种模式）
│       ├── Test-PSModules.bat         # 双击运行入口
│       └── README.md                  # 详细使用说明
├── x/                                 # 零散说明文档
│   └── RunNodeJS-HTTP.md              # http-server 静态服务使用说明
├── log/                               # 运行日志目录
└── README.md
```

> 说明：目录树省略了 `desktop.ini`、文件夹图标 `.ico` 等系统隐藏文件。

## 功能描述

### 根目录 .bat

| 脚本 | 所需环境 | 功能 |
| ---- | ---- | ---- |
| `RunNodeJS.bat` | Node.js（可选 nodemon） | 扫描当前目录 `*.js / *.mjs / *.cjs`，多个脚本时列出选择，单文件直接运行；已装 nodemon 时自动用于热重载 |
| `RunNodeJS-HTTP.bat` | `http-server`（`npm i -g http-server`） | 一行命令将当前目录变成静态文件服务器（`0.0.0.0`、禁用缓存） |
| `RunPython[python].bat` | Python | 扫描当前目录 `*.py` 并列出选择后运行；单文件自动直接运行 |
| `RunPython[uv].bat` | Python + uv | 同上，但通过 `uv` 在项目环境（uv.lock/pyproject）中运行 |
| `RunPython-HTTP.bat` | Python | `python -m http.server 8000`，把当前目录变为局域网可访问的静态服务 |

### PS-Tools（PowerShell 工具）

| 脚本 | 功能 |
| ---- | ---- |
| `generator.ps1` | **开发者工具箱**主菜单：生成 UUID v4、随机密码、Unix 时间戳、随机数，Base64 编解码，MD5/SHA256 哈希，内外网 IP，端口占用检查，Cron 表达式解释，HEX/RGB 颜色转换 |
| `MDTree.ps1` | **MDTree 开发者辅助工具**：生成带大小/日期的目录树（MD & HTML 双格式），JSON 格式化/压缩，图片转 Base64，CSV/XML/JSON 互转与 MD 表格生成 |
| `ManageNewMenu.ps1` | **Windows 右键「新建」菜单管理工具**，主菜单三项功能：<br>1. 添加新建菜单项 —— 自动建立文件类型关联，不覆盖已有关联（默认写入 HKCU，免管理员）<br>2. 查看 / 移除新建菜单项 —— 支持第二层 `ShellNew` 扫描（可识别 Office/WPS 等软件写入的条目），移除时一并清理自建关联<br>3. 管理扩展名的「打开方式」—— 清理程序卸载后残留的打开方式候选条目 |
| `Get-IP.ps1` | 公网 IP 查询（`Invoke-RestMethod` 版）：IPv4 + IPv6 地址 |
| `Get-IP-curl.ps1` | 公网 IP 查询（`curl.exe` 版）：同上功能，依赖系统自带 curl |
| `ConvertTxtToBase64.ps1` | 列出当前目录所有 `.txt` 文件，确认后转为 Base64 文本另存 |
| `TempCleaner_Pro.ps1` | 安全清理 Windows 临时文件/垃圾：默认仅清理 1 天前的文件，可排除指定目录，防止误伤运行中的安装程序，带清理统计 |

### Test-PSModules（子目录工具）

`Test-PSModules.ps1` 是通用的 PowerShell 脚本/模块自动测试工具：

- **自动模式**：无参数运行，自动识别「主脚本 + modules 目录」等常见结构并测试；
- **手动模式**：`-File` / `-MainScript` / `-ModuleDir` / `-CheckFunctions` 等参数精确指定测试目标；
- 测试项：语法检查（AST）、模块加载、函数可用性；完成后生成 `test_result.txt` 报告。

详细用法见 [`PS-Tools/Test-PSModules/README.md`](PS-Tools/Test-PSModules/README.md)。

## 使用方式

- `.bat` 文件：双击运行，或命令行中直接调用；
- `.ps1` 文件：在 PowerShell 中执行。若系统禁用了脚本执行策略，可先运行：
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```
- 需要管理员权限的功能（如写 HKLM 的关联项）会由脚本自动检测并提示。
