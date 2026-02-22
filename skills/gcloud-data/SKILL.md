---
name: gcloud-data
description: Production-grade GCP data patterns -- Cloud SQL, AlloyDB, Firestore, Pub/Sub, Cloud Storage, BigQuery, and Memorystore
---

# GCP Data -- Staff Engineer Patterns

Production-ready patterns for Cloud SQL (HA, AlloyDB), Firestore (distributed counters, transactions), Pub/Sub (ordering, dead-letter, BigQuery subscriptions), Cloud Storage (lifecycle, signed URLs), BigQuery (materialized views, streaming), and Memorystore on Google Cloud Platform.

## Table of Contents
1. [Cloud SQL & AlloyDB](#cloud-sql--alloydb)
2. [Firestore Patterns](#firestore-patterns)
3. [Pub/Sub Event Patterns](#pubsub-event-patterns)
4. [Cloud Storage Patterns](#cloud-storage-patterns)
5. [BigQuery Patterns](#bigquery-patterns)
6. [Best Practices](#best-practices)
7. [Anti-Patterns](#anti-patterns)
8. [Common CLI Commands](#common-cli-commands)
9. [Sources & References](#sources--references)

---

## Cloud SQL & AlloyDB

### Cloud SQL with High Availability

```hcl
# terraform/cloudsql.tf
resource "google_sql_database_instance" "primary" {
  name             = "production-db"
  database_version = "POSTGRES_16"
  region           = var.region
  project          = var.project_id

  settings {
    tier              = "db-custom-4-16384"  # 4 vCPU, 16GB RAM
    availability_type = "REGIONAL"           # HA with automatic failover

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
      }
    }

    maintenance_window {
      day          = 7  # Sunday
      hour         = 4
      update_track = "stable"
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
      require_ssl     = true
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 4096
      record_application_tags = true
      record_client_address   = true
    }

    database_flags {
      name  = "max_connections"
      value = "200"
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"  # Log queries > 1s
    }
  }

  deletion_protection = true
}

# Read replica for read-heavy workloads
resource "google_sql_database_instance" "read_replica" {
  name                 = "production-db-replica"
  master_instance_name = google_sql_database_instance.primary.name
  database_version     = "POSTGRES_16"
  region               = var.region

  settings {
    tier              = "db-custom-4-16384"
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
      require_ssl     = true
    }
  }

  replica_configuration {
    failover_target = false
  }
}
```

### AlloyDB for High-Performance Workloads

```hcl
# terraform/alloydb.tf
resource "google_alloydb_cluster" "primary" {
  cluster_id = "production-cluster"
  location   = var.region
  project    = var.project_id

  network_config {
    network = google_compute_network.vpc.id
  }

  automated_backup_policy {
    location      = var.region
    backup_window = "1800s"

    weekly_schedule {
      days_of_week = ["MONDAY", "WEDNESDAY", "FRIDAY"]

      start_times {
        hours   = 3
        minutes = 0
      }
    }

    quantity_based_retention {
      count = 14
    }

    enabled = true
  }

  continuous_backup_config {
    enabled              = true
    recovery_window_days = 14
  }
}

resource "google_alloydb_instance" "primary" {
  cluster       = google_alloydb_cluster.primary.name
  instance_id   = "primary-instance"
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = 8
  }
}

# Read pool for analytical queries
resource "google_alloydb_instance" "read_pool" {
  cluster       = google_alloydb_cluster.primary.name
  instance_id   = "read-pool"
  instance_type = "READ_POOL"

  read_pool_config {
    node_count = 2
  }

  machine_config {
    cpu_count = 4
  }
}
```

---

## Firestore Patterns

### Distributed Counters

Firestore limits writes to 1 per second per document. Distributed counters shard writes across multiple documents.

```typescript
import { getFirestore, doc, setDoc, increment, collection, getDocs } from 'firebase/firestore';

const SHARD_COUNT = 10;

async function incrementCounter(counterId: string) {
  const db = getFirestore();
  const shardId = Math.floor(Math.random() * SHARD_COUNT);
  const shardRef = doc(db, `counters/${counterId}/shards/${shardId}`);

  await setDoc(shardRef, { count: increment(1) }, { merge: true });
}

async function getCounterValue(counterId: string): Promise<number> {
  const db = getFirestore();
  const shardsSnapshot = await getDocs(
    collection(db, `counters/${counterId}/shards`)
  );

  let total = 0;
  shardsSnapshot.forEach(doc => {
    total += doc.data().count || 0;
  });

  return total;
}
```

### Transactions for Atomic Operations

```typescript
import { getFirestore, doc, runTransaction, serverTimestamp } from 'firebase/firestore';

async function transferCredits(fromId: string, toId: string, amount: number) {
  const db = getFirestore();
  const fromRef = doc(db, 'accounts', fromId);
  const toRef = doc(db, 'accounts', toId);

  await runTransaction(db, async (transaction) => {
    const fromSnap = await transaction.get(fromRef);
    const toSnap = await transaction.get(toRef);

    const fromBalance = fromSnap.data()?.balance || 0;
    if (fromBalance < amount) {
      throw new Error('Insufficient balance');
    }

    transaction.update(fromRef, {
      balance: fromBalance - amount,
      updatedAt: serverTimestamp(),
    });

    transaction.update(toRef, {
      balance: (toSnap.data()?.balance || 0) + amount,
      updatedAt: serverTimestamp(),
    });
  });
}
```

---

## Pub/Sub Event Patterns

### Ordered Messages with Dead Letter

```hcl
# terraform/pubsub.tf
resource "google_pubsub_topic" "orders" {
  name = "orders"

  message_retention_duration = "604800s"  # 7 days

  schema_settings {
    schema   = google_pubsub_schema.order.id
    encoding = "JSON"
  }
}

resource "google_pubsub_schema" "order" {
  name       = "order-schema"
  type       = "AVRO"
  definition = <<EOT
{
  "type": "record",
  "name": "Order",
  "fields": [
    {"name": "order_id", "type": "string"},
    {"name": "user_id", "type": "string"},
    {"name": "total", "type": "double"},
    {"name": "created_at", "type": "string"}
  ]
}
EOT
}

resource "google_pubsub_subscription" "orders_processor" {
  name  = "orders-processor"
  topic = google_pubsub_topic.orders.id

  ack_deadline_seconds = 60

  # Enable ordering by key
  enable_message_ordering = true

  # Dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_dlq.id
    max_delivery_attempts = 5
  }

  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Push to Cloud Run
  push_config {
    push_endpoint = google_cloud_run_v2_service.order_processor.uri

    oidc_token {
      service_account_email = google_service_account.pubsub_invoker.email
    }
  }

  # Exactly-once delivery
  enable_exactly_once_delivery = true
}

# Dead Letter Queue
resource "google_pubsub_topic" "orders_dlq" {
  name = "orders-dlq"
}
```

### BigQuery Subscription

Route Pub/Sub messages directly to BigQuery for analytics without intermediate processing.

```hcl
resource "google_pubsub_subscription" "events_to_bq" {
  name  = "events-to-bigquery"
  topic = google_pubsub_topic.events.id

  bigquery_config {
    table            = "${var.project_id}.analytics.raw_events"
    use_table_schema = true
    write_metadata   = true
    drop_unknown_fields = true
  }
}
```

### Publishing with Ordering Keys

```typescript
import { PubSub } from '@google-cloud/pubsub';

const pubsub = new PubSub();

async function publishOrderEvent(orderId: string, event: any) {
  const topic = pubsub.topic('orders', {
    enableMessageOrdering: true,
    batching: {
      maxMessages: 100,
      maxMilliseconds: 10,
    },
  });

  await topic.publishMessage({
    data: Buffer.from(JSON.stringify(event)),
    orderingKey: orderId,  // All events for same order processed in order
    attributes: {
      eventType: event.type,
      version: '1.0',
    },
  });
}
```

---

## Cloud Storage Patterns

### Signed URLs for Secure Uploads

```typescript
import { Storage } from '@google-cloud/storage';

const storage = new Storage();

export async function generateUploadUrl(
  bucketName: string,
  fileName: string,
  contentType: string
): Promise<string> {
  const bucket = storage.bucket(bucketName);
  const file = bucket.file(fileName);

  const [url] = await file.getSignedUrl({
    version: 'v4',
    action: 'write',
    expires: Date.now() + 15 * 60 * 1000,  // 15 minutes
    contentType,
    extensionHeaders: {
      'x-goog-content-length-range': '0,10485760',  // Max 10MB
    },
  });

  return url;
}

export async function generateDownloadUrl(
  bucketName: string,
  fileName: string
): Promise<string> {
  const bucket = storage.bucket(bucketName);
  const file = bucket.file(fileName);

  const [url] = await file.getSignedUrl({
    version: 'v4',
    action: 'read',
    expires: Date.now() + 60 * 60 * 1000,  // 1 hour
  });

  return url;
}
```

### Lifecycle Management with Autoclass

```hcl
# terraform/storage.tf
resource "google_storage_bucket" "data" {
  name          = "my-project-data"
  location      = "ASIA"
  storage_class = "STANDARD"

  autoclass {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age                   = 365
      matches_storage_class = ["ARCHIVE"]
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age                   = 30
      matches_storage_class = ["STANDARD"]
    }
  }

  versioning {
    enabled = true
  }

  uniform_bucket_level_access {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.storage.id
  }

  cors {
    origin          = ["https://example.com"]
    method          = ["GET", "HEAD", "PUT", "POST"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  public_access_prevention = "enforced"
}

# Dual-region bucket with turbo replication
resource "google_storage_bucket" "critical_data" {
  name          = "my-project-critical-data"
  location      = "ASIA"
  storage_class = "STANDARD"

  custom_placement_config {
    data_locations = ["ASIA-SOUTHEAST1", "ASIA-NORTHEAST1"]
  }

  rpo = "ASYNC_TURBO"  # 15-minute RPO
}
```

---

## BigQuery Patterns

### Materialized Views for Performance

```sql
-- Base table: raw events
CREATE TABLE `analytics.raw_events` (
  event_id STRING NOT NULL,
  user_id STRING NOT NULL,
  event_type STRING NOT NULL,
  event_timestamp TIMESTAMP NOT NULL,
  properties JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(event_timestamp)
CLUSTER BY user_id, event_type;

-- Materialized view: hourly aggregates (auto-refreshed)
CREATE MATERIALIZED VIEW `analytics.hourly_events`
PARTITION BY DATE(event_hour)
CLUSTER BY event_type
AS
SELECT
  TIMESTAMP_TRUNC(event_timestamp, HOUR) AS event_hour,
  event_type,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_id) AS unique_users
FROM `analytics.raw_events`
GROUP BY event_hour, event_type;
```

### Streaming Inserts from Cloud Functions

```typescript
import { BigQuery } from '@google-cloud/bigquery';

const bigquery = new BigQuery();

interface Event {
  event_id: string;
  user_id: string;
  event_type: string;
  event_timestamp: string;
  properties: any;
}

export async function streamEventsToBigQuery(events: Event[]) {
  const dataset = bigquery.dataset('analytics');
  const table = dataset.table('raw_events');

  const rows = events.map(event => ({
    insertId: event.event_id,  // Deduplication key
    json: event,
  }));

  try {
    await table.insert(rows, {
      skipInvalidRows: false,
      ignoreUnknownValues: false,
    });
    console.log(`Inserted ${rows.length} rows`);
  } catch (error: any) {
    if (error.name === 'PartialFailureError') {
      console.error('Some rows failed:', error.errors);
    } else {
      throw error;
    }
  }
}
```

### Federated Queries (Cloud SQL)

```sql
-- Create external connection to Cloud SQL
CREATE EXTERNAL CONNECTION `us.cloudsql-connection`
  CONNECTION_TYPE = CLOUD_SQL_MYSQL
  CLOUDSQL_PROPERTIES = (
    INSTANCE_ID = 'my-project:us-central1:mysql-instance',
    DATABASE = 'mydb'
  )
  CREDENTIAL = (
    USERNAME = 'bigquery',
    PASSWORD = '<password>'
  );

-- Join BigQuery data with Cloud SQL data
SELECT
  bq_events.event_type,
  COUNT(*) AS event_count,
  sql_users.user_name
FROM
  `analytics.events` AS bq_events
INNER JOIN
  EXTERNAL_QUERY(
    'us.cloudsql-connection',
    'SELECT user_id, user_name FROM users WHERE active = true'
  ) AS sql_users
ON bq_events.user_id = sql_users.user_id
GROUP BY event_type, user_name;
```

---

## Best Practices

1. **Cloud SQL: Enable Query Insights** -- Captures query plans, latencies, and lock contention without manual configuration.

2. **Use AlloyDB for HTAP workloads** -- AlloyDB's columnar engine accelerates analytical queries 100x over standard PostgreSQL while maintaining OLTP performance.

3. **Firestore: Prefer subcollections over root collections** -- Subcollections naturally scope data and enable hierarchical security rules.

4. **Pub/Sub: Use ordering keys sparingly** -- Only enable message ordering when strict FIFO is required. Ordering keys limit throughput to a single partition.

5. **BigQuery: Partition by date and cluster by high-cardinality columns** -- Dramatically reduces query cost and latency by scanning less data.

6. **Cloud Storage: Enable Autoclass** -- Automatically transitions objects to optimal storage classes based on access patterns, eliminating manual lifecycle management.

7. **Use BigQuery subscriptions for analytics pipelines** -- Avoids maintaining intermediate Cloud Functions for simple Pub/Sub-to-BigQuery routing.

8. **Cloud SQL: Use Private IP only** -- Disable public IP and use VPC peering or Private Service Connect for database access.

---

## Anti-Patterns

1. **Using Firestore for joins-heavy relational data** -- Firestore is a document database. If your access patterns require complex joins, use Cloud SQL or AlloyDB.

2. **Pub/Sub without dead letter topics** -- Messages that consistently fail processing will block the subscription. Always configure a DLQ with a max delivery attempt limit.

3. **BigQuery: Using SELECT * in production queries** -- BigQuery charges by data scanned. Always select only the columns you need.

4. **Storing large blobs in Firestore** -- Document size limit is 1MB. Use Cloud Storage for files and store the reference URL in Firestore.

5. **Not using connection pooling for Cloud SQL** -- Direct connections exhaust the 200 connection default. Use Cloud SQL Auth Proxy or a connection pooler.

6. **Ignoring Pub/Sub message retention** -- Default retention is 7 days. Set `message_retention_duration` based on your recovery needs.

---

## Common CLI Commands

```bash
# Cloud SQL
gcloud sql instances list
gcloud sql instances describe INSTANCE
gcloud sql connect INSTANCE --user=postgres
gcloud sql databases create DB --instance=INSTANCE
gcloud sql backups list --instance=INSTANCE

# Firestore
gcloud firestore indexes list
gcloud firestore export gs://BUCKET/PATH
gcloud firestore import gs://BUCKET/PATH

# Pub/Sub
gcloud pubsub topics list
gcloud pubsub topics publish TOPIC --message='{"key":"value"}' --ordering-key=KEY
gcloud pubsub subscriptions list
gcloud pubsub subscriptions pull SUBSCRIPTION --auto-ack --limit=10
gcloud pubsub subscriptions seek SUBSCRIPTION --time=TIMESTAMP

# Cloud Storage
gsutil ls gs://BUCKET
gsutil cp FILE gs://BUCKET/PATH
gsutil lifecycle get gs://BUCKET
gsutil versioning get gs://BUCKET

# BigQuery
bq query --use_legacy_sql=false 'SELECT ...'
bq show --schema DATASET.TABLE
bq mk --table DATASET.TABLE schema.json
bq load --source_format=CSV DATASET.TABLE gs://BUCKET/FILE
```

---

## Sources & References

- [AlloyDB vs. Cloud SQL: engineering guide 2025](https://www.bytebase.com/blog/alloydb-vs-cloudsql/)
- [AlloyDB Documentation](https://cloud.google.com/alloydb/docs)
- [Cloud SQL Auth Proxy overview](https://cloud.google.com/alloydb/docs/auth-proxy/overview)
- [Firestore vs Cloud Spanner comparison](https://db-engines.com/en/system/Google+Cloud+Firestore%3BGoogle+Cloud+Spanner)
- [Pub/Sub ordering and filtering](https://docs.cloud.google.com/pubsub/docs/ordering)
- [Dead-letter topics](https://docs.cloud.google.com/pubsub/docs/dead-letter-topics)
- [BigQuery subscriptions](https://docs.cloud.google.com/pubsub/docs/bigquery)
- [Signed URLs](https://docs.cloud.google.com/storage/docs/access-control/signed-urls)
- [Storage lifecycle management](https://docs.cloud.google.com/storage/docs/lifecycle)
- [BigQuery materialized views](https://cloud.google.com/bigquery/docs/materialized-views-intro)
- [BigQuery BI Engine](https://cloud.google.com/bigquery/docs/bi-engine-intro)
- [Firestore Data Modeling](https://firebase.google.com/docs/firestore/data-model)
