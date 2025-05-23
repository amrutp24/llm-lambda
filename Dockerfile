FROM public.ecr.aws/lambda/python:3.11

WORKDIR /var/task

COPY app/ .
COPY requirements.txt .

# ✅ Add echo and fail hard on pip error
RUN echo "Installing Python packages..." && \
    python3 -m pip install --no-cache-dir -r requirements.txt -t /var/task || \
    (echo "❌ pip install failed!" && exit 1)

CMD ["lambda_function.lambda_handler"]
