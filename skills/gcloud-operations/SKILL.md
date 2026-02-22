---
name: gcloud-operations
description: Production-grade GCP operations patterns -- Cloud Monitoring, SLOs, Cloud Logging, Trace, Error Reporting, Cloud Build CI/CD, Eventarc, cost optimization, and Terraform
---

# GCP Operations -- Staff Engineer Patterns

Production-ready patterns for Cloud Monitoring (SLOs, burn rate alerts), Cloud Logging (structured logs), Cloud Trace (OpenTelemetry), Error Reporting, Cloud Build CI/CD pipelines, Eventarc event-driven architecture, cost optimization, and Terraform state management on Google Cloud Platform.

## Table of Contents
1. [Observability & SLOs](#observability--slos)
2. [Cloud Build & CI/CD](#cloud-build--cicd)
3. [Eventarc Architecture](#eventarc-architecture)
4. [Cost Optimization](#cost-optimization)
5. [Terraform Patterns](#terraform-patterns)
6. [Best Practices](#best-practices)
7. [Anti-Patterns](#anti-patterns)
8. [Common CLI Commands](#common-cli-commands)
9. [Sources & References](#sources--references)

---

## Observability & SLOs

### Cloud Logging Structured Logs

```typescript
// src/logger.ts
import { Logging } from '@google-cloud/logging';

const logging = new Logging();
const log = logging.log('application-logs');

interface LogEntry {
  severity: 'DEBUG' | 'INFO' | 'WARNING' | 'ERROR' | 'CRITICAL';
  message: string;
  [key: string]: any;
}

export class Logger {
  private metadata: any;

  constructor(private serviceName: string) {
    this.metadata = {
      resource: {
        type: 'cloud_run_revision',
        labels: {
          service_name: serviceName,
          revision_name: process.env.K_REVISION || 'unknown',
          location: process.env.CLOUD_RUN_REGION || 'unknown',
        },
      },
    };
  }

  private async write(entry: LogEntry) {
    const logEntry = log.entry(this.metadata, {
      severity: entry.severity,
      message: entry.message,
      timestamp: new Date().toISOString(),
      ...entry,
    });

    await log.write(logEntry);
  }

  info(message: string, data?: any) {
    this.write({ severity: 'INFO', message, ...data });
  }

  error(message: string, error?: Error, data?: any) {
    this.write({
      severity: 'ERROR',
      message,
      error: {
        message: error?.message,
        stack: error?.stack,
        name: error?.name,
      },
      ...data,
    });
  }

  warn(message: string, data?: any) {
    this.write({ severity: 'WARNING', message, ...data });
  }
}

export const logger = new Logger('api-service');
```

### Cloud Trace Integration

```typescript
// src/tracing.ts
import { TraceExporter } from '@google-cloud/opentelemetry-cloud-trace-exporter';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { SimpleSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { ExpressInstrumentation } from '@opentelemetry/instrumentation-express';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { registerInstrumentations } from '@opentelemetry/instrumentation';

export function setupTracing() {
  const provider = new NodeTracerProvider();

  const exporter = new TraceExporter();
  provider.addSpanProcessor(new SimpleSpanProcessor(exporter));

  provider.register();

  registerInstrumentations({
    instrumentations: [
      new HttpInstrumentation(),
      new ExpressInstrumentation(),
    ],
  });
}
```

### SLO Monitoring with Terraform

```hcl
# terraform/monitoring.tf

# Custom service for SLO tracking
resource "google_monitoring_custom_service" "app" {
  service_id   = "api-service"
  display_name = "API Service"
}

# SLO: 99.9% availability
resource "google_monitoring_slo" "availability" {
  service      = google_monitoring_custom_service.app.service_id
  slo_id       = "availability-slo"
  display_name = "99.9% Availability"

  goal                = 0.999
  rolling_period_days = 30

  request_based_sli {
    good_total_ratio {
      total_service_filter = join(" AND ", [
        "metric.type=\"run.googleapis.com/request_count\"",
        "resource.type=\"cloud_run_revision\"",
        "resource.label.service_name=\"${var.service_name}\"",
      ])

      good_service_filter = join(" AND ", [
        "metric.type=\"run.googleapis.com/request_count\"",
        "resource.type=\"cloud_run_revision\"",
        "resource.label.service_name=\"${var.service_name}\"",
        "metric.label.response_code_class=\"2xx\"",
      ])
    }
  }
}

# SLO: 95% of requests under 500ms
resource "google_monitoring_slo" "latency" {
  service      = google_monitoring_custom_service.app.service_id
  slo_id       = "latency-slo"
  display_name = "95% requests under 500ms"

  goal                = 0.95
  rolling_period_days = 30

  request_based_sli {
    distribution_cut {
      distribution_filter = join(" AND ", [
        "metric.type=\"run.googleapis.com/request_latencies\"",
        "resource.type=\"cloud_run_revision\"",
        "resource.label.service_name=\"${var.service_name}\"",
      ])

      range {
        max = 500  # 500ms
      }
    }
  }
}

# Alert on SLO burn rate
resource "google_monitoring_alert_policy" "slo_burn" {
  display_name = "SLO Burn Rate Alert"
  combiner     = "OR"

  conditions {
    display_name = "Fast burn rate"

    condition_threshold {
      filter = join(" AND ", [
        "select_slo_burn_rate(\"${google_monitoring_slo.availability.id}\", 3600)",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 10
      duration        = "300s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.pagerduty.id]

  alert_strategy {
    auto_close = "604800s"  # 7 days
  }
}
```

### Error Reporting Integration

```typescript
// src/error-reporting.ts
import { ErrorReporting } from '@google-cloud/error-reporting';

const errors = new ErrorReporting({
  projectId: process.env.GCP_PROJECT_ID,
  reportMode: 'production',
  serviceContext: {
    service: 'api-service',
    version: process.env.K_REVISION || 'unknown',
  },
});

export function reportError(error: Error, request?: any) {
  errors.report(error, {
    user: request?.user?.id,
    httpRequest: request ? {
      method: request.method,
      url: request.url,
      userAgent: request.get('user-agent'),
      referrer: request.get('referrer'),
      remoteIp: request.ip,
    } : undefined,
  });
}
```

---

## Cloud Build & CI/CD

### Multi-Step Cloud Build Pipeline

```yaml
# cloudbuild.yaml
steps:
  # Install dependencies
  - name: 'node:20'
    entrypoint: 'npm'
    args: ['ci']

  # Run tests
  - name: 'node:20'
    entrypoint: 'npm'
    args: ['test']
    env:
      - 'NODE_ENV=test'

  # Build Docker image
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - 'gcr.io/$PROJECT_ID/api:$COMMIT_SHA'
      - '-t'
      - 'gcr.io/$PROJECT_ID/api:latest'
      - '.'

  # Push to Container Registry
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - 'gcr.io/$PROJECT_ID/api:$COMMIT_SHA'

  # Deploy to Cloud Run
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'gcloud'
    args:
      - 'run'
      - 'deploy'
      - 'api-service'
      - '--image=gcr.io/$PROJECT_ID/api:$COMMIT_SHA'
      - '--region=asia-southeast1'
      - '--platform=managed'
      - '--quiet'

images:
  - 'gcr.io/$PROJECT_ID/api:$COMMIT_SHA'
  - 'gcr.io/$PROJECT_ID/api:latest'

options:
  machineType: 'E2_HIGHCPU_8'
  logging: CLOUD_LOGGING_ONLY

timeout: '1200s'  # 20 minutes
```

### Cloud Build Trigger

```hcl
# terraform/cloud-build.tf
resource "google_cloudbuild_trigger" "deploy" {
  name     = "deploy-on-push"
  location = var.region

  github {
    owner = var.github_owner
    name  = var.github_repo

    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _REGION  = var.region
    _SERVICE = "api-service"
  }

  service_account = google_service_account.cloud_build.id
}
```

---

## Eventarc Architecture

### Audit Log Triggers

```hcl
# terraform/eventarc.tf

# Trigger on Cloud Storage object creation
resource "google_eventarc_trigger" "storage_trigger" {
  name     = "storage-upload-trigger"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.uploads.name
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.processor.name
      region  = var.region
    }
  }

  service_account = google_service_account.eventarc.email
}

# Trigger on Cloud SQL instance changes (via Audit Logs)
resource "google_eventarc_trigger" "cloudsql_audit_trigger" {
  name     = "cloudsql-change-trigger"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }

  matching_criteria {
    attribute = "serviceName"
    value     = "sqladmin.googleapis.com"
  }

  matching_criteria {
    attribute = "methodName"
    value     = "cloudsql.instances.update"
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.audit_processor.name
      region  = var.region
    }
  }

  service_account = google_service_account.eventarc.email
}

# Direct event trigger (Pub/Sub)
resource "google_eventarc_trigger" "pubsub_trigger" {
  name     = "orders-trigger"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }

  transport {
    pubsub {
      topic = google_pubsub_topic.orders.id
    }
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.order_processor.name
      region  = var.region
      path    = "/process-order"
    }
  }

  service_account = google_service_account.eventarc.email
}
```

### Event Handler (Cloud Run)

```typescript
// src/eventarc-handler.ts
import { Request, Response } from 'express';

interface CloudEvent {
  specversion: string;
  type: string;
  source: string;
  subject?: string;
  id: string;
  time: string;
  datacontenttype?: string;
  data: any;
}

export async function handleStorageEvent(req: Request, res: Response) {
  const cloudEvent: CloudEvent = req.body;

  console.log('Received CloudEvent:', {
    id: cloudEvent.id,
    type: cloudEvent.type,
    source: cloudEvent.source,
  });

  const { bucket, name, contentType } = cloudEvent.data;
  console.log(`New file: gs://${bucket}/${name} (${contentType})`);

  if (contentType.startsWith('image/')) {
    await processImage(bucket, name);
  } else if (contentType === 'application/pdf') {
    await processPDF(bucket, name);
  }

  res.status(200).send({ processed: true });
}

export async function handleAuditLogEvent(req: Request, res: Response) {
  const cloudEvent: CloudEvent = req.body;
  const auditLog = cloudEvent.data.protoPayload;

  console.log('Audit log received:', {
    serviceName: auditLog.serviceName,
    methodName: auditLog.methodName,
    resourceName: auditLog.resourceName,
    principal: auditLog.authenticationInfo?.principalEmail,
  });

  if (auditLog.methodName.includes('delete')) {
    await sendAlert({
      type: 'SENSITIVE_OPERATION',
      operation: auditLog.methodName,
      user: auditLog.authenticationInfo?.principalEmail,
      resource: auditLog.resourceName,
    });
  }

  res.status(200).send({ acknowledged: true });
}
```

---

## Cost Optimization

### Committed Use Discounts

```hcl
# terraform/cuds.tf
resource "google_billing_budget" "cud_coverage" {
  billing_account = var.billing_account
  display_name    = "CUD Coverage Monitor"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "10000"
    }
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }
}
```

### Cost Optimization Best Practices

```bash
# Enable Active Assist recommendations
gcloud recommender recommendations list \
  --project=${PROJECT_ID} \
  --location=global \
  --recommender=google.compute.commitment.UsageCommitmentRecommender

# Apply rightsizing recommendations
gcloud recommender recommendations describe RECOMMENDATION_ID \
  --project=${PROJECT_ID} \
  --location=global \
  --recommender=google.compute.instance.MachineTypeRecommender

# Scale Cloud Run to zero for dev/staging
gcloud run services update my-service \
  --region asia-southeast1 \
  --min-instances 0

# Use Cloud Storage lifecycle management
gsutil lifecycle set lifecycle.json gs://my-bucket
```

---

## Terraform Patterns

### Remote State in GCS

```hcl
# terraform/backend.tf
terraform {
  backend "gcs" {
    bucket = "my-project-terraform-state"
    prefix = "terraform/state"
  }

  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}
```

### Module Structure

```
terraform/
  modules/
    cloud-run-service/
      main.tf
      variables.tf
      outputs.tf
    vpc-network/
      main.tf
      variables.tf
      outputs.tf
    cloudsql/
      main.tf
      variables.tf
      outputs.tf
  environments/
    production/
      main.tf
      terraform.tfvars
      backend.tf
    staging/
      main.tf
      terraform.tfvars
      backend.tf
    dev/
      main.tf
      terraform.tfvars
      backend.tf
  global/
    iam.tf
    projects.tf
    org-policies.tf
```

---

## Best Practices

1. **SLO-based alerting over threshold-based** -- Define error budget burn rate alerts instead of static thresholds. This reduces alert noise and focuses on customer impact.

2. **Structured logging everywhere** -- Use JSON structured logs with severity, trace ID, and request context. Cloud Logging automatically indexes structured fields.

3. **OpenTelemetry for distributed tracing** -- Use the Cloud Trace exporter with OpenTelemetry for auto-instrumented distributed traces across services.

4. **Cloud Build with dedicated service accounts** -- Never use the default Cloud Build service account. Create dedicated SAs with least-privilege roles.

5. **Eventarc for event-driven architecture** -- Use Eventarc to decouple services with Cloud Events. It supports direct events, Audit Logs, and Pub/Sub sources.

6. **Terraform module per resource type** -- Create reusable modules for Cloud Run, Cloud SQL, and VPC. Use environment-specific tfvars files.

7. **Enable GCS versioning for Terraform state** -- Always enable object versioning on the state bucket for state recovery.

8. **Use Active Assist for cost recommendations** -- Regularly review commitment, rightsizing, and idle resource recommendations.

---

## Anti-Patterns

1. **Alerting on every error** -- Alerting on individual errors creates noise. Alert on error rate or SLO burn rate instead.

2. **Cloud Build without timeout** -- Default timeout is 10 minutes. Set explicit timeouts to prevent runaway builds and costs.

3. **Storing Terraform state locally** -- Always use a remote backend (GCS) with locking. Local state is not shareable and is at risk of loss.

4. **Using Eventarc without idempotent handlers** -- Events can be delivered more than once. Always design handlers to be idempotent.

5. **Ignoring billing budgets** -- Set billing budgets with alerts at 50%, 75%, and 100% to prevent unexpected charges.

6. **Not tagging resources for cost allocation** -- Use consistent labels across all resources for cost attribution by team, environment, and project.

---

## Common CLI Commands

```bash
# Cloud Monitoring
gcloud monitoring dashboards list
gcloud monitoring policies list
gcloud monitoring channel-descriptors list

# Cloud Logging
gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" --limit=50
gcloud logging sinks list
gcloud logging metrics list

# Cloud Build
gcloud builds list --region=REGION
gcloud builds log BUILD_ID --region=REGION
gcloud builds triggers list --region=REGION
gcloud builds submit --config=cloudbuild.yaml

# Eventarc
gcloud eventarc triggers list --location=REGION
gcloud eventarc triggers describe TRIGGER --location=REGION

# Cost & Billing
gcloud billing accounts list
gcloud billing budgets list --billing-account=ACCOUNT_ID
gcloud recommender recommendations list --project=PROJECT --location=global --recommender=RECOMMENDER

# Terraform
terraform init
terraform plan -var-file=environments/production/terraform.tfvars
terraform apply -var-file=environments/production/terraform.tfvars
terraform state list
```

---

## Sources & References

- [SLO monitoring concepts](https://docs.google.com/stackdriver/docs/solutions/slo-monitoring)
- [Cloud Monitoring best practices](https://cloud.google.com/monitoring)
- [Cloud Build triggers](https://docs.google.com/build/docs/automating-builds/create-manage-triggers)
- [Eventarc event-driven architectures](https://cloud.google.com/eventarc/docs/event-driven-architectures)
- [Route audit log events to Cloud Run](https://docs.google.com/eventarc/standard/docs/run/route-trigger-cloud-audit-logs)
- [Eventarc Documentation](https://cloud.google.com/eventarc/docs)
- [Committed use discounts overview](https://docs.google.com/compute/docs/instances/committed-use-discounts-overview)
- [GCP cost optimization strategies](https://www.cloudkeeper.com/insights/blog/gcp-cost-optimization-top-10-effective-strategies-maximum-impact)
- [Cost Optimization Best Practices](https://cloud.google.com/architecture/framework/cost-optimization)
- [Terraform GCS backend](https://developer.hashicorp.com/terraform/language/backend/gcs)
- [Terraform GCP best practices](https://cloud.google.com/docs/terraform/best-practices/root-modules)
- [Cloud Architecture Center](https://cloud.google.com/architecture)
