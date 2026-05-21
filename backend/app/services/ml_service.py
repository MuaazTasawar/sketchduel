import base64
import io
import json
import numpy as np
from PIL import Image
from typing import Tuple

# QuickDraw classes subset — 50 most common drawings
QUICKDRAW_CLASSES = [
    "apple","banana","bicycle","bird","book","bridge","bus","butterfly",
    "cake","car","cat","chair","clock","cloud","coffee cup","computer",
    "crown","cup","dog","dolphin","door","elephant","eye","face","fish",
    "flower","frog","guitar","hammer","hand","hat","helicopter","house",
    "ice cream","key","lamp","laptop","leaf","lion","moon","mountain",
    "mushroom","octopus","pencil","pizza","rabbit","shoe","snake","star",
    "sun","sword","table","telephone","tree","truck","umbrella","violin",
    "whale","windmill","zebra"
]

def preprocess_drawing(base64_data: str) -> np.ndarray:
    """Convert base64 drawing to 28x28 grayscale numpy array (QuickDraw format)."""
    if "," in base64_data:
        base64_data = base64_data.split(",")[1]
    
    image_bytes = base64.b64decode(base64_data)
    image = Image.open(io.BytesIO(image_bytes)).convert("L")  # grayscale
    image = image.resize((28, 28), Image.LANCZOS)
    
    # Invert — QuickDraw uses white strokes on black
    image_array = np.array(image)
    image_array = 255 - image_array
    image_array = image_array.astype(np.float32) / 255.0
    
    return image_array.reshape(1, 28, 28, 1)

def mock_inference(processed: np.ndarray, prompt: str) -> Tuple[str, float]:
    """
    Placeholder for TFLite model inference.
    Replace with actual tflite model when deployed.
    Returns (recognized_label, confidence_score).
    """
    # In production: load quickdraw.tflite and run inference
    # model = tflite.Interpreter(model_path="quickdraw.tflite")
    # model.allocate_tensors()
    # model.set_tensor(input_details[0]['index'], processed)
    # model.invoke()
    # output = model.get_tensor(output_details[0]['index'])
    # top_idx = np.argmax(output)
    # return QUICKDRAW_CLASSES[top_idx], float(output[0][top_idx])
    
    import random
    prompt_lower = prompt.lower()
    if prompt_lower in QUICKDRAW_CLASSES:
        # Simulate realistic confidence
        confidence = random.uniform(0.45, 0.95)
        if random.random() > 0.3:
            return prompt_lower, confidence
        else:
            wrong_label = random.choice([c for c in QUICKDRAW_CLASSES if c != prompt_lower])
            return wrong_label, random.uniform(0.1, 0.5)
    return random.choice(QUICKDRAW_CLASSES), random.uniform(0.1, 0.6)

def calculate_score(
    recognized_as: str,
    confidence: float,
    prompt: str,
    time_taken: float,
    max_time: float = 60.0
) -> dict:
    """
    Scoring formula:
    - Base score: confidence * 60 points
    - Speed bonus: up to 25 points (faster = more)
    - Bluff bonus: 15 points if AI misidentifies but player scores anyway
    - Total: max 100 points
    """
    prompt_lower = prompt.lower().strip()
    recognized_lower = recognized_as.lower().strip()
    bluff_detected = recognized_lower != prompt_lower

    base_score = confidence * 60.0

    time_ratio = max(0, (max_time - time_taken) / max_time)
    speed_bonus = time_ratio * 25.0

    bluff_bonus = 0.0
    if bluff_detected and confidence > 0.6:
        # AI is confident it's something else — successful bluff
        bluff_bonus = 15.0

    total = min(100.0, base_score + speed_bonus + bluff_bonus)

    return {
        "score": round(total, 2),
        "base_score": round(base_score, 2),
        "speed_bonus": round(speed_bonus, 2),
        "bluff_bonus": round(bluff_bonus, 2),
        "bluff_detected": bluff_detected,
        "recognized_as": recognized_as,
        "confidence": round(confidence, 4)
    }

async def score_drawing(drawing_data: str, prompt: str, time_taken: float) -> dict:
    processed = preprocess_drawing(drawing_data)
    recognized_as, confidence = mock_inference(processed, prompt)
    result = calculate_score(recognized_as, confidence, prompt, time_taken)
    return result