---
name: ml-testing
description: ML-specific testing patterns — model validation, data testing, pipeline testing, and regression detection
---

# ML Testing

Machine learning systems fail silently. Unlike traditional software where a bug produces an
exception or incorrect output that is immediately visible, ML systems can run to completion,
produce predictions, and serve results — all while being fundamentally broken. A model trained
on corrupted data returns predictions without complaint. A feature pipeline with a subtle
off-by-one error still outputs tensors of the correct shape. A serialization bug that drops
learned weights still loads a model object that responds to `.predict()`.

This makes testing not just important but existential for ML systems. The testing strategy
for ML code must cover the traditional software layer (unit tests, integration tests) and
extend into data validation, model quality assertions, training determinism, and regression
detection against known baselines. This skill document provides concrete, production-grade
patterns for each of these concerns.

## Table of Contents

1. [Test Structure for ML Projects](#1-test-structure-for-ml-projects)
2. [Unit Testing ML Code](#2-unit-testing-ml-code)
3. [Data Validation Tests](#3-data-validation-tests)
4. [Model Quality Tests](#4-model-quality-tests)
5. [Pipeline Integration Tests](#5-pipeline-integration-tests)
6. [Property-Based Testing with Hypothesis](#6-property-based-testing-with-hypothesis)
7. [Fixture & Factory Patterns](#7-fixture--factory-patterns)
8. [Regression Detection](#8-regression-detection)
9. [CI/CD for ML](#9-cicd-for-ml)
10. [Best Practices](#10-best-practices)
11. [Anti-Patterns](#11-anti-patterns)

---

## 1. Test Structure for ML Projects

A well-organized ML test suite separates concerns into distinct layers. Each layer has
different execution characteristics — unit tests run in milliseconds, data validation tests
may need database access, and model quality tests may require GPU resources and minutes of
compute time.

Recommended directory structure:

```
tests/
  unit/
    test_feature_engineering.py
    test_preprocessing.py
    test_model_architecture.py
    test_loss_functions.py
    test_metrics.py
  data/
    test_schema_validation.py
    test_data_expectations.py
    test_data_drift.py
  integration/
    test_training_pipeline.py
    test_inference_pipeline.py
    test_serialization_roundtrip.py
  quality/
    test_model_accuracy.py
    test_prediction_distribution.py
    test_fairness_metrics.py
    test_regression_baselines.py
  property/
    test_transform_invariants.py
    test_data_generation.py
  fixtures/
    sample_data/
    trained_models/
    baseline_metrics/
  conftest.py
```

Use pytest markers to control which tests run in different contexts:

- `@pytest.mark.unit` — fast, no external dependencies, run on every commit.
- `@pytest.mark.data` — requires data access, run on PR and nightly.
- `@pytest.mark.quality` — requires trained model, run nightly or on model changes.
- `@pytest.mark.slow` — anything exceeding 30 seconds, excluded from default runs.
- `@pytest.mark.gpu` — requires GPU, run only in GPU-enabled CI environments.

Configure these markers in `pyproject.toml`:

```
[tool.pytest.ini_options]
markers = [
    "unit: fast unit tests with no external dependencies",
    "data: data validation tests requiring data access",
    "quality: model quality tests requiring trained models",
    "slow: tests exceeding 30 seconds",
    "gpu: tests requiring GPU resources",
]
```

This separation allows developers to run `pytest -m unit` locally in seconds while the full
suite runs in CI with appropriate resources allocated per marker.

---

## 2. Unit Testing ML Code

Unit tests for ML code focus on the deterministic, algorithmic components of the pipeline.
These are the parts that behave like traditional software — given fixed inputs, they should
produce fixed outputs.

### Testing Feature Engineering Functions

Feature engineering code is often the most testable part of an ML system. Each transformation
function takes data in and produces data out, with well-defined expected behavior.

```python
import pytest
import numpy as np
import pandas as pd
from myproject.features import (
    compute_rolling_mean,
    encode_categorical,
    normalize_features,
    clip_outliers,
    extract_time_features,
)


class TestFeatureEngineering:
    """Tests for individual feature transformation functions."""

    def test_rolling_mean_basic(self):
        """Rolling mean computes correctly over the specified window."""
        series = pd.Series([1.0, 2.0, 3.0, 4.0, 5.0])
        result = compute_rolling_mean(series, window=3)
        expected = pd.Series([np.nan, np.nan, 2.0, 3.0, 4.0])
        pd.testing.assert_series_equal(result, expected)

    def test_rolling_mean_with_nans(self):
        """Rolling mean handles NaN values without propagating them."""
        series = pd.Series([1.0, np.nan, 3.0, 4.0, 5.0])
        result = compute_rolling_mean(series, window=3, min_periods=2)
        assert not result.iloc[3:].isna().any(), "NaNs should not propagate past the window"

    def test_encode_categorical_unknown_category(self):
        """Unknown categories at inference time map to a dedicated unknown index."""
        train_data = pd.Series(["cat", "dog", "bird"])
        encoder = encode_categorical(train_data, fit=True)
        test_data = pd.Series(["cat", "fish", "dog"])
        result = encode_categorical(test_data, encoder=encoder, fit=False)
        assert result[1] == encoder.unknown_index, "Unseen 'fish' should get unknown index"

    def test_normalize_features_zero_variance(self):
        """Zero-variance columns should not produce NaN or Inf after normalization."""
        df = pd.DataFrame({"constant": [5.0, 5.0, 5.0], "varying": [1.0, 2.0, 3.0]})
        result = normalize_features(df)
        assert not result.isna().any().any(), "No NaN values expected"
        assert not np.isinf(result.values).any(), "No Inf values expected"

    def test_clip_outliers_respects_bounds(self):
        """Outlier clipping enforces the specified percentile bounds."""
        data = pd.Series(range(1000))
        result = clip_outliers(data, lower_pct=0.01, upper_pct=0.99)
        assert result.min() >= data.quantile(0.01)
        assert result.max() <= data.quantile(0.99)

    def test_extract_time_features_components(self):
        """Time feature extraction produces expected columns."""
        dates = pd.Series(pd.to_datetime(["2025-01-15", "2025-06-20", "2025-12-31"]))
        result = extract_time_features(dates)
        assert "hour" in result.columns
        assert "day_of_week" in result.columns
        assert "month" in result.columns
        assert "is_weekend" in result.columns
```

### Testing Model Architecture

For neural network architectures, test that the model produces outputs of the correct shape
and dtype, that gradients flow through all parameters, and that a single batch can be
overfit (proving the model has sufficient capacity to learn):

```python
import torch
import pytest
from myproject.models import TransformerClassifier


class TestModelArchitecture:
    """Tests for model architecture correctness."""

    @pytest.fixture
    def model(self):
        return TransformerClassifier(
            vocab_size=1000,
            d_model=64,
            n_heads=4,
            n_layers=2,
            n_classes=10,
        )

    @pytest.fixture
    def sample_batch(self):
        batch_size, seq_len = 4, 32
        input_ids = torch.randint(0, 1000, (batch_size, seq_len))
        labels = torch.randint(0, 10, (batch_size,))
        return input_ids, labels

    def test_output_shape(self, model, sample_batch):
        """Model output has shape (batch_size, n_classes)."""
        input_ids, _ = sample_batch
        output = model(input_ids)
        assert output.shape == (4, 10), f"Expected (4, 10), got {output.shape}"

    def test_output_dtype(self, model, sample_batch):
        """Model output is float32 logits, not probabilities."""
        input_ids, _ = sample_batch
        output = model(input_ids)
        assert output.dtype == torch.float32

    def test_gradients_flow(self, model, sample_batch):
        """All parameters receive gradients after a backward pass."""
        input_ids, labels = sample_batch
        output = model(input_ids)
        loss = torch.nn.functional.cross_entropy(output, labels)
        loss.backward()
        for name, param in model.named_parameters():
            assert param.grad is not None, f"No gradient for {name}"
            assert not torch.all(param.grad == 0), f"Zero gradient for {name}"

    def test_single_batch_overfit(self, model, sample_batch):
        """Model can overfit a single batch, proving sufficient capacity."""
        input_ids, labels = sample_batch
        optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
        model.train()
        for _ in range(200):
            optimizer.zero_grad()
            output = model(input_ids)
            loss = torch.nn.functional.cross_entropy(output, labels)
            loss.backward()
            optimizer.step()
        model.eval()
        with torch.no_grad():
            preds = model(input_ids).argmax(dim=-1)
        accuracy = (preds == labels).float().mean().item()
        assert accuracy > 0.95, f"Could not overfit single batch: accuracy={accuracy}"
```

### Testing Loss Functions and Custom Metrics

Custom loss functions and evaluation metrics must be tested against known values:

```python
import torch
import pytest
from myproject.losses import focal_loss, weighted_cross_entropy
from myproject.metrics import mean_average_precision


class TestLossFunctions:
    """Tests for custom loss function implementations."""

    def test_focal_loss_reduces_to_ce_when_gamma_zero(self):
        """Focal loss with gamma=0 is equivalent to cross-entropy."""
        logits = torch.randn(16, 5)
        targets = torch.randint(0, 5, (16,))
        fl = focal_loss(logits, targets, gamma=0.0, reduction="mean")
        ce = torch.nn.functional.cross_entropy(logits, targets, reduction="mean")
        torch.testing.assert_close(fl, ce, atol=1e-5, rtol=1e-5)

    def test_focal_loss_down_weights_easy_examples(self):
        """Focal loss with gamma > 0 produces lower loss on confident predictions."""
        logits_confident = torch.tensor([[10.0, -10.0]])
        logits_uncertain = torch.tensor([[0.1, -0.1]])
        targets = torch.tensor([0])
        loss_confident = focal_loss(logits_confident, targets, gamma=2.0)
        loss_uncertain = focal_loss(logits_uncertain, targets, gamma=2.0)
        assert loss_confident < loss_uncertain

    def test_weighted_cross_entropy_respects_weights(self):
        """Class weights increase the contribution of minority classes."""
        logits = torch.randn(100, 3)
        targets = torch.zeros(100, dtype=torch.long)  # all class 0
        weights_equal = torch.tensor([1.0, 1.0, 1.0])
        weights_upweight = torch.tensor([5.0, 1.0, 1.0])
        loss_equal = weighted_cross_entropy(logits, targets, weights_equal)
        loss_upweight = weighted_cross_entropy(logits, targets, weights_upweight)
        assert loss_upweight > loss_equal, "Upweighting class 0 should increase loss"
```

---

## 3. Data Validation Tests

Data is the most common source of ML failures. Data validation tests serve as the first
line of defense, catching schema violations, distribution shifts, missing values, and
constraint violations before they silently corrupt model training.

### Schema Validation with Great Expectations

Great Expectations provides a declarative framework for expressing data expectations. Each
expectation is a testable assertion about your data that can be version-controlled, reviewed,
and executed automatically.

```python
import great_expectations as gx
import pytest
import pandas as pd


class TestDataSchema:
    """Data schema and constraint validation using Great Expectations."""

    @pytest.fixture
    def training_data(self):
        """Load the current training dataset."""
        return pd.read_parquet("data/processed/training_set.parquet")

    @pytest.fixture
    def gx_context(self):
        """Initialize the Great Expectations context."""
        return gx.get_context()

    def test_required_columns_present(self, training_data):
        """All required feature columns exist in the training data."""
        required = [
            "user_id", "timestamp", "feature_a", "feature_b",
            "feature_c", "label", "split",
        ]
        missing = set(required) - set(training_data.columns)
        assert not missing, f"Missing required columns: {missing}"

    def test_no_null_values_in_features(self, training_data):
        """Feature columns contain no null values after preprocessing."""
        feature_cols = [c for c in training_data.columns if c.startswith("feature_")]
        null_counts = training_data[feature_cols].isnull().sum()
        cols_with_nulls = null_counts[null_counts > 0]
        assert cols_with_nulls.empty, f"Null values found: {cols_with_nulls.to_dict()}"

    def test_label_distribution_not_degenerate(self, training_data):
        """Label column has at least two distinct values with minimum representation."""
        label_counts = training_data["label"].value_counts(normalize=True)
        assert len(label_counts) >= 2, "Label column must have at least 2 classes"
        min_frequency = label_counts.min()
        assert min_frequency > 0.01, (
            f"Minority class has only {min_frequency:.2%} representation — "
            "check for label leakage or data corruption"
        )

    def test_feature_ranges_within_expected_bounds(self, training_data):
        """Numeric features fall within physically plausible ranges."""
        bounds = {
            "feature_a": (0.0, 1.0),
            "feature_b": (-100.0, 100.0),
            "feature_c": (0.0, float("inf")),
        }
        for col, (low, high) in bounds.items():
            series = training_data[col]
            assert series.min() >= low, f"{col} has value below {low}: {series.min()}"
            assert series.max() <= high, f"{col} has value above {high}: {series.max()}"

    def test_no_duplicate_primary_keys(self, training_data):
        """Each record has a unique (user_id, timestamp) combination."""
        duplicates = training_data.duplicated(subset=["user_id", "timestamp"], keep=False)
        n_duplicates = duplicates.sum()
        assert n_duplicates == 0, f"Found {n_duplicates} duplicate (user_id, timestamp) pairs"

    def test_timestamp_ordering(self, training_data):
        """Training data is sorted by timestamp with no future-dated records."""
        timestamps = pd.to_datetime(training_data["timestamp"])
        assert timestamps.is_monotonic_increasing, "Data should be sorted by timestamp"
        assert timestamps.max() <= pd.Timestamp.now(), "Found future-dated records"

    def test_train_test_split_no_leakage(self, training_data):
        """No user_id appears in both train and test splits."""
        train_users = set(training_data[training_data["split"] == "train"]["user_id"])
        test_users = set(training_data[training_data["split"] == "test"]["user_id"])
        leaked = train_users & test_users
        assert not leaked, f"User IDs in both splits (data leakage): {len(leaked)} users"
```

### Statistical Data Drift Detection

Beyond schema validation, test whether the current data distribution has drifted from
the reference distribution used during training:

```python
import numpy as np
from scipy import stats
import pytest


class TestDataDrift:
    """Detect distribution shifts between training and serving data."""

    @pytest.fixture
    def reference_stats(self):
        """Load saved statistics from the training data distribution."""
        return np.load("tests/fixtures/baseline_metrics/reference_stats.npz")

    @pytest.fixture
    def current_data(self):
        """Load the most recent batch of serving data."""
        return np.load("data/serving/latest_batch.npz")

    def test_feature_mean_stability(self, reference_stats, current_data):
        """Feature means have not shifted beyond 3 standard deviations."""
        for feature_name in reference_stats["feature_names"]:
            ref_mean = reference_stats[f"{feature_name}_mean"]
            ref_std = reference_stats[f"{feature_name}_std"]
            current_mean = current_data[feature_name].mean()
            z_score = abs(current_mean - ref_mean) / (ref_std + 1e-8)
            assert z_score < 3.0, (
                f"Feature '{feature_name}' mean shifted by {z_score:.1f} std devs "
                f"(ref={ref_mean:.4f}, current={current_mean:.4f})"
            )

    def test_ks_test_feature_distributions(self, reference_stats, current_data):
        """Kolmogorov-Smirnov test detects no significant distribution shift."""
        for feature_name in reference_stats["feature_names"]:
            ref_samples = reference_stats[f"{feature_name}_samples"]
            current_samples = current_data[feature_name]
            statistic, p_value = stats.ks_2samp(ref_samples, current_samples)
            assert p_value > 0.01, (
                f"Distribution shift detected for '{feature_name}': "
                f"KS statistic={statistic:.4f}, p-value={p_value:.6f}"
            )
```

---

## 4. Model Quality Tests

Model quality tests assert that a trained model meets minimum performance thresholds.
These tests act as quality gates — a model that fails them should not be deployed.

### Accuracy and Metric Thresholds

```python
import pytest
import numpy as np
from sklearn.metrics import (
    accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    roc_auc_score,
)
from myproject.model import load_model
from myproject.data import load_test_set


class TestModelQuality:
    """Quality gate tests for trained model performance."""

    @pytest.fixture(scope="class")
    def model_and_data(self):
        """Load trained model and held-out test set."""
        model = load_model("artifacts/latest/model.pkl")
        X_test, y_test = load_test_set("data/processed/test_set.parquet")
        y_pred = model.predict(X_test)
        y_prob = model.predict_proba(X_test)[:, 1]
        return y_test, y_pred, y_prob

    def test_accuracy_above_threshold(self, model_and_data):
        """Overall accuracy exceeds the minimum deployment threshold."""
        y_test, y_pred, _ = model_and_data
        accuracy = accuracy_score(y_test, y_pred)
        assert accuracy >= 0.85, f"Accuracy {accuracy:.4f} below threshold 0.85"

    def test_precision_above_threshold(self, model_and_data):
        """Precision exceeds minimum to control false positive rate."""
        y_test, y_pred, _ = model_and_data
        precision = precision_score(y_test, y_pred, average="weighted")
        assert precision >= 0.80, f"Precision {precision:.4f} below threshold 0.80"

    def test_recall_above_threshold(self, model_and_data):
        """Recall exceeds minimum to control false negative rate."""
        y_test, y_pred, _ = model_and_data
        recall = recall_score(y_test, y_pred, average="weighted")
        assert recall >= 0.75, f"Recall {recall:.4f} below threshold 0.75"

    def test_auc_above_threshold(self, model_and_data):
        """AUC-ROC exceeds minimum for ranking quality."""
        y_test, _, y_prob = model_and_data
        auc = roc_auc_score(y_test, y_prob)
        assert auc >= 0.90, f"AUC {auc:.4f} below threshold 0.90"

    def test_prediction_distribution_not_degenerate(self, model_and_data):
        """Model does not predict a single class for all inputs."""
        _, y_pred, _ = model_and_data
        unique_preds = np.unique(y_pred)
        assert len(unique_preds) > 1, (
            f"Model predicts only class {unique_preds[0]} — "
            "likely a collapsed or untrained model"
        )

    def test_probability_calibration(self, model_and_data):
        """Predicted probabilities are reasonably calibrated."""
        y_test, _, y_prob = model_and_data
        # Bin predictions and check calibration
        n_bins = 10
        bin_edges = np.linspace(0, 1, n_bins + 1)
        for i in range(n_bins):
            mask = (y_prob >= bin_edges[i]) & (y_prob < bin_edges[i + 1])
            if mask.sum() < 10:
                continue  # skip bins with too few samples
            predicted_rate = y_prob[mask].mean()
            actual_rate = y_test[mask].mean()
            calibration_error = abs(predicted_rate - actual_rate)
            assert calibration_error < 0.15, (
                f"Calibration error in bin [{bin_edges[i]:.1f}, {bin_edges[i+1]:.1f}): "
                f"predicted={predicted_rate:.3f}, actual={actual_rate:.3f}"
            )
```

### Testing Model Serialization Roundtrips

A model that cannot survive serialization and deserialization is not deployable. Test that
the full save/load cycle preserves prediction behavior:

```python
import tempfile
import os
import numpy as np
import pytest
from myproject.model import save_model, load_model, create_model


class TestSerializationRoundtrip:
    """Test that models survive serialization without prediction drift."""

    @pytest.fixture
    def trained_model(self):
        """Create and train a small model for testing."""
        model = create_model(config="tests/fixtures/small_model_config.yaml")
        X_train = np.random.randn(100, 10)
        y_train = np.random.randint(0, 2, 100)
        model.fit(X_train, y_train)
        return model

    @pytest.fixture
    def test_inputs(self):
        return np.random.randn(20, 10)

    def test_predictions_identical_after_roundtrip(self, trained_model, test_inputs):
        """Predictions are bit-for-bit identical after save and load."""
        preds_before = trained_model.predict(test_inputs)
        probs_before = trained_model.predict_proba(test_inputs)

        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "model.pkl")
            save_model(trained_model, path)
            loaded_model = load_model(path)

        preds_after = loaded_model.predict(test_inputs)
        probs_after = loaded_model.predict_proba(test_inputs)

        np.testing.assert_array_equal(preds_before, preds_after)
        np.testing.assert_array_almost_equal(probs_before, probs_after, decimal=10)

    def test_model_file_not_empty(self, trained_model):
        """Serialized model file has non-trivial size."""
        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "model.pkl")
            save_model(trained_model, path)
            file_size = os.path.getsize(path)
            assert file_size > 1000, f"Suspiciously small model file: {file_size} bytes"
```

---

## 5. Pipeline Integration Tests

Integration tests verify that the full pipeline — from raw data ingestion through feature
engineering to model inference — works end-to-end. These tests catch interface mismatches
between pipeline stages.

```python
import pytest
import pandas as pd
import numpy as np
from myproject.pipeline import (
    IngestStage,
    PreprocessStage,
    FeatureStage,
    InferenceStage,
    PipelineRunner,
)


class TestPipelineIntegration:
    """End-to-end pipeline integration tests."""

    @pytest.fixture
    def sample_raw_data(self):
        """Minimal raw data that exercises all pipeline stages."""
        return pd.DataFrame({
            "user_id": [1, 2, 3, 4, 5],
            "event_time": pd.date_range("2025-01-01", periods=5, freq="h"),
            "action": ["click", "view", "click", "purchase", "view"],
            "amount": [0.0, 0.0, 0.0, 49.99, 0.0],
            "device": ["mobile", "desktop", "mobile", "desktop", "tablet"],
        })

    @pytest.fixture
    def pipeline(self):
        """Construct the full pipeline with test configuration."""
        return PipelineRunner(
            stages=[
                IngestStage(),
                PreprocessStage(),
                FeatureStage(),
                InferenceStage(model_path="tests/fixtures/trained_models/small_model.pkl"),
            ]
        )

    def test_pipeline_produces_predictions(self, pipeline, sample_raw_data):
        """Pipeline runs to completion and outputs predictions."""
        result = pipeline.run(sample_raw_data)
        assert "prediction" in result.columns
        assert len(result) == len(sample_raw_data)

    def test_pipeline_predictions_in_valid_range(self, pipeline, sample_raw_data):
        """Predicted probabilities are in [0, 1]."""
        result = pipeline.run(sample_raw_data)
        assert result["prediction"].between(0, 1).all(), (
            "Predictions outside [0, 1] range detected"
        )

    def test_pipeline_preserves_primary_key(self, pipeline, sample_raw_data):
        """The user_id column survives all pipeline transformations."""
        result = pipeline.run(sample_raw_data)
        pd.testing.assert_series_equal(
            result["user_id"].reset_index(drop=True),
            sample_raw_data["user_id"].reset_index(drop=True),
        )

    def test_pipeline_handles_empty_input(self, pipeline):
        """Pipeline handles empty input gracefully instead of crashing."""
        empty_df = pd.DataFrame(columns=["user_id", "event_time", "action", "amount", "device"])
        result = pipeline.run(empty_df)
        assert len(result) == 0
        assert "prediction" in result.columns

    def test_pipeline_handles_single_row(self, pipeline, sample_raw_data):
        """Pipeline works correctly with a single-row input."""
        single_row = sample_raw_data.iloc[:1]
        result = pipeline.run(single_row)
        assert len(result) == 1
        assert "prediction" in result.columns
```

---

## 6. Property-Based Testing with Hypothesis

Property-based testing uses the Hypothesis library to generate random inputs and verify
that invariant properties hold across all of them. This approach is particularly powerful
for ML data transforms because it discovers edge cases that hand-written examples miss.
Research published in 2024 (IEEE ICSME) examined 58 open-source ML projects using Hypothesis
and found that property-based tests were effective at catching subtle bugs in data
transformation code that example-based tests missed entirely.

### Testing Transform Invariants

Many data transformations have mathematical properties that must hold regardless of input:

```python
import numpy as np
import pandas as pd
import pytest
from hypothesis import given, settings, assume
from hypothesis import strategies as st
from hypothesis.extra.numpy import arrays
from hypothesis.extra.pandas import columns, data_frames, column
from myproject.transforms import (
    normalize,
    one_hot_encode,
    log_transform,
    impute_median,
)


class TestTransformInvariants:
    """Property-based tests for data transformation invariants."""

    @given(
        data=arrays(
            dtype=np.float64,
            shape=st.tuples(
                st.integers(min_value=2, max_value=100),
                st.integers(min_value=1, max_value=20),
            ),
            elements=st.floats(min_value=-1e6, max_value=1e6, allow_nan=False),
        )
    )
    @settings(max_examples=200, deadline=None)
    def test_normalize_output_range(self, data):
        """Normalized data has zero mean and unit variance per column."""
        result = normalize(data)
        for col_idx in range(data.shape[1]):
            col = result[:, col_idx]
            if np.std(data[:, col_idx]) < 1e-10:
                continue  # skip constant columns
            assert abs(np.mean(col)) < 1e-6, f"Mean not zero for column {col_idx}"
            assert abs(np.std(col) - 1.0) < 1e-6, f"Std not 1 for column {col_idx}"

    @given(
        data=arrays(
            dtype=np.float64,
            shape=st.tuples(
                st.integers(min_value=2, max_value=100),
                st.integers(min_value=1, max_value=20),
            ),
            elements=st.floats(min_value=-1e6, max_value=1e6, allow_nan=False),
        )
    )
    @settings(max_examples=200, deadline=None)
    def test_normalize_preserves_shape(self, data):
        """Normalization does not change the shape of the data."""
        result = normalize(data)
        assert result.shape == data.shape

    @given(
        values=st.lists(
            st.sampled_from(["red", "green", "blue", "yellow"]),
            min_size=1,
            max_size=50,
        )
    )
    def test_one_hot_rows_sum_to_one(self, values):
        """Each row in a one-hot encoding sums to exactly 1."""
        series = pd.Series(values)
        result = one_hot_encode(series)
        row_sums = result.sum(axis=1)
        assert (row_sums == 1).all(), "One-hot rows must sum to 1"

    @given(
        data=arrays(
            dtype=np.float64,
            shape=st.integers(min_value=5, max_value=200),
            elements=st.floats(min_value=0.01, max_value=1e6),
        )
    )
    def test_log_transform_monotonic(self, data):
        """Log transform preserves ordering of positive values."""
        result = log_transform(data)
        for i in range(len(data) - 1):
            if data[i] < data[i + 1]:
                assert result[i] < result[i + 1], "Monotonicity violated"
            elif data[i] > data[i + 1]:
                assert result[i] > result[i + 1], "Monotonicity violated"

    @given(
        df=data_frames(
            columns=[
                column("a", dtype=float, elements=st.floats(-100, 100, allow_nan=True)),
                column("b", dtype=float, elements=st.floats(-100, 100, allow_nan=True)),
            ],
            rows=st.tuples(
                st.floats(-100, 100, allow_nan=True),
                st.floats(-100, 100, allow_nan=True),
            ),
            index=st.just(pd.RangeIndex(10)),
        )
    )
    def test_impute_median_no_nans_remain(self, df):
        """Median imputation eliminates all NaN values."""
        assume(not df.isna().all().any())  # skip if an entire column is NaN
        result = impute_median(df)
        assert not result.isna().any().any(), "NaN values remain after imputation"
```

---

## 7. Fixture & Factory Patterns

Well-designed fixtures reduce test boilerplate and ensure consistency. For ML testing,
fixtures fall into three categories: data fixtures, model fixtures, and metric fixtures.

### Shared Conftest Configuration

```python
# tests/conftest.py
import pytest
import numpy as np
import pandas as pd
import torch
import tempfile
import os


@pytest.fixture(scope="session")
def random_seed():
    """Global random seed for reproducibility across all tests."""
    return 42


@pytest.fixture(autouse=True)
def set_random_seeds(random_seed):
    """Set all random seeds before each test for determinism."""
    np.random.seed(random_seed)
    torch.manual_seed(random_seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(random_seed)
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.benchmark = False


@pytest.fixture(scope="session")
def sample_classification_data():
    """Generate a small but realistic classification dataset."""
    np.random.seed(42)
    n_samples = 500
    n_features = 10
    X = np.random.randn(n_samples, n_features)
    # Create a linearly separable problem with some noise
    true_weights = np.random.randn(n_features)
    logits = X @ true_weights + np.random.randn(n_samples) * 0.5
    y = (logits > 0).astype(int)
    return X, y


@pytest.fixture(scope="session")
def sample_dataframe():
    """Generate a sample DataFrame mimicking production data."""
    np.random.seed(42)
    n = 200
    return pd.DataFrame({
        "user_id": range(n),
        "timestamp": pd.date_range("2025-01-01", periods=n, freq="h"),
        "feature_a": np.random.uniform(0, 1, n),
        "feature_b": np.random.normal(0, 10, n),
        "feature_c": np.random.exponential(5, n),
        "category": np.random.choice(["A", "B", "C"], n),
        "label": np.random.randint(0, 2, n),
    })


@pytest.fixture
def tmp_model_dir():
    """Temporary directory for model artifacts that auto-cleans."""
    with tempfile.TemporaryDirectory(prefix="ml_test_") as tmpdir:
        yield tmpdir


@pytest.fixture(scope="session")
def device():
    """Return the appropriate torch device based on availability."""
    if torch.cuda.is_available():
        return torch.device("cuda")
    elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")
```

### Factory Functions for Test Data

When tests need variations on a dataset, factory functions are cleaner than duplicating
fixture code:

```python
# tests/factories.py
import numpy as np
import pandas as pd
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class DatasetFactory:
    """Factory for generating test datasets with configurable properties."""

    n_samples: int = 100
    n_features: int = 10
    n_classes: int = 2
    noise_level: float = 0.1
    missing_rate: float = 0.0
    class_imbalance: Optional[float] = None
    seed: int = 42

    def create(self) -> tuple:
        """Generate a dataset with the specified properties."""
        rng = np.random.RandomState(self.seed)
        X = rng.randn(self.n_samples, self.n_features)

        if self.class_imbalance:
            # Create imbalanced classes
            threshold = np.quantile(X[:, 0], self.class_imbalance)
            y = (X[:, 0] > threshold).astype(int)
        else:
            weights = rng.randn(self.n_features)
            logits = X @ weights + rng.randn(self.n_samples) * self.noise_level
            y = (logits > 0).astype(int)

        if self.missing_rate > 0:
            mask = rng.random(X.shape) < self.missing_rate
            X[mask] = np.nan

        return X, y

    def create_dataframe(self) -> pd.DataFrame:
        """Generate a dataset as a pandas DataFrame."""
        X, y = self.create()
        df = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(self.n_features)])
        df["label"] = y
        return df
```

---

## 8. Regression Detection

Regression detection compares current model metrics against a saved baseline. If any metric
degrades beyond a threshold, the test fails — preventing silent performance regressions from
reaching production.

### Baseline Comparison Tests

```python
import json
import pytest
import numpy as np
from pathlib import Path
from sklearn.metrics import accuracy_score, f1_score, roc_auc_score
from myproject.model import load_model
from myproject.data import load_test_set

BASELINE_PATH = Path("tests/fixtures/baseline_metrics/baseline.json")
REGRESSION_TOLERANCE = 0.02  # allow up to 2% degradation


class TestRegressionDetection:
    """Compare current model metrics against saved baselines."""

    @pytest.fixture(scope="class")
    def baseline_metrics(self):
        """Load the baseline metrics from the last approved model."""
        with open(BASELINE_PATH) as f:
            return json.load(f)

    @pytest.fixture(scope="class")
    def current_metrics(self):
        """Compute metrics for the current model on the held-out test set."""
        model = load_model("artifacts/latest/model.pkl")
        X_test, y_test = load_test_set("data/processed/test_set.parquet")
        y_pred = model.predict(X_test)
        y_prob = model.predict_proba(X_test)[:, 1]
        return {
            "accuracy": accuracy_score(y_test, y_pred),
            "f1": f1_score(y_test, y_pred, average="weighted"),
            "auc_roc": roc_auc_score(y_test, y_prob),
        }

    def test_accuracy_not_regressed(self, baseline_metrics, current_metrics):
        """Accuracy has not dropped below baseline minus tolerance."""
        baseline = baseline_metrics["accuracy"]
        current = current_metrics["accuracy"]
        assert current >= baseline - REGRESSION_TOLERANCE, (
            f"Accuracy regression: {current:.4f} < {baseline:.4f} - {REGRESSION_TOLERANCE}"
        )

    def test_f1_not_regressed(self, baseline_metrics, current_metrics):
        """F1 score has not dropped below baseline minus tolerance."""
        baseline = baseline_metrics["f1"]
        current = current_metrics["f1"]
        assert current >= baseline - REGRESSION_TOLERANCE, (
            f"F1 regression: {current:.4f} < {baseline:.4f} - {REGRESSION_TOLERANCE}"
        )

    def test_auc_not_regressed(self, baseline_metrics, current_metrics):
        """AUC-ROC has not dropped below baseline minus tolerance."""
        baseline = baseline_metrics["auc_roc"]
        current = current_metrics["auc_roc"]
        assert current >= baseline - REGRESSION_TOLERANCE, (
            f"AUC regression: {current:.4f} < {baseline:.4f} - {REGRESSION_TOLERANCE}"
        )


def update_baseline(metrics: dict, path: Path = BASELINE_PATH):
    """
    Utility to update the baseline after an approved model change.
    Run manually: python -c "from tests.quality.test_regression_baselines import ..."
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(metrics, f, indent=2)
    print(f"Baseline updated at {path}")
```

### Training Determinism Tests

Verify that training with a fixed seed produces identical results, ensuring reproducibility
for debugging and auditing:

```python
import torch
import numpy as np
import pytest
from myproject.training import train_model
from myproject.config import TrainingConfig


class TestTrainingDeterminism:
    """Verify that training is reproducible with fixed seeds."""

    @pytest.fixture
    def config(self):
        return TrainingConfig(
            seed=42,
            epochs=5,
            batch_size=32,
            learning_rate=1e-3,
            model_type="small",
        )

    @pytest.fixture
    def training_data(self):
        np.random.seed(42)
        X = np.random.randn(200, 10).astype(np.float32)
        y = np.random.randint(0, 2, 200)
        return X, y

    def test_identical_weights_from_same_seed(self, config, training_data):
        """Two training runs with the same seed produce identical model weights."""
        X, y = training_data

        model_1 = train_model(X, y, config)
        model_2 = train_model(X, y, config)

        for (name1, p1), (name2, p2) in zip(
            model_1.named_parameters(), model_2.named_parameters()
        ):
            assert name1 == name2
            torch.testing.assert_close(
                p1, p2,
                msg=f"Weight mismatch in {name1} between two seeded runs"
            )

    def test_different_seeds_produce_different_weights(self, config, training_data):
        """Different seeds produce meaningfully different models."""
        X, y = training_data

        config_a = config
        config_b = TrainingConfig(**{**config.__dict__, "seed": 123})

        model_a = train_model(X, y, config_a)
        model_b = train_model(X, y, config_b)

        any_different = False
        for (_, pa), (_, pb) in zip(
            model_a.named_parameters(), model_b.named_parameters()
        ):
            if not torch.allclose(pa, pb, atol=1e-6):
                any_different = True
                break
        assert any_different, "Different seeds produced identical models — RNG may be broken"
```

### GPU vs CPU Parity Testing

When models run on different hardware in different environments (GPU in training, CPU in
production), verify that predictions remain consistent. PyTorch documentation notes that
completely deterministic behavior across devices requires explicit configuration:

```python
import torch
import numpy as np
import pytest
from myproject.model import create_model


@pytest.mark.gpu
class TestDeviceParity:
    """Test that model predictions are consistent across CPU and GPU."""

    @pytest.fixture
    def model_and_input(self):
        """Create a small model and fixed input tensor."""
        torch.manual_seed(42)
        model = create_model(config="tests/fixtures/small_model_config.yaml")
        model.eval()
        test_input = torch.randn(8, 32)  # batch of 8, sequence length 32
        return model, test_input

    @pytest.mark.skipif(not torch.cuda.is_available(), reason="CUDA not available")
    def test_cpu_gpu_prediction_parity(self, model_and_input):
        """CPU and GPU predictions agree within floating-point tolerance."""
        model, test_input = model_and_input

        # CPU inference
        model_cpu = model.cpu()
        with torch.no_grad():
            preds_cpu = model_cpu(test_input.cpu())

        # GPU inference
        model_gpu = model.cuda()
        with torch.no_grad():
            preds_gpu = model_gpu(test_input.cuda())

        torch.testing.assert_close(
            preds_cpu,
            preds_gpu.cpu(),
            atol=1e-5,
            rtol=1e-4,
            msg="CPU/GPU predictions diverge beyond tolerance",
        )

    @pytest.mark.skipif(not torch.cuda.is_available(), reason="CUDA not available")
    def test_gpu_inference_determinism(self, model_and_input):
        """Multiple GPU inferences with the same input produce identical results."""
        model, test_input = model_and_input
        model_gpu = model.cuda()
        model_gpu.eval()
        input_gpu = test_input.cuda()

        with torch.no_grad():
            preds_1 = model_gpu(input_gpu)
            preds_2 = model_gpu(input_gpu)

        torch.testing.assert_close(preds_1, preds_2)
```

---

## 9. CI/CD for ML

ML-specific CI/CD extends traditional software CI with data validation gates, model quality
checks, and automated baseline updates. The goal is to catch issues at the right stage of the
pipeline without making every PR wait for a full training run.

### GitHub Actions Workflow

```yaml
# .github/workflows/ml-tests.yml
name: ML Test Suite

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -e ".[test]"
      - run: pytest tests/unit -m unit -v --tb=short
        name: Run unit tests

  data-validation:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -e ".[test]"
      - run: pytest tests/data -m data -v --tb=short
        name: Run data validation tests

  model-quality:
    runs-on: [self-hosted, gpu]
    needs: data-validation
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -e ".[test,gpu]"
      - run: pytest tests/quality -m quality -v --tb=long
        name: Run model quality tests
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: quality-report
          path: reports/quality/

  property-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -e ".[test]"
      - run: pytest tests/property -v --hypothesis-seed=0
        name: Run property-based tests
```

### MLflow Integration for Metric Tracking

Use MLflow to track metrics across test runs, providing historical context for regression
detection:

```python
import mlflow
import pytest
from sklearn.metrics import accuracy_score, f1_score
from myproject.model import load_model
from myproject.data import load_test_set


@pytest.fixture(scope="session", autouse=True)
def mlflow_experiment():
    """Set up MLflow tracking for this test run."""
    mlflow.set_tracking_uri("http://mlflow.internal:5000")
    mlflow.set_experiment("model-quality-tests")
    with mlflow.start_run(run_name="ci-quality-gate"):
        yield


class TestModelQualityWithTracking:
    """Model quality tests that log results to MLflow."""

    @pytest.fixture(scope="class")
    def predictions(self):
        model = load_model("artifacts/latest/model.pkl")
        X_test, y_test = load_test_set("data/processed/test_set.parquet")
        y_pred = model.predict(X_test)
        return y_test, y_pred

    def test_accuracy_threshold(self, predictions):
        y_test, y_pred = predictions
        accuracy = accuracy_score(y_test, y_pred)
        mlflow.log_metric("test_accuracy", accuracy)
        assert accuracy >= 0.85

    def test_f1_threshold(self, predictions):
        y_test, y_pred = predictions
        f1 = f1_score(y_test, y_pred, average="weighted")
        mlflow.log_metric("test_f1", f1)
        assert f1 >= 0.80
```

---

## 10. Best Practices

### Test Data Management

- **Never test against production data directly.** Use representative samples, synthetic
  data, or anonymized snapshots. Production data access in tests creates security risks
  and makes tests non-reproducible.
- **Version your test fixtures alongside code.** When feature engineering changes, the
  test data must change with it. Use DVC or Git LFS for large fixtures.
- **Use factories over static fixtures.** Static test data files become stale. Factory
  functions (see Section 7) generate fresh data with configurable properties.

### Seed Management

- **Set seeds globally in conftest.py** using an `autouse` fixture that configures NumPy,
  PyTorch, TensorFlow, and Python's `random` module. This prevents flaky tests caused by
  non-deterministic behavior.
- **Use `torch.use_deterministic_algorithms(True)`** during testing. This forces PyTorch
  to use deterministic implementations of operations. Some operations will raise errors
  rather than silently produce non-deterministic results.
- **Document known sources of non-determinism.** GPU operations, multi-threaded data
  loading, and certain CuDNN algorithms have inherent non-determinism. When parity tests
  use tolerances, explain why in the docstring.

### Threshold Selection

- **Base thresholds on historical performance, not aspirational targets.** If your model
  historically achieves 0.87 accuracy, set the threshold at 0.85 (allowing 2% degradation),
  not at 0.90.
- **Use separate thresholds for different segments.** A model may perform well overall but
  fail catastrophically on a minority subgroup. Add per-segment tests for critical slices.
- **Review and update thresholds quarterly.** As models improve, tighten thresholds. As
  data shifts, adjust expectations. Stale thresholds either never fail or always fail.

### Test Performance

- **Use `scope="session"` for expensive fixtures.** Loading a model or dataset once per
  test session instead of once per test saves minutes of runtime.
- **Mark slow tests and skip them locally.** Developers should run `pytest -m "not slow"`
  for fast feedback, with the full suite running in CI.
- **Parallelize with pytest-xdist.** Data validation tests and unit tests are usually
  independent and can run in parallel: `pytest -n auto tests/unit tests/data`.

### Data Pipeline Testing

- **Test each pipeline stage in isolation and then together.** Unit tests verify individual
  transforms. Integration tests verify the full pipeline produces valid output.
- **Validate data at pipeline boundaries.** Add schema checks after every stage that
  transforms data shape or types.
- **Test with adversarial inputs.** Empty DataFrames, single-row inputs, all-NaN columns,
  and extremely large values expose fragile assumptions.

### Continuous Monitoring

- **Log test metrics to MLflow or a similar platform.** This creates a history of model
  quality over time and helps diagnose when regressions were introduced.
- **Set up alerts for data drift.** Automated drift detection (Section 3) should run on
  a schedule, not just during CI.
- **Compare training and serving distributions.** If the data a model sees in production
  differs from what it was trained on, the model is unreliable regardless of test results.

---

## 11. Anti-Patterns

### The "It Compiles, Ship It" Anti-Pattern

**Problem:** The test suite only checks that code runs without exceptions. No assertions
about output quality, data validity, or metric thresholds.

```python
# BAD: This "test" proves nothing about correctness
def test_model_runs():
    model = load_model("model.pkl")
    X = load_data("test.csv")
    result = model.predict(X)  # no assertion — just checking it doesn't crash
```

**Fix:** Always assert on the output. At minimum, check shape, dtype, value range, and
distribution.

### The "Magic Number" Anti-Pattern

**Problem:** Thresholds are hardcoded without context or justification. When they fail,
nobody knows whether to fix the model or update the threshold.

```python
# BAD: Where does 0.847 come from? Is this realistic?
def test_accuracy():
    assert accuracy >= 0.847  # arbitrary, undocumented threshold
```

**Fix:** Document threshold provenance, store baselines in version-controlled JSON files,
and reference the baseline in test docstrings.

### The "Test on Training Data" Anti-Pattern

**Problem:** Model quality tests evaluate the model on data it was trained on, producing
unrealistically high metrics that mask poor generalization.

```python
# BAD: Testing on training data gives inflated metrics
def test_model_accuracy():
    model = load_model("model.pkl")
    X_train, y_train = load_training_data()  # same data used for training!
    accuracy = accuracy_score(y_train, model.predict(X_train))
    assert accuracy > 0.95  # of course it's high — the model memorized this data
```

**Fix:** Always evaluate on held-out test data that was not used during training. Verify
no data leakage between splits (Section 3).

### The "Flaky Seed" Anti-Pattern

**Problem:** Tests pass or fail depending on random state. Seeds are not set consistently,
or they are set in some places but not others (e.g., NumPy is seeded but not PyTorch).

```python
# BAD: No seed management — results vary on every run
def test_model_training():
    model = train_model(data)  # non-deterministic without seed
    assert accuracy_score(y_test, model.predict(X_test)) > 0.80  # sometimes passes
```

**Fix:** Use the `autouse` seed fixture from Section 7. Set seeds for every source of
randomness: NumPy, PyTorch, TensorFlow, Python `random`, and CUDA.

### The "Tolerance Creep" Anti-Pattern

**Problem:** When GPU/CPU parity tests fail, the response is to widen tolerances until
they pass, gradually accepting larger and larger discrepancies.

```python
# BAD: Tolerance widened repeatedly to make tests pass
torch.testing.assert_close(cpu_output, gpu_output, atol=0.1, rtol=0.1)  # was 1e-5
```

**Fix:** Investigate the root cause of divergence. Use `float32` precision when parity
matters. If wider tolerance is truly needed, document the specific operation causing
divergence and add a comment explaining the rationale.

### The "Test Everything in One Function" Anti-Pattern

**Problem:** A single test function checks accuracy, precision, recall, calibration,
latency, and fairness. When it fails, the failure message is ambiguous.

```python
# BAD: Monolithic test with multiple unrelated assertions
def test_model():
    # ... 100 lines of setup ...
    assert accuracy > 0.85
    assert precision > 0.80
    assert recall > 0.75
    assert latency < 100  # ms
    assert max_memory < 2048  # MB
    # first failure hides all subsequent issues
```

**Fix:** One test, one concern. Each assertion gets its own test function with a descriptive
name. When accuracy drops, you see `test_accuracy_above_threshold FAILED`, not
`test_model FAILED`.

### The "No Baseline" Anti-Pattern

**Problem:** Tests check absolute thresholds but never compare against the previous model
version. A 2% accuracy drop from 0.92 to 0.90 still passes the 0.85 threshold but
represents a significant regression.

**Fix:** Maintain baseline metrics in version control (Section 8). Test both absolute
thresholds and relative regressions.

### The "GPU-Only Testing" Anti-Pattern

**Problem:** The test suite only runs on GPU machines, meaning developers without GPUs
cannot run any tests locally. This slows down the feedback loop.

**Fix:** Structure the suite so that unit tests, data validation, and property tests
run on CPU. Only GPU-specific tests (parity, performance benchmarks) require GPU hardware.
Use `@pytest.mark.gpu` and `pytest.importorskip("torch.cuda")` to handle this gracefully.

---

## Sources & References

- [Made With ML - Testing Machine Learning Systems: Code, Data and Models](https://madewithml.com/courses/mlops/testing/) — Comprehensive guide covering unit tests, data tests, and model tests for ML systems.
- [Hypothesis - Property-Based Testing for Python](https://hypothesis.works/articles/what-is-property-based-testing/) — Official documentation for the Hypothesis library used in property-based testing of data transforms.
- [Great Expectations - Data Validation Framework](https://greatexpectations.io/) — The standard open-source framework for declarative data validation in ML pipelines.
- [MLflow Model Evaluation](https://mlflow.org/docs/latest/ml/evaluation/) — MLflow documentation for automated model assessment with metric thresholds and validation.
- [PyTorch Reproducibility Guide](https://docs.pytorch.org/docs/stable/notes/randomness.html) — Official PyTorch documentation on controlling randomness and achieving deterministic behavior across CPU and GPU.
- [Deepchecks - ML Testing Best Practices](https://www.deepchecks.com/ml-testing-best-practices-and-their-implementation/) — Overview of ML testing strategies including data integrity, model performance, and drift detection.
- [Hopsworks - Testing Feature Pipelines with pytest](https://www.hopsworks.ai/post/testing-feature-logic-transformations-and-feature-pipelines-with-pytest) — Practical guide to testing feature logic and transformation pipelines using pytest.
- [IEEE ICSME 2024 - Property-Based Testing within ML Projects](https://ieeexplore.ieee.org/document/10795051/) — Empirical study examining how 58 open-source ML projects use Hypothesis for property-based testing.
- [Ploomber - Effective Testing for Machine Learning](https://ploomber.io/blog/ml-testing-i/) — Practical walkthrough of iterative test development for ML training pipelines.
- [Fuzzy Labs - The Art of Testing Machine Learning Pipelines](https://www.fuzzylabs.ai/blog-post/the-art-of-testing-machine-learning-pipelines) — Techniques for integration testing of end-to-end ML pipelines.
