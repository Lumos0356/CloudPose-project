#!/usr/bin/env python3
"""
CloudPose 后端服务启动脚本

使用方法:
    python run.py
    
或者使用gunicorn生产环境部署:
    gunicorn -w 4 -b 0.0.0.0:8000 app:app
"""

import os
import sys
from app import app, load_model, logger

def main():
    """主函数"""
    logger.info("="*50)
    logger.info("CloudPose 姿态检测服务启动中...")
    logger.info("="*50)
    
    # 检查模型文件是否存在
    model_path = '../model2-movenet/movenet-full-256.tflite'
    if not os.path.exists(model_path):
        logger.error(f"模型文件未找到: {model_path}")
        logger.error("请确保模型文件存在于正确位置")
        sys.exit(1)
    
    # 加载模型
    logger.info("正在加载MoveNet模型...")
    if load_model():
        logger.info("✅ 模型加载成功")
    else:
        logger.error("❌ 模型加载失败")
        sys.exit(1)
    
    # 启动服务
    logger.info("🚀 启动Flask服务器...")
    logger.info("API文档: http://localhost:8000/")
    logger.info("健康检查: http://localhost:8000/health")
    logger.info("姿态检测: POST http://localhost:8000/api/pose_detection")
    logger.info("按 Ctrl+C 停止服务")
    logger.info("="*50)
    
    try:
        app.run(host='0.0.0.0', port=8000, debug=False)
    except KeyboardInterrupt:
        logger.info("\n👋 服务已停止")
    except Exception as e:
        logger.error(f"服务启动失败: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()