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

# 等待部署就绪（带超时和详细状态检查）
wait_for_deployment() {
    log_info "等待CloudPose部署就绪..."
    
    # 设置超时时间（秒）
    TIMEOUT=300
    START_TIME=$(date +%s)
    
    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        
        if [ $ELAPSED -ge $TIMEOUT ]; then
            log_error "部署超时（${TIMEOUT}秒），开始诊断..."
            
            echo "\n📊 当前部署状态:"
            kubectl get deployment cloudpose-deployment -o wide
            
            echo "\n🏃 Pod状态:"
            kubectl get pods -l app=cloudpose -o wide
            
            echo "\n🔔 最近事件:"
            kubectl get events --sort-by='.lastTimestamp' | tail -10
            
            echo "\n📋 Pod详细信息:"
            PODS=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[*].metadata.name}')
            for pod in $PODS; do
                echo "\n--- Pod: $pod ---"
                kubectl describe pod $pod | tail -20
            done
            
            log_error "部署失败，请运行以下命令进行修复:"
            echo "  ./fix_k8s_deployment_issues.sh"
            echo "  ./quick_diagnose_k8s.sh"
            return 1
        fi
        
        # 检查部署状态
        READY_REPLICAS=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED_REPLICAS=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$READY_REPLICAS" = "$DESIRED_REPLICAS" ] && [ "$READY_REPLICAS" != "0" ]; then
            log_success "CloudPose Deployment已就绪 ($READY_REPLICAS/$DESIRED_REPLICAS)"
            break
        fi
        
        # 显示当前状态
        echo -ne "\r⏳ 等待部署就绪... ($ELAPSED/${TIMEOUT}s) - 就绪副本: $READY_REPLICAS/$DESIRED_REPLICAS"
        
        # 每30秒显示详细状态
        if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
            echo "\n\n📊 当前状态检查 (${ELAPSED}s):"
            kubectl get pods -l app=cloudpose -o wide
            
            # 检查是否有错误状态的Pod
            ERROR_PODS=$(kubectl get pods -l app=cloudpose --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
            if [ -n "$ERROR_PODS" ]; then
                echo "\n⚠️  发现问题Pod: $ERROR_PODS"
                for pod in $ERROR_PODS; do
                    POD_STATUS=$(kubectl get pod $pod -o jsonpath='{.status.phase}')
                    echo "  - $pod: $POD_STATUS"
                    
                    # 如果Pod状态异常，显示更多信息
                    if [ "$POD_STATUS" = "Pending" ] || [ "$POD_STATUS" = "Failed" ]; then
                        echo "    原因: $(kubectl get pod $pod -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}' 2>/dev/null || echo '未知')"
                        echo "    消息: $(kubectl get pod $pod -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].message}' 2>/dev/null || echo '无')"
                    fi
                done
            fi
            
            log_info "继续等待..."
        fi
        
        sleep 5
    done
    
    echo "" # 换行
    
    # 等待Pod运行
    log_info "等待Pod运行..."
    if kubectl wait --for=condition=ready --timeout=60s pod -l app=cloudpose; then
        log_success "CloudPose Pod已运行"
    else
        log_error "CloudPose Pod未能在1分钟内运行"
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