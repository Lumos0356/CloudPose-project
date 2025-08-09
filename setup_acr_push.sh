#!/bin/bash

# 阿里云ACR镜像推送配置脚本
# 用于将本地CloudPose镜像推送到阿里云容器镜像服务

set -e

echo "=== 阿里云ACR镜像推送配置 ==="
echo "时间: $(date)"
echo

# 配置变量 - 请根据您的ACR实例修改这些值
ACR_REGISTRY="crpi-r4l5tp7zj19m2jd.cn-hongkong.personal.cr.aliyuncs.com"  # 替换为您的ACR地址
ACR_NAMESPACE="cloudpose-api"  # 替换为您的命名空间
IMAGE_NAME="backend-cloudpose-api"
IMAGE_TAG="latest"
LOCAL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
ACR_IMAGE="${ACR_REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}[步骤]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查必要的工具
print_step "检查必要工具..."
if ! command -v docker &> /dev/null; then
    print_error "Docker 未安装或不在PATH中"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl 未安装或不在PATH中"
    exit 1
fi

echo "✅ Docker 和 kubectl 已安装"
echo

# 检查本地镜像是否存在
print_step "检查本地镜像..."
if ! docker images | grep -q "${IMAGE_NAME}.*${IMAGE_TAG}"; then
    print_error "本地镜像 ${LOCAL_IMAGE} 不存在"
    echo "请先构建镜像:"
    echo "cd backend && docker build -t ${LOCAL_IMAGE} ."
    exit 1
fi

echo "✅ 找到本地镜像: ${LOCAL_IMAGE}"
docker images | grep "${IMAGE_NAME}.*${IMAGE_TAG}"
echo

# 配置检查
print_step "配置检查..."
echo "ACR 注册表: ${ACR_REGISTRY}"
echo "命名空间: ${ACR_NAMESPACE}"
echo "镜像名称: ${IMAGE_NAME}"
echo "镜像标签: ${IMAGE_TAG}"
echo "本地镜像: ${LOCAL_IMAGE}"
echo "ACR 镜像: ${ACR_IMAGE}"
echo

print_warning "请确认以上配置正确，特别是ACR注册表地址和命名空间"
read -p "是否继续? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "操作已取消"
    exit 1
fi

# 登录到ACR
print_step "登录到阿里云ACR..."
echo "请输入您的阿里云ACR凭据:"
echo "提示: 您可以在阿里云控制台 -> 容器镜像服务 -> 访问凭证 中找到登录命令"
echo "登录命令格式: docker login --username=your-username ${ACR_REGISTRY}"
echo

# 尝试自动登录（如果已配置）
if docker login ${ACR_REGISTRY} --username="" --password="" 2>/dev/null; then
    echo "✅ 使用已保存的凭据登录成功"
else
    echo "请手动登录到ACR:"
    echo "docker login --username=your-username ${ACR_REGISTRY}"
    read -p "登录完成后按回车继续..."
fi
echo

# 标记镜像
print_step "标记镜像为ACR格式..."
echo "将 ${LOCAL_IMAGE} 标记为 ${ACR_IMAGE}"
docker tag ${LOCAL_IMAGE} ${ACR_IMAGE}

if [ $? -eq 0 ]; then
    echo "✅ 镜像标记成功"
else
    print_error "镜像标记失败"
    exit 1
fi
echo

# 推送镜像到ACR
print_step "推送镜像到ACR..."
echo "正在推送 ${ACR_IMAGE}..."
docker push ${ACR_IMAGE}

if [ $? -eq 0 ]; then
    echo "✅ 镜像推送成功!"
else
    print_error "镜像推送失败"
    exit 1
fi
echo

# 验证推送结果
print_step "验证推送结果..."
echo "检查ACR中的镜像..."
# 注意: 这里需要阿里云CLI工具，如果没有安装可以跳过
if command -v aliyun &> /dev/null; then
    echo "使用阿里云CLI检查镜像..."
    # aliyun cr GET /repos/${ACR_NAMESPACE}/${IMAGE_NAME}/tags
else
    echo "请在阿里云控制台中验证镜像是否推送成功:"
    echo "https://cr.console.aliyun.com/"
fi
echo

# 生成Kubernetes配置
print_step "生成Kubernetes配置信息..."
echo "ACR镜像地址: ${ACR_IMAGE}"
echo
echo "请将k8s-deployment.yaml中的镜像地址更新为:"
echo "image: ${ACR_IMAGE}"
echo
echo "如果需要私有仓库认证，请创建docker-registry secret:"
echo "kubectl create secret docker-registry acr-secret \\"
echo "  --docker-server=${ACR_REGISTRY} \\"
echo "  --docker-username=your-username \\"
echo "  --docker-password=your-password \\"
echo "  --docker-email=your-email"
echo
echo "然后在deployment中添加:"
echo "imagePullSecrets:"
echo "- name: acr-secret"
echo

# 清理本地标记的镜像（可选）
print_step "清理..."
read -p "是否删除本地标记的ACR镜像? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker rmi ${ACR_IMAGE}
    echo "✅ 已删除本地ACR标记镜像"
fi

echo
echo "=== ACR推送配置完成 ==="
echo "下一步:"
echo "1. 运行 ./setup_acr_k8s.sh 配置Kubernetes使用ACR镜像"
echo "2. 或手动修改 k8s-deployment.yaml 中的镜像地址"
echo "3. 重新部署应用: kubectl apply -f k8s-deployment.yaml"
echo