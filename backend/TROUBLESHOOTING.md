# CloudPose 容器故障排除指南

## 问题诊断

### 问题现象
- 容器状态显示 `Restarting (1)`
- 无法连接到端口 8000
- `curl http://localhost:8000/health` 返回连接拒绝

### 根本原因分析

经过详细诊断，发现主要问题是：

1. **模型路径错误** ⚠️ **主要问题**
   - `app.py` 中硬编码了本地开发路径：`/Users/luka/Downloads/client/model2-movenet/movenet-full-256.tflite`
   - 容器内应该使用：`/app/model/movenet-full-256.tflite`
   - **已修复**：现在使用环境变量 `MODEL_PATH`，默认为容器路径

2. **端口配置** ✅ **正常**
   - Docker Compose 正确映射了 8000:8000
   - Dockerfile 正确暴露了端口 8000
   - Flask 应用配置为监听 0.0.0.0:8000

3. **模型文件复制** ✅ **正常**
   - Dockerfile 正确复制模型文件到 `/app/model/`
   - Docker Compose 构建上下文已修复为父目录

## 解决方案

### 1. 立即修复步骤

```bash
# 1. 停止当前容器
docker-compose down

# 2. 重新构建镜像（清除缓存）
docker-compose build --no-cache

# 3. 启动服务
docker-compose up -d

# 4. 检查状态
docker-compose ps

# 5. 测试健康检查
curl http://localhost:8000/health
```

### 2. 验证修复

```bash
# 检查容器日志
docker-compose logs cloudpose-api

# 检查容器内文件
docker-compose exec cloudpose-api ls -la /app/model/

# 测试API端点
curl http://localhost:8000/
curl http://localhost:8000/health
```

### 3. 使用调试脚本

```bash
# 运行完整的调试脚本
./debug_container.sh
```

## 预防措施

### 1. 环境变量配置

在 `docker-compose.yml` 中已正确设置：
```yaml
environment:
  - MODEL_PATH=/app/model/movenet-full-256.tflite
```

### 2. 健康检查

容器配置了健康检查，会自动检测服务状态：
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

### 3. 日志监控

```bash
# 实时查看日志
docker-compose logs -f cloudpose-api

# 查看最近的错误
docker-compose logs --tail=50 cloudpose-api
```

## 常见问题

### Q1: 容器仍然重启怎么办？

```bash
# 以交互模式启动容器进行调试
docker-compose run --rm cloudpose-api /bin/bash

# 在容器内手动测试
python -c "import tensorflow.lite as tflite; print('TensorFlow Lite OK')"
ls -la /app/model/
python app.py
```

### Q2: 模型文件缺失

```bash
# 检查宿主机模型文件
ls -la ../model2-movenet/movenet-full-256.tflite

# 检查容器内模型文件
docker-compose exec cloudpose-api ls -la /app/model/
```

### Q3: 依赖问题

```bash
# 检查Python依赖
docker-compose run --rm cloudpose-api pip list

# 重新安装依赖
docker-compose build --no-cache
```

## 性能优化

### 1. 资源限制

当前配置：
```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 2G
    reservations:
      cpus: '0.5'
      memory: 1G
```

### 2. 监控指标

访问 Prometheus 指标：
```bash
curl http://localhost:8000/metrics
```

## 部署验证清单

- [ ] 模型文件存在：`../model2-movenet/movenet-full-256.tflite`
- [ ] Docker 构建成功：`docker-compose build`
- [ ] 容器启动正常：`docker-compose ps`
- [ ] 健康检查通过：`curl http://localhost:8000/health`
- [ ] API 文档可访问：`curl http://localhost:8000/`
- [ ] 日志无错误：`docker-compose logs cloudpose-api`

## 联系支持

如果问题仍然存在，请提供以下信息：

1. 运行 `./debug_container.sh` 的完整输出
2. `docker-compose logs cloudpose-api` 的日志
3. 系统信息：`uname -a` 和 `docker --version`
4. 模型文件信息：`ls -la ../model2-movenet/`

---

**最后更新**: $(date)
**状态**: 主要问题已修复，容器应该能正常启动