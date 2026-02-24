---
name: ml-data
description: Data pipelines, feature engineering, preprocessing, and dataset management for ML workflows
---

# ML Data Engineering

ML data engineering encompasses the practices, tools, and patterns for building robust data
pipelines that feed machine learning models. This skill covers the full lifecycle of ML data:
loading raw data from diverse sources, cleaning and validating it, engineering features that
capture meaningful signals, versioning datasets for reproducibility, and serving features at
training and inference time. Production ML systems spend the majority of their complexity on
data -- getting data right is the single highest-leverage activity in any ML project.

## Table of Contents

1. Data Loading & Formats
2. Data Preprocessing
3. Feature Engineering
4. Data Validation
5. Dataset Versioning
6. PyTorch DataLoaders
7. Pandas & Polars Patterns
8. Data Augmentation
9. Feature Stores
10. Best Practices
11. Anti-Patterns

---

## 1. Data Loading & Formats

Choosing the right storage format has a direct impact on I/O throughput, memory usage, and
pipeline complexity. CSV is ubiquitous but slow and untyped. Parquet provides columnar
compression with schema enforcement and is the de facto standard for analytical ML workloads.
Arrow IPC (Feather v2) offers zero-copy reads in memory-mapped mode. For very large datasets,
consider sharded Parquet files on object storage (S3, GCS) with partition pruning.

Key considerations when selecting a data format:

- **Parquet**: Columnar, compressed, schema-embedded. Best for tabular ML data at rest.
  Supports predicate pushdown when read through engines like Polars or DuckDB.
- **Arrow IPC / Feather v2**: Fastest for local reads. Ideal for intermediate pipeline
  artifacts and inter-process data exchange.
- **CSV / TSV**: Use only for small datasets or human-readable interchange. Always specify
  dtypes explicitly to avoid silent type inference errors.
- **JSONL**: Useful for semi-structured data (NLP corpora, event logs). Parse with streaming
  readers to control memory.
- **TFRecord / WebDataset**: Optimized for sequential training reads in TensorFlow and
  PyTorch respectively. Best when data is consumed in a single pass.

```python
import polars as pl
import pandas as pd
from pathlib import Path

# --- Polars: lazy scan with predicate pushdown ---
# Only reads columns and rows that match, minimizing I/O
df_lazy = (
    pl.scan_parquet("s3://bucket/training_data/*.parquet")
    .filter(pl.col("label").is_not_null())
    .select(["user_id", "feature_1", "feature_2", "label"])
)
df = df_lazy.collect()

# --- Pandas: explicit dtypes to avoid inference issues ---
dtype_map = {
    "user_id": "int64",
    "feature_1": "float32",
    "feature_2": "float32",
    "label": "int8",
}
df_pd = pd.read_parquet(
    "data/training.parquet",
    columns=list(dtype_map.keys()),
    dtype_backend="pyarrow",  # use Arrow backend for better performance
)

# --- Writing partitioned Parquet for large datasets ---
df.write_parquet(
    "output/features/",
    use_pyarrow=True,
    pyarrow_options={"partition_cols": ["year", "month"]},
)
```

When working with remote storage, prefer scan/lazy operations that push filters down to the
storage layer. Avoid downloading entire datasets locally when you only need a subset. For
datasets exceeding available RAM, use chunked reading or streaming APIs.

---

## 2. Data Preprocessing

Data preprocessing transforms raw data into a clean, consistent format suitable for model
consumption. This stage handles missing values, encoding categorical variables, scaling
numeric features, and removing outliers. scikit-learn's Pipeline and ColumnTransformer
provide a composable, reproducible framework for these transformations.

The preprocessing pipeline should be deterministic: given the same input data and
configuration, it must always produce the same output. Fit transformers only on training
data, then apply the fitted transforms to validation and test sets. Serialize the fitted
pipeline alongside your model to ensure consistent transforms at inference time.

Common preprocessing steps:

- **Missing value imputation**: Median for numerics, mode or constant for categoricals.
  Consider whether missingness itself is informative (add a binary indicator column).
- **Scaling**: StandardScaler for normally distributed features, RobustScaler when outliers
  are present, MinMaxScaler when bounded ranges are required (e.g., neural network inputs).
- **Encoding**: OneHotEncoder for low-cardinality categoricals, OrdinalEncoder for ordinal
  variables, TargetEncoder for high-cardinality categoricals (with proper cross-validation
  to avoid leakage).
- **Outlier handling**: Clip extreme values using domain-informed thresholds rather than
  arbitrary percentiles. Log-transform heavily skewed distributions.

```python
import numpy as np
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import (
    StandardScaler,
    OneHotEncoder,
    OrdinalEncoder,
    FunctionTransformer,
)
import joblib

# Define column groups
numeric_features = ["age", "income", "transaction_count"]
categorical_features = ["city", "device_type"]
ordinal_features = ["education_level"]

# Build preprocessing sub-pipelines
numeric_pipeline = Pipeline([
    ("imputer", SimpleImputer(strategy="median")),
    ("log_transform", FunctionTransformer(np.log1p, validate=True)),
    ("scaler", StandardScaler()),
])

categorical_pipeline = Pipeline([
    ("imputer", SimpleImputer(strategy="constant", fill_value="unknown")),
    ("encoder", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
])

ordinal_pipeline = Pipeline([
    ("imputer", SimpleImputer(strategy="most_frequent")),
    ("encoder", OrdinalEncoder(
        categories=[["high_school", "bachelors", "masters", "phd"]]
    )),
])

# Compose into a single ColumnTransformer
preprocessor = ColumnTransformer(
    transformers=[
        ("num", numeric_pipeline, numeric_features),
        ("cat", categorical_pipeline, categorical_features),
        ("ord", ordinal_pipeline, ordinal_features),
    ],
    remainder="drop",  # explicitly drop unspecified columns
)

# Fit on training data only
X_train_processed = preprocessor.fit_transform(X_train)
X_val_processed = preprocessor.transform(X_val)

# Serialize for inference
joblib.dump(preprocessor, "artifacts/preprocessor.joblib")
```

When building preprocessing pipelines, always use `remainder="drop"` to make column
selection explicit. Name your transformers descriptively so that error messages and
feature name tracking are clear. Use `set_output(transform="pandas")` on scikit-learn 1.2+
to preserve column names through the pipeline.

---

## 3. Feature Engineering

Feature engineering is the process of creating new input variables from raw data that
better capture the underlying patterns a model needs to learn. Good features encode domain
knowledge and reduce the burden on the model to discover complex relationships on its own.

Categories of engineered features:

- **Temporal features**: Day of week, hour of day, time since last event, rolling
  aggregates (7-day mean, 30-day sum), exponential moving averages, cyclical encodings
  using sin/cos transforms for periodic features.
- **Interaction features**: Products or ratios of two numeric columns (e.g., price per
  unit, click-through rate). Use domain knowledge to select meaningful interactions rather
  than exhaustive polynomial expansion.
- **Aggregation features**: Group-by statistics (mean, median, std, count, min, max) at
  different entity levels (per user, per product, per session). Window functions for
  sequential data.
- **Text features**: TF-IDF, character n-grams, embedding-based features from
  sentence-transformers, token counts, text length, language detection.
- **Geospatial features**: Haversine distance between coordinates, geohash clustering,
  nearest-neighbor distances to points of interest.

```python
import polars as pl

def engineer_temporal_features(df: pl.DataFrame) -> pl.DataFrame:
    """Add temporal features derived from a timestamp column."""
    return df.with_columns([
        # Basic calendar features
        pl.col("event_time").dt.weekday().alias("day_of_week"),
        pl.col("event_time").dt.hour().alias("hour_of_day"),
        pl.col("event_time").dt.month().alias("month"),

        # Cyclical encoding for hour (captures periodicity)
        (2 * np.pi * pl.col("event_time").dt.hour() / 24)
        .sin()
        .alias("hour_sin"),
        (2 * np.pi * pl.col("event_time").dt.hour() / 24)
        .cos()
        .alias("hour_cos"),

        # Time since previous event per user (seconds)
        (pl.col("event_time") - pl.col("event_time").shift(1))
        .over("user_id")
        .dt.total_seconds()
        .alias("seconds_since_last_event"),
    ])


def engineer_aggregation_features(df: pl.DataFrame) -> pl.DataFrame:
    """Add rolling and group-level aggregation features."""
    return df.with_columns([
        # Per-user rolling 7-day transaction count
        pl.col("amount")
        .rolling_sum(window_size="7d", by="event_time")
        .over("user_id")
        .alias("user_7d_total_amount"),

        # Per-user historical mean transaction amount
        pl.col("amount")
        .mean()
        .over("user_id")
        .alias("user_mean_amount"),

        # Ratio: current transaction vs user average
        (pl.col("amount") / pl.col("amount").mean().over("user_id"))
        .alias("amount_vs_user_avg_ratio"),

        # Per-merchant transaction count
        pl.col("transaction_id")
        .count()
        .over("merchant_id")
        .alias("merchant_tx_count"),
    ])
```

When engineering features, always be vigilant about data leakage. Features must only use
information that would be available at prediction time. Use point-in-time joins for
historical aggregations and never include future data in rolling windows. Document each
feature with its business meaning, computation logic, and expected value range.

---

## 4. Data Validation

Data validation ensures that the data flowing through your pipeline meets expected quality
standards before it reaches the model. Without validation, silent data quality issues --
schema drift, distribution shift, unexpected nulls, stale data -- can degrade model
performance without any visible error.

Two leading Python tools for data validation are Pandera and Great Expectations. Pandera
is lightweight and integrates directly into code with a Pythonic API that supports type
hints. Great Expectations is a more comprehensive platform with built-in profiling, data
documentation (Data Docs), and checkpoint-based validation for pipeline orchestration.

Use Pandera when you want fast, code-native validation tightly coupled with your
DataFrame operations. Use Great Expectations when you need shared expectation suites
across teams, human-readable validation reports, and integration with orchestrators like
Airflow or Dagster.

Validation checks to implement:

- **Schema validation**: Column names, data types, nullable constraints.
- **Value constraints**: Ranges, allowed values, regex patterns for strings.
- **Statistical checks**: Mean within expected range, standard deviation bounds,
  distribution shape tests.
- **Completeness checks**: Null rates below thresholds, required fields populated.
- **Freshness checks**: Data timestamp within expected recency window.
- **Uniqueness checks**: Primary key columns have no duplicates.

```python
import pandera as pa
from pandera import Column, Check, DataFrameSchema
import pandas as pd

# Define a schema for training data validation
training_schema = DataFrameSchema(
    columns={
        "user_id": Column(
            int,
            Check.greater_than(0),
            nullable=False,
            unique=False,
        ),
        "age": Column(
            float,
            [
                Check.in_range(min_value=0, max_value=150),
                Check(lambda s: s.mean() > 18, error="Mean age suspiciously low"),
            ],
            nullable=True,  # allow nulls, imputer will handle
        ),
        "income": Column(
            float,
            [
                Check.greater_than_or_equal_to(0),
                Check(lambda s: s.std() > 0, error="Zero variance in income"),
            ],
            nullable=True,
        ),
        "city": Column(
            str,
            Check.isin(["new_york", "london", "tokyo", "berlin", "unknown"]),
            nullable=False,
        ),
        "label": Column(
            int,
            Check.isin([0, 1]),
            nullable=False,
        ),
    },
    index=pa.Index(int, name="index"),
    strict=True,  # fail on unexpected columns
    coerce=True,  # attempt type coercion before validation
)

# Validate a DataFrame -- raises SchemaError on failure
try:
    validated_df = training_schema.validate(df, lazy=True)
    print(f"Validation passed: {len(validated_df)} rows")
except pa.errors.SchemaErrors as exc:
    print(f"Validation failed with {len(exc.failure_cases)} issues:")
    print(exc.failure_cases.head(20))
    raise
```

Integrate validation at every pipeline boundary: after data ingestion, after feature
engineering, and before model training. Log validation results to your experiment tracker.
Set up alerts for validation failures in production inference pipelines so that data
quality regressions are caught before they affect users.

---

## 5. Dataset Versioning

Dataset versioning ensures that every model training run can be traced back to the exact
data it was trained on. This is critical for reproducibility, debugging model regressions,
regulatory compliance, and rolling back to known-good datasets.

DVC (Data Version Control) is the standard open-source tool for dataset versioning. It
works alongside Git: Git tracks code and pipeline definitions while DVC tracks large
data files and model artifacts stored in remote storage (S3, GCS, Azure Blob, SSH, etc.).
DVC uses content-addressable storage, so identical files are deduplicated automatically.

Core DVC workflow:

1. **Initialize**: `dvc init` in your Git repository.
2. **Track data**: `dvc add data/training.parquet` creates a `.dvc` metadata file.
3. **Push to remote**: `dvc push` uploads data to configured remote storage.
4. **Version with Git**: Commit the `.dvc` files to Git. Each Git commit now references
   a specific data version.
5. **Reproduce**: `dvc repro` re-runs the pipeline, only recomputing stages whose
   inputs have changed.
6. **Switch versions**: `git checkout <commit> && dvc checkout` restores the exact
   dataset for any historical commit.

DVC pipelines (`dvc.yaml`) define directed acyclic graphs of processing stages. Each
stage specifies its dependencies (input files, scripts, parameters) and outputs. DVC
tracks whether any dependency has changed and only re-executes affected stages, saving
compute time in iterative development.

For teams that need database-style branching and merging of datasets, consider lakeFS,
which provides a Git-like interface for object storage with atomic operations and
zero-copy branching. lakeFS acquired DVC in late 2025, signaling convergence in the
dataset versioning space.

Best practices for dataset versioning:

- Commit `.dvc` files alongside the code that generates or consumes the data.
- Use semantic tags (e.g., `dataset-v2.1.0`) for major dataset releases.
- Store data processing parameters in `params.yaml` and track with DVC for full
  reproducibility.
- Set up CI checks that run `dvc repro --dry` to verify pipeline integrity.
- Implement TTL (time-to-live) policies for intermediate artifacts to control storage
  costs.

---

## 6. PyTorch DataLoaders

PyTorch's Dataset and DataLoader abstractions provide a flexible, performant interface for
feeding data to models. The Dataset defines how to access individual samples, while the
DataLoader handles batching, shuffling, multi-process loading, and memory pinning.

For map-style datasets (random access by index), subclass `torch.utils.data.Dataset` and
implement `__len__` and `__getitem__`. For streaming datasets too large to fit in memory
or read from network sources, use `torch.utils.data.IterableDataset`.

Performance tuning guidelines:

- **num_workers**: Set to 2-4x the number of GPUs. More workers overlap CPU preprocessing
  with GPU compute. Profile to find the sweet spot -- too many workers waste memory and
  cause contention.
- **pin_memory**: Set to `True` when training on GPU. This allocates data in page-locked
  memory, enabling faster host-to-device transfers via DMA.
- **persistent_workers**: Set to `True` for multi-epoch training to avoid the overhead of
  spawning worker processes at each epoch boundary.
- **prefetch_factor**: Controls how many batches each worker pre-loads. Default is 2.
  Increase if your preprocessing is CPU-bound and GPU is starving for data.
- **Collate functions**: Custom `collate_fn` for variable-length sequences (padding),
  nested data structures, or multi-modal batches.

```python
import torch
from torch.utils.data import Dataset, DataLoader
from pathlib import Path
import numpy as np

class TabularDataset(Dataset):
    """Memory-mapped dataset for large tabular data stored as .npy files."""

    def __init__(self, features_path: str, labels_path: str):
        # Memory-map for zero-copy reads -- data stays on disk until accessed
        self.features = np.load(features_path, mmap_mode="r")
        self.labels = np.load(labels_path, mmap_mode="r")
        assert len(self.features) == len(self.labels)

    def __len__(self) -> int:
        return len(self.labels)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        features = torch.from_numpy(self.features[idx].copy()).float()
        label = torch.tensor(self.labels[idx], dtype=torch.long)
        return features, label


class TextClassificationDataset(Dataset):
    """Dataset with on-the-fly tokenization for text classification."""

    def __init__(self, texts: list[str], labels: list[int], tokenizer, max_length: int = 512):
        self.texts = texts
        self.labels = labels
        self.tokenizer = tokenizer
        self.max_length = max_length

    def __len__(self) -> int:
        return len(self.texts)

    def __getitem__(self, idx: int) -> dict:
        encoding = self.tokenizer(
            self.texts[idx],
            truncation=True,
            max_length=self.max_length,
            padding="max_length",
            return_tensors="pt",
        )
        return {
            "input_ids": encoding["input_ids"].squeeze(0),
            "attention_mask": encoding["attention_mask"].squeeze(0),
            "label": torch.tensor(self.labels[idx], dtype=torch.long),
        }


def create_dataloader(
    dataset: Dataset,
    batch_size: int = 64,
    shuffle: bool = True,
    num_workers: int = 4,
) -> DataLoader:
    """Create an optimized DataLoader with production settings."""
    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=shuffle,
        num_workers=num_workers,
        pin_memory=torch.cuda.is_available(),
        persistent_workers=num_workers > 0,
        prefetch_factor=2 if num_workers > 0 else None,
        drop_last=shuffle,  # drop incomplete last batch during training
    )


# Usage
if __name__ == "__main__":
    train_dataset = TabularDataset("data/train_features.npy", "data/train_labels.npy")
    train_loader = create_dataloader(train_dataset, batch_size=256, shuffle=True)

    for batch_features, batch_labels in train_loader:
        if torch.cuda.is_available():
            batch_features = batch_features.cuda(non_blocking=True)
            batch_labels = batch_labels.cuda(non_blocking=True)
        # ... training step
```

Always wrap DataLoader creation and training loops inside `if __name__ == "__main__":`
on platforms that use spawn-based multiprocessing (Windows, macOS). Place custom
`collate_fn` and `worker_init_fn` at module-level scope so they can be pickled by worker
processes.

---

## 7. Pandas & Polars Patterns

Pandas and Polars are the two dominant DataFrame libraries for ML data work. Pandas has
the larger ecosystem and deeper integration with scikit-learn and visualization libraries.
Polars offers dramatically better performance through lazy evaluation, multi-threaded
execution, and Apache Arrow memory layout.

Performance characteristics based on 2025 benchmarks:

- Polars reads CSV files roughly 5x faster than Pandas.
- Group-by aggregations run 5-10x faster in Polars due to parallel hash-based execution.
- Sorting is up to 11x faster in Polars.
- Polars uses approximately 87% less peak memory for common operations.

For production ML pipelines, a hybrid approach works well: use Polars for heavy
preprocessing and aggregation, then convert to Pandas for scikit-learn or visualization
steps where Pandas integration is required. The conversion between the two is lightweight
since both can share Apache Arrow buffers.

Key Polars patterns for ML data work:

- **Lazy evaluation**: Use `scan_parquet` / `scan_csv` and chain operations before calling
  `.collect()`. The query optimizer will apply predicate pushdown, projection pushdown,
  and operation fusion automatically.
- **Expression API**: Polars expressions are composable and parallelized. Prefer expressions
  over `apply` / `map_elements` which fall back to slow Python execution.
- **Window functions**: Use `.over()` for grouped operations without materializing groups.
- **Struct columns**: Pack related features into struct columns for cleaner schemas.

Key Pandas patterns for ML data work:

- **PyArrow backend**: Use `dtype_backend="pyarrow"` when reading data for better
  performance and nullable type support.
- **Categorical dtype**: Convert low-cardinality string columns to `category` to reduce
  memory by 90%+ and speed up group-by operations.
- **Vectorized operations**: Always prefer vectorized NumPy/Pandas operations over
  iterating with `iterrows()` or `apply()`. Use `.to_numpy()` for bulk operations.

---

## 8. Data Augmentation

Data augmentation artificially expands training data by applying label-preserving
transformations. This reduces overfitting, improves generalization, and is especially
valuable when labeled data is scarce. Augmentation strategies vary by data modality.

**Image augmentation** (using torchvision or albumentations):

- Geometric: random crop, horizontal/vertical flip, rotation, affine transforms.
- Photometric: brightness, contrast, saturation, hue jitter, Gaussian blur.
- Advanced: CutOut, MixUp, CutMix, RandAugment, AugMax.
- Always apply augmentation during training only, not during validation or inference.
- Use albumentations for faster augmentation with a wider operation set.

**Text augmentation**:

- Synonym replacement using WordNet or contextual embeddings.
- Random insertion, deletion, or swap of words (EDA technique).
- Back-translation: translate to another language and back.
- Paraphrase generation using LLMs for high-quality augmentation.
- Character-level noise injection for robustness to typos.

**Tabular augmentation**:

- SMOTE (Synthetic Minority Over-sampling Technique) for imbalanced classification.
- Feature-space noise injection: add Gaussian noise to continuous features.
- Mixup: linear interpolation between pairs of training examples and their labels.
- Conditional generation using CTGAN or TVAE for synthetic tabular data.

**Audio augmentation**:

- Time stretching, pitch shifting, and speed perturbation.
- Adding background noise from noise corpora (SpecAugment for spectrograms).
- Random volume adjustment and reverb simulation.

When implementing augmentation:

- Apply augmentation stochastically during training -- each epoch sees different
  augmented versions of the same sample.
- Tune augmentation intensity: too aggressive augmentation can distort the signal.
- For tabular data, augmentation is less standard -- validate that synthetic samples
  preserve the underlying data distribution.

---

## 9. Feature Stores

A feature store is a centralized repository that manages the lifecycle of ML features:
definition, computation, storage, versioning, and serving. Feature stores solve the
feature consistency problem -- ensuring that the same feature computation logic is used
in both training (batch, historical) and inference (real-time, low-latency) contexts.

Core components of a feature store:

- **Feature registry**: Metadata catalog of all features with descriptions, owners,
  data types, freshness SLAs, and lineage.
- **Offline store**: Historical feature values for training. Typically backed by a
  data warehouse (BigQuery, Snowflake, Redshift) or object storage (Parquet on S3).
- **Online store**: Low-latency feature serving for real-time inference. Backed by
  key-value stores (Redis, DynamoDB, Bigtable).
- **Feature computation engine**: Batch (Spark, Polars) and streaming (Flink, Kafka
  Streams) pipelines that compute and materialize features.
- **Point-in-time joins**: Correctly join features to training labels using event
  timestamps to prevent data leakage from the future.

Popular feature store options in 2025:

- **Feast**: Open-source, lightweight, supports multiple backends. Good for teams
  getting started with feature stores.
- **Tecton**: Managed feature platform built on Feast foundations. Supports real-time
  feature computation and streaming features.
- **Hopsworks**: Open-source platform with integrated feature store, model registry,
  and experiment tracking.
- **Databricks Feature Store**: Integrated with Unity Catalog for teams on the
  Databricks platform.
- **Vertex AI Feature Store**: Google Cloud managed service with BigQuery integration.

When evaluating feature stores, prioritize: point-in-time correctness for training data,
online serving latency for your inference SLA, integration with your existing data
infrastructure, and the operational burden of running the system. Many teams start with
a simple Parquet-based offline store and a Redis-based online store before adopting a
full-featured platform.

---

## 10. Best Practices

These best practices reflect current production ML data engineering patterns as of 2025.

**Data Quality First**

- Treat data quality as a first-class concern, not an afterthought. No model architecture
  can compensate for systematically flawed data.
- Implement automated data validation at every pipeline boundary using tools like Pandera
  or Great Expectations.
- Monitor data distributions in production and alert on drift before it degrades model
  performance.
- Define data contracts between data producers and ML consumers specifying schema,
  freshness, and quality SLAs.

**Reproducibility**

- Version datasets alongside code using DVC or lakeFS. Every experiment should be fully
  reproducible from a single Git commit.
- Pin all library versions in your environment (use lock files). Feature computation can
  change subtly across library versions.
- Log data statistics (row count, feature distributions, null rates) as experiment
  metadata for every training run.
- Use deterministic seeds for any randomized operations (shuffling, augmentation, splits).

**Pipeline Design**

- Build idempotent pipelines: re-running a pipeline on the same input should produce
  identical output without side effects.
- Separate data extraction, transformation, and loading into distinct pipeline stages
  with clear interfaces.
- Use schema-on-read with explicit type casting rather than relying on automatic type
  inference.
- Implement graceful failure handling: validate inputs, catch exceptions, log errors
  with context, and fail fast on unrecoverable issues.

**Performance**

- Profile your data pipeline before optimizing. Identify whether the bottleneck is I/O,
  CPU preprocessing, or memory.
- Use columnar formats (Parquet, Arrow) and read only the columns you need.
- Prefer Polars over Pandas for preprocessing steps on datasets exceeding 1 million rows.
- For PyTorch training, benchmark DataLoader configurations (num_workers, pin_memory,
  prefetch_factor) on your specific hardware.
- Cache intermediate results when pipeline stages are expensive and inputs change
  infrequently.

**Feature Engineering**

- Document every feature: what it represents, how it is computed, expected value range,
  and known failure modes.
- Guard against data leakage by using only information available at prediction time.
- Prefer simple, interpretable features over complex ones unless the complexity is
  justified by measurable model improvement.
- Implement feature importance monitoring to detect when engineered features lose their
  predictive signal over time.

**Security and Privacy**

- Never store raw PII in feature stores or training datasets. Apply tokenization, hashing,
  or differential privacy as appropriate.
- Implement role-based access control for sensitive datasets.
- Maintain audit logs for data access, especially for datasets subject to regulatory
  requirements (GDPR, HIPAA, CCPA).

---

## 11. Anti-Patterns

These are common mistakes in ML data engineering that lead to bugs, degraded model
performance, and operational pain.

**Data Leakage**

- Using future information in feature computation (e.g., aggregating over the full
  time series instead of using only historical data at the point of prediction).
- Fitting preprocessors (scalers, encoders, imputers) on the full dataset including
  test data. Always fit on training data only.
- Including the target variable or a proxy for it as an input feature.
- Using global statistics (dataset mean) instead of per-fold or per-split statistics
  in cross-validation.

**Silent Data Corruption**

- Not validating data at pipeline boundaries, allowing schema changes, type drift,
  or distribution shift to propagate undetected.
- Relying on automatic type inference for CSV files (a column of "1", "2", "NA"
  gets inferred as strings instead of nullable integers).
- Ignoring pandas SettingWithCopyWarning -- this often indicates unintended mutation
  of underlying data.
- Using `inplace=True` in pandas, which makes debugging harder and has no performance
  benefit.

**Performance Anti-Patterns**

- Iterating over DataFrame rows with `iterrows()` or `apply()` instead of using
  vectorized operations. This can be 100-1000x slower.
- Loading entire datasets into memory when only a subset is needed. Use lazy
  evaluation (Polars) or chunked reading (Pandas).
- Setting `num_workers=0` in PyTorch DataLoader during training, leaving GPUs idle
  while data loads on the main process.
- Creating new DataFrame copies in every transformation step instead of chaining
  operations.
- Not using categorical dtypes for low-cardinality string columns, wasting memory
  and slowing group-by operations.

**Pipeline Anti-Patterns**

- Hardcoding file paths, column names, and hyperparameters instead of using
  configuration files.
- Writing monolithic preprocessing scripts instead of composable, testable pipeline
  stages.
- Not version-controlling datasets, making it impossible to reproduce past experiments
  or diagnose model regressions.
- Running preprocessing differently in training and inference (training-serving skew).
  Always use the same serialized pipeline for both.
- Skipping unit tests for feature engineering functions. Treat data transforms as
  production code with proper test coverage.

**Feature Engineering Anti-Patterns**

- Exhaustive polynomial feature expansion without domain justification, creating
  thousands of noise features that increase training time and overfitting risk.
- Not handling rare categories in categorical features, leading to unseen values at
  inference time.
- Computing features that require information from the serving context that will not
  be available in production (e.g., features based on batch statistics).
- Ignoring feature correlation -- highly correlated features add redundancy without
  improving model performance and can destabilize linear models.
- Not monitoring feature distributions in production, missing when a feature pipeline
  breaks or upstream data changes meaning.

---

## Sources & References

- Pandas documentation: https://pandas.pydata.org/docs/
- Polars documentation: https://docs.pola.rs/
- PyTorch Data utilities documentation: https://pytorch.org/docs/stable/data.html
- DVC (Data Version Control) documentation: https://dvc.org/doc
- Great Expectations documentation: https://docs.greatexpectations.io/docs/
- Pandera documentation: https://pandera.readthedocs.io/en/stable/
- Feast feature store documentation: https://docs.feast.dev/
- scikit-learn Pipeline and ColumnTransformer: https://scikit-learn.org/stable/modules/compose.html
- Albumentations image augmentation library: https://albumentations.ai/docs/
- lakeFS data versioning platform: https://lakefs.io/
