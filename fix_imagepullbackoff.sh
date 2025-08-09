#!/bin/bash

# CloudPose ImagePullBackOff 修复脚本
# 解决镜像拉取失败问题的完整方案

echo "=== CloudPose ImagePullBackOff 修复脚本 ==="
echo "开始修复时间: $(date)"
echo

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
IMAGE_NAME="cloudpose"
IMAGE_TAG="latest"
LOCAL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
REMOTE_REGISTRY="registry.cn-hangzhou.aliyuncs.com"
NAMESPACE="cloudpose-test"
REMOTE_IMAGE="$REMOTE_REGISTRY/$NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"
DOCKERFILE_PATH="./backend/Dockerfile"
BUILD_CONTEXT="./backend"

echo -e "${BLUE}配置信息:${NC}"
echo "本地镜像: $LOCAL_IMAGE"
echo "远程镜像: $REMOTE_IMAGE"
echo "Dockerfile路径: $DOCKERFILE_PATH"
echo "构建上下文: $BUILD_CONTEXT"
echo

# 检查必要文件
echo -e "${YELLOW}=== 1. 检查必要文件 ===${NC}"
if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo -e "${RED}错误: Dockerfile不存在: $DOCKERFILE_PATH${NC}"
    exit 1
fi

if [ ! -d "$BUILD_CONTEXT" ]; then
    echo -e "${RED}错误: 构建上下文目录不存在: $BUILD_CONTEXT${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 必要文件检查通过${NC}"
echo

# 检查Docker是否可用
echo -e "${YELLOW}=== 2. 检查Docker环境 ===${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker未安装或不在PATH中${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}错误: Docker服务未运行${NC}"
    echo "请启动Docker服务: sudo systemctl start docker"
    exit 1
fi

echo -e "${GREEN}✓ Docker环境检查通过${NC}"
echo

# 构建本地镜像
echo -e "${YELLOW}=== 3. 构建本地镜像 ===${NC}"
echo "开始构建镜像: $LOCAL_IMAGE"
echo "构建命令: docker build -t $LOCAL_IMAGE $BUILD_CONTEXT"
echo

docker build -t "$LOCAL_IMAGE" "$BUILD_CONTEXT"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 镜像构建成功${NC}"
else
    echo -e "${RED}❌ 镜像构建失败${NC}"
    echo "请检查Dockerfile和构建上下文"
    exit 1
fi
echo

# 标记镜像用于推送
echo -e "${YELLOW}=== 4. 标记镜像 ===${NC}"
echo "标记镜像: $LOCAL_IMAGE -> $REMOTE_IMAGE"
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 镜像标记成功${NC}"
else
    echo -e "${RED}❌ 镜像标记失败${NC}"
    exit 1
fi
echo

# 提供推送选项
echo -e "${YELLOW}=== 5. 镜像推送选项 ===${NC}"
echo "现在有以下选项来解决镜像问题:"
echo
echo "选项1: 推送到阿里云ACR (需要登录凭证)"
echo "选项2: 使用Docker Hub公共仓库"
echo "选项3: 修改Kubernetes配置使用本地镜像"
echo

read -p "请选择选项 (1/2/3): " choice

case $choice in
    1)
        echo -e "${BLUE}选择了阿里云ACR推送${NC}"
        echo "请先登录阿里云ACR:"
        echo "docker login --username=<your-username> $REMOTE_REGISTRY"
        echo
        read -p "是否已经登录? (y/n): " logged_in
        if [ "$logged_in" = "y" ] || [ "$logged_in" = "Y" ]; then
            echo "推送镜像到阿里云ACR..."
            docker push "$REMOTE_IMAGE"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ 镜像推送成功${NC}"
                echo "现在可以重新部署Pod"
            else
                echo -e "${RED}❌ 镜像推送失败${NC}"
                echo "请检查登录凭证和仓库权限"
            fi
        else
            echo "请先登录后再运行此脚本"
        fi
        ;;
    2)
        echo -e "${BLUE}选择了Docker Hub推送${NC}"
        DOCKERHUB_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
        echo "标记镜像用于Docker Hub: $DOCKERHUB_IMAGE"
        docker tag "$LOCAL_IMAGE" "$DOCKERHUB_IMAGE"
        echo
        echo