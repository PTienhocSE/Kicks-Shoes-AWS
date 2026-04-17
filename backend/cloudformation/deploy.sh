#!/bin/bash

# Deploy script for ECS EC2 CloudFormation stacks
# Usage: ./deploy.sh [environment] [region]

set -e

ENVIRONMENT=${1:-dev}
REGION=${2:-ap-southeast-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=========================================="
echo "Deploying Backend to ECS EC2"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
echo "=========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials are not configured properly."
    exit 1
fi

# Variables
ECR_REPOSITORY="kicks-shoes-backend"
NETWORK_STACK_NAME="${ENVIRONMENT}-network-stack"
APP_STACK_NAME="${ENVIRONMENT}-app-stack"
APP_CONFIG_SECRET="${ENVIRONMENT}/app-config"

# Step 1: Create ECR repository if not exists
print_status "Checking ECR repository..."
if ! aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $REGION &> /dev/null; then
    print_status "Creating ECR repository..."
    aws ecr create-repository \
        --repository-name $ECR_REPOSITORY \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --region $REGION
else
    print_status "ECR repository already exists"
fi

# Step 2: Build and push Docker image
print_status "Building Docker image..."
IMAGE_TAG=$(git rev-parse --short HEAD)
IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"

cd ..
docker build -f Dockerfile -t $IMAGE_URI -t "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPOSITORY}:latest" .
cd cloudformation

print_status "Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

print_status "Pushing image to ECR..."
docker push $IMAGE_URI
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPOSITORY}:latest"

print_status "Image pushed: $IMAGE_URI"

# Step 3: Validate app configuration secret
print_status "Validating app configuration secret..."
if ! aws secretsmanager describe-secret --secret-id "kicks-shoes-${APP_CONFIG_SECRET}" --region $REGION &> /dev/null; then
    print_error "Secret 'kicks-shoes-${APP_CONFIG_SECRET}' does not exist."
    print_warning "Please create the secret with your app configuration:"
    echo ""
    echo "aws secretsmanager create-secret \\"
    echo "  --name kicks-shoes-${APP_CONFIG_SECRET} \\"
    echo "  --description 'Backend application configuration' \\"
    echo "  --secret-string '{...}' \\"
    echo "  --region $REGION"
    exit 1
fi

# Step 4: Deploy Network Stack
print_status "Deploying Network Stack..."
aws cloudformation deploy \
    --template-file 01-network.yaml \
    --stack-name $NETWORK_STACK_NAME \
    --parameter-overrides EnvironmentName=$ENVIRONMENT \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --region $REGION

print_status "Network stack deployed successfully"

# Step 5: Deploy Application Stack
print_status "Deploying Application Stack..."

# Check if custom domain is enabled
ENABLE_CUSTOM_DOMAIN=${ENABLE_CUSTOM_DOMAIN:-false}
DOMAIN_NAME=${DOMAIN_NAME:-}
CERTIFICATE_ARN=""

if [ "$ENABLE_CUSTOM_DOMAIN" = "true" ]; then
    if [ -z "$DOMAIN_NAME" ]; then
        print_error "DOMAIN_NAME is required when ENABLE_CUSTOM_DOMAIN is true"
        exit 1
    fi
    
    print_status "Looking up ACM certificate for $DOMAIN_NAME..."
    CERTIFICATE_ARN=$(aws acm list-certificates --region $REGION \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn | [0]" \
        --output text)
    
    if [ -z "$CERTIFICATE_ARN" ] || [ "$CERTIFICATE_ARN" = "None" ]; then
        print_error "No certificate found for domain $DOMAIN_NAME"
        exit 1
    fi
    
    print_status "Found certificate: $CERTIFICATE_ARN"
fi

# Build parameters
PARAMS=(
    "EnvironmentName=$ENVIRONMENT"
    "ContainerImage=$IMAGE_URI"
    "AppConfigSecretName=kicks-shoes-${APP_CONFIG_SECRET}"
    "EnableCustomDomain=$ENABLE_CUSTOM_DOMAIN"
    "InstanceType=${INSTANCE_TYPE:-t3.small}"
    "DesiredCount=${DESIRED_COUNT:-2}"
    "MinCapacity=${MIN_CAPACITY:-1}"
    "MaxCapacity=${MAX_CAPACITY:-4}"
)

if [ "$ENABLE_CUSTOM_DOMAIN" = "true" ]; then
    PARAMS+=("DomainName=$DOMAIN_NAME")
    PARAMS+=("CertificateArn=$CERTIFICATE_ARN")
fi

aws cloudformation deploy \
    --template-file 02-app.yaml \
    --stack-name $APP_STACK_NAME \
    --parameter-overrides "${PARAMS[@]}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --region $REGION

print_status "Application stack deployed successfully"

# Step 6: Get outputs
print_status "Retrieving stack outputs..."
LB_URL=$(aws cloudformation describe-stacks \
    --stack-name $APP_STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerURL'].OutputValue" \
    --output text \
    --region $REGION)

print_status "Waiting for ECS service to stabilize..."
CLUSTER_NAME="${ENVIRONMENT}-cluster"
SERVICE_NAME="${ENVIRONMENT}-backend-service"

aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $REGION

echo ""
echo "=========================================="
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo "=========================================="
echo "Load Balancer URL: $LB_URL"
echo "Image: $IMAGE_URI"
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "=========================================="
echo ""
print_status "Testing health endpoint..."
sleep 10

if curl -f -s "$LB_URL/api/health" > /dev/null; then
    print_status "Health check passed!"
else
    print_warning "Health check failed. Service might still be starting up."
fi

echo ""
print_status "Deployment complete!"
