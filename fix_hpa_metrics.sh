#!/bin/bash

# 修复HPA metrics问题的脚本
# 安装和配置metrics-server以解决HPA显示targets为unknown的问题

echo "=== 修复HPA Metrics问题 ==="
echo "时间: $(date)"
echo ""

# 1. 检查当前HPA状态
echo "1. 检查当前HPA状态:"
kubectl get hpa
echo ""
kubectl describe hpa cloudpose-hpa
echo ""
echo "==========================================="
echo ""

# 2. 检查metrics-server是否存在
echo "2. 检查metrics-server状态:"
kubectl get pods -n kube-system | grep metrics-server
echo ""
echo "==========================================="
echo ""

# 3. 如果metrics-server不存在，安装它
echo "3. 安装metrics-server:"
echo "下载metrics-server配置文件..."
wget -q https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -O metrics-server.yaml

if [ $? -eq 0 ]; then
    echo "成功下载metrics-server配置文件"
    
    # 修改配置以适应单节点集群和自签名证书
    echo "修改metrics-server配置以适应单节点集群..."
    
    # 备份原文件
    cp metrics-server.yaml metrics-server.yaml.backup
    
    # 添加--kubelet-insecure-tls参数
    sed -i 's/- --cert-dir=\/tmp/- --cert-dir=\/tmp\n        - --kubelet-insecure-tls/' metrics-server.yaml
    
    # 添加--kubelet-preferred-address-types参数
    sed -i 's/- --kubelet-insecure-tls/- --kubelet-insecure-tls\n        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname/' metrics-server.yaml
    
    echo "应用metrics-server配置..."
    kubectl apply -f metrics-server.yaml
    
    echo "等待metrics-server启动..."
    sleep 30
    
    echo "检查metrics-server Pod状态:"
    kubectl get pods -n kube-system | grep metrics-server
    
else
    echo "下载失败，尝试使用curl..."
    curl -L https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -o metrics-server.yaml
    
    if [ $? -eq 0 ]; then
        echo "使用curl成功下载"
        # 同样的修改步骤
        cp metrics-server.yaml metrics-server.yaml.backup
        sed -i 's/- --cert-dir=\/tmp/- --cert-dir=\/tmp\n        - --kubelet-insecure-tls/' metrics-server.yaml
        sed -i 's/- --kubelet-insecure-tls/- --kubelet-insecure-tls\n        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname/' metrics-server.yaml
        kubectl apply -f metrics-server.yaml
        sleep 30
        kubectl get pods -n kube-system | grep metrics-server
    else
        echo "无法下载metrics-server配置文件，请检查网络连接"
        echo "手动安装命令:"
        echo "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
fi

echo ""
echo "==========================================="
echo ""

# 4. 等待metrics-server就绪
echo "4. 等待metrics-server就绪:"
echo "等待60秒让metrics-server完全启动..."
sleep 60

# 5. 检查metrics-server日志
echo "5. 检查metrics-server日志:"
METRICS_POD=$(kubectl get pods -n kube-system | grep metrics-server | awk '{print $1}')
if [ ! -z "$METRICS_POD" ]; then
    echo "Metrics-server Pod: $METRICS_POD"
    kubectl logs -n kube-system $METRICS_POD --tail=20
else
    echo "未找到metrics-server Pod"
fi
echo ""
echo "==========================================="
echo ""

# 6. 测试metrics API
echo "6. 测试metrics API:"
echo "测试节点metrics:"
kubectl top nodes
echo ""
echo "测试Pod metrics:"
kubectl top pods
echo ""
echo "==========================================="
echo ""

# 7. 检查修复后的HPA状态
echo "7. 检查修复后的HPA状态:"
kubectl get hpa
echo ""
kubectl describe hpa cloudpose-hpa
echo ""

echo "=== HPA Metrics修复脚本完成 ==="
echo ""
echo "如果HPA仍然显示unknown，可能的原因:"
echo "1. Pod还未启动 - 等待Pod运行后HPA才能获取metrics"
echo "2. 应用未暴露metrics端点 - 检查应用是否正确配置"
echo "3. metrics-server需要更多时间 - 等待几分钟后重新检查"
echo "4. 资源请求未设置 - HPA需要Pod设置resource requests"
echo ""
echo "手动检查命令:"
echo "kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes"
echo "kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods"