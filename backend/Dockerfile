# 多阶段构建优化镜像大小
FROM python:3.10-slim as builder

# 安装构建依赖
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# 复制requirements并安装Python依赖
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# 生产阶段
FROM python:3.10-slim

# 安装运行时依赖
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 从构建阶段复制Python包
COPY --from=builder /root/.local /root/.local

# 设置工作目录
WORKDIR /app

# 创建模型目录
RUN mkdir -p /app/model

# 复制应用代码
COPY app.py .
COPY run.py .

# 复制MoveNet模型文件
COPY ../model2-movenet/movenet-full-256.tflite ./model/

# 创建非root用户
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app

# 设置环境变量
ENV PATH=/root/.local/bin:$PATH
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