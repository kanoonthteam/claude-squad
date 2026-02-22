---
name: flyio-operations
description: Production-grade Fly.io operations patterns -- scaling, monitoring, Prometheus/Grafana, structured logging, cost optimization, and framework-specific patterns
---

# Fly.io Operations -- Staff Engineer Patterns

Production-ready patterns for Fly.io scaling (concurrency-based, metrics-based auto-scaling), monitoring (Prometheus, Grafana, built-in metrics), structured logging, cost optimization (machine sizing, auto-stop, volume management), and framework-specific production configurations for Node.js, Rails, Next.js, and Python.

## Table of Contents
1. [Scaling & Performance](#scaling--performance)
2. [Monitoring & Observability](#monitoring--observability)
3. [Cost Optimization](#cost-optimization)
4. [Framework-Specific Patterns](#framework-specific-patterns)
5. [Best Practices](#best-practices)
6. [Anti-Patterns](#anti-patterns)
7. [Common CLI Commands](#common-cli-commands)
8. [Sources & References](#sources--references)

---

## Scaling & Performance

### Concurrency-Based Auto-Scaling

```toml
# fly.toml
[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = "suspend"
  auto_start_machines = true
  min_machines_running = 2

  [http_service.concurrency]
    type = "requests"      # "requests" or "connections"
    soft_limit = 200       # Start scaling at this threshold
    hard_limit = 250       # Reject new requests/connections above this
```

### Metrics-Based Auto-Scaling

```toml
# fly.toml -- scale based on custom Prometheus metrics
[http_service]
  min_machines_running = 2
  auto_start_machines = true
  auto_stop_machines = "suspend"

[metrics]
  port = 3000
  path = "/metrics"
```

### Manual Scaling

```bash
# Horizontal scaling
fly scale count 3 --region sin    # 3 machines in Singapore
fly scale count 2 --region nrt    # 2 machines in Tokyo
fly scale count 1 --region syd    # 1 machine in Sydney

# Vertical scaling
fly scale vm shared-cpu-2x --memory 1024
fly scale vm performance-1x --memory 4096

# View current scale
fly scale show
```

---

## Monitoring & Observability

### Prometheus Metrics Endpoint

```javascript
// Prometheus metrics with prom-client
import client from 'prom-client';

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpDuration = new client.Histogram({
  name: 'http_request_duration_ms',
  help: 'HTTP request duration in milliseconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [10, 50, 100, 200, 500, 1000],
});
register.registerMetric(httpDuration);

const activeConnections = new client.Gauge({
  name: 'active_connections',
  help: 'Number of active connections',
});
register.registerMetric(activeConnections);

// Middleware: track request duration
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    httpDuration
      .labels(req.method, req.route?.path || req.path, String(res.statusCode))
      .observe(duration);
  });
  next();
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.send(await register.metrics());
});
```

### Fly.io Metrics Configuration

```toml
# fly.toml
[metrics]
  port = 3000
  path = "/metrics"
```

Fly.io scrapes this endpoint and makes metrics available in the built-in Grafana dashboard.

### Structured Logging

```javascript
// Structured JSON logging for Fly.io log aggregation
const logger = {
  info(message, data = {}) {
    console.log(JSON.stringify({
      level: 'info',
      message,
      region: process.env.FLY_REGION,
      machine: process.env.FLY_MACHINE_ID,
      app: process.env.FLY_APP_NAME,
      timestamp: new Date().toISOString(),
      ...data,
    }));
  },

  error(message, error, data = {}) {
    console.error(JSON.stringify({
      level: 'error',
      message,
      error: {
        name: error?.name,
        message: error?.message,
        stack: error?.stack,
      },
      region: process.env.FLY_REGION,
      machine: process.env.FLY_MACHINE_ID,
      timestamp: new Date().toISOString(),
      ...data,
    }));
  },

  warn(message, data = {}) {
    console.warn(JSON.stringify({
      level: 'warn',
      message,
      region: process.env.FLY_REGION,
      timestamp: new Date().toISOString(),
      ...data,
    }));
  },
};

export default logger;
```

### Distributed Tracing

```javascript
// Add Fly-Region header to all responses for request tracing
app.use((req, res, next) => {
  res.set('Fly-Region', process.env.FLY_REGION);
  res.set('Fly-Machine', process.env.FLY_MACHINE_ID);
  next();
});

// Log incoming request source region
app.use((req, res, next) => {
  const clientRegion = req.headers['fly-client-ip'];
  const forwardedRegion = req.headers['fly-region'];
  logger.info('Request received', {
    path: req.path,
    method: req.method,
    clientRegion,
    forwardedRegion,
  });
  next();
});
```

---

## Cost Optimization

### Machine Sizing Strategy

| Type | vCPU | Memory | Price/mo* | Use Case |
|---|---|---|---|---|
| shared-cpu-1x | 1 | 256MB-2GB | $1.94-$15.5 | Dev, staging, low traffic |
| shared-cpu-2x | 2 | 512MB-4GB | $3.88-$31 | Small production apps |
| shared-cpu-4x | 4 | 1GB-8GB | $7.76-$62 | Medium production apps |
| performance-1x | 1 | 2GB-8GB | $62-$248 | CPU-intensive tasks |
| performance-2x | 2 | 4GB-16GB | $124-$496 | High-traffic apps |

*Prices for 730 hours/month (continuous operation)

### Cost-Saving Patterns

**1. Auto stop/start for low-traffic apps:**

```toml
[http_service]
  auto_stop_machines = "suspend"
  auto_start_machines = true
  min_machines_running = 0  # Scale to zero

# Savings: Pay only when running (per-second billing)
# Example: App used 2 hours/day = ~91% cost reduction
```

**2. Shared CPU for non-critical workloads:**

```bash
# Development
fly scale vm shared-cpu-1x --memory 256

# Staging
fly scale vm shared-cpu-1x --memory 512

# Production workers
fly scale vm shared-cpu-2x --memory 1024
```

**3. Avoid dedicated IPv4:**

```bash
# IPv6 is free, IPv4 costs $2/month per app
# Use IPv6 + Fly proxy

# If IPv4 needed, use shared (free):
fly ips allocate-v4 --shared
```

**4. Optimize volume usage:**

```bash
# Volumes billed 24/7, even when machines stopped
fly volumes create data --size 1   # 1GB = $0.15/month
fly volumes create data --size 10  # 10GB = $1.50/month

# Delete unused volumes
fly volumes delete vol_xyz
```

**5. Monitor usage:**

```bash
fly dashboard billing
fly orgs billing-alerts set --threshold 100
```

### Cost Tracking in App

```javascript
let startTime = Date.now();

app.get('/health', (req, res) => {
  const uptimeHours = (Date.now() - startTime) / (1000 * 60 * 60);
  const estimatedCost = uptimeHours * 0.0027;  // shared-cpu-1x 256MB

  res.json({
    uptime: uptimeHours.toFixed(2),
    estimatedCost: `$${estimatedCost.toFixed(4)}`,
    region: process.env.FLY_REGION,
  });
});
```

---

## Framework-Specific Patterns

### Node.js / Express

```javascript
import express from 'express';
import helmet from 'helmet';
import compression from 'compression';

const app = express();
const port = process.env.PORT || 3000;

app.use(helmet());
app.use(compression());
app.set('trust proxy', true);  // Trust Fly proxy

// Multi-region handling
app.use((req, res, next) => {
  res.set('Fly-Region', process.env.FLY_REGION);
  next();
});

// Graceful shutdown
const server = app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});

process.on('SIGTERM', () => {
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
```

### Ruby on Rails

```ruby
# config/environments/production.rb
Rails.application.configure do
  config.cache_store = :mem_cache_store, ENV["REDIS_URL"],
    { namespace: "myapp:#{ENV['FLY_REGION']}" }

  config.asset_host = ENV['ASSET_HOST']
  config.force_ssl = true
end
```

```bash
# Generate Fly-optimized Dockerfile
bin/rails generate dockerfile \
  --postgresql --redis --litefs --swap 512m

fly launch
```

```ruby
# config/database.yml (with LiteFS)
production:
  adapter: sqlite3
  database: /litefs/db/production.sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
```

### Next.js

```javascript
// next.config.js
module.exports = {
  output: 'standalone',

  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: process.env.FLY_REGION === process.env.PRIMARY_REGION
          ? '/api/:path*'
          : `http://my-api.internal:3000/api/:path*`,
      },
    ];
  },
};
```

### FastAPI / Python

```python
from fastapi import FastAPI, Request
import os

app = FastAPI()

@app.middleware("http")
async def add_fly_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Fly-Region"] = os.getenv("FLY_REGION", "unknown")
    return response

@app.get("/health")
async def health():
    return {"status": "healthy", "region": os.getenv("FLY_REGION")}

import signal

def handle_sigterm(*args):
    print("Received SIGTERM, shutting down")
    raise KeyboardInterrupt()

signal.signal(signal.SIGTERM, handle_sigterm)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8000)))
```

---

## Best Practices

1. **Use structured JSON logging** -- Fly.io log aggregation works best with structured JSON. Include region, machine ID, and timestamps in every log entry.

2. **Expose Prometheus metrics** -- Configure `[metrics]` in fly.toml to enable built-in Grafana dashboards and metrics-based auto-scaling.

3. **Right-size machines** -- Start with `shared-cpu-1x` and scale up based on actual metrics. Over-provisioning wastes money.

4. **Scale to zero for dev/staging** -- Set `min_machines_running = 0` for non-production environments. Per-second billing means you pay only for actual usage.

5. **Use shared IPv4** -- Shared IPv4 is free and works for most applications. Only use dedicated IPv4 when legacy clients require it.

6. **Set billing alerts** -- Configure budget thresholds to prevent unexpected charges from misconfigured scaling.

7. **Framework-specific optimizations** -- Trust the Fly proxy (`trust proxy`), enable compression, and handle SIGTERM in every framework.

8. **Monitor volume costs** -- Volumes are billed 24/7 regardless of machine state. Delete unused volumes and use the smallest size needed.

---

## Anti-Patterns

1. **Not monitoring costs** -- Without billing alerts, auto-scaling can cause unexpected charges. Set thresholds early.

2. **Using performance VMs for dev/staging** -- Performance VMs start at $62/month. Use `shared-cpu-1x` for non-production workloads.

3. **Ignoring Prometheus metrics** -- Without metrics, you are blind to performance issues. Always expose and monitor key metrics.

4. **Unstructured logging** -- Plain text logs are hard to search and aggregate. Use JSON structured logging with consistent fields.

5. **Not setting `trust proxy`** -- Without this, Express/Rails will not correctly read client IPs from Fly's proxy headers.

6. **Keeping unused machines running** -- Review `fly status` regularly. Destroy unused apps and machines to avoid charges.

---

## Common CLI Commands

```bash
# Scaling
fly scale count N --region REGION
fly scale vm VM_SIZE --memory SIZE_MB
fly scale show

# Monitoring
fly logs
fly logs --region REGION
fly status
fly dashboard metrics

# Billing
fly dashboard billing
fly orgs billing-alerts set --threshold AMOUNT

# GPU
fly platform regions  # Check GPU region availability
fly scale vm a10      # Use GPU machine

# Diagnostics
fly doctor
fly ping
fly ssh console
fly ssh console -C "top"  # Run command on machine
```

---

## Sources & References

- [Autoscale based on metrics](https://fly.io/docs/launch/autoscale-by-metric/)
- [Metrics on Fly.io](https://fly.io/docs/monitoring/metrics/)
- [Machine Sizing](https://fly.io/docs/machines/guides-examples/machine-sizing/)
- [Cost Management](https://fly.io/docs/about/cost-management/)
- [JavaScript on Fly.io](https://fly.io/docs/js/)
- [Using WebSockets with Next.js on Fly.io](https://fly.io/javascript-journal/websockets-with-nextjs/)
- [LiteFS for Rails](https://fly.io/docs/rails/advanced-guides/litefs/)
- [AnyCable on Fly](https://fly.io/docs/rails/advanced-guides/anycable/)
- [Fly GPUs](https://fly.io/docs/gpus/)
- [Fly Volumes overview](https://fly.io/docs/volumes/overview/)
