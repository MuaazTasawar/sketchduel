import asyncio

import pytest

from app.services import ml_service as ml


class TestCalculateScore:
    def test_worked_example(self):
        # AI says "cat" at 85 %, drawn in 6 s:
        #   accuracy = 0.85 * 70 = 59.5      speed = (54/60) * 30 * 0.85 = 22.95
        result = ml.calculate_score("cat", 0.85, "cat", 6)
        assert result["score"] == pytest.approx(82.45)
        assert result["accuracy_score"] == pytest.approx(59.5)
        assert result["speed_bonus"] == pytest.approx(22.95)
        assert result["matched"] is True
        assert result["prompt_confidence"] == 0.85

    def test_the_formula_in_one_line(self):
        # score = prompt_confidence * (70 + 30 * time_left / max_time)
        result = ml.calculate_score("cat", 0.8, "cat", 15)
        assert result["score"] == pytest.approx(0.8 * (70 + 30 * 45 / 60))

    def test_a_confident_wrong_guess_scores_nothing(self):
        # The exploit this rule closes: drawing something the AI recognises easily
        # (a butterfly) for a different prompt (a cat) must not pay.
        result = ml.calculate_score("butterfly", 0.99, "cat", 1)
        assert result["score"] == 0.0
        assert result["matched"] is False
        assert result["prompt_confidence"] == 0.0

    def test_a_wrong_guess_still_earns_the_little_the_prompt_was_worth(self):
        # AI's favourite is "dog" (90 %) but it gives the prompt "cat" 12 %.
        result = ml.calculate_score("dog", 0.9, "cat", 10, prompt_confidence=0.12)
        assert result["matched"] is False
        assert result["prompt_confidence"] == 0.12
        assert result["score"] == pytest.approx(0.12 * (70 + 30 * 50 / 60))

    def test_speed_only_counts_in_proportion_to_accuracy(self):
        # A fast scribble earns almost nothing; a fast good drawing earns the full speed bonus.
        scribble = ml.calculate_score("cat", 0.1, "cat", 0)
        good = ml.calculate_score("cat", 1.0, "cat", 0)
        assert scribble["speed_bonus"] == pytest.approx(3.0)
        assert good["speed_bonus"] == pytest.approx(30.0)

    def test_accuracy_beats_speed(self):
        slow_but_good = ml.calculate_score("cat", 0.9, "cat", 59)["score"]
        fast_but_poor = ml.calculate_score("cat", 0.2, "cat", 1)["score"]
        assert slow_but_good > fast_but_poor

    def test_a_better_match_always_scores_higher_at_the_same_speed(self):
        scores = [ml.calculate_score("cat", c / 10, "cat", 20)["score"] for c in range(11)]
        assert scores == sorted(scores)

    def test_a_perfect_instant_drawing_scores_exactly_100(self):
        assert ml.calculate_score("cat", 1.0, "cat", 0)["score"] == 100.0

    def test_scores_never_exceed_100_or_go_below_0(self):
        assert ml.calculate_score("cat", 5.0, "cat", -10)["score"] == 100.0
        assert ml.calculate_score("cat", -1.0, "cat", 10)["score"] == 0.0

    def test_time_is_clamped(self):
        assert ml.calculate_score("cat", 0.5, "cat", -5)["speed_bonus"] == pytest.approx(15.0)
        assert ml.calculate_score("cat", 0.5, "cat", 999)["speed_bonus"] == 0.0

    def test_prompt_confidence_is_clamped(self):
        assert ml.calculate_score("x", 0.5, "cat", 60, prompt_confidence=7.0)["accuracy_score"] == 70.0
        assert ml.calculate_score("x", 0.5, "cat", 60, prompt_confidence=-1.0)["accuracy_score"] == 0.0

    def test_labels_compare_case_and_space_insensitively(self):
        assert ml.calculate_score("Cat ", 0.5, " cat", 5)["matched"] is True

    def test_blank_canvas_scores_zero(self):
        result = ml.calculate_score("", 0.0, "cat", 1, blank=True)
        assert result["score"] == 0.0 and result["matched"] is False

    def test_custom_max_time(self):
        # half of a 30 second round left: 70 + 15
        assert ml.calculate_score("cat", 1.0, "cat", 15, max_time=30)["score"] == pytest.approx(85.0)

    def test_there_is_no_bluff_bonus_any_more(self):
        result = ml.calculate_score("dog", 0.99, "cat", 0, prompt_confidence=0.0)
        assert "bluff_bonus" not in result and "bluff_detected" not in result


class TestScoreDrawing:
    def test_scores_a_drawing_with_a_fixed_classifier(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("cat", 0.85, 0.85))
        result = ml.score_drawing_sync(png(), "cat", 6)
        assert result["score"] == pytest.approx(82.45)
        assert result["blank"] is False
        assert result["matched"] is True
        assert result["model"] == "mock"  # no model file in tests
        assert result["prompt_confidence"] == 0.85

    def test_a_wrong_guess_through_the_whole_pipeline(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("dog", 0.9, 0.02))
        result = ml.score_drawing_sync(png(), "cat", 10)
        assert result["recognized_as"] == "dog"
        assert result["matched"] is False
        assert result["prompt_confidence"] == 0.02
        assert result["score"] < 3.0

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
            assert 0.0 <= result["prompt_confidence"] <= 1.0


class TestPredictDrawing:
    def test_a_drawing_that_matches_the_prompt(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("cat", 0.9, 0.9))
        result = ml.predict_drawing(png(), "cat")
        assert result["matches_prompt"] is True and result["prompt_confidence"] == 0.9
        assert result["blank"] is False

    def test_a_drawing_the_ai_reads_as_something_else(self, monkeypatch, png):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("dog", 0.9, 0.01))
        result = ml.predict_drawing(png(), "cat")
        assert result["matches_prompt"] is False
        assert result["recognized_as"] == "dog"
        assert result["prompt_confidence"] == 0.01

    def test_blank_canvas(self, png):
        result = ml.predict_drawing(png("blank"), "cat")
        assert result["blank"] is True and result["confidence"] == 0.0 and result["recognized_as"] == ""
        assert result["matches_prompt"] is False

    def test_no_bluff_fields_any_more(self, png):
        assert "bluff_detected" not in ml.predict_drawing(png(), "cat")
