# Terraform Setup for llm-lambda

This Terraform configuration:

- Creates an ECR repo to store your Lambda image
- Creates an IAM role with Lambda + ECR permissions
- Deploys the Lambda function using your Docker image

## Requirements

- AWS CLI with credentials
- Terraform v1.3+
- Docker image already pushed to ECR

## Usage

1. Update the `image_uri` variable in your `.tfvars` file:

```hcl
image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/llm-lambda:latest"
