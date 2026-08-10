FROM public.ecr.aws/lambda/python:3.11

WORKDIR /var/task

# Only /tmp is writable in a Lambda execution environment. The model is baked into
# the image so nothing is downloaded at runtime, but huggingface still probes its
# cache directory on import and the failed write costs time inside the 10s init
# budget. Without this you get, on every cold start:
#   There was a problem when trying to write in your cache folder
#   (/home/sbx_userNNNN/.cache/huggingface/hub)
ENV HF_HOME=/tmp
ENV TRANSFORMERS_CACHE=/tmp

# Dependencies first, application code second. Docker invalidates every layer
# after the first one that changes, so copying app/ before installing meant any
# edit to the handler or the model re-ran the whole pip install and re-pushed
# ~2.7 GB to ECR. In this order a code change rebuilds and pushes only the last
# layer.
COPY requirements.txt .

# ✅ Add echo and fail hard on pip error
RUN echo "Installing Python packages..." && \
    python3 -m pip install --no-cache-dir -r requirements.txt -t /var/task || \
    (echo "❌ pip install failed!" && exit 1)

COPY app/ .

CMD ["lambda_function.lambda_handler"]
