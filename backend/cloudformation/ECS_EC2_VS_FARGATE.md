# So sánh ECS EC2 vs Fargate

## Tổng quan

Branch này (`feature/ecs-ec2-deployment`) implement deployment với **ECS EC2**, trong khi branch khác có thể dùng **Fargate**. Đây là so sánh chi tiết giữa 2 approaches.

## Kiến trúc

### ECS EC2 (Branch này)
```
ALB → ECS Service → EC2 Instances (Auto Scaling) → Docker Containers
```

### Fargate (Branch khác)
```
ALB → ECS Service → Fargate Tasks (Serverless)
```

## So sánh chi tiết

| Tiêu chí | ECS EC2 | Fargate |
|----------|---------|---------|
| **Quản lý Infrastructure** | Phải quản lý EC2 instances | AWS quản lý hoàn toàn |
| **Pricing Model** | Trả tiền theo EC2 instances | Trả tiền theo vCPU/Memory/giây |
| **Cost (Small workload)** | Cao hơn (minimum 1 instance) | Thấp hơn (pay per use) |
| **Cost (Large workload)** | Thấp hơn (economies of scale) | Cao hơn |
| **Startup Time** | Nhanh hơn (instance đã chạy) | Chậm hơn (cold start ~30s) |
| **Control** | Full control (SSH, customize) | Limited control |
| **Scaling** | 2-tier (instances + tasks) | 1-tier (chỉ tasks) |
| **Maintenance** | Cần patch OS, update AMI | Không cần maintain |
| **Networking** | Bridge/Host mode | awsvpc mode only |
| **Storage** | EBS volumes | Ephemeral storage |
| **Spot Instances** | Có thể dùng | Fargate Spot available |

## Chi phí ước tính (ap-southeast-1)

### ECS EC2 (2x t3.small, 24/7)
```
EC2 instances:     $30/month
NAT Gateway:       $32/month
ALB:               $22/month
Data Transfer:     $10/month
CloudWatch:        $5/month
-----------------------------------
Total:             ~$100/month
```

### Fargate (2 tasks, 0.5 vCPU, 1GB RAM, 24/7)
```
Fargate compute:   $36/month
NAT Gateway:       $32/month
ALB:               $22/month
Data Transfer:     $10/month
CloudWatch:        $5/month
-----------------------------------
Total:             ~$105/month
```

**Note**: Chi phí tương đương cho workload nhỏ, nhưng:
- ECS EC2 rẻ hơn khi scale lên (nhiều tasks trên 1 instance)
- Fargate rẻ hơn cho workload không đều (scale to zero)

## Khi nào dùng ECS EC2?

✅ **Nên dùng khi:**
- Workload ổn định, chạy 24/7
- Cần control chi tiết về infrastructure
- Cần SSH vào instances để debug
- Muốn dùng Spot instances để tiết kiệm
- Có nhiều containers chạy cùng lúc
- Cần persistent storage (EBS)
- Cần GPU hoặc specialized hardware
- Team có kinh nghiệm quản lý EC2

❌ **Không nên dùng khi:**
- Workload không đều, có thể scale to zero
- Team nhỏ, không muốn maintain infrastructure
- Cần deploy nhanh, không quan tâm underlying infrastructure
- Workload có burst traffic
- Ưu tiên simplicity hơn cost optimization

## Khi nào dùng Fargate?

✅ **Nên dùng khi:**
- Muốn serverless, không maintain infrastructure
- Workload có burst traffic
- Team nhỏ, focus vào application
- Cần deploy nhanh, đơn giản
- Workload có thể scale to zero
- Mỗi task cần isolated networking
- Không cần SSH access

❌ **Không nên dùng khi:**
- Workload lớn, chạy 24/7 (cost cao)
- Cần control chi tiết về infrastructure
- Cần GPU hoặc specialized hardware
- Cần persistent storage
- Cold start time là vấn đề

## Migration giữa 2 approaches

### Từ EC2 sang Fargate

1. Update Task Definition:
```yaml
RequiresCompatibilities:
  - FARGATE  # Thay vì EC2
NetworkMode: awsvpc  # Bắt buộc với Fargate
```

2. Update Service:
```yaml
LaunchType: FARGATE
NetworkConfiguration:
  AwsvpcConfiguration:
    Subnets: [subnet-1, subnet-2]
    SecurityGroups: [sg-1]
    AssignPublicIp: DISABLED
```

3. Remove EC2-specific resources:
- Launch Template
- Auto Scaling Group
- EC2 Instance Profile
- Capacity Provider

### Từ Fargate sang EC2

Làm ngược lại, thêm:
- Launch Template với ECS-optimized AMI
- Auto Scaling Group
- EC2 Instance Profile
- Capacity Provider

## Best Practices

### ECS EC2
1. Dùng ECS-optimized AMI
2. Enable Container Insights
3. Configure Auto Scaling cho cả instances và tasks
4. Dùng Spot instances cho non-production
5. Monitor instance health
6. Regular AMI updates
7. Use Systems Manager Session Manager thay vì SSH

### Fargate
1. Right-size tasks (CPU/Memory)
2. Use Fargate Spot cho non-critical workloads
3. Enable Container Insights
4. Configure Auto Scaling
5. Monitor cold start times
6. Optimize container image size

## Hybrid Approach

Có thể dùng cả 2 trong cùng 1 cluster:

```yaml
CapacityProviderStrategy:
  - CapacityProvider: FARGATE
    Weight: 1
    Base: 2  # Minimum 2 tasks on Fargate
  - CapacityProvider: EC2_CAPACITY_PROVIDER
    Weight: 4  # 80% traffic to EC2
```

**Use case**: 
- Base load trên EC2 (cost-effective)
- Burst traffic trên Fargate (flexible)

## Kết luận

### Chọn ECS EC2 nếu:
- Bạn có workload ổn định, lớn
- Team có kinh nghiệm với EC2
- Muốn optimize cost cho long-term
- Cần control và flexibility

### Chọn Fargate nếu:
- Bạn muốn simplicity và serverless
- Workload không đều hoặc nhỏ
- Team nhỏ, focus vào application
- Ưu tiên time-to-market

### Recommendation cho project này:

**Development**: Fargate (đơn giản, dễ setup)
**Production**: ECS EC2 (cost-effective cho workload ổn định)

Hoặc dùng hybrid approach để có best of both worlds!
