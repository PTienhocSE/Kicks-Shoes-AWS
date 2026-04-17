# Hướng dẫn Deploy Backend lên AWS ECS với EC2

## Mục lục
1. [Tổng quan](#tổng-quan)
2. [Prerequisites](#prerequisites)
3. [Setup ban đầu](#setup-ban-đầu)
4. [Deploy qua GitHub Actions (Khuyến nghị)](#deploy-qua-github-actions)
5. [Deploy thủ công](#deploy-thủ-công)
6. [Quản lý và Monitoring](#quản-lý-và-monitoring)
7. [Troubleshooting](#troubleshooting)

## Tổng quan

### Kiến trúc hệ thống

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  Internet Gateway    │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ Application Load     │
              │    Balancer (ALB)    │
              │  (Public Subnets)    │
              └──────────┬───────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌─────────────────┐           ┌─────────────────┐
│ Private Subnet 1│           │ Private Subnet 2│
│                 │           │                 │
│  ┌───────────┐  │           │  ┌───────────┐  │
│  │ EC2 + ECS │  │           │  │ EC2 + ECS │  │
│  │ Container │  │           │  │ Container │  │
│  └───────────┘  │           │  └───────────┘  │
└────────┬────────┘           └────────┬────────┘
         │                              │
         └──────────────┬───────────────┘
                        │
                        ▼
                ┌───────────────┐
                │  NAT Gateway  │
                └───────┬───────┘
                        │
                        ▼
                    Internet
```

### Components

- **VPC**: Virtual Private Cloud với 2 AZs
- **Public Subnets**: Chứa ALB và NAT Gateway
- **Private Subnets**: Chứa EC2 instances chạy ECS containers
- **ALB**: Phân phối traffic và health checks
- **ECS Cluster**: Quản lý containers
- **EC2 Auto Scaling**: Tự động scale instances
- **ECS Service Auto Scaling**: Tự động scale tasks
- **CloudWatch**: Logs và monitoring
- **Secrets Manager**: Quản lý sensitive data

## Prerequisites

### 1. AWS Account
- AWS Account với quyền tạo resources (VPC, EC2, ECS, ALB, IAM, etc.)
- AWS CLI đã cài đặt và cấu hình

### 2. Tools
```bash
# AWS CLI
aws --version

# Docker
docker --version

# Git
git --version
```

### 3. AWS Credentials
Cấu hình AWS credentials:
```bash
aws configure
# Hoặc set environment variables:
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_SESSION_TOKEN=your-session-token  # nếu dùng temporary credentials
```

## Setup ban đầu

### Bước 1: Tạo Secrets Manager Secret

Có 2 cách:

#### Cách 1: Dùng script tự động (Khuyến nghị)
```bash
cd backend/cloudformation
./setup-secrets.sh dev ap-southeast-1
```

Script sẽ hỏi các thông tin cần thiết và tự động tạo secret.

#### Cách 2: Tạo thủ công
```bash
aws secretsmanager create-secret \
  --name kicks-shoes-dev/app-config \
  --description "Backend application configuration" \
  --secret-string '{
    "NODE_ENV": "production",
    "PORT": "3000",
    "MONGODB_URI": "mongodb+srv://user:pass@cluster.mongodb.net/kicks-shoes",
    "JWT_SECRET": "your-super-secret-jwt-key-change-this",
    "JWT_EXPIRES_IN": "7d",
    "CLOUDINARY_CLOUD_NAME": "your-cloud-name",
    "CLOUDINARY_API_KEY": "your-api-key",
    "CLOUDINARY_API_SECRET": "your-api-secret",
    "GOOGLE_CLIENT_ID": "your-google-client-id",
    "GOOGLE_CLIENT_SECRET": "your-google-client-secret",
    "EMAIL_SERVICE": "gmail",
    "EMAIL_USER": "your-email@gmail.com",
    "EMAIL_PASSWORD": "your-app-password",
    "PAYOS_CLIENT_ID": "your-payos-client-id",
    "PAYOS_API_KEY": "your-payos-api-key",
    "PAYOS_CHECKSUM_KEY": "your-payos-checksum-key",
    "VNPAY_TMN_CODE": "your-vnpay-code",
    "VNPAY_HASH_SECRET": "your-vnpay-secret",
    "VNPAY_URL": "https://sandbox.vnpayment.vn/paymentv2/vpcpay.html",
    "GEMINI_API_KEY": "your-gemini-api-key",
    "FRONTEND_URL": "https://your-frontend-domain.com",
    "AWS_REGION": "ap-southeast-1"
  }' \
  --region ap-southeast-1
```

### Bước 2: (Optional) Setup Custom Domain với HTTPS

Nếu muốn dùng custom domain:

#### 2.1. Request ACM Certificate
```bash
aws acm request-certificate \
  --domain-name api.kicks-shoes.com \
  --validation-method DNS \
  --region ap-southeast-1
```

#### 2.2. Validate Certificate
- Vào ACM Console
- Copy CNAME records
- Thêm vào DNS provider (Route53, Cloudflare, etc.)
- Đợi certificate được issued

#### 2.3. Create Route53 Hosted Zone (nếu dùng Route53)
```bash
aws route53 create-hosted-zone \
  --name kicks-shoes.com \
  --caller-reference $(date +%s)
```

## Deploy qua GitHub Actions

### Bước 1: Setup GitHub Secrets

Vào repository Settings → Secrets and variables → Actions, thêm:

**Required Secrets:**
- `AWS_ACCESS_KEY_ID`: AWS access key
- `AWS_SECRET_ACCESS_KEY`: AWS secret key
- `AWS_SESSION_TOKEN`: Session token (nếu dùng temporary credentials)

**Optional Variables:**
- `APP_CONFIG_SECRET_NAME`: `kicks-shoes-dev/app-config` (default)
- `ENABLE_CUSTOM_DOMAIN`: `false` (default) hoặc `true`
- `DOMAIN_NAME`: `api.kicks-shoes.com` (nếu enable custom domain)
- `INSTANCE_TYPE`: `t3.small` (default)
- `DESIRED_COUNT`: `2` (default)
- `MIN_CAPACITY`: `1` (default)
- `MAX_CAPACITY`: `4` (default)

### Bước 2: Trigger Deployment

#### Tự động (khi push code)
```bash
git add .
git commit -m "Deploy backend to ECS EC2"
git push origin feature/ecs-ec2-deployment
```

#### Thủ công (Manual trigger)
1. Vào GitHub repository
2. Click tab "Actions"
3. Chọn workflow "Deploy Backend to ECS EC2"
4. Click "Run workflow"
5. Chọn branch và click "Run workflow"

### Bước 3: Monitor Deployment

- Xem progress trong GitHub Actions tab
- Deployment summary sẽ hiển thị Load Balancer URL
- Health check tự động được thực hiện

## Deploy thủ công

### Cách 1: Dùng deploy script (Khuyến nghị)

```bash
cd backend/cloudformation

# Set environment variables (optional)
export ENABLE_CUSTOM_DOMAIN=false
export INSTANCE_TYPE=t3.small
export DESIRED_COUNT=2
export MIN_CAPACITY=1
export MAX_CAPACITY=4

# Run deploy script
./deploy.sh dev ap-southeast-1
```

### Cách 2: Deploy từng bước

#### 1. Create ECR Repository
```bash
aws ecr create-repository \
  --repository-name kicks-shoes-backend \
  --image-scanning-configuration scanOnPush=true \
  --region ap-southeast-1
```

#### 2. Build và Push Docker Image
```bash
# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com

# Build image
cd backend
docker build -f Dockerfile -t kicks-shoes-backend:latest .

# Tag image
docker tag kicks-shoes-backend:latest \
  ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/kicks-shoes-backend:latest

# Push image
docker push ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/kicks-shoes-backend:latest
```

#### 3. Deploy Network Stack
```bash
cd cloudformation

aws cloudformation deploy \
  --template-file 01-network.yaml \
  --stack-name dev-network-stack \
  --parameter-overrides EnvironmentName=dev \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1
```

#### 4. Deploy Application Stack
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/kicks-shoes-backend:latest"

aws cloudformation deploy \
  --template-file 02-app.yaml \
  --stack-name dev-app-stack \
  --parameter-overrides \
    EnvironmentName=dev \
    ContainerImage=$IMAGE_URI \
    AppConfigSecretName=kicks-shoes-dev/app-config \
    EnableCustomDomain=false \
    InstanceType=t3.small \
    DesiredCount=2 \
    MinCapacity=1 \
    MaxCapacity=4 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1
```

#### 5. Get Load Balancer URL
```bash
aws cloudformation describe-stacks \
  --stack-name dev-app-stack \
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerURL'].OutputValue" \
  --output text \
  --region ap-southeast-1
```

## Quản lý và Monitoring

### View Logs
```bash
# Tail logs
aws logs tail /ecs/dev/backend --follow --region ap-southeast-1

# Get logs từ specific time
aws logs tail /ecs/dev/backend --since 1h --region ap-southeast-1
```

### Check Service Status
```bash
aws ecs describe-services \
  --cluster dev-cluster \
  --services dev-backend-service \
  --region ap-southeast-1
```

### List Running Tasks
```bash
aws ecs list-tasks \
  --cluster dev-cluster \
  --service-name dev-backend-service \
  --region ap-southeast-1
```

### Check EC2 Instances
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=dev-ecs-instance" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress]" \
  --output table \
  --region ap-southeast-1
```

### Scale Service
```bash
# Scale ECS tasks
aws ecs update-service \
  --cluster dev-cluster \
  --service dev-backend-service \
  --desired-count 4 \
  --region ap-southeast-1

# Scale EC2 instances
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name dev-ecs-asg \
  --desired-capacity 3 \
  --region ap-southeast-1
```

### Update Application

#### Update với image mới:
```bash
# Build và push image mới
# ... (như bước 2 ở trên)

# Update stack với image mới
aws cloudformation deploy \
  --template-file 02-app.yaml \
  --stack-name dev-app-stack \
  --parameter-overrides \
    ContainerImage=<new-image-uri> \
    # ... other parameters
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1
```

ECS sẽ tự động rolling update với zero downtime.

## Troubleshooting

### Service không start được

```bash
# Check service events
aws ecs describe-services \
  --cluster dev-cluster \
  --services dev-backend-service \
  --query "services[0].events[0:5]" \
  --region ap-southeast-1

# Check task definition
aws ecs describe-task-definition \
  --task-definition dev-backend \
  --region ap-southeast-1

# Check stopped tasks
aws ecs list-tasks \
  --cluster dev-cluster \
  --desired-status STOPPED \
  --region ap-southeast-1
```

### Health Check Fails

1. Verify endpoint:
```bash
LB_URL=$(aws cloudformation describe-stacks \
  --stack-name dev-app-stack \
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerURL'].OutputValue" \
  --output text)

curl -v $LB_URL/api/health
```

2. Check Security Groups:
```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=dev-alb-sg" \
  --region ap-southeast-1
```

3. Check Target Group health:
```bash
# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
  --names dev-tg \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text)

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region ap-southeast-1
```

### EC2 Instances không join cluster

1. Check instance logs:
```bash
# SSH vào instance (cần setup SSH key trước)
ssh ec2-user@<instance-ip>

# Check ECS agent logs
sudo cat /var/log/ecs/ecs-agent.log

# Check ecs config
cat /etc/ecs/ecs.config
```

2. Verify IAM role:
```bash
aws iam get-instance-profile \
  --instance-profile-name dev-ecs-instance-profile \
  --region ap-southeast-1
```

### Container crashes

```bash
# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster dev-cluster \
  --service-name dev-backend-service \
  --query "taskArns[0]" \
  --output text)

# Describe task
aws ecs describe-tasks \
  --cluster dev-cluster \
  --tasks $TASK_ARN \
  --region ap-southeast-1

# Check logs
aws logs tail /ecs/dev/backend --follow
```

### Rollback Deployment

```bash
# List task definitions
aws ecs list-task-definitions \
  --family-prefix dev-backend \
  --region ap-southeast-1

# Update service với task definition cũ
aws ecs update-service \
  --cluster dev-cluster \
  --service dev-backend-service \
  --task-definition dev-backend:1 \
  --region ap-southeast-1
```

## Cleanup Resources

```bash
# Delete app stack
aws cloudformation delete-stack \
  --stack-name dev-app-stack \
  --region ap-southeast-1

# Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name dev-app-stack \
  --region ap-southeast-1

# Delete network stack
aws cloudformation delete-stack \
  --stack-name dev-network-stack \
  --region ap-southeast-1

# Delete ECR images (optional)
aws ecr batch-delete-image \
  --repository-name kicks-shoes-backend \
  --image-ids imageTag=latest \
  --region ap-southeast-1

# Delete secret (optional)
aws secretsmanager delete-secret \
  --secret-id kicks-shoes-dev/app-config \
  --force-delete-without-recovery \
  --region ap-southeast-1
```

## Cost Estimation

### Monthly costs (ap-southeast-1):

- **EC2 t3.small (2 instances)**: ~$30
- **NAT Gateway**: ~$32
- **Application Load Balancer**: ~$22
- **Data Transfer**: ~$10-20
- **CloudWatch Logs**: ~$5
- **Total**: ~$100-110/month

### Cost Optimization Tips:

1. Dùng Spot Instances cho non-production
2. Giảm số lượng instances khi không cần
3. Dùng NAT instance thay vì NAT Gateway
4. Giảm log retention period
5. Enable S3 VPC endpoint để tránh NAT Gateway charges

## Support

Nếu gặp vấn đề, check:
1. CloudWatch Logs: `/ecs/dev/backend`
2. ECS Service Events
3. CloudFormation Stack Events
4. GitHub Actions logs (nếu deploy qua CI/CD)
