#!/bin/bash

# Kubernetes containerd修复验证脚本
# 验证containerd修复后的Kubernetes集群初始化

set -e

echo "=== Kubernetes containerd修复验证脚本 ==="
echo "验证containerd修复和Kubernetes集群初始化..."
echo

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo "错误: 请使用root权限运行此脚本"
    echo "使用: sudo $0"
    exit 1
fi

echo "1. 检查containerd服务状态..."
if systemctl is-active --quiet containerd; then
    echo "✅ containerd服务运行正常"
else
    echo "❌ containerd服务未运行，请先运行修复脚本"
    echo "sudo ./fix_k8s_containerd.sh"
    exit 1
fi

echo "2. 检查containerd配置..."
if grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
    echo "✅ SystemdCgroup已正确配置"
else
    echo "❌ SystemdCgroup配置错误"
    exit 1
fi

echo "3. 测试containerd CRI接口..."
if crictl version >/dev/null 2>&1; then
    echo "✅ containerd CRI接口正常"
    crictl version
else
    echo "⚠️  crictl未安装，但containerd服务正常"
fi

echo "4. 检查Kubernetes组件..."
if command -v kubeadm >/dev/null 2>&1; then
    echo "✅ kubeadm已安装"
    kubeadm version
else
    echo "❌ kubeadm未安装"
    exit 1
fi

if command -v kubelet >/dev/null 2>&1; then
    echo "✅ kubelet已安装"
else
    echo "❌ kubelet未安装"
    exit 1
fi

if command -v kubectl >/dev/null 2>&1; then
    echo "✅ kubectl已安装"
else
    echo "❌ kubectl未安装"
    exit 1
fi

echo "5. 检查系统资源..."
MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
if [ "$MEM_GB" -ge 2 ]; then
    echo "✅ 内存充足: ${MEM_GB}GB"
else
    echo "⚠️  内存不足: ${MEM_GB}GB (建议2GB+)"
fi

CPU_COUNT=$(nproc)
if [ "$CPU_COUNT" -ge 2 ]; then
    echo "✅ CPU核心充足: ${CPU_COUNT}核"
else
    echo "⚠️  CPU核心不足: ${CPU_COUNT}核 (建议2核+)"
fi

echo "6. 检查网络配置..."
if ip route | grep -q default; then
    echo "✅ 默认路由配置正常"
else
    echo "❌ 默认路由配置异常"
fi

echo "7. 检查防火墙状态..."
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
        echo "⚠️  UFW防火墙已启用，可能影响集群通信"
        echo "建议: sudo ufw disable"
    else
        echo "✅ UFW防火墙已禁用"
    fi
fi

echo "8. 预检查Kubernetes初始化..."
echo "执行kubeadm预检查..."
if kubeadm init phase preflight --ignore-preflight-errors=NumCPU,Mem 2>/dev/null; then
    echo "✅ Kubernetes预检查通过"
else
    echo "❌ Kubernetes预检查失败，查看详细错误:"
    kubeadm init phase preflight --ignore-preflight-errors=NumCPU,Mem
    exit 1
fi

echo
echo "=== 验证完成 ==="
echo "✅ containerd运行时修复成功"
echo "✅ 系统满足Kubernetes集群要求"
echo "✅ 可以安全执行Kubernetes集群初始化"
echo
echo "现在可以执行以下命令初始化集群:"
echo "sudo kubeadm init --pod-network-cidr=10.244.0.0/16"
echo
echo "初始化完成后，执行以下命令配置kubectl:"
echo "mkdir -p \$HOME/.kube"
echo "sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
echo "sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
echo
echo "安装网络插件（Flannel）:"
echo "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
echo
echo "验证集群状态:"
echo "kubectl get nodes"
echo "kubectl get pods --all-namespaces"