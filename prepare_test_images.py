#!/usr/bin/env python3
"""
测试图像准备脚本
从inputfolder目录复制128个图像到test_images目录，用于Locust负载测试

使用方法:
    python prepare_test_images.py
"""

import os
import shutil
import sys
from pathlib import Path

def prepare_test_images():
    """准备测试图像"""
    
    # 源目录和目标目录
    source_dir = Path("inputfolder")
    target_dir = Path("test_images")
    
    print("CloudPose 测试图像准备脚本")
    print("=" * 50)
    
    # 检查源目录是否存在
    if not source_dir.exists():
        print(f"错误: 源目录 '{source_dir}' 不存在!")
        print("请确保 inputfolder 目录存在并包含测试图像。")
        return False
    
    # 获取所有图像文件
    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.webp'}
    image_files = []
    
    for file_path in source_dir.iterdir():
        if file_path.is_file() and file_path.suffix.lower() in image_extensions:
            image_files.append(file_path)
    
    if not image_files:
        print(f"错误: 在 '{source_dir}' 目录中没有找到图像文件!")
        print(f"支持的图像格式: {', '.join(image_extensions)}")
        return False
    
    print(f"在 '{source_dir}' 中找到 {len(image_files)} 个图像文件")
    
    # 限制为128个图像
    max_images = 128
    selected_images = image_files[:max_images]
    
    print(f"选择前 {len(selected_images)} 个图像进行测试")
    
    # 创建目标目录
    if target_dir.exists():
        print(f"目标目录 '{target_dir}' 已存在，清空中...")
        shutil.rmtree(target_dir)
    
    target_dir.mkdir(exist_ok=True)
    print(f"创建目标目录: {target_dir}")
    
    # 复制图像文件
    copied_count = 0
    failed_count = 0
    
    print("\n开始复制图像文件...")
    
    for i, source_file in enumerate(selected_images, 1):
        try:
            # 生成目标文件名（保持原始文件名）
            target_file = target_dir / source_file.name
            
            # 复制文件
            shutil.copy2(source_file, target_file)
            copied_count += 1
            
            # 显示进度
            if i % 10 == 0 or i == len(selected_images):
                print(f"进度: {i}/{len(selected_images)} ({i/len(selected_images)*100:.1f}%)")
                
        except Exception as e:
            print(f"复制文件失败 {source_file.name}: {e}")
            failed_count += 1
    
    print("\n复制完成!")
    print(f"成功复制: {copied_count} 个文件")
    if failed_count > 0:
        print(f"复制失败: {failed_count} 个文件")
    
    # 验证结果
    actual_files = list(target_dir.glob("*"))
    print(f"目标目录中实际文件数: {len(actual_files)}")
    
    # 显示文件大小统计
    total_size = sum(f.stat().st_size for f in actual_files if f.is_file())
    avg_size = total_size / len(actual_files) if actual_files else 0
    
    print(f"总文件大小: {total_size / (1024*1024):.2f} MB")
    print(f"平均文件大小: {avg_size / 1024:.2f} KB")
    
    print("\n测试图像准备完成!")
    print(f"现在可以运行负载测试: locust -f locustfile.py --host=http://localhost:8000")
    
    return True

def verify_test_images():
    """验证测试图像目录"""
    target_dir = Path("test_images")
    
    if not target_dir.exists():
        print(f"测试图像目录 '{target_dir}' 不存在")
        return False
    
    image_files = list(target_dir.glob("*"))
    print(f"测试图像目录包含 {len(image_files)} 个文件")
    
    # 检查前几个文件
    for i, file_path in enumerate(image_files[:5]):
        size = file_path.stat().st_size
        print(f"  {file_path.name}: {size/1024:.2f} KB")
    
    if len(image_files) > 5:
        print(f"  ... 还有 {len(image_files)-5} 个文件")
    
    return len(image_files) > 0

def clean_test_images():
    """清理测试图像目录"""
    target_dir = Path("test_images")
    
    if target_dir.exists():
        print(f"删除测试图像目录: {target_dir}")
        shutil.rmtree(target_dir)
        print("清理完成")
    else:
        print(f"测试图像目录 '{target_dir}' 不存在")

def main():
    """主函数"""
    if len(sys.argv) > 1:
        command = sys.argv[1].lower()
        
        if command == "verify":
            verify_test_images()
        elif command == "clean":
            clean_test_images()
        elif command == "help":
            print("使用方法:")
            print("  python prepare_test_images.py        # 准备测试图像")
            print("  python prepare_test_images.py verify # 验证测试图像")
            print("  python prepare_test_images.py clean  # 清理测试图像")
            print("  python prepare_test_images.py help   # 显示帮助")
        else:
            print(f"未知命令: {command}")
            print("使用 'python prepare_test_images.py help' 查看帮助")
    else:
        # 默认操作：准备测试图像
        success = prepare_test_images()
        if not success:
            sys.exit(1)

if __name__ == "__main__":
    main()