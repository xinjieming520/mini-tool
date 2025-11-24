#!/usr/bin/env python3
"""
UV 环境管理工具 - Windows 版本
功能：安装/更新 UV、配置环境变量、初始化项目环境
作者：AI Assistant
版本：1.1.0-Windows
"""

import os
import sys
import subprocess
import platform
import shutil
import winreg
import ctypes
from typing import Optional, Tuple

# ============================ 配置区域 ============================
UV_INDEX_URL = r"https://pypi.tuna.tsinghua.edu.cn/simple"
UV_CACHE_PATH = r"D:\AI\uv"
PYPI_MIRROR_URL = r"https://mirrors.aliyun.com/pypi/simple/"

ENV_VARS = {
    "UV_DEFAULT_INDEX": UV_INDEX_URL,
    "UV_CACHE_DIR": UV_CACHE_PATH
}
# ============================ 配置结束 ============================


class UVEnvironmentManagerWindows:
    """Windows 专用 UV 环境管理器"""
    
    def __init__(self):
        self.env_vars = ENV_VARS
        self.home_dir = os.path.expanduser("~")
        self._check_python_version()
        self._check_windows_version()
    
    def _check_windows_version(self):
        """检查Windows版本"""
        if platform.system() != "Windows":
            print("❌ 此脚本仅适用于 Windows 系统")
            input("按回车键退出...")
            sys.exit(1)
        
        version = platform.version()
        print(f"✅ Windows 版本: {version}")
    
    def _check_python_version(self):
        """检查Python版本"""
        try:
            if sys.version_info < (3, 7):
                print("❌ 需要 Python 3.7 或更高版本")
                print("💡 请从 https://www.python.org/downloads/windows/ 下载")
                input("\n按回车键退出...")
                sys.exit(1)
        except Exception as e:
            print(f"❌ 无法获取Python版本信息: {e}")
            input("\n按回车键退出...")
            sys.exit(1)
    
    def clear_screen(self):
        """清屏"""
        os.system('cls')
    
    def display_header(self):
        """显示标题"""
        print("=" * 60)
        print("      UV 环境管理工具 Windows v1.1.0")
        print("=" * 60)
        print(f"操作系统: Windows {platform.release()}")
        print(f"Python版本号: {platform.python_version()}")
        
        uv_version = self.get_uv_version()
        if uv_version:
            print(f"当前uv版本号: {uv_version}")
        else:
            print(f"当前uv版本号: 未安装")
            
        print(f"当前uv镜像源: {UV_INDEX_URL}")
        print(f"当前uv缓存路径: {UV_CACHE_PATH}")
        print("=" * 60)
    
    def display_menu(self):
        """显示主菜单"""
        print("\n请选择要执行的操作：")
        print("1. 安装/更新UV")
        print("2. 配置环境变量")
        print("3. 检查当前UV状态")
        print("4. 项目UV环境初始化")
        print("5. 修复路径问题")
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
                command,
                shell=True,
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
        except Exception as e:
            return False, f"执行命令时发生错误: {str(e)}"
    
    def get_uv_version(self) -> Optional[str]:
        """获取UV版本"""
        success, output = self.run_command("uv --version", check=False)
        return output if success else None
    
    def install_uv_windows(self) -> bool:
        """在Windows上安装UV"""
        print("\n选择安装方法：")
        print("1. 使用官方PowerShell脚本（推荐）")
        print("2. 使用pip安装")
        print("3. 使用winget安装")
        
        choice = input("请选择 (1-3, 默认1): ").strip() or "1"
        
        if choice == "1":
            return self._install_uv_powershell()
        elif choice == "2":
            return self._install_uv_pip()
        elif choice == "3":
            return self._install_uv_winget()
        else:
            return self._install_uv_powershell()
    
    def _install_uv_powershell(self) -> bool:
        """使用PowerShell脚本安装"""
        print("🚀 使用官方PowerShell脚本安装...")
        command = 'powershell -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex"'
        success, output = self.run_command(command)
        
        if success:
            print("✅ UV 安装成功")
            # 刷新PATH
            self._refresh_path_environment()
            return True
        else:
            print(f"❌ PowerShell安装失败: {output}")
            return False
    
    def _install_uv_pip(self) -> bool:
        """使用pip安装"""
        print("🚀 使用pip安装...")
        command = f'"{sys.executable}" -m pip install uv --upgrade -i {PYPI_MIRROR_URL}'
        success, output = self.run_command(command)
        
        if success:
            print("✅ pip安装成功")
            return True
        else:
            print(f"❌ pip安装失败: {output}")
            return False
    
    def _install_uv_winget(self) -> bool:
        """使用winget安装"""
        print("🚀 使用winget安装...")
        success, _ = self.run_command("winget --version", check=False)
        if not success:
            print("❌ winget 不可用，请使用其他安装方法")
            return False
        
        command = "winget install astral.uv"
        success, output = self.run_command(command)
        
        if success:
            print("✅ winget安装成功")
            return True
        else:
            print(f"❌ winget安装失败: {output}")
            return False
    
    def _refresh_path_environment(self):
        """刷新PATH环境变量"""
        print("🔄 刷新环境变量...")
        # 通知系统环境变量已更改
        HWND_BROADCAST = 0xFFFF
        WM_SETTINGCHANGE = 0x001A
        ctypes.windll.user32.SendMessageW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, 'Environment')
    
    def set_environment_variables(self) -> bool:
        """设置环境变量"""
        print("\n" + "=" * 50)
        print("         配置 UV 系统环境变量")
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
        
        success_count = 0
        for var_name, var_value in self.env_vars.items():
            print(f"🔄 设置 {var_name}...")
            
            try:
                # 设置用户环境变量
                with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_WRITE) as key:
                    winreg.SetValueEx(key, var_name, 0, winreg.REG_EXPAND_SZ, var_value)
                
                # 设置当前进程环境变量
                os.environ[var_name] = var_value
                
                print(f"✅ {var_name} = {var_value}")
                success_count += 1
                
            except Exception as e:
                print(f"❌ 设置 {var_name} 失败: {e}")
        
        # 广播环境变量更改
        self._refresh_path_environment()
        
        if success_count == len(self.env_vars):
            print("\n✅ 所有环境变量设置完成")
            print("💡 部分设置可能需要重启终端或重新登录才能生效")
            return True
        else:
            print(f"⚠️  部分环境变量设置失败 ({success_count}/{len(self.env_vars)})")
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
            python_path = os.path.join(venv_path, "Scripts", "python.exe")
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
            activate_cmd = os.path.join(".venv", "Scripts", "activate")
            print(f"\n🎉 环境初始化完成！")
            print(f"🚀 激活命令: {activate_cmd}")
            print(f"📊 项目路径: {project_path}")
            
            return True
            
        except Exception as e:
            print(f"❌ 初始化失败: {e}")
            return False
        finally:
            os.chdir(original_dir)
    
    def fix_path_issues(self):
        """修复路径问题"""
        print("\n" + "=" * 50)
        print("           修复路径问题")
        print("=" * 50)
        
        print("1. 检查UV是否在PATH中")
        uv_path = shutil.which("uv")
        if uv_path:
            print(f"✅ UV 路径: {uv_path}")
        else:
            print("❌ UV 不在PATH中")
            print("💡 尝试重新安装UV或手动添加路径")
        
        print("\n2. 检查Python脚本路径")
        script_path = shutil.which("python")
        if script_path:
            print(f"✅ Python 路径: {script_path}")
        
        print("\n3. 刷新环境变量")
        self._refresh_path_environment()
        print("✅ 环境变量已刷新")
        
        print("\n💡 如果问题仍然存在，请重启终端或计算机")
    
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
                    if self.install_uv_windows():
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
                    self.fix_path_issues()
                    input("\n🔧 修复完成，按回车键返回主菜单...")
                
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
    manager = UVEnvironmentManagerWindows()
    manager.run()


if __name__ == "__main__":
    main()