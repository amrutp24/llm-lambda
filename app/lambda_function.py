import json
import os

# Path to the model directory baked into the image. Override with the MODEL_PATH
# environment variable to swap models without rebuilding the handler.
MODEL_PATH = os.environ.get("MODEL_PATH", "/var/task/model/bge-small-en")

# How many dimensions to return. Unset (or 0) returns the full vector, which is
# what a vectorization endpoint should do - bge-small-en produces 384. Set it to
# a small number if you only want a readable sample in a demo.
EMBEDDING_DIMS = int(os.environ.get("EMBEDDING_DIMS", "0"))

# The model and its imports are loaded lazily, inside the handler, rather than at
# module scope.
#
# Lambda caps the Init phase at 10 seconds. Importing torch (~8.5s) and loading
# bge-small-en (~5.2s) takes ~17.5s, so module-level loading blows that budget:
# Lambda discards the timed-out init and re-runs it inside the first invocation.
# Measured on a 2048 MB function, that was INIT_REPORT Status: timeout at 9996ms
# followed by a 43s billed invocation. Loading here keeps Init at ~150ms and the
# cost is paid once, on the first invocation, where Duration actually shows it.
_model = None


def _get_model():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer

        _model = SentenceTransformer(MODEL_PATH)
    return _model


def lambda_handler(event, context):
    text = event.get("text", "")
    if not text:
        return {"statusCode": 400, "body": "Text missing"}

    embedding = _get_model().encode(text).tolist()
    if EMBEDDING_DIMS > 0:
        embedding = embedding[:EMBEDDING_DIMS]

    return {
        "statusCode": 200,
        "body": json.dumps({"embedding": embedding, "dims": len(embedding)}),
    }
