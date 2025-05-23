resource "aws_iam_role" "lambda_exec" {
  name = "llm-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ECR Repository
resource "aws_ecr_repository" "llm_lambda" {
  name = var.lambda_name
}

# Lambda Function (Container-based)
resource "aws_lambda_function" "llm_lambda" {
  function_name = var.lambda_name
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = var.image_uri # You must pass this in via tfvars or CLI
  timeout       = 60
  memory_size   = 2048
  depends_on    = [aws_iam_role_policy_attachment.lambda_basic, aws_iam_role_policy_attachment.ecr_access]
}
