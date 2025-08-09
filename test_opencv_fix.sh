#!/bin/bash

# CloudPose OpenCV修复验证脚本
# 用于在阿里云ECS上验证OpenCV依赖修复效果

set -e

echo "=== CloudPose OpenCV修复验证脚本 ==="
echo "验证OpenCV依赖修复是否成功..."
echo

# 检查Docker和docker-compose是否可用
if ! command -v docker &> /dev/null; then
    echo "❌ Docker未安装或不可用"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose未安装或不可用"
    exit 1
fi

echo "✅ Docker环境检查通过"

# 检查是否在正确的目录
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ 请在包含docker-compose.yml的目录中运行此脚本"
    exit 1
fi

echo "✅ 项目目录检查通过"

# 检查容器状态
echo
echo "=== 检查容