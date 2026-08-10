import json

# The model and its imports are loaded lazily, inside the handler, rather than at
# module scope.
#
# Lambda caps the Init phase at 10 seconds. Importing torch (~8.5s) and loading
# bge-small-en (~5.2s) takes ~17.5s, so module-level loading blows that budget:
# Lambda discards the timed-out init and re-runs it inside the first invocation,
# billing ~41s for what is ~17.5s of work. INIT_REPORT reports Status: timeout,
# and that log line only appears when init fails, so it is easy to miss.
#
# Loading here means Init stays trivial and the cost is paid once, on the first
# invocation, where it is visible in Duration. Subsequent invocations reuse the
# cached model exactly as before.
_model = None


def _get_model():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer

        _model = SentenceTransformer("/var/task/model/bge-small-en")
    return _model


def lambda_handler(event, context):
    text = event.get("text", "")
    if not text:
        return {"statusCode": 400, "body": "Text missing"}

    embedding = _get_model().encode(text).tolist()
    return {
        "statusCode": 200,
        "body": json.dumps({"embedding": embedding[:5]})  # partial output
    }
