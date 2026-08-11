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

## 🔧 Changes since the original version

The original version stopped building. It was fine when it shipped in May 2025, but
`requirements.txt` pinned only five packages and let every transitive dependency float. By
2026 pip resolved `scikit-learn` to a release with no cp311 wheel, fell back to compiling
from source, and failed because the Lambda base image has no C compiler. Pinning past that
hit the same wall on `Pillow`.

What changed:

`requirements.txt` is now a full lock. All 29 resolved packages are pinned, not just the
five top-level ones. Regenerate it from a known-good image with:

```bash
docker run --rm --entrypoint /bin/sh <image> \
  -c "python3 -m pip list --format=freeze --path /var/task" | sort
```

torch is now the CPU build, `torch==2.0.1+cpu`. The default x86 wheel is compiled with
CUDA enabled, so pip also pulled `nvidia-cudnn`, `nvidia-cublas`, `nvidia-nccl` and six
others — 2.6 GB unpacked. Lambda has no GPU, and the handler never requested one, so none of
it could ever execute. Removing it takes the image from **8.43 GB to 2.66 GB**. Note that
Lambda's container image limit is 10 GB, so the original was within 1.6 GB of a hard ceiling.

This needs the extra index in `requirements.txt`:

```
--extra-index-url https://download.pytorch.org/whl/cpu
```

`AmazonEC2ContainerRegistryReadOnly` is gone from the Lambda execution role. Lambda
pulls the container image itself before your code runs; the execution role governs what the
*function* calls at runtime, and this function calls nothing. The policy granted read access
to every ECR repository in the account for no benefit. The `depends_on` in
`aws_lambda_function.llm_lambda` was updated to match.

`deploy_lambda.sh` no longer passes `--profile $PROFILE`. That variable was deleted from
the config block but the flags were left behind, so the script expanded them to
`--profile ""` and failed on the first AWS call. It now uses the standard credential chain,
so `AWS_PROFILE=dev ./deploy_lambda.sh` works.

Troubleshooting was rewritten. The old entry told you to raise `timeout` and
`memory_size` for a first-invocation timeout. That hides the symptom. See the section below.

arm64 builds cleanly and is ~400 MB smaller (image 2.35 GB vs 2.88 GB; torch unpacks to
319 MB vs 722 MB), plus Graviton is ~20% cheaper per GB-second. Note `torch==2.0.1+cpu` is
x86-only — aarch64 needs the stock PyPI wheel, which is already CPU-only since there is no
CUDA on ARM. `requirements.txt` uses environment markers to pick the right one. Build it
with:

```bash
docker buildx build --platform linux/arm64 -t llm-lambda:arm64 --load .
```

The deploy script still hardcodes `--platform linux/amd64`, and `architectures` is not set
on the Lambda resource, so switching targets means changing both. Neither arm64 nor the
lazy-loading change has been measured on real Lambda yet.

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

* ❌ *"Task timed out after N seconds"* on the **first** invocation, then fine afterwards:
  this is almost certainly the init phase, not your handler. Lambda limits `Init` to
  10 seconds; if module-level code (importing torch, loading the model) runs longer, Lambda
  discards the init and re-runs it inside your first invocation, billed against the function
  timeout. Raising `timeout` hides it; it does not fix it. Check `Init Duration` in the
  CloudWatch `REPORT` line and get it under 10s — the CPU-only torch build is the biggest
  single win. See
  [Lambda execution environment lifecycle](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtime-environment.html).
* ❌ *pip tries to compile a package from source and fails with `no such file or directory: 'gcc'`*:
  a dependency resolved to a version with no wheel for this Python version. The Lambda base
  image has no compiler by design. Pin the offending package in `requirements.txt` — that
  file is a full lock for this reason.
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
