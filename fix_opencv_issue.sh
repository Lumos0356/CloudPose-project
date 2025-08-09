#!/bin/bash

# CloudPose OpenCV依赖修复脚本
# 解决libGL.so.1库缺失问题

set -e

echo "=== CloudPose OpenCV依赖修复脚本 ==="
echo "正在修复OpenCV的libGL.so.1库缺失问题..."
echo

# 检查是否在正确的目录
if [ ! -f "docker-compose.yml" ]; then
    echo "错误: 请在包含docker-compose.yml的目录中运行此脚本"
    exit 1
fi

# 停止现有容器
echo "1. 停止现有容器..."
docker-compose down

# 删除现有镜像（强制重建）
echo "2. 删除现有镜像以强制重建..."
docker rmi cloudpose-backend:latest 2>/dev/null || echo "镜像不存在，跳过删除"

# 清理Docker缓存
echo "3. 清理Docker构建缓存..."
docker builder prune -f

# 重新构建镜像
echo "4. 重新构建CloudPose镜像（包含OpenCV依赖）..."
docker-compose build --no-cache

# 启动容器
echo "5. 启动容器..."
docker-compose up -d

# 等待容器启动
echo "6. 等待容器启动..."
sleep 10

# 检查容器状态
echo "7. 检查容器状态..."
docker-compose ps

echo
echo "=== 容器日志 ==="
docker-compose logs --tail=20 cloudpose-api

echo
echo "=== 健康检查 ==="
echo "等待30秒进行健康检查..."
sleep 30

# 测试API健康状态
if curl -f http://localhost:8000/health 2>/dev/null; then
    echo "✅ CloudPose API健康检查通过！"
    echo "🎉 OpenCV依赖问题已修复，服务正常运行"
else
    echo "❌ 健康检查失败，请查看容器日志:"
    echo "docker-compose logs cloudpose-api"
    exit 1
fi

echo
echo "=== 修复完成 ==="
echo "CloudPose服务已成功启动，可以进行姿态检测了！"
echo "API地址: http://localhost:8000"
echo "健康检查: http://localhost:8000/health"
echo "姿态检测: http://localhost:8000/pose"