---
name: gcloud-security
description: Production-grade GCP security patterns -- IAM, Workload Identity Federation, Secret Manager, KMS, VPC Service Controls, Cloud Armor, and Org Policies
---

# GCP Security -- Staff Engineer Patterns

Production-ready patterns for IAM (Workload Identity Federation, conditions, cross-project), Secret Manager (rotation, Pub/Sub notifications), KMS (customer-managed keys), VPC networking (Private Service Connect, Cloud NAT, firewall rules), Cloud Armor (WAF, rate limiting), and Organization Policies on Google Cloud Platform.

## Table of Contents
1. [IAM & Workload Identity](#iam--workload-identity)
2. [Secret Management](#secret-management)
3. [VPC Networking](#vpc-networking)
4. [Cloud Armor WAF](#cloud-armor-waf)
5. [Best Practices](#best-practices)
6. [Anti-Patterns](#anti-patterns)
7. [Common CLI Commands](#common-cli-commands)
8. [Sources & References](#sources--references)

---

## IAM & Workload Identity

### Workload Identity Federation for GitHub Actions

Eliminates the need for service account keys in CI/CD pipelines by using OIDC federation.

```hcl
# terraform/workload-identity-federation.tf

# Create a Workload Identity Pool
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "Identity pool for GitHub Actions CI/CD"
}

# Create a Workload Identity Pool Provider
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Actions Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow GitHub repo to impersonate the service account
resource "google_service_account_iam_member" "github_deployer" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# Service account for deployments
resource "google_service_account" "deployer" {
  account_id   = "github-deployer"
  display_name = "GitHub Actions Deployer"
}

resource "google_project_iam_member" "deployer_roles" {
  for_each = toset([
    "roles/run.developer",
    "roles/artifactregistry.writer",
    "roles/iam.serviceAccountUser",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.deployer.email}"
}
```

### GitHub Actions Workflow with OIDC

```yaml
# .github/workflows/deploy.yml
name: Deploy to Cloud Run

on:
  push:
    branches: [main]

env:
  PROJECT_ID: my-project
  REGION: asia-southeast1
  SERVICE: api-service
  WORKLOAD_IDENTITY_PROVIDER: projects/123456/locations/global/workloadIdentityPools/github-actions/providers/github-provider
  SERVICE_ACCOUNT: github-deployer@my-project.iam.gserviceaccount.com

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - id: 'auth'
        name: 'Authenticate to Google Cloud'
        uses: 'google-github-actions/auth@v2'
        with:
          workload_identity_provider: ${{ env.WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ env.SERVICE_ACCOUNT }}
          token_format: 'access_token'

      - name: 'Set up Cloud SDK'
        uses: 'google-github-actions/setup-gcloud@v2'

      - name: 'Build and push image'
        run: |
          gcloud builds submit \
            --tag gcr.io/${{ env.PROJECT_ID }}/${{ env.SERVICE }}:${{ github.sha }}

      - name: 'Deploy to Cloud Run'
        run: |
          gcloud run deploy ${{ env.SERVICE }} \
            --image gcr.io/${{ env.PROJECT_ID }}/${{ env.SERVICE }}:${{ github.sha }} \
            --region ${{ env.REGION }} \
            --platform managed
```

### IAM Conditions

```hcl
# terraform/iam-conditions.tf

# Grant access only during business hours
resource "google_project_iam_member" "developer_business_hours" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "user:developer@example.com"

  condition {
    title       = "business_hours_only"
    description = "Access only during business hours (9-5 Mon-Fri UTC)"
    expression  = <<-EOT
      request.time.getHours("UTC") >= 9 &&
      request.time.getHours("UTC") < 17 &&
      request.time.getDayOfWeek("UTC") >= 1 &&
      request.time.getDayOfWeek("UTC") <= 5
    EOT
  }
}

# Grant access only from specific IP ranges
resource "google_project_iam_member" "developer_ip_restricted" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "user:admin@example.com"

  condition {
    title       = "office_ip_only"
    description = "Access only from office IP range"
    expression  = "origin.ip in ['203.0.113.0/24', '198.51.100.0/24']"
  }
}

# Temporary access (expires after date)
resource "google_project_iam_member" "contractor_temporary" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "user:contractor@example.com"

  condition {
    title       = "temporary_access"
    description = "Access expires on 2026-12-31"
    expression  = "request.time < timestamp('2026-12-31T00:00:00Z')"
  }
}
```

---

## Secret Management

### Secret Manager with Rotation

```hcl
# terraform/secrets.tf
resource "google_secret_manager_secret" "database_password" {
  secret_id = "database-password"

  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    }
  }

  rotation {
    next_rotation_time = "2026-03-01T00:00:00Z"
    rotation_period    = "2592000s"  # 30 days
  }

  topics {
    name = google_pubsub_topic.secret_rotation.id
  }

  labels = {
    environment = "production"
    app         = "api-service"
  }
}

resource "google_secret_manager_secret_version" "database_password" {
  secret      = google_secret_manager_secret.database_password.id
  secret_data = random_password.db_password.result
}

# IAM access
resource "google_secret_manager_secret_iam_member" "app_access" {
  secret_id = google_secret_manager_secret.database_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# Pub/Sub topic for rotation notifications
resource "google_pubsub_topic" "secret_rotation" {
  name = "secret-rotation-events"
}

# Cloud Function for automatic rotation
resource "google_cloudfunctions2_function" "rotate_secret" {
  name     = "rotate-database-password"
  location = var.region

  build_config {
    runtime     = "nodejs20"
    entry_point = "rotateSecret"
    source {
      storage_source {
        bucket = google_storage_bucket.functions.name
        object = google_storage_bucket_object.rotation_function.name
      }
    }
  }

  service_config {
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.rotation_function.email

    secret_environment_variables {
      key        = "DB_CONNECTION"
      project_id = var.project_id
      secret     = google_secret_manager_secret.database_connection.secret_id
      version    = "latest"
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.secret_rotation.id
  }
}
```

### Accessing Secrets in Applications

```typescript
// src/secrets.ts
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const client = new SecretManagerServiceClient();

// In-memory cache with TTL
const secretCache = new Map<string, { value: string; expiresAt: number }>();

export async function getSecret(secretName: string): Promise<string> {
  const cached = secretCache.get(secretName);

  if (cached && cached.expiresAt > Date.now()) {
    return cached.value;
  }

  const [version] = await client.accessSecretVersion({
    name: `projects/${process.env.GCP_PROJECT_ID}/secrets/${secretName}/versions/latest`,
  });

  const value = version.payload?.data?.toString() || '';

  // Cache for 5 minutes
  secretCache.set(secretName, {
    value,
    expiresAt: Date.now() + 5 * 60 * 1000,
  });

  return value;
}
```

---

## VPC Networking

### VPC with Private Service Connect

```hcl
# terraform/networking.tf

# Custom VPC
resource "google_compute_network" "vpc" {
  name                    = "production-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Subnets with secondary ranges for GKE
resource "google_compute_subnetwork" "private" {
  name          = "private-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud NAT for outbound internet access
resource "google_compute_router" "router" {
  name    = "nat-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name   = "nat-gateway"
  router = google_compute_router.router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private Service Connect for managed services
resource "google_compute_global_address" "private_service_connect" {
  name          = "psc-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_connect.name]
}
```

---

## Cloud Armor WAF

### Security Policy with Rate Limiting and OWASP Protection

```hcl
# terraform/cloud-armor.tf
resource "google_compute_security_policy" "policy" {
  name = "cloud-armor-policy"

  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }

      ban_duration_sec = 600
    }
  }

  # Block SQL injection
  rule {
    action   = "deny(403)"
    priority = "2000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
  }

  # Block XSS
  rule {
    action   = "deny(403)"
    priority = "3000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
  }

  # Allow all other traffic
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
```

### Cloud CDN with Security Policy

```hcl
# terraform/cdn.tf
resource "google_compute_backend_bucket" "cdn_backend" {
  name        = "cdn-backend"
  bucket_name = google_storage_bucket.static_assets.name
  enable_cdn  = true

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    client_ttl        = 3600
    default_ttl       = 3600
    max_ttl           = 86400
    negative_caching  = true
    serve_while_stale = 86400

    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = false
    }
  }
}

resource "google_compute_url_map" "cdn" {
  name            = "cdn-url-map"
  default_service = google_compute_backend_bucket.cdn_backend.id
}

resource "google_compute_target_https_proxy" "cdn" {
  name             = "cdn-https-proxy"
  url_map          = google_compute_url_map.cdn.id
  ssl_certificates = [google_compute_managed_ssl_certificate.cdn.id]
}

resource "google_compute_global_forwarding_rule" "cdn" {
  name       = "cdn-forwarding-rule"
  target     = google_compute_target_https_proxy.cdn.id
  port_range = "443"
  ip_address = google_compute_global_address.cdn.address
}

resource "google_compute_managed_ssl_certificate" "cdn" {
  name = "cdn-cert"
  managed {
    domains = ["cdn.example.com"]
  }
}
```

---

## Best Practices

1. **Workload Identity Federation over service account keys** -- Never export JSON key files. Use OIDC federation for external identities (GitHub, GitLab, AWS) and Workload Identity for GKE.

2. **IAM conditions for temporal and network-based access** -- Use CEL expressions for time-based, IP-based, and resource-based access restrictions.

3. **Secret Manager with automatic rotation** -- Configure rotation schedules and Pub/Sub notifications to trigger rotation Cloud Functions.

4. **Least-privilege service accounts** -- Create dedicated service accounts per workload with only the required roles. Never use the default compute service account.

5. **Private networking for all managed services** -- Disable public IPs on Cloud SQL, GKE nodes, and Cloud Run. Use VPC connectors, Private Service Connect, or VPC peering.

6. **Cloud Armor for all external load balancers** -- Enable preconfigured WAF rules (SQLi, XSS) and rate limiting on all public-facing services.

7. **Enable VPC Flow Logs** -- Log network traffic for auditing and troubleshooting. Use sampling to control costs.

8. **Organization policies for guardrails** -- Enforce constraints like `constraints/compute.disableSerialPortAccess` and `constraints/iam.disableServiceAccountKeyCreation` at the org level.

---

## Anti-Patterns

1. **Using service account keys in CI/CD** -- Keys are long-lived credentials that can be leaked. Use Workload Identity Federation with OIDC tokens instead.

2. **Granting roles/editor or roles/owner** -- These are overly permissive. Use predefined roles like `roles/run.developer` or `roles/cloudsql.client`.

3. **Secrets in environment variables or source code** -- Use Secret Manager and mount secrets at runtime. Never commit secrets to git.

4. **Public Cloud SQL instances** -- Always use private IP with VPC peering. If external access is needed, use Cloud SQL Auth Proxy with IAM authentication.

5. **Disabling VPC Flow Logs in production** -- Flow logs are essential for security auditing, incident response, and compliance.

6. **Single VPC for all environments** -- Use separate VPCs or projects per environment (dev, staging, production) with VPC peering where needed.

---

## Common CLI Commands

```bash
# IAM
gcloud iam service-accounts list --project=PROJECT
gcloud iam service-accounts create SA_NAME --display-name="Display Name"
gcloud projects get-iam-policy PROJECT --format=json
gcloud projects add-iam-policy-binding PROJECT --member=MEMBER --role=ROLE

# Workload Identity Federation
gcloud iam workload-identity-pools list --location=global
gcloud iam workload-identity-pools providers list --workload-identity-pool=POOL --location=global

# Secret Manager
gcloud secrets list
gcloud secrets create SECRET_NAME --replication-policy=automatic
gcloud secrets versions add SECRET_NAME --data-file=./secret.txt
gcloud secrets versions access latest --secret=SECRET_NAME

# VPC
gcloud compute networks list
gcloud compute networks subnets list --network=VPC_NAME
gcloud compute firewall-rules list --filter="network=VPC_NAME"

# Cloud Armor
gcloud compute security-policies list
gcloud compute security-policies describe POLICY_NAME
gcloud compute security-policies rules list --security-policy=POLICY_NAME
```

---

## Sources & References

- [Workload Identity Federation best practices](https://docs.google.com/iam/docs/best-practices-for-using-workload-identity-federation)
- [Best practices for managing service account keys](https://docs.google.com/iam/docs/best-practices-for-managing-service-account-keys)
- [Secret Manager best practices](https://docs.google.com/secret-manager/docs/best-practices)
- [Secret rotation schedules](https://docs.google.com/secret-manager/docs/rotation-recommendations)
- [Private Service Connect](https://cloud.google.com/vpc/docs/private-service-connect)
- [Cloud NAT overview](https://cloud.google.com/nat/docs/overview)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
- [Cloud Armor documentation](https://cloud.google.com/armor/docs)
- [VPC Flow Logs](https://cloud.google.com/vpc/docs/flow-logs)
- [Organization Policy constraints](https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints)
