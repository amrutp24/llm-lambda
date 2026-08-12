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

The original stopped building. `requirements.txt` pinned five packages and let the rest
float. `scikit-learn` later dropped its cp311 wheel, pip fell back to a source build, and
the Lambda base image has no compiler. Same again for `Pillow` behind it.

What changed:

- `requirements.txt` is a full 29-package lock, not five top-level pins. Regenerate it from
  a working image with `pip list --format=freeze --path /var/task | sort`.
- torch is the CPU build. The default x86 wheel pulls ~2.6 GB of CUDA libraries that cannot
  run on Lambda. Image drops from 8.43 GB to 2.66 GB. The limit is 10 GB, so the original
  was closer to it than is comfortable. Needs
  `--extra-index-url https://download.pytorch.org/whl/cpu`.
- The model and its imports load inside the handler. Lambda caps `Init` at 10 seconds and
  module scope took ~17.5 s, so init timed out, was thrown away, and ran again inside the
  first invocation for 43 s billed. Init is now 109-514 ms. Cold starts are still 5-16 s:
  this fixes the double load, not the load.
- The Dockerfile installs requirements before `COPY app/ .`, so editing the handler no
  longer rebuilds every dependency. `HF_HOME` and `TRANSFORMERS_CACHE` point at `/tmp`,
  the only writable path.
- The handler returns the full 384-dim vector. It used to truncate to 5. Set
  `EMBEDDING_DIMS` to truncate again, `MODEL_PATH` to point somewhere else.
- Terraform exposes `memory_size`, `timeout`, `architecture`, `model_path` and
  `embedding_dims`. The role name derives from `lambda_name` so the module can be applied
  more than once per account, and the ECR repo sets `force_delete`, without which `destroy`
  fails as soon as an image exists.
- `AmazonEC2ContainerRegistryReadOnly` is off the execution role. Lambda pulls the image
  itself; the role governs what the function calls, and this one calls nothing.
- `deploy_lambda.sh` no longer passes an undefined `--profile`, and takes `REGION`,
  `FUNCTION_NAME`, `IMAGE_NAME` and `ARCH` from the environment.
- Troubleshooting no longer tells you to raise the timeout. That stops the error appearing
  and leaves the doubled init in place.

### arm64

`torch==2.0.1+cpu` is x86-only. aarch64 uses the stock PyPI wheel, already CPU-only because
there is no CUDA on ARM, and `requirements.txt` picks between them with environment markers.

Build and deploy targets must match; Lambda rejects an arm64 image on an x86_64 function.

```bash
ARCH=arm64 ./deploy_lambda.sh
terraform apply -var 'architecture=arm64' -var "image_uri=$IMAGE_URI"
```

Measured on Lambda at 2048 MB, six or seven cold starts each, discarding the first two while
the image cache warms:

| | x86_64 | arm64 |
| --- | --- | --- |
| median cold start | 6.83 s | 5.78 s |
| range | 5.16 – 16.49 s | 4.34 – 14.24 s |
| init | 146 – 514 ms | 109 – 372 ms |
| first invoke after deploy | 56.7 s | 28.3 s |

The ranges overlap, so treat the median difference as directional rather than precise. The
price difference is not: Graviton is ~20% cheaper per GB-second.

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
