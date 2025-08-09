# CloudPose 阿里云ECS部署指导

本指南将帮助您在阿里云ECS服务器上部署CloudPose姿态检测服务，并执行负载测试实验。

## 📋 目录

1. [环境准备](#环境准备)
2. [阿里云ACR配置](#阿里云acr配置)
3. [Docker镜像构建与推送](#docker镜像构建与推送)
4. [Kubernetes集群部署](#kubernetes集群部署)
5. [负载测试执行](#负载测试执行)
6. [实验数据收集](#实验数据收集)
7. [故障排除](#故障排除)

## 🚀 环境准备

### 1. 阿里云ECS服务器要求

**推荐配置：**
- **实例规格**: ecs.c7.large 或更高 (2 vCPU, 4 GiB)
- **操作系统**: Ubuntu 22.04 LTS 或 CentOS 8+
- **存储**: 系统盘 40GB + 数据盘 100GB
- **网络**: 专有网络VPC，公网带宽 ≥ 5Mbps
- **安全组**: 开放端口 22(SSH), 80(HTTP), 443(HTTPS), 8000(应用)

### 2. 必需软件安装

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 安装Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 安装Kubernetes工具（可选）
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 安装Python和依赖
sudo apt install -y python3 python3-pip
pip3 install locust requests

# 重新登录以应用Docker组权限
exit
```

## 🏗️ 阿里云ACR配置

### 1. 创建容器镜像服务实例

1. 登录阿里云控制台
2. 进入 **容器镜像服务ACR** → **实例列表**
3. 创建个人版实例（免费）或企业版实例
4. 记录实例地址：`registry.cn-hangzhou.aliyuncs.com`

### 2. 创建命名空间

```bash
# 在ACR控制台创建命名空间
命名空间名称: cloudpose-test
自动创建仓库: 开启
默认仓库类型: 私有
```

### 3. 配置访问凭证

```bash
# 登录阿里云ACR
docker login registry.cn-hangzhou.aliyuncs.com
# 输入阿里云账号和密码
```

## 🐳 Docker镜像构建与推送

### 1. 准备项目文件

```bash
# 克隆或上传项目到ECS服务器
git clone <your-repo-url> cloudpose
cd cloudpose

# 或者使用scp上传
# scp -r /local/path/to/client root@your-ecs-ip:/root/cloudpose
```

### 2. 构建和推送镜像

```bash
cd backend

# 确保build.sh有执行权限
chmod +x build.sh

# 构建镜像
./build.sh latest

# 推送到阿里云ACR
docker push registry.cn-hangzhou.aliyuncs.com/cloudpose-test/cloudpose:latest

# 验证推送成功
docker images | grep cloudpose
```

### 3. 测试镜像

```bash
# 本地测试运行
docker run -d -p 8000:8000 --name cloudpose-test \
  registry.cn-hangzhou.aliyuncs.com/cloudpose-test/cloudpose:latest

# 健康检查
curl http://localhost:8000/health

# 停止测试容器
docker stop cloudpose-test && docker rm cloudpose-test
```

## ☸️ Kubernetes集群部署

### 选项A: 使用阿里云容器服务ACK

#### 1. 创建ACK集群

1. 登录阿里云控制台
2. 进入 **容器服务Kubernetes版** → **集群**
3. 创建托管版Kubernetes集群
   - **集群名称**: cloudpose-cluster
   - **Kubernetes版本**: 1.24+
   - **节点规格**: ecs.c7.large (2核4G) × 3台
   - **网络插件**: Flannel
   - **服务网段**: 172.21.0.0/20

#### 2. 配置kubectl访问

```bash
# 下载集群kubeconfig
# 在ACK控制台 → 集群信息 → 连接信息 → 复制kubeconfig

mkdir -p ~/.kube
vi ~/.kube/config
# 粘贴kubeconfig内容

# 验证连接
kubectl get nodes
```

#### 3. 创建镜像拉取密钥

```bash
# 创建ACR访问密钥
kubectl create secret docker-registry aliyun-acr-secret \
  --docker-server=registry.cn-hangzhou.aliyuncs.com \
  --docker-username=<your-aliyun-username> \
  --docker-password=<your-aliyun-password> \
  --docker-email=<your-email>
```

#### 4. 部署应用

```bash
# 部署CloudPose服务
kubectl apply -f k8s-deployment.yaml

# 检查部署状态
kubectl get pods -l app=cloudpose
kubectl get svc cloudpose-service

# 获取外部访问地址
kubectl get svc cloudpose-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 选项B: 自建Kubernetes集群

#### 1. 安装kubeadm

```bash
# 安装kubeadm, kubelet, kubectl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

#### 2. 初始化集群

```bash
# 初始化master节点
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# 配置kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 安装网络插件
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# 允许master节点调度Pod（单节点集群）
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### 选项C: 使用Docker Compose（简化部署）

```bash
# 使用docker-compose部署
cd backend
docker-compose up -d

# 检查服务状态
docker-compose ps
docker-compose logs cloudpose

# 健康检查
curl http://localhost:8000/health
```

## 🧪 负载测试执行

### 1. 准备测试环境

```bash
# 返回项目根目录
cd /root/cloudpose

# 准备测试图像
python3 prepare_test_images.py

# 验证测试图像
ls -la test_images/ | wc -l  # 应该显示128个图像文件
```

### 2. 获取服务访问地址

```bash
# Kubernetes部署
SERVICE_IP=$(kubectl get svc cloudpose-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Service URL: http://$SERVICE_IP"

# Docker Compose部署
echo "Service URL: http://localhost:8000"

# 验证服务可访问
curl http://$SERVICE_IP/health
```

### 3. 执行负载测试实验

#### 方法A: 自动化实验脚本

```bash
# 修改实验脚本中的服务地址
vi run_experiments.py
# 更新 BASE_URL = "http://your-service-ip"

# 执行完整实验（1, 2, 4, 8 pods）
python3 run_experiments.py --mode kubernetes --base-url http://$SERVICE_IP

# 查看实验结果
ls -la experiment_results_*
```

#### 方法B: 手动执行单个测试

```bash
# 测试1个Pod
kubectl scale deployment cloudpose-deployment --replicas=1
kubectl wait --for=condition=ready pod -l app=cloudpose --timeout=300s

# 执行负载测试
locust -f locustfile.py --host=http://$SERVICE_IP \
  --users=50 --spawn-rate=5 --run-time=300s --html=report_1pod.html

# 测试2个Pod
kubectl scale deployment cloudpose-deployment --replicas=2
kubectl wait --for=condition=ready pod -l app=cloudpose --timeout=300s
locust -f locustfile.py --host=http://$SERVICE_IP \
  --users=100 --spawn-rate=10 --run-time=300s --html=report_2pods.html

# 测试4个Pod
kubectl scale deployment cloudpose-deployment --replicas=4
kubectl wait --for=condition=ready pod -l app=cloudpose --timeout=300s
locust -f locustfile.py --host=http://$SERVICE_IP \
  --users=200 --spawn-rate=20 --run-time=300s --html=report_4pods.html

# 测试8个Pod
kubectl scale deployment cloudpose-deployment --replicas=8
kubectl wait --for=condition=ready pod -l app=cloudpose --timeout=300s
locust -f locustfile.py --host=http://$SERVICE_IP \
  --users=400 --spawn-rate=40 --run-time=300s --html=report_8pods.html
```

### 4. 监控和数据收集

```bash
# 实时监控Pod状态
watch kubectl get pods -l app=cloudpose

# 查看Pod资源使用
kubectl top pods -l app=cloudpose

# 查看服务日志
kubectl logs -l app=cloudpose --tail=100 -f

# 查看集群资源使用
kubectl top nodes
```

## 📊 实验数据收集

### 1. 收集测试报告

```bash
# 下载HTML报告到本地
scp root@your-ecs-ip:/root/cloudpose/report_*.html ./
scp root@your-ecs-ip:/root/cloudpose/experiment_results_*.json ./
```

### 2. 生成实验报告

```bash
# 使用实验报告模板
cp experiment_report_template.md my_experiment_report.md

# 编辑报告，填入实验数据
vi my_experiment_report.md
```

### 3. 关键指标提取

```bash
# 从Locust结果中提取关键指标
python3 -c "
import json
with open('experiment_results_1_pods.json') as f:
    data = json.load(f)
    print(f'平均响应时间: {data["stats"][0]["avg_response_time"]}ms')
    print(f'最大响应时间: {data["stats"][0]["max_response_time"]}ms')
    print(f'请求成功率: {data["stats"][0]["num_requests"] - data["stats"][0]["num_failures"]} / {data["stats"][0]["num_requests"]}')
    print(f'吞吐量: {data["stats"][0]["current_rps"]} RPS')
"
```

## 🔧 故障排除

### 常见问题解决

#### 1. 镜像拉取失败

```bash
# 检查ACR登录状态
docker login registry.cn-hangzhou.aliyuncs.com

# 验证镜像存在
docker pull registry.cn-hangzhou.aliyuncs.com/cloudpose-test/cloudpose:latest

# 检查Kubernetes密钥
kubectl get secret aliyun-acr-secret -o yaml
```

#### 2. Pod启动失败

```bash
# 查看Pod详细信息
kubectl describe pod <pod-name>

# 查看Pod日志
kubectl logs <pod-name>

# 检查资源限制
kubectl top pods
kubectl describe nodes
```

#### 3. 服务无法访问

```bash
# 检查Service状态
kubectl get svc cloudpose-service -o wide

# 检查Endpoints
kubectl get endpoints cloudpose-service

# 检查安全组规则
# 确保ECS安全组开放了80端口
```

#### 4. 负载测试连接失败

```bash
# 检查网络连通性
ping $SERVICE_IP
telnet $SERVICE_IP 80

# 检查防火墙
sudo ufw status
sudo iptables -L

# 检查服务健康状态
curl -v http://$SERVICE_IP/health
```

#### 5. Kubernetes集群初始化失败

**问题**: 执行`kubeadm init`时出现containerd运行时错误

```
[ERROR CRI]: container runtime is not running: output: time="2025-08-10T01:10:28+08:00" level=fatal msg="validate service connection: CRI v1 runtime API is not implemented for endpoint \"unix:///var/run/containerd/containerd.sock\": rpc error: code = Unimplemented desc = unknown service runtime.v1.RuntimeService"
```

**解决方案**: 使用containerd修复脚本

```bash
# 下载并运行containerd修复脚本
wget https://raw.githubusercontent.com/your-repo/CloudPose/main/backend/fix_k8s_containerd.sh
chmod +x fix_k8s_containerd.sh
sudo ./fix_k8s_containerd.sh

# 或者手动修复containerd配置
sudo systemctl stop containerd
sudo mkdir -p /etc/containerd
sudo containerd config default > /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl start containerd

# 重置并重新初始化Kubernetes
sudo kubeadm reset -f
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

**验证修复**:

```bash
# 检查containerd服务状态
sudo systemctl status containerd

# 测试CRI接口
sudo crictl version

# 检查containerd配置
sudo cat /etc/containerd/config.toml | grep SystemdCgroup
```

**常见containerd问题**:

1. **SystemdCgroup未启用**: 确保配置文件中`SystemdCgroup = true`
2. **配置文件损坏**: 重新生成默认配置文件
3. **服务未启动**: 检查systemd服务状态和日志
4. **权限问题**: 确保以root权限运行修复脚本

```bash
# 查看containerd详细日志
sudo journalctl -u containerd -f

# 查看kubelet日志
sudo journalctl -u kubelet -f
```

### 性能调优建议

#### 1. 容器资源优化

```yaml
# 在k8s-deployment.yaml中调整资源限制
resources:
  requests:
    memory: "1Gi"
    cpu: "1"
  limits:
    memory: "2Gi"
    cpu: "2"
```

#### 2. 网络优化

```bash
# 优化网络参数
echo 'net.core.somaxconn = 65535' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_max_syn_backlog = 65535' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

#### 3. 存储优化

```bash
# 使用SSD存储
# 在阿里云控制台选择ESSD云盘

# 优化Docker存储驱动
sudo vi /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
sudo systemctl restart docker
```

## 📝 实验检查清单

- [ ] ECS服务器配置满足要求
- [ ] Docker和Kubernetes环境正常
- [ ] 阿里云ACR配置完成
- [ ] CloudPose镜像构建并推送成功
- [ ] Kubernetes集群部署成功
- [ ] 服务健康检查通过
- [ ] 测试图像准备完成（128张）
- [ ] 负载测试脚本配置正确
- [ ] 1, 2, 4, 8 Pod扩展测试完成
- [ ] 实验数据收集完整
- [ ] 实验报告撰写完成

## 🎯 下一步操作

1. **完成实验**: 按照本指南执行完整的负载测试实验
2. **数据分析**: 分析不同Pod数量下的性能表现
3. **报告撰写**: 使用模板撰写详细的实验报告
4. **优化建议**: 基于实验结果提出系统优化建议
5. **清理资源**: 实验完成后清理阿里云资源以避免费用

```bash
# 清理Kubernetes资源
kubectl delete -f k8s-deployment.yaml

# 清理Docker资源
docker system prune -a

# 删除ACR镜像（可选）
# 在阿里云控制台手动删除
```

---

**注意**: 请根据实际的阿里云账号信息和网络环境调整配置参数。如遇到问题，请参考故障排除部分或联系技术支持。