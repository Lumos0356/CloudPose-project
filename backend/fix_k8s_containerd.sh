#!/bin/bash

# Kubernetes containerd运行时修复脚本
# 解决kubeadm init时的containerd CRI错误

set -e

echo "=== Kubernetes containerd运行时修复脚本 ==="
echo "正在修复containerd CRI运行时错误..."
echo

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo "错误: 请使用root权限运行此脚本"
    echo "使用: sudo $0"
    exit 1
fi

echo "1. 停止containerd服务..."
systemctl stop containerd

echo "2. 备份现有containerd配置..."
if [ -f "/etc/containerd/config.toml" ]; then
    cp /etc/containerd/config.toml /etc/containerd/config.toml.backup.$(date +%Y%m%d_%H%M%S)
    echo "已备份现有配置文件"
fi

echo "3. 创建containerd配置目录..."
mkdir -p /etc/containerd

echo "4. 生成默认containerd配置..."
containerd config default > /etc/containerd/config.toml

echo "5. 配置SystemdCgroup..."
# 启用SystemdCgroup以支持Kubernetes
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

echo "6. 配置sandbox镜像..."
# 使用阿里云镜像加速
sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.7"|' /etc/containerd/config.toml

echo "7. 重新加载systemd配置..."
systemctl daemon-reload

echo "8. 启动并启用containerd服务..."
systemctl enable containerd
systemctl start containerd

echo "9. 等待containerd服务启动..."
sleep 5

echo "10. 检查containerd服务状态..."
if systemctl is-active --quiet containerd; then
    echo "✅ containerd服务运行正常"
else
    echo "❌ containerd服务启动失败"
    systemctl status containerd
    exit 1
fi

echo "11. 测试containerd CRI接口..."
if crictl version >/dev/null 2>&1; then
    echo "✅ containerd CRI接口正常"
else
    echo "⚠️  crictl未安装或配置不正确，但containerd服务已修复"
fi

echo "12. 重置kubeadm配置（如果存在）..."
if command -v kubeadm >/dev/null 2>&1; then
    kubeadm reset -f 2>/dev/null || true
    echo "已重置kubeadm配置"
fi

echo
echo "=== containerd修复完成 ==="
echo "✅ containerd运行时已修复并正常运行"
echo "✅ 已启用SystemdCgroup支持Kubernetes"
echo "✅ 已配置阿里云镜像加速"
echo
echo "现在可以重新执行Kubernetes集群初始化:"
echo "sudo kubeadm init --pod-network-cidr=10.244.0.0/16"
echo
echo "如果仍有问题，请检查:"
echo "1. 系统内存是否充足（建议2GB+）"
echo "2. 防火墙是否正确配置"
echo "3. 网络连接是否正常"
echo
echo "查看containerd日志: journalctl -u containerd -f"
echo "查看kubelet日志: journalctl -u kubelet -f"