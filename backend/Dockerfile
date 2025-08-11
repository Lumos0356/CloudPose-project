# Multi-stage build to optimize image size
FROM python:3.10-slim as builder

# Install build dependencies (including libraries required by OpenCV)
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
    libtbb-dev \
    libdc1394-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Production stage
FROM python:3.10-slim

# Install runtime dependencies (including GUI libraries required by OpenCV)
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
    libtbb-dev \
    libdc1394-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Create model directory
RUN mkdir -p /app/model

# Copy application code
COPY backend/app.py .
COPY backend/run.py .

# Copy MoveNet model file
COPY model2-movenet/movenet-full-256.tflite ./model/

# Create non-root user
RUN useradd --create-home --shell /bin/bash app

# Copy Python packages from build stage to app user directory
COPY --from=builder /root/.local /home/app/.local
RUN chown -R app:app /home/app/.local

# Change app directory permissions
RUN chown -R app:app /app
USER app

# Set environment variables
ENV PATH=/home/app/.local/bin:$PATH
ENV PYTHONPATH=/app
ENV FLASK_ENV=production
ENV MODEL_PATH=/app/model/movenet-full-256.tflite

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Startup command
CMD ["python", "app.py"]