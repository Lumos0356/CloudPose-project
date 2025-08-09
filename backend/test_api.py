#!/usr/bin/env python3
"""
CloudPose API测试脚本
"""

import base64
import json
import requests
import sys
import os

def test_health_check():
    """测试健康检查接口"""
    print("Testing health check endpoint...")
    try:
        response = requests.get('http://127.0.0.1:8000/health')
        print(f"Status Code: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Health check failed: {e}")
        return False

def test_pose_detection():
    """测试姿态检测接口"""
    print("\nTesting pose detection endpoint...")
    
    # 读取测试图像
    image_path = '../model2-movenet/test.jpg'
    if not os.path.exists(image_path):
        print(f"Test image not found: {image_path}")
        return False
    
    try:
        # 读取并编码图像
        with open(image_path, 'rb') as f:
            img_data = base64.b64encode(f.read()).decode()
        
        # 发送请求
        payload = {
            'image': img_data,
            'id': 'test_001'
        }
        
        response = requests.post(
            'http://127.0.0.1:8000/api/pose_detection',
            json=payload,
            headers={'Content-Type': 'application/json'}
        )
        
        print(f"Status Code: {response.status_code}")
        result = response.json()
        
        if response.status_code == 200:
            print(f"Success! Detected {len(result.get('keypoints', []))} keypoints")
            print(f"Response ID: {result.get('id')}")
            print(f"Status: {result.get('status')}")
            
            # 显示前3个关键点作为示例
            keypoints = result.get('keypoints', [])
            if keypoints:
                print("\nFirst 3 keypoints (y, x, confidence):")
                for i, kp in enumerate(keypoints[:3]):
                    print(f"  Keypoint {i}: {kp}")
        else:
            print(f"Error: {json.dumps(result, indent=2)}")
            
        return response.status_code == 200
        
    except Exception as e:
        print(f"Pose detection test failed: {e}")
        return False

def test_invalid_request():
    """测试无效请求处理"""
    print("\nTesting invalid request handling...")
    
    try:
        # 测试缺少参数
        response = requests.post(
            'http://127.0.0.1:8000/api/pose_detection',
            json={'image': 'invalid_base64'},
            headers={'Content-Type': 'application/json'}
        )
        
        print(f"Status Code: {response.status_code}")
        result = response.json()
        print(f"Response: {json.dumps(result, indent=2)}")
        
        return response.status_code == 400
        
    except Exception as e:
        print(f"Invalid request test failed: {e}")
        return False

if __name__ == '__main__':
    print("CloudPose API Test Suite")
    print("=" * 40)
    
    # 运行测试
    tests = [
        ("Health Check", test_health_check),
        ("Pose Detection", test_pose_detection),
        ("Invalid Request", test_invalid_request)
    ]
    
    passed = 0
    total = len(tests)
    
    for test_name, test_func in tests:
        print(f"\n[{test_name}]")
        if test_func():
            print(f"✅ {test_name} PASSED")
            passed += 1
        else:
            print(f"❌ {test_name} FAILED")
    
    print(f"\n=" * 40)
    print(f"Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed!")
        sys.exit(0)
    else:
        print("⚠️  Some tests failed")
        sys.exit(1)