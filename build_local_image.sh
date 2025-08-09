#!/bin/bash

# CloudPose 本地Docker镜像构建脚本
# 用于从GitHub克隆的项目构建本地Docker镜像

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== CloudPose 本地Docker镜像构建脚本 ===${NC}"
echo "从GitHub克隆的项目构建本地Docker镜像"
echo

# 检查必要文件
echo -e "${YELLOW}检查必要文件...${NC}"
required_files=(
    "backend/Dockerfile"
    "backend/app.py"
    "backend/requirements.txt"
    "model2-movenet/movenet-full-256.tflite"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}错误: 缺少必要文件 $file${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ 所有必要文件检查通过${NC}"
echo

# 检查Docker是否运行
echo -e "${YELLOW}检查Docker环境...${NC}"
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}错误: Docker未运行或未安装${NC}"
    echo "请启动Docker服务"
    exit 1
fi
echo -e "${GREEN}✓ Docker环境检查通过${NC}"
echo

# 构建镜像
IMAGE_NAME="cloudpose"
TAG="latest"
echo -e "${YELLOW}开始构建Docker镜像...${NC}"
echo "镜像名称: ${IMAGE_NAME}:${TAG}"
echo

# 使用backend目录下的Dockerfile构建
echo -e "${BLUE}执行构建命令...${NC}"
docker build -f backend/Dockerfile -t ${IMAGE_NAME}:${TAG} .

if [ $? -eq 0 ]; then
    echo
    echo -e "${GREEN}✓ Docker镜像构建成功!${NC}"
    echo "镜像名称: ${IMAGE_NAME}:${TAG}"
    echo
    
    # 显示镜像信息
    echo -e "${YELLOW}镜像信息:${NC}"
    docker images ${IMAGE_NAME}:${TAG}
    echo
    
    # 提供下一步操作建议
    echo -e "${BLUE}下一步操作:${NC}"
    echo "1. 测试镜像: docker run --rm -p 8000:8000 ${IMAGE_NAME}:${TAG}"
    echo "2. 部署到Kubernetes: kubectl apply -f k8s-deployment.yaml"
    echo "3. 检查Pod状态: kubectl get pods -l app=cloudpose"
    echo
else
    echo -e "${RED}✗ Docker镜像构建失败${NC}"
    echo "请检查构建日志中的错误信息"
    exit 1
fi

# 可选：标记镜像为Kubernetes可用
echo -e "${YELLOW}为Kubernetes准备镜像...${NC}"
echo "确保镜像在本地Docker环境中可用"
docker tag ${IMAGE_NAME}:${TAG} ${IMAGE_NAME}:latest
echo -e "${GREEN}✓ 镜像已准备就绪，可用于Kubernetes部署${NC}"
echo

echo -e "${GREEN}=== 构建完成 ===${NC}"
echo "现在可以使用以下命令部署到Kubernetes:"
echo "kubectl apply -f k8s-deployment.yaml"