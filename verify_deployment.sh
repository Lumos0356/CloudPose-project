#!/bin/bash

# CloudPose Kubernetes 部署验证脚本
# 全面验证CloudPose在Kubernetes集群中的部署状态

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

# 全局变量
VERIFICATION_PASSED=0
VERIFICATION_FAILED=0
VERIFICATION_WARNINGS=0

# 验证结果记录
record_result() {
    local status=$1
    local message=$2
    
    case $status in
        "pass")
            log_success "✅ $message"
            ((VERIFICATION_PASSED++))
            ;;
        "fail")
            log_error "❌ $message"
            ((VERIFICATION_FAILED++))
            ;;
        "warn")
            log_warning "⚠️  $message"
            ((VERIFICATION_WARNINGS++))
            ;;
    esac
}

# 检查kubectl连接
check_kubectl_connection() {
    log_section "检查Kubernetes连接"
    
    if ! command -v kubectl &> /dev/null; then
        record_result "fail" "kubectl未安装"
        return 1
    fi
    
    if kubectl cluster-info &> /dev/null; then
        record_result "pass" "kubectl连接正常"
        
        # 显示集群信息
        local cluster_info=$(kubectl cluster-info | head -2)
        echo "$cluster_info"
    else
        record_result "fail" "无法连接到Kubernetes集群"
        return 1
    fi
}

# 检查节点状态
check_node_status() {
    log_section "检查节点状态"
    
    local nodes=$(kubectl get nodes --no-headers)
    local node_count=$(echo "$nodes" | wc -l)
    
    echo "📊 集群节点信息:"
    kubectl get nodes -o wide
    
    # 检查每个节点的状态
    while IFS= read -r line; do
        local node_name=$(echo "$line" | awk '{print $1}')
        local node_status=$(echo "$line" | awk '{print $2}')
        local node_role=$(echo "$line" | awk '{print $3}')
        
        if [ "$node_status" = "Ready" ]; then
            record_result "pass" "节点 $node_name ($node_role) 状态正常"
        else
            record_result "fail" "节点 $node_name ($node_role) 状态异常: $node_status"
        fi
    done <<< "$nodes"
    
    echo "\n📈 节点资源使用情况:"
    kubectl top nodes 2>/dev/null || log_warning "无法获取节点资源信息（可能需要安装metrics-server）"
}

# 检查CloudPose Deployment
check_deployment() {
    log_section "检查CloudPose Deployment"
    
    if kubectl get deployment cloudpose-deployment &> /dev/null; then
        record_result "pass" "CloudPose Deployment存在"
        
        # 获取Deployment详细信息
        local ready_replicas=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        local available_replicas=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
        
        echo "\n📊 Deployment状态:"
        kubectl get deployment cloudpose-deployment -o wide
        
        if [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]; then
            record_result "pass" "所有副本已就绪 ($ready_replicas/$desired_replicas)"
        else
            record_result "fail" "副本未完全就绪 ($ready_replicas/$desired_replicas)"
        fi
        
        if [ "$available_replicas" = "$desired_replicas" ] && [ "$available_replicas" != "0" ]; then
            record_result "pass" "所有副本可用 ($available_replicas/$desired_replicas)"
        else
            record_result "warn" "部分副本不可用 ($available_replicas/$desired_replicas)"
        fi
        
        # 检查Deployment事件
        echo "\n📋 Deployment事件:"
        kubectl describe deployment cloudpose-deployment | grep -A 10 "Events:" || echo "无事件"
        
    else
        record_result "fail" "CloudPose Deployment不存在"
        return 1
    fi
}

# 检查Pod状态
check_pods() {
    log_section "检查CloudPose Pod状态"
    
    local pods=$(kubectl get pods -l app=cloudpose --no-headers 2>/dev/null)
    
    if [ -z "$pods" ]; then
        record_result "fail" "没有找到CloudPose Pod"
        return 1
    fi
    
    echo "📊 Pod状态:"
    kubectl get pods -l app=cloudpose -o wide
    
    # 检查每个Pod的状态
    while IFS= read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local pod_status=$(echo "$line" | awk '{print $3}')
        local pod_ready=$(echo "$line" | awk '{print $2}')
        local pod_restarts=$(echo "$line" | awk '{print $4}')
        
        case $pod_status in
            "Running")
                if [[ "$pod_ready" == *"/"* ]]; then
                    local ready_containers=$(echo "$pod_ready" | cut -d'/' -f1)
                    local total_containers=$(echo "$pod_ready" | cut -d'/' -f2)
                    
                    if [ "$ready_containers" = "$total_containers" ]; then
                        record_result "pass" "Pod $pod_name 运行正常 ($pod_ready)"
                    else
                        record_result "warn" "Pod $pod_name 部分容器未就绪 ($pod_ready)"
                    fi
                else
                    record_result "pass" "Pod $pod_name 运行正常"
                fi
                
                # 检查重启次数
                if [ "$pod_restarts" -gt 0 ]; then
                    record_result "warn" "Pod $pod_name 已重启 $pod_restarts 次"
                fi
                ;;
            "Pending")
                record_result "fail" "Pod $pod_name 处于Pending状态"
                echo "    原因: $(kubectl get pod $pod_name -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}' 2>/dev/null || echo '未知')"
                ;;
            "Failed")
                record_result "fail" "Pod $pod_name 处于Failed状态"
                ;;
            "CrashLoopBackOff")
                record_result "fail" "Pod $pod_name 处于CrashLoopBackOff状态"
                ;;
            "ImagePullBackOff"|"ErrImagePull")
                record_result "fail" "Pod $pod_name 镜像拉取失败: $pod_status"
                ;;
            *)
                record_result "warn" "Pod $pod_name 状态未知: $pod_status"
                ;;
        esac
    done <<< "$pods"
    
    # 显示Pod资源使用情况
    echo "\n📈 Pod资源使用情况:"
    kubectl top pods -l app=cloudpose 2>/dev/null || log_warning "无法获取Pod资源信息"
}

# 检查Service状态
check_service() {
    log_section "检查CloudPose Service"
    
    if kubectl get service cloudpose-service &> /dev/null; then
        record_result "pass" "CloudPose Service存在"
        
        echo "\n📊 Service信息:"
        kubectl get service cloudpose-service -o wide
        
        # 检查Service类型
        local service_type=$(kubectl get service cloudpose-service -o jsonpath='{.spec.type}')
        local cluster_ip=$(kubectl get service cloudpose-service -o jsonpath='{.spec.clusterIP}')
        
        case $service_type in
            "ClusterIP")
                record_result "pass" "Service类型: ClusterIP ($cluster_ip)"
                ;;
            "NodePort")
                local node_port=$(kubectl get service cloudpose-service -o jsonpath='{.spec.ports[0].nodePort}')
                record_result "pass" "Service类型: NodePort (端口: $node_port)"
                
                # 获取节点IP用于访问
                local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                echo "    外部访问地址: http://$node_ip:$node_port"
                ;;
            "LoadBalancer")
                local external_ip=$(kubectl get service cloudpose-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                if [ -n "$external_ip" ] && [ "$external_ip" != "null" ]; then
                    record_result "pass" "Service类型: LoadBalancer (外部IP: $external_ip)"
                else
                    record_result "warn" "Service类型: LoadBalancer (外部IP待分配)"
                fi
                ;;
        esac
        
        # 检查Endpoints
        local endpoints=$(kubectl get endpoints cloudpose-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
        if [ -n "$endpoints" ]; then
            record_result "pass" "Service有可用的Endpoints: $endpoints"
        else
            record_result "fail" "Service没有可用的Endpoints"
        fi
        
    else
        record_result "fail" "CloudPose Service不存在"
    fi
}

# 检查HPA状态
check_hpa() {
    log_section "检查CloudPose HPA"
    
    if kubectl get hpa cloudpose-hpa &> /dev/null; then
        record_result "pass" "CloudPose HPA存在"
        
        echo "\n📊 HPA状态:"
        kubectl get hpa cloudpose-hpa
        
        # 检查HPA指标
        local current_replicas=$(kubectl get hpa cloudpose-hpa -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
        local desired_replicas=$(kubectl get hpa cloudpose-hpa -o jsonpath='{.status.desiredReplicas}' 2>/dev/null || echo "0")
        local min_replicas=$(kubectl get hpa cloudpose-hpa -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo "1")
        local max_replicas=$(kubectl get hpa cloudpose-hpa -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "10")
        
        if [ "$current_replicas" -ge "$min_replicas" ] && [ "$current_replicas" -le "$max_replicas" ]; then
            record_result "pass" "HPA副本数正常 (当前: $current_replicas, 范围: $min_replicas-$max_replicas)"
        else
            record_result "warn" "HPA副本数异常 (当前: $current_replicas, 范围: $min_replicas-$max_replicas)"
        fi
        
    else
        record_result "warn" "CloudPose HPA不存在（可选组件）"
    fi
}

# 检查ConfigMap和Secret
check_config() {
    log_section "检查配置和密钥"
    
    # 检查ConfigMap
    if kubectl get configmap cloudpose-config &> /dev/null; then
        record_result "pass" "CloudPose ConfigMap存在"
        
        local config_keys=$(kubectl get configmap cloudpose-config -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "无法解析")
        if [ "$config_keys" != "无法解析" ]; then
            echo "    配置项: $config_keys"
        fi
    else
        record_result "warn" "CloudPose ConfigMap不存在（可选组件）"
    fi
    
    # 检查Secret
    if kubectl get secret cloudpose-secret &> /dev/null; then
        record_result "pass" "CloudPose Secret存在"
        
        local secret_keys=$(kubectl get secret cloudpose-secret -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "无法解析")
        if [ "$secret_keys" != "无法解析" ]; then
            echo "    密钥项: $secret_keys"
        fi
    else
        record_result "warn" "CloudPose Secret不存在（可选组件）"
    fi
}

# 检查网络策略
check_network_policy() {
    log_section "检查网络策略"
    
    if kubectl get networkpolicy cloudpose-netpol &> /dev/null; then
        record_result "pass" "CloudPose NetworkPolicy存在"
        
        echo "\n📊 NetworkPolicy信息:"
        kubectl get networkpolicy cloudpose-netpol -o wide
    else
        record_result "warn" "CloudPose NetworkPolicy不存在（可选组件）"
    fi
}

# 测试应用连通性
test_connectivity() {
    log_section "测试应用连通性"
    
    # 获取Service信息
    local service_type=$(kubectl get service cloudpose-service -o jsonpath='{.spec.type}' 2>/dev/null)
    local service_port=$(kubectl get service cloudpose-service -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
    
    if [ -z "$service_type" ]; then
        record_result "fail" "无法获取Service信息"
        return 1
    fi
    
    case $service_type in
        "ClusterIP")
            # 集群内测试
            local cluster_ip=$(kubectl get service cloudpose-service -o jsonpath='{.spec.clusterIP}')
            
            log_info "测试集群内连通性..."
            if kubectl run test-connectivity --image=curlimages/curl --rm -i --restart=Never -- curl -f -m 10 "http://$cluster_ip:$service_port/health" &> /dev/null; then
                record_result "pass" "集群内连通性测试通过"
            else
                record_result "fail" "集群内连通性测试失败"
            fi
            ;;
        "NodePort")
            # NodePort测试
            local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
            local node_port=$(kubectl get service cloudpose-service -o jsonpath='{.spec.ports[0].nodePort}')
            
            log_info "测试NodePort连通性..."
            if curl -f -m 10 "http://$node_ip:$node_port/health" &> /dev/null; then
                record_result "pass" "NodePort连通性测试通过"
                echo "    访问地址: http://$node_ip:$node_port"
            else
                record_result "warn" "NodePort连通性测试失败（可能是健康检查端点不存在）"
                echo "    访问地址: http://$node_ip:$node_port"
            fi
            ;;
        "LoadBalancer")
            # LoadBalancer测试
            local external_ip=$(kubectl get service cloudpose-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
            
            if [ -n "$external_ip" ] && [ "$external_ip" != "null" ]; then
                log_info "测试LoadBalancer连通性..."
                if curl -f -m 10 "http://$external_ip:$service_port/health" &> /dev/null; then
                    record_result "pass" "LoadBalancer连通性测试通过"
                    echo "    访问地址: http://$external_ip:$service_port"
                else
                    record_result "warn" "LoadBalancer连通性测试失败（可能是健康检查端点不存在）"
                    echo "    访问地址: http://$external_ip:$service_port"
                fi
            else
                record_result "warn" "LoadBalancer外部IP未分配，跳过连通性测试"
            fi
            ;;
    esac
}

# 检查日志
check_logs() {
    log_section "检查应用日志"
    
    local pods=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$pods" ]; then
        record_result "fail" "没有找到CloudPose Pod，无法检查日志"
        return 1
    fi
    
    for pod in $pods; do
        echo "\n📋 Pod $pod 最近日志:"
        
        # 检查当前容器日志
        local current_logs=$(kubectl logs $pod --tail=10 2>/dev/null)
        if [ -n "$current_logs" ]; then
            echo "$current_logs"
            
            # 检查是否有错误日志
            if echo "$current_logs" | grep -i "error\|exception\|failed\|panic" &> /dev/null; then
                record_result "warn" "Pod $pod 日志中发现错误信息"
            else
                record_result "pass" "Pod $pod 日志正常"
            fi
        else
            record_result "warn" "Pod $pod 没有日志输出"
        fi
        
        # 检查之前容器日志（如果有重启）
        local previous_logs=$(kubectl logs $pod --previous --tail=5 2>/dev/null)
        if [ -n "$previous_logs" ]; then
            echo "\n📋 Pod $pod 之前容器日志:"
            echo "$previous_logs"
        fi
    done
}

# 生成验证报告
generate_report() {
    log_section "验证报告"
    
    local total_checks=$((VERIFICATION_PASSED + VERIFICATION_FAILED + VERIFICATION_WARNINGS))
    
    echo "📊 验证统计:"
    echo "  ✅ 通过: $VERIFICATION_PASSED"
    echo "  ❌ 失败: $VERIFICATION_FAILED"
    echo "  ⚠️  警告: $VERIFICATION_WARNINGS"
    echo "  📋 总计: $total_checks"
    
    if [ $VERIFICATION_FAILED -eq 0 ]; then
        if [ $VERIFICATION_WARNINGS -eq 0 ]; then
            log_success "🎉 CloudPose部署验证完全通过！"
            return 0
        else
            log_warning "⚠️  CloudPose部署基本正常，但有 $VERIFICATION_WARNINGS 个警告项需要关注"
            return 0
        fi
    else
        log_error "❌ CloudPose部署验证失败，有 $VERIFICATION_FAILED 个严重问题需要修复"
        echo "\n🔧 建议修复步骤:"
        echo "  1. 运行诊断脚本: ./quick_diagnose_k8s.sh"
        echo "  2. 运行修复脚本: ./fix_k8s_deployment_issues.sh"
        echo "  3. 重新验证部署: ./verify_deployment.sh"
        return 1
    fi
}

# 主函数
main() {
    echo "🔍 开始CloudPose Kubernetes部署验证..."
    echo "验证时间: $(date)"
    
    # 执行所有检查
    check_kubectl_connection || exit 1
    check_node_status
    check_deployment
    check_pods
    check_service
    check_hpa
    check_config
    check_network_policy
    test_connectivity
    check_logs
    
    # 生成报告
    generate_report
    
    # 返回适当的退出码
    if [ $VERIFICATION_FAILED -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi