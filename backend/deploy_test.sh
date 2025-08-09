#!/bin/bash

# CloudPose 部署验证脚本
# 用于测试修复后的Docker配置

set -e

echo "=== CloudPose 部署验证脚本 ==="
echo "检查必要文件是否存在..."

# 检查必要文件
required_files=(
    "../model2-movenet/movenet-full-256.tflite"
    "app.py"
    "run.py"
    "requirements.txt"
    "Dockerfile"
    "docker-compose.yml"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file 存在"
    else
        echo "✗ $file 不存在"
        exit 1
    fi
done

echo ""
echo "开始构建Docker镜像..."
docker-compose build

if [ $? -eq 0 ]; then
    echo "✓ Docker镜像构建成功"
else
    echo "✗ Docker镜像构建失败"
    exit 1
fi

echo ""
echo "启动服务..."
docker-compose up -d

if [ $? -eq 0 ]; then
    echo "✓ 服务启动成功"
else
    echo "✗ 服务启动失败"
    exit 1
fi

echo ""
echo "等待服务就绪..."
sleep 10

echo "测试健康检查接口..."
health_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health)

if [ "$health_response" = "200" ]; then
    echo "✓ 健康检查通过 (HTTP $health_response)"
else
    echo "✗ 健康检查失败 (HTTP $health_response)"
    echo "查看容器日志:"
    docker-compose logs cloudpose-api
    exit 1
fi

echo ""
echo "测试姿态检测接口..."
test_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"image_data": "test"}' \
    http://localhost:8000/pose_detection)

if [ "$test_response" = "400" ] || [ "$test_response" = "200" ]; then
    echo "✓ 姿态检测接口响应正常 (HTTP $test_response)"
else
    echo "✗ 姿态检测接口异常 (HTTP $test_response)"
fi

echo ""
echo "=== 部署验证完成 ==="
echo "服务状态:"
docker-compose ps

echo ""
echo "如需停止服务，请运行: docker-compose down"
echo "如需查看日志，请运行: docker-compose logs -f cloudpose-api"
echo "服务地址: http://localhost:8000"
echo "健康检查: http://localhost:8000/health"