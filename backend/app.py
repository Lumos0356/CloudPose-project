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

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Prometheus monitoring metrics
REQUEST_COUNT = Counter('cloudpose_requests_total', 'Total requests', ['method', 'endpoint'])
REQUEST_DURATION = Histogram('cloudpose_request_duration_seconds', 'Request duration')
POSE_DETECTION_COUNT = Counter('cloudpose_pose_detections_total', 'Total pose detections')
ERROR_COUNT = Counter('cloudpose_errors_total', 'Total errors', ['error_type'])

# Global variables for model storage
interpreter = None
model_loaded = False
model_lock = threading.Lock()  # Thread lock to protect model access

# MoveNet keypoint names
KEYPOINT_NAMES = [
    'nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear',
    'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
    'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
    'left_knee', 'right_knee', 'left_ankle', 'right_ankle'
]

# Skeleton connection definitions
CONNECTIONS = [
    (5, 6), (5, 11), (6, 12), (11, 12),  # Torso
    (5, 7), (6, 8), (7, 9), (8, 10),    # Arms
    (11, 13), (12, 14), (13, 15), (14, 16)  # Legs
]

# Color definitions (BGR format)
KEYPOINT_COLOR = (0, 255, 0)  # Green
CONNECTION_COLOR = (255, 0, 0)  # Blue
BOX_COLOR = (0, 0, 255)  # Red

def load_model():
    """Load MoveNet model"""
    global interpreter, model_loaded
    try:
        # Prioritize environment variable, otherwise use default container path
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
    """Decode base64 image data"""
    try:
        # Remove possible data URL prefix
        if ',' in base64_string:
            base64_string = base64_string.split(',')[1]
        
        # Decode base64
        image_data = base64.b64decode(base64_string)
        
        # Convert to PIL image
        image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB format
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # Convert to numpy array
        image_array = np.array(image)
        
        return image_array
    except Exception as e:
        logger.error(f"Failed to decode base64 image: {e}")
        return None

def encode_image_to_base64(image_array):
    """Encode image array to base64 string"""
    try:
        # Convert to PIL image
        image = Image.fromarray(image_array.astype(np.uint8))
        
        # Save to byte stream
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG', quality=95)
        
        # Encode to base64
        image_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
        
        return image_base64
    except Exception as e:
        logger.error(f"Failed to encode image to base64: {e}")
        return None

def detect_persons(image_array):
    """Detect persons in image and return bounding boxes"""
    # Simple person detection implementation (based on keypoint visibility)
    # In real applications, specialized person detection models can be used
    height, width = image_array.shape[:2]
    
    # Perform pose detection to get keypoints
    keypoints = predict_pose_single(image_array)
    
    persons = []
    if keypoints and len(keypoints) > 0:
        # keypoints is a 17x3 list, each element is [y, x, confidence]
        # Calculate bounding box
        visible_points = []
        confidence_scores = []
        
        for i, kp in enumerate(keypoints):
            try:
                # Ensure kp is a list with 3 elements
                if isinstance(kp, list) and len(kp) >= 3:
                    confidence = float(kp[2]) if not isinstance(kp[2], list) else float(kp[2][0]) if kp[2] else 0.0
                    if confidence > 0.3:  # Check confidence
                        x_coord = float(kp[1]) if not isinstance(kp[1], list) else float(kp[1][0]) if kp[1] else 0.0
                        y_coord = float(kp[0]) if not isinstance(kp[0], list) else float(kp[0][0]) if kp[0] else 0.0
                        x = x_coord * width  # x coordinate
                        y = y_coord * height  # y coordinate
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
            
            # Add margin
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
    """Perform single-person pose detection using MoveNet model"""
    global interpreter, model_lock
    
    if not model_loaded or interpreter is None:
        raise Exception("Model not loaded")
    
    # Use thread lock to protect the entire inference process
    with model_lock:
        try:
            # Get input and output details
            input_details = interpreter.get_input_details()
            output_details = interpreter.get_output_details()
            
            # Get input size
            input_shape = input_details[0]['shape'][1:3]  # [height, width]
            
            # Resize image
            resized_image = cv2.resize(image_array, (input_shape[1], input_shape[0]))
            
            # Normalize to [0,1]
            input_data = np.expand_dims(resized_image, axis=0).astype(np.float32) / 255.0
            
            # Execute inference
            interpreter.set_tensor(input_details[0]['index'], input_data)
            interpreter.invoke()
            
            # Get keypoint output and immediately copy data to avoid memory reference issues
            keypoints_output = interpreter.get_tensor(output_details[0]['index']).copy()
            keypoints = keypoints_output[0]  # Shape: (17, 3) - [y, x, confidence]
            
            # Convert to list format
            keypoints_list = keypoints.tolist()
            
            return keypoints_list
            
        except Exception as e:
            logger.error(f"Pose prediction failed: {e}")
            raise

def draw_pose_on_image(image_array, persons):
    """Draw pose keypoints and skeleton connections on image"""
    try:
        # Copy image to avoid modifying original
        annotated_image = image_array.copy()
        height, width = annotated_image.shape[:2]
        
        for person in persons:
            keypoints = person['keypoints']
            box = person['box']
            
            # Draw bounding box
            cv2.rectangle(annotated_image, 
                         (box['x'], box['y']), 
                         (box['x'] + box['width'], box['y'] + box['height']), 
                         BOX_COLOR, 2)
            
            # Draw confidence
            cv2.putText(annotated_image, f"{box['probability']:.2f}", 
                       (box['x'], box['y'] - 10), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, BOX_COLOR, 1)
            
            # Draw skeleton connections
            for connection in CONNECTIONS:
                kp1_idx, kp2_idx = connection
                kp1 = keypoints[kp1_idx]
                kp2 = keypoints[kp2_idx]
                
                # Check keypoint visibility
                if kp1[2] > 0.3 and kp2[2] > 0.3:
                    x1, y1 = int(kp1[1] * width), int(kp1[0] * height)
                    x2, y2 = int(kp2[1] * width), int(kp2[0] * height)
                    cv2.line(annotated_image, (x1, y1), (x2, y2), CONNECTION_COLOR, 2)
            
            # Draw keypoints
            for i, keypoint in enumerate(keypoints):
                if keypoint[2] > 0.3:  # Confidence threshold
                    x, y = int(keypoint[1] * width), int(keypoint[0] * height)
                    cv2.circle(annotated_image, (x, y), 4, KEYPOINT_COLOR, -1)
                    
                    # Optional: add keypoint labels
                    # cv2.putText(annotated_image, str(i), (x+5, y-5), 
                    #            cv2.FONT_HERSHEY_SIMPLEX, 0.3, KEYPOINT_COLOR, 1)
        
        return annotated_image
        
    except Exception as e:
        logger.error(f"Failed to draw pose on image: {e}")
        return image_array

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    REQUEST_COUNT.labels(method='GET', endpoint='/health').inc()
    
    try:
        # Get system resource information
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
    """Pose detection API endpoint - returns JSON data"""
    REQUEST_COUNT.labels(method='POST', endpoint='/api/pose_detection').inc()
    
    start_time = time.time()
    preprocess_time = 0
    inference_time = 0
    postprocess_time = 0
    
    try:
        # Validate request content type
        if not request.is_json:
            ERROR_COUNT.labels(error_type='invalid_content_type').inc()
            return jsonify({
                'status': 'error',
                'message': 'Content-Type must be application/json'
            }), 400
        
        # Get request data
        data = request.get_json()
        
        # Validate required parameters
        if not data or 'image' not in data or 'id' not in data:
            ERROR_COUNT.labels(error_type='missing_parameters').inc()
            return jsonify({
                'status': 'error',
                'message': 'Required parameters "image" and "id" are missing'
            }), 400
        
        image_data = data['image']
        request_id = data['id']
        
        # Validate parameter types
        if not isinstance(image_data, str) or not isinstance(request_id, str):
            ERROR_COUNT.labels(error_type='invalid_parameter_type').inc()
            return jsonify({
                'status': 'error',
                'message': 'Parameters "image" and "id" must be strings'
            }), 400
        
        # Check if model is loaded
        if not model_loaded:
            ERROR_COUNT.labels(error_type='model_not_loaded').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Model not loaded'
            }), 503
        
        # Preprocessing stage
        preprocess_start = time.time()
        
        # Decode image
        image_array = decode_base64_image(image_data)
        if image_array is None:
            ERROR_COUNT.labels(error_type='invalid_image').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Invalid image format or corrupted data'
            }), 400
        
        preprocess_time = time.time() - preprocess_start
        
        # Inference stage
        inference_start = time.time()
        
        # Detect persons
        persons = detect_persons(image_array)
        
        inference_time = time.time() - inference_start
        
        # Postprocessing stage
        postprocess_start = time.time()
        
        # Format response data
        boxes = [person['box'] for person in persons]
        keypoints = [person['keypoints'] for person in persons]
        count = len(persons)
        
        postprocess_time = time.time() - postprocess_start
        
        # Record successful pose detection
        POSE_DETECTION_COUNT.inc()
        
        # Record request duration
        REQUEST_DURATION.observe(time.time() - start_time)
        
        # Return success response
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
        
        # Get request ID (if possible)
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
    """Pose detection image API endpoint - returns annotated image"""
    REQUEST_COUNT.labels(method='POST', endpoint='/api/pose_estimation_image').inc()
    
    start_time = time.time()
    preprocess_time = 0
    inference_time = 0
    postprocess_time = 0
    
    try:
        # Validate request content type
        if not request.is_json:
            ERROR_COUNT.labels(error_type='invalid_content_type').inc()
            return jsonify({
                'status': 'error',
                'message': 'Content-Type must be application/json'
            }), 400
        
        # Get request data
        data = request.get_json()
        
        # Validate required parameters
        if not data or 'image' not in data or 'id' not in data:
            ERROR_COUNT.labels(error_type='missing_parameters').inc()
            return jsonify({
                'status': 'error',
                'message': 'Required parameters "image" and "id" are missing'
            }), 400
        
        image_data = data['image']
        request_id = data['id']
        
        # Validate parameter types
        if not isinstance(image_data, str) or not isinstance(request_id, str):
            ERROR_COUNT.labels(error_type='invalid_parameter_type').inc()
            return jsonify({
                'status': 'error',
                'message': 'Parameters "image" and "id" must be strings'
            }), 400
        
        # Check if model is loaded
        if not model_loaded:
            ERROR_COUNT.labels(error_type='model_not_loaded').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Model not loaded'
            }), 503
        
        # Preprocessing stage
        preprocess_start = time.time()
        
        # Decode image
        image_array = decode_base64_image(image_data)
        if image_array is None:
            ERROR_COUNT.labels(error_type='invalid_image').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Invalid image format or corrupted data'
            }), 400
        
        preprocess_time = time.time() - preprocess_start
        
        # Inference stage
        inference_start = time.time()
        
        # Detect persons
        persons = detect_persons(image_array)
        
        inference_time = time.time() - inference_start
        
        # Postprocessing stage
        postprocess_start = time.time()
        
        # Draw pose on image
        annotated_image = draw_pose_on_image(image_array, persons)
        
        # Encode to base64
        annotated_image_base64 = encode_image_to_base64(annotated_image)
        if annotated_image_base64 is None:
            ERROR_COUNT.labels(error_type='image_encoding_failed').inc()
            return jsonify({
                'status': 'error',
                'id': request_id,
                'message': 'Failed to encode annotated image'
            }), 500
        
        postprocess_time = time.time() - postprocess_start
        
        # Record successful pose detection
        POSE_DETECTION_COUNT.inc()
        
        # Record request duration
        REQUEST_DURATION.observe(time.time() - start_time)
        
        # Return success response
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
        
        # Get request ID (if possible)
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
    """Prometheus monitoring metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/', methods=['GET'])
def api_documentation():
    """API documentation page"""
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
        <h1 class="header">CloudPose Pose Detection API v2.0</h1>
        
        <div class="endpoint">
            <h2><span class="method">POST</span> /api/pose_detection</h2>
            <p>Perform human pose detection, return person count, bounding boxes, keypoints and processing time statistics</p>
            
            <h3>Request Parameters:</h3>
            <div class="code">
                <pre>{
  "image": "base64 encoded image data",
  "id": "unique request identifier"
}</pre>
            </div>
            
            <h3>Response Example:</h3>
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
            <p>Perform human pose detection, return annotated base64 encoded image</p>
            
            <h3>Request Parameters:</h3>
            <div class="code">
                <pre>{
  "image": "base64 encoded image data",
  "id": "unique request identifier"
}</pre>
            </div>
            
            <h3>Response Example:</h3>
            <div class="code">
                <pre>{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "annotated_image": "base64 encoded annotated image",
  "speed_preprocess": 0.012,
  "speed_inference": 0.045,
  "speed_postprocess": 0.008
}</pre>
            </div>
        </div>
        
        <div class="endpoint">
            <h2><span class="method">GET</span> /health</h2>
            <p>Check service health status and system resources</p>
            
            <h3>Response Example:</h3>
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
            <p>Prometheus monitoring metrics endpoint</p>
        </div>
        
        <div class="endpoint">
            <h2>Keypoint Description</h2>
            <p>MoveNet model returns 17 human body keypoints, each keypoint contains three values [y, x, confidence]:</p>
            <div class="code">
                <pre>0: nose, 1: left_eye, 2: right_eye, 3: left_ear, 4: right_ear
5: left_shoulder, 6: right_shoulder, 7: left_elbow, 8: right_elbow
9: left_wrist, 10: right_wrist, 11: left_hip, 12: right_hip
13: left_knee, 14: right_knee, 15: left_ankle, 16: right_ankle</pre>
            </div>
        </div>
        
        <div class="endpoint">
            <h2>Bounding Box Format</h2>
            <p>Each detected person has a bounding box containing the following fields:</p>
            <div class="code">
                <pre>{
  "x": top-left x coordinate,
  "y": top-left y coordinate,
  "width": width,
  "height": height,
  "probability": confidence (0-1)
}</pre>
            </div>
        </div>
    </body>
    </html>
    """
    return doc_html

if __name__ == '__main__':
    # Load model at startup
    logger.info("Starting CloudPose API server v2.0...")
    if load_model():
        logger.info("Model loaded successfully, starting server")
    else:
        logger.warning("Model loading failed, server will start but pose detection will not work")
    
    # Start Flask application
    app.run(host='0.0.0.0', port=8000, debug=True)