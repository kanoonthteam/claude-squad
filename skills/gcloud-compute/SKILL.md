---
name: gcloud-compute
description: Production-grade GCP compute patterns -- Cloud Run, GKE Autopilot, Cloud Functions v2, and Terraform modules for compute workloads
---

# GCP Compute -- Staff Engineer Patterns

Production-ready patterns for Cloud Run (sidecars, GPU, always-on CPU), GKE Autopilot (Workload Identity, Gateway API, Config Sync), and Cloud Functions v2 on Google Cloud Platform.

## Table of Contents
1. [Cloud Run Advanced Patterns](#cloud-run-advanced-patterns)
2. [GKE Enterprise Patterns](#gke-enterprise-patterns)
3. [Cloud Functions v2 Patterns](#cloud-functions-v2-patterns)
4. [Terraform Modules for Compute](#terraform-modules-for-compute)
5. [Best Practices](#best-practices)
6. [Anti-Patterns](#anti-patterns)
7. [Common CLI Commands](#common-cli-commands)
8. [Sources & References](#sources--references)

---

## Cloud Run Advanced Patterns

### Multi-Container Sidecar Pattern

Cloud Run supports up to 10 containers per instance, enabling advanced patterns like telemetry collection, security proxies, and service mesh integration.

```yaml
# cloud-run-sidecar.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: app-with-sidecars
  annotations:
    run.googleapis.com/launch-stage: BETA
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: "100"
        run.googleapis.com/cpu-throttling: "false"
        run.googleapis.com/startup-cpu-boost: "true"
    spec:
      containerConcurrency: 1000
      containers:
        # Main application container
        - name: app
          image: gcr.io/my-project/app:latest
          ports:
            - name: http1
              containerPort: 8080
          resources:
            limits:
              memory: 2Gi
              cpu: "4"
          env:
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://localhost:4318"
          volumeMounts:
            - name: shared-data
              mountPath: /data

        # OpenTelemetry collector sidecar
        - name: otel-collector
          image: otel/opentelemetry-collector:latest
          resources:
            limits:
              memory: 512Mi
              cpu: "1"
          volumeMounts:
            - name: shared-data
              mountPath: /data

        # Cloud SQL Auth Proxy sidecar
        - name: cloud-sql-proxy
          image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:latest
          args:
            - "--structured-logs"
            - "--port=5432"
            - "my-project:asia-southeast1:mydb"
          resources:
            limits:
              memory: 256Mi
              cpu: "0.5"

      volumes:
        - name: shared-data
          emptyDir:
            medium: Memory
            sizeLimit: 100Mi
```

### Cloud Run Jobs with GPU

GPU-accelerated batch workloads for ML inference, data processing, and video transcoding.

```yaml
# cloud-run-gpu-job.yaml
apiVersion: run.googleapis.com/v1
kind: Job
metadata:
  name: ml-batch-processing
spec:
  template:
    spec:
      template:
        spec:
          maxRetries: 3
          timeoutSeconds: 3600
          containers:
            - name: ml-processor
              image: gcr.io/my-project/ml-processor:latest
              resources:
                limits:
                  memory: 16Gi
                  cpu: "4"
                  nvidia.com/gpu: "1"
              env:
                - name: GPU_TYPE
                  value: "nvidia-l4"
                - name: BATCH_SIZE
                  value: "64"
          nodeSelector:
            cloud.google.com/gke-accelerator: nvidia-l4
```

### Cloud Run Service with Always-On CPU

For workloads requiring continuous background processing or WebSocket connections.

```bash
# Deploy with always-allocated CPU
gcloud run deploy websocket-service \
  --image gcr.io/my-project/websocket-app:latest \
  --region asia-southeast1 \
  --cpu-throttling \
  --min-instances 2 \
  --max-instances 100 \
  --cpu 4 \
  --memory 8Gi \
  --concurrency 1000 \
  --timeout 3600 \
  --allow-unauthenticated
```

### Cloud Run Terraform -- Production Grade

```hcl
# terraform/cloud-run.tf
resource "google_cloud_run_v2_service" "app" {
  name     = "production-app"
  location = var.region

  labels = {
    environment = "production"
    team        = "platform"
    cost-center = "engineering"
  }

  template {
    scaling {
      min_instance_count = 2
      max_instance_count = 100
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    service_account = google_service_account.app.email

    max_instance_request_concurrency = 1000
    timeout                         = "300s"
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

    containers {
      name  = "app"
      image = "gcr.io/${var.project_id}/app:${var.image_tag}"

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "4"
          memory = "8Gi"
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 5
        period_seconds        = 3
        failure_threshold     = 5
      }

      liveness_probe {
        http_get {
          path = "/health"
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# IAM: Allow unauthenticated access
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.public_access ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

---

## GKE Enterprise Patterns

### GKE Autopilot Cluster

```hcl
# terraform/gke.tf
resource "google_container_cluster" "autopilot" {
  name     = "production-cluster"
  location = var.region
  project  = var.project_id

  enable_autopilot = true

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.private.name

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  release_channel {
    channel = "RAPID"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  dns_config {
    cluster_dns        = "CLOUD_DNS"
    cluster_dns_scope  = "CLUSTER_SCOPE"
    cluster_dns_domain = "cluster.local"
  }
}
```

### Workload Identity for GKE

```yaml
# k8s/workload-identity.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: production
  annotations:
    iam.gke.io/gcp-service-account: app-sa@my-project.iam.gserviceaccount.com
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      serviceAccountName: app-sa
      nodeSelector:
        cloud.google.com/gke-accelerator: ""  # No GPU needed
      containers:
        - name: api
          image: gcr.io/my-project/api:v1.0
          resources:
            requests:
              cpu: "500m"
              memory: "256Mi"
              ephemeral-storage: "1Gi"
            limits:
              cpu: "2"
              memory: "1Gi"
              ephemeral-storage: "2Gi"
```

```hcl
# terraform/workload-identity.tf
resource "google_service_account" "app" {
  account_id   = "app-sa"
  display_name = "Application Service Account"
}

resource "google_project_iam_member" "app_roles" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/storage.objectViewer",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[production/app-sa]"
}
```

### Gateway API with GKE

```yaml
# k8s/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: production-gateway
  namespace: production
  annotations:
    networking.gke.io/certmap: production-certmap
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: tls-secret
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: production
spec:
  parentRefs:
    - name: production-gateway
  hostnames:
    - "api.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/v1
      backendRefs:
        - name: api-v1
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /api/v2
      backendRefs:
        - name: api-v2
          port: 80
```

### Config Sync (GitOps)

```yaml
# root-sync.yaml
apiVersion: configsync.gke.io/v1beta1
kind: RootSync
metadata:
  name: root-sync
  namespace: config-management-system
spec:
  sourceFormat: unstructured
  git:
    repo: https://github.com/my-org/platform-config
    branch: main
    dir: /clusters/production
    auth: gcpserviceaccount
    gcpServiceAccountEmail: config-sync@my-project.iam.gserviceaccount.com
```

---

## Cloud Functions v2 Patterns

### HTTP-Triggered Function

```typescript
// functions/src/api.ts
import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';

const apiKey = defineSecret('API_KEY');

export const apiEndpoint = onRequest(
  {
    region: 'asia-southeast1',
    memory: '512MiB',
    timeoutSeconds: 60,
    minInstances: 1,
    maxInstances: 100,
    concurrency: 80,
    secrets: [apiKey],
    cors: ['https://example.com'],
  },
  async (req, res) => {
    if (req.headers['x-api-key'] !== apiKey.value()) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    res.json({ message: 'Hello from Cloud Functions v2' });
  }
);
```

### Eventarc-Triggered Function

```typescript
// functions/src/triggers/storage.ts
import { onObjectFinalized } from 'firebase-functions/v2/storage';

export const processUpload = onObjectFinalized(
  {
    bucket: 'my-uploads-bucket',
    region: 'asia-southeast1',
    memory: '1GiB',
    timeoutSeconds: 300,
    retry: true,
  },
  async (event) => {
    const { name, contentType, size } = event.data;

    console.log(`Processing: ${name} (${contentType}, ${size} bytes)`);

    if (contentType?.startsWith('image/')) {
      // Image processing logic
    }
  }
);
```

### Pub/Sub-Triggered Function

```typescript
// functions/src/triggers/pubsub.ts
import { onMessagePublished } from 'firebase-functions/v2/pubsub';

interface OrderMessage {
  orderId: string;
  userId: string;
  total: number;
}

export const processOrder = onMessagePublished<OrderMessage>(
  {
    topic: 'orders',
    region: 'asia-southeast1',
    memory: '256MiB',
    timeoutSeconds: 120,
    retry: true,
  },
  async (event) => {
    const { orderId, userId, total } = event.data.message.json;

    console.log(`Processing order ${orderId} for user ${userId}: $${total}`);
    // Order processing logic
  }
);
```

---

## Terraform Modules for Compute

### Reusable Cloud Run Module

```hcl
# modules/cloud-run-service/main.tf
variable "service_name" { type = string }
variable "image"        { type = string }
variable "region"       { type = string; default = "asia-southeast1" }
variable "min_instances" { type = number; default = 0 }
variable "max_instances" { type = number; default = 10 }
variable "cpu"          { type = string; default = "1" }
variable "memory"       { type = string; default = "512Mi" }

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "secrets" {
  type = map(object({
    secret_name = string
    version     = string
  }))
  default = {}
}

resource "google_cloud_run_v2_service" "service" {
  name     = var.service_name
  location = var.region

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_name
              version = env.value.version
            }
          }
        }
      }
    }
  }
}

output "service_url" {
  value = google_cloud_run_v2_service.service.uri
}
```

### Using the Module

```hcl
# environments/production/main.tf
module "api_service" {
  source = "../../modules/cloud-run-service"

  service_name  = "api-service"
  image         = "gcr.io/my-project/api:v1.2.3"
  region        = "asia-southeast1"
  min_instances = 2
  max_instances = 100
  cpu           = "4"
  memory        = "8Gi"

  env_vars = {
    NODE_ENV  = "production"
    LOG_LEVEL = "info"
  }

  secrets = {
    DATABASE_URL = {
      secret_name = "database-url"
      version     = "latest"
    }
  }
}
```

---

## Best Practices

1. **Cloud Run: Use Gen2 execution environment** -- Gen2 provides full Linux compatibility, broader networking support, and longer request timeouts (up to 60 minutes).

2. **Always set min instances for production** -- Prevents cold start latency for user-facing services. Set `min_instances >= 2` for high-availability workloads.

3. **Use startup CPU boost** -- Cloud Run's `startup-cpu-boost` temporarily allocates more CPU during container startup, reducing cold start time by 40-60%.

4. **GKE Autopilot over Standard** -- Autopilot removes node management burden, enforces security best practices, and right-sizes pods automatically.

5. **Workload Identity over service account keys** -- Never export or mount service account JSON keys. Workload Identity maps Kubernetes SAs to GCP SAs without key management.

6. **Cloud Functions: Set concurrency** -- v2 supports up to 1000 concurrent requests per instance. Set `concurrency` to avoid unnecessary instance scaling.

7. **Use VPC connectors for private resources** -- Connect Cloud Run and Cloud Functions to your VPC for accessing Cloud SQL, Memorystore, and other private services.

8. **Tag resources consistently** -- Use labels for `environment`, `team`, and `cost-center` across all compute resources for billing and governance.

---

## Anti-Patterns

1. **Running stateful workloads on Cloud Run** -- Cloud Run instances are ephemeral. Use GKE with persistent volumes or managed databases instead.

2. **Using Cloud Functions for long-running tasks** -- Functions have a 60-minute max timeout. Use Cloud Run Jobs or GKE Jobs for extended processing.

3. **Ignoring concurrency settings** -- Default Cloud Functions v1 concurrency is 1 request per instance. Failing to increase this in v2 causes excessive scaling and cost.

4. **Using GKE Standard without node auto-provisioning** -- Manually managing node pools leads to over- or under-provisioning. Use Autopilot or enable NAP.

5. **Hardcoding regions** -- Use variables for regions in Terraform and parameterize gcloud commands. This enables multi-region deployments.

6. **Granting roles/owner to service accounts** -- Always use least-privilege roles. Grant only the specific roles needed (e.g., `roles/cloudsql.client` instead of `roles/editor`).

---

## Common CLI Commands

```bash
# Cloud Run
gcloud run deploy SERVICE --image IMAGE --region REGION
gcloud run services list --region REGION
gcloud run services describe SERVICE --region REGION
gcloud run revisions list --service SERVICE --region REGION
gcloud run services update SERVICE --min-instances 2 --region REGION
gcloud run services update-traffic SERVICE --to-revisions REVISION=50,LATEST=50

# Cloud Run Jobs
gcloud run jobs create JOB --image IMAGE --region REGION
gcloud run jobs execute JOB --region REGION
gcloud run jobs executions list --job JOB --region REGION

# GKE
gcloud container clusters get-credentials CLUSTER --region REGION
gcloud container clusters describe CLUSTER --region REGION
kubectl get pods -n NAMESPACE
kubectl top pods -n NAMESPACE

# Cloud Functions
gcloud functions deploy FUNCTION --gen2 --runtime nodejs20 --region REGION
gcloud functions describe FUNCTION --region REGION
gcloud functions logs read FUNCTION --region REGION
gcloud functions list --region REGION
```

---

## Sources & References

- [Cloud Run sidecars enable advanced multi-container patterns](https://cloud.google.com/blog/products/serverless/cloud-run-now-supports-multi-container-deployments)
- [Configure GPUs for Cloud Run jobs](https://docs.cloud.google.com/run/docs/configuring/jobs/gpu)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [GKE Autopilot Overview](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview)
- [Authenticate to Google Cloud APIs from GKE workloads](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Cloud Functions 2nd generation overview](https://cloud.google.com/blog/products/serverless/cloud-functions-2nd-generation-now-generally-available)
- [Cloud Functions v2](https://cloud.google.com/functions/docs/2nd-gen/overview)
- [Terraform GCP best practices](https://cloud.google.com/docs/terraform/best-practices/root-modules)
- [Cloud Architecture Center](https://cloud.google.com/architecture)
