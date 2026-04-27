import os

def 生成目录结构(输出文件名='目录结构.md'):
    # 获取当前脚本所在的绝对路径
    当前路径 = os.path.dirname(os.path.abspath(__file__))
    脚本名称 = os.path.basename(__file__)
    
    try:
        with open(os.path.join(当前路径, 输出文件名), 'w', encoding='utf-8') as f:
            f.write(f"# 目录结构视图\n\n- **生成路径**: `{当前路径}`\n\n```text\n")
            
            # 使用 os.walk 遍历目录
            for 根目录, 子目录列表, 文件列表 in os.walk(当前路径):
                # 排序确保输出整齐（按字母顺序）
                子目录列表.sort()
                文件列表.sort()
                
                # 计算相对路径以确定缩进层级
                相对路径 = os.path.relpath(根目录, 当前路径)
                
                if 相对路径 == ".":
                    f.write(f". (根目录)\n")
                    层级 = 0
                else:
                    层级 = 相对路径.count(os.sep) + 1
                    缩进 = '│   ' * (层级 - 1)
                    f.write(f"{缩进}├── {os.path.basename(根目录)}/\n")
                
                # 设置文件缩进
                文件缩进 = '│   ' * 层级
                
                # 遍历并写入文件
                for 文件名 in 文件列表:
                    # 排除脚本自身和生成的输出文件
                    if 文件名 != 脚本名称 and 文件名 != 输出文件名:
                        f.write(f"{文件缩进}└── {文件名}\n")
            
            f.write("```\n")
        print(f"生成成功！请查看文件: {输出文件名}")
        
    except Exception as e:
        print(f"发生错误: {e}")

if __name__ == "__main__":
    生成目录结构()
