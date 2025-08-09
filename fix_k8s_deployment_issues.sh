#!/bin/bash

# CloudPose Kubernetes 部署问题修复脚本
# 自动检测和修复常见的Kubernetes部署问题

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
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl未安装"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
}

# 修复单节点集群调度问题
fix_single_node_scheduling() {
    log_section "修复单节点集群调度问题"
    
    local master_nodes=$(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$master_nodes" ]; then
        # 尝试旧版本的标签
        master_nodes=$(kubectl get nodes --selector='node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}')
    fi
    
    if [ -n "$master_nodes" ]; then
        log_info "检测到master节点: $master_nodes"
        
        for node in $master_nodes; do
            local taints=$(kubectl describe node $node | grep "Taints:" | grep "NoSchedule")
            
            if [ -n "$taints" ]; then
                log_warning "节点 $node 有NoSchedule污点，正在移除..."
                
                # 移除control-plane污点
                kubectl taint nodes $node node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
                # 移除master污点（旧版本）
                kubectl taint nodes $node node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || true
                
                log_success "已移除节点 $node 的NoSchedule污点"
            else
                log_info "节点 $node 没有NoSchedule污点"
            fi
        done
    else
        log_info "没有检测到master节点"
    fi
}

# 修复镜像拉取问题
fix_image_pull_issues() {
    log_section "修复镜像拉取问题"
    
    # 检查Docker镜像是否存在
    if ! docker images | grep -q "cloudpose.*latest"; then
        log_warning "CloudPose镜像不存在，尝试构建..."
        
        if [ -f "build_local_image.sh" ]; then
            log_info "运行镜像构建脚本..."
            chmod +x build_local_image.sh
            ./build_local_image.sh
        elif [ -f "backend/Dockerfile" ]; then
            log_info "使用Dockerfile构建镜像..."
            docker build -t cloudpose:latest backend/
        else
            log_error "无法找到构建脚本或Dockerfile"
            return 1
        fi
    else
        log_success "CloudPose镜像已存在"
    fi
    
    # 检查镜像拉取策略
    local image_pull_policy=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}' 2>/dev/null)
    
    if [ "$image_pull_policy" != "Never" ] && [ "$image_pull_policy" != "IfNotPresent" ]; then
        log_warning "镜像拉取策略不正确，正在修复..."
        
        kubectl patch deployment cloudpose-deployment -p '{
            "spec": {
                "template": {
                    "spec": {
                        "containers": [{
                            "name": "cloudpose",
                            "imagePullPolicy": "IfNotPresent"
                        }]
                    }
                }
            }
        }'
        
        log_success "已修复镜像拉取策略"
    fi
}

# 修复资源限制问题
fix_resource_limits() {
    log_section "修复资源限制问题"
    
    # 检查节点资源
    log_info "检查节点资源使用情况..."
    kubectl top nodes 2>/dev/null || log_warning "无法获取节点资源信息（可能需要安装metrics-server）"
    
    # 检查Pod资源请求
    local cpu_request=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
    local memory_request=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null)
    
    if [ -n "$cpu_request" ] || [ -n "$memory_request" ]; then
        log_info "当前资源请求 - CPU: ${cpu_request:-未设置}, 内存: ${memory_request:-未设置}"
        
        # 如果资源请求过高，降低它们
        if [[ "$cpu_request" =~ ^[0-9]+$ ]] && [ "$cpu_request" -gt 1000 ]; then
            log_warning "CPU请求过高，正在降低..."
            kubectl patch deployment cloudpose-deployment -p '{
                "spec": {
                    "template": {
                        "spec": {
                            "containers": [{
                                "name": "cloudpose",
                                "resources": {
                                    "requests": {
                                        "cpu": "100m"
                                    }
                                }
                            }]
                        }
                    }
                }
            }'
        fi
        
        if [[ "$memory_request" =~ Gi$ ]] && [ "${memory_request%Gi}" -gt 2 ]; then
            log_warning "内存请求过高，正在降低..."
            kubectl patch deployment cloudpose-deployment -p '{
                "spec": {
                    "template": {
                        "spec": {
                            "containers": [{
                                "name": "cloudpose",
                                "resources": {
                                    "requests": {
                                        "memory": "512Mi"
                                    }
                                }
                            }]
                        }
                    }
                }
            }'
        fi
    fi
}

# 修复健康检查问题
fix_health_checks() {
    log_section "修复健康检查问题"
    
    # 检查是否有健康检查配置
    local readiness_probe=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null)
    local liveness_probe=$(kubectl get deployment cloudpose-deployment -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null)
    
    if [ -n "$readiness_probe" ] || [ -n "$liveness_probe" ]; then
        log_info "检测到健康检查配置"
        
        # 增加健康检查的超时时间和失败阈值
        kubectl patch deployment cloudpose-deployment -p '{
            "spec": {
                "template": {
                    "spec": {
                        "containers": [{
                            "name": "cloudpose",
                            "readinessProbe": {
                                "httpGet": {
                                    "path": "/health",
                                    "port": 5000
                                },
                                "initialDelaySeconds": 30,
                                "periodSeconds": 10,
                                "timeoutSeconds": 5,
                                "failureThreshold": 5
                            },
                            "livenessProbe": {
                                "httpGet": {
                                    "path": "/health",
                                    "port": 5000
                                },
                                "initialDelaySeconds": 60,
                                "periodSeconds": 30,
                                "timeoutSeconds": 10,
                                "failureThreshold": 3
                            }
                        }]
                    }
                }
            }
        }'
        
        log_success "已优化健康检查配置"
    else
        log_info "没有检测到健康检查配置"
    fi
}

# 修复网络问题
fix_network_issues() {
    log_section "修复网络问题"
    
    # 检查Service配置
    local service_type=$(kubectl get service cloudpose-service -o jsonpath='{.spec.type}' 2>/dev/null)
    
    if [ "$service_type" = "LoadBalancer" ]; then
        log_warning "Service类型为LoadBalancer，在单节点集群中可能不工作"
        log_info "将Service类型改为NodePort..."
        
        kubectl patch service cloudpose-service -p '{
            "spec": {
                "type": "NodePort"
            }
        }'
        
        log_success "已将Service类型改为NodePort"
    fi
    
    # 检查Endpoints
    local endpoints=$(kubectl get endpoints cloudpose-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    
    if [ -z "$endpoints" ]; then
        log_warning "Service没有可用的Endpoints"
        log_info "这通常意味着Pod没有就绪或标签选择器不匹配"
    else
        log_success "Service有可用的Endpoints: $endpoints"
    fi
}

# 修复存储问题
fix_storage_issues() {
    log_section "修复存储问题"
    
    # 检查PVC状态
    local pvcs=$(kubectl get pvc -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -n "$pvcs" ]; then
        for pvc in $pvcs; do
            local status=$(kubectl get pvc $pvc -o jsonpath='{.status.phase}')
            
            if [ "$status" != "Bound" ]; then
                log_warning "PVC $pvc 状态为 $status"
                
                # 如果是Pending状态，可能需要创建StorageClass
                if [ "$status" = "Pending" ]; then
                    log_info "尝试创建默认StorageClass..."
                    
                    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
                    
                    log_success "已创建默认StorageClass"
                fi
            fi
        done
    else
        log_info "没有检测到PVC"
    fi
}

# 重启部署
restart_deployment() {
    log_section "重启部署"
    
    log_info "重启CloudPose部署..."
    kubectl rollout restart deployment/cloudpose-deployment
    
    log_info "等待部署完成..."
    kubectl rollout status deployment/cloudpose-deployment --timeout=300s
    
    log_success "部署重启完成"
}

# 强制重新创建Pod
force_recreate_pods() {
    log_section "强制重新创建Pod"
    
    local pods=$(kubectl get pods -l app=cloudpose -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -n "$pods" ]; then
        log_info "删除现有Pod..."
        kubectl delete pods -l app=cloudpose --force --grace-period=0
        
        log_info "等待新Pod创建..."
        sleep 10
        
        kubectl wait --for=condition=ready --timeout=300s pod -l app=cloudpose
        
        log_success "Pod重新创建完成"
    else
        log_info "没有找到需要删除的Pod"
    fi
}

# 检查和修复metrics-server
fix_metrics_server() {
    log_section "检查和修复Metrics Server"
    
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        log_warning "Metrics Server未安装，正在安装..."
        
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        
        # 为单节点集群添加必要的参数
        kubectl patch deployment metrics-server -n kube-system -p '{
            "spec": {
                "template": {
                    "spec": {
                        "containers": [{
                            "name": "metrics-server",
                            "args": [
                                "--cert-dir=/tmp",
                                "--secure-port=4443",
                                "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
                                "--kubelet-use-node-status-port",
                                "--metric-resolution=15s",
                                "--kubelet-insecure-tls"
                            ]
                        }]
                    }
                }
            }
        }'
        
        log_success "Metrics Server安装完成"
    else
        log_info "Metrics Server已安装"
    fi
}

# 显示修复后的状态
show_status_after_fix() {
    log_section "修复后状态检查"
    
    echo "\n📦 Deployment状态:"
    kubectl get deployment cloudpose-deployment -o wide
    
    echo "\n🏃 Pod状态:"
    kubectl get pods -l app=cloudpose -o wide
    
    echo "\n🔧 Service状态:"
    kubectl get service cloudpose-service -o wide
    
    echo "\n🔔 最近事件:"
    kubectl get events --sort-by='.lastTimestamp' | tail -10
}

# 主函数
main() {
    log_info "开始CloudPose Kubernetes部署问题修复..."
    
    check_kubectl
    
    # 根据参数选择修复操作
    case "${1:-all}" in
        "scheduling")
            fix_single_node_scheduling
            ;;
        "image")
            fix_image_pull_issues
            ;;
        "resources")
            fix_resource_limits
            ;;
        "health")
            fix_health_checks
            ;;
        "network")
            fix_network_issues
            ;;
        "storage")
            fix_storage_issues
            ;;
        "restart")
            restart_deployment
            ;;
        "recreate")
            force_recreate_pods
            ;;
        "metrics")
            fix_metrics_server
            ;;
        "all")
            fix_single_node_scheduling
            fix_image_pull_issues
            fix_resource_limits
            fix_health_checks
            fix_network_issues
            fix_storage_issues
            fix_metrics_server
            restart_deployment
            ;;
        *)
            echo "用法: $0 [scheduling|image|resources|health|network|storage|restart|recreate|metrics|all]"
            echo "  scheduling - 修复单节点集群调度问题"
            echo "  image      - 修复镜像拉取问题"
            echo "  resources  - 修复资源限制问题"
            echo "  health     - 修复健康检查问题"
            echo "  network    - 修复网络问题"
            echo "  storage    - 修复存储问题"
            echo "  restart    - 重启部署"
            echo "  recreate   - 强制重新创建Pod"
            echo "  metrics    - 修复metrics-server"
            echo "  all        - 执行所有修复操作（默认）"
            exit 1
            ;;
    esac
    
    show_status_after_fix
    
    log_success "CloudPose Kubernetes部署问题修复完成！"
    log_info "如果问题仍然存在，请运行 ./quick_diagnose_k8s.sh 进行详细诊断"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi