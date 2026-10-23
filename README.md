# llm-lambda

Serves the `bge-small-en` sentence-embedding model from an AWS Lambda container image, deployed with Terraform. Send it text and it returns a 384-dimension vector. Nothing calls an external inference API; the model is baked into the image.

![License](https://img.shields.io/github/license/amrutp24/llm-lambda)

The first version of this stopped building after about a year. What broke and what I changed is written up in [I put an embedding model in a Lambda container. A year later, here's what I got wrong](https://amruteng.medium.com/i-put-an-embedding-model-in-a-lambda-container-a-year-later-heres-what-i-got-wrong-bcc1dc6995f4), and summarized below.

## What's in the repo

```
llm-lambda/
├── app/
│   └── lambda_function.py   # handler; loads the model on first invoke
├── build_model.py           # downloads bge-small-en to app/model/bge-small-en
├── requirements.txt         # full dependency lock (29 packages)
├── Dockerfile               # Lambda Python 3.11 base image
├── deploy_lambda.sh         # builds, pushes, and updates the function's image
└── terraform/
    ├── main.tf              # ECR repository, IAM role, Lambda function
    ├── variable.tf          # inputs
    ├── outputs.tf
    ├── providers.tf
    └── README.md
```

`app/model/` is not committed. `build_model.py` creates it.

## Requirements

- Docker
- Terraform
- AWS CLI, with credentials configured
- Python with `sentence-transformers`, to run `build_model.py`

## First deploy

The Lambda function needs an image in ECR before Terraform can create it, and the deploy script's last step needs the function to exist. So the first deploy goes in three steps: create the ECR repository, push an image, then create everything else.

```bash
git clone https://github.com/amrutp24/llm-lambda.git
cd llm-lambda
python build_model.py

# 1. ECR repository only. image_uri is required but not used yet.
cd terraform
terraform init
terraform apply -target=aws_ecr_repository.llm_lambda -var 'image_uri=unused'
cd ..

# 2. Build and push. The script's final update-function-code step fails on a
#    first deploy because the function doesn't exist yet; the push has already
#    happened by then.
./deploy_lambda.sh

# 3. Everything else. Same image URI the script just pushed.
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
cd terraform
terraform apply -var "image_uri=$ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/llm-lambda:latest"
```

After that, code changes deploy with `./deploy_lambda.sh` alone. `terraform apply` won't pick up a new image on its own, because `image_uri` still says `:latest` and the plan is empty.

## Calling it

```bash
aws lambda invoke \
  --function-name llm-lambda \
  --payload '{"text": "Deploying LLMs to Lambda"}' \
  --cli-binary-format raw-in-base64-out \
  --region us-east-1 \
  response.json

cat response.json
```

```json
{
  "statusCode": 200,
  "body": "{\"embedding\": [0.12, -0.01, 0.89, ...], \"dims\": 384}"
}
```

An event with no `text` returns `400`.

## Settings

Terraform variables, all optional except `image_uri`:

| variable | default | |
| --- | --- | --- |
| `lambda_name` | `llm-lambda` | names the function, the ECR repository and the IAM role |
| `region` | `us-east-1` | |
| `memory_size` | `2048` | CPU scales with memory, so this is the main lever on cold-start time |
| `timeout` | `60` | |
| `architecture` | `x86_64` | `x86_64` or `arm64`; must match the image |
| `model_path` | `/var/task/model/bge-small-en` | |
| `embedding_dims` | `0` | `0` returns the full vector; anything else truncates it |

`deploy_lambda.sh` reads `REGION`, `FUNCTION_NAME`, `IMAGE_NAME` and `ARCH` from the environment. `FUNCTION_NAME` and `IMAGE_NAME` have to match `lambda_name`.

## Changes since the original version

The original stopped building. `requirements.txt` pinned five packages and let the rest float. `scikit-learn` later dropped its cp311 wheel, pip fell back to a source build, and the Lambda base image has no compiler. Same again for `Pillow` behind it.

What changed:

- `requirements.txt` is a full 29-package lock, not five top-level pins. Regenerate it from a working image with `pip list --format=freeze --path /var/task | sort`.
- torch is the CPU build. The default x86 wheel pulls about 2.6 GB of CUDA libraries that can't run on Lambda. The image drops from 8.43 GB to 2.66 GB. The limit is 10 GB, so the original was closer to it than is comfortable. Needs `--extra-index-url https://download.pytorch.org/whl/cpu`.
- The model and its imports load inside the handler. Lambda caps `Init` at 10 seconds and module scope took about 17.5 s, so init timed out, was thrown away, and ran again inside the first invocation for 43 s billed. Init is now 109 to 514 ms. Cold starts are still 5 to 16 s; this fixes the double load, not the load.
- The Dockerfile installs requirements before `COPY app/ .`, so editing the handler no longer rebuilds every dependency. `HF_HOME` and `TRANSFORMERS_CACHE` point at `/tmp`, the only writable path.
- The handler returns the full 384-dimension vector. It used to truncate to 5. Set `EMBEDDING_DIMS` to truncate again, `MODEL_PATH` to point somewhere else.
- Terraform exposes `memory_size`, `timeout`, `architecture`, `model_path` and `embedding_dims`. The role name derives from `lambda_name` so the configuration can be applied more than once per account, and the ECR repository sets `force_delete`, without which `destroy` fails as soon as an image exists.
- `AmazonEC2ContainerRegistryReadOnly` is off the execution role. Lambda pulls the image itself; the role governs what the function calls, and this one calls nothing.
- `deploy_lambda.sh` no longer passes an undefined `--profile`, and takes `REGION`, `FUNCTION_NAME`, `IMAGE_NAME` and `ARCH` from the environment.
- Troubleshooting no longer tells you to raise the timeout. That stops the error appearing and leaves the doubled init in place.

### arm64

`torch==2.0.1+cpu` is x86-only. aarch64 uses the stock PyPI wheel, which is already CPU-only because there is no CUDA on ARM, and `requirements.txt` picks between them with environment markers.

Build and deploy targets must match; Lambda rejects an arm64 image on an x86_64 function.

```bash
ARCH=arm64 ./deploy_lambda.sh
terraform apply -var 'architecture=arm64' -var "image_uri=$IMAGE_URI"
```

Measured on Lambda at 2048 MB, six or seven cold starts each, discarding the first two while the image cache warms:

| | x86_64 | arm64 |
| --- | --- | --- |
| median cold start | 6.83 s | 5.78 s |
| range | 5.16 to 16.49 s | 4.34 to 14.24 s |
| init | 146 to 514 ms | 109 to 372 ms |
| first invoke after deploy | 56.7 s | 28.3 s |

The ranges overlap, so treat the median difference as directional rather than precise. The price difference is not: Graviton is about 20% cheaper per GB-second.

## Troubleshooting

**"Task timed out after N seconds" on the first invocation, then fine afterwards.** This is almost certainly the init phase, not your handler. Lambda limits `Init` to 10 seconds; if module-level code (importing torch, loading the model) runs longer, Lambda discards the init and re-runs it inside your first invocation, billed against the function timeout. Raising `timeout` hides it but doesn't fix it. Check `Init Duration` in the CloudWatch `REPORT` line and get it under 10 s. The CPU-only torch build is the biggest single win. See [Lambda execution environment lifecycle](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtime-environment.html).

**pip tries to compile a package from source and fails with `no such file or directory: 'gcc'`.** A dependency resolved to a version with no wheel for this Python version. The Lambda base image has no compiler by design. Pin the package in `requirements.txt`, which is a full lock for this reason.

**"No module named 'sentence_transformers'".** The dependencies didn't install into the image. Check the `docker build` output for pip errors.

**"Unable to import module".** Check that `app/` was copied into the image and that the model directory matches `MODEL_PATH`.

## License

MIT. See [LICENSE](LICENSE).
