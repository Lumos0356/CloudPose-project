#!/usr/bin/env python3
"""
CloudPose 自动化实验脚本
自动执行不同pod数量(1,2,4,8)的负载测试，收集性能数据并生成报告

使用方法:
    # 本地测试
    python run_experiments.py --host http://localhost:8000 --mode local
    
    # Kubernetes集群测试
    python run_experiments.py --host http://your-k8s-cluster-ip:30080 --mode k8s
    
    # 自定义测试
    python run_experiments.py --host http://localhost:8000 --pods 1,2,4 --users 10,20,50
"""

import argparse
import json
import os
import subprocess
import sys
import time
import csv
from datetime import datetime
from pathlib import Path
import signal
import threading

class ExperimentRunner:
    """实验运行器"""
    
    def __init__(self, host, mode='local'):
        self.host = host
        self.mode = mode
        self.results = []
        self.experiment_dir = Path(f"experiments_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
        self.experiment_dir.mkdir(exist_ok=True)
        
        # 实验配置
        self.pod_configs = [1, 2, 4, 8] if mode == 'k8s' else [1]
        self.user_configs = [10, 20, 50, 100] if mode == 'k8s' else [5, 10, 20]
        self.test_duration = 300  # 5分钟
        self.spawn_rate = 5
        
        print(f"实验模式: {mode}")
        print(f"目标主机: {host}")
        print(f"结果目录: {self.experiment_dir}")
    
    def check_prerequisites(self):
        """检查实验前提条件"""
        print("检查实验前提条件...")
        
        # 检查Locust是否安装
        try:
            result = subprocess.run(['locust', '--version'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                print(f"✓ Locust已安装: {result.stdout.strip()}")
            else:
                print("✗ Locust未正确安装")
                return False
        except (subprocess.TimeoutExpired, FileNotFoundError):
            print("✗ Locust未安装，请运行: pip install locust")
            return False
        
        # 检查locustfile.py
        if not Path('locustfile.py').exists():
            print("✗ locustfile.py不存在")
            return False
        print("✓ locustfile.py存在")
        
        # 检查测试图像
        test_images_dir = Path('test_images')
        if not test_images_dir.exists():
            print("✗ test_images目录不存在，请运行: python prepare_test_images.py")
            return False
        
        image_count = len(list(test_images_dir.glob('*')))
        if image_count < 10:
            print(f"✗ 测试图像不足({image_count}个)，请运行: python prepare_test_images.py")
            return False
        print(f"✓ 测试图像准备就绪({image_count}个)")
        
        # 检查服务可用性
        print(f"检查服务可用性: {self.host}")
        try:
            import requests
            response = requests.get(f"{self.host}/health", timeout=10)
            if response.status_code == 200:
                health_data = response.json()
                if health_data.get('status') == 'healthy':
                    print("✓ CloudPose服务健康")
                else:
                    print(f"✗ CloudPose服务不健康: {health_data}")
                    return False
            else:
                print(f"✗ 健康检查失败: HTTP {response.status_code}")
                return False
        except Exception as e:
            print(f"✗ 无法连接到服务: {e}")
            return False
        
        return True
    
    def run_single_experiment(self, pod_count, user_count, experiment_id):
        """运行单个实验"""
        print(f"\n{'='*60}")
        print(f"实验 {experiment_id}: {pod_count} Pods, {user_count} Users")
        print(f"{'='*60}")
        
        # 如果是Kubernetes模式，需要调整pod数量
        if self.mode == 'k8s' and pod_count > 1:
            print(f"请手动调整Kubernetes deployment的replica数量为 {pod_count}")
            print("命令: kubectl scale deployment cloudpose-deployment --replicas={}".format(pod_count))
            input("调整完成后按Enter继续...")
        
        # 准备输出文件
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = self.experiment_dir / f"experiment_{experiment_id}_{pod_count}pods_{user_count}users_{timestamp}"
        
        # 构建Locust命令
        cmd = [
            'locust',
            '-f', 'locustfile.py',
            '--host', self.host,
            '--users', str(user_count),
            '--spawn-rate', str(self.spawn_rate),
            '--run-time', f'{self.test_duration}s',
            '--headless',
            '--csv', str(output_file),
            '--html', f'{output_file}.html',
            '--logfile', f'{output_file}.log'
        ]
        
        print(f"执行命令: {' '.join(cmd)}")
        print(f"测试时长: {self.test_duration}秒")
        print(f"输出文件: {output_file}.*")
        
        # 运行实验
        start_time = time.time()
        
        try:
            # 启动Locust进程
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            # 实时显示输出
            def print_output(pipe, prefix):
                for line in iter(pipe.readline, ''):
                    if line.strip():
                        print(f"[{prefix}] {line.strip()}")
            
            # 启动输出线程
            stdout_thread = threading.Thread(target=print_output, args=(process.stdout, "OUT"))
            stderr_thread = threading.Thread(target=print_output, args=(process.stderr, "ERR"))
            
            stdout_thread.daemon = True
            stderr_thread.daemon = True
            
            stdout_thread.start()
            stderr_thread.start()
            
            # 等待进程完成
            return_code = process.wait()
            
            end_time = time.time()
            duration = end_time - start_time
            
            if return_code == 0:
                print(f"\n✓ 实验完成，耗时: {duration:.2f}秒")
                
                # 解析结果
                result = self.parse_experiment_result(output_file, pod_count, user_count, experiment_id)
                if result:
                    self.results.append(result)
                    print(f"✓ 结果解析成功")
                    self.print_experiment_summary(result)
                else:
                    print("✗ 结果解析失败")
                
                return True
            else:
                print(f"\n✗ 实验失败，返回码: {return_code}")
                return False
                
        except KeyboardInterrupt:
            print("\n实验被用户中断")
            if 'process' in locals():
                process.terminate()
            return False
        except Exception as e:
            print(f"\n✗ 实验执行错误: {e}")
            return False
    
    def parse_experiment_result(self, output_file, pod_count, user_count, experiment_id):
        """解析实验结果"""
        try:
            # 读取统计文件
            stats_file = f"{output_file}_stats.csv"
            if not Path(stats_file).exists():
                print(f"统计文件不存在: {stats_file}")
                return None
            
            with open(stats_file, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                stats = list(reader)
            
            # 查找主要API的统计数据
            pose_detection_stats = None
            for row in stats:
                if row['Name'] == '/api/pose_detection':
                    pose_detection_stats = row
                    break
            
            if not pose_detection_stats:
                print("未找到姿态检测API的统计数据")
                return None
            
            # 提取关键指标
            result = {
                'experiment_id': experiment_id,
                'pod_count': pod_count,
                'user_count': user_count,
                'timestamp': datetime.now().isoformat(),
                'request_count': int(pose_detection_stats.get('Request Count', 0)),
                'failure_count': int(pose_detection_stats.get('Failure Count', 0)),
                'avg_response_time': float(pose_detection_stats.get('Average Response Time', 0)),
                'min_response_time': float(pose_detection_stats.get('Min Response Time', 0)),
                'max_response_time': float(pose_detection_stats.get('Max Response Time', 0)),
                'p50_response_time': float(pose_detection_stats.get('50%', 0)),
                'p95_response_time': float(pose_detection_stats.get('95%', 0)),
                'p99_response_time': float(pose_detection_stats.get('99%', 0)),
                'requests_per_second': float(pose_detection_stats.get('Requests/s', 0)),
                'failures_per_second': float(pose_detection_stats.get('Failures/s', 0)),
                'average_content_size': float(pose_detection_stats.get('Average Content Size', 0))
            }
            
            # 计算成功率
            total_requests = result['request_count'] + result['failure_count']
            result['success_rate'] = (result['request_count'] / total_requests * 100) if total_requests > 0 else 0
            
            return result
            
        except Exception as e:
            print(f"解析结果时出错: {e}")
            return None
    
    def print_experiment_summary(self, result):
        """打印实验摘要"""
        print(f"\n实验摘要:")
        print(f"  Pod数量: {result['pod_count']}")
        print(f"  用户数量: {result['user_count']}")
        print(f"  总请求数: {result['request_count']}")
        print(f"  失败请求数: {result['failure_count']}")
        print(f"  成功率: {result['success_rate']:.2f}%")
        print(f"  平均响应时间: {result['avg_response_time']:.2f}ms")
        print(f"  P95响应时间: {result['p95_response_time']:.2f}ms")
        print(f"  QPS: {result['requests_per_second']:.2f}")
    
    def run_all_experiments(self):
        """运行所有实验"""
        print(f"\n开始运行实验序列")
        print(f"Pod配置: {self.pod_configs}")
        print(f"用户配置: {self.user_configs}")
        
        experiment_id = 1
        
        for pod_count in self.pod_configs:
            for user_count in self.user_configs:
                success = self.run_single_experiment(pod_count, user_count, experiment_id)
                
                if not success:
                    print(f"实验 {experiment_id} 失败，是否继续？(y/n): ", end='')
                    if input().lower() != 'y':
                        print("实验序列被终止")
                        break
                
                experiment_id += 1
                
                # 实验间隔
                if experiment_id <= len(self.pod_configs) * len(self.user_configs):
                    print(f"\n等待 30 秒后开始下一个实验...")
                    time.sleep(30)
        
        # 生成最终报告
        self.generate_final_report()
    
    def generate_final_report(self):
        """生成最终实验报告"""
        if not self.results:
            print("没有实验结果可生成报告")
            return
        
        print(f"\n{'='*60}")
        print("生成最终实验报告")
        print(f"{'='*60}")
        
        # 保存JSON格式结果
        json_file = self.experiment_dir / "experiment_results.json"
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(self.results, f, indent=2, ensure_ascii=False)
        print(f"JSON结果已保存: {json_file}")
        
        # 生成CSV报告
        csv_file = self.experiment_dir / "experiment_summary.csv"
        with open(csv_file, 'w', newline='', encoding='utf-8') as f:
            if self.results:
                writer = csv.DictWriter(f, fieldnames=self.results[0].keys())
                writer.writeheader()
                writer.writerows(self.results)
        print(f"CSV报告已保存: {csv_file}")
        
        # 生成Markdown报告
        self.generate_markdown_report()
        
        # 打印汇总表格
        self.print_summary_table()
    
    def generate_markdown_report(self):
        """生成Markdown格式的实验报告"""
        md_file = self.experiment_dir / "experiment_report.md"
        
        with open(md_file, 'w', encoding='utf-8') as f:
            f.write("# CloudPose 负载测试实验报告\n\n")
            f.write(f"**实验时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"**测试主机**: {self.host}\n")
            f.write(f"**测试模式**: {self.mode}\n\n")
            
            f.write("## 实验配置\n\n")
            f.write(f"- Pod数量: {self.pod_configs}\n")
            f.write(f"- 用户数量: {self.user_configs}\n")
            f.write(f"- 测试时长: {self.test_duration}秒\n")
            f.write(f"- 用户生成速率: {self.spawn_rate}/秒\n\n")
            
            f.write("## 实验结果\n\n")
            f.write("| Pod数量 | 用户数量 | 平均响应时间(ms) | P95响应时间(ms) | QPS | 成功率(%) |\n")
            f.write("|---------|----------|------------------|-----------------|-----|-----------|\n")
            
            for result in self.results:
                f.write(f"| {result['pod_count']} | {result['user_count']} | "
                       f"{result['avg_response_time']:.2f} | {result['p95_response_time']:.2f} | "
                       f"{result['requests_per_second']:.2f} | {result['success_rate']:.2f} |\n")
            
            f.write("\n## 详细分析\n\n")
            f.write("### 性能观察\n\n")
            f.write("1. **响应时间趋势**: 随着用户数量增加，响应时间的变化情况\n")
            f.write("2. **吞吐量分析**: 不同配置下的QPS表现\n")
            f.write("3. **稳定性评估**: 成功率和错误率分析\n\n")
            
            f.write("### 扩展性分析\n\n")
            f.write("1. **水平扩展效果**: Pod数量增加对性能的影响\n")
            f.write("2. **负载承受能力**: 系统在不同负载下的表现\n")
            f.write("3. **资源利用率**: CPU和内存使用情况\n\n")
            
            f.write("### 结论和建议\n\n")
            f.write("1. **最佳配置**: 推荐的Pod和用户配置\n")
            f.write("2. **性能瓶颈**: 识别的主要限制因素\n")
            f.write("3. **优化建议**: 进一步改进的方向\n")
        
        print(f"Markdown报告已保存: {md_file}")
    
    def print_summary_table(self):
        """打印汇总表格"""
        print("\n实验结果汇总:")
        print(f"{'Pod数量':<8} {'用户数量':<8} {'平均响应时间(ms)':<16} {'P95响应时间(ms)':<16} {'QPS':<8} {'成功率(%)':<10}")
        print("-" * 80)
        
        for result in self.results:
            print(f"{result['pod_count']:<8} {result['user_count']:<8} "
                  f"{result['avg_response_time']:<16.2f} {result['p95_response_time']:<16.2f} "
                  f"{result['requests_per_second']:<8.2f} {result['success_rate']:<10.2f}")

def main():
    parser = argparse.ArgumentParser(description='CloudPose 自动化负载测试实验')
    parser.add_argument('--host', required=True, help='测试目标主机 (例如: http://localhost:8000)')
    parser.add_argument('--mode', choices=['local', 'k8s'], default='local', help='测试模式')
    parser.add_argument('--pods', help='Pod数量配置 (逗号分隔，例如: 1,2,4)')
    parser.add_argument('--users', help='用户数量配置 (逗号分隔，例如: 10,20,50)')
    parser.add_argument('--duration', type=int, default=300, help='每个测试的持续时间(秒)')
    parser.add_argument('--spawn-rate', type=int, default=5, help='用户生成速率(/秒)')
    
    args = parser.parse_args()
    
    # 创建实验运行器
    runner = ExperimentRunner(args.host, args.mode)
    
    # 自定义配置
    if args.pods:
        runner.pod_configs = [int(x.strip()) for x in args.pods.split(',')]
    if args.users:
        runner.user_configs = [int(x.strip()) for x in args.users.split(',')]
    
    runner.test_duration = args.duration
    runner.spawn_rate = args.spawn_rate
    
    print("CloudPose 自动化负载测试实验")
    print("=" * 50)
    
    # 检查前提条件
    if not runner.check_prerequisites():
        print("\n前提条件检查失败，请解决上述问题后重试")
        sys.exit(1)
    
    print("\n所有前提条件检查通过，开始实验...")
    
    try:
        runner.run_all_experiments()
        print(f"\n所有实验完成！结果保存在: {runner.experiment_dir}")
    except KeyboardInterrupt:
        print("\n实验被用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n实验执行出错: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()