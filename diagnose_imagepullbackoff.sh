#!/bin/bash

# CloudPose ImagePullBackOff 诊断脚本
# 用于诊断Kubernetes Pod镜像拉取失败问题

echo "=== CloudPose ImagePullBackOff 诊断脚本 ==="
echo "开始诊断时间: $(date)"
echo

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取CloudPose Pod名称
POD_NAME=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}错误: 未找到CloudPose Pod${NC}"
    echo "请确认Pod已部署: kubectl get pods -l app=cloudpose"
    exit 1
fi

echo -e "${BLUE}找到Pod: $POD_NAME${NC}"
echo

# 1. 检查Pod状态
echo -e "${YELLOW}=== 1. Pod状态检查 ===${NC}"
kubectl get pod $POD_NAME -o wide
echo

# 2. 检查Pod详细信息
echo -e "${YELLOW}=== 2. Pod详细信息 ===${NC}"
kubectl describe pod $POD_NAME
echo

# 3. 检查Pod事件
echo -e "${YELLOW}=== 3. Pod事件日志 ===${NC}"
kubectl get events --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp'
echo

# 4. 检查镜像配置
echo -e "${YELLOW}=== 4. 镜像配置检查 ===${NC}"
IMAGE_NAME=$(kubectl get pod $POD_NAME -o jsonpath='{.spec.containers[0].image}')
echo "配置的镜像: $IMAGE_NAME"
echo

# 5. 检查ImagePullSecrets
echo -e "${YELLOW}=== 5. ImagePullSecrets检查 ===${NC}"
SECRET_NAME=$(kubectl get pod $POD_NAME -o jsonpath='{.spec.imagePullSecrets[0].name}' 2>/dev/null)
if [ -n "$SECRET_NAME" ]; then
    echo "配置的Secret: $SECRET_NAME"
    kubectl get secret $SECRET_NAME 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Secret存在${NC}"
        kubectl describe secret $SECRET_NAME
    else
        echo -e "${RED}Secret不存在或无法访问${NC}"
    fi
else
    echo -e "${YELLOW}未配置ImagePullSecrets${NC}"
fi
echo

# 6. 检查节点Docker/containerd状态
echo -e "${YELLOW}=== 6. 节点容器运行时检查 ===${NC}"
NODE_NAME=$(kubectl get pod $POD_NAME -o jsonpath='{.spec.nodeName}')
echo "Pod所在节点: $NODE_NAME"
kubectl describe node $NODE_NAME | grep -A 10 "Container Runtime"
echo

# 7. 尝试手动拉取镜像（在节点上）
echo -e "${YELLOW}=== 7. 镜像拉取测试建议 ===${NC}"
echo "建议在节点 $NODE_NAME 上手动测试镜像拉取:"
echo "sudo docker pull $IMAGE_NAME"
echo "或"
echo "sudo crictl pull $IMAGE_NAME"
echo

# 8. 检查网络连接
echo -e "${YELLOW}=== 8. 网络连接检查 ===${NC}"
echo "检查到镜像仓库的网络连接..."
REGISTRY_HOST=$(echo $IMAGE_NAME | cut -d'/' -f1)
echo "镜像仓库主机: $REGISTRY_HOST"
ping -c 3 $REGISTRY_HOST 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}网络连接正常${NC}"
else
    echo -e "${RED}网络连接失败${NC}"
fi
echo

# 9. 常见问题诊断
echo -e "${YELLOW}=== 9. 常见问题诊断 ===${NC}"
echo "检查常见的ImagePullBackOff原因:"
echo

# 检查镜像名称格式
if [[ $IMAGE_NAME == *":latest"* ]] || [[ $IMAGE_NAME != *":"* ]]; then
    echo -e "${YELLOW}⚠️  使用了latest标签或未指定标签${NC}"
    echo "   建议使用具体的版本标签"
fi

# 检查是否为私有仓库
if [[ $IMAGE_NAME == *"registry.cn-"* ]] || [[ $IMAGE_NAME == *"aliyuncs.com"* ]]; then
    echo -e "${YELLOW}⚠️  使用阿里云ACR私有仓库${NC}"
    echo "   需要配置正确的ImagePullSecrets"
fi

# 检查Secret配置
if [ -z "$SECRET_NAME" ]; then
    echo -e "${RED}❌ 未配置ImagePullSecrets${NC}"
    echo "   私有仓库需要认证信息"
fi

echo

# 10. 解决方案建议
echo -e "${YELLOW}=== 10. 解决方案建议 ===${NC}"
echo "根据诊断结果，可能的解决方案:"
echo
echo "1. 如果是私有仓库认证问题:"
echo "   - 创建Docker registry secret"
echo "   - 确保Secret配置正确"
echo
echo "2. 如果是镜像不存在:"
echo "   - 检查镜像名称和标签"
echo "   - 确认镜像已推送到仓库"
echo
echo "3. 如果是网络问题:"
echo "   - 检查防火墙设置"
echo "   - 确认DNS解析正常"
echo
echo "4. 如果是节点资源问题:"
echo "   - 检查磁盘空间"
echo "   - 清理无用镜像"
echo

echo -e "${GREEN}诊断完成！${NC}"
echo "详细信息请查看上述输出，根据建议进行修复。"
echo