---
name: flyio-core
description: Production-grade Fly.io core patterns -- Machines API, fly.toml configuration, multi-region architecture, databases, networking, and volumes
---

# Fly.io Core -- Staff Engineer Patterns

Production-ready patterns for Fly.io Machines API (auto start/stop/suspend, scale to zero), fly.toml configuration, multi-region architecture (fly-replay, read replicas), databases (Fly Postgres, LiteFS), networking (private .internal DNS, Flycast), and volumes.

## Table of Contents
1. [Machines API & Lifecycle](#machines-api--lifecycle)
2. [Multi-Region Patterns](#multi-region-patterns)
3. [Database Strategies](#database-strategies)
4. [Networking & Connectivity](#networking--connectivity)
5. [Volumes](#volumes)
6. [Best Practices](#best-practices)
7. [Anti-Patterns](#anti-patterns)
8. [Common CLI Commands](#common-cli-commands)
9. [Sources & References](#sources--references)

---

## Machines API & Lifecycle

### Machine States

Fly Machines transition through distinct lifecycle states:

- **created** -- Initial state after creation
- **started** -- Machine is running and ready
- **stopped** -- Gracefully stopped, no CPU/RAM charges
- **suspended** -- Memory/disk state preserved, faster resume than stopped
- **destroyed** -- Permanently deleted

### Auto Start/Stop Configuration

```toml
# fly.toml
[http_service]
  internal_port = 3000
  force_https = true

  # Auto-stop options: "off", "stop", "suspend"
  auto_stop_machines = "suspend"  # suspend is faster to resume
  auto_start_machines = true
  min_machines_running = 1  # Keep at least 1 running in primary region

  [http_service.concurrency]
    type = "requests"
    soft_limit = 200  # Start new machine when exceeded
    hard_limit = 250  # Reject requests when exceeded
```

**Suspended vs Stopped:**
- Suspended machines resume ~2-3x faster than stopped
- Suspended preserves memory state but requires more disk
- Use suspend for apps with slow startup or large in-memory caches
- Use stop for stateless apps or when disk space is limited

### Scale to Zero Pattern

```toml
[http_service]
  auto_stop_machines = "suspend"
  auto_start_machines = true
  min_machines_running = 0  # Scale to zero when idle
```

**Trade-offs:**
- Saves costs for low-traffic apps
- First request after idle incurs cold start (~1-5s)
- Not suitable for apps requiring immediate response times
- Perfect for development, staging, or bursty workloads

### Programmatic Machine Management

```javascript
// Using Fly Machines API
const createMachine = async (appName) => {
  const response = await fetch(
    `https://api.machines.dev/v1/apps/${appName}/machines`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${FLY_API_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        config: {
          image: 'registry.fly.io/my-app:latest',
          auto_destroy: true,
          restart: {
            policy: 'on-failure',
            max_retries: 3,
          },
          services: [{
            protocol: 'tcp',
            internal_port: 3000,
            ports: [{ port: 80, handlers: ['http'] }],
          }],
        },
      }),
    }
  );
  return response.json();
};
```

---

## Multi-Region Patterns

### Primary Region Writes with fly-replay

The `fly-replay` header forwards entire HTTP requests to the primary region, avoiding cross-region database connections.

```javascript
// Express.js middleware for fly-replay
app.use((req, res, next) => {
  const isPrimaryRegion = process.env.FLY_REGION === process.env.PRIMARY_REGION;
  const isWriteRequest = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method);

  if (isWriteRequest && !isPrimaryRegion) {
    res.set('fly-replay', `region=${process.env.PRIMARY_REGION}`);
    return res.status(307).end();
  }

  next();
});
```

```ruby
# Rails middleware for fly-replay
class FlyReplayMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if write_request?(request) && !primary_region?
      headers = { 'fly-replay' => "region=#{ENV['PRIMARY_REGION']}" }
      [307, headers, []]
    else
      @app.call(env)
    end
  end

  private

  def write_request?(request)
    %w[POST PUT PATCH DELETE].include?(request.request_method)
  end

  def primary_region?
    ENV['FLY_REGION'] == ENV['PRIMARY_REGION']
  end
end
```

### Multi-Region Deployment Configuration

```toml
# fly.toml
app = "my-app"
primary_region = "sin"  # Singapore

[env]
  PRIMARY_REGION = "sin"

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 1

# Deploy to multiple regions:
# fly scale count 2 --region sin
# fly scale count 1 --region nrt  # Tokyo
# fly scale count 1 --region syd  # Sydney
```

### Read Replica Consistency Model

**Important considerations:**
- Read replicas are eventually consistent (typically 100-500ms lag)
- Write -> immediate read may return stale data from replica
- For read-after-write consistency, use sticky sessions or cache

```javascript
// Read from primary for consistency-sensitive operations
app.get('/api/order/:id', async (req, res) => {
  const needsFreshData = req.query.fresh === 'true';

  if (needsFreshData && process.env.FLY_REGION !== process.env.PRIMARY_REGION) {
    res.set('fly-replay', `region=${process.env.PRIMARY_REGION}`);
    return res.status(307).end();
  }

  const order = await db.query('SELECT * FROM orders WHERE id = $1', [req.params.id]);
  res.json(order.rows[0]);
});
```

---

## Database Strategies

### Fly Postgres

```bash
# Create Postgres cluster
fly postgres create --name my-app-db --region sin

# Attach to your app (sets DATABASE_URL secret)
fly postgres attach my-app-db

# Create read replica in another region
fly postgres create --name my-app-db-nrt --region nrt

# Connect replicas
fly postgres attach my-app-db-nrt --app my-app
```

### LiteFS -- Distributed SQLite

```yaml
# litefs.yml
fuse:
  dir: "/litefs/data"

data:
  dir: "/litefs/state"

proxy:
  addr: ":8080"
  target: "localhost:3000"
  db: "production.db"
  passthrough:
    - "*.css"
    - "*.js"
    - "*.png"

lease:
  type: "consul"
  advertise-url: "http://${HOSTNAME}.vm.${FLY_APP_NAME}.internal:20202"
  candidate: ${FLY_REGION == PRIMARY_REGION}
  promote: true

  consul:
    url: "${FLY_CONSUL_URL}"
    key: "litefs/${FLY_APP_NAME}"
```

```toml
# fly.toml with LiteFS
[env]
  LITEFS_DIR = "/litefs/data"
  DATABASE_URL = "/litefs/data/production.db"

[mounts]
  source = "litefs"
  destination = "/litefs"
```

---

## Networking & Connectivity

### Private Networking (.internal DNS)

```javascript
// Access internal services via .internal DNS
const internalUrl = `http://${process.env.FLY_APP_NAME}.internal:3000`;

// Access specific region
const tokyoUrl = `http://nrt.${process.env.FLY_APP_NAME}.internal:3000`;

// Access Postgres internally
const pgUrl = `postgres://user:pass@my-app-db.internal:5432/mydb`;
```

### Flycast (Private Load Balancing)

```bash
# Allocate a Flycast (private) address
fly ips allocate-v6 --private

# Apps within the same org can reach this via:
# http://my-app.flycast:3000
```

```toml
# fly.toml for internal-only services
[http_service]
  internal_port = 3000
  auto_stop_machines = true
  auto_start_machines = true
  # No force_https -- Flycast is private networking
```

### Shared vs Dedicated IPv4

```bash
# IPv6 is free
fly ips allocate-v6

# Shared IPv4 is free (recommended for most apps)
fly ips allocate-v4 --shared

# Dedicated IPv4 costs $2/month (needed for some legacy clients)
fly ips allocate-v4
```

---

## Volumes

### Volume Management

```bash
# Create volume
fly volumes create data --region sin --size 10 --snapshot-retention 7

# List volumes
fly volumes list

# Create snapshot
fly volumes snapshots create vol_abc123

# Restore from snapshot
fly volumes create data_restored --snapshot-id vs_xyz789 --region sin

# Fork volume (copy to new region)
fly volumes fork vol_abc123 --region nrt

# Extend volume size
fly volumes extend vol_abc123 --size 20
```

### Volume Configuration in fly.toml

```toml
[mounts]
  source = "data"
  destination = "/data"
```

### Volume Forking for Fast Scaling

```bash
# Create "golden" volume with pre-loaded data
fly volumes create data --region sin --size 10
# ... load data ...
fly volumes snapshots create vol_abc123

# Fork to multiple regions
fly volumes fork vol_abc123 --region nrt
fly volumes fork vol_abc123 --region syd
fly volumes fork vol_abc123 --region lax
```

**Forks vs Snapshots:**
- Forks: Live copy, instant read access, background sync
- Snapshots: Point-in-time backup, slower to restore

### Volume IOPS Limits

| Machine Size | Max IOPS |
|---|---|
| shared-cpu-1x | 4,000 |
| shared-cpu-2x | 8,000 |
| shared-cpu-4x | 16,000 |
| performance-1x | 8,000 |
| performance-2x | 16,000 |
| performance-4x | 32,000 |

---

## Best Practices

1. **Use `suspend` over `stop` for faster resume** -- Suspended machines preserve memory state and resume 2-3x faster than stopped machines.

2. **Set `min_machines_running = 1` for production** -- Prevents cold starts for the first request. Use `0` only for dev/staging.

3. **Always implement fly-replay for multi-region** -- Route write requests to the primary region to maintain database consistency.

4. **Use .internal DNS for service-to-service** -- Private networking via `.internal` DNS is free, low-latency, and encrypted.

5. **Flycast for internal load balancing** -- Use Flycast addresses for backend services that should not be publicly accessible.

6. **Volume snapshots before risky operations** -- Always snapshot volumes before database migrations or major deployments.

7. **Fork volumes for multi-region data** -- Volume forks provide instant read access with background sync, faster than full copies.

8. **LiteFS for read-heavy SQLite workloads** -- Distributed SQLite with LiteFS provides multi-region reads with zero configuration complexity.

---

## Anti-Patterns

1. **Running databases without volumes** -- Machine filesystems are ephemeral. Always attach volumes for persistent data.

2. **Direct cross-region database writes** -- Use fly-replay to route writes to the primary region instead of connecting to a remote database.

3. **Dedicated IPv4 for every app** -- At $2/month each, use shared IPv4 or IPv6 unless legacy clients require dedicated IPv4.

4. **Ignoring volume IOPS limits** -- I/O-intensive apps on shared-cpu-1x machines are capped at 4,000 IOPS. Scale up machine size for higher throughput.

5. **Not setting concurrency limits** -- Without soft/hard limits, a single machine can be overwhelmed. Set limits based on your app's capacity.

6. **Volumes without snapshots** -- Volumes are not replicated by default. Configure snapshot retention for disaster recovery.

---

## Common CLI Commands

```bash
# App management
fly launch
fly deploy
fly status
fly apps list
fly apps destroy APP_NAME

# Machines
fly machine list
fly machine status MACHINE_ID
fly machine start MACHINE_ID
fly machine stop MACHINE_ID

# Scaling
fly scale count 2 --region sin
fly scale count 1 --region nrt
fly scale vm shared-cpu-2x --memory 1024
fly scale show

# Networking
fly ips list
fly ips allocate-v6
fly ips allocate-v4 --shared

# Volumes
fly volumes list
fly volumes create NAME --region REGION --size SIZE_GB
fly volumes extend VOL_ID --size NEW_SIZE
fly volumes snapshots list VOL_ID

# Postgres
fly postgres create --name DB_NAME --region REGION
fly postgres attach DB_NAME
fly postgres connect -a DB_NAME

# Logs
fly logs
fly logs --region sin
fly logs --app APP_NAME
```

---

## Sources & References

- [Autostop/autostart Machines](https://fly.io/docs/launch/autostop-autostart/)
- [Machine states and lifecycle](https://fly.io/docs/machines/machine-states/)
- [Machines API Reference](https://fly.io/docs/machines/api/)
- [Multi-region databases and fly-replay](https://fly.io/docs/blueprints/multi-region-fly-replay/)
- [Dynamic Request Routing with fly-replay](https://fly.io/docs/networking/dynamic-request-routing/)
- [LiteFS - Distributed SQLite](https://fly.io/docs/litefs/)
- [I Migrated from a Postgres Cluster to Distributed SQLite with LiteFS](https://kentcdodds.com/blog/i-migrated-from-a-postgres-cluster-to-distributed-sqlite-with-litefs)
- [Fly Postgres (Unmanaged)](https://fly.io/docs/postgres/)
- [High Availability & Global Replication](https://fly.io/docs/postgres/advanced-guides/high-availability-and-global-replication/)
- [Flycast - Private Fly Proxy services](https://fly.io/docs/networking/flycast/)
- [Private Networking](https://fly.io/docs/networking/private-networking/)
- [Fly Volumes overview](https://fly.io/docs/volumes/overview/)
- [Using Fly Volume forks for faster startup times](https://fly.io/docs/blueprints/volume-forking/)
- [Manage volume snapshots](https://fly.io/docs/volumes/snapshots/)
