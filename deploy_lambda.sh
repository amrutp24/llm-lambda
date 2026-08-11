#!/bin/bash

set -euo pipefail

# Config. Override from the environment, e.g.:
#   ARCH=arm64 FUNCTION_NAME=my-fn ./deploy_lambda.sh
#
# FUNCTION_NAME and IMAGE_NAME must match terraform's var.lambda_name, which
# names both the function and the ECR repository.
REGION="${REGION:-us-east-1}"
FUNCTION_NAME="${FUNCTION_NAME:-llm-lambda}"
IMAGE_NAME="${IMAGE_NAME:-$FUNCTION_NAME}"

# Must match terraform's var.architecture and the wheels in requirements.txt.
# x86_64 -> linux/amd64, arm64 -> linux/arm64
ARCH="${ARCH:-x86_64}"
case "$ARCH" in
  x86_64) PLATFORM="linux/amd64" ;;
  arm64)  PLATFORM="linux/arm64" ;;
  *) echo "ARCH must be x86_64 or arm64, got '$ARCH'" >&2; exit 2 ;;
esac

echo "🔧 Getting AWS Account ID..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${IMAGE_NAME}:latest"

echo "🔄 Creating ECR repository if not exists..."
aws ecr describe-repositories --repository-names "$IMAGE_NAME" --region "$REGION" >/dev/null 2>&1 || \
aws ecr create-repository --repository-name "$IMAGE_NAME" --region "$REGION"

echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "🐳 Building Docker image for $PLATFORM..."
if [ "$PLATFORM" = "linux/arm64" ]; then
  # Cross-building needs buildkit; --load puts the result in the local daemon.
  docker buildx build --platform "$PLATFORM" -t "$IMAGE_NAME" --load .
else
  export DOCKER_BUILDKIT=0
  docker build --platform "$PLATFORM" -t "$IMAGE_NAME" .
fi

echo "🏷️ Tagging image..."
docker tag "$IMAGE_NAME:latest" "$IMAGE_URI"

echo "📤 Pushing image to ECR..."
docker push "$IMAGE_URI"

echo "🛠️ Updating Lambda function code..."
# terraform apply will NOT pick up a new image on its own: image_uri still reads
# ":latest", so the plan is empty even though the tag now points elsewhere. This
# call re-resolves the tag, so code deploys go through here, not terraform.
aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --image-uri "$IMAGE_URI" \
  --region "$REGION"

echo "✅ Deployment complete!"
