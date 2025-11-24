#!/usr/bin/env python3
"""
UV 环境管理工具 - Linux 版本
功能：安装/更新 UV、配置环境变量、初始化项目环境
作者：AI Assistant
版本：1.1.0-Linux
"""

import os
import sys
import subprocess
import platform
import shutil
import shlex
from typing import Optional, Tuple

# ============================ 配置区域 ============================
UV_INDEX_URL = "https://pypi.tuna.tsinghua.edu.cn/simple"
UV_CACHE_PATH = os.path.expanduser("~/.cache/uv")
PYPI_MIRROR_URL = "https://mirrors.aliyun.com/pypi/simple/"

ENV_VARS = {
    "UV_DEFAULT_INDEX": UV_INDEX_URL,
    "UV_CACHE_DIR": UV_CACHE_PATH
}
# ============================ 配置结束 ============================


class UVEnvironmentManagerLinux:
    """Linux 专用 UV 环境管理器"""
    
    def __init__(self):
        self.env_vars = ENV_VARS
        self.home_dir = os.path.expanduser("~")
        self._check_linux_environment()
        self._check_python_version()
    
    def _check_linux_environment(self):
        """检查Linux环境"""
        if platform.system() != "Linux":
            print("❌ 此脚本仅适用于 Linux 系统")
            sys.exit(1)
        
        # 检测包管理器
        self.package_manager = self._detect_package_manager()
        print(f"✅ 检测到包管理器: {self.package_manager}")
    
    def _detect_package_manager(self):
        """检测包管理器"""
        managers = {
            'apt': ['apt', 'apt-get'],      # Debian/Ubuntu
            'yum': ['yum', 'dnf'],          # RHEL/CentOS/Fedora
            'pacman': ['pacman'],           # Arch
            'zypper': ['zypper'],           # openSUSE
            'apk': ['apk']                  # Alpine
        }
        
        for manager, commands in managers.items():
            for cmd in commands:
                if shutil.which(cmd):
                    return manager
        return "unknown"
    
    def _check_python_version(self):
        """检查Python版本"""
        try:
            if sys.version_info < (3, 7):
                print("❌ 需要 Python 3.7 或更高版本")
                self._suggest_python_install()
                sys.exit(1)
        except Exception as e:
            print(f"❌ 无法获取Python版本信息: {e}")
            sys.exit(1)
    
    def _suggest_python_install(self):
        """根据系统建议Python安装方法"""
        suggestions = {
            'apt': "sudo apt update && sudo apt install python3 python3-pip",
            'yum': "sudo yum install python3 python3-pip",
            'dnf': "sudo dnf install python3 python3-pip", 
            'pacman': "sudo pacman -S python python-pip",
            'zypper': "sudo zypper install python3 python3-pip",
            'apk': "sudo apk add python3 py3-pip"
        }
        
        if self.package_manager in suggestions:
            print(f"💡 建议安装命令: {suggestions[self.package_manager]}")
        else:
            print("💡 请使用系统包管理器安装 Python 3.7+")
    
    def clear_screen(self):
        """清屏"""
        os.system('clear')
    
    def display_header(self):
        """显示标题"""
        print("=" * 60)
        print("       UV 环境管理工具 Linux v1.1.0")
        print("=" * 60)
        print(f"操作系统: {platform.system()} {platform.release()}")
        print(f"发行版: {self._get_linux_distro()}")
        print(f"包管理器: {self.package_manager}")
        print(f"Python版本号: {platform.python_version()}")
        
        uv_version = self.get_uv_version()
        if uv_version:
            print(f"当前uv版本号: {uv_version}")
        else:
            print(f"当前uv版本号: 未安装")
            
        print(f"当前uv镜像源: {UV_INDEX_URL}")
        print(f"当前uv缓存路径: {UV_CACHE_PATH}")
        print("=" * 60)
    
    def _get_linux_distro(self):
        """获取Linux发行版信息"""
        try:
            with open('/etc/os-release', 'r') as f:
                for line in f:
                    if line.startswith('PRETTY_NAME='):
                        return line.split('=')[1].strip().strip('"')
        except:
            pass
        return "Unknown"
    
    def display_menu(self):
        """显示主菜单"""
        print("\n请选择要执行的操作：")
        print("1. 安装/更新UV")
        print("2. 配置环境变量") 
        print("3. 检查当前UV状态")
        print("4. 项目UV环境初始化")
        print("5. 安装系统依赖")
        print("0. 退出")
        print("-" * 60)
    
    def get_user_choice(self):
        """获取用户选择"""
        while True:
            try:
                choice = input("请输入选项 (0-5): ").strip()
                if choice in ['0', '1', '2', '3', '4', '5']:
                    return choice
                print("❌ 无效选择，请输入 0-5 之间的数字")
            except KeyboardInterrupt:
                print("\n\n用户中断输入")
                return '0'
    
    def run_command(self, command: str, check: bool = True) -> Tuple[bool, str]:
        """运行命令"""
        try:
            result = subprocess.run(
                shlex.split(command),
                check=check,
                capture_output=True,
                text=True,
                timeout=300
            )
            return result.returncode == 0, result.stdout.strip() or result.stderr.strip()
        except subprocess.CalledProcessError as e:
            return False, str(e)
        except subprocess.TimeoutExpired:
            return False, "命令执行超时"
        except FileNotFoundError:
            return False, f"命令未找到: {command}"
        except Exception as e:
            return False, f"执行命令时发生错误: {str(e)}"
    
    def get_uv_version(self) -> Optional[str]:
        """获取UV版本"""
        success, output = self.run_command("uv --version", check=False)
        return output if success else None
    
    def install_uv_linux(self) -> bool:
        """在Linux上安装UV"""
        print("\n选择安装方法：")
        print("1. 使用官方安装脚本（推荐）")
        print("2. 使用pip安装")
        print("3. 使用系统包管理器安装")
        
        choice = input("请选择 (1-3, 默认1): ").strip() or "1"
        
        if choice == "1":
            return self._install_uv_curl()
        elif choice == "2":
            return self._install_uv_pip()
        elif choice == "3":
            return self._install_uv_package_manager()
        else:
            return self._install_uv_curl()
    
    def _install_uv_curl(self) -> bool:
        """使用curl安装"""
        print("🚀 使用官方安装脚本安装...")
        command = "curl -LsSf https://astral.sh/uv/install.sh | sh"
        success, output = self.run_command(command)
        
        if success:
            print("✅ UV 安装成功")
            # 添加~/.cargo/bin到PATH
            self._add_cargo_to_path()
            return True
        else:
            print(f"❌ curl安装失败: {output}")
            return False
    
    def _install_uv_pip(self) -> bool:
        """使用pip安装"""
        print("🚀 使用pip安装...")
        command = f"{sys.executable} -m pip install uv --upgrade -i {PYPI_MIRROR_URL}"
        success, output = self.run_command(command)
        
        if success:
            print("✅ pip安装成功")
            return True
        else:
            print(f"❌ pip安装失败: {output}")
            return False
    
    def _install_uv_package_manager(self) -> bool:
        """使用系统包管理器安装"""
        install_commands = {
            'apt': "sudo apt update && sudo apt install uv",
            'yum': "sudo yum install uv", 
            'dnf': "sudo dnf install uv",
            'pacman': "sudo pacman -S uv",
            'zypper': "sudo zypper install uv",
            'apk': "sudo apk add uv"
        }
        
        if self.package_manager not in install_commands:
            print(f"❌ 不支持的系统包管理器: {self.package_manager}")
            return False
        
        print(f"🚀 使用 {self.package_manager} 安装...")
        success, output = self.run_command(install_commands[self.package_manager])
        
        if success:
            print("✅ 包管理器安装成功")
            return True
        else:
            print(f"❌ 包管理器安装失败: {output}")
            return False
    
    def _add_cargo_to_path(self):
        """添加cargo到PATH"""
        cargo_bin = os.path.expanduser("~/.cargo/bin")
        if os.path.exists(cargo_bin):
            # 在当前会话中添加
            os.environ["PATH"] = cargo_bin + ":" + os.environ.get("PATH", "")
            print(f"✅ 已添加 {cargo_bin} 到PATH")
    
    def set_environment_variables(self) -> bool:
        """设置环境变量"""
        print("\n" + "=" * 50)
        print("         配置 UV 环境变量")
        print("=" * 50)
        
        # 显示当前状态
        print("\n当前环境变量状态:")
        for var_name, expected_value in self.env_vars.items():
            current_value = os.environ.get(var_name)
            status = "✅" if current_value == expected_value else "❌"
            print(f"  {status} {var_name} = {current_value or '未设置'}")
        
        confirm = input("\n❓ 是否继续设置环境变量？(y/N): ").strip().lower()
        if confirm not in ['y', 'yes']:
            print("❌ 操作已取消")
            return False
        
        # 确定shell配置文件
        shell_rc = self._detect_shell_rc()
        if not shell_rc:
            print("❌ 无法确定shell配置文件")
            return False
        
        print(f"📝 将配置写入: {shell_rc}")
        
        success_count = 0
        for var_name, var_value in self.env_vars.items():
            if self._set_env_var_linux(var_name, var_value, shell_rc):
                success_count += 1
        
        if success_count == len(self.env_vars):
            print(f"\n✅ 环境变量配置完成")
            print(f"💡 请运行 'source {shell_rc}' 或重新打开终端使配置生效")
            return True
        else:
            print(f"⚠️  部分环境变量设置失败 ({success_count}/{len(self.env_vars)})")
            return False
    
    def _detect_shell_rc(self):
        """检测shell配置文件"""
        shell = os.environ.get('SHELL', '')
        rc_files = []
        
        if 'zsh' in shell:
            rc_files = ['.zshrc', '.zprofile']
        elif 'fish' in shell:
            rc_files = ['.config/fish/config.fish']
        else:  # 默认bash
            rc_files = ['.bashrc', '.bash_profile', '.profile']
        
        for rc_file in rc_files:
            rc_path = os.path.join(self.home_dir, rc_file)
            if os.path.exists(rc_path):
                return rc_path
        
        # 如果都不存在，使用.bashrc
        return os.path.join(self.home_dir, '.bashrc')
    
    def _set_env_var_linux(self, var_name: str, var_value: str, rc_file: str) -> bool:
        """设置Linux环境变量"""
        try:
            # 读取现有内容
            lines = []
            if os.path.exists(rc_file):
                with open(rc_file, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
            
            # 查找并替换或添加
            var_pattern = f'export {var_name}='
            new_line = f'export {var_name}="{var_value}"\n'
            found = False
            
            new_lines = []
            for line in lines:
                if line.strip().startswith(var_pattern):
                    new_lines.append(new_line)
                    found = True
                else:
                    new_lines.append(line)
            
            if not found:
                new_lines.append(f'\n# UV Environment Variables\n{new_line}')
            
            # 写回文件
            with open(rc_file, 'w', encoding='utf-8') as f:
                f.writelines(new_lines)
            
            # 设置当前进程环境变量
            os.environ[var_name] = var_value
            
            print(f"✅ {var_name} = {var_value}")
            return True
            
        except Exception as e:
            print(f"❌ 设置 {var_name} 失败: {e}")
            return False
    
    def check_current_status(self):
        """检查当前状态"""
        print("\n" + "=" * 50)
        print("             当前 UV 状态")
        print("=" * 50)
        
        # UV安装状态
        version = self.get_uv_version()
        if version:
            print(f"✅ UV 已安装 - {version}")
            uv_path = shutil.which("uv")
            if uv_path:
                print(f"📍 UV 路径: {uv_path}")
        else:
            print("❌ UV 未安装")
        
        # 环境变量状态
        print("\n环境变量状态:")
        for var_name, expected_value in self.env_vars.items():
            current_value = os.environ.get(var_name)
            status = "✅" if current_value == expected_value else "❌"
            print(f"  {status} {var_name} = {current_value or '未设置'}")
        
        # 项目环境检查
        current_dir = os.getcwd()
        print(f"\n📁 当前目录: {current_dir}")
        
        venv_path = os.path.join(current_dir, ".venv")
        if os.path.exists(venv_path):
            print("✅ 当前目录已存在 UV 虚拟环境 (.venv)")
            python_path = os.path.join(venv_path, "bin", "python")
            if os.path.exists(python_path):
                success, output = self.run_command(f'"{python_path}" --version', check=False)
                if success:
                    print(f"🐍 虚拟环境Python版本: {output}")
    
    def initialize_project_environment(self) -> bool:
        """初始化项目环境"""
        print("\n" + "=" * 50)
        print("         项目 UV 环境初始化")
        print("=" * 50)
        
        if not self.get_uv_version():
            print("❌ 请先安装 UV")
            input("按回车键继续...")
            return False
        
        project_path = input("请输入项目路径（直接回车使用当前目录）: ").strip()
        if not project_path:
            project_path = os.getcwd()
        
        project_path = os.path.abspath(project_path)
        if not os.path.exists(project_path):
            print(f"❌ 路径不存在: {project_path}")
            return False
        
        original_dir = os.getcwd()
        try:
            os.chdir(project_path)
            print(f"📁 项目目录: {project_path}")
            
            # 执行初始化步骤
            steps = [
                ("执行 uv init", "uv init"),
                ("创建虚拟环境", "uv venv"),
                ("安装基础工具", "uv add pip setuptools wheel")
            ]
            
            for step_name, command in steps:
                print(f"\n📝 {step_name}...")
                success, output = self.run_command(command, check=False)
                if success or "already exists" in output.lower():
                    print(f"✅ {step_name} 完成")
                else:
                    print(f"❌ {step_name} 失败: {output}")
                    return False
            
            # 显示激活信息
            activate_cmd = "source .venv/bin/activate"
            print(f"\n🎉 环境初始化完成！")
            print(f"🚀 激活命令: {activate_cmd}")
            print(f"📊 项目路径: {project_path}")
            
            return True
            
        except Exception as e:
            print(f"❌ 初始化失败: {e}")
            return False
        finally:
            os.chdir(original_dir)
    
    def install_system_dependencies(self):
        """安装系统依赖"""
        print("\n" + "=" * 50)
        print("          安装系统依赖")
        print("=" * 50)
        
        dependencies = {
            'apt': ["curl", "python3", "python3-pip", "python3-venv", "build-essential"],
            'yum': ["curl", "python3", "python3-pip", "gcc", "gcc-c++", "make"],
            'dnf': ["curl", "python3", "python3-pip", "gcc", "gcc-c++", "make"],
            'pacman': ["curl", "python", "python-pip", "gcc", "base-devel"],
            'zypper': ["curl", "python3", "python3-pip", "gcc", "gcc-c++", "make"],
            'apk': ["curl", "python3", "py3-pip", "gcc", "musl-dev", "make"]
        }
        
        if self.package_manager not in dependencies:
            print(f"❌ 不支持的系统: {self.package_manager}")
            return
        
        deps = dependencies[self.package_manager]
        print(f"📦 将安装依赖: {', '.join(deps)}")
        
        confirm = input("❓ 是否继续？(y/N): ").strip().lower()
        if confirm not in ['y', 'yes']:
            print("❌ 操作取消")
            return
        
        install_commands = {
            'apt': f"sudo apt update && sudo apt install -y {' '.join(deps)}",
            'yum': f"sudo yum install -y {' '.join(deps)}",
            'dnf': f"sudo dnf install -y {' '.join(deps)}",
            'pacman': f"sudo pacman -S --noconfirm {' '.join(deps)}",
            'zypper': f"sudo zypper install -y {' '.join(deps)}",
            'apk': f"sudo apk add {' '.join(deps)}"
        }
        
        command = install_commands[self.package_manager]
        print(f"🚀 执行: {command}")
        
        success, output = self.run_command(command)
        if success:
            print("✅ 系统依赖安装完成")
        else:
            print(f"❌ 安装失败: {output}")
    
    def run(self):
        """运行主程序"""
        try:
            while True:
                self.clear_screen()
                self.display_header()
                self.display_menu()
                
                choice = self.get_user_choice()
                
                if choice == '1':
                    self.clear_screen()
                    if self.install_uv_linux():
                        input("\n✅ 操作成功，按回车键返回主菜单...")
                    else:
                        input("\n❌ 操作失败，按回车键返回主菜单...")
                
                elif choice == '2':
                    self.clear_screen()
                    if self.set_environment_variables():
                        input("\n✅ 配置完成，按回车键返回主菜单...")
                    else:
                        input("\n❌ 配置失败，按回车键返回主菜单...")
                
                elif choice == '3':
                    self.clear_screen()
                    self.check_current_status()
                    input("\n📊 状态检查完成，按回车键返回主菜单...")
                
                elif choice == '4':
                    self.clear_screen()
                    if self.initialize_project_environment():
                        input("\n✅ 初始化完成，按回车键返回主菜单...")
                    else:
                        input("\n❌ 初始化失败，按回车键返回主菜单...")
                
                elif choice == '5':
                    self.clear_screen()
                    self.install_system_dependencies()
                    input("\n📦 依赖安装完成，按回车键返回主菜单...")
                
                elif choice == '0':
                    print("\n👋 感谢使用 UV 环境管理工具！")
                    break
                    
        except KeyboardInterrupt:
            print("\n\n👋 程序被用户中断")
        except Exception as e:
            print(f"\n❌ 程序发生错误: {e}")
            input("按回车键退出...")


def main():
    """主函数"""
   