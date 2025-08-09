#!/bin/bash

# CloudPose Docker构建脚本
# 使用方法: ./build.sh [tag]

set -e

# 默认标签
TAG=${1:-latest}
IMAGE_NAME="cloudpose"
REGISTRY="registry.cn-hangzhou.aliyuncs.com/cloudpose-test"

echo "🐳 开始构建CloudPose Docker镜像..."
echo "镜像名称: ${IMAGE_NAME}:${TAG}"
echo "注册表: ${REGISTRY}"

# 检查Dockerfile是否存在
if [ ! -f "Dockerfile" ]; then
    echo "❌ 错误: 找不到Dockerfile文件"
    exit 1
fi

# 检查模型文件是否存在
if [ ! -f "../model2-movenet/movenet-full-256.tflite" ]; then
    echo "❌ 错误: 找不到模型文件 ../model2-movenet/movenet-full-256.tflite"
    exit 1
fi

# 构建镜像
echo "📦 构建Docker镜像..."
docker build -t ${IMAGE_NAME}:${TAG} .

if [ $? -eq 0 ]; then
    echo "✅ 镜像构建成功: ${IMAGE_NAME}:${TAG}"
else
    echo "❌ 镜像构建失败"
    exit 1
fi

# 标记镜像用于推送到阿里云ACR
echo "🏷️  标记镜像用于推送..."
docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}

echo "📋 构建完成!"
echo "本地镜像: ${IMAGE_NAME}:${TAG}"
echo "远程镜像: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
echo ""
echo "📝 下一步操作:"
echo "1. 测试镜像: docker run -p 8000:8000 ${IMAGE_NAME}:${TAG}"
echo "2. 推送镜像: docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}"
echo "3. 使用docker-compose: docker-compose up -d"
echo ""
echo "🔍 镜像信息:"
docker images ${IMAGE_NAME}:${TAG}

# 显示镜像大小
echo ""
echo "📊 镜像大小分析:"
docker history ${IMAGE_NAME}:${TAG} --format "table {{.CreatedBy}}\t{{.Size}}"