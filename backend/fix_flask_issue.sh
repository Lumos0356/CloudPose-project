#!/bin/bash

# CloudPose Flask依赖修复脚本
# 解决容器中Flask模块缺失的问题

echo "=== CloudPose Flask依赖修复脚本 ==="
echo "时间: $(date)"
echo ""

echo "🔧 修复步骤:"
echo "1. 停止当前容器"
echo "2. 清理旧镜像"
echo "3. 重新构建镜像"
echo "4. 启动新容器"
echo "5. 验证修复结果"
echo ""

# 1. 停止当前容器
echo "📦 停止当前容器..."
docker-compose down
echo ""

# 2. 清理旧镜像（可选）
echo "🧹 清理旧镜像..."
docker image prune -f
echo ""

# 3. 重新构建镜像
echo "🔨 重新构建镜像（无缓存）..."
docker-compose build --no-cache
if [ $? -ne 0 ]; then
    echo "❌ 镜像构建失败！请检查错误信息。"
    exit 1
fi
echo ""

# 4. 启动新容器
echo "🚀 启动新容器..."
docker-compose up -d
if [ $? -ne 0 ]; then
    echo "❌ 容器启动失败！请检查错误信息。"
    exit 1
fi
echo ""

# 5. 等待容器启动
echo "⏳ 等待容器启动..."
sleep 10

# 6. 验证修复结果
echo "✅ 验证修复结果:"
echo ""
echo "容器状态:"
docker-compose ps
echo ""
echo "健康检查:"
for i in {1..5}; do
    echo "尝试 $i/5: 测试健康检查接口..."
    if curl -s http://localhost:8000/health > /dev/null; then
        echo "✅ 健康检查成功！"
        echo "🎉 CloudPose服务已成功启动！"
        echo ""
        echo "📋 服务信息:"
        echo "- 健康检查: http://localhost:8000/health"
        echo "- 姿态检测: http://localhost:8000/pose_detection"
        echo ""
        echo "🔍 查看实时日志: docker-compose logs -f cloudpose-api"
        exit 0
    else
        echo "⏳ 等待服务启动..."
        sleep 5
    fi
done

echo "⚠️  服务可能仍在启动中，请手动检查:"
echo "- 查看容器状态: docker-compose ps"
echo "- 查看容器日志: docker-compose logs cloudpose-api"
echo "- 测试健康检查: curl http://localhost:8000/health"

echo ""
echo "=== 修复脚本完成 ==="