#!/bin/bash

# CloudPose Kubernetes 部署脚本
# 用于在已构建Docker镜像后重新部署CloudPose到Kubernetes集群

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必要的工具
check_prerequisites() {
    log_info "检查必要的工具..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装或不在PATH中"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "docker 未安装或不在PATH中"
        exit 1
    fi
    
    log_success "所有必要工具已安装"
}

# 检查Kubernetes集群连接
check_k8s_connection() {
    log_info "检查Kubernetes集群连接..."
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        log_error "请检查kubeconfig配置"
        exit 1
    fi
    
    log_success "Kubernetes集群连接正常"
}

# 检查Docker镜像是否存在
check_docker_image() {
    log_info "检查Docker镜像是否存在..."
    
    if ! docker images | grep -q "cloudpose.*latest"; then
        log_error "CloudPose Docker镜像不存在"
        log_error "请先运行 ./build_local_image.sh 构建镜像"
        exit 1
    fi
    
    log_success "CloudPose Docker镜像已存在"
}

# 清理旧的部署
cleanup_old_deployment() {
    log_info "清理旧的CloudPose部署..."
    
    # 删除旧的部署（如果存在）
    kubectl delete -f k8s-deployment.yaml --ignore-not-found=true
    
    # 等待Pod完全删除
    log_info "等待Pod完全删除..."
    kubectl wait --for=delete pod -l app=cloudpose --timeout=60s || true
    
    log_success "旧部署已清理"
}

# 部署CloudPose
deploy_cloudpose() {
    log_info "部署CloudPose到Kubernetes集群..."
    
    # 检查k8s-deployment.yaml文件是否存在
    if [ ! -f "k8s-deployment.yaml" ]; then
        log_error "k8s-deployment.yaml 文件不存在"
        exit 1
    fi
    
    # 应用部署配置
    kubectl apply -f k8s-deployment.yaml
    
    log_success "CloudPose部署配置已应用"
}

# 等待部署就绪
wait_for_deployment() {
    log_info "等待CloudPose部署就绪..."
    
    # 等待Deployment就绪
    if kubectl wait --for=condition=available --timeout=300s deployment/cloudpose-deployment; then
        log_success "CloudPose Deployment已就绪"
    else
        log_error "CloudPose Deployment未能在5分钟内就绪"
        log_error "请检查Pod状态和日志"
        return 1
    fi
    
    # 等待Pod运行
    log_info "等待Pod运行..."
    if kubectl wait --for=condition=ready --timeout=300s pod -l app=cloudpose; then
        log_success "CloudPose Pod已运行"
    else
        log_error "CloudPose Pod未能在5分钟内运行"
        log_error "请检查Pod状态和日志"
        return 1
    fi
}

# 检查服务状态
check_service_status() {
    log_info "检查CloudPose服务状态..."
    
    # 获取服务信息
    kubectl get service cloudpose-service
    
    # 获取NodePort
    NODE_PORT=$(kubectl get service cloudpose-service -o jsonpath='{.spec.ports[0].nodePort}')
    
    if [ -n "$NODE_PORT" ]; then
        log_success "CloudPose服务已创建，NodePort: $NODE_PORT"
        
        # 获取节点IP
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        
        if [ -n "$NODE_IP" ]; then
            log_info "CloudPose访问地址: http://$NODE_IP:$NODE_PORT"
        fi
    else
        log_warning "无法获取NodePort信息"
    fi
}

# 显示部署状态
show_deployment_status() {
    log_info "CloudPose部署状态:"
    echo "==========================================="
    
    echo "\n📦 Pods状态:"
    kubectl get pods -l app=cloudpose
    
    echo "\n🔧 Services状态:"
    kubectl get services -l app=cloudpose
    
    echo "\n📊 HPA状态:"
    kubectl get hpa cloudpose-hpa || log_warning "HPA未配置或不可用"
    
    echo "\n🔍 最近的Pod事件:"
    kubectl get events --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | tail -10
    
    echo "==========================================="
}

# 主函数
main() {
    log_info "开始CloudPose Kubernetes部署流程..."
    
    check_prerequisites
    check_k8s_connection
    check_docker_image
    
    cleanup_old_deployment
    deploy_cloudpose
    
    if wait_for_deployment; then
        check_service_status
        show_deployment_status
        
        log_success "CloudPose已成功部署到Kubernetes集群！"
        log_info "使用以下命令查看详细状态:"
        echo "  kubectl get all -l app=cloudpose"
        echo "  kubectl logs -l app=cloudpose"
        echo "  kubectl describe pod -l app=cloudpose"
    else
        log_error "CloudPose部署失败"
        log_info "查看详细错误信息:"
        echo "  kubectl describe pod -l app=cloudpose"
        echo "  kubectl logs -l app=cloudpose"
        exit 1
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi