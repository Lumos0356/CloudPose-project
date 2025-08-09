# Kubernetes Pod Pending 问题解决方案

## 问题描述

CloudPose Pod (`cloudpose-deployment-57f7f9f48b-f9fmm`) 处于 Pending 状态超过5分钟，同时 HPA 显示 targets 为 unknown。

## 诊断步骤

### 1. 快速诊断

```bash
# 在Kubernetes集群上执行完整诊断
./run_k8s_diagnosis.sh
```

### 2. 分步诊断

#### 检查Pod状态
```bash
kubectl describe pod cloudpose-deployment-57f7f9f48b-f9fmm
kubectl get events --field-selector involvedObject.name=cloudpose-deployment-57f7f9f48b-f9fmm
```

#### 检查节点状态
```bash
kubectl get nodes -o wide
kubectl describe nodes
```

#### 检查资源使用
```bash
kubectl top nodes
kubectl top pods
```

## 常见原因及解决方案

### 1. 单节点集群调度问题 (最常见)

**问题**: Master节点默认有 NoSchedule taint，阻止Pod调度

**解决方案**:
```bash
# 执行单节点修复脚本
./fix_single_node_k8s.sh

# 或手动执行
kubectl taint nodes <master-node-name> node-role.kubernetes.io/control-plane:NoSchedule-
kubectl taint nodes <master-node-name> node-role.kubernetes.io/master:NoSchedule-
```

### 2. 镜像拉取失败

**检查方法**:
```bash
kubectl describe pod cloudpose-deployment-57f7f9f48b-f9fmm | grep -i image
```

**可能的解决方案**:
- 检查镜像名称是否正确
- 确保网络连接正常
- 如果是私有镜像，检查 imagePullSecrets
- 考虑使用本地镜像或更换镜像源

### 3. 资源不足

**检查方法**:
```bash
kubectl describe nodes | grep -A 10 "Allocated resources:"
kubectl get pod cloudpose-deployment-57f7f9f48b-f9fmm -o yaml | grep -A 10 resources:
```

**解决方案**:
- 减少Pod的资源请求
- 增加节点资源
- 添加更多节点

### 4. 存储问题

**检查方法**:
```bash
kubectl get pvc
kubectl describe pvc
```

**解决方案**:
- 检查存储类配置
- 确保有足够的存储空间
- 检查PV和PVC绑定状态

### 5. 网络插件问题

**检查方法**:
```bash
kubectl get pods -n kube-system | grep -E "(flannel|calico|weave)"
```

**解决方案**:
- 重启网络插件Pod
- 检查网络插件配置
- 确保网络插件与集群版本兼容

## HPA Metrics 问题解决

### 问题: HPA 显示 targets 为 unknown

**原因**: metrics-server 未安装或配置不正确

**解决方案**:
```bash
# 执行HPA修复脚本
./fix_hpa_metrics.sh
```

**手动安装 metrics-server**:
```bash
# 下载配置文件
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 修改配置以适应单节点集群
# 在 metrics-server deployment 的 args 中添加:
# - --kubelet-insecure-tls
# - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname

# 应用配置
kubectl apply -f components.yaml

# 等待启动
kubectl get pods -n kube-system | grep metrics-server
```

## 验证修复

### 1. 检查Pod状态
```bash
kubectl get pods -o wide
```

### 2. 检查HPA状态
```bash
kubectl get hpa
kubectl describe hpa cloudpose-hpa
```

### 3. 检查Service状态
```bash
kubectl get services
```

### 4. 测试应用访问
```bash
# 如果是NodePort服务
curl http://<node-ip>:<node-port>/health

# 如果是LoadBalancer服务
curl http://<external-ip>/health
```

## 故障排除脚本使用指南

1. **run_k8s_diagnosis.sh** - 完整的诊断报告
2. **fix_single_node_k8s.sh** - 修复单节点集群调度问题
3. **fix_hpa_metrics.sh** - 修复HPA metrics问题

## 预防措施

1. **定期监控**:
   ```bash
   kubectl get pods --all-namespaces
   kubectl get nodes
   kubectl top nodes
   ```

2. **设置资源限制**:
   - 为Pod设置合理的resource requests和limits
   - 监控集群资源使用情况

3. **备份配置**:
   - 定期备份重要的Kubernetes配置
   - 使用版本控制管理YAML文件

4. **日志监控**:
   ```bash
   kubectl logs -f deployment/cloudpose-deployment
   kubectl get events --sort-by=.metadata.creationTimestamp
   ```

## 联系支持

如果问题仍然存在，请提供以下信息：
1. `kubectl get pods -o wide` 输出
2. `kubectl describe pod <pod-name>` 输出
3. `kubectl get events` 输出
4. `kubectl get nodes -o wide` 输出
5. 集群配置信息