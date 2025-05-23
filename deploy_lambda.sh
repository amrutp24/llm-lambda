#!/bin/bash

set -e

# Config
REGION="us-east-1"
FUNCTION_NAME="llmLambda"
IMAGE_NAME="llm-lambda"
ROLE_NAME="llm-lambda-execution-role" # update if you named it differently

echo "🔧 Getting AWS Account ID..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $PROFILE)
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${IMAGE_NAME}:latest"

echo "🔄 Creating ECR repository if not exists..."
aws ecr describe-repositories --repository-names $IMAGE_NAME --region $REGION --profile $PROFILE >/dev/null 2>&1 || \
aws ecr create-repository --repository-name $IMAGE_NAME --region $REGION --profile $PROFILE

echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region $REGION --profile $PROFILE | \
docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

echo "🐳 Building Docker image..."
export DOCKER_BUILDKIT=0
docker build --platform linux/amd64 -t $IMAGE_NAME .

echo "🏷️ Tagging image..."
docker tag $IMAGE_NAME:latest $IMAGE_URI

echo "📤 Pushing image to ECR..."
docker push $IMAGE_URI

echo "🛠️ Updating Lambda function code..."
aws lambda update-function-code \
  --function-name $FUNCTION_NAME \
  --image-uri $IMAGE_URI \
  --region $REGION \

echo "✅ Deployment complete!"
