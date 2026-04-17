#!/bin/bash

# Script to create AWS Secrets Manager secret for backend configuration
# Usage: ./setup-secrets.sh [environment] [region]

set -e

ENVIRONMENT=${1:-dev}
REGION=${2:-ap-southeast-1}
SECRET_NAME="kicks-shoes-${ENVIRONMENT}/app-config"

echo "=========================================="
echo "Setting up AWS Secrets Manager"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Secret Name: $SECRET_NAME"
echo "=========================================="

# Check if secret already exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region $REGION &> /dev/null; then
    echo "Secret already exists. Do you want to update it? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    UPDATE_MODE=true
else
    UPDATE_MODE=false
fi

# Prompt for configuration values
echo ""
echo "Please enter the configuration values:"
echo ""

read -p "MongoDB URI: " MONGODB_URI
read -p "JWT Secret: " JWT_SECRET
read -p "Cloudinary Cloud Name: " CLOUDINARY_CLOUD_NAME
read -p "Cloudinary API Key: " CLOUDINARY_API_KEY
read -sp "Cloudinary API Secret: " CLOUDINARY_API_SECRET
echo ""
read -p "Google Client ID: " GOOGLE_CLIENT_ID
read -sp "Google Client Secret: " GOOGLE_CLIENT_SECRET
echo ""
read -p "Email User: " EMAIL_USER
read -sp "Email Password: " EMAIL_PASSWORD
echo ""
read -p "PayOS Client ID (optional): " PAYOS_CLIENT_ID
read -p "PayOS API Key (optional): " PAYOS_API_KEY
read -sp "PayOS Checksum Key (optional): " PAYOS_CHECKSUM_KEY
echo ""
read -p "VNPay TMN Code (optional): " VNPAY_TMN_CODE
read -sp "VNPay Hash Secret (optional): " VNPAY_HASH_SECRET
echo ""
read -p "Gemini API Key (optional): " GEMINI_API_KEY
echo ""
read -p "Frontend URL: " FRONTEND_URL

# Create JSON secret string
SECRET_JSON=$(cat <<EOF
{
  "NODE_ENV": "production",
  "PORT": "3000",
  "MONGODB_URI": "$MONGODB_URI",
  "JWT_SECRET": "$JWT_SECRET",
  "JWT_EXPIRES_IN": "7d",
  "CLOUDINARY_CLOUD_NAME": "$CLOUDINARY_CLOUD_NAME",
  "CLOUDINARY_API_KEY": "$CLOUDINARY_API_KEY",
  "CLOUDINARY_API_SECRET": "$CLOUDINARY_API_SECRET",
  "GOOGLE_CLIENT_ID": "$GOOGLE_CLIENT_ID",
  "GOOGLE_CLIENT_SECRET": "$GOOGLE_CLIENT_SECRET",
  "EMAIL_SERVICE": "gmail",
  "EMAIL_USER": "$EMAIL_USER",
  "EMAIL_PASSWORD": "$EMAIL_PASSWORD",
  "PAYOS_CLIENT_ID": "$PAYOS_CLIENT_ID",
  "PAYOS_API_KEY": "$PAYOS_API_KEY",
  "PAYOS_CHECKSUM_KEY": "$PAYOS_CHECKSUM_KEY",
  "VNPAY_TMN_CODE": "$VNPAY_TMN_CODE",
  "VNPAY_HASH_SECRET": "$VNPAY_HASH_SECRET",
  "VNPAY_URL": "https://sandbox.vnpayment.vn/paymentv2/vpcpay.html",
  "GEMINI_API_KEY": "$GEMINI_API_KEY",
  "FRONTEND_URL": "$FRONTEND_URL",
  "AWS_REGION": "$REGION"
}
EOF
)

# Create or update secret
if [ "$UPDATE_MODE" = true ]; then
    echo ""
    echo "Updating secret..."
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SECRET_JSON" \
        --region $REGION
    echo "Secret updated successfully!"
else
    echo ""
    echo "Creating secret..."
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Backend application configuration for $ENVIRONMENT" \
        --secret-string "$SECRET_JSON" \
        --region $REGION
    echo "Secret created successfully!"
fi

echo ""
echo "=========================================="
echo "Secret setup completed!"
echo "=========================================="
echo "Secret Name: $SECRET_NAME"
echo "Region: $REGION"
echo "=========================================="
