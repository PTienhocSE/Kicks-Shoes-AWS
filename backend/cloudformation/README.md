# Backend Deployment với ECS EC2 và CloudFormation

## Tổng quan

Hệ thống deploy backend lên AWS sử dụng:
- **ECS (Elastic Container Service)** với **EC2 launch type**
- **Application Load Balancer (ALB)** để phân phối traffic
- **Auto Scaling** cho cả EC2 instances và ECS tasks
- **CloudFormation** để quản lý infrastructure as code
- **GitHub Actions** cho CI/CD pipeline

## Kiến trúc

```
Internet
    ↓
Internet Gateway
    ↓
Application Load Balancer (Public Subnets)
    ↓
ECS Service (Private Subnets)
    ↓
EC2 Instances (Auto Scaling Group)
    ↓
Docker Containers
    ↓
NAT Gateway → Internet (cho outbound traffic)
```

## Cấu trúc CloudFormation Stacks

### 1. Network Stack (`01-network.yaml`)
- VPC với CIDR 10.0.0.0/16
- 2 Public Subnets (10.0.1.0/24, 10.0.2.0/24)
- 2 Private Subnets (10.0.11.0/24, 10.0.12.0/24)
- Internet Gateway
- NAT Gateway
- Route Tables

### 2. Application Stack (`02-app.yaml`)
- ECS Cluster với Container Insights
- EC2 Launch Template với ECS-optimized AMI
- Auto Scaling Group
- Application Load Balancer
- Target Group với health checks
- ECS Service với rolling deployment
- IAM Roles và Security Groups
- CloudWatch Logs
- Auto Scaling policies (CPU và Memory based)

## Prerequisites

### 1. AWS Secrets Manager
Tạo secret chứa cấu hình app:

```bash
aws secretsmanager create-secret \
  --name kicks-shoes-dev/app-config \
  --description "Backend application configuration" \
  --secret-string '{
    "MONGODB_URI": "mongodb://...",
    "JWT_SECRET": "your-jwt-secret",
    "CLOUDINARY_CLOUD_NAME": "...",
    "CLOUDINARY_API_KEY": "...",
    "CLOUDINARY_API_SECRET": "...",
    "GOOGLE_CLIENT_ID": "...",
    "GOOGLE_CLIENT_SECRET": "...",
    "EMAIL_USER": "...",
    "EMAIL_PASSWORD": "..."
  }'
```

### 2. GitHub Secrets
Cấu hình trong GitHub repository settings:

**Required Secrets:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (nếu dùng temporary credentials)

**Optional Variables:**
- `APP_CONFIG_SECRET_NAME` (default: kicks-shoes-dev/app-config)
- `ENABLE_CUSTOM_DOMAIN` (default: false)
- `DOMAIN_NAME` (nếu enable custom domain)
- `INSTANCE_TYPE` (default: t3.small)
- `DESIRED_COUNT` (default: 2)
- `MIN_CAPACITY` (default: 1)
- `MAX_CAPACITY` (default: 4)

### 3. ACM Certificate (Optional - cho HTTPS)
Nếu muốn dùng custom domain với HTTPS:

```bash
aws acm request-certificate \
  --domain-name kicks-shoes.com \
  --validation-method DNS \
  --region ap-southeast-1
```

## Deployment

### Tự động qua GitHub Actions

Push code lên branch `feature/ecs-ec2-deployment`:

```bash
git add .
git commit -m "Deploy backend to ECS EC2"
git push origin feature/ecs-ec2-deployment
```

Hoặc trigger manually từ GitHub Actions tab.

### Manual Deployment

#### 1. Deploy Network Stack

```bash
aws cloudformation deploy \
  --template-file backend/cloudformation/01-network.yaml \
  --stack-name dev-network-stack \
  --parameter-overrides EnvironmentName=dev \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1
```

#### 2. Build và Push Docker Image

```bash
# Login to ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com

# Build image
docker build -f backend/Dockerfile -t kicks-shoes-backend:latest ./backend

# Tag và push
docker tag kicks-shoes-backend:latest <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/kicks-shoes-backend:latest
docker push <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/kicks-shoes-backend:latest
```

#### 3. Deploy Application Stack

```bash
aws cloudformation deploy \
  --template-file backend/cloudformation/02-app.yaml \
  --stack-name dev-app-stack \
  --parameter-overrides \
    EnvironmentName=dev \
    ContainerImage=<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/kicks-shoes-backend:latest \
    AppConfigSecretName=kicks-shoes-dev/app-config \
    EnableCustomDomain=false \
    InstanceType=t3.small \
    DesiredCount=2 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1
```

## Monitoring và Logs

### CloudWatch Logs
```bash
aws logs tail /ecs/dev/backend --follow --region ap-southeast-1
```

### ECS Service Status
```bash
aws ecs describe-services \
  --cluster dev-cluster \
  --services dev-backend-service \
  --region ap-southeast-1
```

### EC2 Instances
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=dev-ecs-instance" \
  --region ap-southeast-1
```

## Scaling

### Manual Scaling

**ECS Service:**
```bash
aws ecs update-service \
  --cluster dev-cluster \
  --service dev-backend-service \
  --desired-count 4 \
  --region ap-southeast-1
```

**Auto Scaling Group:**
```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name dev-ecs-asg \
  --desired-capacity 3 \
  --region ap-southeast-1
```

### Auto Scaling
- **CPU-based**: Scale khi CPU > 70%
- **Memory-based**: Scale khi Memory > 80%
- **Scale-out cooldown**: 60 seconds
- **Scale-in cooldown**: 300 seconds

## Update Application

Để update application với image mới:

1. Push code mới lên branch
2. GitHub Actions sẽ tự động:
   - Build image mới
   - Push lên ECR
   - Update CloudFormation stack
   - ECS sẽ rolling update với zero downtime

## Rollback

### Rollback ECS Service
```bash
# List task definitions
aws ecs list-task-definitions --family-prefix dev-backend

# Update service với task definition cũ
aws ecs update-service \
  --cluster dev-cluster \
  --service dev-backend-service \
  --task-definition dev-backend:1 \
  --region ap-southeast-1
```

### Rollback CloudFormation Stack
```bash
aws cloudformation cancel-update-stack --stack-name dev-app-stack
```

## Cleanup

Để xóa toàn bộ resources:

```bash
# Xóa app stack trước
aws cloudformation delete-stack --stack-name dev-app-stack --region ap-southeast-1

# Đợi app stack xóa xong
aws cloudformation wait stack-delete-complete --stack-name dev-app-stack --region ap-southeast-1

# Xóa network stack
aws cloudformation delete-stack --stack-name dev-network-stack --region ap-southeast-1
```

## Cost Optimization

- **Instance Type**: Dùng t3.small cho dev (có thể scale lên t3.medium/large cho production)
- **Spot Instances**: Có thể config Auto Scaling Group dùng Spot instances để tiết kiệm chi phí
- **NAT Gateway**: Tốn khoảng $32/tháng, có thể dùng NAT instance để tiết kiệm
- **CloudWatch Logs**: Retention 7 ngày cho dev, có thể tăng cho production

## Troubleshooting

### Service không start được
```bash
# Check service events
aws ecs describe-services --cluster dev-cluster --services dev-backend-service

# Check task logs
aws logs tail /ecs/dev/backend --follow
```

### Health check fail
- Kiểm tra Security Group rules
- Verify `/api/health` endpoint hoạt động
- Check container logs

### EC2 instances không join cluster
- Verify IAM instance profile
- Check UserData script trong Launch Template
- Review CloudWatch logs trên EC2 instance

## Support

Để được hỗ trợ, tạo issue trong repository hoặc liên hệ DevOps team.
