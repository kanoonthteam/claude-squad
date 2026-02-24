---
name: ml-modeling
description: ML model training, evaluation, experiment tracking, and hyperparameter tuning with PyTorch, scikit-learn, and Hugging Face
---

# ML Modeling

This skill covers the full lifecycle of machine learning model development, from architecture
selection and training loop implementation through evaluation, experiment tracking, and model
versioning. It provides production-grade patterns for PyTorch, scikit-learn, and Hugging Face
Transformers, along with integration guidance for MLflow, Weights & Biases, and Optuna. The
focus is on reproducible, scalable, and maintainable ML workflows suitable for both research
prototyping and production deployment.

## Table of Contents

1. Model Architecture Patterns
2. Training Loops
3. Loss Functions & Optimizers
4. Hyperparameter Tuning
5. Experiment Tracking
6. Model Evaluation
7. Transfer Learning & Fine-Tuning
8. Distributed Training
9. Model Registry & Versioning
10. Best Practices
11. Anti-Patterns
12. Sources & References

---

## 1. Model Architecture Patterns

When designing model architectures, separate concerns into reusable modules. Each component
should handle a single responsibility: feature extraction, transformation, or prediction. This
makes architectures composable, testable, and easier to modify during experimentation.

For PyTorch models, always inherit from `nn.Module` and implement the `forward` method. Use
`nn.Sequential` for linear stacks and custom modules for branching or residual architectures.
Register all learnable parameters through `nn.Parameter` or submodules so that `.parameters()`
and `.state_dict()` work correctly.

For scikit-learn workflows, use `Pipeline` and `ColumnTransformer` to compose preprocessing
steps with estimators into a single reproducible unit. This prevents data leakage during
cross-validation and simplifies deployment by serializing the entire pipeline as one artifact.

```python
import torch
import torch.nn as nn

class ResidualBlock(nn.Module):
    """A standard residual block with skip connection."""

    def __init__(self, in_channels: int, out_channels: int, stride: int = 1):
        super().__init__()
        self.conv1 = nn.Conv2d(in_channels, out_channels, 3, stride=stride, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(out_channels)
        self.conv2 = nn.Conv2d(out_channels, out_channels, 3, stride=1, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(out_channels)
        self.relu = nn.ReLU(inplace=True)

        self.shortcut = nn.Sequential()
        if stride != 1 or in_channels != out_channels:
            self.shortcut = nn.Sequential(
                nn.Conv2d(in_channels, out_channels, 1, stride=stride, bias=False),
                nn.BatchNorm2d(out_channels),
            )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        residual = self.shortcut(x)
        out = self.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        out += residual
        return self.relu(out)


class ImageClassifier(nn.Module):
    """Composable classifier using residual blocks."""

    def __init__(self, num_classes: int = 10):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(3, 64, 3, padding=1, bias=False),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            ResidualBlock(64, 128, stride=2),
            ResidualBlock(128, 256, stride=2),
            nn.AdaptiveAvgPool2d((1, 1)),
        )
        self.classifier = nn.Linear(256, num_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.features(x)
        x = x.view(x.size(0), -1)
        return self.classifier(x)
```

For scikit-learn, always wrap preprocessing and modeling into a single `Pipeline` object.
Use `ColumnTransformer` to apply different transformations to numerical and categorical
features. This approach prevents data leakage during cross-validation, since fitting only
happens on training folds.

```python
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.impute import SimpleImputer
from sklearn.ensemble import GradientBoostingClassifier

numeric_features = ["age", "income", "credit_score"]
categorical_features = ["occupation", "region", "education"]

numeric_transformer = Pipeline(steps=[
    ("imputer", SimpleImputer(strategy="median")),
    ("scaler", StandardScaler()),
])

categorical_transformer = Pipeline(steps=[
    ("imputer", SimpleImputer(strategy="most_frequent")),
    ("encoder", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
])

preprocessor = ColumnTransformer(transformers=[
    ("num", numeric_transformer, numeric_features),
    ("cat", categorical_transformer, categorical_features),
])

model_pipeline = Pipeline(steps=[
    ("preprocessor", preprocessor),
    ("classifier", GradientBoostingClassifier(
        n_estimators=200,
        learning_rate=0.1,
        max_depth=5,
        random_state=42,
    )),
])

# Fit and predict in one call; preprocessing is applied correctly
model_pipeline.fit(X_train, y_train)
predictions = model_pipeline.predict(X_test)
```

---

## 2. Training Loops

A well-structured PyTorch training loop separates data loading, forward pass, loss computation,
backward pass, and optimizer step into clearly delineated phases. Use `torch.amp` (automatic
mixed precision) to reduce memory usage and accelerate training on modern GPUs. Always call
`model.train()` before training and `model.eval()` before evaluation to toggle dropout and
batch normalization behavior.

Gradient accumulation allows simulating larger batch sizes when GPU memory is limited. Accumulate
gradients across multiple micro-batches before calling `optimizer.step()`. This is critical for
training large models on consumer hardware.

Checkpoint regularly and save both model state and optimizer state so that training can resume
from any point. Include the epoch number, global step, and validation metric in the checkpoint
to enable proper restoration.

```python
import torch
import torch.nn as nn
from torch.amp import GradScaler, autocast
from torch.utils.data import DataLoader

def train_one_epoch(
    model: nn.Module,
    dataloader: DataLoader,
    optimizer: torch.optim.Optimizer,
    scheduler: torch.optim.lr_scheduler.LRScheduler,
    device: torch.device,
    accumulation_steps: int = 4,
) -> dict:
    model.train()
    scaler = GradScaler("cuda")
    total_loss = 0.0
    num_batches = 0

    optimizer.zero_grad()

    for step, (inputs, targets) in enumerate(dataloader):
        inputs = inputs.to(device, non_blocking=True)
        targets = targets.to(device, non_blocking=True)

        with autocast("cuda"):
            outputs = model(inputs)
            loss = nn.functional.cross_entropy(outputs, targets)
            loss = loss / accumulation_steps

        scaler.scale(loss).backward()

        if (step + 1) % accumulation_steps == 0:
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            scaler.step(optimizer)
            scaler.update()
            optimizer.zero_grad()
            scheduler.step()

        total_loss += loss.item() * accumulation_steps
        num_batches += 1

    return {"train_loss": total_loss / num_batches}


@torch.no_grad()
def evaluate(
    model: nn.Module,
    dataloader: DataLoader,
    device: torch.device,
) -> dict:
    model.eval()
    total_loss = 0.0
    correct = 0
    total = 0

    for inputs, targets in dataloader:
        inputs = inputs.to(device, non_blocking=True)
        targets = targets.to(device, non_blocking=True)

        with autocast("cuda"):
            outputs = model(inputs)
            loss = nn.functional.cross_entropy(outputs, targets)

        total_loss += loss.item()
        preds = outputs.argmax(dim=1)
        correct += (preds == targets).sum().item()
        total += targets.size(0)

    return {
        "val_loss": total_loss / len(dataloader),
        "val_accuracy": correct / total,
    }


def save_checkpoint(model, optimizer, scheduler, epoch, step, metric, path):
    torch.save({
        "epoch": epoch,
        "global_step": step,
        "model_state_dict": model.state_dict(),
        "optimizer_state_dict": optimizer.state_dict(),
        "scheduler_state_dict": scheduler.state_dict(),
        "val_metric": metric,
    }, path)
```

---

## 3. Loss Functions & Optimizers

Choosing the right loss function and optimizer is critical for model convergence. For
classification tasks, `CrossEntropyLoss` combines `LogSoftmax` and `NLLLoss` and expects raw
logits. For regression, `MSELoss` or `L1Loss` are standard choices. For imbalanced datasets,
use `class_weight` in scikit-learn or `weight` tensors in PyTorch loss functions.

AdamW is the default optimizer for most deep learning tasks in 2025. It decouples weight decay
from the gradient update, which produces better generalization than the original Adam. For
learning rate scheduling, cosine annealing with warmup is the standard approach for transformer
models and large-scale training.

Set weight decay to 0.01-0.1 for most tasks. Exclude bias terms and layer normalization
parameters from weight decay, as regularizing these can hurt performance. Use gradient clipping
(max norm of 1.0) to prevent exploding gradients, especially in recurrent and transformer
architectures.

Key optimizer configuration guidelines:

- **AdamW**: Default choice. Use `lr=1e-3` to `5e-5` depending on model size. Set `betas=(0.9, 0.999)` and `eps=1e-8`.
- **SGD with momentum**: Preferred for CNNs in some benchmarks. Use `lr=0.1`, `momentum=0.9`, with step or cosine decay.
- **Learning rate warmup**: Linearly increase learning rate from 0 to target over the first 5-10% of training steps to stabilize early training dynamics.
- **Cosine annealing**: After warmup, decay learning rate following a cosine curve to a small minimum value (e.g., `1e-6`).
- **Label smoothing**: Set `label_smoothing=0.1` in `CrossEntropyLoss` to improve generalization and reduce overconfidence in predictions.

---

## 4. Hyperparameter Tuning

Optuna provides Bayesian optimization for hyperparameter search with built-in pruning of
unpromising trials. Define an objective function that takes a `trial` object, samples
hyperparameters using `trial.suggest_*` methods, trains the model, and returns the metric
to optimize. Optuna automatically learns which regions of the hyperparameter space are most
promising and focuses sampling there.

Use `MedianPruner` to stop trials early if their intermediate performance falls below the
median of completed trials. This can reduce total computation by 50-80% compared to exhaustive
search. For multi-objective optimization, Optuna supports Pareto-optimal solutions through
`create_study(directions=["minimize", "maximize"])`.

Always persist the Optuna study to a database backend (SQLite or PostgreSQL) so that tuning
runs can be resumed after interruption and results can be shared across team members.

```python
import optuna
from optuna.pruners import MedianPruner
from optuna.samplers import TPESampler

def objective(trial: optuna.Trial) -> float:
    # Sample hyperparameters
    lr = trial.suggest_float("lr", 1e-5, 1e-2, log=True)
    weight_decay = trial.suggest_float("weight_decay", 1e-6, 1e-2, log=True)
    num_layers = trial.suggest_int("num_layers", 2, 6)
    hidden_dim = trial.suggest_categorical("hidden_dim", [128, 256, 512, 1024])
    dropout = trial.suggest_float("dropout", 0.0, 0.5)
    batch_size = trial.suggest_categorical("batch_size", [16, 32, 64, 128])

    # Build model with sampled hyperparameters
    model = build_model(num_layers=num_layers, hidden_dim=hidden_dim, dropout=dropout)
    model = model.to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)

    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size)

    # Train with pruning support
    for epoch in range(max_epochs):
        train_one_epoch(model, train_loader, optimizer, scheduler, device)
        metrics = evaluate(model, val_loader, device)

        # Report intermediate value for pruning
        trial.report(metrics["val_loss"], epoch)
        if trial.should_prune():
            raise optuna.TrialPruned()

    return metrics["val_loss"]


# Create study with TPE sampler and median pruner
study = optuna.create_study(
    study_name="model-hparam-search",
    storage="sqlite:///optuna_studies.db",
    sampler=TPESampler(seed=42),
    pruner=MedianPruner(n_startup_trials=5, n_warmup_steps=3),
    direction="minimize",
    load_if_exists=True,
)

study.optimize(objective, n_trials=100, timeout=3600)

# Retrieve the best trial
best = study.best_trial
print(f"Best val_loss: {best.value:.4f}")
print(f"Best params: {best.params}")
```

---

## 5. Experiment Tracking

Experiment tracking is essential for reproducibility and team collaboration. Every training
run should log its hyperparameters, metrics at each step, system information, and output
artifacts. Use MLflow or Weights & Biases as the tracking backend depending on team preference
and infrastructure.

### MLflow

MLflow provides a lightweight, open-source experiment tracking server that stores parameters,
metrics, and artifacts. Use `mlflow.autolog()` for automatic logging with supported frameworks
(PyTorch, scikit-learn, Hugging Face). For production, deploy the tracking server with a
PostgreSQL backend and S3/GCS artifact storage.

```python
import mlflow
import mlflow.pytorch

# Configure tracking server
mlflow.set_tracking_uri("http://mlflow-server:5000")
mlflow.set_experiment("image-classification-v2")

# Enable autologging for PyTorch
mlflow.pytorch.autolog(log_every_n_epoch=1)

with mlflow.start_run(run_name="resnet-baseline") as run:
    # Log hyperparameters
    mlflow.log_params({
        "learning_rate": 1e-3,
        "batch_size": 64,
        "epochs": 50,
        "optimizer": "AdamW",
        "architecture": "ResNet-50",
        "weight_decay": 0.01,
    })

    # Training loop
    for epoch in range(num_epochs):
        train_metrics = train_one_epoch(model, train_loader, optimizer, scheduler, device)
        val_metrics = evaluate(model, val_loader, device)

        # Log metrics per epoch
        mlflow.log_metrics({
            "train_loss": train_metrics["train_loss"],
            "val_loss": val_metrics["val_loss"],
            "val_accuracy": val_metrics["val_accuracy"],
        }, step=epoch)

    # Log the trained model as an artifact
    mlflow.pytorch.log_model(model, "model")

    # Log additional artifacts
    mlflow.log_artifact("configs/training_config.yaml")
    mlflow.log_artifact("reports/confusion_matrix.png")

    # Register model in the model registry
    model_uri = f"runs:/{run.info.run_id}/model"
    mlflow.register_model(model_uri, "image-classifier")
```

### Weights & Biases

W&B provides richer visualization, collaborative dashboards, and built-in sweep support for
hyperparameter tuning. Use `wandb.watch()` to log gradient histograms and `wandb.Table()` to
log structured prediction data for detailed error analysis.

```python
import wandb

wandb.init(
    project="image-classification",
    name="resnet-baseline",
    config={
        "learning_rate": 1e-3,
        "batch_size": 64,
        "epochs": 50,
        "optimizer": "AdamW",
        "architecture": "ResNet-50",
    },
    tags=["baseline", "resnet"],
)

# Watch model gradients and parameters
wandb.watch(model, log="all", log_freq=100)

for epoch in range(num_epochs):
    train_metrics = train_one_epoch(model, train_loader, optimizer, scheduler, device)
    val_metrics = evaluate(model, val_loader, device)

    wandb.log({
        "epoch": epoch,
        "train/loss": train_metrics["train_loss"],
        "val/loss": val_metrics["val_loss"],
        "val/accuracy": val_metrics["val_accuracy"],
        "lr": scheduler.get_last_lr()[0],
    })

# Log prediction table for error analysis
columns = ["image", "true_label", "predicted_label", "confidence"]
table = wandb.Table(columns=columns)
for img, true, pred, conf in sample_predictions:
    table.add_data(wandb.Image(img), true, pred, conf)
wandb.log({"predictions": table})

# Save model artifact
artifact = wandb.Artifact("trained-model", type="model")
artifact.add_file("checkpoints/best_model.pt")
wandb.log_artifact(artifact)

wandb.finish()
```

---

## 6. Model Evaluation

Evaluation must go beyond a single aggregate metric. Use multiple complementary metrics and
visualizations to understand model behavior across different data segments. For classification,
track precision, recall, F1, ROC-AUC, and confusion matrices. For regression, use RMSE, MAE,
R-squared, and residual plots.

Stratified evaluation across subgroups reveals performance disparities that aggregate metrics
hide. Split evaluation results by demographic attributes, data sources, or difficulty levels
to identify failure modes before deployment.

Key evaluation principles:

- **Hold-out test set**: Never use the test set for hyperparameter tuning or model selection. Reserve it for final evaluation only.
- **Cross-validation**: Use stratified k-fold (k=5 or k=10) during development to get robust performance estimates.
- **Confidence intervals**: Report bootstrap confidence intervals for all metrics to quantify statistical uncertainty.
- **Calibration**: For probabilistic predictions, evaluate calibration with reliability diagrams and the Brier score. Well-calibrated models produce probability estimates that match observed frequencies.
- **Error analysis**: Manually inspect misclassified or high-error samples to identify systematic failure patterns that metrics alone miss.
- **Threshold tuning**: For binary classifiers, optimize the decision threshold on the validation set using precision-recall tradeoff analysis rather than defaulting to 0.5.

For scikit-learn, use `cross_val_score` with appropriate scoring functions and `classification_report`
for per-class breakdowns. For PyTorch, implement evaluation as a separate function with
`@torch.no_grad()` and `model.eval()` to disable gradient computation and training-specific
layers.

---

## 7. Transfer Learning & Fine-Tuning

Transfer learning leverages pretrained model weights to achieve strong performance with limited
domain-specific data. The standard approach is to load a pretrained backbone, freeze its
parameters, replace the classification head, and fine-tune progressively by unfreezing layers
from the top down.

For Hugging Face Transformers, the `Trainer` API abstracts away the training loop and provides
built-in support for mixed precision, gradient accumulation, distributed training, and
evaluation. Use `TrainingArguments` to configure all aspects of training without modifying
the loop itself.

```python
from transformers import (
    AutoModelForSequenceClassification,
    AutoTokenizer,
    TrainingArguments,
    Trainer,
)
from datasets import load_dataset
import numpy as np
from sklearn.metrics import accuracy_score, f1_score

# Load pretrained model and tokenizer
model_name = "microsoft/deberta-v3-base"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForSequenceClassification.from_pretrained(
    model_name,
    num_labels=3,
    problem_type="single_label_classification",
)

# Load and tokenize dataset
dataset = load_dataset("glue", "mnli")

def tokenize_fn(examples):
    return tokenizer(
        examples["premise"],
        examples["hypothesis"],
        truncation=True,
        max_length=256,
        padding="max_length",
    )

tokenized = dataset.map(tokenize_fn, batched=True, remove_columns=dataset["train"].column_names)
tokenized = tokenized.rename_column("label", "labels")
tokenized.set_format("torch")

# Define metrics
def compute_metrics(eval_pred):
    logits, labels = eval_pred
    preds = np.argmax(logits, axis=-1)
    return {
        "accuracy": accuracy_score(labels, preds),
        "f1_macro": f1_score(labels, preds, average="macro"),
        "f1_weighted": f1_score(labels, preds, average="weighted"),
    }

# Configure training
training_args = TrainingArguments(
    output_dir="./results/deberta-mnli",
    num_train_epochs=3,
    per_device_train_batch_size=16,
    per_device_eval_batch_size=32,
    gradient_accumulation_steps=2,
    learning_rate=2e-5,
    weight_decay=0.01,
    warmup_ratio=0.06,
    lr_scheduler_type="cosine",
    fp16=True,
    eval_strategy="steps",
    eval_steps=500,
    save_strategy="steps",
    save_steps=500,
    save_total_limit=3,
    load_best_model_at_end=True,
    metric_for_best_model="f1_macro",
    greater_is_better=True,
    logging_steps=50,
    report_to=["mlflow", "wandb"],
    dataloader_num_workers=4,
    dataloader_pin_memory=True,
)

# Initialize trainer and train
trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=tokenized["train"],
    eval_dataset=tokenized["validation_matched"],
    compute_metrics=compute_metrics,
)

trainer.train()
trainer.save_model("./final_model/deberta-mnli")
tokenizer.save_pretrained("./final_model/deberta-mnli")
```

Progressive unfreezing strategy for PyTorch transfer learning:

- **Phase 1**: Freeze the entire backbone. Train only the new classification head for 2-5 epochs with a higher learning rate (e.g., `1e-3`).
- **Phase 2**: Unfreeze the top 25-50% of backbone layers. Train with a lower learning rate (e.g., `1e-4`) and discriminative learning rates (lower layers get smaller rates).
- **Phase 3**: Optionally unfreeze all layers and fine-tune end-to-end with a very small learning rate (e.g., `1e-5`).

---

## 8. Distributed Training

PyTorch Distributed Data Parallel (DDP) is the standard approach for multi-GPU training. DDP
replicates the model on each GPU, partitions the data across processes using `DistributedSampler`,
and synchronizes gradients via all-reduce after each backward pass. Spawn one process per GPU
for optimal performance.

Key DDP configuration requirements:

- **Process group initialization**: Use `torch.distributed.init_process_group(backend="nccl")` for GPU training. NCCL is optimized for NVIDIA GPU communication.
- **DistributedSampler**: Wrap your dataset with `DistributedSampler` and set `shuffle=False` in the `DataLoader` (the sampler handles shuffling). Call `sampler.set_epoch(epoch)` at the start of each epoch to ensure proper shuffling.
- **Model wrapping**: Wrap your model with `DistributedDataParallel(model, device_ids=[local_rank])` after moving it to the correct device.
- **Gradient accumulation**: Use `model.no_sync()` context manager during accumulation steps to skip gradient synchronization, then synchronize on the final step.
- **Checkpointing**: Save checkpoints only on rank 0 to avoid file corruption. Use `torch.distributed.barrier()` to synchronize before loading checkpoints on other ranks.
- **SyncBatchNorm**: Convert `BatchNorm` layers to `SyncBatchNorm` with `nn.SyncBatchNorm.convert_sync_batchnorm(model)` to synchronize batch statistics across GPUs.

For models too large to fit on a single GPU, use Fully Sharded Data Parallel (FSDP), which
shards model parameters, gradients, and optimizer states across GPUs. FSDP reduces per-GPU
memory usage proportionally to the number of GPUs, enabling training of models that would
otherwise require model parallelism.

```python
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import DataLoader, DistributedSampler

def setup_ddp(rank: int, world_size: int):
    """Initialize DDP process group."""
    dist.init_process_group(
        backend="nccl",
        init_method="env://",
        rank=rank,
        world_size=world_size,
    )
    torch.cuda.set_device(rank)

def cleanup_ddp():
    dist.destroy_process_group()

def train_ddp(rank: int, world_size: int, config: dict):
    setup_ddp(rank, world_size)
    device = torch.device(f"cuda:{rank}")

    # Build model and wrap with DDP
    model = ImageClassifier(num_classes=config["num_classes"]).to(device)
    model = nn.SyncBatchNorm.convert_sync_batchnorm(model)
    model = DDP(model, device_ids=[rank])

    optimizer = torch.optim.AdamW(model.parameters(), lr=config["lr"])

    # Create distributed data loader
    sampler = DistributedSampler(train_dataset, num_replicas=world_size, rank=rank)
    train_loader = DataLoader(
        train_dataset,
        batch_size=config["batch_size"],
        sampler=sampler,
        num_workers=4,
        pin_memory=True,
        shuffle=False,  # Sampler handles shuffling
    )

    for epoch in range(config["epochs"]):
        sampler.set_epoch(epoch)  # Ensure proper shuffling each epoch
        train_one_epoch(model, train_loader, optimizer, scheduler, device)

        # Evaluate and checkpoint on rank 0 only
        if rank == 0:
            val_metrics = evaluate(model.module, val_loader, device)
            save_checkpoint(model.module, optimizer, scheduler, epoch, 0, val_metrics, "checkpoint.pt")

        dist.barrier()  # Synchronize all processes

    cleanup_ddp()


# Launch with torchrun:
# torchrun --nproc_per_node=4 train.py
```

---

## 9. Model Registry & Versioning

A model registry provides a centralized store for managing model versions, tracking lineage
from experiment to deployment, and enforcing promotion workflows. MLflow Model Registry is
the most widely adopted open-source solution and integrates tightly with the tracking server.

Key model registry practices:

- **Semantic versioning**: Tag models with stage labels (Staging, Production, Archived) rather than version numbers alone to clarify deployment status.
- **Lineage tracking**: Every registered model should link back to its training run, dataset version, and code commit hash for full reproducibility.
- **Transition gates**: Require passing validation tests (accuracy thresholds, latency benchmarks, bias checks) before a model can transition from Staging to Production.
- **Artifact storage**: Store model artifacts in object storage (S3, GCS) with the registry holding only metadata and pointers. This scales to large models without bloating the registry database.
- **Model signatures**: Define input/output schemas with MLflow model signatures to catch data type mismatches early during inference.
- **A/B testing metadata**: Track traffic allocation percentages and comparison metrics for models serving simultaneously in production.

Use `mlflow.register_model()` after a successful training run and `mlflow.pyfunc.load_model()`
to load models in a framework-agnostic way for inference. The PyFunc interface provides a
uniform prediction API regardless of whether the underlying model is PyTorch, scikit-learn,
or a custom implementation.

---

## 10. Best Practices

### Reproducibility

- **Set all random seeds**: Set seeds for `random`, `numpy`, `torch`, and `torch.cuda` at the start of every run. Use `torch.backends.cudnn.deterministic = True` and `torch.backends.cudnn.benchmark = False` for fully deterministic behavior, though this may reduce performance.
- **Pin dependencies**: Use a lock file (poetry.lock, pnpm-lock.yaml for JS tooling, or pip-compile) to pin exact library versions. Record the full environment in each experiment run.
- **Version datasets**: Use DVC, Delta Lake, or Hugging Face Datasets versioning to track dataset changes. Never train on unversioned data.
- **Log everything**: Record hyperparameters, random seeds, git commit hash, hardware info, and data splits for every experiment.

### Performance

- **Use `torch.compile()`**: Starting with PyTorch 2.x, `torch.compile()` can significantly speed up training and inference by JIT-compiling the model graph. Test it on your model and measure the speedup, as benefits vary by architecture.
- **Enable mixed precision**: Use `torch.amp.autocast` and `GradScaler` for FP16 training. This typically reduces memory usage by 30-50% and speeds up training by 20-60% on modern GPUs.
- **Optimize data loading**: Set `num_workers` equal to the number of CPU cores divided by the number of GPUs. Use `pin_memory=True` and `persistent_workers=True`. Pre-process data offline rather than in the training loop.
- **Profile before optimizing**: Use `torch.profiler` to identify actual bottlenecks. Do not guess; measure GPU utilization, data loading time, and memory allocation patterns.
- **Gradient checkpointing**: For memory-constrained training, use `torch.utils.checkpoint.checkpoint()` to trade compute for memory by recomputing activations during the backward pass instead of storing them.

### Code Quality

- **Type hints**: Annotate all function signatures with type hints. Use `torch.Tensor` for tensor arguments and return types.
- **Configuration files**: Store hyperparameters in YAML or TOML files rather than hardcoding them. Use dataclasses or Pydantic models to validate configuration.
- **Separate concerns**: Keep data loading, model definition, training logic, and evaluation in separate modules. Each should be independently testable.
- **Unit test model components**: Write tests that verify model output shapes, loss computation, and gradient flow. Test that `model.parameters()` returns the expected number of parameters.

### Experiment Management

- **Naming conventions**: Use descriptive run names that encode the key experiment variables (e.g., `resnet50-lr1e3-bs64-augv2`). This makes it easy to scan results without opening each run.
- **Tagging**: Tag runs with metadata like `baseline`, `ablation`, `final`, or `debugging` to organize experiments and filter results.
- **Compare systematically**: Change one variable at a time in ablation studies. Document the hypothesis, result, and conclusion for each experiment.
- **Archive failed runs**: Do not delete failed runs. Mark them as failed and log the reason. Failed experiments often contain valuable information about what does not work.

---

## 11. Anti-Patterns

### Data Leakage

- **Fitting on test data**: Never call `.fit()` or `.fit_transform()` on the test set. All preprocessing transformations must be learned only from the training data. Use scikit-learn Pipelines with `cross_val_score` to enforce this automatically.
- **Temporal leakage**: For time-series data, never shuffle before splitting. Use time-based splits where all training data precedes all validation and test data.
- **Target leakage**: Features that are derived from the target variable (or are proxies for the target that would not be available at prediction time) will inflate metrics during development and fail in production.

### Training Pitfalls

- **No learning rate schedule**: Using a constant learning rate throughout training prevents the model from fine-tuning in later epochs. Always use at least cosine decay or step decay.
- **Ignoring gradient norms**: Not monitoring gradient norms means you will not detect exploding or vanishing gradients until training diverges. Log gradient norms and use gradient clipping.
- **Overly large batch sizes**: Very large batch sizes can degrade generalization. If scaling up batch sizes, scale the learning rate accordingly (linear scaling rule) and add warmup.
- **No early stopping**: Training until a fixed epoch count wastes compute and risks overfitting. Monitor validation loss and stop when it plateaus or increases for several consecutive evaluations.
- **Single metric obsession**: Optimizing only accuracy (or only loss) can hide catastrophic failures in subgroups. Track multiple metrics and examine per-class or per-segment performance.

### Infrastructure Mistakes

- **No checkpointing**: Losing hours of training progress due to a crash is avoidable. Save checkpoints at regular intervals and after each epoch.
- **Logging too infrequently**: Logging only at the end of each epoch hides intra-epoch dynamics. Log every 50-100 steps to catch divergence, oscillation, or learning rate issues early.
- **Hardcoded paths**: Using absolute paths in training scripts breaks portability. Use environment variables or configuration files for all paths.
- **Ignoring resource monitoring**: Not tracking GPU utilization, memory, and disk I/O means you cannot diagnose training slowdowns. Use `nvidia-smi`, `torch.cuda.memory_summary()`, or W&B system metrics.
- **Training on unvalidated data**: Launching long training runs without first running data validation (schema checks, distribution checks, missing value analysis) wastes compute on garbage-in-garbage-out outcomes.

### Evaluation Mistakes

- **Evaluating on training data**: Reporting metrics on training data gives a misleading picture of generalization. Always evaluate on a held-out set that the model has never seen.
- **No statistical significance**: Reporting results from a single run without confidence intervals or variance estimates makes it impossible to distinguish genuine improvements from noise. Run at least 3-5 seeds and report mean plus standard deviation.
- **Stale test sets**: Using the same test set for months or years leads to implicit overfitting through repeated evaluation and selection. Periodically refresh test sets from production data.

### Organizational Anti-Patterns

- **No experiment log**: Running experiments without recording what was tried, what worked, and what failed leads to repeated work and lost knowledge. Maintain an experiment log alongside the code.
- **Premature optimization**: Spending weeks on distributed training, custom CUDA kernels, or elaborate architectures before establishing a strong baseline on a simple model wastes effort. Start with a simple model, establish a baseline, then iterate.
- **Not sharing results**: Keeping experiment results in personal notebooks rather than a shared tracking system prevents the team from building on each other's work and catching errors early.

---

## Sources & References

- PyTorch Performance Tuning Guide: https://docs.pytorch.org/tutorials/recipes/recipes/tuning_guide.html
- PyTorch Distributed Data Parallel Tutorial: https://docs.pytorch.org/tutorials/intermediate/ddp_tutorial.html
- Hugging Face Trainer API Documentation: https://huggingface.co/docs/transformers/en/main_classes/trainer
- Hugging Face Fine-Tuning Guide: https://huggingface.co/docs/transformers/en/training
- MLflow Experiment Tracking Documentation: https://mlflow.org/docs/latest/ml/tracking/
- MLflow Model Registry: https://mlflow.org/classical-ml/experiment-tracking
- Weights & Biases Documentation: https://docs.wandb.ai/models/track/log
- Optuna Hyperparameter Optimization Framework: https://optuna.org/
- scikit-learn Pipeline Documentation: https://scikit-learn.org/stable/modules/generated/sklearn.pipeline.Pipeline.html
- scikit-learn Common Pitfalls and Recommended Practices: https://scikit-learn.org/stable/common_pitfalls.html
