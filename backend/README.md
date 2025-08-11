# CloudPose Backend Service

A Flask-based human pose detection API service that uses the MoveNet deep learning model to provide real-time pose analysis capabilities.

## Features

- 🎯 **Pose Detection**: Uses MoveNet model to detect 17 human body keypoints
- 🚀 **RESTful API**: Standard HTTP interface with JSON format support
- 📊 **Health Monitoring**: Provides service status and model loading status checks
- 🛡️ **Error Handling**: Comprehensive exception handling and error responses
- 📖 **API Documentation**: Built-in interface documentation page

## Installation

```bash
# Install Python dependencies
pip install -r requirements.txt
```

## Starting the Service

### Development Environment

```bash
# Method 1: Using startup script
python run.py

# Method 2: Running Flask application directly
python app.py
```

### Production Environment

```bash
# Deploy using gunicorn
gunicorn -w 4 -b 0.0.0.0:8000 app:app
```

## API Endpoints

### 1. Pose Detection

**Endpoint**: `POST /api/pose_detection`

**Request Example**:
```json
{
  "image": "base64-encoded image data",
  "id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response Example**:
```json
{
  "status": "success",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "keypoints": [
    [0.45, 0.32, 0.89],
    [0.43, 0.31, 0.92],
    ...
  ]
}
```

### 2. Health Check

**Endpoint**: `GET /health`

**Response Example**:
```json
{
  "status": "healthy",
  "model_loaded": true,
  "timestamp": "2024-01-08T10:30:00"
}
```

### 3. API Documentation

**Endpoint**: `GET /`

Visit `http://localhost:8000/` to view the complete API documentation.

## Keypoint Description

The MoveNet model returns 17 human body keypoints, each keypoint contains three values `[y, x, confidence]`:

```
0: nose          1: left_eye       2: right_eye
3: left_ear      4: right_ear      5: left_shoulder
6: right_shoulder 7: left_elbow     8: right_elbow
9: left_wrist    10: right_wrist   11: left_hip
12: right_hip    13: left_knee     14: right_knee
15: left_ankle   16: right_ankle
```

## Error Handling

The service provides detailed error information:

- `400 Bad Request`: Request parameter error
- `500 Internal Server Error`: Server internal error
- `503 Service Unavailable`: Model not loaded

## Test Client

You can use the `cloudpose_client.py` in the project root directory to test the API:

```bash
# Run from project root directory
python cloudpose_client.py inputfolder/ http://localhost:8000/api/pose_detection 4
```

## Project Structure

```
backend/
├── app.py              # Flask main application
├── run.py              # Startup script
├── requirements.txt    # Python dependencies
└── README.md          # Documentation
```

## Technology Stack

- **Web Framework**: Flask 2.3.3
- **AI Model**: TensorFlow Lite 2.13.0
- **Image Processing**: OpenCV 4.8.1, Pillow 10.0.1
- **Numerical Computing**: NumPy 1.24.3
- **Production Deployment**: Gunicorn 21.2.0

## Notes

1. Ensure the `../model2-movenet/movenet-full-256.tflite` model file exists
2. Service runs on `http://localhost:8000` by default
3. Image data needs to be base64 encoded
4. Supports JPG and PNG format images
5. Recommended image size should not exceed 2MB