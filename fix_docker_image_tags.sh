#!/bin/bash

# Docker镜像标签修复脚本
# 自动修复CloudPose ImagePullBackOff问题

set -e

echo "🔧 Docker镜像标签修复开始..."
echo "======================================"

# 检查Docker是否运行
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker未运行或无法访问"
    exit 1
fi

# 目标镜像名称
TARGET_IMAGE="backend-cloudpose-api:latest"

# 检查目标镜像是否存在
echo "📋 检查目标镜像 $TARGET_IMAGE..."
if docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "✅ 目标镜像已存在"
    docker images | grep "backend-cloudpose-api.*latest"
else
    echo "❌ 目标镜像不存在，开始修复..."
    
    # 查找可能的CloudPose镜像
    echo "\n🔍 查找可能的CloudPose镜像..."
    
    # 方案1: 查找包含cloudpose的镜像
    CLOUDPOSE_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i cloudpose || true)
    if [ ! -z "$CLOUDPOSE_IMAGES" ]; then
        echo "找到CloudPose相关镜像:"
        echo "$CLOUDPOSE_IMAGES"
        
        # 选择第一个镜像进行标记
        FIRST_IMAGE=$(echo "$CLOUDPOSE_IMAGES" | head -1)
        echo "\n🏷️  使用镜像 $FIRST_IMAGE 创建标签 $TARGET_IMAGE"
        docker tag "$FIRST_IMAGE" "$TARGET_IMAGE"
        echo "✅ 镜像标签创建成功"
    else
        # 方案2: 查找包含backend的镜像
        BACKEND_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i backend || true)
        if [ ! -z "$BACKEND_IMAGES" ]; then
            echo "找到Backend相关镜像:"
            echo "$BACKEND_IMAGES"
            
            # 选择第一个镜像进行标记
            FIRST_IMAGE=$(echo "$BACKEND_IMAGES" | head -1)
            echo "\n🏷️  使用镜像 $FIRST_IMAGE 创建标签 $TARGET_IMAGE"
            docker tag "$FIRST_IMAGE" "$TARGET_IMAGE"
            echo "✅ 镜像标签创建成功"
        else
            # 方案3: 重新构建镜像
            echo "\n❌ 未找到可用的镜像，尝试重新构建..."
            if [ -d "backend" ] && [ -f "backend/Dockerfile" ]; then
                echo "🔨 开始构建镜像..."
                cd backend
                docker build -t "$TARGET_IMAGE" .
                cd ..
                echo "✅ 镜像构建成功"
            else
                echo "❌ 未找到backend目录或Dockerfile"
                echo "请手动构建镜像或检查项目结构"
                exit 1
            fi
        fi
    fi
fi

# 验证镜像是否存在
echo "\n📋 验证镜像状态..."
if docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "✅ 目标镜像验证成功"
    docker images | grep "backend-cloudpose-api.*latest"
else
    echo "❌ 镜像验证失败"
    exit 1
fi

# 检查k8s-deployment.yaml配置
echo "\n📋 检查Kubernetes配置..."
if [ -f "k8s-deployment.yaml" ]; then
    if grep -q "image: backend-cloudpose-api:latest" k8s-deployment.yaml; then
        echo "✅ k8s-deployment.yaml配置正确"
    else
        echo "🔧 修复k8s-deployment.yaml配置..."
        # 备份原文件
        cp k8s-deployment.yaml k8s-deployment.yaml.backup
        
        # 替换镜像配置
        sed -i.bak 's|image: .*cloudpose.*|image: backend-cloudpose-api:latest|g' k8s-deployment.yaml
        sed -i.bak 's|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|g' k8s-deployment.yaml
        
        echo "✅ k8s-deployment.yaml配置已修复"
        echo "当前镜像配置:"
        grep -n "image:" k8s-deployment.yaml
    fi
else
    echo "❌ 未找到k8s-deployment.yaml文件"
fi

# 重新部署到Kubernetes
echo "\n🚀 重新部署到Kubernetes..."
if command -v kubectl >/dev/null 2>&1; then
    # 删除现有部署
    echo "删除现有部署..."
    kubectl delete deployment cloudpose-deployment --ignore-not-found=true
    
    # 等待删除完成
    echo "等待删除完成..."
    sleep 5
    
    # 重新部署
    echo "重新部署..."
    kubectl apply -f k8s-deployment.yaml
    
    echo "\n⏳ 等待Pod启动..."
    sleep 10
    
    # 检查部署状态
    echo "\n📋 检查部署状态..."
    kubectl get pods -l app=cloudpose
    
    # 检查Pod详细状态
    POD_NAME=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ ! -z "$POD_NAME" ]; then
        echo "\nPod详细状态:"
        kubectl describe pod "$POD_NAME" | grep -A 5 -B 5 "Image"
        
        # 检查Pod状态
        POD_STATUS=$(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$POD_STATUS" = "Running" ]; then
            echo "\n✅ Pod运行成功！"
        else
            echo "\n⚠️  Pod状态: $POD_STATUS"
            echo "如果仍有问题，请运行: kubectl describe pod $POD_NAME"
        fi
    fi
else
    echo "❌ kubectl未安装，无法重新部署"
    echo "请手动运行: kubectl apply -f k8s-deployment.yaml"
fi

echo "\n✅ 修复完成"
echo "======================================"
echo "如果仍有问题，请检查:"
echo "1. Docker镜像是否正确构建"
echo "2. Kubernetes配置是否正确"
echo "3. 运行诊断脚本: ./diagnose_docker_image.sh"