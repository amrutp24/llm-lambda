from sentence_transformers import SentenceTransformer
import json

model = SentenceTransformer("/var/task/model/bge-small-en")

def lambda_handler(event, context):
    text = event.get("text", "")
    if not text:
        return {"statusCode": 400, "body": "Text missing"}

    embedding = model.encode(text).tolist()
    return {
        "statusCode": 200,
        "body": json.dumps({"embedding": embedding[:5]})  # partial output
    }
