# CloudPose Kubernetes 部署验证和故障排除指南

本指南提供了CloudPose在Kubernetes集群中部署的完整流程、验证方法和故障排除方案。

## 📋 目录

1. [部署前准备](#部署前准备)
2. [部署流程](#部署流程)
3. [验证部署](#验证部署)
4. [故障排除](#故障排除)
5. [常见问题](#常见问题)
6. [脚本说明](#脚本说明)
7. [集群扩展](#集群扩展)

## 🚀 部署前准备

### 1. 环境要求

- **操作系统**: Ubuntu 20.04+ 或 CentOS 7+
- **Kubernetes**: v1.20+
- **Docker**: v20.10+
- **内存**: 至少 4GB
- **CPU**: 至少 2 核心
- **存储**: 至少 20GB 可用空间

### 2. 必要工具检查

```bash
# 检查kubectl
kubectl version --client

# 检查Docker
docker --version

# 检查集群连接
kubectl cluster-info

# 检查节点状态
kubectl get nodes
```

### 3. 镜像准备

确保CloudPose Docker镜像已构建：

```bash
# 检查镜像是否存在
docker images | grep cloudpose

# 如果不存在，运行构建脚本
./build_local_image.sh
```

## 🔄 部署流程

### 方法一：使用自动部署脚本（推荐）

```bash
# 给脚本执行权限
chmod +x deploy_cloudpose_k8s.sh

# 运行部署脚本
./deploy_cloudpose_k8s.sh
```

### 方法二：手动部署

```bash
# 1. 清理旧部署（如果存在）
kubectl delete -f k8s-deployment.yaml --ignore-not-found=true

# 2. 等待资源清理
kubectl wait --for=delete pod -l app=cloudpose --timeout=60s

# 3. 应用新部署
kubectl apply -f k8s-deployment.yaml

# 4. 等待部署就绪
kubectl wait --for=condition=available --timeout=300s deployment/cloudpose-deployment
```

## ✅ 验证部署

### 1. 快速状态检查

```bash
# 运行快速诊断脚本
./quick_diagnose_k8s.sh
```

### 2. 手动验证步骤

```bash
# 检查Deployment状态
kubectl get deployment cloudpose-deployment

# 检查Pod状态
kubectl get pods -l app=cloudpose

# 检查Service状态
kubectl get service cloudpose-service

# 检查HPA状态
kubectl get hpa cloudpose-hpa

# 查看Pod日志
kubectl logs -l app=cloudpose --tail=50
```

### 3. 服务访问测试

```bash
# 获取Service信息
kubectl get service cloudpose-service

# 如果是NodePort类型，获取访问地址
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get service cloudpose-service -o jsonpath='{.spec.ports[0].nodePort}')

echo "CloudPose访问地址: http://$NODE_IP:$NODE_PORT"

# 测试健康检查端点
curl -f http://$NODE_IP:$NODE_PORT/health || echo "健康检查失败"
```

## 🔧 故障排除

### 自动故障排除

```bash
# 运行自动修复脚本
./fix_k8s_deployment_issues.sh

# 或者针对特定问题运行
./fix_k8s_deployment_issues.sh scheduling  # 修复调度问题
./fix_k8s_deployment_issues.sh image      # 修复镜像问题
./fix_k8s_deployment_issues.sh network    # 修复网络问题
```

### 手动故障排除步骤

#### 1. Pod无法调度（Pending状态）

**症状**: Pod状态为Pending

**诊断**:
```bash
kubectl describe pod <pod-name>
kubectl get events --sort-by='.lastTimestamp'
```

**解决方案**:
```bash
# 检查节点污点
kubectl describe nodes

# 移除master节点污点（单节点集群）
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule-
```

#### 2. 镜像拉取失败（ImagePullBackOff）

**症状**: Pod状态为ImagePullBackOff或ErrImagePull

**诊断**:
```bash
kubectl describe pod <pod-name>
docker images | grep cloudpose
```

**解决方案**:
```bash
# 确保镜像存在
./build_local_image.sh

# 修改镜像拉取策略
kubectl patch deployment cloudpose-deployment -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "cloudpose",
          "imagePullPolicy": "IfNotPresent"
        }]
      }
    }
  }
}'
```

#### 3. 容器启动失败（CrashLoopBackOff）

**症状**: Pod状态为CrashLoopBackOff

**诊断**:
```bash
kubectl logs <pod-name> --previous
kubectl describe pod <pod-name>
```

**解决方案**:
```bash
# 检查应用配置
kubectl get configmap cloudpose-config -o yaml

# 检查应用密钥
kubectl get secret cloudpose-secret -o yaml

# 调整健康检查参数
kubectl patch deployment cloudpose-deployment -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "cloudpose",
          "livenessProbe": {
            "initialDelaySeconds": 60,
            "periodSeconds": 30,
            "timeoutSeconds": 10,
            "failureThreshold": 5
          }
        }]
      }
    }
  }
}'
```

#### 4. 服务无法访问

**症状**: 无法通过Service访问应用

**诊断**:
```bash
kubectl get endpoints cloudpose-service
kubectl get service cloudpose-service
```

**解决方案**:
```bash
# 检查Service选择器
kubectl get service cloudpose-service -o yaml

# 检查Pod标签
kubectl get pods -l app=cloudpose --show-labels

# 如果是LoadBalancer类型，改为NodePort
kubectl patch service cloudpose-service -p '{
  "spec": {
    "type": "NodePort"
  }
}'
```

## ❓ 常见问题

### Q1: 部署脚本卡在"等待CloudPose部署就绪"？

**A**: 这通常是由于Pod调度或镜像拉取问题导致的。

**解决步骤**:
1. 按 `Ctrl+C` 中断脚本
2. 运行 `./quick_diagnose_k8s.sh` 诊断问题
3. 运行 `./fix_k8s_deployment_issues.sh` 自动修复
4. 重新运行 `./deploy_cloudpose_k8s.sh`

### Q2: 单节点集群中Pod无法调度？

**A**: 默认情况下，master节点有NoSchedule污点。

**解决方案**:
```bash
./fix_k8s_deployment_issues.sh scheduling
```

### Q3: 如何查看应用日志？

**A**: 使用以下命令查看日志：
```bash
# 查看当前日志
kubectl logs -l app=cloudpose

# 查看实时日志
kubectl logs -l app=cloudpose -f

# 查看之前容器的日志
kubectl logs <pod-name> --previous
```

### Q4: 如何重新部署应用？

**A**: 有几种方法：
```bash
# 方法1: 重新运行部署脚本
./deploy_cloudpose_k8s.sh

# 方法2: 重启Deployment
kubectl rollout restart deployment/cloudpose-deployment

# 方法3: 强制重新创建Pod
./fix_k8s_deployment_issues.sh recreate
```

### Q5: 如何扩展Pod副本数？

**A**: 使用以下命令：
```bash
# 扩展到3个副本
kubectl scale deployment cloudpose-deployment --replicas=3

# 检查扩展状态
kubectl get deployment cloudpose-deployment
```

## 📜 脚本说明

### 1. `deploy_cloudpose_k8s.sh`
- **功能**: 自动部署CloudPose到Kubernetes集群
- **特性**: 包含超时机制、详细状态检查、错误诊断
- **使用**: `./deploy_cloudpose_k8s.sh`

### 2. `quick_diagnose_k8s.sh`
- **功能**: 快速诊断Kubernetes部署问题
- **特性**: 全面的状态检查、事件分析、问题识别
- **使用**: `./quick_diagnose_k8s.sh`

### 3. `fix_k8s_deployment_issues.sh`
- **功能**: 自动修复常见的Kubernetes部署问题
- **特性**: 模块化修复、支持特定问题修复
- **使用**: 
  - `./fix_k8s_deployment_issues.sh` (修复所有问题)
  - `./fix_k8s_deployment_issues.sh scheduling` (仅修复调度问题)

### 4. `build_local_image.sh`
- **功能**: 构建CloudPose Docker镜像
- **特性**: 环境检查、构建验证
- **使用**: `./build_local_image.sh`

## 🔗 集群扩展

### 添加Worker节点

如果需要将第二台ECS服务器添加为Worker节点：

1. **在Master节点获取加入命令**:
```bash
kubeadm token create --print-join-command
```

2. **在Worker节点执行**:
```bash
# 安装Docker和kubeadm（参考初始安装步骤）
# 然后执行上面获取的join命令
sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
```

3. **验证节点加入**:
```bash
kubectl get nodes
```

### 多节点部署优化

当有多个节点时，可以优化部署配置：

```bash
# 增加副本数
kubectl scale deployment cloudpose-deployment --replicas=3

# 启用Pod反亲和性（避免所有Pod在同一节点）
kubectl patch deployment cloudpose-deployment -p '{
  "spec": {
    "template": {
      "spec": {
        "affinity": {
          "podAntiAffinity": {
            "preferredDuringSchedulingIgnoredDuringExecution": [{
              "weight": 100,
              "podAffinityTerm": {
                "labelSelector": {
                  "matchExpressions": [{
                    "key": "app",
                    "operator": "In",
                    "values": ["cloudpose"]
                  }]
                },
                "topologyKey": "kubernetes.io/hostname"
              }
            }]
          }
        }
      }
    }
  }
}'
```

## 📞 支持和帮助

如果遇到本指南未涵盖的问题：

1. **查看详细日志**:
```bash
kubectl logs -l app=cloudpose --tail=100
kubectl get events --sort-by='.lastTimestamp'
```

2. **生成诊断报告**:
```bash
./quick_diagnose_k8s.sh > diagnosis_report.txt
```

3. **检查系统资源**:
```bash
kubectl top nodes
kubectl top pods
df -h
free -h
```

---

**注意**: 本指南假设您使用的是单节点Kubernetes集群。对于生产环境，建议使用多节点集群并配置适当的资源限制、监控和备份策略。