from flask import Flask, request, jsonify
import json
import base64
import io
import logging
import time
from PIL import Image
import numpy as np
import tensorflow.lite as tflite
import cv2
import os
import traceback
from datetime import datetime
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import psutil
import threading

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Prometheus监控指标
REQUEST_COUNT = Counter('cloudpose_requests_total', 'Total requests', ['method', 'endpoint'])
REQUEST_DURATION = Histogram('cloudpose_request_duration_seconds', 'Request duration')
POSE_DETECTION_COUNT = Counter('cloudpose_pose_detections_total', 'Total pose detections')
ERROR_COUNT = Counter('cloudpose_errors_total', 'Total errors', ['error_type'])

# 全局变量存储模型
interpreter = None
model_loaded = False
model_lock = threading.Lock()  # 线程锁保护模型访问

# MoveNet关键点名称
KEYPOINT_NAMES = [
    'nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear',
    'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
    'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
    'left_knee', 'right_knee', 'left_ankle', 'right_ankle'
]

# 骨骼连接定义
CONNECTIONS = [
    (5, 6), (5, 11), (6, 12), (11, 12),  # 躯干
    (5, 7), (6, 8), (7, 9), (8, 10),    # 手臂
    (11, 13), (12, 14), (13, 15), (14, 16)  # 腿部
]

# 颜色定义（BGR格式）
KEYPOINT_COLOR = (0, 255, 0)  # 绿色
CONNECTION_COLOR = (255, 0, 0)  # 蓝色
BOX_COLOR = (0, 0, 255)  # 红色

def load_model():
    """加载MoveNet模型"""
    global interpreter, model_loaded
    try:
        # 优先使用环境变量，否则使用默认容器路径
        model_path = os.environ.get('MODEL_PATH', '/app/model/movenet-full-256.tflite')
        if not os.path.exists(model_path):
            logger.error(f"Model file not found: {model_path}")
            return False
            
        interpreter = tflite.Interpreter(model_path=model_path)
        interpreter.allocate_tensors()
        model_loaded = True
        logger.info("MoveNet model loaded successfully")
        return True
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        model_loaded = False
        return False

def decode_base64_image(base64_string):
    """解码base64图像数据"""
    try:
        # 移除可能的数据URL前缀
        if ',' in base64_string:
            base64_string = base64_string.split(',')[1]
        
        # 解码base64
        image_data = base64.b64decode(base64_string)
        
        # 转换为PIL图像
        image = Image.open(io.BytesIO(image_data))
        
        # 转换为RGB格式
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # 转换为numpy数组
        image_array = np.array(image)
        
        return image_array
    except Exception as e:
        logger.error(f"Failed to decode base64 image: {e}")
        return None

def encode_image_to_base64(image_array):
    """将图像数组编码为base64字符串"""
    try:
        # 转换为PIL图像
        image = Image.fromarray(image_array.astype(np.uint8))
        
        # 保存到字节流
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG', quality=95)
        
        # 编码为base64
        image_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
        
        return image_base64
    except Exception as e:
        logger.error(f"Failed to encode image to base64: {e}")
        return None

def detect_persons(image_array):
    """检测图像中的人体并返回边界框"""
    # 简单的人体检测实现（基于关键点可见性）
    # 在实际应用中，可以使用专门的人体检测模型
    height, width = image_array.shape[:2]
    
    # 执行姿态检测获取关键点
    keypoints = predict_pose_single(image_array)
    
    persons = []
    if keypoints and len(keypoints) > 0:
        # keypoints是一个17x3的列表，每个元素是[y, x, confidence]
        # 计算边界框
        visible_points = []
        confidence_scores = []
        
        for i, kp in enumerate(keypoints):
            try:
                # 确保kp是列表且有3个元素
                if isinstance(kp, list) and len(kp) >= 3:
                    confidence = float(kp[2]) if not isinstance(kp[2], list) else float(kp[2][0]) if kp[2] else 0.0
                    if confidence > 0.3:  # 检查置信度
                        x_coord = float(kp[1]) if not isinstance(kp[1], list) else float(kp[1][0]) if kp[1] else 0.0
                        y_coord = float(kp[0]) if not isinstance(kp[0], list) else float(kp[0][0]) if kp[0] else 0.0
                        x = x_coord * width  # x坐标
                        y = y_coord * height  # y坐标
                        visible_points.append((x, y))
                        confidence_scores.append(confidence)
            except (TypeError, ValueError, IndexError) as e:
                logger.warning(f"Skipping keypoint {i} due to format error: {e}, kp: {kp}")
                continue
        
        if visible_points:
            x_coords = [p[0] for p in visible_points]
            y_coords = [p[1] for p in visible_points]
            
            x_min, x_max = min(x_coords), max(x_coords)
            y_min, y_max = min(y_coords), max(y_coords)
            
            # 添加边距
            margin = 20
            x_min = max(0, x_min - margin)
            y_min = max(0, y_min - margin)
            x_max = min(width, x_max + margin)
            y_max = min(height, y_max + margin)
            
            box = {
                "x": int(x_min),
                "y": int(y_min),
                "width": int(x_max - x_min),
                "height": int(y_max - y_min),
                "probability": float(np.mean(confidence_scores)) if confidence_scores else 0.0
            }
            
            persons.append({
                "box": box,
                "keypoints": keypoints
            })
    
    return persons

def predict_pose_single(image_array):
    """使用MoveNet模型进行单人姿态检测"""
    global interpreter, model_lock
    
    if not model_loaded or interpreter is None:
        raise Exception("Model not loaded")
    
    # 使用线程锁保护整个推理过程
    with model_lock:
        try:
            # 获取输入输出详情
            input_details = interpreter.get_input_details()
            output_details = interpreter.get_output_details()
            
            # 获取输入尺寸
            input_shape = input_details[0]['shape'][1:3]  # [height, width]
            
            # 调整图像尺寸
            resized_image = cv2.resize(image_array, (input_shape[1], input_shape[0]))
            
            # 归一化到[0,1]
            input_data = np.expand_dims(resized_image, axis=0).astype(np.float32) / 255.0
            
            # 执行推理
            interpreter.set_tensor(input_details[0]['index'], input_data)
            interpreter.invoke()
            
            # 获取关键点输出并立即复制数据以避免内存引用问题
            keypoints_output = interpreter.get_tensor(output_details[0]['index']).copy()
            keypoints = keypoints_output[0]  # Shape: (17, 3) - [y, x, confidence]
            
            # 转换为列表格式
            keypoints_list = keypoints.tolist()
            
            return keypoints_list
            
        except Exception as e:
            logger.error(f"Pose prediction failed: {e}")
            raise

def draw_pose_on_image(image_array, persons):
    """在图像上绘制姿态关键点和骨骼连接"""
    try:
        # 复制图像以避免修改原图
        annotated_image = image_array.copy()
        height, width = annotated_image.shape[:2]
        
        for person in persons:
            keypoints = person['keypoints']
            box = person['box']
            
            # 绘制边界框
            cv2.rectangle(annotated_image, 
                         (box['x'], box['y']), 
                         (box['x'] + box['width'], box['y'] + box['height']), 
                         BOX_COLOR, 2)
            
            # 绘制置信度
            cv2.putText(annotated_image, f"{box['probability']:.2f}", 
                       (box['x'], box['y'] - 10), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, BOX_COLOR, 1)
            
            # 绘制骨骼连接
            for connection in CONNECTIONS:
                kp1_idx, kp2_idx = connection
                kp1 = keypoints[kp1_idx]
                kp2 = keypoints[kp2_idx]
                
                # 检查关键点可见性
                if kp1[2] > 0.3 and kp2[2] > 0.3:
                    x1, y1 = int(kp1[1] * width), int(kp1[0] * height)
                    x2, y2 = int(kp2[1] * width), int(kp2[0] * height)
                    cv2.line(annotated_image, (x1, y1), (x2, y2), CONNECTION_COLOR, 2)
            
            # 绘制关键点
            for i, keypoint in enumerate(keypoints):
                if keypoint[2] > 0.3:  # 置信度阈值
                    x, y = int(keypoint[1] * width), int(keypoint[0] * height)
                    cv2.circle(annotated_image, (x, y), 4, KEYPOINT_COLOR, -1)
                    
                    # 可选：添加关键点标签
                    # cv2.putText(annotated_image, str(i), (x+5, y-5), 
                    #            cv2.FONT_HERSHEY_SIMPLEX, 0.3, KEYPOINT_COLOR, 1)
        
        return annotated_image
        
    except Exception as e:
        logger.error(f"Failed to draw pose on image: {e}")
        return image_array

@app.route('/health', methods=['GET'])
def health_check():
    """健康检查接口"""
    REQUEST_COUNT.labels(method='GET', endpoint='/health').inc()
    
    try:
        # 获取系统资源信息
        cpu_percent = psutil.cpu_percent()
        memory = psutil.virtual_memory()
        
        return jsonify({
            'status': 'healthy' if model_loaded else 'unhealthy',
            'model_loaded': model_loaded,
            'timestamp': datetime.now().isoformat(),
            'system': {
                'cpu_percent': cpu_percent,
                'memory_percent': memory.percent,
                'memory_available': memory.available
            }
        }), 200
    except Exception as e:
        ERROR_COUNT.labels(error_type='health_check').inc()
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'model_loaded': False,
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/api/pose_detection', methods=['POST'])
def pose_detection():
    """姿态检测API接口 - 返回JSON数据"""
    REQUEST_COUNT.labels(method='POST', endpoint='/api/pose_detection').inc()
    
    start_time = time.time()
    preprocess_time = 0
    inference_time = 0
    postprocess_time = 0
    
    try:
        # 验证请求内容类型
        if not request.is_json:
            ERROR_COUNT.labels(error_type='invalid_content_type').inc()
            return jsonify({
                'status': 'error',
                'message': 'Content-Type must be application/json'
            }), 400
        
        # 获取请求数据
        data = request.get_json()
        
        # 验证必需参数
        if not data or 'image' not in data or 'id' not in data:
            ERROR_COUNT.labels(error_type='missing_parameters').inc()
            return jsonify({
                'status': 'error',
                'message': 'Required parameters "image" and "id" are missing'
            }), 400
        
        image_data = data['image']
        request_id = data['id']
        
        # 验证参数类型
        if not isinstance(image_data, str) or not isinstance(request_id, str):
            ERROR_COUNT.labels(error_type='invalid_parameter_type').inc()
            return jsonify({
                'status': 'error',
                'message': 'Parameters "image" and "id" must be strings'
            }), 400
        
        # 检查模型是否已加载
        if not model_loaded:
            ERROR_COUNT.labels(error_type='model_not_loaded').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Model not loaded'
            }), 503
        
        # 预处理阶段
        preprocess_start = time.time()
        
        # 解码图像
        image_array = decode_base64_image(image_data)
        if image_array is None:
            ERROR_COUNT.labels(error_type='invalid_image').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Invalid image format or corrupted data'
            }), 400
        
        preprocess_time = time.time() - preprocess_start
        
        # 推理阶段
        inference_start = time.time()
        
        # 检测人体
        persons = detect_persons(image_array)
        
        inference_time = time.time() - inference_start
        
        # 后处理阶段
        postprocess_start = time.time()
        
        # 格式化响应数据
        boxes = [person['box'] for person in persons]
        keypoints = [person['keypoints'] for person in persons]
        count = len(persons)
        
        postprocess_time = time.time() - postprocess_start
        
        # 记录成功的姿态检测
        POSE_DETECTION_COUNT.inc()
        
        # 记录请求持续时间
        REQUEST_DURATION.observe(time.time() - start_time)
        
        # 返回成功响应
        return jsonify({
            'id': request_id,
            'count': count,
            'boxes': boxes,
            'keypoints': keypoints,
            'speed_preprocess': round(preprocess_time, 6),
            'speed_inference': round(inference_time, 6),
            'speed_postprocess': round(postprocess_time, 6)
        }), 200
        
    except Exception as e:
        ERROR_COUNT.labels(error_type='internal_error').inc()
        logger.error(f"Pose detection error: {e}")
        logger.error(traceback.format_exc())
        
        # 获取请求ID（如果可能）
        request_id = None
        try:
            data = request.get_json()
            if data and 'id' in data:
                request_id = data['id']
        except:
            pass
        
        response = {
            'status': 'error',
            'message': 'Internal server error during pose detection',
            'speed_preprocess': round(preprocess_time, 6),
            'speed_inference': round(inference_time, 6),
            'speed_postprocess': round(postprocess_time, 6)
        }
        
        if request_id:
            response['id'] = request_id
            
        return jsonify(response), 500

@app.route('/api/pose_estimation_image', methods=['POST'])
def pose_estimation_image():
    """姿态检测图像API接口 - 返回带注释的图像"""
    REQUEST_COUNT.labels(method='POST', endpoint='/api/pose_estimation_image').inc()
    
    start_time = time.time()
    preprocess_time = 0
    inference_time = 0
    postprocess_time = 0
    
    try:
        # 验证请求内容类型
        if not request.is_json:
            ERROR_COUNT.labels(error_type='invalid_content_type').inc()
            return jsonify({
                'status': 'error',
                'message': 'Content-Type must be application/json'
            }), 400
        
        # 获取请求数据
        data = request.get_json()
        
        # 验证必需参数
        if not data or 'image' not in data or 'id' not in data:
            ERROR_COUNT.labels(error_type='missing_parameters').inc()
            return jsonify({
                'status': 'error',
                'message': 'Required parameters "image" and "id" are missing'
            }), 400
        
        image_data = data['image']
        request_id = data['id']
        
        # 验证参数类型
        if not isinstance(image_data, str) or not isinstance(request_id, str):
            ERROR_COUNT.labels(error_type='invalid_parameter_type').inc()
            return jsonify({
                'status': 'error',
                'message': 'Parameters "image" and "id" must be strings'
            }), 400
        
        # 检查模型是否已加载
        if not model_loaded:
            ERROR_COUNT.labels(error_type='model_not_loaded').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Model not loaded'
            }), 503
        
        # 预处理阶段
        preprocess_start = time.time()
        
        # 解码图像
        image_array = decode_base64_image(image_data)
        if image_array is None:
            ERROR_COUNT.labels(error_type='invalid_image').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Invalid image format or corrupted data'
            }), 400
        
        preprocess_time = time.time() - preprocess_start
        
        # 推理阶段
        inference_start = time.time()
        
        # 检测人体
        persons = detect_persons(image_array)
        
        inference_time = time.time() - inference_start
        
        # 后处理阶段
        postprocess_start = time.time()
        
        # 在图像上绘制姿态
        annotated_image = draw_pose_on_image(image_array, persons)
        
        # 编码为base64
        annotated_image_base64 = encode_image_to_base64(annotated_image)
        if annotated_image_base64 is None:
            ERROR_COUNT.labels(error_type='image_encoding_failed').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Failed to encode annotated image'
            }), 500
        
        postprocess_time = time.time() - postprocess_start
        
        # 记录成功的姿态检测
        POSE_DETECTION_COUNT.inc()
        
        # 记录请求持续时间
        REQUEST_DURATION.observe(time.time() - start_time)
        
        # 返回成功响应
        return jsonify({
            'id': request_id,
            'annotated_image': annotated_image_base64,
            'speed_preprocess': round(preprocess_time, 6),
            'speed_inference': round(inference_time, 6),
            'speed_postprocess': round(postprocess_time, 6)
        }), 200
        
    except Exception as e:
        ERROR_COUNT.labels(error_type='internal_error').inc()
        logger.error(f"Pose estimation image error: {e}")
        logger.error(traceback.format_exc())
        
        # 获取请求ID（如果可能）
        request_id = None
        try:
            data = request.get_json()
            if data and 'id' in data:
                request_id = data['id']
        except:
            pass
        
        response = {
            'status': 'error',
            'message': 'Internal server error during pose estimation image',
            'speed_preprocess': round(preprocess_time, 6),
            'speed_inference': round(inference_time, 6),
            'speed_postprocess': round(postprocess_time, 6)
        }
        
        if request_id:
            response['id'] = request_id
            
        return jsonify(response), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus监控指标端点"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/', methods=['GET'])
def api_documentation():
    """API文档页面"""
    REQUEST_COUNT.labels(method='GET', endpoint='/').inc()
    
    doc_html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>CloudPose API Documentation</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
            .header { color: #1e3a8a; border-bottom: 2px solid #10b981; padding-bottom: 10px; }
            .endpoint { background: #f8f9fa; padding: 20px; margin: 20px 0; border-radius: 8px; }
            .method { background: #10b981; color: white; padding: 4px 8px; border-radius: 4px; }
            .code { background: #f1f5f9; padding: 15px; border-radius: 4px; overflow-x: auto; }
            pre { margin: 0; }
        </style>
    </head>
    <body>
        <h1 class="header">CloudPose 姿态检测 API v2.0</h1>
        
        <div class="endpoint">
            <h2><span class="method">POST</span> /api/pose_detection</h2>
            <p>执行人体姿态检测，返回人数、边界框、关键点和处理时间统计</p>
            
            <h3>请求参数:</h3>
            <div class="code">
                <pre>{
  "image": "base64编码的图像数据",
  "id": "请求唯一标识符"
}</pre>
            </div>
            
            <h3>响应示例:</h3>
            <div class="code">
                <pre>{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "count": 2,
  "boxes": [
    {"x": 100, "y": 50, "width": 200, "height": 400, "probability": 0.95}
  ],
  "keypoints": [
    [[0.45, 0.32, 0.89], [0.43, 0.31, 0.92], ...]
  ],
  "speed_preprocess": 0.012,
  "speed_inference": 0.045,
  "speed_postprocess": 0.008
}</pre>
            </div>
        </div>
        
        <div class="endpoint">
            <h2><span class="method">POST</span> /api/pose_estimation_image</h2>
            <p>执行人体姿态检测，返回带注释的base64编码图像</p>
            
            <h3>请求参数:</h3>
            <div class="code">
                <pre>{
  "image": "base64编码的图像数据",
  "id": "请求唯一标识符"
}</pre>
            </div>
            
            <h3>响应示例:</h3>
            <div class="code">
                <pre>{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "annotated_image": "base64编码的带注释图像",
  "speed_preprocess": 0.012,
  "speed_inference": 0.045,
  "speed_postprocess": 0.008
}</pre>
            </div>
        </div>
        
        <div class="endpoint">
            <h2><span class="method">GET</span> /health</h2>
            <p>检查服务健康状态和系统资源</p>
            
            <h3>响应示例:</h3>
            <div class="code">
                <pre>{
  "status": "healthy",
  "model_loaded": true,
  "timestamp": "2024-01-08T10:30:00",
  "system": {
    "cpu_percent": 25.5,
    "memory_percent": 45.2,
    "memory_available": 8589934592
  }
}</pre>
            </div>
        </div>
        
        <div class="endpoint">
            <h2><span class="method">GET</span> /metrics</h2>
            <p>Prometheus监控指标端点</p>
        </div>
        
        <div class="endpoint">
            <h2>关键点说明</h2>
            <p>MoveNet模型返回17个人体关键点，每个关键点包含[y, x, confidence]三个值：</p>
            <div class="code">
                <pre>0: nose, 1: left_eye, 2: right_eye, 3: left_ear, 4: right_ear
5: left_shoulder, 6: right_shoulder, 7: left_elbow, 8: right_elbow
9: left_wrist, 10: right_wrist, 11: left_hip, 12: right_hip
13: left_knee, 14: right_knee, 15: left_ankle, 16: right_ankle</pre>
            </div>
        </div>
        
        <div class="endpoint">
            <h2>边界框格式</h2>
            <p>每个检测到的人体都有一个边界框，包含以下字段：</p>
            <div class="code">
                <pre>{
  "x": 左上角x坐标,
  "y": 左上角y坐标,
  "width": 宽度,
  "height": 高度,
  "probability": 置信度 (0-1)
}</pre>
            </div>
        </div>
    </body>
    </html>
    """
    return doc_html

if __name__ == '__main__':
    # 启动时加载模型
    logger.info("Starting CloudPose API server v2.0...")
    if load_model():
        logger.info("Model loaded successfully, starting server")
    else:
        logger.warning("Model loading failed, server will start but pose detection will not work")
    
    # 启动Flask应用
    app.run(host='0.0.0.0', port=8000, debug=True)