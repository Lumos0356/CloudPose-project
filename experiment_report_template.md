# Experiments and Report

**Name:** Yuehuai Zhang 
**Student Number:** 35523271 

---

## 1. Experiment Results

The table below summarizes the maximum number of concurrent users the system can handle with 100% success rate and the corresponding average response time, tested under different numbers of pods in the Kubernetes cluster. Two environments were compared: ECS Master Node and Local PC.

### Table 1: Experiment Results

| # of Pods | ECS Master Node Max Users | ECS Master Node Avg. Response Time (ms) | Local PC Max Users | Local PC Avg. Response Time (ms) |
| --------- | ------------------------- | --------------------------------------- | ------------------ | -------------------------------- |
| 1         | 15                        | 4701.62                                 | 17                 | 1448.63                          |
| 2         | 30                        | 171.41                                  | 22                 | 517.21                           |
| 3         | 30                        | 105.53                                  | 38                 | 845.25                           |
| 4         | 19                        | 257.21                                  | 36                 | 342.77                           |

---

## 2. Observations and Analysis

### 2.1 ECS Master Node
- When increasing from **1 pod to 2 pods**, maximum concurrent users doubled (15 → 30) and response time dropped drastically from **4701.62 ms** to **171.41 ms**.  
- **2 to 3 pods** showed marginal improvement in response time (171.41 → 105.53 ms) but no increase in max users, suggesting CPU/memory limits or network saturation became the bottleneck.  
- Increasing to **4 pods** unexpectedly reduced the max users to 19 and increased response time to 257.21 ms, which may indicate overhead from inter-pod coordination or resource contention on the master node.

### 2.2 Local PC
- Initial increase from **1 to 2 pods** improved response time significantly (1448.63 → 517.21 ms), though max users increased moderately (17 → 22).  
- From **2 to 3 pods**, the system handled **38 concurrent users** but with increased response time (845.25 ms), possibly due to local hardware limits or network latency during scaling.  
- At **4 pods**, max users slightly decreased (38 → 36), while response time improved to 342.77 ms, suggesting better load distribution but with diminishing returns in scalability.

### 2.3 Cross-Environment Comparison
- ECS Master Node performance was initially worse than Local PC for 1 pod due to possible VM network overhead, but showed better scaling behavior until resource limits were reached.  
- Local PC consistently had lower response times at low pod counts, but ECS scaled better in handling more concurrent users at 2–3 pods.

---

## 3. Conclusions
1. Scaling from 1 to 2 pods yields the most significant performance improvement in both environments.  
2. Beyond 2–3 pods, improvements are marginal or even negative due to resource contention, scheduler overhead, and network limitations.  
3. ECS Master Node handles higher concurrency better at optimal pod counts, but suffers performance degradation when over-scaled.

---

## 4. Distributed Systems Challenges and Examples

### Challenge 1: **Load Balancing**
- **Example in project:** Kubernetes Service evenly distributes requests to pods, improving response time up to 3 pods. Over-scaling to 4 pods increased coordination overhead, reducing efficiency.

### Challenge 2: **Resource Management**
- **Example in project:** CPU and memory limits per pod influenced scaling effectiveness. At 3 pods, resource utilization reached optimal balance; at 4 pods, contention caused degraded performance.

### Challenge 3: **Network Latency**
- **Example in project:** ECS Master Node initially had higher latency than Local PC due to cloud networking layers. Scaling helped mitigate impact, but at higher pod counts network overhead reappeared.

