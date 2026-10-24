import asyncio

import pytest

from app.services import ml_service as ml


class TestCalculateScore:
    def test_worked_example(self):
        # AI says "cat" at 85 %, drawn in 6 s: 0.85*60 + (54/60)*25 = 51 + 22.5
        result = ml.calculate_score("cat", 0.85, "cat", 6)
        assert result["score"] == 73.5
        assert result["base_score"] == 51.0
        assert result["speed_bonus"] == 22.5
        assert result["bluff_bonus"] == 0.0
        assert result["bluff_detected"] is False

    def test_confident_wrong_label_earns_bluff_bonus(self):
        result = ml.calculate_score("dog", 0.9, "cat", 10)
        assert result["bluff_detected"] is True
        assert result["bluff_bonus"] == 15.0

    def test_unconfident_wrong_label_is_flagged_but_not_rewarded(self):
        result = ml.calculate_score("dog", 0.5, "cat", 10)
        assert result["bluff_detected"] is True
        assert result["bluff_bonus"] == 0.0

    def test_bluff_threshold_is_strictly_above_60_percent(self):
        assert ml.calculate_score("dog", 0.6, "cat", 10)["bluff_bonus"] == 0.0
        assert ml.calculate_score("dog", 0.61, "cat", 10)["bluff_bonus"] == 15.0

    def test_score_is_capped_at_100(self):
        assert ml.calculate_score("dog", 1.0, "cat", 0)["score"] == 100.0  # 60 + 25 + 15 = 100

    def test_time_is_clamped(self):
        assert ml.calculate_score("cat", 0.5, "cat", -5)["speed_bonus"] == 25.0
        assert ml.calculate_score("cat", 0.5, "cat", 999)["speed_bonus"] == 0.0

    def test_confidence_is_clamped(self):
        assert ml.calculate_score("cat", 7.0, "cat", 60)["base_score"] == 60.0
        assert ml.calculate_score("cat", -1.0, "cat", 60)["base_score"] == 0.0

    def test_labels_compare_case_and_space_insensitively(self):
        assert ml.calculate_score("Cat ", 0.5, " cat", 5)["bluff_detected"] is False

    def test_blank_canvas_scores_zero(self):
        result = ml.calculate_score("", 0.0, "cat", 1, blank=True)
        assert result["score"] == 0.0 and result["bluff_detected"] is False

    def test_custom_max_time(self):
        assert ml.calculate_score("cat", 0.0, "cat", 15, max_time=30)["speed_bonus"] == 12.5


class TestScoreDrawing:
    def test_scores_a_drawing_with_a_fixed_classifier(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("cat", 0.85, 0.85))
        result = ml.score_drawing_sync(png(), "cat", 6)
        assert result["score"] == 73.5
        assert result["blank"] is False
        assert result["model"] == "mock"  # no model file in tests
        assert result["prompt_confidence"] == 0.85

    def test_bluff_through_the_whole_pipeline(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("dog", 0.9, 0.02))
        result = ml.score_drawing_sync(png(), "cat", 10)
        assert result["bluff_bonus"] == 15.0
        assert result["prompt_confidence"] == 0.02

    def test_blank_canvas(self, png):
        result = ml.score_drawing_sync(png("blank"), "cat", 1)
        assert result["score"] == 0.0 and result["blank"] is True and result["recognized_as"] == ""

    def test_invalid_drawing_raises(self):
        with pytest.raises(ml.InvalidDrawingError):
            ml.score_drawing_sync("definitely not an image", "cat", 1)

    def test_async_wrapper(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("cat", 0.5, 0.5))
        result = asyncio.run(ml.score_drawing(png(), "cat", 5))
        assert result["recognized_as"] == "cat"

    def test_mock_classifier_stays_in_range(self, png):
        for _ in range(30):
            result = ml.score_drawing_sync(png(), "cat", 10)
            assert 0.0 <= result["score"] <= 100.0
            assert 0.0 <= result["confidence"] <= 1.0


class TestPredictDrawing:
    def test_eligible_bluff(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("dog", 0.9, 0.01))
        result = ml.predict_drawing(png(), "cat")
        assert result["bluff_detected"] and result["bluff_eligible"] and not result["blank"]

    def test_mismatch_below_threshold_is_not_eligible(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("dog", 0.5, 0.2))
        result = ml.predict_drawing(png(), "cat")
        assert result["bluff_detected"] is True and result["bluff_eligible"] is False

    def test_matching_drawing_is_no_bluff(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("cat", 0.9, 0.9))
        result = ml.predict_drawing(png(), "cat")
        assert not result["bluff_detected"] and not result["bluff_eligible"]

    def test_blank_canvas(self, png):
        result = ml.predict_drawing(png("blank"), "cat")
        assert result["blank"] is True and result["confidence"] == 0.0 and result["recognized_as"] == ""