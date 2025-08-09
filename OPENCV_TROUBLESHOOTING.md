# CloudPose OpenCV故障排除指南

## 问题描述

当运行CloudPose容器时，可能遇到以下错误：
```
ImportError: libGL.so.1: cannot open shared object file: No such file or directory
```

这个错误表明OpenCV无法找到必要的GUI库依赖。

## 解决方案

### 自动修复（推荐）

运行我们提供的自动修复脚本：
```bash
./fix_opencv_issue.sh
```

### 手动修复步骤

如果自动修复脚本无法解决问题，请按以下步骤手动修复：

#### 1. 停止现有容器
```bash
docker-compose down
```

#### 2. 删除现有镜像
```bash
docker rmi cloudpose-backend:latest
```

#### 3. 清理Docker缓存
```bash
docker builder prune -f
```

#### 4. 重新构建镜像
```bash
docker-compose build --no-cache
```

#### 5. 启动容器
```bash
docker-compose up -d
```

## 验证修复

### 检查容器状态
```bash
docker-compose ps
```

### 查看容器日志
```bash
docker-compose logs cloudpose-api
```

### 测试API健康状态
```bash
curl http://localhost:8000/health
```

期望输出：
```json
{"status": "healthy", "model_loaded": true}
```

## 已添加的OpenCV依赖库

我们在Dockerfile中添加了以下系统库来支持OpenCV：

- `libgl1-mesa-glx` - OpenGL库
- `libgtk-3-0` - GTK+3库
- `libavcodec-dev` - 视频编解码库
- `libavformat-dev` - 视频格式库
- `libswscale-dev` - 视频缩放库
- `libv4l-dev` - Video4Linux库
- `libxvidcore-dev` - Xvid编解码器
- `libx264-dev` - H.264编解码器
- `libjpeg-dev` - JPEG库
- `libpng-dev` - PNG库
- `libtiff-dev` - TIFF库
- `gfortran` - Fortran编译器
- `openexr` - OpenEXR库
- `libatlas-base-dev` - ATLAS数学库
- `python3-dev` - Python开发头文件
- `python3-numpy` - NumPy库
- `libtbb2` - Threading Building Blocks
- `libtbb-dev` - TBB开发库
- `libdc1394-22-dev` - IEEE 1394相机库

## 常见问题

### Q: 为什么需要这么多库？
A: OpenCV是一个功能强大的计算机视觉库，支持多种图像和视频格式、GUI显示、硬件加速等功能。这些库确保OpenCV能够正常工作。

### Q: 这会增加镜像大小吗？
A: 是的，添加这些库会增加镜像大小，但这是运行OpenCV应用程序的必要代价。我们使用多阶段构建来尽可能优化镜像大小。

### Q: 在生产环境中是否需要所有这些库？