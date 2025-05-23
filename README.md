# llm-lambda Project Setup

This project shows how to deploy a SentenceTransformer-based LLM inside an AWS Lambda function using Docker and Terraform. It includes full infrastructure provisioning and model packaging steps to run lightweight inference serverlessly.

---

![License](https://img.shields.io/github/license/amrutp24/llm-lambda)

---

## ✨ What It Does

* Embeds input text into semantic vectors using `bge-small-en`
* Runs inside AWS Lambda using a Docker image (no external inference API)
* Uses Terraform to provision IAM, ECR, and Lambda function infra
* Includes a deploy script to automate Docker build and Lambda updates

---

## 📁 Repo Structure (Updated)

```
llm-lambda/
├── app/
│   ├── lambda_function.py      # Lambda entrypoint
│   └── model/                  # downloaded model dir
├── build_model.py              # downloads model to /app/model
├── requirements.txt            # pinned Python dependencies
├── Dockerfile                  # builds container image
├── deploy_lambda.sh            # standalone script for one-step Docker + Lambda update
├── terraform/
│   ├── main.tf                 # Lambda + ECR resources
│   ├── output.tf               # output values
│   ├── providers.tf            # AWS provider block
│   ├── variables.tf            # declared input variables
│   ├── dev.tfvars              # environment values
│   └── README.md               # Terraform usage
└── LICENSE                     # MIT license
└── README.md                   # this file
```

---

## 🛠 Prerequisites

* [Docker](https://www.docker.com/products/docker-desktop)
* [Terraform](https://www.terraform.io/downloads)
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
* AWS account and credentials configured via `~/.aws/credentials` or environment variables

---

## 🚀 How to Use

### 1. Clone this repo

```bash
git clone https://github.com/amrutp24/llm-lambda.git
cd llm-lambda
```

### 2. Download the model

```bash
python build_model.py
```

### 3. Build and Push the Docker Image

Use the deploy script or manual Docker + ECR commands:

```bash
chmod +x deploy_lambda.sh
./deploy_lambda.sh
```

### 4. Deploy Infrastructure (IAM, ECR, Lambda)

```bash
cd terraform
terraform init
terraform apply -var-file="dev.tfvars"
```

### 5. Test the Lambda

```bash
aws lambda invoke \
  --function-name llm-lambda \
  --payload '{"text": "Deploying LLMs to Lambda"}' \
  --cli-binary-format raw-in-base64-out \
  --region us-east-1 \
  response.json

cat response.json
```

Expected output:

```json
{
  "statusCode": 200,
  "body": "{\"embedding\": [0.12, -0.01, 0.89, ...]}"
}
```

---

## 💡 Use Cases

* Lightweight semantic search services
* On-demand vectorization API
* Background enrichment pipelines
* Building blocks for chatbot memory/context

---

## 🛠 Troubleshooting

* ❌ *"Task timed out after 30.00 seconds"*: Increase `timeout` and `memory_size` in Terraform.
* ❌ *"No module named 'sentence\_transformers'"*: Ensure dependencies are installed inside Docker image.
* ❌ *"Unable to import module"*: Check file paths, and model folder structure.

---

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.

---

## 🎓 Learn More

* [Sentence Transformers](https://www.sbert.net/)
* [AWS Lambda Docker Support](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
* [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

Maintained by \@amrutp24. Contributions welcome!
