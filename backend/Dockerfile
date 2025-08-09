# 多阶段构建优化镜像大小
FROM python:3.10-slim as builder

# 安装构建依赖（包含OpenCV所需的库）
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgl1-mesa-glx \
    libgtk-3-0 \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libv4l-dev \
    libxvidcore-dev \
    libx264-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    gfortran \
    openexr \
    libatlas-base-dev \
    python3-dev \
    python3-numpy \
    libtbb2 \
    libtbb-dev \
    libdc1394-22-dev \
    && rm -rf /var/lib/apt/lists/*

# 复制requirements并安装Python依赖
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# 生产阶段
FROM python:3.10-slim

# 安装运行时依赖（包含OpenCV所需的GUI库）
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    curl \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libgtk-3-0 \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libv4l-dev \
    libxvidcore-dev \
    libx264-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    gfortran \
    openexr \
    libatlas-base-dev \
    python3-dev \
    python3-numpy \
    libtbb2 \
    libtbb-dev \
    libdc1394-22-dev \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 创建模型目录
RUN mkdir -p /app/model

# 复制应用代码
COPY backend/app.py .
COPY backend/run.py .

# 复制MoveNet模型文件
COPY model2-movenet/movenet-full-256.tflite ./model/

# 创建非root用户
RUN useradd --create-home --shell /bin/bash app

# 从构建阶段复制Python包到app用户目录
COPY --from=builder /root/.local /home/app/.local
RUN chown -R app:app /home/app/.local

# 修改app目录权限
RUN chown -R app:app /app
USER app

# 设置环境变量
ENV PATH=/home/app/.local/bin:$PATH
ENV PYTHONPATH=/app
ENV FLASK_ENV=production
ENV MODEL_PATH=/app/model/movenet-full-256.tflite

# 暴露端口
EXPOSE 8000

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# 启动命令
CMD ["python", "app.py"]