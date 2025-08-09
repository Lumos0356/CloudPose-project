# CloudPose 后端服务

基于Flask的人体姿态检测API服务，使用MoveNet深度学习模型提供实时姿态分析能力。

## 功能特性

- 🎯 **姿态检测**: 使用MoveNet模型检测17个人体关键点
- 🚀 **RESTful API**: 标准的HTTP接口，支持JSON格式
- 📊 **健康监控**: 提供服务状态和模型加载状态检查
- 🛡️ **错误处理**: 完善的异常处理和错误响应
- 📖 **API文档**: 内置的接口文档页面

## 安装依赖

```bash
# 安装Python依赖
pip install -r requirements.txt
```

## 启动服务

### 开发环境

```bash
# 方式1: 使用启动脚本
python run.py

# 方式2: 直接运行Flask应用
python app.py
```

### 生产环境

```bash
# 使用gunicorn部署
gunicorn -w 4 -b 0.0.0.0:8000 app:app
```

## API接口

### 1. 姿态检测

**接口**: `POST /api/pose_detection`

**请求示例**:
```json
{
  "image": "base64编码的图像数据",
  "id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**响应示例**:
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

### 2. 健康检查

**接口**: `GET /health`

**响应示例**:
```json
{
  "status": "healthy",
  "model_loaded": true,
  "timestamp": "2024-01-08T10:30:00"
}
```

### 3. API文档

**接口**: `GET /`

访问 `http://localhost:8000/` 查看完整的API文档。

## 关键点说明

MoveNet模型返回17个人体关键点，每个关键点包含 `[y, x, confidence]` 三个值：

```
0: nose          1: left_eye       2: right_eye
3: left_ear      4: right_ear      5: left_shoulder
6: right_shoulder 7: left_elbow     8: right_elbow
9: left_wrist    10: right_wrist   11: left_hip
12: right_hip    13: left_knee     14: right_knee
15: left_ankle   16: right_ankle
```

## 错误处理

服务提供详细的错误信息：

- `400 Bad Request`: 请求参数错误
- `500 Internal Server Error`: 服务器内部错误
- `503 Service Unavailable`: 模型未加载

## 测试客户端

可以使用项目根目录的 `cloudpose_client.py` 测试API：

```bash
# 从项目根目录运行
python cloudpose_client.py inputfolder/ http://localhost:8000/api/pose_detection 4
```

## 项目结构

```
backend/
├── app.py              # Flask主应用
├── run.py              # 启动脚本
├── requirements.txt    # Python依赖
└── README.md          # 说明文档
```

## 技术栈

- **Web框架**: Flask 2.3.3
- **AI模型**: TensorFlow Lite 2.13.0
- **图像处理**: OpenCV 4.8.1, Pillow 10.0.1
- **数值计算**: NumPy 1.24.3
- **生产部署**: Gunicorn 21.2.0

## 注意事项

1. 确保 `../model2-movenet/movenet-full-256.tflite` 模型文件存在
2. 服务默认运行在 `http://localhost:8000`
3. 图像数据需要base64编码
4. 支持JPG和PNG格式图像
5. 建议图像尺寸不超过2MB