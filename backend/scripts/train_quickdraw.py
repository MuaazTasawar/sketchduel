"""Train the QuickDraw classifier used by SketchDuel and export it as ONNX.

Run from the backend folder:

    pip install -r requirements-train.txt
    python scripts/train_quickdraw.py --smoke-test      # ~1 minute, fake data: checks your setup
    python scripts/train_quickdraw.py                   # real training (downloads ~300 MB once)

What it does
  1. Downloads the first N drawings of each of the 60 categories (Google QuickDraw 28x28 bitmaps,
     CC BY 4.0) using HTTP range requests, so only ~N * 784 bytes per category are fetched.
  2. Trains a small CNN (about 0.4 M parameters).
  3. Exports models/quickdraw.onnx with a softmax output and the label list embedded.
  4. Re-loads the ONNX file with onnxruntime and checks it matches the PyTorch model.

The backend picks the model up automatically (MODEL_PATH, default models/quickdraw.onnx).
"""
import argparse
import io
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Tuple

import numpy as np

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

from app.services.ml_service import IMG_SIZE, QUICKDRAW_CLASSES  # noqa: E402

BASE_URL = "https://storage.googleapis.com/quickdraw_dataset/full/numpy_bitmap/"
PIXELS = IMG_SIZE * IMG_SIZE


# ------------------------------------------------------------------------------------------------
# Data
# ------------------------------------------------------------------------------------------------
def _http_range(url: str, start: int, end: int) -> Tuple[bytes, int]:
    request = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read(), response.status


def _with_retries(func, attempts: int = 4):
    for attempt in range(1, attempts + 1):
        try:
            return func()
        except Exception as error:  # network hiccups
            if attempt == attempts:
                raise
            wait = 2 * attempt
            print(f"   retry {attempt}/{attempts - 1} after error: {error} (waiting {wait}s)")
            time.sleep(wait)


def parse_npy_header(head: bytes) -> Tuple[int, tuple]:
    """Return (data_offset, shape) for an .npy file given its first bytes."""
    stream = io.BytesIO(head)
    version = np.lib.format.read_magic(stream)
    if version == (1, 0):
        shape, _fortran, dtype = np.lib.format.read_array_header_1_0(stream)
    else:
        shape, _fortran, dtype = np.lib.format.read_array_header_2_0(stream)
    if dtype != np.uint8:
        raise ValueError(f"unexpected dtype {dtype}")
    return stream.tell(), shape


def download_class(name: str, samples: int, cache_dir: Path, base_url: str = BASE_URL) -> np.ndarray:
    """Download (or load from cache) the first `samples` drawings of one category."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_file = cache_dir / f"{name}.npy"
    if cache_file.exists():
        cached = np.load(cache_file)
        if len(cached) >= samples:
            return cached[:samples]

    url = base_url + urllib.parse.quote(name) + ".npy"
    head, status = _with_retries(lambda: _http_range(url, 0, 1023))
    if status == 200 and len(head) > 1_000_000:
        print("   (server ignored the Range header; reading the whole file)")
        array = np.load(io.BytesIO(head))
    else:
        offset, shape = parse_npy_header(head)
        take = min(samples, shape[0])
        end = offset + take * PIXELS - 1
        data, _ = _with_retries(lambda: _http_range(url, offset, end))
        array = np.frombuffer(data, dtype=np.uint8).reshape(take, PIXELS)

    array = np.ascontiguousarray(array[:samples])
    np.save(cache_file, array)
    return array


def build_real_dataset(samples: int, data_dir: Path) -> Tuple[np.ndarray, np.ndarray]:
    xs, ys = [], []
    for index, name in enumerate(QUICKDRAW_CLASSES):
        print(f"[{index + 1:2d}/{len(QUICKDRAW_CLASSES)}] {name}")
        images = download_class(name, samples, data_dir)
        xs.append(images)
        ys.append(np.full(len(images), index, dtype=np.int64))
    return np.concatenate(xs), np.concatenate(ys)


def build_smoke_dataset(samples: int, seed: int) -> Tuple[np.ndarray, np.ndarray]:
    """Fake data: every class gets a random prototype blob plus noise. Only checks the pipeline."""
    rng = np.random.default_rng(seed)
    prototypes = (rng.random((len(QUICKDRAW_CLASSES), PIXELS)) > 0.85).astype(np.float32)
    xs, ys = [], []
    for index in range(len(QUICKDRAW_CLASSES)):
        noise = rng.random((samples, PIXELS)) * 0.4
        images = np.clip(prototypes[index] + noise - 0.1, 0, 1)
        xs.append((images * 255).astype(np.uint8))
        ys.append(np.full(samples, index, dtype=np.int64))
    return np.concatenate(xs), np.concatenate(ys)


# ------------------------------------------------------------------------------------------------
# Training
# ------------------------------------------------------------------------------------------------
def train(args) -> None:
    import onnx
    import onnxruntime as ort
    import torch
    from torch import nn

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    # ---- data ----
    if args.smoke_test:
        print("SMOKE TEST: using synthetic data (the resulting model is NOT useful)")
        images, labels = build_smoke_dataset(args.samples_per_class, args.seed)
    else:
        images, labels = build_real_dataset(args.samples_per_class, Path(args.data_dir))

    order = np.random.permutation(len(images))
    images, labels = images[order], labels[order]
    split = int(len(images) * (1 - args.val_fraction))

    def to_tensor(x: np.ndarray) -> "torch.Tensor":
        return torch.from_numpy(x.astype(np.float32) / 255.0).reshape(-1, 1, IMG_SIZE, IMG_SIZE)

    x_train, y_train = to_tensor(images[:split]), torch.from_numpy(labels[:split])
    x_val, y_val = to_tensor(images[split:]), torch.from_numpy(labels[split:])
    print(f"Train: {len(x_train):,}   Validation: {len(x_val):,}   Classes: {len(QUICKDRAW_CLASSES)}")

    # ---- model ----
    class QuickDrawNet(nn.Module):
        def __init__(self, classes: int) -> None:
            super().__init__()
            self.features = nn.Sequential(
                nn.Conv2d(1, 32, 3, padding=1), nn.BatchNorm2d(32), nn.ReLU(), nn.MaxPool2d(2),
                nn.Conv2d(32, 64, 3, padding=1), nn.BatchNorm2d(64), nn.ReLU(), nn.MaxPool2d(2),
                nn.Conv2d(64, 128, 3, padding=1), nn.BatchNorm2d(128), nn.ReLU(), nn.MaxPool2d(2),
            )
            self.classifier = nn.Sequential(
                nn.Flatten(),
                nn.Linear(128 * 3 * 3, 256), nn.ReLU(), nn.Dropout(0.3),
                nn.Linear(256, classes),
            )

        def forward(self, x):
            return self.classifier(self.features(x))

    model = QuickDrawNet(len(QUICKDRAW_CLASSES)).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    steps_per_epoch = max(1, (len(x_train) + args.batch_size - 1) // args.batch_size)
    scheduler = torch.optim.lr_scheduler.OneCycleLR(
        optimizer, max_lr=args.lr, epochs=args.epochs, steps_per_epoch=steps_per_epoch
    )
    loss_fn = nn.CrossEntropyLoss(label_smoothing=0.05)

    def evaluate() -> float:
        model.eval()
        correct = 0
        with torch.no_grad():
            for start in range(0, len(x_val), 1024):
                batch = x_val[start:start + 1024].to(device)
                correct += (model(batch).argmax(1).cpu() == y_val[start:start + 1024]).sum().item()
        return correct / max(len(x_val), 1)

    best_accuracy, best_state = -1.0, None
    for epoch in range(1, args.epochs + 1):
        model.train()
        started = time.time()
        permutation = torch.randperm(len(x_train))
        running = 0.0
        for start in range(0, len(x_train), args.batch_size):
            index = permutation[start:start + args.batch_size]
            batch, target = x_train[index].to(device), y_train[index].to(device)

            # light augmentation: random shift (+-2 px) and random stroke intensity
            dy, dx = np.random.randint(-2, 3, size=2)
            batch = torch.roll(batch, shifts=(int(dy), int(dx)), dims=(2, 3))
            batch = batch * float(np.random.uniform(0.75, 1.0))

            optimizer.zero_grad()
            loss = loss_fn(model(batch), target)
            loss.backward()
            optimizer.step()
            scheduler.step()
            running += loss.item() * len(index)

        accuracy = evaluate()
        print(f"Epoch {epoch}/{args.epochs}  loss {running / len(x_train):.4f}  "
              f"val acc {accuracy:.4f}  ({time.time() - started:.0f}s)")
        if accuracy > best_accuracy:
            best_accuracy = accuracy
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}

    model.load_state_dict(best_state)
    model.eval().cpu()

    # ---- export ----
    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = BACKEND_DIR / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    exported = nn.Sequential(model, nn.Softmax(dim=1)).eval()
    dummy = torch.zeros(1, 1, IMG_SIZE, IMG_SIZE)
    export_kwargs = dict(
        input_names=["input"],
        output_names=["probabilities"],
        dynamic_axes={"input": {0: "batch"}, "probabilities": {0: "batch"}},
        opset_version=17,
    )
    try:
        torch.onnx.export(exported, dummy, str(out_path), dynamo=False, **export_kwargs)
    except TypeError:  # older PyTorch without the `dynamo` argument
        torch.onnx.export(exported, dummy, str(out_path), **export_kwargs)

    # embed the label order so the backend can never mix it up
    onnx_model = onnx.load(str(out_path))
    del onnx_model.metadata_props[:]
    entry = onnx_model.metadata_props.add()
    entry.key, entry.value = "labels", json.dumps(QUICKDRAW_CLASSES)
    onnx.save(onnx_model, str(out_path))

    # ---- verify the exported file ----
    session = ort.InferenceSession(str(out_path), providers=["CPUExecutionProvider"])
    sample = x_val[:256]
    with torch.no_grad():
        expected = exported(sample).numpy()
    actual = session.run(None, {"input": sample.numpy()})[0]
    max_diff = float(np.abs(expected - actual).max())
    onnx_accuracy = float((actual.argmax(1) == y_val[:256].numpy()).mean())
    embedded = json.loads(session.get_modelmeta().custom_metadata_map["labels"])
    assert embedded == QUICKDRAW_CLASSES, "label list was not embedded correctly"
    assert max_diff < 1e-3, f"ONNX output differs from PyTorch by {max_diff}"

    size_mb = out_path.stat().st_size / 1_000_000
    print(f"\nSaved {out_path}  ({size_mb:.2f} MB)")
    print(f"Best validation accuracy: {best_accuracy:.4f}   ONNX check: max diff {max_diff:.2e}, "
          f"acc on 256 samples {onnx_accuracy:.3f}")

    if not args.smoke_test:
        metrics = {
            "validation_accuracy": round(best_accuracy, 4),
            "classes": len(QUICKDRAW_CLASSES),
            "samples_per_class": args.samples_per_class,
            "epochs": args.epochs,
            "trained_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "dataset": "Google QuickDraw numpy_bitmap (CC BY 4.0)",
        }
        (out_path.parent / "quickdraw.metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
        print("Next: commit models/quickdraw.onnx and models/quickdraw.metrics.json, then restart the API.")
    else:
        print("Smoke test OK. Delete this fake model before real use "
              "(the real run overwrites it): " + str(out_path))


def main(argv: List[str] = None) -> None:
    parser = argparse.ArgumentParser(description="Train the SketchDuel QuickDraw classifier")
    parser.add_argument("--samples-per-class", type=int, default=6000)
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--lr", type=float, default=3e-3)
    parser.add_argument("--val-fraction", type=float, default=0.05)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--data-dir", default=str(BACKEND_DIR / "data" / "quickdraw"))
    parser.add_argument("--out", default="models/quickdraw.onnx")
    parser.add_argument("--smoke-test", action="store_true",
                        help="use tiny synthetic data to verify the pipeline quickly")
    args = parser.parse_args(argv)

    if args.smoke_test:
        args.samples_per_class = min(args.samples_per_class, 150)
        args.epochs = min(args.epochs, 2)

    train(args)


if __name__ == "__main__":
    main()