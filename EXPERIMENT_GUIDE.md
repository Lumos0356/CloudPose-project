# CloudPose 负载测试实验完整指导

本指导文档将帮助您完成Assignment第7节要求的负载测试实验和报告撰写。

## 📋 实验概述

根据Assignment要求，您需要：
1. 测试系统在不同Pod数量(1,2,4,8)下的最大负载承受能力
2. 使用Locust进行并发用户测试，支持128个图像的RESTful API调用
3. 监控响应时间、QPS和错误率
4. 生成包含表格和分析的实验报告

## 🛠️ 环境准备

### 1. 安装依赖

```bash
# 安装Locust负载测试工具
pip install locust

# 安装其他依赖
pip install requests psutil
```

### 2. 验证文件结构

确保您的项目目录包含以下文件：

```
client/
├── locustfile.py                    # Locust测试脚本
├── run_experiments.py               # 自动化实验脚本
├── prepare_test_images.py           # 测试图像准备脚本
├── experiment_report_template.md    # 报告模板
├── inputfolder/                     # 包含128个测试图像
├── backend/                         # 后端服务代码
│   ├── app.py
│   ├── Dockerfile
│   └── ...
└── EXPERIMENT_GUIDE.md             # 本指导文档
```

## 🚀 实验执行步骤

### 步骤1: 准备测试图像

```bash
# 从inputfolder复制128个图像到test_images目录
python prepare_test_images.py

# 验证图像准备情况
python prepare_test_images.py verify
```

预期输出：
```
CloudPose 测试图像准备脚本
==================================================
在 'inputfolder' 中找到 120 个图像文件
选择前 120 个图像进行测试
创建目标目录: test_images
...
测试图像准备完成!
```

### 步骤2: 启动后端服务

#### 选项A: 本地运行

```bash
# 进入后端目录
cd backend

# 启动服务
python run.py
```

#### 选项B: Docker运行

```bash
# 构建Docker镜像
cd backend
docker build -t cloudpose-api .

# 运行容器
docker run -p 8000:8000 cloudpose-api
```

#### 选项C: Kubernetes部署

```bash
# 部署到Kubernetes
kubectl apply -f k8s/

# 检查服务状态
kubectl get pods
kubectl get services
```

### 步骤3: 验证服务可用性

```bash
# 检查健康状态
curl http://localhost:8000/health

# 或者对于Kubernetes
curl http://your-k8s-cluster-ip:30080/health
```

预期响应：
```json
{
  "status": "healthy",
  "model_loaded": true,
  "timestamp": "2024-01-20T10:30:00Z"
}
```

### 步骤4: 执行负载测试实验

#### 方法A: 自动化实验（推荐）

```bash
# 本地测试
python run_experiments.py --host http://localhost:8000 --mode local

# Kubernetes集群测试
python run_experiments.py --host http://your-k8s-cluster-ip:30080 --mode k8s

# 自定义配置
python run_experiments.py --host http://localhost:8000 --pods 1,2,4 --users 10,20,50 --duration 300
```

#### 方法B: 手动测试

```bash
# 单个实验示例
locust -f locustfile.py --host=http://localhost:8000 --users 50 --spawn-rate 5 --run-time 300s --headless --csv results_50users
```

### 步骤5: Kubernetes Pod扩展（如果使用K8s）

在运行不同Pod数量的测试时，需要手动调整replica数量：

```bash
# 1 Pod
kubectl scale deployment cloudpose-deployment --replicas=1

# 2 Pods
kubectl scale deployment cloudpose-deployment --replicas=2

# 4 Pods
kubectl scale deployment cloudpose-deployment --replicas=4

# 8 Pods
kubectl scale deployment cloudpose-deployment --replicas=8

# 验证Pod状态
kubectl get pods -l app=cloudpose
```

## 📊 实验数据收集

### 自动化实验结果

运行`run_experiments.py`后，会在`experiments_YYYYMMDD_HHMMSS/`目录下生成：

```
experiments_20240120_103000/
├── experiment_results.json          # 完整JSON数据
├── experiment_summary.csv           # 汇总CSV数据
├── experiment_report.md             # 自动生成的报告
├── experiment_1_1pods_10users_*.csv # 详细统计数据
├── experiment_1_1pods_10users_*.html # Locust HTML报告
└── experiment_1_1pods_10users_*.log  # 测试日志
```

### 关键指标说明

| 指标 | 说明 | 重要性 |
|------|------|--------|
| Average Response Time | 平均响应时间(ms) | 用户体验指标 |
| P95 Response Time | 95%请求的响应时间 | 性能稳定性 |
| Requests/s (QPS) | 每秒查询数 | 吞吐量指标 |
| Failure Rate | 失败率(%) | 系统稳定性 |
| Request Count | 总请求数 | 测试覆盖度 |

## 📝 报告撰写指导

### 1. 使用报告模板

```bash
# 复制模板开始撰写
cp experiment_report_template.md my_experiment_report.md
```

### 2. 填写实验数据

根据实验结果填写以下表格：

```markdown
| # of Pods | Max Users | Avg. Response Time (ms) |
|-----------|-----------|-------------------------|
| 1         | 25        | 145.2                   |
| 2         | 45        | 167.8                   |
| 4         | 85        | 189.3                   |
| 8         | 150       | 201.7                   |
```

### 3. 分析要点

**响应时间分析**:
- 描述响应时间随用户数增加的变化趋势
- 分析不同Pod配置的性能差异
- 识别性能拐点

**扩展性分析**:
- 计算水平扩展效率：`(Pod2_QPS - Pod1_QPS) / Pod1_QPS`
- 分析边际收益递减现象
- 识别扩展瓶颈

**稳定性分析**:
- 记录开始出现错误的负载水平
- 分析错误类型和原因
- 评估系统容错能力

### 4. 分布式系统挑战分析

选择三个挑战进行分析，例如：

1. **负载均衡**: Kubernetes Service如何分发请求
2. **容错性**: Pod故障时的系统行为
3. **资源管理**: CPU/内存限制对性能的影响

## 🔧 故障排除

### 常见问题及解决方案

#### 1. 测试图像加载失败

```bash
# 检查图像目录
ls -la test_images/

# 重新准备图像
python prepare_test_images.py clean
python prepare_test_images.py
```

#### 2. 服务连接失败

```bash
# 检查服务状态
curl -v http://localhost:8000/health

# 检查端口占用
lsof -i :8000

# 检查防火墙设置
```

#### 3. Locust测试失败

```bash
# 检查Locust版本
locust --version

# 验证locustfile.py语法
python -m py_compile locustfile.py

# 查看详细错误日志
locust -f locustfile.py --host=http://localhost:8000 --loglevel DEBUG
```

#### 4. Kubernetes Pod扩展问题

```bash
# 检查Deployment状态
kubectl describe deployment cloudpose-deployment

# 检查Pod日志
kubectl logs -l app=cloudpose

# 检查资源限制
kubectl top pods
```

### 性能调优建议

1. **增加测试时长**: 对于稳定的结果，建议每个测试运行5-10分钟
2. **调整生成速率**: 根据系统响应调整`--spawn-rate`参数
3. **监控资源使用**: 使用`kubectl top`或`docker stats`监控资源
4. **网络优化**: 确保测试客户端和服务器之间的网络延迟最小

## 📈 结果验证

### 数据合理性检查

1. **响应时间**: 应该随负载增加而增长
2. **QPS**: 应该随Pod数量增加而提升（但可能有上限）
3. **成功率**: 在系统容量内应该保持100%
4. **扩展效率**: 2个Pod的QPS应该接近1个Pod的2倍

### 实验重现性

```bash
# 重复实验验证结果一致性
python run_experiments.py --host http://localhost:8000 --mode local --duration 180
```

## 📋 检查清单

实验完成前请确认：

- [ ] 测试图像已准备（128个）
- [ ] 后端服务正常运行
- [ ] 健康检查接口返回正常
- [ ] 完成了1,2,4,8个Pod的测试
- [ ] 收集了完整的性能数据
- [ ] 生成了HTML和CSV报告
- [ ] 填写了实验报告模板
- [ ] 分析了分布式系统挑战
- [ ] 报告字数符合要求（1500字以内）
- [ ] 包含了个人信息（姓名、学号等）

## 🎯 提交要求

根据Assignment要求，您需要提交：

1. **实验报告** (PDF格式)
   - 使用12pt Times字体
   - 单栏，1英寸边距
   - 包含完整的个人信息
   - 最多1500字（不包括表格）

2. **实验数据** (可选)
   - CSV格式的原始数据
   - Locust生成的HTML报告

3. **代码文件** (如果要求)
   - locustfile.py
   - 其他相关脚本

## 💡 额外建议

1. **多次运行**: 每个配置至少运行2-3次以确保结果稳定
2. **监控资源**: 记录CPU、内存使用情况
3. **网络分析**: 考虑网络延迟对结果的影响
4. **错误分析**: 详细分析失败请求的原因
5. **可视化**: 考虑添加图表来展示趋势

## 📞 获取帮助

如果遇到问题，可以：

1. 查看Locust官方文档: https://docs.locust.io/
2. 检查Kubernetes文档: https://kubernetes.io/docs/
3. 查看项目README文件
4. 联系导师或同学讨论

---

**祝您实验顺利！** 🎉

记住，实验的目标不仅是收集数据，更重要的是理解系统的性能特征和扩展性限制。通过这个实验，您将深入了解分布式系统的实际表现和挑战。