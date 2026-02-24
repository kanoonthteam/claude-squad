---
name: ml-serving
description: Model deployment, inference optimization, serving APIs, and production ML systems
---

# ML Model Serving

This skill covers the end-to-end process of deploying machine learning models into
production environments. It addresses model serialization and export, building inference
APIs, optimization techniques for latency and throughput, GPU memory management,
containerized deployment, traffic management with A/B testing and canary releases,
monitoring for data and prediction drift, and scaling strategies. The goal is to bridge
the gap between trained models and reliable, performant production systems -- a gap that
causes 87% of ML models to never reach production.

## Table of Contents

1. Model Export & Serialization
2. FastAPI Inference Endpoints
3. Batch vs Real-Time Inference
4. Model Optimization (ONNX, TorchScript, Quantization)
5. GPU Inference Management
6. Containerized Deployment
7. A/B Testing & Canary Releases
8. Monitoring & Observability
9. Scaling & Load Balancing
10. Best Practices
11. Anti-Patterns

---

## 1. Model Export & Serialization

Before a model can be served, it must be exported from its training environment into a
format suitable for inference. The two most common approaches for PyTorch models are
ONNX export and TorchScript compilation. Each has trade-offs in terms of portability,
performance, and compatibility.

### ONNX Export

ONNX (Open Neural Network Exchange) provides a framework-agnostic format that can run
on ONNX Runtime, TensorRT, and other inference engines. ONNX export works by tracing
the model with a sample input and recording the computation graph.

```python
import torch
import torch.onnx
from transformers import AutoModelForSequenceClassification, AutoTokenizer

# Load the trained model
model = AutoModelForSequenceClassification.from_pretrained("./fine-tuned-bert")
model.eval()

tokenizer = AutoTokenizer.from_pretrained("./fine-tuned-bert")

# Create dummy input matching the model's expected shape
dummy_input = tokenizer(
    "Sample input text for tracing",
    return_tensors="pt",
    padding="max_length",
    max_length=128,
    truncation=True,
)

# Export to ONNX format
torch.onnx.export(
    model,
    (dummy_input["input_ids"], dummy_input["attention_mask"]),
    "model.onnx",
    export_params=True,
    opset_version=17,
    do_constant_folding=True,
    input_names=["input_ids", "attention_mask"],
    output_names=["logits"],
    dynamic_axes={
        "input_ids": {0: "batch_size", 1: "sequence_length"},
        "attention_mask": {0: "batch_size", 1: "sequence_length"},
        "logits": {0: "batch_size"},
    },
)

# Validate the exported model
import onnx
onnx_model = onnx.load("model.onnx")
onnx.checker.check_model(onnx_model)
print("ONNX model exported and validated successfully.")
```

Key considerations for ONNX export:

- Always use `dynamic_axes` to allow variable batch sizes and sequence lengths at
  inference time. Hardcoded shapes will limit flexibility.
- Set `opset_version` to the highest version supported by your target runtime. Opset 17+
  is recommended for transformer architectures.
- Enable `do_constant_folding=True` to pre-compute constant expressions at export time,
  reducing the graph size and improving inference speed.
- After export, always validate the model with `onnx.checker.check_model` and run
  inference with ONNX Runtime to compare outputs against the original PyTorch model.

### TorchScript Compilation

TorchScript is PyTorch's built-in serialization format. It supports two modes: tracing
(records operations during a forward pass) and scripting (analyzes Python source code
directly). Use tracing for models with static control flow and scripting for models with
dynamic control flow (e.g., conditional branches or variable-length loops).

```python
import torch

model = torch.load("trained_model.pt")
model.eval()

# Option 1: Tracing (for models with static control flow)
example_input = torch.randn(1, 3, 224, 224)
traced_model = torch.jit.trace(model, example_input)
traced_model.save("model_traced.pt")

# Option 2: Scripting (for models with dynamic control flow)
scripted_model = torch.jit.script(model)
scripted_model.save("model_scripted.pt")

# Verify outputs match
with torch.no_grad():
    original_output = model(example_input)
    traced_output = traced_model(example_input)
    assert torch.allclose(original_output, traced_output, atol=1e-5), \
        "Traced model output diverges from original"
```

TorchScript models can be loaded and served in C++ runtimes (via libtorch), which
eliminates the Python GIL bottleneck and is useful for latency-critical applications.

---

## 2. FastAPI Inference Endpoints

FastAPI is a high-performance Python web framework well suited for serving ML models. It
provides automatic request validation via Pydantic, async support for non-blocking I/O,
and auto-generated OpenAPI documentation. For production deployments, pair FastAPI with
Uvicorn (ASGI server) and a process manager like Gunicorn.

```python
import asyncio
from contextlib import asynccontextmanager
from typing import List

import numpy as np
import onnxruntime as ort
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


class PredictionRequest(BaseModel):
    texts: List[str] = Field(..., min_length=1, max_length=32, description="Texts to classify")


class PredictionResponse(BaseModel):
    predictions: List[int]
    probabilities: List[List[float]]
    model_version: str


# Global model session holder
_model_session = None
_model_version = "v1.2.0"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model on startup, release on shutdown."""
    global _model_session
    sess_options = ort.SessionOptions()
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    sess_options.intra_op_num_threads = 4
    sess_options.inter_op_num_threads = 2

    _model_session = ort.InferenceSession(
        "model.onnx",
        sess_options=sess_options,
        providers=["CUDAExecutionProvider", "CPUExecutionProvider"],
    )
    print("Model loaded successfully.")
    yield
    _model_session = None
    print("Model unloaded.")


app = FastAPI(title="ML Inference API", version="1.0.0", lifespan=lifespan)


@app.get("/health")
async def health_check():
    """Health check endpoint for load balancers and orchestrators."""
    if _model_session is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    return {"status": "healthy", "model_version": _model_version}


@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    """Run inference on the provided texts."""
    if _model_session is None:
        raise HTTPException(status_code=503, detail="Model not ready")

    try:
        # Tokenize inputs (simplified -- use a real tokenizer in production)
        from transformers import AutoTokenizer
        tokenizer = AutoTokenizer.from_pretrained("./fine-tuned-bert")
        encoded = tokenizer(
            request.texts,
            padding=True,
            truncation=True,
            max_length=128,
            return_tensors="np",
        )

        # Run inference in a thread pool to avoid blocking the event loop
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            lambda: _model_session.run(
                None,
                {
                    "input_ids": encoded["input_ids"].astype(np.int64),
                    "attention_mask": encoded["attention_mask"].astype(np.int64),
                },
            ),
        )

        logits = result[0]
        probabilities = softmax(logits, axis=1).tolist()
        predictions = np.argmax(logits, axis=1).tolist()

        return PredictionResponse(
            predictions=predictions,
            probabilities=probabilities,
            model_version=_model_version,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Inference error: {str(e)}")


def softmax(x, axis=1):
    e_x = np.exp(x - np.max(x, axis=axis, keepdims=True))
    return e_x / e_x.sum(axis=axis, keepdims=True)
```

Run with Gunicorn and Uvicorn workers for production:

```bash
gunicorn app:app \
    --workers 4 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:8000 \
    --timeout 120 \
    --graceful-timeout 30 \
    --keep-alive 5
```

Key design decisions for inference APIs:

- Use the `lifespan` context manager to load models at startup and release them on
  shutdown. This avoids loading models on every request.
- Run inference calls in a thread pool executor (`run_in_executor`) to prevent blocking
  the async event loop while the model is computing.
- Always include a `/health` endpoint that verifies the model is loaded. Kubernetes
  liveness and readiness probes depend on this.
- Return the `model_version` in every response for traceability and debugging.
- Set explicit `intra_op_num_threads` and `inter_op_num_threads` in ONNX Runtime session
  options to control CPU parallelism and prevent thread oversubscription.

---

## 3. Batch vs Real-Time Inference

Choosing between batch and real-time inference depends on latency requirements, cost
constraints, and the nature of the workload.

### Real-Time (Online) Inference

Real-time inference serves predictions synchronously, typically via REST or gRPC APIs.
Latency requirements are usually under 100ms for user-facing applications. Use real-time
inference when predictions are needed immediately in response to user actions (search
ranking, recommendations, fraud detection).

Design considerations for real-time serving:

- Pre-load models into memory at server startup rather than loading on demand.
- Use connection pooling and keep-alive connections to reduce TCP overhead.
- Implement request timeouts to prevent slow requests from consuming resources.
- Use adaptive batching (e.g., BentoML or TorchServe built-in batching) to group
  incoming requests over a short window and process them as a single batch. This improves
  GPU utilization without significantly increasing latency.

### Batch (Offline) Inference

Batch inference processes large volumes of data on a schedule (hourly, daily). It is
cost-effective for workloads that do not require immediate results, such as generating
product recommendations overnight, scoring all users for a marketing campaign, or running
periodic anomaly detection on historical data.

Batch inference patterns:

- Store input data in object storage (S3, GCS) or a data warehouse.
- Use a job scheduler (Airflow, Prefect, Dagster) to trigger inference pipelines.
- Write predictions back to a database or feature store for downstream consumption.
- Leverage large batch sizes to maximize GPU throughput.
- Implement checkpointing so that failed jobs can resume from the last completed batch
  rather than restarting from scratch.

### Dynamic Batching

TorchServe and BentoML both support dynamic batching, which accumulates incoming
requests over a configurable time window and batches them together. This is critical
for GPU-based serving where processing one request at a time wastes compute. Configure
`batch_size` (maximum number of requests per batch) and `max_batch_delay` (maximum time
to wait before processing an incomplete batch) to balance latency and throughput.

---

## 4. Model Optimization (ONNX, TorchScript, Quantization)

Model optimization reduces inference latency and memory consumption, enabling deployment
on constrained hardware or at lower cost. The three primary techniques are graph
optimization, quantization, and compilation.

### ONNX Runtime Graph Optimization

ONNX Runtime applies graph-level optimizations automatically when a model is loaded.
These include constant folding, redundant node elimination, and operator fusion. For
transformer models, ONNX Runtime can fuse multi-head attention, layer normalization,
and GELU activation into single optimized kernels.

### Quantization (INT8 and FP16)

Quantization reduces the precision of model weights and activations from FP32 to lower
bit widths. INT8 quantization reduces model size by 4x and can deliver 2-4x speedup on
hardware with INT8 support (NVIDIA T4, A100, Intel CPUs with VNNI).

There are three quantization approaches:

- **Dynamic quantization**: Weights are quantized ahead of time; activations are
  quantized dynamically at runtime. Simple to apply, no calibration data needed.
- **Static quantization**: Both weights and activations are quantized using calibration
  data. Better performance than dynamic quantization but requires a representative
  calibration dataset.
- **Quantization-aware training (QAT)**: Quantization is simulated during training,
  allowing the model to adapt to reduced precision. Yields the best accuracy but
  requires retraining.

```python
import onnxruntime as ort
from onnxruntime.quantization import (
    quantize_dynamic,
    quantize_static,
    QuantType,
    CalibrationDataReader,
)
import numpy as np

# --- Dynamic Quantization (no calibration data needed) ---
quantize_dynamic(
    model_input="model.onnx",
    model_output="model_int8_dynamic.onnx",
    weight_type=QuantType.QInt8,
)

# --- Static Quantization (requires calibration data) ---
class CalibrationReader(CalibrationDataReader):
    """Provides calibration data for static quantization."""

    def __init__(self, calibration_texts, tokenizer, max_length=128):
        self.tokenizer = tokenizer
        self.data = []
        for text in calibration_texts:
            encoded = tokenizer(
                text,
                padding="max_length",
                truncation=True,
                max_length=max_length,
                return_tensors="np",
            )
            self.data.append({
                "input_ids": encoded["input_ids"].astype(np.int64),
                "attention_mask": encoded["attention_mask"].astype(np.int64),
            })
        self.index = 0

    def get_next(self):
        if self.index >= len(self.data):
            return None
        sample = self.data[self.index]
        self.index += 1
        return sample

    def rewind(self):
        self.index = 0


# Prepare calibration data (100-500 representative samples)
calibration_texts = [
    "This is a sample calibration sentence.",
    "Another example for calibration purposes.",
    # ... add 100-500 representative samples from your production data
]

from transformers import AutoTokenizer
tokenizer = AutoTokenizer.from_pretrained("./fine-tuned-bert")
calibration_reader = CalibrationReader(calibration_texts, tokenizer)

quantize_static(
    model_input="model.onnx",
    model_output="model_int8_static.onnx",
    calibration_data_reader=calibration_reader,
    quant_format=ort.quantization.QuantFormat.QDQ,
    weight_type=QuantType.QInt8,
    activation_type=QuantType.QInt8,
)

# --- FP16 Conversion (for GPU inference) ---
from onnxconverter_common import float16
import onnx

model_fp32 = onnx.load("model.onnx")
model_fp16 = float16.convert_float_to_float16(model_fp32, keep_io_types=True)
onnx.save(model_fp16, "model_fp16.onnx")

# --- Benchmark the quantized models ---
import time

def benchmark_model(model_path, sample_input, n_runs=100):
    session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    # Warmup
    for _ in range(10):
        session.run(None, sample_input)
    # Timed runs
    start = time.perf_counter()
    for _ in range(n_runs):
        session.run(None, sample_input)
    elapsed = time.perf_counter() - start
    return elapsed / n_runs * 1000  # ms per inference

sample = calibration_reader.data[0]
for model_path in ["model.onnx", "model_int8_dynamic.onnx", "model_int8_static.onnx"]:
    avg_ms = benchmark_model(model_path, sample)
    print(f"{model_path}: {avg_ms:.2f} ms/inference")
```

Quantization guidelines:

- Start with dynamic quantization as a baseline. It requires no calibration data and
  typically achieves 1.5-2x speedup with minimal accuracy loss.
- Use static quantization when you need higher performance and can provide calibration
  data. Use 100-500 representative samples from production data.
- Use FP16 for GPU inference. Most modern NVIDIA GPUs (Volta and newer) have dedicated
  FP16 Tensor Cores that deliver up to 2x throughput over FP32.
- Always measure accuracy on a held-out test set after quantization. Accept no more than
  1-2% accuracy degradation for classification tasks.
- For transformer models, consider per-channel quantization instead of per-tensor
  quantization for better accuracy preservation.

---

## 5. GPU Inference Management

Efficient GPU utilization is critical for cost-effective model serving. GPU instances are
expensive, and under-utilized GPUs waste money.

### Memory Management

- Profile GPU memory usage with `nvidia-smi` or `torch.cuda.memory_summary()` to
  understand peak and steady-state memory consumption.
- Use CUDA memory pools (`torch.cuda.CUDAPluggableAllocator` or ONNX Runtime's arena
  allocator) to reduce memory allocation overhead.
- For multiple models on a single GPU, use NVIDIA Multi-Process Service (MPS) to share
  the GPU across multiple processes without context switching overhead.
- Set `CUDA_VISIBLE_DEVICES` environment variable to restrict which GPUs a process can
  access. This prevents accidental cross-process GPU contention.
- Clear GPU caches between inference batches if memory pressure is high:
  `torch.cuda.empty_cache()`.

### Multi-GPU Serving

For models that fit on a single GPU, run multiple model replicas across GPUs to increase
throughput. For models too large for a single GPU (LLMs), use tensor parallelism to shard
the model across GPUs.

vLLM is the standard tool for serving large language models. It uses PagedAttention to
manage KV cache memory efficiently, achieving up to 24x throughput improvement over
naive implementations. Key vLLM configuration options:

- `tensor-parallel-size`: Number of GPUs for tensor parallelism. Set to the number of
  GPUs per node.
- `max-model-len`: Maximum sequence length. Reducing this frees KV cache memory.
- `gpu-memory-utilization`: Fraction of GPU memory to allocate (default 0.9). Lower
  this if you see OOM errors.
- `quantization`: Enable AWQ, GPTQ, or FP8 quantization for reduced memory usage.
- `enforce-eager`: Disable CUDA graph capture for debugging; enable graphs in production
  for lower latency.

### vLLM Deployment

For LLM serving, vLLM provides an OpenAI-compatible API server out of the box:

```bash
# Start vLLM server with tensor parallelism across 2 GPUs
python -m vllm.entrypoints.openai.api_server \
    --model meta-llama/Llama-3.1-8B-Instruct \
    --tensor-parallel-size 2 \
    --max-model-len 4096 \
    --gpu-memory-utilization 0.90 \
    --quantization awq \
    --enable-prefix-caching \
    --max-num-seqs 256 \
    --port 8000
```

For production vLLM deployments, separate prefill and decode workers. Prefill is
compute-bound and bursty; decode is memory-bound and latency-sensitive. Running them
on separate instances with independent autoscaling policies prevents prefill spikes from
degrading decode latency.

---

## 6. Containerized Deployment

Docker containers provide reproducible, isolated environments for model serving. A
well-structured Dockerfile ensures consistent behavior across development, staging,
and production.

```dockerfile
# Use NVIDIA CUDA base image for GPU support
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    MODEL_PATH=/app/models/model.onnx \
    PORT=8000

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# Install Python dependencies (cached layer)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/
COPY models/ ./models/

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Expose port
EXPOSE ${PORT}

# Start the server
CMD ["gunicorn", "app.main:app", \
     "--workers", "2", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--timeout", "120", \
     "--graceful-timeout", "30"]
```

Containerization best practices for ML workloads:

- Use multi-stage builds to separate the build environment (with compilers and build
  tools) from the runtime environment. This reduces image size significantly.
- Pin all dependency versions in `requirements.txt` to ensure reproducible builds.
- Include the model artifact in the image for small models (under 500MB). For large
  models, download from object storage at startup or mount a shared volume.
- Set `HEALTHCHECK` in the Dockerfile so Docker and orchestrators can detect unhealthy
  containers and restart them automatically.
- Run as a non-root user to follow the principle of least privilege.
- Use `.dockerignore` to exclude training data, notebooks, and other unnecessary files
  from the build context.

For Kubernetes deployment, define resource requests and limits for GPU:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-inference
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ml-inference
  template:
    metadata:
      labels:
        app: ml-inference
    spec:
      containers:
        - name: inference
          image: registry.example.com/ml-inference:v1.2.0
          ports:
            - containerPort: 8000
          resources:
            requests:
              cpu: "2"
              memory: "4Gi"
              nvidia.com/gpu: "1"
            limits:
              cpu: "4"
              memory: "8Gi"
              nvidia.com/gpu: "1"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 60
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 90
            periodSeconds: 30
          env:
            - name: MODEL_PATH
              value: /app/models/model.onnx
            - name: CUDA_VISIBLE_DEVICES
              value: "0"
```

---

## 7. A/B Testing & Canary Releases

Deploying a new model version directly to all traffic is risky. A/B testing and canary
releases allow gradual rollout with the ability to monitor performance and roll back
if the new model underperforms.

### Canary Releases

In a canary release, a small percentage of traffic (e.g., 5-10%) is routed to the new
model version while the majority continues to hit the existing version. If metrics
(latency, error rate, business KPIs) remain stable or improve, traffic is gradually
increased until the new version handles 100%.

Implementation approaches:

- **Service mesh (Istio)**: Use traffic splitting rules to route a percentage of requests
  to the canary deployment. Istio VirtualService allows weight-based routing between two
  Kubernetes services.
- **Load balancer (NGINX, Envoy)**: Configure upstream weights to split traffic between
  the stable and canary backends.
- **Application-level routing**: Implement routing logic in the API gateway or inference
  service. Route based on user ID hash, request headers, or random sampling.

### A/B Testing

A/B testing goes beyond canary releases by assigning users to specific model variants
and measuring the impact on business metrics (click-through rate, conversion rate,
revenue). Key requirements:

- Consistent user assignment: The same user should always see the same model variant
  during the test period. Use a hash of the user ID to determine assignment.
- Statistical significance: Run the test long enough to collect sufficient data. Use
  power analysis to determine the required sample size before starting the test.
- Metric collection: Log the model version alongside every prediction for post-hoc
  analysis.
- Guard rails: Define stopping criteria (e.g., error rate exceeds 5%) that trigger
  automatic rollback.

### Shadow (Dark) Launches

In a shadow launch, the new model receives a copy of production traffic but its responses
are discarded. The new model's predictions are compared against the production model
offline. This is the safest approach for validating a new model because it has zero impact
on users, but it doubles the inference compute cost.

---

## 8. Monitoring & Observability

Production ML systems require monitoring at multiple levels: infrastructure metrics,
application metrics, and ML-specific metrics. Without monitoring, model degradation goes
undetected and silently harms business outcomes.

### Infrastructure Metrics

- **GPU utilization**: Monitor with NVIDIA DCGM or `nvidia-smi`. Low utilization
  indicates inefficient batching or over-provisioned hardware.
- **GPU memory usage**: Track peak and average memory consumption. Approaching the limit
  causes OOM errors.
- **CPU and memory usage**: Monitor with Prometheus node_exporter.
- **Request latency (p50, p95, p99)**: Track the full request lifecycle including
  preprocessing, inference, and postprocessing.
- **Throughput (requests per second)**: Monitor to detect capacity issues.
- **Error rate**: Track HTTP 5xx errors and inference failures.

### ML-Specific Metrics

- **Data drift**: Monitor the statistical distribution of input features over time.
  Drift indicates that the production data is diverging from the training data. Use
  tools like Evidently, Whylogs, or custom statistical tests (KS test, PSI) to detect
  drift.
- **Prediction drift**: Monitor the distribution of model outputs. A shift in prediction
  distribution (e.g., the model suddenly predicts one class much more frequently) signals
  a problem even if input distributions appear stable.
- **Prediction quality**: When ground truth labels become available (often with a delay),
  compute metrics like accuracy, precision, recall, and F1 score. Track these over time
  to detect model degradation.
- **Feature store freshness**: If features are served from a feature store, monitor the
  lag between feature computation and serving. Stale features degrade model performance.

### Alerting Strategy

- Alert on sudden spikes in latency (p99 exceeds SLA threshold).
- Alert on error rate exceeding baseline by more than 2x.
- Alert on data drift exceeding a configured threshold (e.g., PSI > 0.2).
- Alert on prediction distribution shift beyond 2 standard deviations from baseline.
- Use Prometheus + Grafana for infrastructure dashboards and Evidently for ML-specific
  monitoring dashboards.

Integrate structured logging with OpenTelemetry to trace requests end-to-end. Each
prediction request should log: request ID, model version, input hash, prediction result,
latency breakdown (preprocess, inference, postprocess), and timestamp.

---

## 9. Scaling & Load Balancing

ML inference workloads have unique scaling characteristics compared to typical web
services. Models are memory-heavy, GPU-bound, and have variable latency depending on
input size.

### Horizontal Scaling

- Add more replicas of the inference service behind a load balancer to increase throughput.
- Use Kubernetes Horizontal Pod Autoscaler (HPA) with custom metrics. Scale on GPU
  utilization or request queue depth rather than CPU utilization, which is often misleading
  for ML workloads.
- For vLLM and LLM serving, use the vLLM Production Stack with prefix-aware routing that
  directs requests to instances holding the relevant KV caches, reducing redundant
  computation.

### Vertical Scaling

- Use larger GPU instances (e.g., A100 80GB instead of A100 40GB) to serve larger models
  or increase batch sizes.
- Vertical scaling is simpler but has hardware limits and creates single points of failure.

### Load Balancing Strategies

- **Round-robin**: Simple but suboptimal for ML workloads because request processing times
  vary significantly based on input size.
- **Least-connections**: Routes requests to the server with the fewest active connections.
  Better than round-robin but still imperfect.
- **Latency-aware**: Routes requests to the server with the lowest recent latency. Best
  for ML workloads but more complex to implement.
- **Prefix-aware (for LLMs)**: Routes requests to the server most likely to have relevant
  KV cache entries, reducing prefill computation. Used by vLLM Production Stack.

### Autoscaling Policies

Define separate autoscaling policies for different workload types:

- Real-time inference: Scale based on request queue depth with a target of zero queued
  requests. Use aggressive scale-up (react within 30 seconds) and conservative scale-down
  (wait 5 minutes of low utilization before removing replicas).
- Batch inference: Scale based on job queue length. Scale to zero when there are no
  pending jobs to minimize cost.
- LLM serving: Scale based on GPU memory utilization and KV cache usage. Keep headroom
  for bursty prefill operations.

---

## 10. Best Practices

These best practices are drawn from production deployments and address the most common
failure modes in ML serving systems.

1. **Version everything**: Tag every model artifact with a version. Include the model
   version in every API response and log entry. Use a model registry (MLflow, Weights &
   Biases, DVC) to track model lineage, training parameters, and evaluation metrics.

2. **Separate model from serving code**: The inference service should load the model as an
   external artifact, not embed it in the application code. This allows updating the model
   without redeploying the service and vice versa.

3. **Implement graceful shutdown**: When a container receives SIGTERM, finish processing
   in-flight requests before shutting down. Set Kubernetes `terminationGracePeriodSeconds`
   to a value longer than your maximum expected request duration.

4. **Use health checks at multiple levels**: Implement both liveness probes (is the
   process running?) and readiness probes (is the model loaded and ready to serve?).
   The readiness probe should fail during model loading so the load balancer does not
   route traffic to an unready instance.

5. **Pre-warm models**: Load and run a warmup inference pass on startup before marking
   the service as ready. The first inference pass is often significantly slower due to
   JIT compilation, CUDA kernel caching, and memory allocation.

6. **Set explicit resource limits**: In containerized environments, always set CPU,
   memory, and GPU resource requests and limits. Without limits, a single misbehaving
   pod can starve other workloads on the same node.

7. **Benchmark before deploying**: Run load tests (with tools like Locust or k6) against
   the inference service in a staging environment before deploying to production. Measure
   latency at various percentiles (p50, p95, p99) under realistic load.

8. **Use structured logging**: Log every prediction with the request ID, model version,
   input features (or a hash of them), output, latency, and timestamp. This is essential
   for debugging, auditing, and monitoring.

9. **Plan for rollback**: Every deployment should have a tested rollback procedure. Keep
   the previous model version available and ready to serve. Automate rollback triggers
   based on error rate or latency thresholds.

10. **Optimize the critical path**: Profile the end-to-end request handling to identify
    bottlenecks. Common bottlenecks include tokenization, data preprocessing, and
    postprocessing -- not just the model forward pass. Optimize these steps with compiled
    tokenizers (e.g., HuggingFace tokenizers Rust backend) and vectorized operations.

11. **Cache repeated predictions**: If the same input is frequently submitted (e.g.,
    popular search queries), cache the prediction result in Redis or an in-memory LRU
    cache. This can dramatically reduce average latency and GPU utilization.

12. **Use feature stores for online features**: When the model depends on real-time
    features (user history, item popularity), serve them from a low-latency feature
    store (Feast, Tecton) rather than computing them on the fly.

---

## 11. Anti-Patterns

These are common mistakes that cause production ML systems to fail or underperform. Avoid
them.

1. **Loading models on every request**: Initializing the model inside the request handler
   adds seconds of latency to every call. Always load models at startup and reuse the
   loaded session across requests.

2. **Ignoring the Python GIL**: Running CPU-bound inference in a multi-threaded Python
   server leads to contention. Use multi-process serving (Gunicorn with multiple workers)
   or offload inference to a non-Python runtime (ONNX Runtime, TorchScript via libtorch).

3. **No input validation**: Serving a model without validating input shape, type, and
   range leads to cryptic errors or silent incorrect predictions. Use Pydantic models
   in FastAPI to enforce constraints on inputs.

4. **Coupling model training and serving code**: When the same codebase is used for
   training and serving, training dependencies (large datasets, experiment tracking
   libraries) bloat the serving container. Separate them into distinct packages with
   minimal shared code.

5. **Skipping quantization evaluation**: Deploying a quantized model without comparing
   its accuracy against the full-precision model on a representative test set. Always
   benchmark accuracy, not just speed.

6. **No timeout on inference calls**: A single malformed input or edge case can cause the
   model to hang or take minutes to process. Always set request timeouts in the API
   server, the load balancer, and the model runner.

7. **Serving without monitoring**: Deploying a model and assuming it will continue to
   perform well indefinitely. Production data distributions shift over time (data drift),
   and model performance degrades silently. Monitor input distributions, prediction
   distributions, and (when available) accuracy metrics continuously.

8. **Over-provisioning GPU resources**: Running one small model per expensive GPU instance
   wastes money. Use NVIDIA MPS or pack multiple models onto a single GPU when individual
   models do not fully utilize GPU memory or compute.

9. **Hardcoding model paths and configuration**: Embedding file paths, batch sizes, and
   other configuration values in the source code makes it impossible to change settings
   without redeploying. Use environment variables or a configuration management system.

10. **Ignoring cold start latency**: In serverless or scale-to-zero deployments, the first
    request after a period of inactivity triggers model loading, which can take 10-60
    seconds for large models. Keep at least one warm replica for latency-sensitive
    workloads, or use model caching strategies to reduce load times.

11. **Testing only with small inputs**: Load testing with trivially small inputs gives
    misleadingly fast results. Test with production-representative input sizes (sequence
    lengths, image resolutions, batch sizes) to get realistic latency numbers.

12. **No graceful degradation strategy**: When the inference service is overloaded, all
    requests fail instead of degrading gracefully. Implement circuit breakers, request
    queuing with bounded queue sizes, and fallback responses (cached predictions, default
    values) for overload scenarios.

---

## Sources & References

- [FastAPI Documentation](https://fastapi.tiangolo.com/) -- Official documentation for
  building high-performance Python APIs with automatic validation and OpenAPI support.
- [ONNX Runtime Performance Tuning and Quantization](https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html) --
  Official guide for ONNX model optimization, including dynamic and static quantization.
- [TorchServe Documentation](https://docs.pytorch.org/serve/) -- PyTorch's official model
  serving framework with support for multi-model serving, dynamic batching, and REST/gRPC.
- [BentoML Documentation](https://docs.bentoml.com/) -- Framework for building production
  ML inference APIs with adaptive batching, model management, and containerized deployment.
- [vLLM Documentation](https://docs.vllm.ai/) -- High-throughput LLM inference engine with
  PagedAttention, tensor parallelism, and OpenAI-compatible API server.
- [vLLM GitHub Repository](https://github.com/vllm-project/vllm) -- Source code and
  deployment guides for the vLLM inference engine.
- [Evidently AI -- ML Monitoring](https://www.evidentlyai.com/blog/fastapi-tutorial) --
  Tutorial on ML serving and monitoring with FastAPI and Evidently for data drift detection.
- [NVIDIA Triton Inference Server](https://developer.nvidia.com/triton-inference-server) --
  NVIDIA's multi-framework model serving platform with dynamic batching, model ensembles,
  and GPU scheduling.
