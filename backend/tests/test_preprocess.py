import base64
import io
import json

import numpy as np
import pytest
from PIL import Image

from app.services import ml_service as ml


def to_b64(image: Image.Image) -> str:
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return base64.b64encode(buffer.getvalue()).decode()


class TestPreprocessing:
    def test_output_shape_and_range(self, png):
        array = ml.preprocess_drawing(png())
        assert array.shape == (1, 1, 28, 28) and array.dtype == np.float32
        assert array.min() >= 0.0 and abs(float(array.max()) - 1.0) < 1e-6

    def test_drawing_fills_the_frame_and_is_centred(self, png):
        array = ml.preprocess_drawing(png())[0, 0]
        ys, xs = np.where(array > 0.3)
        assert ys.max() - ys.min() >= 22 and xs.max() - xs.min() >= 22
        assert abs((ys.min() + ys.max()) / 2 - 13.5) < 2
        assert abs((xs.min() + xs.max()) / 2 - 13.5) < 2

    def test_small_drawings_are_scaled_up(self, png):
        array = ml.preprocess_drawing(png("tiny"))[0, 0]
        ys, _ = np.where(array > 0.3)
        assert ys.max() - ys.min() >= 20

    def test_strokes_are_thick_enough_to_survive_downscaling(self, png):
        array = ml.preprocess_drawing(png())[0, 0]
        assert (array > 0.5).sum() > 40  # a hairline would leave almost nothing

    def test_empty_canvas_returns_none(self, png):
        assert ml.preprocess_drawing(png("blank")) is None

    def test_black_on_white_matches_white_on_dark(self, png):
        light = ml.preprocess_drawing(png("dark_on_light"))
        dark = ml.preprocess_drawing(png())
        assert np.abs(light - dark).mean() < 0.02

    def test_transparent_canvas(self, png):
        from PIL import ImageDraw

        image = Image.new("RGBA", (600, 420), (0, 0, 0, 0))
        ImageDraw.Draw(image).ellipse((150, 60, 450, 360), outline=(10, 10, 10, 255), width=4)
        array = ml.preprocess_drawing(to_b64(image))
        assert array is not None and np.abs(array - ml.preprocess_drawing(png())).mean() < 0.05

    def test_data_uri_prefix_and_whitespace_are_accepted(self, png):
        data = png()
        wrapped = "data:image/png;base64," + data[:40] + "\n" + data[40:]
        assert ml.preprocess_drawing(wrapped) is not None

    @pytest.mark.parametrize("bad", ["", "not base64!!", base64.b64encode(b"hello world").decode()])
    def test_invalid_input_is_rejected(self, bad):
        with pytest.raises(ml.InvalidDrawingError):
            ml.preprocess_drawing(bad)

    def test_oversized_image_is_rejected(self):
        with pytest.raises(ml.InvalidDrawingError):
            ml.preprocess_drawing(to_b64(Image.new("L", (2500, 2500), 0)))

    @pytest.mark.parametrize(
        ("wanted", "expected"),
        [(0.2, 1), (1.0, 1), (4.8, 5), (9.6, 9), (10.4, 11), (13.0, 13)],
    )
    def test_dilation_kernel_is_the_nearest_odd_size(self, wanted, expected):
        assert ml._nearest_odd(wanted) == expected

    def test_the_same_drawing_gives_the_same_input_on_any_canvas_size(self):
        # A drawing is judged by its shape, not by how big the player's window is.
        from PIL import ImageDraw

        def circle_on(size):
            width, height = size
            diameter = min(width, height) - 40
            image = Image.new("RGB", size, (26, 26, 46))
            ImageDraw.Draw(image).ellipse(
                (
                    (width - diameter) // 2,
                    (height - diameter) // 2,
                    (width + diameter) // 2,
                    (height + diameter) // 2,
                ),
                outline=(255, 255, 255),
                width=4,
            )
            return ml.drawing_to_array(image)

        phone = circle_on((360, 420))
        for size in [(600, 420), (700, 500), (300, 300)]:
            assert np.abs(phone - circle_on(size)).mean() < 0.03

    def test_a_canvas_filling_drawing_is_processed_quickly(self):
        import time

        from PIL import ImageDraw

        image = Image.new("RGB", (700, 500), (26, 26, 46))
        ImageDraw.Draw(image).ellipse((15, 15, 685, 485), outline=(255, 255, 255), width=4)
        started = time.perf_counter()
        for _ in range(5):
            assert ml.drawing_to_array(image) is not None
        # about 15 ms each on a laptop; the old full-size dilation took ~265 ms. Very generous bound:
        assert (time.perf_counter() - started) / 5 < 0.15


# ---------------------------------------------------------------------------------------------
# Real ONNX models (a tiny synthetic one is built on the fly; skipped if `onnx` is not installed)
# ---------------------------------------------------------------------------------------------
try:
    import onnx
    from onnx import TensorProto, helper, numpy_helper
except ImportError:  # only the ONNX tests below are skipped; everything above still runs
    onnx = None


def build_model(path, labels, favour, channels_last=False, logits=False):
    count = len(labels)
    bias = np.zeros(count, np.float32)
    bias[favour] = 8.0
    shape = [None, 28, 28, 1] if channels_last else [None, 1, 28, 28]
    nodes = [
        helper.make_node("Flatten", ["input"], ["flat"], axis=1),
        helper.make_node("Gemm", ["flat", "W", "b"], ["logits" if logits else "z"]),
    ]
    output = "logits" if logits else "probabilities"
    if not logits:
        nodes.append(helper.make_node("Softmax", ["z"], ["probabilities"], axis=1))
    graph = helper.make_graph(
        nodes,
        "test",
        [helper.make_tensor_value_info("input", TensorProto.FLOAT, shape)],
        [helper.make_tensor_value_info(output, TensorProto.FLOAT, [None, count])],
        [numpy_helper.from_array(np.zeros((784, count), np.float32), "W"), numpy_helper.from_array(bias, "b")],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
    model.ir_version = 9
    entry = model.metadata_props.add()
    entry.key, entry.value = "labels", json.dumps(labels)
    onnx.save(model, str(path))


def load(path):
    ml.reset_model_cache()
    ml._load_model(path)


@pytest.mark.skipif(onnx is None, reason="onnx is not installed (pip install -r requirements-train.txt)")
class TestOnnxModel:
    def test_model_is_used_and_labels_are_read(self, tmp_path, png):
        labels = ml.QUICKDRAW_CLASSES
        build_model(tmp_path / "m.onnx", labels, labels.index("dog"))
        load(tmp_path / "m.onnx")
        result = ml.score_drawing_sync(png(), "cat", 10)
        assert result["model"] == "onnx"
        assert result["recognized_as"] == "dog" and result["bluff_bonus"] == 15.0
        assert result["prompt_confidence"] < 0.1

    def test_prompt_confidence_for_matching_prompt(self, tmp_path, png):
        labels = ml.QUICKDRAW_CLASSES
        build_model(tmp_path / "m.onnx", labels, labels.index("dog"))
        load(tmp_path / "m.onnx")
        result = ml.score_drawing_sync(png(), "dog", 10)
        assert result["bluff_detected"] is False
        assert abs(result["prompt_confidence"] - result["confidence"]) < 1e-3

    def test_labels_embedded_in_the_model_win(self, tmp_path, png):
        custom = ["x"] * 60
        custom[5] = "special"
        build_model(tmp_path / "c.onnx", custom, 5)
        load(tmp_path / "c.onnx")
        assert ml.score_drawing_sync(png(), "cat", 1)["recognized_as"] == "special"

    def test_logit_outputs_are_converted_to_probabilities(self, tmp_path, png):
        build_model(tmp_path / "l.onnx", ml.QUICKDRAW_CLASSES, 3, logits=True)
        load(tmp_path / "l.onnx")
        assert 0.9 < ml.score_drawing_sync(png(), "cat", 1)["confidence"] <= 1.0

    def test_channels_last_models_are_supported(self, tmp_path, png):
        build_model(tmp_path / "h.onnx", ml.QUICKDRAW_CLASSES, 7, channels_last=True)
        load(tmp_path / "h.onnx")
        assert ml.score_drawing_sync(png(), "cat", 1)["recognized_as"] == ml.QUICKDRAW_CLASSES[7]

    def test_corrupt_model_falls_back_to_the_mock(self, tmp_path):
        (tmp_path / "broken.onnx").write_bytes(b"garbage")
        load(tmp_path / "broken.onnx")
        assert ml.model_info()["backend"] == "mock"

    def test_missing_model_falls_back_to_the_mock(self, tmp_path):
        load(tmp_path / "nope.onnx")
        assert ml.model_info() == {"backend": "mock", "classes": 60}