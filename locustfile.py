#!/usr/bin/env python3
"""
CloudPose 负载测试脚本
使用Locust进行并发用户测试，支持128个图像的RESTful API调用

使用方法:
    # Web界面模式
    locust -f locustfile.py --host=http://localhost:8000
    
    # 命令行模式
    locust -f locustfile.py --host=http://localhost:8000 --users 50 --spawn-rate 5 --run-time 300s --headless
    
    # Kubernetes集群测试
    locust -f locustfile.py --host=http://your-k8s-cluster-ip:30080 --users 100 --spawn-rate 10 --run-time 600s --headless
"""

from locust import HttpUser, task, between
import base64
import json
import uuid
import os
import random
import time
import logging

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CloudPoseUser(HttpUser):
    """CloudPose API负载测试用户类"""
    
    # 用户等待时间：1-3秒之间随机
    wait_time = between(1, 3)
    
    def on_start(self):
        """用户启动时加载测试图像"""
        self.images = []
        self.load_test_images()
        
        if not self.images:
            logger.error("No test images loaded! Please run prepare_test_images.py first.")
            self.environment.runner.quit()
    
    def load_test_images(self):
        """加载128个测试图像"""
        image_dir = "test_images"
        
        if not os.path.exists(image_dir):
            logger.warning(f"Test images directory '{image_dir}' not found. Trying inputfolder...")
            image_dir = "inputfolder"
        
        if not os.path.exists(image_dir):
            logger.error(f"Neither 'test_images' nor 'inputfolder' directory found!")
            return
        
        # 获取所有图像文件
        image_files = [f for f in os.listdir(image_dir) 
                      if f.lower().endswith(('.jpg', '.jpeg', '.png', '.bmp'))]
        
        # 限制为128个图像
        image_files = image_files[:128]
        
        logger.info(f"Loading {len(image_files)} test images from {image_dir}...")
        
        for filename in image_files:
            try:
                file_path = os.path.join(image_dir, filename)
                with open(file_path, 'rb') as f:
                    image_data = base64.b64encode(f.read()).decode('utf-8')
                    self.images.append({
                        'data': image_data,
                        'filename': filename
                    })
            except Exception as e:
                logger.warning(f"Failed to load image {filename}: {e}")
        
        logger.info(f"Successfully loaded {len(self.images)} test images")
    
    @task(3)
    def pose_detection_json(self):
        """测试姿态检测JSON API - 权重3（主要测试）"""
        if not self.images:
            return
        
        # 随机选择一个测试图像
        image_info = random.choice(self.images)
        request_id = str(uuid.uuid4())
        
        payload = {
            "image": image_info['data'],
            "id": request_id
        }
        
        headers = {
            "Content-Type": "application/json",
            "User-Agent": "Locust-CloudPose-Test"
        }
        
        start_time = time.time()
        
        with self.client.post("/api/pose_detection", 
                             json=payload,
                             headers=headers,
                             catch_response=True,
                             timeout=30) as response:
            
            response_time = (time.time() - start_time) * 1000  # 转换为毫秒
            
            if response.status_code == 200:
                try:
                    result = response.json()
                    
                    # 验证响应格式
                    required_fields = ['id', 'count', 'keypoints', 'speed_preprocess', 
                                     'speed_inference', 'speed_postprocess']
                    
                    if all(field in result for field in required_fields):
                        # 记录性能指标
                        inference_time = result.get('speed_inference', 0) * 1000
                        total_processing_time = (result.get('speed_preprocess', 0) + 
                                               result.get('speed_inference', 0) + 
                                               result.get('speed_postprocess', 0)) * 1000
                        
                        response.success()
                        
                        # 记录详细指标到日志
                        logger.debug(f"Pose Detection - Response: {response_time:.2f}ms, "
                                   f"Inference: {inference_time:.2f}ms, "
                                   f"Processing: {total_processing_time:.2f}ms, "
                                   f"Persons: {result.get('count', 0)}")
                    else:
                        response.failure(f"Invalid response format: missing required fields")
                        
                except json.JSONDecodeError:
                    response.failure("Invalid JSON response")
            elif response.status_code == 500:
                response.failure(f"Server error: {response.status_code}")
            elif response.status_code == 400:
                response.failure(f"Bad request: {response.status_code}")
            else:
                response.failure(f"HTTP {response.status_code}: {response.text[:100]}")
    
    @task(1)
    def pose_detection_image(self):
        """测试姿态检测图像API - 权重1（辅助测试）"""
        if not self.images:
            return
        
        # 随机选择一个测试图像
        image_info = random.choice(self.images)
        request_id = str(uuid.uuid4())
        
        payload = {
            "image": image_info['data'],
            "id": request_id
        }
        
        headers = {
            "Content-Type": "application/json",
            "User-Agent": "Locust-CloudPose-Test"
        }
        
        start_time = time.time()
        
        with self.client.post("/api/pose_estimation_image", 
                             json=payload,
                             headers=headers,
                             catch_response=True,
                             timeout=45) as response:  # 图像处理需要更长时间
            
            response_time = (time.time() - start_time) * 1000
            
            if response.status_code == 200:
                try:
                    result = response.json()
                    
                    # 验证响应格式
                    required_fields = ['id', 'annotated_image', 'speed_preprocess', 
                                     'speed_inference', 'speed_postprocess']
                    
                    if all(field in result for field in required_fields):
                        # 验证base64图像数据
                        annotated_image = result.get('annotated_image', '')
                        if annotated_image and len(annotated_image) > 100:
                            response.success()
                            
                            # 记录性能指标
                            inference_time = result.get('speed_inference', 0) * 1000
                            total_processing_time = (result.get('speed_preprocess', 0) + 
                                                   result.get('speed_inference', 0) + 
                                                   result.get('speed_postprocess', 0)) * 1000
                            
                            logger.debug(f"Image API - Response: {response_time:.2f}ms, "
                                       f"Inference: {inference_time:.2f}ms, "
                                       f"Processing: {total_processing_time:.2f}ms")
                        else:
                            response.failure("Invalid or empty annotated image")
                    else:
                        response.failure("Invalid response format: missing required fields")
                        
                except json.JSONDecodeError:
                    response.failure("Invalid JSON response")
            else:
                response.failure(f"HTTP {response.status_code}: {response.text[:100]}")
    
    @task(1)
    def health_check(self):
        """健康检查 - 权重1（监控测试）"""
        with self.client.get("/health", 
                             catch_response=True,
                             timeout=10) as response:
            
            if response.status_code == 200:
                try:
                    result = response.json()
                    if result.get('status') == 'healthy' and result.get('model_loaded') is True:
                        response.success()
                    else:
                        response.failure(f"Service unhealthy: {result}")
                except json.JSONDecodeError:
                    response.failure("Invalid JSON response")
            else:
                response.failure(f"Health check failed: {response.status_code}")
    
    def on_stop(self):
        """用户停止时的清理工作"""
        logger.info(f"User stopped. Processed {len(self.images)} images.")


class WebsiteUser(HttpUser):
    """网站用户类 - 测试API文档页面"""
    
    wait_time = between(5, 15)
    weight = 1  # 较低权重
    
    @task
    def view_api_docs(self):
        """访问API文档页面"""
        with self.client.get("/", catch_response=True) as response:
            if response.status_code == 200:
                if "CloudPose" in response.text:
                    response.success()
                else:
                    response.failure("API docs page content invalid")
            else:
                response.failure(f"Failed to load API docs: {response.status_code}")
    
    @task
    def check_metrics(self):
        """检查Prometheus指标"""
        with self.client.get("/metrics", catch_response=True) as response:
            if response.status_code == 200:
                if "cloudpose_" in response.text:
                    response.success()
                else:
                    response.failure("Metrics endpoint invalid")
            else:
                response.failure(f"Failed to load metrics: {response.status_code}")


# 自定义事件处理器
from locust import events

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """测试开始时的处理"""
    logger.info("=" * 60)
    logger.info("CloudPose Load Test Started")
    logger.info(f"Target host: {environment.host}")
    logger.info("=" * 60)

@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """测试结束时的处理"""
    logger.info("=" * 60)
    logger.info("CloudPose Load Test Completed")
    logger.info("=" * 60)

@events.request.add_listener
def on_request_failure(request_type, name, response_time, response_length, exception, **kwargs):
    """记录请求失败事件"""
    if exception:
        logger.error(f"Request failed: {request_type} {name} - {exception}")

# 如果直接运行此脚本
if __name__ == "__main__":
    print("CloudPose Locust Load Test Script")
    print("Please run with: locust -f locustfile.py --host=http://localhost:8000")
    print("Or use the run_experiments.py script for automated testing.")