#!/bin/bash

# CloudPose Docker Build Script
# Usage: ./build.sh [tag]

set -e

# Default tag
TAG=${1:-latest}
IMAGE_NAME="cloudpose"
REGISTRY="registry.cn-hangzhou.aliyuncs.com/cloudpose-test"

echo "🐳 Starting CloudPose Docker image build..."
echo "Image name: ${IMAGE_NAME}:${TAG}"
echo "Registry: ${REGISTRY}"

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo "❌ Error: Dockerfile not found"
    exit 1
fi

# Check if model file exists
if [ ! -f "../model2-movenet/movenet-full-256.tflite" ]; then
    echo "❌ Error: Model file not found ../model2-movenet/movenet-full-256.tflite"
    exit 1
fi

# Build image
echo "📦 Building Docker image..."
docker build -t ${IMAGE_NAME}:${TAG} .

if [ $? -eq 0 ]; then
    echo "✅ Image build successful: ${IMAGE_NAME}:${TAG}"
else
    echo "❌ Image build failed"
    exit 1
fi

# Tag image for pushing to Alibaba Cloud ACR
echo "🏷️  Tagging image for push..."
docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}

echo "📋 Build completed!"
echo "Local image: ${IMAGE_NAME}:${TAG}"
echo "Remote image: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
echo ""
echo "📝 Next steps:"
echo "1. Test image: docker run -p 8000:8000 ${IMAGE_NAME}:${TAG}"
echo "2. Push image: docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}"
echo "3. Use docker-compose: docker-compose up -d"
echo ""
echo "🔍 Image information:"
docker images ${IMAGE_NAME}:${TAG}

# Show image size
echo ""
echo "📊 Image size analysis:"
docker history ${IMAGE_NAME}:${TAG} --format "table {{.CreatedBy}}\t{{.Size}}"