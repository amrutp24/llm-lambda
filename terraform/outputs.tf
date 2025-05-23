output "lambda_function_name" {
  value = aws_lambda_function.llm_lambda.function_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.llm_lambda.repository_url
}

output "iam_role_name" {
  value = aws_iam_role.lambda_exec.name
}

output "iam_role_arn" {
  value = aws_iam_role.lambda_exec.arn
}