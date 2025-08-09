# Kubernetes Worker节点配置指南

本指南详细说明如何将第二台ECS服务器配置为Kubernetes集群的Worker节点，以扩展CloudPose的部署能力。

## 📋 目录

1. [环境准备](#环境准备)
2. [系统配置](#系统配置)
3. [Docker安装](#docker安装)
4. [Kubernetes组件安装](#kubernetes组件安装)
5. [加入集群](#加入集群)
6. [验证配置](#验证配置)
7. [故障排除](#故障排除)
8. [集群管理](#集群管理)

## 🚀 环境准备

### 1. 服务器要求

**Worker节点最低配置**:
- **CPU**: 2核心
- **内存**: 4GB RAM
- **存储**: 20GB 可用空间
- **网络**: 与Master节点网络互通
- **操作系统**: Ubuntu 20.04+ 或 CentOS 7+

### 2. 网络要求

确保Worker节点能够访问Master节点的以下端口：

| 端口 | 协议 | 用途 |
|------|------|------|
| 6443 | TCP | Kubernetes API Server |
| 2379-2380 | TCP | etcd server client API |
| 10250 | TCP | Kubelet API |
| 10251 | TCP | kube-scheduler |
| 10252 | TCP | kube-controller-manager |
| 10255 | TCP | Read-only Kubelet API |

Worker节点需要开放的端口：

| 端口 | 协议 | 用途 |
|------|------|------|
| 10250 | TCP | Kubelet API |
| 30000-32767 | TCP | NodePort Services |

### 3. 主机名和DNS配置

```bash
# 设置主机名（替换为实际的主机名）
sudo hostnamectl set-hostname worker-node-1

# 更新hosts文件，添加集群节点信息
sudo tee -a /etc/hosts <<EOF
<MASTER_IP> master-node
<WORKER_IP> worker-node-1
EOF
```

## ⚙️ 系统配置

### 1. 禁用Swap

```bash
# 临时禁用swap
sudo swapoff -a

# 永久禁用swap
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 验证swap已禁用
free -h
```

### 2. 配置内核参数

```bash
# 加载必要的内核模块
sudo tee /etc/modules-load.d/k8s.conf <<EOF
br_netfilter
EOF

sudo modprobe br_netfilter

# 配置内核参数
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# 应用配置
sudo sysctl --system
```

### 3. 配置防火墙

**Ubuntu (ufw)**:
```bash
# 允许必要的端口
sudo ufw allow 10250/tcp
sudo ufw allow 30000:32767/tcp

# 允许来自Master节点的连接
sudo ufw allow from <MASTER_IP>

# 启用防火墙
sudo ufw --force enable
```

**CentOS (firewalld)**:
```bash
# 允许必要的端口
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp

# 允许来自Master节点的连接
sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='<MASTER_IP>' accept"

# 重新加载防火墙配置
sudo firewall-cmd --reload
```

## 🐳 Docker安装

### Ubuntu系统

```bash
# 更新包索引
sudo apt update

# 安装必要的包
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# 添加Docker官方GPG密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 添加Docker仓库
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新包索引
sudo apt update

# 安装Docker
sudo apt install -y docker-ce docker-ce-cli containerd.io

# 启动并启用Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 将当前用户添加到docker组
sudo usermod -aG docker $USER
```

### CentOS系统

```bash
# 安装必要的包
sudo yum install -y yum-utils device-mapper-persistent-data lvm2

# 添加Docker仓库
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 安装Docker
sudo yum install -y docker-ce docker-ce-cli containerd.io

# 启动并启用Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 将当前用户添加到docker组
sudo usermod -aG docker $USER
```

### 配置Docker

```bash
# 配置Docker daemon
sudo tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# 重启Docker服务
sudo systemctl daemon-reload
sudo systemctl restart docker

# 验证Docker安装
docker --version
sudo docker run hello-world
```

## ☸️ Kubernetes组件安装

### Ubuntu系统

```bash
# 添加Kubernetes GPG密钥
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# 添加Kubernetes仓库
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 更新包索引
sudo apt update

# 安装Kubernetes组件（指定版本以确保兼容性）
sudo apt install -y kubelet=1.28.0-00 kubeadm=1.28.0-00 kubectl=1.28.0-00

# 锁定版本，防止自动更新
sudo apt-mark hold kubelet kubeadm kubectl

# 启用kubelet服务
sudo systemctl enable kubelet
```

### CentOS系统

```bash
# 添加Kubernetes仓库
sudo tee /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# 安装Kubernetes组件
sudo yum install -y kubelet-1.28.0 kubeadm-1.28.0 kubectl-1.28.0 --disableexcludes=kubernetes

# 启用kubelet服务
sudo systemctl enable kubelet
```

## 🔗 加入集群

### 1. 在Master节点获取加入命令

在Master节点上执行以下命令获取Worker节点加入集群的命令：

```bash
# 生成加入命令
kubeadm token create --print-join-command
```

输出示例：
```bash