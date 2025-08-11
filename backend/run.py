#!/usr/bin/env python3
"""
CloudPose Backend Service Startup Script

Usage:
    python run.py
    
Or use gunicorn for production deployment:
    gunicorn -w 4 -b 0.0.0.0:8000 app:app
"""

import os
import sys
from app import app, load_model, logger

def main():
    """Main function"""
    logger.info("="*50)
    logger.info("CloudPose Pose Detection Service Starting...")
    logger.info("="*50)
    
    # Check if model file exists
    model_path = '../model2-movenet/movenet-full-256.tflite'
    if not os.path.exists(model_path):
        logger.error(f"Model file not found: {model_path}")
        logger.error("Please ensure the model file exists in the correct location")
        sys.exit(1)
    
    # Load model
    logger.info("Loading MoveNet model...")
    if load_model():
        logger.info("✅ Model loaded successfully")
    else:
        logger.error("❌ Model loading failed")
        sys.exit(1)
    
    # Start service
    logger.info("🚀 Starting Flask server...")
    logger.info("API Documentation: http://localhost:8000/")
    logger.info("Health Check: http://localhost:8000/health")
    logger.info("Pose Detection: POST http://localhost:8000/api/pose_detection")
    logger.info("Press Ctrl+C to stop service")
    logger.info("="*50)
    
    try:
        app.run(host='0.0.0.0', port=8000, debug=False)
    except KeyboardInterrupt:
        logger.info("\n👋 Service stopped")
    except Exception as e:
        logger.error(f"Service startup failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()