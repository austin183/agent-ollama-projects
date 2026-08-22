#!/usr/bin/env python3
"""Tests for model_pricing.py — fallback warning bug B6.

B6: Unknown models silently fall back to default rates with no warning
  2.4.1.1  model_id='agents-a1' (unknown) → returns fallback + logs warning
  2.4.1.2  model_id='big-pickle' (unknown) → returns fallback + logs warning
  2.4.1.3  model_id='qwen/qwen3.6-27b' (known) → returns explicit rates, no warning
  2.4.1.4  model_id=None → returns fallback, no warning (None is expected)
"""

import logging
import sys
from contextlib import contextmanager
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

import model_pricing


class TestB6_FallbackWarning:
    """B6: get_pricing() must warn once per unknown model."""

    def test_known_model_no_warning(self):
        """2.4.1.3 — Known model returns explicit rates without warning."""
        with self._capture_logs(model_pricing.logger, level=logging.WARNING) as records:
            pricing = model_pricing.get_pricing('qwen/qwen3.6-27b')

        assert pricing == model_pricing.MODEL_PRICING['qwen/qwen3.6-27b']
        assert len(records) == 0, f"Known model triggered {len(records)} warning(s)"

    def test_none_model_no_warning(self):
        """2.4.1.4 — None model_id returns fallback without warning."""
        with self._capture_logs(model_pricing.logger, level=logging.WARNING) as records:
            pricing = model_pricing.get_pricing(None)

        assert pricing == model_pricing.MODEL_PRICING['fallback']
        assert len(records) == 0, f"None model_id triggered {len(records)} warning(s)"

    def test_unknown_model_warns_once(self):
        """2.4.1.1 — Unknown model returns fallback AND logs a warning."""
        test_model = 'unknown-test-model-x'
        model_pricing._FALLBACK_WARNED.discard(test_model)

        with self._capture_logs(model_pricing.logger, level=logging.WARNING) as records:
            pricing = model_pricing.get_pricing(test_model)

        assert pricing == model_pricing.MODEL_PRICING['fallback']
        assert len(records) == 1, f"Expected 1 warning, got {len(records)}"
        assert test_model in records[0].message

    def test_unknown_model_warns_only_once(self):
        """Unknown model warning is deduplicated — second call produces no warning."""
        test_model = 'unknown-test-model-y'
        model_pricing._FALLBACK_WARNED.discard(test_model)

        # First call — should warn
        with self._capture_logs(model_pricing.logger, level=logging.WARNING) as records:
            model_pricing.get_pricing(test_model)
        assert len(records) == 1

        # Second call — should NOT warn
        with self._capture_logs(model_pricing.logger, level=logging.WARNING) as records:
            model_pricing.get_pricing(test_model)
        assert len(records) == 0, "Second call to unknown model should not warn"

    def test_another_unknown_model_warns_independently(self):
        """2.4.1.2 — Different unknown models each warn once."""
        model_a = 'unknown-test-model-a'
        model_b = 'unknown-test-model-b'
        model_pricing._FALLBACK_WARNED.discard(model_a)
        model_pricing._FALLBACK_WARNED.discard(model_b)

        # Warn for model_a
        with self._capture_logs(model_pricing.logger, level=logging.WARNING):
            model_pricing.get_pricing(model_a)

        # model_b should still warn (independent dedup)
        with self._capture_logs(model_pricing.logger, level=logging.WARNING) as records:
            model_pricing.get_pricing(model_b)

        assert len(records) == 1
        assert model_b in records[0].message

    def test_fallback_warned_set_exists(self):
        """model_pricing module must have _FALLBACK_WARNED set for deduplication."""
        assert hasattr(model_pricing, '_FALLBACK_WARNED'), \
            "model_pricing missing _FALLBACK_WARNED set"
        assert isinstance(model_pricing._FALLBACK_WARNED, set), \
            "_FALLBACK_WARNED should be a set"

    @contextmanager
    def _capture_logs(self, logger, level=logging.WARNING):
        """Context manager to capture log records from a logger."""
        handler = logging.Handler()
        handler.setLevel(level)
        records = []
        handler.emit = lambda record: records.append(record)
        logger.addHandler(handler)
        try:
            yield records
        finally:
            logger.removeHandler(handler)


class TestB6_ExplicitCustomModels:
    """B6: Custom models that appear in data should have explicit pricing entries."""

    def test_agents_a1_has_explicit_entry(self):
        """agents-a1 should have an explicit entry in MODEL_PRICING."""
        assert 'agents-a1' in model_pricing.MODEL_PRICING, \
            "agents-a1 missing from MODEL_PRICING (should be explicit, not fallback)"

    def test_big_pickle_has_explicit_entry(self):
        """big-pickle should have an explicit entry in MODEL_PRICING."""
        assert 'big-pickle' in model_pricing.MODEL_PRICING, \
            "big-pickle missing from MODEL_PRICING (should be explicit, not fallback)"

    def test_custom_models_have_required_keys(self):
        """Custom model entries must have input, output, cached_input keys."""
        for model_id in ('agents-a1', 'big-pickle'):
            if model_id in model_pricing.MODEL_PRICING:
                entry = model_pricing.MODEL_PRICING[model_id]
                for key in ('input', 'output', 'cached_input'):
                    assert key in entry, \
                        f"{model_id} missing pricing key '{key}'"


class TestPhase3_MissingModels:
    """Phase 3: Models that appear in real project data must have explicit pricing
    entries to avoid fallback warnings.

    These 4 models were identified as missing from MODEL_PRICING during the
    CollageMaker analytics report, causing fallback warnings at runtime.
    """

    # Models and their expected pricing (per 1M tokens)
    MISSING_MODELS = {
        'laguna-s-2.1':           {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
        'qwen/qwen3.6-27b-q4':    {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
        'qwen/qwen3.6-27b-lite':  {'input': 0.40,  'output': 1.20,  'cached_input': 0.04},
        'qwen/qwen3.5-9b':        {'input': 0.30,  'output': 0.60,  'cached_input': 0.03},
    }

    def test_laguna_s_2_1_has_explicit_entry(self):
        """3.1.1 — laguna-s-2.1 must have an explicit entry in MODEL_PRICING."""
        assert 'laguna-s-2.1' in model_pricing.MODEL_PRICING, \
            "laguna-s-2.1 missing from MODEL_PRICING (was triggering fallback)"

    def test_qwen3_6_27b_q4_has_explicit_entry(self):
        """3.1.2 — qwen/qwen3.6-27b-q4 must have an explicit entry in MODEL_PRICING."""
        assert 'qwen/qwen3.6-27b-q4' in model_pricing.MODEL_PRICING, \
            "qwen/qwen3.6-27b-q4 missing from MODEL_PRICING (was triggering fallback)"

    def test_qwen3_6_27b_lite_has_explicit_entry(self):
        """3.1.3 — qwen/qwen3.6-27b-lite must have an explicit entry in MODEL_PRICING."""
        assert 'qwen/qwen3.6-27b-lite' in model_pricing.MODEL_PRICING, \
            "qwen/qwen3.6-27b-lite missing from MODEL_PRICING (was triggering fallback)"

    def test_qwen3_5_9b_has_explicit_entry(self):
        """3.1.4 — qwen/qwen3.5-9b must have an explicit entry in MODEL_PRICING."""
        assert 'qwen/qwen3.5-9b' in model_pricing.MODEL_PRICING, \
            "qwen/qwen3.5-9b missing from MODEL_PRICING (was triggering fallback)"

    def test_missing_models_have_correct_pricing(self):
        """Each previously-missing model must have the expected pricing rates."""
        for model_id, expected in self.MISSING_MODELS.items():
            assert model_id in model_pricing.MODEL_PRICING, \
                f"{model_id} missing from MODEL_PRICING"
            entry = model_pricing.MODEL_PRICING[model_id]
            for key, value in expected.items():
                assert key in entry, f"{model_id} missing key '{key}'"
                assert entry[key] == value, \
                    f"{model_id}.{key} should be {value}, got {entry.get(key)}"

    def test_missing_models_do_not_trigger_fallback_warning(self):
        """get_pricing() for previously-missing models must NOT warn (they are now known)."""
        import logging

        for model_id in self.MISSING_MODELS:
            model_pricing._FALLBACK_WARNED.discard(model_id)

        with self._capture_logs(model_pricing.logger, level=logging.WARNING) as records:
            for model_id in self.MISSING_MODELS:
                model_pricing.get_pricing(model_id)

        fallback_warnings = [
            r for r in records
            if 'not found in pricing table' in r.message
        ]
        assert len(fallback_warnings) == 0, \
            f"Expected 0 fallback warnings for known models, got {len(fallback_warnings)}: " \
            f"{[r.message for r in fallback_warnings]}"

    def test_missing_models_have_required_keys(self):
        """All previously-missing model entries must have input, output, cached_input keys."""
        for model_id in self.MISSING_MODELS:
            if model_id in model_pricing.MODEL_PRICING:
                entry = model_pricing.MODEL_PRICING[model_id]
                for key in ('input', 'output', 'cached_input'):
                    assert key in entry, \
                        f"{model_id} missing pricing key '{key}'"

    def test_qwen3_5_9b_is_cheaper_than_qwen3_6_27b(self):
        """The 9B model should have lower rates than the 27B model (size-proportional)."""
        p9b  = model_pricing.get_pricing('qwen/qwen3.5-9b')
        p27b = model_pricing.get_pricing('qwen/qwen3.6-27b')
        assert p9b['input'] < p27b['input'], \
            f"9B input rate ({p9b['input']}) should be less than 27B ({p27b['input']})"
        assert p9b['output'] < p27b['output'], \
            f"9B output rate ({p9b['output']}) should be less than 27B ({p27b['output']})"

    def test_qwen3_6_27b_q4_same_as_base(self):
        """The quantized q4 variant should have the same pricing as the base 27B model."""
        p_base = model_pricing.get_pricing('qwen/qwen3.6-27b')
        p_q4   = model_pricing.get_pricing('qwen/qwen3.6-27b-q4')
        assert p_q4['input'] == p_base['input'], \
            f"q4 input rate ({p_q4['input']}) should match base ({p_base['input']})"
        assert p_q4['output'] == p_base['output'], \
            f"q4 output rate ({p_q4['output']}) should match base ({p_base['output']})"

    @property
    def _capture_logs(self):
        """Lazy property to access the base class method."""
        return TestB6_FallbackWarning._capture_logs.__get__(self, TestB6_FallbackWarning)
