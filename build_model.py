from sentence_transformers import SentenceTransformer
import os

print("Starting model download...")

model = SentenceTransformer("BAAI/bge-small-en")
save_path = "app/model/bge-small-en"
os.makedirs(save_path, exist_ok=True)
model.save(save_path)

print(f"Model saved to: {save_path}")
