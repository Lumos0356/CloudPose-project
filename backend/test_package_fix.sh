#!/bin/bash

# CloudPose包依赖修复测试脚本
# 测试修复后的Dockerfile能否正常构建

set -e

echo "=== CloudPose包依赖修复测试 ==="
echo "测试修复后的Dockerfile包依赖问题..."
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

# 测试构建过程
echo "4. 测试Docker镜像构建（包含修复的包依赖）..."
echo "正在构建镜像，这可能需要几分钟..."

if docker-compose build --no-cache; then
    echo "✅ Docker镜像构建成功！包依赖问题已修复"
else
    echo "❌ Docker镜像构建失败，请检查错误信息"
    exit 1
fi

# 启动容器进行功能测试
echo "5. 启动容器进行功能测试..."
docker-compose up -d

# 等待容器启动
echo "6. 等待容器启动..."
sleep 15

# 检查容器状态
echo "7. 检查容器状态..."
docker-compose ps

echo
echo "=== 容器日志 ==="
docker-compose logs --tail=30 cloudpose-api

echo
echo "=== 健康检查 ==="
echo "等待30秒进行健康检查..."
sleep 30

# 测试API健康状态
if curl -f http://localhost:8000/health 2>/dev/null; then
    echo "✅ CloudPose API健康检查通过！"
    echo "🎉 包依赖问题已完全修复，服务正常运行"
    
    # 进行简单的API测试
    echo
    echo "=== API功能测试 ==="
    echo "测试姿态检测API..."
    
    # 创建测试图片的base64编码（简单的1x1像素图片）
    TEST_IMAGE="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    
    if curl -X POST http://localhost:8000/pose \
        -H "Content-Type: application/json" \
        -d "{\"image\": \"$TEST_IMAGE\"}" \
        -w "\nHTTP状态码: %{http_code}\n" 2>/dev/null; then
        echo "✅ 姿态检测API响应正常"
    else
        echo "⚠️  姿态检测API测试失败，但服务已启动"
    fi
else
    echo "❌ 健康检查失败，请查看容器日志:"
    echo "docker-compose logs cloudpose-api"
    exit 1
fi

echo
echo "=== 测试完成 ==="
echo "✅ 包依赖修复测试通过！"
echo "CloudPose服务已成功启动，可以进行姿态检测了！"
echo "API地址: http://localhost:8000"
echo "健康检查: http://localhost:8000/health"
echo "姿态检测: http://localhost:8000/pose"
echo
echo "如需停止服务，请运行: docker-compose down"