variable "region" {
  default = "us-east-1"
}

variable "lambda_name" {
  default = "llm-lambda"
}

variable "image_uri" {
  description = "URI of the container image in ECR"
  type        = string
}