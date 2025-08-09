#!/bin/bash

# CloudPose 深度镜像诊断脚本
# 用于诊断 backend-cloudpose-api:latest 镜像问题

echo "=== CloudPose 深度镜像诊断 ==="
echo "时间: $(date)"
echo

# 1. 检查 Docker 服务状态
echo "1. 检查 Docker 服务状态..."
if ! systemctl is-active --quiet docker; then
    echo "❌ Docker 服务未运行"
    echo "尝试启动 Docker 服务..."
    sudo systemctl start docker
    sleep 3
else
    echo "✅ Docker 服务正在运行"
fi
echo

# 2. 检查 Docker 镜像列表
echo "2. 检查所有 Docker 镜像..."
docker images
echo

# 3. 专门检查目标镜像
echo "3. 检查目标镜像 backend-cloudpose-api:latest..."
if docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "✅ 找到镜像 backend-cloudpose-api:latest"
    docker images | grep "backend-cloudpose-api.*latest"
else
    echo "❌ 未找到镜像 backend-cloudpose-api:latest"
fi
echo

# 4. 检查所有相关镜像
echo "4. 检查所有 CloudPose 相关镜像..."
echo "包含 'cloudpose' 的镜像:"
docker images | grep -i cloudpose || echo "未找到包含 cloudpose 的镜像"
echo
echo "包含 'backend' 的镜像:"
docker images | grep -i backend || echo "未找到包含 backend 的镜像"
echo

# 5. 检查镜像详细信息
echo "5. 检查镜像详细信息..."
if docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "镜像详细信息:"
    docker inspect backend-cloudpose-api:latest | jq '.[] | {Id: .Id, Created: .Created, Size: .Size, Architecture: .Architecture, Os: .Os}' 2>/dev/null || docker inspect backend-cloudpose-api:latest | grep -E '"Id"|"Created"|"Size"|"Architecture"|"Os"'
else
    echo "无法检查镜像详细信息，镜像不存在"
fi
echo

# 6. 检查 Kubernetes 节点
echo "6. 检查 Kubernetes 节点状态..."
kubectl get nodes -o wide
echo

# 7. 检查当前 Pod 状态
echo "7. 检查 CloudPose Pod 状态..."
kubectl get pods -l app=cloudpose -o wide
echo

# 8. 检查 Pod 事件
echo "8. 检查 Pod 事件..."
kubectl describe pods -l app=cloudpose | grep -A 10 -B 5 "Events:"
echo

# 9. 检查 Docker 守护进程配置
echo "9. 检查 Docker 守护进程配置..."
echo "Docker 版本:"
docker version
echo
echo "Docker 信息:"
docker info | grep -E "Server Version|Storage Driver|Logging Driver|Cgroup Driver|Kernel Version"
echo

# 10. 检查磁盘空间
echo "10. 检查磁盘空间..."
df -h /var/lib/docker
echo

# 11. 尝试手动拉取镜像（如果不存在）
echo "11. 镜像存在性测试..."
if ! docker images | grep -q "backend-cloudpose-api.*latest"; then
    echo "❌ 镜像不存在，需要重新构建"
    echo "建议执行以下命令重新构建镜像:"
    echo "cd /root/CloudPose-project/backend"
    echo "docker build -t backend-cloudpose-api:latest ."
else
    echo "✅ 镜像存在，测试镜像是否可用"
    echo "尝试运行镜像测试..."
    docker run --rm backend-cloudpose-api:latest echo "镜像测试成功" || echo "❌ 镜像运行失败"
fi
echo

# 12. 检查 containerd 状态（如果使用）
echo "12. 检查容器运行时状态..."
if command -v crictl &> /dev/null; then
    echo "检查 crictl 镜像:"
    crictl images | grep -i cloudpose || echo "crictl 中未找到 cloudpose 镜像"
else
    echo "crictl 未安装或不可用"
fi
echo

echo "=== 诊断完成 ==="
echo "请检查上述输出，特别关注:"
echo "1. Docker 镜像是否真的存在"
echo "2. 镜像的架构和操作系统是否匹配"
echo "3. Kubernetes 节点状态是否正常"
echo "4. Pod 事件中的具体错误信息"
echo
echo "如果镜像不存在，请运行以下命令重新构建:"
echo "cd /root/CloudPose-project/backend && docker build -t backend-cloudpose-api:latest ."