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

variable "memory_size" {
  description = "Memory in MB. Lambda scales CPU with this (1 vCPU at 1769 MB), so it is the main lever on cold-start duration - the function itself peaks around 760 MB."
  type        = number
  default     = 2048
}

variable "timeout" {
  description = "Function timeout in seconds. Cold starts on this image measured 5-16s once the image is cached, and up to 57s on the first invocation after a deploy."
  type        = number
  default     = 60
}

variable "model_path" {
  description = "Path to the model directory inside the image."
  type        = string
  default     = "/var/task/model/bge-small-en"
}

variable "embedding_dims" {
  description = "Dimensions to return. 0 returns the full vector (384 for bge-small-en)."
  type        = number
  default     = 0
}

variable "architecture" {
  description = "Instruction set for the function. Must match the image you built."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}