import asyncio
import base64
import binascii
import io
import json
import logging
import math
import random
import threading
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
from PIL import Image, ImageFilter, UnidentifiedImageError

logger = logging.getLogger(__name__)

# The 60 QuickDraw categories the model is trained on. The order matters: it is the order of the
# model's outputs. scripts/train_quickdraw.py embeds this list inside the .onnx file, and the
# backend prefers the embedded list when it is present.
QUICKDRAW_CLASSES: List[str] = [
    "apple", "banana", "bicycle", "bird", "book", "bridge", "bus", "butterfly",
    "cake", "car", "cat", "chair", "clock", "cloud", "coffee cup", "computer",
    "crown", "cup", "dog", "dolphin", "door", "elephant", "eye", "face", "fish",
    "flower", "frog", "guitar", "hammer", "hand", "hat", "helicopter", "house",
    "ice cream", "key", "laptop", "leaf", "light bulb", "lion", "moon", "mountain",
    "mushroom", "octopus", "pencil", "pizza", "rabbit", "shoe", "snake", "star",
    "sun", "sword", "table", "telephone", "tree", "truck", "umbrella", "violin",
    "whale", "windmill", "zebra",
]

# --- Scoring rules --------------------------------------------------------------------------
ACCURACY_MAX_POINTS = 70.0
SPEED_MAX_POINTS = 30.0
MAX_SCORE = 100.0

# --- Preprocessing constants ------------------------------------------------------------------
IMG_SIZE = 28
MAX_INPUT_PIXELS = 4_000_000   # reject absurdly large images (decompression-bomb guard)
MIN_PEAK_CONTRAST = 40.0       # below this the canvas is treated as empty
INK_THRESHOLD = 0.15           # fraction of peak contrast that counts as "stroke"
MIN_INK_PIXELS = 8
TARGET_SPAN = 26               # the drawing should span ~26 of the 28 pixels (QuickDraw style)
STROKE_SCALE = 1.2             # thickens strokes so they survive the downscale (~1.5px at 28x28)
WORK_SIZE = IMG_SIZE * 8       # strokes are thickened at 224 px, not at full canvas size (fast)


class InvalidDrawingError(ValueError):
    """The uploaded drawing could not be decoded as an image."""


# =================================================================================================
# Preprocessing
# =================================================================================================
def decode_image(base64_data: str) -> Image.Image:
    if not base64_data:
        raise InvalidDrawingError("Empty drawing")

    payload = base64_data
    if payload.startswith("data:") and "," in payload[:100]:
        payload = payload.split(",", 1)[1]
    payload = "".join(payload.split())

    try:
        raw = base64.b64decode(payload, validate=True)
    except (binascii.Error, ValueError):
        raise InvalidDrawingError("Drawing is not valid base64")

    try:
        image = Image.open(io.BytesIO(raw))
        if image.width * image.height > MAX_INPUT_PIXELS:
            raise InvalidDrawingError("Drawing image is too large")
        image.load()
    except InvalidDrawingError:
        raise
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError):
        raise InvalidDrawingError("Drawing is not a valid image")
    return image


def _ink_map(image: Image.Image) -> np.ndarray:
    """Return a float32 map where 0 = background and larger = stroke (polarity independent)."""
    rgba = np.asarray(image.convert("RGBA"))
    alpha = rgba[..., 3]

    # Transparent canvas: the alpha channel *is* the drawing.
    if (alpha < 250).any():
        return alpha.astype(np.float32)

    # Opaque canvas (what the Flutter app sends): ink = difference from the background colour,
    # so white-on-dark and black-on-white both work.
    gray = np.asarray(image.convert("L"), dtype=np.float32)
    border = np.concatenate([gray[0, :], gray[-1, :], gray[:, 0], gray[:, -1]])
    background = float(np.median(border))
    return np.abs(gray - background)


def _nearest_odd(value: float) -> int:
    """The odd integer closest to `value` (dilation kernels must have an odd size)."""
    return max(1, 2 * round((value - 1) / 2) + 1)


def drawing_to_array(image: Image.Image) -> Optional[np.ndarray]:
    """Turn a canvas image into a (1, 1, 28, 28) float32 array in QuickDraw format.

    QuickDraw bitmaps are white strokes on black, centred, and scaled so the drawing fills the
    frame. We mimic that: find the strokes, crop to their bounding box, pad to a square, thicken,
    and shrink to 28x28. Returns None for an empty canvas.
    """
    ink = _ink_map(image)
    peak = float(ink.max()) if ink.size else 0.0
    if peak < MIN_PEAK_CONTRAST:
        return None
    ink = ink / peak

    ys, xs = np.where(ink >= INK_THRESHOLD)
    if ys.size < MIN_INK_PIXELS:
        return None

    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    crop = ink[y0:y1, x0:x1]
    height, width = crop.shape
    side = max(height, width)

    padded_side = int(math.ceil(side * IMG_SIZE / TARGET_SPAN))
    square = Image.new("L", (padded_side, padded_side), 0)
    crop_img = Image.fromarray((np.clip(crop, 0.0, 1.0) * 255).astype(np.uint8), mode="L")
    square.paste(crop_img, ((padded_side - width) // 2, (padded_side - height) // 2))

    # Shrink to a small working size BEFORE thickening: the dilation filter costs time
    # proportional to (image area x kernel area), which is slow on a full-size canvas.
    resample = Image.Resampling.BOX if padded_side >= WORK_SIZE else Image.Resampling.BILINEAR
    square = square.resize((WORK_SIZE, WORK_SIZE), resample)

    kernel = _nearest_odd(WORK_SIZE / IMG_SIZE * STROKE_SCALE)
    if kernel > 1:
        square = square.filter(ImageFilter.MaxFilter(kernel))

    small = square.resize((IMG_SIZE, IMG_SIZE), Image.Resampling.BOX)
    array = np.asarray(small, dtype=np.float32) / 255.0
    top = float(array.max())
    if top <= 0.0:
        return None
    array = array / top
    return array.reshape(1, 1, IMG_SIZE, IMG_SIZE)


def preprocess_drawing(base64_data: str) -> Optional[np.ndarray]:
    """base64 PNG -> model input, or None if the canvas is empty. Raises InvalidDrawingError."""
    return drawing_to_array(decode_image(base64_data))


# =================================================================================================
# Model loading and inference
# =================================================================================================
_lock = threading.Lock()
_loaded = False
_session = None
_labels: List[str] = list(QUICKDRAW_CLASSES)
_input_name = "input"
_channels_last = False


def reset_model_cache() -> None:
    """Forget the loaded model (used by tests and after replacing the .onnx file)."""
    global _loaded, _session, _labels
    with _lock:
        _loaded = False
        _session = None
        _labels = list(QUICKDRAW_CLASSES)


def _load_model(path: Optional[Path] = None) -> None:
    global _loaded, _session, _labels, _input_name, _channels_last
    with _lock:
        if _loaded:
            return
        _loaded = True

        if path is None:
            from app.core.config import settings

            path = settings.model_file

        if not Path(path).exists():
            logger.warning(
                "ONNX model not found at %s - using the MOCK classifier. "
                "Run scripts/train_quickdraw.py to create a real model.",
                path,
            )
            return

        try:
            import onnxruntime as ort

            session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
            meta = session.get_modelmeta().custom_metadata_map or {}
            labels = QUICKDRAW_CLASSES
            if "labels" in meta:
                labels = json.loads(meta["labels"])

            model_input = session.get_inputs()[0]
            shape = model_input.shape
            _channels_last = len(shape) == 4 and shape[-1] == 1 and shape[1] != 1
            _input_name = model_input.name
            _labels = list(labels)
            _session = session
            logger.info("Loaded ONNX model %s (%d classes)", path, len(_labels))
        except Exception:
            logger.exception("Could not load ONNX model %s - using the MOCK classifier", path)
            _session = None


def model_info() -> Dict[str, object]:
    _load_model()
    return {
        "backend": "onnx" if _session is not None else "mock",
        "classes": len(_labels),
    }


def _softmax(values: np.ndarray) -> np.ndarray:
    shifted = values - values.max()
    exp = np.exp(shifted)
    return exp / exp.sum()


def _run_model(processed: np.ndarray) -> np.ndarray:
    data = processed.transpose(0, 2, 3, 1) if _channels_last else processed
    output = _session.run(None, {_input_name: np.ascontiguousarray(data, dtype=np.float32)})[0][0]
    output = np.asarray(output, dtype=np.float64)
    # Accept models that return logits as well as probabilities.
    if (output < 0).any() or abs(float(output.sum()) - 1.0) > 1e-3:
        output = _softmax(output)
    return output


def mock_inference(processed: np.ndarray, prompt: str) -> Tuple[str, float, float]:
    """Stand-in classifier used only when no ONNX model is available.

    Returns (label, confidence, prompt_confidence).
    """
    prompt_lower = prompt.lower().strip()
    if prompt_lower in QUICKDRAW_CLASSES:
        if random.random() > 0.3:
            confidence = random.uniform(0.45, 0.95)
            return prompt_lower, confidence, confidence
        wrong = random.choice([c for c in QUICKDRAW_CLASSES if c != prompt_lower])
        return wrong, random.uniform(0.1, 0.5), random.uniform(0.0, 0.3)
    return random.choice(QUICKDRAW_CLASSES), random.uniform(0.1, 0.6), 0.0


def classify(processed: np.ndarray, prompt: str) -> Tuple[str, float, float]:
    """Return (recognized_label, confidence, probability_of_the_prompt_class)."""
    _load_model()
    if _session is None:
        return mock_inference(processed, prompt)

    probabilities = _run_model(processed)
    top = int(np.argmax(probabilities))
    label = _labels[top] if top < len(_labels) else str(top)

    prompt_lower = prompt.lower().strip()
    prompt_probability = 0.0
    if prompt_lower in _labels:
        prompt_probability = float(probabilities[_labels.index(prompt_lower)])

    return label, float(probabilities[top]), prompt_probability


# =================================================================================================
# Scoring
# =================================================================================================
def calculate_score(
    recognized_as: str,
    confidence: float,
    prompt: str,
    time_taken: float,
    max_time: float = 60.0,
    blank: bool = False,
    prompt_confidence: Optional[float] = None,
) -> dict:
    """
    Accuracy-first scoring (max 100):

        score = prompt_confidence x (70 + 30 x time_left / max_time)

    * prompt_confidence is how sure the AI is that the drawing is the PROMPT (not just the label
      it likes best), so a confident wrong guess scores about 0 and nothing can be gamed by
      drawing something easy to recognise.
    * Speed only counts in proportion to accuracy: a fast scribble earns almost nothing.
    * If prompt_confidence is not given, it is the AI's confidence when its best guess is the
      prompt and 0 otherwise.
    An empty canvas scores 0.
    """
    if blank:
        return {
            "score": 0.0,
            "accuracy_score": 0.0,
            "speed_bonus": 0.0,
            "matched": False,
            "recognized_as": "",
            "confidence": 0.0,
            "prompt_confidence": 0.0,
        }

    matched = recognized_as.lower().strip() == prompt.lower().strip()
    confidence = min(max(float(confidence), 0.0), 1.0)
    if prompt_confidence is None:
        prompt_confidence = confidence if matched else 0.0
    prompt_confidence = min(max(float(prompt_confidence), 0.0), 1.0)
    time_taken = min(max(float(time_taken), 0.0), max_time)

    accuracy_score = prompt_confidence * ACCURACY_MAX_POINTS
    time_left = (max_time - time_taken) / max_time
    speed_bonus = time_left * SPEED_MAX_POINTS * prompt_confidence

    total = min(MAX_SCORE, accuracy_score + speed_bonus)

    return {
        "score": round(total, 2),
        "accuracy_score": round(accuracy_score, 2),
        "speed_bonus": round(speed_bonus, 2),
        "matched": matched,
        "recognized_as": recognized_as,
        "confidence": round(confidence, 4),
        "prompt_confidence": round(prompt_confidence, 4),
    }


def score_drawing_sync(
    drawing_data: str,
    prompt: str,
    time_taken: float,
    max_time: float = 60.0,
) -> dict:
    """Decode, classify and score one drawing. Raises InvalidDrawingError for bad input."""
    processed = preprocess_drawing(drawing_data)

    if processed is None:
        result = calculate_score("", 0.0, prompt, time_taken, max_time, blank=True)
        result["blank"] = True
    else:
        label, confidence, prompt_confidence = classify(processed, prompt)
        result = calculate_score(
            label,
            confidence,
            prompt,
            time_taken,
            max_time,
            prompt_confidence=prompt_confidence,
        )
        result["blank"] = False

    result["model"] = model_info()["backend"]
    return result


async def score_drawing(drawing_data: str, prompt: str, time_taken: float) -> dict:
    """Async wrapper kept for older callers; runs the blocking work in a thread."""
    return await asyncio.to_thread(score_drawing_sync, drawing_data, prompt, time_taken)


def predict_drawing(drawing_data: str, prompt: str) -> dict:
    """Live preview: what does the AI see right now? Nothing is scored or stored.

    `prompt_confidence` is the number that would drive the score if the player handed in now.
    """
    processed = preprocess_drawing(drawing_data)
    info = model_info()

    if processed is None:
        return {
            "recognized_as": "",
            "confidence": 0.0,
            "prompt_confidence": 0.0,
            "matches_prompt": False,
            "blank": True,
            "model": info["backend"],
        }

    label, confidence, prompt_confidence = classify(processed, prompt)
    return {
        "recognized_as": label,
        "confidence": round(confidence, 4),
        "prompt_confidence": round(prompt_confidence, 4),
        "matches_prompt": label.lower().strip() == prompt.lower().strip(),
        "blank": False,
        "model": info["backend"],
    }
