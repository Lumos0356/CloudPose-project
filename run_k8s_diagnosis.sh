#!/bin/bash

# 实际执行Kubernetes Pod诊断的脚本
# 在Kubernetes集群上运行以诊断CloudPose Pod问题

echo "=== Kubernetes Pod 诊断报告 ==="
echo "时间: $(date)"
echo ""

# 1. 检查Pod详细状态
echo "1. 检查Pod详细状态:"
kubectl describe pod cloudpose-deployment-57f7f9f48b-f9fmm
echo ""
echo "==========================================="
echo ""

# 2. 检查Pod事件
echo "2. 检查Pod事件:"
kubectl get events --field-selector involvedObject.name=cloudpose-deployment-57f7f9f48b-f9fmm
echo ""
echo "==========================================="
echo ""

# 3. 检查节点状态
echo "3. 检查节点状态:"
kubectl get nodes -o wide
echo ""
echo "==========================================="
echo ""

# 4. 检查节点资源使用情况
echo "4. 检查节点资源使用情况:"
kubectl top nodes 2>/dev/null || echo "metrics-server可能未安装或未就绪"
echo ""
echo "==========================================="
echo ""

# 5. 检查Pod资源需求
echo "5. 检查Pod资源需求:"
kubectl get pod cloudpose-deployment-57f7f9f48b-f9fmm -o yaml | grep -A 10 resources: || echo "Pod不存在或无法获取资源信息"
echo ""
echo "==========================================="
echo ""

# 6. 检查Deployment状态
echo "6. 检查Deployment状态:"
kubectl describe deployment cloudpose-deployment
echo ""
echo "==========================================="
echo ""

# 7. 检查ReplicaSet状态
echo "7. 检查ReplicaSet状态:"
kubectl describe rs cloudpose-deployment-57f7f9f48b
echo ""
echo "==========================================="
echo ""

# 8. 检查镜像拉取状态
echo "8. 检查镜像拉取状态:"
kubectl get pods cloudpose-deployment-57f7f9f48b-f9fmm -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null || echo "无法获取容器状态"
echo ""
echo "==========================================="
echo ""

# 9. 检查调度器相关事件
echo "9. 检查调度器相关事件:"
kubectl get events --all-namespaces | grep -i schedule
echo ""
echo "==========================================="
echo ""

# 10. 检查HPA状态
echo "10. 检查HPA状态:"
kubectl describe hpa cloudpose-hpa
echo ""
echo "==========================================="
echo ""

# 11. 检查metrics-server状态
echo "11. 检查metrics-server状态:"
kubectl get pods -n kube-system | grep metrics-server
echo ""
echo "==========================================="
echo ""

# 12. 检查Service状态
echo "12. 检查Service状态:"
kubectl describe service cloudpose-service
echo ""
echo "==========================================="
echo ""

# 13. 检查所有Pod状态
echo "13. 检查所有Pod状态:"
kubectl get pods -o wide
echo ""
echo "==========================================="
echo ""

# 14. 检查系统Pod状态
echo "14. 检查系统Pod状态:"
kubectl get pods -n kube-system
echo ""
echo "==========================================="
echo ""

echo "=== 诊断脚本完成 ==="
echo ""
echo "常见解决方案:"
echo "1. 如果是资源不足: 增加节点资源或减少Pod资源需求"
echo "2. 如果是镜像拉取失败: 检查镜像名称和网络连接"
echo "3. 如果是调度失败: 检查节点标签和Pod调度约束"
echo "4. 如果是HPA问题: 安装或修复metrics-server"
echo "5. 如果是网络问题: 检查CNI插件状态"
echo "6. 如果是单节点集群: 移除master节点的taint"