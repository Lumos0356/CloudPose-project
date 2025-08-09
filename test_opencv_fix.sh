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
echo "=== 检查容器状态 ==="
docker-compose ps

# 检查容器是否正在运行
if ! docker-compose ps | grep -q "cloudpose-api.*Up"; then
    echo "⚠️  容器未运行，尝试启动..."
    docker-compose up -d
    echo "等待容器启动..."
    sleep 15
fi

# 再次检查容器状态
echo
echo "=== 当前容器状态 ==="
docker-compose ps

# 检查容器日志中是否还有OpenCV错误
echo
echo "=== 检查容器日志 ==="
echo "查看最近的日志..."
docker-compose logs --tail=20 cloudpose-api

# 检查是否还有libGL错误
if docker-compose logs cloudpose-api 2>&1 | grep -q "libGL.so.1"; then
    echo "❌ 仍然存在libGL.so.1错误，修复未成功"
    echo "请运行: ./fix_opencv_issue.sh 进行修复"
    exit 1
else
    echo "✅ 未发现libGL.so.1错误"
fi

# 测试API健康状态
echo
echo "=== 测试API健康状态 ==="
echo "等待API完全启动..."
sleep 10

max_attempts=6
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "尝试 $attempt/$max_attempts: 测试健康检查端点..."
    
    if curl -f -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✅ 健康检查通过！"
        
        # 获取健康检查响应
        health_response=$(curl -s http://localhost:8000/health)
        echo "健康检查响应: $health_response"
        
        # 检查模型是否加载成功
        if echo "$health_response" | grep -q '"model_loaded".*true'; then
            echo "✅ 模型加载成功！"
        else
            echo "⚠️  模型可能未正确加载"
        fi
        
        break
    else
        echo "❌ 健康检查失败 (尝试 $attempt/$max_attempts)"
        if [ $attempt -eq $max_attempts ]; then
            echo "❌ 所有健康检查尝试都失败了"
            echo "请检查容器日志: docker-compose logs cloudpose-api"
            exit 1
        fi
        echo "等待10秒后重试..."
        sleep 10
    fi
    
    attempt=$((attempt + 1))
done

# 测试姿态检测端点
echo
echo "=== 测试姿态检测端点 ==="
if curl -f -s http://localhost:8000/pose > /dev/null 2>&1; then
    echo "✅ 姿态检测端点可访问"
else
    echo "⚠️  姿态检测端点可能需要POST请求或图像数据"
fi

echo
echo "=== 验证完成 ==="
echo "🎉 CloudPose OpenCV依赖修复验证成功！"
echo
echo "服务信息:"
echo "- API地址: http://localhost:8000"
echo "- 健康检查: http://localhost:8000/health"
echo "- 姿态检测: http://localhost:8000/pose"
echo
echo "可以开始进行负载测试了！"
echo "运行负载测试: ./load_test.sh"