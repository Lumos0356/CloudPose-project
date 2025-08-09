#!/bin/bash

# CloudPose Kubernetes 快速诊断脚本
# 用于快速检查Pod状态、事件日志和常见问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
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

log_section() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# 检查kubectl连接
check_kubectl() {
    log_info "检查kubectl连接..."
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    log_success "kubectl连接正常"
}

# 检查CloudPose资源状态
check_cloudpose_resources() {
    log_section "CloudPose 资源状态检查"
    
    echo "\n📦 Deployment状态:"
    kubectl get deployment cloudpose-deployment -o wide 2>/dev/null || log_warning "Deployment不存在"
    
    echo "\n🏃 Pod状态:"
    kubectl get pods -l app=cloudpose -o wide 2>/dev/null || log_warning "没有找到CloudPose Pod"
    
    echo "\n🔧 Service状态:"
    kubectl get service cloudpose-service -o wide 2>/dev/null || log_warning "Service不存在"
    
    echo "\n📊 HPA状态:"
    kubectl get hpa cloudpose-hpa -o wide 2>/dev/null || log_warning "HPA不存在"
    
    echo "\n🗂️ ConfigMap状态:"
    kubectl get configmap cloudpose-config 2>/dev/null || log_warning "ConfigMap不存在"
    
    echo "\n🔐 Secret状态:"
    kubectl get secret cloudpose-secret 2>/dev/null || log_warning "Secret不存在"
}

# 检查Pod详细状态
check_pod_details() {
    log_section "Pod 详细状态检查"
    
    local pods=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$pods" ]; then
        log_error "没有找到CloudPose Pod"
        return 1
    fi
    
    for pod in $pods; do
        echo "\n🔍 Pod: $pod"
        echo "----------------------------------------"
        
        # Pod基本信息
        echo "📋 基本信息:"
        kubectl get pod $pod -o wide
        
        # Pod状态详情
        echo "\n📊 状态详情:"
        kubectl describe pod $pod | grep -A 10 "Conditions:"
        
        # 容器状态
        echo "\n🐳 容器状态:"
        kubectl get pod $pod -o jsonpath='{.status.containerStatuses[*]}' | jq -r '.' 2>/dev/null || kubectl get pod $pod -o jsonpath='{.status.containerStatuses[*]}'
        
        # 资源使用情况
        echo "\n💾 资源使用:"
        kubectl top pod $pod 2>/dev/null || log_warning "无法获取资源使用情况（可能需要安装metrics-server）"
        
        # 最近的日志（最后20行）
        echo "\n📝 最近日志（最后20行）:"
        kubectl logs $pod --tail=20 2>/dev/null || log_warning "无法获取Pod日志"
        
        echo "\n----------------------------------------"
    done
}

# 检查事件日志
check_events() {
    log_section "事件日志检查"
    
    echo "\n🔔 CloudPose相关事件（最近30个）:"
    kubectl get events --field-selector involvedObject.name=cloudpose-deployment --sort-by='.lastTimestamp' | tail -30
    
    echo "\n🔔 Pod相关事件（最近20个）:"
    kubectl get events --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | grep cloudpose | tail -20
    
    echo "\n🔔 所有最近事件（最近10个）:"
    kubectl get events --sort-by='.lastTimestamp' | tail -10
}

# 检查节点状态
check_node_status() {
    log_section "节点状态检查"
    
    echo "\n🖥️ 节点状态:"
    kubectl get nodes -o wide
    
    echo "\n💾 节点资源使用:"
    kubectl top nodes 2>/dev/null || log_warning "无法获取节点资源使用情况（可能需要安装metrics-server）"
    
    echo "\n🏷️ 节点标签和污点:"
    kubectl describe nodes | grep -E "Name:|Labels:|Taints:" | head -20
}

# 检查网络状态
check_network_status() {
    log_section "网络状态检查"
    
    echo "\n🌐 Service详情:"
    kubectl describe service cloudpose-service 2>/dev/null || log_warning "Service不存在"
    
    echo "\n🔗 Endpoints:"
    kubectl get endpoints cloudpose-service 2>/dev/null || log_warning "Endpoints不存在"
    
    echo "\n🛡️ NetworkPolicy:"
    kubectl get networkpolicy cloudpose-netpol -o wide 2>/dev/null || log_warning "NetworkPolicy不存在"
}

# 检查存储状态
check_storage_status() {
    log_section "存储状态检查"
    
    echo "\n💽 PersistentVolumes:"
    kubectl get pv 2>/dev/null || log_info "没有PersistentVolumes"
    
    echo "\n📁 PersistentVolumeClaims:"
    kubectl get pvc 2>/dev/null || log_info "没有PersistentVolumeClaims"
}

# 诊断常见问题
diagnose_common_issues() {
    log_section "常见问题诊断"
    
    local pods=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$pods" ]; then
        log_error "❌ 没有找到CloudPose Pod - 可能是调度问题"
        echo "   建议检查:"
        echo "   - 节点资源是否充足"
        echo "   - 节点是否有污点阻止调度"
        echo "   - 是否有nodeSelector或affinity限制"
        return 1
    fi
    
    for pod in $pods; do
        local status=$(kubectl get pod $pod -o jsonpath='{.status.phase}' 2>/dev/null)
        local ready=$(kubectl get pod $pod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        
        echo "\n🔍 Pod: $pod (状态: $status)"
        
        case $status in
            "Pending")
                log_warning "⏳ Pod处于Pending状态"
                echo "   可能原因:"
                echo "   - 资源不足（CPU/内存）"
                echo "   - 节点调度限制"
                echo "   - 镜像拉取问题"
                echo "   - 存储挂载问题"
                ;;
            "Running")
                if [ "$ready" = "True" ]; then
                    log_success "✅ Pod运行正常"
                else
                    log_warning "⚠️ Pod运行但未就绪"
                    echo "   可能原因:"
                    echo "   - 健康检查失败"
                    echo "   - 应用启动时间过长"
                    echo "   - 端口配置问题"
                fi
                ;;
            "Failed")
                log_error "❌ Pod运行失败"
                echo "   建议检查Pod日志和事件"
                ;;
            "CrashLoopBackOff")
                log_error "💥 Pod崩溃循环"
                echo "   可能原因:"
                echo "   - 应用启动失败"
                echo "   - 配置错误"
                echo "   - 依赖服务不可用"
                ;;
            "ImagePullBackOff")
                log_error "📥 镜像拉取失败"
                echo "   可能原因:"
                echo "   - 镜像不存在"
                echo "   - 镜像仓库认证问题"
                echo "   - 网络连接问题"
                ;;
            *)
                log_info "ℹ️ Pod状态: $status"
                ;;
        esac
    done
}

# 提供解决建议
provide_solutions() {
    log_section "解决建议"
    
    echo "\n🛠️ 常用故障排除命令:"
    echo "   查看Pod详情: kubectl describe pod -l app=cloudpose"
    echo "   查看Pod日志: kubectl logs -l app=cloudpose"
    echo "   查看事件: kubectl get events --sort-by='.lastTimestamp'"
    echo "   强制删除Pod: kubectl delete pod -l app=cloudpose --force --grace-period=0"
    echo "   重新部署: kubectl rollout restart deployment/cloudpose-deployment"
    
    echo "\n🔧 常见修复方法:"
    echo "   1. 如果是镜像问题: 检查镜像是否存在，运行 docker images | grep cloudpose"
    echo "   2. 如果是资源问题: 检查节点资源，运行 kubectl top nodes"
    echo "   3. 如果是调度问题: 检查节点污点，运行 kubectl describe nodes"
    echo "   4. 如果是网络问题: 检查Service和Endpoints配置"
    echo "   5. 如果是配置问题: 检查ConfigMap和Secret"
    
    echo "\n📚 相关脚本:"
    echo "   修复单节点集群: ./fix_single_node_k8s.sh"
    echo "   修复镜像问题: ./fix_imagepullbackoff.sh"
    echo "   修复HPA指标: ./fix_hpa_metrics.sh"
    echo "   重新部署: ./deploy_cloudpose_k8s.sh"
}

# 生成诊断报告
generate_report() {
    local report_file="cloudpose_diagnosis_$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "生成诊断报告: $report_file"
    
    {
        echo "CloudPose Kubernetes 诊断报告"
        echo "生成时间: $(date)"
        echo "======================================"
        
        echo "\n=== 集群信息 ==="
        kubectl cluster-info
        
        echo "\n=== 节点状态 ==="
        kubectl get nodes -o wide
        
        echo "\n=== CloudPose 资源 ==="
        kubectl get all -l app=cloudpose
        
        echo "\n=== Pod 详情 ==="
        kubectl describe pods -l app=cloudpose
        
        echo "\n=== 最近事件 ==="
        kubectl get events --sort-by='.lastTimestamp' | tail -20
        
        echo "\n=== Pod 日志 ==="
        kubectl logs -l app=cloudpose --tail=50
        
    } > "$report_file"
    
    log_success "诊断报告已保存到: $report_file"
}

# 主函数
main() {
    log_info "开始CloudPose Kubernetes快速诊断..."
    
    check_kubectl
    check_cloudpose_resources
    check_pod_details
    check_events
    check_node_status
    check_network_status
    check_storage_status
    diagnose_common_issues
    provide_solutions
    
    echo "\n"
    read -p "是否生成详细诊断报告？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        generate_report
    fi
    
    log_success "CloudPose Kubernetes诊断完成！"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi