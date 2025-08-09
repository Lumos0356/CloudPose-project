#!/bin/bash

# CloudPose重新部署脚本
# 用于应用修复后的k8s-deployment.yaml配置

set -e

echo "🚀 开始重新部署CloudPose..."

# 检查kubectl是否可用
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl未安装或不在PATH中"
    exit 1
fi

# 检查Kubernetes连接
echo "📡 检查Kubernetes集群连接..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 无法连接到Kubernetes集群"
    exit 1
fi

# 检查镜像是否存在
echo "🔍 检查Docker镜像..."
if ! docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "❌ 未找到backend-cloudpose-api:latest镜像"
    echo "请先运行: ./build_local_image.sh"
    exit 1
fi

echo "✅ 找到镜像: backend-cloudpose-api:latest"

# 删除现有部署（如果存在）
echo "🗑️  清理现有部署..."
kubectl delete deployment cloudpose-deployment --ignore-not-found=true
kubectl delete service cloudpose-service --ignore-not-found=true
kubectl delete hpa cloudpose-hpa --ignore-not-found=true
kubectl delete configmap cloudpose-config --ignore-not-found=true
kubectl delete secret cloudpose-secret --ignore-not-found=true
kubectl delete networkpolicy cloudpose-netpol --ignore-not-found=true

echo "⏳ 等待资源清理完成..."
sleep 10

# 应用新的部署配置
echo "📦 应用新的部署配置..."
kubectl apply -f k8s-deployment.yaml

echo "⏳ 等待部署就绪..."

# 等待部署就绪（最多5分钟）
TIMEOUT=300
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo "❌ 部署超时（${TIMEOUT}秒）"
        echo "\n📊 当前状态:"
        kubectl get pods -l app=cloudpose
        kubectl describe pods -l app=cloudpose
        exit 1
    fi
    
    # 检查部署状态
    READY_REPLICAS=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED_REPLICAS=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [ "$READY_REPLICAS" = "$DESIRED_REPLICAS" ] && [ "$READY_REPLICAS" != "0" ]; then
        echo "✅ 部署成功！"
        break
    fi
    
    echo "⏳ 等待Pod就绪... ($ELAPSED/${TIMEOUT}秒)"
    kubectl get pods -l app=cloudpose --no-headers 2>/dev/null || true
    sleep 10
done

# 检查服务状态
echo "\n📊 部署状态:"
kubectl get deployment cloudpose-deployment
kubectl get pods -l app=cloudpose
kubectl get service cloudpose-service

# 获取服务访问信息
echo "\n🌐 服务访问信息:"
NODE_PORT=$(kubectl get service cloudpose-service -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "CloudPose服务已部署完成！"
echo "访问地址: http://${NODE_IP}:${NODE_PORT}"
echo "健康检查: http://${NODE_IP}:${NODE_PORT}/health"

echo "\n🔍 如需诊断问题，请运行:"
echo "  ./quick_diagnose_k8s.sh"
echo "  ./verify_deployment.sh"

echo "\n✅ 重新部署完成！"