#!/bin/bash

# Docker镜像诊断脚本
# 用于诊断CloudPose ImagePullBackOff问题

set -e

echo "🔍 Docker镜像诊断开始..."
echo "======================================"

# 检查Docker是否运行
echo "📋 检查Docker状态..."
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker未运行或无法访问"
    exit 1
fi
echo "✅ Docker运行正常"

# 检查所有CloudPose相关镜像
echo "\n📋 检查CloudPose相关镜像..."
echo "当前所有CloudPose相关镜像:"
docker images | grep -E "(cloudpose|backend)" || echo "❌ 未找到CloudPose相关镜像"

# 检查具体的镜像
echo "\n📋 检查目标镜像 backend-cloudpose-api:latest..."
if docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "✅ 找到镜像 backend-cloudpose-api:latest"
    IMAGE_ID=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}" | grep "backend-cloudpose-api:latest" | awk '{print $2}')
    echo "   镜像ID: $IMAGE_ID"
    echo "   镜像详情:"
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}" | grep "backend-cloudpose-api:latest"
else
    echo "❌ 未找到镜像 backend-cloudpose-api:latest"
    echo "\n🔧 可能的解决方案:"
    echo "1. 重新构建镜像:"
    echo "   cd backend && docker build -t backend-cloudpose-api:latest ."
    echo "2. 或者重新标记现有镜像:"
    echo "   docker tag <现有镜像ID> backend-cloudpose-api:latest"
fi

# 检查是否有其他可能的镜像标签
echo "\n📋 检查其他可能的镜像标签..."
echo "所有包含'cloudpose'的镜像:"
docker images | grep -i cloudpose || echo "未找到包含'cloudpose'的镜像"

echo "\n所有包含'backend'的镜像:"
docker images | grep -i backend || echo "未找到包含'backend'的镜像"

# 检查最近构建的镜像
echo "\n📋 检查最近构建的镜像 (最近5个)..."
echo "最近构建的镜像:"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}" | head -6

# 检查Kubernetes配置
echo "\n📋 检查Kubernetes部署配置..."
if [ -f "k8s-deployment.yaml" ]; then
    echo "当前k8s-deployment.yaml中的镜像配置:"
    grep -n "image:" k8s-deployment.yaml || echo "未找到镜像配置"
else
    echo "❌ 未找到k8s-deployment.yaml文件"
fi

# 检查Pod状态
echo "\n📋 检查Pod状态..."
if command -v kubectl >/dev/null 2>&1; then
    echo "CloudPose Pod状态:"
    kubectl get pods -l app=cloudpose 2>/dev/null || echo "未找到CloudPose Pod"
    
    echo "\nPod详细信息:"
    kubectl describe pods -l app=cloudpose 2>/dev/null | grep -A 10 -B 5 "Image" || echo "无法获取Pod详细信息"
else
    echo "❌ kubectl未安装或不可用"
fi

# 提供修复建议
echo "\n🔧 修复建议:"
echo "======================================"

# 检查是否需要重新标记镜像
if docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "✅ 镜像存在，可能是Kubernetes配置问题"
    echo "1. 确保imagePullPolicy设置正确:"
    echo "   imagePullPolicy: IfNotPresent"
    echo "2. 重新部署:"
    echo "   kubectl delete deployment cloudpose-deployment"
    echo "   kubectl apply -f k8s-deployment.yaml"
else
    echo "❌ 镜像不存在，需要重新构建或标记"
    echo "\n选择以下方案之一:"
    echo "\n方案1: 重新构建镜像"
    echo "   cd backend"
    echo "   docker build -t backend-cloudpose-api:latest ."
    echo "\n方案2: 重新标记现有镜像"
    echo "   # 找到现有的CloudPose镜像ID"
    echo "   docker images | grep cloudpose"
    echo "   # 重新标记 (替换<IMAGE_ID>为实际的镜像ID)"
    echo "   docker tag <IMAGE_ID> backend-cloudpose-api:latest"
    echo "\n方案3: 修改k8s-deployment.yaml使用现有镜像"
    echo "   # 查看上面的镜像列表，选择一个存在的镜像"
    echo "   # 修改k8s-deployment.yaml中的image字段"
fi

echo "\n🚀 自动修复脚本:"
echo "如果需要自动修复，可以运行:"
echo "   ./fix_docker_image_tags.sh"

echo "\n✅ 诊断完成"
