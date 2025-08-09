#!/bin/bash

# 修复单节点Kubernetes集群的常见问题
# 主要解决master节点taint导致Pod无法调度的问题

echo "=== 修复单节点Kubernetes集群问题 ==="
echo "时间: $(date)"
echo ""

# 1. 检查节点状态
echo "1. 检查当前节点状态:"
kubectl get nodes -o wide
echo ""

# 2. 检查节点taints
echo "2. 检查节点taints:"
kubectl describe nodes | grep -A 5 "Taints:"
echo ""

# 3. 获取master节点名称
MASTER_NODE=$(kubectl get nodes --no-headers | awk '{print $1}' | head -1)
echo "3. 检测到的master节点: $MASTER_NODE"
echo ""

# 4. 移除master节点的NoSchedule taint
echo "4. 移除master节点的NoSchedule taint:"
echo "执行命令: kubectl taint nodes $MASTER_NODE node-role.kubernetes.io/control-plane:NoSchedule-"
kubectl taint nodes $MASTER_NODE node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || echo "taint可能已经被移除或不存在"
echo ""

# 5. 也尝试移除旧版本的taint
echo "5. 移除旧版本的master taint:"
echo "执行命令: kubectl taint nodes $MASTER_NODE node-role.kubernetes.io/master:NoSchedule-"
kubectl taint nodes $MASTER_NODE node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || echo "旧版本taint可能已经被移除或不存在"
echo ""

# 6. 检查修复后的节点状态
echo "6. 检查修复后的节点状态:"
kubectl describe nodes | grep -A 5 "Taints:"
echo ""

# 7. 检查Pod是否开始调度
echo "7. 等待10秒后检查Pod状态:"
sleep 10
kubectl get pods -o wide
echo ""

# 8. 检查系统Pod状态
echo "8. 检查系统Pod状态:"
kubectl get pods -n kube-system | grep -E "(coredns|flannel|kube-proxy)"
echo ""

# 9. 如果Pod仍然Pending，检查其他可能的问题
echo "9. 如果Pod仍然Pending，检查资源需求:"
kubectl describe pod cloudpose-deployment-57f7f9f48b-f9fmm | grep -A 10 "Requests:"
echo ""

# 10. 检查节点可用资源
echo "10. 检查节点可用资源:"
kubectl describe nodes | grep -A 10 "Allocated resources:"
echo ""

echo "=== 修复脚本完成 ==="
echo ""
echo "如果Pod仍然Pending，可能的原因:"
echo "1. 镜像拉取失败 - 检查网络连接和镜像名称"
echo "2. 资源不足 - 减少Pod资源需求或增加节点资源"
echo "3. 存储问题 - 检查PVC和存储类配置"
echo "4. 网络插件问题 - 检查CNI插件状态"
echo ""
echo "建议执行以下命令进一步诊断:"
echo "kubectl describe pod cloudpose-deployment-57f7f9f48b-f9fmm"
echo "kubectl get events --sort-by=.metadata.creationTimestamp"