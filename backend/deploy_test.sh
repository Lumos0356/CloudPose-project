#!/bin/bash

# CloudPose Deployment Verification Script
# Used to test fixed Docker configuration

set -e

echo "=== CloudPose Deployment Verification Script ==="
echo "Checking if required files exist..."

# Check required files
required_files=(
    "../model2-movenet/movenet-full-256.tflite"
    "app.py"
    "run.py"
    "requirements.txt"
    "Dockerfile"
    "docker-compose.yml"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file does not exist"
        exit 1
    fi
done

echo ""
echo "Starting Docker image build..."
docker-compose build

if [ $? -eq 0 ]; then
    echo "✓ Docker image build successful"
else
    echo "✗ Docker image build failed"
    exit 1
fi

echo ""
echo "Starting service..."
docker-compose up -d

if [ $? -eq 0 ]; then
    echo "✓ Service started successfully"
else
    echo "✗ Service startup failed"
    exit 1
fi

echo ""
echo "Waiting for service to be ready..."
sleep 10

echo "Testing health check endpoint..."
health_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health)

if [ "$health_response" = "200" ]; then
    echo "✓ Health check passed (HTTP $health_response)"
else
    echo "✗ Health check failed (HTTP $health_response)"
    echo "Viewing container logs:"
    docker-compose logs cloudpose-api
    exit 1
fi

echo ""
echo "Testing pose detection endpoint..."
test_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"image_data": "test"}' \
    http://localhost:8000/pose_detection)

if [ "$test_response" = "400" ] || [ "$test_response" = "200" ]; then
    echo "✓ Pose detection endpoint responding normally (HTTP $test_response)"
else
    echo "✗ Pose detection endpoint abnormal (HTTP $test_response)"
fi

echo ""
echo "=== Deployment Verification Complete ==="
echo "Service status:"
docker-compose ps

echo ""
echo "To stop the service, run: docker-compose down"
echo "To view logs, run: docker-compose logs -f cloudpose-api"
echo "Service address: http://localhost:8000"
echo "Health check: http://localhost:8000/health"