#!/usr/bin/env python3
"""
UV 环境管理工具 - 跨平台版本
功能：安装、更新、卸载 UV，配置镜像源和缓存路径。
支持：Windows、Linux、macOS
"""

import ctypes
import os
import platform
import shutil
import subprocess
import sys
import sysconfig
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


DEFAULT_INDEX_URL = "https://pypi.tuna.tsinghua.edu.cn/simple"
DEFAULT_PIP_INDEX_URL = "https://mirrors.aliyun.com/pypi/simple/"

MIRROR_PRESETS = {
    "1": ("清华大学", "https://pypi.tuna.tsinghua.edu.cn/simple"),
    "2": ("阿里云", "https://mirrors.aliyun.com/pypi/simple/"),
    "3": ("中国科学技术大学", "https://pypi.mirrors.ustc.edu.cn/simple/"),
    "4": ("腾讯云", "https://mirrors.cloud.tencent.com/pypi/simple"),
    "5": ("官方 PyPI", "https://pypi.org/simple"),
}

ENV_INDEX_KEY = "UV_DEFAULT_INDEX"
ENV_CACHE_KEY = "UV_CACHE_DIR"


class UVManager:
    """按当前系统管理 uv。"""

    def __init__(self) -> None:
        self.system = platform.system()
        self.home_dir = Path.home()
        self.default_cache_dir = self._get_default_cache_dir()
        self.package_manager = self._detect_package_manager()
        self._check_supported_system()
        self._check_python_version()
        self._refresh_current_process_path()

    def _check_supported_system(self) -> None:
        if self.system not in {"Windows", "Linux", "Darwin"}:
            print(f"不支持的系统: {self.system}")
            sys.exit(1)

    def _check_python_version(self) -> None:
        if sys.version_info < (3, 7):
            print("需要 Python 3.7 或更高版本")
            sys.exit(1)

    def _get_default_cache_dir(self) -> str:
        if self.system == "Windows":
            return r"D:\AI\uv"
        if self.system == "Darwin":
            return str(self.home_dir / "Library" / "Caches" / "uv")
        return str(self.home_dir / ".cache" / "uv")

    def _detect_package_manager(self) -> str:
        if self.system == "Windows":
            return "winget" if shutil.which("winget") else "unknown"
        managers = ["brew", "apt", "dnf", "yum", "pacman", "zypper", "apk"]
        for manager in managers:
            if shutil.which(manager):
                return manager
        return "unknown"

    def _known_uv_bin_dirs(self) -> List[Path]:
        paths = [
            Path(sysconfig.get_path("scripts") or ""),
            self.home_dir / ".local" / "bin",
            self.home_dir / ".cargo" / "bin",
        ]
        if self.system == "Windows":
            paths.extend(
                [
                    self.home_dir / ".local" / "bin",
                    self.home_dir / "AppData" / "Roaming" / "Python" / "Scripts",
                ]
            )
        return [path for path in paths if str(path)]

    def _refresh_current_process_path(self) -> None:
        current_paths = os.environ.get("PATH", "").split(os.pathsep)
        normalized = {os.path.normcase(os.path.abspath(path)) for path in current_paths if path}

        added = []
        for path in self._known_uv_bin_dirs():
            if not path.exists():
                continue
            normalized_path = os.path.normcase(os.path.abspath(str(path)))
            if normalized_path not in normalized:
                added.append(str(path))
                normalized.add(normalized_path)

        if added:
            os.environ["PATH"] = os.pathsep.join(added + current_paths)

    def clear_screen(self) -> None:
        os.system("cls" if self.system == "Windows" else "clear")

    def pause(self, message: str = "按回车键返回主菜单...") -> None:
        try:
            input(f"\n{message}")
        except KeyboardInterrupt:
            pass

    def run_command(
        self,
        args: Sequence[str],
        check: bool = False,
        timeout: int = 300,
    ) -> Tuple[bool, str]:
        try:
            result = subprocess.run(
                list(args),
                check=check,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            output = "\n".join(
                part.strip()
                for part in [result.stdout, result.stderr]
                if part and part.strip()
            )
            return result.returncode == 0, output
        except subprocess.CalledProcessError as exc:
            output = "\n".join(
                part.strip()
                for part in [exc.stdout, exc.stderr]
                if part and part.strip()
            )
            return False, output or str(exc)
        except subprocess.TimeoutExpired:
            return False, "命令执行超时"
        except FileNotFoundError:
            return False, f"命令未找到: {' '.join(args)}"
        except Exception as exc:
            return False, f"执行命令时发生错误: {exc}"

    def get_uv_version(self) -> Optional[str]:
        success, output = self.run_command(["uv", "--version"])
        return output if success else None

    def get_uv_path(self) -> Optional[str]:
        return shutil.which("uv")

    def display_header(self) -> None:
        print("=" * 64)
        print("             UV 环境管理工具 v2.0.0")
        print("=" * 64)
        print(f"操作系统: {self.system} {platform.release()}")
        if self.system != "Windows":
            print(f"包管理器: {self.package_manager}")
        print(f"Python 版本: {platform.python_version()}")

        uv_version = self.get_uv_version()
        print(f"UV 版本: {uv_version or '未安装'}")
        print(f"UV 路径: {self.get_uv_path() or '未找到'}")
        print(f"镜像源: {os.environ.get(ENV_INDEX_KEY) or '未设置'}")
        print(f"缓存路径: {os.environ.get(ENV_CACHE_KEY) or '未设置'}")
        print("=" * 64)

    def display_menu(self) -> None:
        print("\n请选择要执行的操作：")
        print("1. 安装 UV")
        print("2. 更新 UV")
        print("3. 卸载 UV")
        print("4. 配置镜像源")
        print("5. 配置缓存路径")
        print("6. 检查当前状态")
        print("7. 初始化项目环境")
        print("0. 退出")
        print("-" * 64)

    def get_user_choice(self) -> str:
        valid_choices = {str(index) for index in range(8)} | {"0"}
        while True:
            try:
                choice = input("请输入选项 (0-7): ").strip()
                if choice in valid_choices:
                    return choice
                print("无效选择，请输入 0-7 之间的数字")
            except KeyboardInterrupt:
                print("\n用户中断输入")
                return "0"

    def install_uv(self) -> bool:
        print("\n选择安装方法：")
        print("1. 官方安装脚本（推荐）")
        print("2. pip 安装")
        if self.system == "Windows":
            print("3. winget 安装")
        else:
            print(f"3. 系统包管理器安装 ({self.package_manager})")

        choice = input("请选择 (1-3, 默认1): ").strip() or "1"
        if choice == "2":
            return self._install_with_pip()
        if choice == "3":
            return self._install_with_package_manager()
        return self._install_with_official_script()

    def _install_with_official_script(self) -> bool:
        print("\n正在使用官方安装脚本安装 UV...")
        if self.system == "Windows":
            command = [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                "irm https://astral.sh/uv/install.ps1 | iex",
            ]
        else:
            command = ["sh", "-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"]

        success, output = self.run_command(command)
        if success:
            self._refresh_current_process_path()
            self._broadcast_windows_environment_change()
            print("UV 安装成功")
            return True

        print(f"安装失败:\n{output}")
        return False

    def _install_with_pip(self) -> bool:
        print("\n正在使用 pip 安装 UV...")
        command = [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--upgrade",
            "uv",
            "-i",
            os.environ.get(ENV_INDEX_KEY, DEFAULT_PIP_INDEX_URL),
        ]
        success, output = self.run_command(command)
        if success:
            self._refresh_current_process_path()
            print("pip 安装成功")
            return True

        print(f"pip 安装失败:\n{output}")
        return False

    def _install_with_package_manager(self) -> bool:
        commands = self._package_manager_commands("install")
        if not commands:
            print(f"当前系统没有可用的包管理器安装命令: {self.package_manager}")
            return False

        print(f"\n正在使用 {self.package_manager} 安装 UV...")
        return self._run_command_chain(commands, "包管理器安装成功", "包管理器安装失败")

    def update_uv(self) -> bool:
        if not self.get_uv_version():
            print("UV 未安装，请先安装")
            return False

        print("\n选择更新方法：")
        print("1. uv self update（推荐，适用于官方安装器）")
        print("2. 重新运行官方安装脚本")
        print("3. pip 升级")
        if self.package_manager != "unknown":
            print(f"4. 系统包管理器升级 ({self.package_manager})")

        max_choice = "4" if self.package_manager != "unknown" else "3"
        choice = input(f"请选择 (1-{max_choice}, 默认1): ").strip() or "1"

        if choice == "1":
            success, output = self.run_command(["uv", "self", "update"])
            if success:
                print("UV 更新成功")
                return True
            print(f"uv self update 失败:\n{output}")
            return False
        if choice == "2":
            return self._install_with_official_script()
        if choice == "3":
            return self._install_with_pip()
        if choice == "4" and self.package_manager != "unknown":
            return self._update_with_package_manager()

        print("无效选择")
        return False

    def _update_with_package_manager(self) -> bool:
        commands = self._package_manager_commands("update")
        if not commands:
            print(f"当前系统没有可用的包管理器升级命令: {self.package_manager}")
            return False
        return self._run_command_chain(commands, "包管理器升级成功", "包管理器升级失败")

    def uninstall_uv(self) -> bool:
        if not self.get_uv_version():
            print("UV 未安装")
            return False

        print("\n选择卸载方法：")
        print("1. 删除官方安装器二进制文件（适用于官方安装器）")
        print("2. pip 卸载")
        if self.package_manager != "unknown":
            print(f"3. 系统包管理器卸载 ({self.package_manager})")

        max_choice = "3" if self.package_manager != "unknown" else "2"
        choice = input(f"请选择 (1-{max_choice}, 默认1): ").strip() or "1"

        if choice == "1":
            if self._uninstall_standalone_binaries():
                self._ask_remove_uv_environment()
                return True
            return False
        if choice == "2":
            return self._uninstall_with_pip()
        if choice == "3" and self.package_manager != "unknown":
            return self._uninstall_with_package_manager()

        print("无效选择")
        return False

    def _uninstall_standalone_binaries(self) -> bool:
        candidates = self._standalone_binary_candidates()
        if not candidates:
            print("未找到官方安装器常用位置中的 UV 二进制文件")
            print("如果 UV 由 pip、winget、brew 或系统包管理器安装，请选择对应卸载方式")
            return False

        print("\n将删除以下文件：")
        for path in candidates:
            print(f"  {path}")

        confirm = input("确认删除？(y/N): ").strip().lower()
        if confirm not in {"y", "yes"}:
            print("操作已取消")
            return False

        success = True
        for path in candidates:
            try:
                path.unlink()
                print(f"已删除: {path}")
            except Exception as exc:
                print(f"删除失败 {path}: {exc}")
                success = False
        return success

    def _standalone_binary_candidates(self) -> List[Path]:
        names = ["uv.exe", "uvx.exe", "uvw.exe"] if self.system == "Windows" else ["uv", "uvx", "uvw"]
        candidate_dirs = [self.home_dir / ".local" / "bin", self.home_dir / ".cargo" / "bin"]
        candidates = []
        for directory in candidate_dirs:
            try:
                resolved_dir = directory.resolve()
            except Exception:
                continue
            for name in names:
                path = resolved_dir / name
                if path.exists() and path.is_file():
                    candidates.append(path)
        return candidates

    def _uninstall_with_pip(self) -> bool:
        success, output = self.run_command([sys.executable, "-m", "pip", "uninstall", "-y", "uv"])
        if success:
            print("pip 卸载成功")
            self._ask_remove_uv_environment()
            return True
        print(f"pip 卸载失败:\n{output}")
        return False

    def _uninstall_with_package_manager(self) -> bool:
        commands = self._package_manager_commands("uninstall")
        if not commands:
            print(f"当前系统没有可用的包管理器卸载命令: {self.package_manager}")
            return False

        success = self._run_command_chain(commands, "包管理器卸载成功", "包管理器卸载失败")
        if success:
            self._ask_remove_uv_environment()
        return success

    def _package_manager_commands(self, action: str) -> List[List[str]]:
        if self.system == "Windows":
            if self.package_manager != "winget":
                return []
            if action == "install":
                return [["winget", "install", "-e", "--id", "astral-sh.uv", "--accept-package-agreements", "--accept-source-agreements"]]
            if action == "update":
                return [["winget", "upgrade", "-e", "--id", "astral-sh.uv", "--accept-package-agreements", "--accept-source-agreements"]]
            if action == "uninstall":
                return [["winget", "uninstall", "-e", "--id", "astral-sh.uv"]]

        commands: Dict[str, Dict[str, List[List[str]]]] = {
            "brew": {
                "install": [["brew", "install", "uv"]],
                "update": [["brew", "upgrade", "uv"]],
                "uninstall": [["brew", "uninstall", "uv"]],
            },
            "apt": {
                "install": [["sudo", "apt", "update"], ["sudo", "apt", "install", "-y", "uv"]],
                "update": [["sudo", "apt", "update"], ["sudo", "apt", "install", "--only-upgrade", "-y", "uv"]],
                "uninstall": [["sudo", "apt", "remove", "-y", "uv"]],
            },
            "dnf": {
                "install": [["sudo", "dnf", "install", "-y", "uv"]],
                "update": [["sudo", "dnf", "upgrade", "-y", "uv"]],
                "uninstall": [["sudo", "dnf", "remove", "-y", "uv"]],
            },
            "yum": {
                "install": [["sudo", "yum", "install", "-y", "uv"]],
                "update": [["sudo", "yum", "update", "-y", "uv"]],
                "uninstall": [["sudo", "yum", "remove", "-y", "uv"]],
            },
            "pacman": {
                "install": [["sudo", "pacman", "-S", "--noconfirm", "uv"]],
                "update": [["sudo", "pacman", "-S", "--noconfirm", "uv"]],
                "uninstall": [["sudo", "pacman", "-Rns", "--noconfirm", "uv"]],
            },
            "zypper": {
                "install": [["sudo", "zypper", "install", "-y", "uv"]],
                "update": [["sudo", "zypper", "update", "-y", "uv"]],
                "uninstall": [["sudo", "zypper", "remove", "-y", "uv"]],
            },
            "apk": {
                "install": [["sudo", "apk", "add", "uv"]],
                "update": [["sudo", "apk", "upgrade", "uv"]],
                "uninstall": [["sudo", "apk", "del", "uv"]],
            },
        }
        return commands.get(self.package_manager, {}).get(action, [])

    def _run_command_chain(self, commands: List[List[str]], success_message: str, failure_message: str) -> bool:
        for command in commands:
            print(f"执行: {' '.join(command)}")
            success, output = self.run_command(command)
            if not success:
                print(f"{failure_message}:\n{output}")
                return False
        self._refresh_current_process_path()
        self._broadcast_windows_environment_change()
        print(success_message)
        return True

    def configure_index_url(self) -> bool:
        print("\n可选镜像源：")
        for key, (name, url) in MIRROR_PRESETS.items():
            print(f"{key}. {name}: {url}")
        print("0. 自定义")

        current_value = os.environ.get(ENV_INDEX_KEY, DEFAULT_INDEX_URL)
        choice = input("请选择镜像源 (默认1): ").strip() or "1"
        if choice == "0":
            value = input(f"请输入镜像源 URL（当前 {current_value}）: ").strip()
            if not value:
                print("未输入 URL，操作取消")
                return False
        elif choice in MIRROR_PRESETS:
            value = MIRROR_PRESETS[choice][1]
        else:
            print("无效选择")
            return False

        return self._set_persistent_env_var(ENV_INDEX_KEY, value)

    def configure_cache_dir(self) -> bool:
        current_value = os.environ.get(ENV_CACHE_KEY, self.default_cache_dir)
        value = input(f"请输入 UV 缓存路径（默认 {current_value}）: ").strip() or current_value
        value = str(Path(value).expanduser())

        try:
            Path(value).mkdir(parents=True, exist_ok=True)
        except Exception as exc:
            print(f"创建缓存目录失败: {exc}")
            return False

        return self._set_persistent_env_var(ENV_CACHE_KEY, value)

    def _set_persistent_env_var(self, name: str, value: str) -> bool:
        os.environ[name] = value
        if self.system == "Windows":
            success = self._set_windows_user_env(name, value)
        else:
            success = self._set_unix_shell_env(name, value)

        if success:
            print(f"{name} = {value}")
            print("配置完成。重新打开终端后会自动生效，当前脚本进程已立即生效。")
        return success

    def _set_windows_user_env(self, name: str, value: str) -> bool:
        try:
            import winreg

            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_WRITE) as key:
                winreg.SetValueEx(key, name, 0, winreg.REG_EXPAND_SZ, value)
            self._broadcast_windows_environment_change()
            return True
        except Exception as exc:
            print(f"写入 Windows 用户环境变量失败: {exc}")
            return False

    def _set_unix_shell_env(self, name: str, value: str) -> bool:
        rc_file = self._detect_shell_rc()
        try:
            rc_file.parent.mkdir(parents=True, exist_ok=True)
            lines = rc_file.read_text(encoding="utf-8").splitlines() if rc_file.exists() else []
            new_line = self._format_shell_env_line(name, value)
            filtered_lines = [
                line
                for line in lines
                if not self._is_env_var_line(line, name)
            ]

            if filtered_lines and filtered_lines[-1].strip():
                filtered_lines.append("")
            filtered_lines.append("# UV environment")
            filtered_lines.append(new_line)
            rc_file.write_text("\n".join(filtered_lines) + "\n", encoding="utf-8")
            print(f"已写入: {rc_file}")
            return True
        except Exception as exc:
            print(f"写入 shell 配置失败: {exc}")
            return False

    def _detect_shell_rc(self) -> Path:
        shell = os.environ.get("SHELL", "")
        if "zsh" in shell:
            return self.home_dir / ".zshrc"
        if "fish" in shell:
            return self.home_dir / ".config" / "fish" / "config.fish"
        if self.system == "Darwin":
            return self.home_dir / ".zshrc"
        return self.home_dir / ".bashrc"

    def _format_shell_env_line(self, name: str, value: str) -> str:
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        shell = os.environ.get("SHELL", "")
        if "fish" in shell:
            return f'set -gx {name} "{escaped}"'
        return f'export {name}="{escaped}"'

    def _is_env_var_line(self, line: str, name: str) -> bool:
        stripped = line.strip()
        return stripped.startswith(f"export {name}=") or stripped.startswith(f"set -gx {name} ")

    def _ask_remove_uv_environment(self) -> None:
        confirm = input("是否同时删除 UV 镜像源和缓存路径环境变量？(y/N): ").strip().lower()
        if confirm not in {"y", "yes"}:
            return
        for name in [ENV_INDEX_KEY, ENV_CACHE_KEY]:
            self._remove_persistent_env_var(name)

    def _remove_persistent_env_var(self, name: str) -> bool:
        os.environ.pop(name, None)
        if self.system == "Windows":
            return self._remove_windows_user_env(name)
        return self._remove_unix_shell_env(name)

    def _remove_windows_user_env(self, name: str) -> bool:
        try:
            import winreg

            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_SET_VALUE) as key:
                try:
                    winreg.DeleteValue(key, name)
                    print(f"已删除: {name}")
                except FileNotFoundError:
                    print(f"未设置: {name}")
            self._broadcast_windows_environment_change()
            return True
        except Exception as exc:
            print(f"删除 Windows 用户环境变量失败: {exc}")
            return False

    def _remove_unix_shell_env(self, name: str) -> bool:
        rc_file = self._detect_shell_rc()
        if not rc_file.exists():
            print(f"配置文件不存在: {rc_file}")
            return True

        try:
            lines = rc_file.read_text(encoding="utf-8").splitlines()
            filtered_lines = [
                line
                for line in lines
                if not self._is_env_var_line(line, name)
            ]
            rc_file.write_text("\n".join(filtered_lines) + "\n", encoding="utf-8")
            print(f"已从 {rc_file} 删除: {name}")
            return True
        except Exception as exc:
            print(f"删除 shell 配置失败: {exc}")
            return False

    def _broadcast_windows_environment_change(self) -> None:
        if self.system != "Windows":
            return
        try:
            hwnd_broadcast = 0xFFFF
            wm_settingchange = 0x001A
            ctypes.windll.user32.SendMessageW(hwnd_broadcast, wm_settingchange, 0, "Environment")
        except Exception:
            pass

    def check_current_status(self) -> None:
        print("\n" + "=" * 64)
        print("当前 UV 状态")
        print("=" * 64)
        print(f"UV 版本: {self.get_uv_version() or '未安装'}")
        print(f"UV 路径: {self.get_uv_path() or '未找到'}")
        print(f"{ENV_INDEX_KEY}: {os.environ.get(ENV_INDEX_KEY) or '未设置'}")
        print(f"{ENV_CACHE_KEY}: {os.environ.get(ENV_CACHE_KEY) or '未设置'}")
        print(f"默认缓存路径建议: {self.default_cache_dir}")
        print(f"当前目录: {Path.cwd()}")

        venv_path = Path.cwd() / ".venv"
        python_path = venv_path / ("Scripts/python.exe" if self.system == "Windows" else "bin/python")
        if python_path.exists():
            success, output = self.run_command([str(python_path), "--version"])
            print(f"当前目录虚拟环境: {output if success else '存在但无法读取 Python 版本'}")
        else:
            print("当前目录虚拟环境: 未发现 .venv")

    def initialize_project_environment(self) -> bool:
        if not self.get_uv_version():
            print("请先安装 UV")
            return False

        project_path = input("请输入项目路径（直接回车使用当前目录）: ").strip()
        project_dir = Path(project_path).expanduser().resolve() if project_path else Path.cwd()
        if not project_dir.exists():
            print(f"路径不存在: {project_dir}")
            return False

        original_dir = Path.cwd()
        try:
            os.chdir(str(project_dir))
            steps = [
                ("执行 uv init", ["uv", "init"]),
                ("创建虚拟环境", ["uv", "venv"]),
                ("安装基础工具", ["uv", "pip", "install", "pip", "setuptools", "wheel"]),
            ]
            for step_name, command in steps:
                print(f"\n{step_name}...")
                success, output = self.run_command(command)
                if success or "already exists" in output.lower():
                    print(f"{step_name} 完成")
                else:
                    print(f"{step_name} 失败:\n{output}")
                    return False

            if self.system == "Windows":
                print("\n激活命令:")
                print(r"PowerShell: .venv\Scripts\Activate.ps1")
                print(r"CMD: .venv\Scripts\activate.bat")
            else:
                print("\n激活命令: source .venv/bin/activate")
            print(f"项目路径: {project_dir}")
            return True
        finally:
            os.chdir(str(original_dir))

    def run(self) -> None:
        try:
            while True:
                self.clear_screen()
                self.display_header()
                self.display_menu()
                choice = self.get_user_choice()

                self.clear_screen()
                if choice == "1":
                    self.install_uv()
                    self.pause()
                elif choice == "2":
                    self.update_uv()
                    self.pause()
                elif choice == "3":
                    self.uninstall_uv()
                    self.pause()
                elif choice == "4":
                    self.configure_index_url()
                    self.pause()
                elif choice == "5":
                    self.configure_cache_dir()
                    self.pause()
                elif choice == "6":
                    self.check_current_status()
                    self.pause()
                elif choice == "7":
                    self.initialize_project_environment()
                    self.pause()
                elif choice == "0":
                    print("感谢使用 UV 环境管理工具")
                    break
        except KeyboardInterrupt:
            print("\n程序被用户中断")


def main() -> None:
    manager = UVManager()
    manager.run()


if __name__ == "__main__":
    main()
