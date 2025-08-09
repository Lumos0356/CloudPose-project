#!/bin/bash

# CloudPose 容器调试脚本
# 用于诊断容器启动失败的问题

echo "=== CloudPose 容器调试脚本 ==="
echo "时间: $(date)"
echo ""

# 1. 检查容器状态
echo "1. 检查容器状态:"
docker-compose ps
echo ""

# 2. 检查容器日志
echo "2. 检查容器日志 (最近50行):"
echo "--- 容器日志开始 ---"
docker-compose logs --tail=50 cloudpose-api
echo "--- 容器日志结束 ---"
echo ""

# 3. 检查端口配置
echo "3. 检查端口配置:"
echo "Docker Compose 端口映射:"
grep -A 5 -B 5 "ports:" docker-compose.yml
echo ""
echo "系统端口占用情况:"
netstat -tlnp | grep :8000 || echo "端口8000未被占用"
echo ""

# 4. 检查镜像构建
echo "4. 检查镜像信息:"
docker images | grep cloudpose
echo ""

# 5. 检查模型文件
echo "5. 检查模型文件是否存在:"
if [ -f "../model2-movenet/movenet-full-256.tflite" ]; then
    echo "✓ 模型文件存在: ../model2-movenet/movenet-full-256.tflite"
    ls -la ../model2-movenet/movenet-full-256.tflite
else
    echo "✗ 模型文件不存在: ../model2-movenet/movenet-full-256.tflite"
fi
echo ""

# 6. 检查容器内文件
echo "6. 检查容器内文件结构:"
echo "尝试进入容器检查文件..."
if docker-compose exec cloudpose-api ls -la /app/ 2>/dev/null; then
    echo "容器内 /app 目录内容:"
    docker-compose exec cloudpose-api ls -la /app/
    echo ""
    echo "容器内模型目录内容:"
    docker-compose exec cloudpose-api ls -la /app/model/ 2>/dev/null || echo "模型目录不存在或无法访问"
else
    echo "无法进入容器，容器可能未正常运行"
fi
echo ""

# 7. 尝试手动启动容器进行调试
echo "7. 建议的调试步骤:"
echo "如果容器持续重启，可以尝试以下命令进行调试:"
echo ""
echo "a) 停止当前容器:"
echo "   docker-compose down"
echo ""
echo "b) 重新构建镜像:"
echo "   docker-compose build --no-cache"
echo ""
echo "c) 以交互模式启动容器进行调试:"
echo "   docker-compose run --rm cloudpose-api /bin/bash"
echo "   # 在容器内手动运行: python app.py"
echo ""
echo "d) 检查Python依赖:"
echo "   docker-compose run --rm cloudpose-api pip list"
echo ""
echo "e) 查看详细启动日志:"
echo "   docker-compose up --no-daemon"
echo ""

echo "=== 调试脚本完成 ==="
echo "请根据上述输出信息分析问题原因"