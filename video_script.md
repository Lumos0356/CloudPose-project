# CloudPose Project Video Demonstration Script

**Video Duration**: Approximately 8 minutes  
**Presenter**: [Your Name]  
**Student ID**: [Your Student ID]  
**Date**: [Recording Date]  

---

## 🎬 Video Structure Overview

1. **Web Service** (2 minutes)
2. **Dockerfile** (1 minute) 
3. **Kubernetes Cluster and Kubernetes Service** (4 minutes)
4. **Locust Script** (1 minute)

---

## 📝 Detailed Demonstration Script

### Part 1: Web Service (0:00-2:00)

**[Camera: Face the camera, show project folder]**

**Narration:**
"Hello everyone, I'm [Your Name], student ID [Your Student ID]. Today I will demonstrate the CloudPose pose detection service project. First, let's examine the Web Service implementation."

**Demonstration Actions:**

1. **Open backend/app.py file** (60 seconds)
   ```
   "This is our Flask backend service source code. Let me briefly explain the program's methodology and overall architecture:
   
   - We use the Flask framework to create RESTful APIs
   - Integrated TensorFlow Lite's MoveNet model for pose detection
   - Provides two main API endpoints:
     * /api/pose_detection: handles base64-encoded images
     * /api/pose_estimation_image: handles multipart/form-data format images
   
   The Web Service creation adopts a microservices architecture pattern, defining API endpoints through Flask's route decorators,
   using OpenCV for image processing and TensorFlow Lite for inference computation.
   
   Prometheus monitoring is also integrated here for collecting performance metrics."
   ```

2. **Show API endpoints and routing structure** (30 seconds)
   ```
   "As you can see, our routing structure is clear, including health check endpoints, homepage, API documentation page,
   and the core pose detection API. Each endpoint has a clear division of responsibilities."
   ```

3. **Show model loading and inference logic** (30 seconds)
   ```
   "The model is loaded when the application starts, using TensorFlow Lite interpreter for efficient inference.
   Input images are preprocessed before being fed into the model, outputting keypoint coordinates and confidence scores."
   ```

---

### Part 2: Dockerfile (2:00-3:00)

**[Camera: Screen recording, show Dockerfile content]**

**Narration:**
"Next, let me briefly explain our containerization approach."

**Demonstration Actions:**

1. **Open and explain Dockerfile** (60 seconds)
   ```bash
   cat backend/Dockerfile
   ```
   ```
   "Our Dockerfile uses multi-stage builds to optimize image size:
   
   - Base image: Uses python:3.9-slim, providing a lightweight Python environment
   - System dependencies: Installs system libraries required by OpenCV, such as libglib2.0-0, libsm6, etc.
   - Python dependencies: Installs all necessary Python packages through requirements.txt
   - Application code: Copies source code into the container
   - Runtime configuration: Exposes port 5000, sets startup command
   
   This containerization approach ensures consistent application execution across different environments,
   solving the 'it works on my machine' problem."
   ```

---

### Part 3: Kubernetes Cluster and Kubernetes Service (3:00-7:00)

**[Camera: Terminal operations, live demonstration]**

**Narration:**
"Now let me demonstrate the Kubernetes cluster installation, configuration, and deployment process."

**Demonstration Actions:**

1. **Show Docker and Kubernetes versions** (30 seconds)
   ```bash
   docker --version
   kubectl version --client
   ```
   ```
   "The tool versions we're using:
   - Docker: [Show version]
   - Kubernetes: [Show version]
   
   These are current stable production versions, ensuring system reliability."
   ```

2. **Show cluster information and nodes** (45 seconds)
   ```bash
   kubectl cluster-info
   kubectl get nodes -o wide
   ```
   ```
   "This is our Kubernetes cluster information:
   - Control plane running at the specified address
   - Cluster contains [X] nodes
   - Status, role, age, and version information for each node
   
   As you can see, all nodes are in Ready status, and the cluster is running normally."
   ```

3. **Show and explain deployment YAML file** (60 seconds)
   ```bash
   cat k8s-deployment.yaml
   ```
   ```
   "This is our Kubernetes deployment configuration file:
   
   - Deployment configuration: Defines Pod replicas, image, resource limits
   - Resource limits: 0.5 CPU cores, 512MB memory, ensuring reasonable resource allocation
   - Health checks: Configured liveness and readiness probes
   - Image pull policy: Set to IfNotPresent, optimizing deployment speed
   
   This declarative configuration ensures the application's desired state."
   ```

4. **Show service configuration and security group settings** (45 seconds)
   ```bash
   cat service.yaml
   kubectl get services
   ```
   ```
   "Service configuration explanation:
   - Type: NodePort, allowing external access
   - Port mapping: Internal port 5000 mapped to external port 30080
   - Selector: Selects corresponding Pods through labels
   
   Security group configuration allows inbound traffic on port 30080, ensuring the service can be accessed externally.
   This configuration provides a stable external access point in cloud environments."
   ```

5. **Show controller node public IP and security group** (30 seconds)
   ```bash
   kubectl get nodes -o wide
   ```
   ```
   "The controller node's public IP address is: [Show IP address]
   Security group has been configured to allow the following ports:
   - 30080: CloudPose service port
   - 22: SSH access port
   - 6443: Kubernetes API server port"
   ```

6. **Deploy application and verify** (45 seconds)
   ```bash
   kubectl apply -f k8s-deployment.yaml
   kubectl apply -f service.yaml
   kubectl get pods
   kubectl get deployments
   ```
   ```
   "Now deploying our application:
   - Apply deployment configuration files
   - Check Pod status: we can see Pods are starting up
   - Wait for Pods to become Running status
   
   Deployment successful! All Pods are in Running status."
   ```

7. **Verify load balancer functionality** (45 seconds)
   ```bash
   curl http://[public-IP]:30080/health
   curl http://[public-IP]:30080/
   kubectl get endpoints
   ```
   ```
   "Verify if the load balancer works as expected:
   - Health check endpoint returns normal status
   - Homepage can be accessed normally
   - Endpoints show service correctly mapped to Pod IPs
   
   Load balancer is working properly, requests are automatically distributed to different Pod instances."
   ```

---

### Part 4: Locust Script (7:00-8:00)

**[Camera: Show Locust code and quick demonstration]**

**Narration:**
"Finally, let me explain the Locust client and provide a quick demonstration."

**Demonstration Actions:**

1. **Show locustfile.py code** (30 seconds)
   ```bash
   cat locustfile.py
   ```
   ```
   "Our Locust script defines load testing scenarios:
   
   - CloudPoseUser class: Inherits from HttpUser, simulating user behavior
   - Test tasks: Include health checks, homepage access, pose detection API calls
   - Weight configuration: Different tasks have different execution weights
   - Wait time: Simulates real user thinking time
   
   This design can simulate realistic user access patterns."
   ```

2. **Start Locust and quick demonstration** (30 seconds)
   ```bash
   locust -f locustfile.py --host=http://[public-IP]:30080 --headless -u 10 -r 2 -t 30s
   ```
   ```
   "Starting Locust for quick load testing:
   - 10 concurrent users
   - Adding 2 users per second
   - Running for 30 seconds
   
   You can see real-time request statistics: response time, QPS, success rate, and other key metrics.
   This proves our system can handle concurrent loads."
   ```

---

## 🎯 Recording Key Points Reminder

### Technical Preparation
- [ ] Ensure Kubernetes cluster is running normally
- [ ] Pre-build Docker images
- [ ] Test all commands to ensure they work correctly
- [ ] Prepare public IP address information

### Recording Techniques
- [ ] Use screen recording software (such as OBS Studio)
- [ ] Ensure terminal font size is appropriate for viewing
- [ ] Moderate speaking pace, clear pronunciation
- [ ] Allow time for potential network delays

### Demonstration Process
- [ ] Follow script sequence, avoid jumping around
- [ ] Provide clear explanations for each step
- [ ] Show actual command execution and results
- [ ] Highlight key technical points

### Contingency Plans
- [ ] Have backup demonstration data if commands fail
- [ ] Prepare pre-generated screenshots as backup
- [ ] Use local deployment demonstration if network issues occur

---

## 📋 Checklist

Pre-recording confirmation:
- [ ] All code files are prepared
- [ ] Kubernetes cluster is accessible
- [ ] Related tools are installed
- [ ] Recording equipment and software tested
- [ ] Demonstration script is well-practiced

Post-recording confirmation:
- [ ] Video duration is around 8 minutes
- [ ] Audio is clear with no noise
- [ ] Screen content is clearly visible
- [ ] All demonstration steps are completed
- [ ] Key results are shown

---

**Wishing you a successful recording!** 🎬

Remember, this video should not only showcase technical implementation but also demonstrate your understanding of distributed systems, containerization technology, and load testing. Through clear demonstration and analysis, showcase your technical capabilities and project achievements.