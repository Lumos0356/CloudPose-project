#!/bin/bash

# CloudPose 修复后重新部署脚本
# 此脚本用于在修复imagePullPolicy配置后重新部署CloudPose

set -e

echo "🚀 CloudPose 修复后重新部署开始..."
echo "======================================"

# 检查kubectl是否可用
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl未安装或不在PATH中"
    exit 1
fi

# 检查Kubernetes集群连接
echo "📋 检查Kubernetes集群连接..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 无法连接到Kubernetes集群"
    exit 1
fi
echo "✅ Kubernetes集群连接正常"

# 检查k8s-deployment.yaml文件是否存在
if [ ! -f "k8s-deployment.yaml" ]; then
    echo "❌ k8s-deployment.yaml文件不存在"
    exit 1
fi

# 检查Docker镜像是否存在
echo "📋 检查Docker镜像..."
if ! docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "❌ Docker镜像 backend-cloudpose-api:latest 不存在"
    echo "请先构建镜像: docker build -t backend-cloudpose-api:latest ."
    exit 1
fi
echo "✅ Docker镜像 backend-cloudpose-api:latest 存在"

# 删除现有的CloudPose部署
echo "📋 删除现有的CloudPose部署..."
kubectl delete deployment cloudpose-deployment --ignore-not-found=true
kubectl delete service cloudpose-service --ignore-not-found=true
kubectl delete hpa cloudpose-hpa --ignore-not-found=true
kubectl delete networkpolicy cloudpose-network-policy --ignore-not-found=true
kubectl delete configmap cloudpose-config --ignore-not-found=true

echo "⏳ 等待资源清理完成..."
sleep 10

# 重新应用配置
echo "📋 重新部署CloudPose..."
kubectl apply -f k8s-deployment.yaml

echo "⏳ 等待部署完成..."
sleep 5

# 检查部署状态
echo "📋 检查部署状态..."
echo "Deployment状态:"
kubectl get deployment cloudpose-deployment

echo "\nPod状态:"
kubectl get pods -l app=cloudpose

echo "\nService状态:"
kubectl get service cloudpose-service

# 等待Pod就绪
echo "📋 等待Pod就绪..."
echo "正在等待Pod启动，这可能需要几分钟..."

# 设置超时时间（5分钟）
TIMEOUT=300
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo "❌ 超时：Pod在${TIMEOUT}秒内未能就绪"
        echo "\n当前Pod状态:"
        kubectl get pods -l app=cloudpose
        echo "\n详细Pod信息:"
        kubectl describe pods -l app=cloudpose
        exit 1
    fi
    
    # 检查Pod状态
    POD_STATUS=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    
    if [ "$POD_STATUS" = "Running" ]; then
        # 检查容器是否就绪
        READY_STATUS=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [ "$READY_STATUS" = "true" ]; then
            echo "✅ Pod已就绪！"
            break
        fi
    fi
    
    if [ "$POD_STATUS" = "Failed" ] || [ "$POD_STATUS" = "CrashLoopBackOff" ]; then
        echo "❌ Pod启动失败，状态: $POD_STATUS"
        echo "\n详细Pod信息:"
        kubectl describe pods -l app=cloudpose
        exit 1
    fi
    
    echo "⏳ Pod状态: $POD_STATUS，继续等待... (已等待${ELAPSED}秒)"
    sleep 10
done

# 最终状态检查
echo "\n📋 最终部署状态:"
echo "======================================"
echo "Deployment:"
kubectl get deployment cloudpose-deployment

echo "\nPods:"
kubectl get pods -l app=cloudpose

echo "\nServices:"
kubectl get service cloudpose-service

echo "\nHPA:"
kubectl get hpa cloudpose-hpa 2>/dev/null || echo "HPA未创建或不可用"

# 获取服务访问信息
echo "\n🌐 服务访问信息:"
echo "======================================"
SERVICE_TYPE=$(kubectl get service cloudpose-service -o jsonpath='{.spec.type}')
echo "服务类型: $SERVICE_TYPE"

if [ "$SERVICE_TYPE" = "NodePort" ]; then
    NODE_PORT=$(kubectl get service cloudpose-service -o jsonpath='{.spec.ports[0].nodePort}')
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi
    echo "访问地址: http://$NODE_IP:$NODE_PORT"
elif [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
    EXTERNAL_IP=$(kubectl get service cloudpose-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -n "$EXTERNAL_IP" ]; then
        echo "访问地址: http://$EXTERNAL_IP:8000"
    else
        echo "LoadBalancer外部IP正在分配中..."
    fi
else
    echo "ClusterIP服务，需要通过kubectl port-forward访问"
    echo "运行: kubectl port-forward service/cloudpose-service 8000:8000"
fi

# 健康检查
echo "\n🏥 健康检查:"
echo "======================================"
echo "检查Pod日志（最近20行）:"
kubectl logs -l app=cloudpose --tail=20 2>/dev/null || echo "无法获取日志"

echo "\n✅ CloudPose重新部署完成！"
echo "\n📋 后续操作建议:"
echo "1. 检查应用健康状态: kubectl get pods -l app=cloudpose"
echo "2. 查看详细日志: kubectl logs -f deployment/cloudpose-deployment"
echo "3. 测试API端点: curl http://<service-ip>:8000/health"
echo "4. 如果仍有问题，运行诊断脚本: ./diagnose_docker_image.sh"