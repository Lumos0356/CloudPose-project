#!/bin/bash

# Kubernetes Pod 诊断脚本
# 用于诊断CloudPose Pod处于Pending状态的问题

echo "=== Kubernetes Pod 诊断报告 ==="
echo "时间: $(date)"
echo ""

# 1. 检查Pod详细状态
echo "1. 检查Pod详细状态:"
echo "kubectl describe pod cloudpose-deployment-57f7f9f48b-f9fmm"
echo ""

# 2. 检查Pod事件
echo "2. 检查Pod事件:"
echo "kubectl get events --field-selector involvedObject.name=cloudpose-deployment-57f7f9f48b-f9fmm"
echo ""

# 3. 检查节点状态
echo "3. 检查节点状态:"
echo "kubectl get nodes -o wide"
echo ""

# 4. 检查节点资源使用情况
echo "4. 检查节点资源使用情况:"
echo "kubectl top nodes"
echo ""

# 5. 检查Pod资源需求
echo "5. 检查Pod资源需求:"
echo "kubectl get pod cloudpose-deployment-57f7f9f48b-f9fmm -o yaml | grep -A 10 resources:"
echo ""

# 6. 检查Deployment状态
echo "6. 检查Deployment状态:"
echo "kubectl describe deployment cloudpose-deployment"
echo ""

# 7. 检查ReplicaSet状态
echo "7. 检查ReplicaSet状态:"
echo "kubectl describe rs cloudpose-deployment-57f7f9f48b"
echo ""

# 8. 检查镜像拉取状态
echo "8. 检查镜像拉取状态:"
echo "kubectl get pods cloudpose-deployment-57f7f9f48b-f9fmm -o jsonpath='{.status.containerStatuses[0].state}'"
echo ""

# 9. 检查调度器日志
echo "9. 检查调度器相关事件:"
echo "kubectl get events --all-namespaces | grep -i schedule"
echo ""

# 10. 检查HPA状态
echo "10. 检查HPA状态:"
echo "kubectl describe hpa cloudpose-hpa"
echo ""

# 11. 检查metrics-server状态
echo "11. 检查metrics-server状态:"
echo "kubectl get pods -n kube-system | grep metrics-server"
echo ""

# 12. 检查Service状态
echo "12. 检查Service状态:"
echo "kubectl describe service cloudpose-service"
echo ""

echo "=== 诊断脚本完成 ==="
echo ""
echo "常见解决方案:"
echo "1. 如果是资源不足: 增加节点资源或减少Pod资源需求"
echo "2. 如果是镜像拉取失败: 检查镜像名称和网络连接"
echo "3. 如果是调度失败: 检查节点标签和Pod调度约束"
echo "4. 如果是HPA问题: 安装或修复metrics-server"
echo "5. 如果是网络问题: 检查CNI插件状态"