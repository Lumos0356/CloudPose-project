# CloudPose 包依赖问题故障排除指南

## 问题描述

在构建CloudPose Docker镜像时，可能会遇到以下包依赖错误：

```
E: Package 'libtbb2' has no installation candidate
E: Unable to locate package libdc1394-22-dev
```

## 问题原因

这些错误通常发生在以下情况：

1. **包名变更**: 某些包在新版本的Linux发行版中被重命名或替换
2. **版本不兼容**: 使用的包名在当前Debian/Ubuntu版本中不存在
3. **仓库更新**: 包仓库中的包结构发生变化

## 解决方案

### 1. 包名映射

以下是常见的过时包名及其替换：

| 过时包名 | 新包名 | 说明 |
|---------|--------|------|
| `libtbb2` | `libtbb-dev` | Intel Threading Building Blocks开发库 |
| `libdc1394-22-dev` | `libdc1394-dev` | IEEE 1394相机控制库 |
| `python3-numpy` | 通常已包含在python3-dev中 | NumPy数学库 |

### 2. 自动修复

我们已经修复了Dockerfile中的包依赖问题。如果遇到类似问题，可以：

#### 方法1: 使用修复脚本
```bash
# 运行包依赖修复测试
./test_package_fix.sh
```

#### 方法2: 手动修复
```bash
# 停止容器
docker-compose down

# 清理缓存
docker builder prune -f

# 重新构建
docker-compose build --no-cache
```

### 3. 验证修复

修复后，验证步骤：

1. **构建测试**:
   ```bash
   docker-compose build --no-cache
   ```

2. **启动测试**:
   ```bash
   docker-compose up -d
   ```

3. **健康检查**:
   ```bash
   curl http://localhost:8000/health
   ```

## 预防措施

### 1. 使用稳定的基础镜像

```dockerfile
# 推荐使用特定版本标签
FROM python:3.10-slim
# 而不是
# FROM python:latest
```

### 2. 定期更新依赖

定期检查和更新包依赖，确保兼容性：

```bash
# 检查可用包
apt-cache search libtbb
apt-cache search libdc1394
```

### 3. 使用包管理器查询

在添加新依赖前，验证包名：

```bash
# 在容器内或相同环境中测试
apt-get update
apt-cache show package-name
```

## 常见错误及解决方案

### 错误1: Package has no installation candidate

**原因**: 包名在当前发行版中不存在

**解决**: 
1. 查找替代包名
2. 更新包名映射
3. 检查是否需要添加额外的仓库

### 错误2: Unable to locate package

**原因**: 包名拼写错误或