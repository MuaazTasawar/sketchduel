"""How well does the trained model recognise drawings made on the SketchDuel canvas?

The training script reports accuracy on QuickDraw's own 28x28 images. Players, however, draw with
a 4-pixel stroke on a canvas several hundred pixels wide, and ml_service has to turn that into
something the model understands. This script measures the WHOLE chain:

    real human strokes (QuickDraw "simplified" vectors)
      -> drawn on a dark canvas the way the Flutter app draws (white, 4 px, random size/position)
      -> ml_service preprocessing -> ONNX model -> top-1 / top-3 accuracy

Run from the backend folder:

    python scripts/evaluate_model.py                  # ~1-2 minutes, downloads ~15 MB once
    python scripts/evaluate_model.py --tune           # also tries other preprocessing settings
    python scripts/evaluate_model.py --per-class 80   # steadier numbers

It uses drawings from further into each category's file than the training script read, so the
model has not seen them.
"""
import argparse
import json
import random
import sys
import urllib.parse
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

import train_quickdraw as tq  # noqa: E402  (reuses its download helpers; torch is not imported)
from app.services import ml_service as ml  # noqa: E402

SIMPLIFIED_URL = "https://storage.googleapis.com/quickdraw_dataset/full/simplified/"
CANVAS_SIZES = [(360, 420), (600, 420), (700, 500)]  # phone, laptop, wide window
BACKGROUND = (26, 26, 46)
STROKE = (255, 255, 255)
STROKE_WIDTH = 4

Strokes = List[List[List[float]]]  # [[xs, ys], [xs, ys], ...]


# ------------------------------------------------------------------------------------------------
# Data
# ------------------------------------------------------------------------------------------------
def fetch_drawings(
    name: str,
    count: int,
    offset_mb: float,
    cache_dir: Path,
    base_url: str,
    recognized_only: bool,
) -> List[Strokes]:
    """Up to `count` human drawings of one category, taken from `offset_mb` into its file."""
    cache = cache_dir / f"{name}.ndjson"
    if not cache.exists():
        url = base_url + urllib.parse.quote(name) + ".ndjson"
        start = int(offset_mb * 1_000_000)
        size = max(count, 20) * 2500  # ~1 KB per drawing on average; generous on purpose
        data, status = tq._with_retries(lambda: tq._http_range(url, start, start + size - 1))
        if status == 200 and len(data) > size * 2:  # the server ignored the Range header
            data = data[start : start + size]
        cache_dir.mkdir(parents=True, exist_ok=True)
        cache.write_bytes(data)

    text = cache.read_bytes().decode("utf-8", errors="ignore")
    lines = text.split("\n")[1:-1]  # the first and last lines are cut off mid-way
    drawings: List[Strokes] = []
    for line in lines:
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if recognized_only and not record.get("recognized"):
            continue
        strokes = record.get("drawing")
        if strokes and all(len(s) >= 2 and len(s[0]) > 0 for s in strokes):
            drawings.append(strokes)
        if len(drawings) >= count:
            break
    return drawings


def render_drawing(strokes: Strokes, rng: random.Random) -> Image.Image:
    """Draw the strokes the way a player would: white on the app's dark canvas, random placement."""
    width, height = rng.choice(CANVAS_SIZES)
    xs = [x for stroke in strokes for x in stroke[0]]
    ys = [y for stroke in strokes for y in stroke[1]]
    min_x, min_y = min(xs), min(ys)
    span_x, span_y = max(max(xs) - min_x, 1.0), max(max(ys) - min_y, 1.0)

    target = rng.uniform(0.55, 0.95) * min(width, height)
    scale = target / max(span_x, span_y)
    left = (width - span_x * scale) * rng.uniform(0.2, 0.8)
    top = (height - span_y * scale) * rng.uniform(0.2, 0.8)

    image = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(image)
    for stroke in strokes:
        points = [(left + (x - min_x) * scale, top + (y - min_y) * scale) for x, y in zip(stroke[0], stroke[1])]
        if len(points) == 1:
            x, y = points[0]
            draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=STROKE)
        else:
            draw.line(points, fill=STROKE, width=STROKE_WIDTH, joint="curve")
    return image


# ------------------------------------------------------------------------------------------------
# Scoring
# ------------------------------------------------------------------------------------------------
def top_labels(image: Image.Image, k: int = 3) -> Optional[List[str]]:
    """The model's k best guesses for a canvas image (None if the canvas counts as empty)."""
    array = ml.drawing_to_array(image)
    if array is None:
        return None
    probabilities = ml._run_model(array)  # noqa: SLF001 - a diagnostic tool may look inside
    order = np.argsort(probabilities)[::-1][:k]
    return [ml._labels[i] for i in order]  # noqa: SLF001


def evaluate(dataset: Dict[str, List[Image.Image]]) -> Dict[str, object]:
    per_class: Dict[str, List[int]] = defaultdict(lambda: [0, 0, 0])  # total, top1, top3
    confusions: Dict[str, Counter] = defaultdict(Counter)
    for truth, images in dataset.items():
        for image in images:
            guesses = top_labels(image)
            per_class[truth][0] += 1
            if guesses is None:
                confusions[truth]["(blank)"] += 1
                continue
            if guesses[0] == truth:
                per_class[truth][1] += 1
            else:
                confusions[truth][guesses[0]] += 1
            if truth in guesses:
                per_class[truth][2] += 1

    total = sum(v[0] for v in per_class.values())
    top1 = sum(v[1] for v in per_class.values())
    top3 = sum(v[2] for v in per_class.values())
    return {
        "total": total,
        "top1": top1 / total if total else 0.0,
        "top3": top3 / total if total else 0.0,
        "per_class": per_class,
        "confusions": confusions,
    }


def percent(value: float) -> str:
    return f"{value * 100:5.1f}%"


# ------------------------------------------------------------------------------------------------
def load_prompts() -> Optional[List[str]]:
    try:
        from app.services.game_service import PROMPTS

        return list(PROMPTS)
    except Exception:  # needs a configured .env; the report simply skips the prompt-only line
        return None


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Evaluate the model on canvas-style drawings")
    parser.add_argument("--per-class", type=int, default=40, help="drawings per category")
    parser.add_argument("--offset-mb", type=float, default=6.0,
                        help="skip this far into each file (the model trained on the first rows)")
    parser.add_argument("--recognized-only", action="store_true",
                        help="only drawings the original Quick, Draw! game recognised (easier)")
    parser.add_argument("--tune", action="store_true", help="also try other preprocessing settings")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--cache-dir", default=str(BACKEND_DIR / "data" / "quickdraw_eval"))
    parser.add_argument("--base-url", default=SIMPLIFIED_URL)
    args = parser.parse_args(argv)

    if ml.model_info()["backend"] != "onnx":
        print("No trained model found (models/quickdraw.onnx). Train it first:\n"
              "  python scripts/train_quickdraw.py")
        return 2

    rng = random.Random(args.seed)
    print(f"Downloading {args.per_class} drawings for each of {len(ml.QUICKDRAW_CLASSES)} categories "
          f"(cached in {args.cache_dir}) ...")
    dataset: Dict[str, List[Image.Image]] = {}
    for index, name in enumerate(ml.QUICKDRAW_CLASSES):
        drawings = fetch_drawings(name, args.per_class, args.offset_mb, Path(args.cache_dir),
                                  args.base_url, args.recognized_only)
        dataset[name] = [render_drawing(d, rng) for d in drawings]
        print(f"  [{index + 1:2d}/{len(ml.QUICKDRAW_CLASSES)}] {name:<12} {len(drawings)} drawings")

    print(f"\nPreprocessing now: STROKE_SCALE={ml.STROKE_SCALE}, TARGET_SPAN={ml.TARGET_SPAN}")
    result = evaluate(dataset)
    print(f"\nEvaluated {result['total']} drawings")
    print(f"  Top-1 accuracy: {percent(result['top1'])}   (the AI's first guess is right)")
    print(f"  Top-3 accuracy: {percent(result['top3'])}   (the right answer is among its 3 guesses)")

    per_class = result["per_class"]
    prompts = load_prompts()
    if prompts:
        total = sum(per_class[p][0] for p in prompts if p in per_class)
        right = sum(per_class[p][1] for p in prompts if p in per_class)
        if total:
            print(f"  Top-1 on the {len(prompts)} game prompts only: {percent(right / total)}")

    ranked = sorted(per_class.items(), key=lambda kv: kv[1][1] / max(kv[1][0], 1))
    print("\nWeakest categories (top-1)   most common wrong answer")
    for name, (count, hits, _) in ranked[:8]:
        wrong = result["confusions"][name].most_common(1)
        print(f"  {name:<14} {percent(hits / max(count, 1))}      {wrong[0][0] if wrong else '-'}")
    print("Strongest categories")
    for name, (count, hits, _) in ranked[-5:][::-1]:
        print(f"  {name:<14} {percent(hits / max(count, 1))}")

    if args.tune:
        print("\nTrying other preprocessing settings (same drawings) ...")
        original = (ml.STROKE_SCALE, ml.TARGET_SPAN)
        trials: List[Tuple[float, float, float, float]] = []
        for stroke_scale in (0.8, 1.2, 1.8, 2.5):
            for span in (22, 26):
                ml.STROKE_SCALE, ml.TARGET_SPAN = stroke_scale, span
                r = evaluate(dataset)
                trials.append((r["top1"], r["top3"], stroke_scale, span))
                print(f"  STROKE_SCALE={stroke_scale:<3} TARGET_SPAN={span}  "
                      f"top-1 {percent(r['top1'])}  top-3 {percent(r['top3'])}")
        ml.STROKE_SCALE, ml.TARGET_SPAN = original
        best = max(trials)
        current = next((t for t in trials if (t[2], t[3]) == original), None)
        print(f"\nBest of these: STROKE_SCALE={best[2]}, TARGET_SPAN={best[3]} (top-1 {percent(best[0])})")
        if current is None or best[0] > current[0] + 0.01:
            print("To use it, edit backend/app/services/ml_service.py:\n"
                  f"    TARGET_SPAN = {best[3]}\n    STROKE_SCALE = {best[2]}")
        else:
            print("The current settings are already about as good as any of these: no change needed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())