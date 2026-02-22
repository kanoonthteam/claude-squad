---
name: devops-monitoring
description: Observability practices — metrics, logs, traces, Prometheus, Grafana, alerting, and SLOs
---

# Monitoring & Observability

## Purpose

Guide agents in implementing production-grade observability using the three pillars (metrics, logs, traces), setting up Prometheus and Grafana, defining SLOs, and creating actionable alerting strategies.

## Three Pillars of Observability

```
         ┌──────────┐    ┌──────────┐    ┌──────────┐
         │ Metrics   │    │  Logs    │    │  Traces  │
         │ (What)    │    │ (Why)    │    │ (Where)  │
         └─────┬─────┘    └─────┬────┘    └─────┬────┘
               │                │               │
               └────────────────┼───────────────┘
                                │
                    ┌───────────┴──────────┐
                    │   Observability      │
                    │   Platform           │
                    └──────────────────────┘
```

### Metrics
Numeric measurements over time. Answer "what is happening?"

- **Counter**: Monotonically increasing value (total requests, errors)
- **Gauge**: Value that goes up and down (active connections, temperature)
- **Histogram**: Distribution of values (request duration buckets)
- **Summary**: Client-side calculated percentiles

### Logs
Discrete events with context. Answer "why did it happen?"

### Traces
Request paths across services. Answer "where did it happen?"

## Prometheus

### Scrape Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "recording_rules.yml"
  - "alerting_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

scrape_configs:
  - job_name: 'api-server'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['api:3000']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  # Kubernetes service discovery
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
```

### Instrumenting a Node.js Application

```typescript
import { Registry, Counter, Histogram, Gauge, collectDefaultMetrics } from 'prom-client';

const register = new Registry();

// Collect default Node.js metrics (GC, event loop, memory)
collectDefaultMetrics({ register });

// Custom metrics
const httpRequestsTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [register],
});

const activeConnections = new Gauge({
  name: 'http_active_connections',
  help: 'Number of active HTTP connections',
  registers: [register],
});

// Middleware to track metrics
function metricsMiddleware(req, res, next) {
  const start = process.hrtime.bigint();
  activeConnections.inc();

  res.on('finish', () => {
    const duration = Number(process.hrtime.bigint() - start) / 1e9;
    const route = req.route?.path || req.path;

    httpRequestsTotal.inc({
      method: req.method,
      route,
      status_code: res.statusCode,
    });

    httpRequestDuration.observe(
      { method: req.method, route, status_code: res.statusCode },
      duration,
    );

    activeConnections.dec();
  });

  next();
}

// Expose /metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

### Essential PromQL Queries

```promql
# Request rate (requests per second)
rate(http_requests_total[5m])

# Error rate as percentage
sum(rate(http_requests_total{status_code=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m])) * 100

# 95th percentile response time
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Top 5 slowest endpoints
topk(5, histogram_quantile(0.95,
  sum by (route) (rate(http_request_duration_seconds_bucket[5m]))
))

# Memory usage percentage
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
/ node_memory_MemTotal_bytes * 100

# CPU usage percentage
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Disk space remaining
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100
```

### Recording Rules

Pre-compute expensive queries to speed up dashboards and alerting.

```yaml
# recording_rules.yml
groups:
  - name: api_metrics
    interval: 30s
    rules:
      - record: api:request_rate:5m
        expr: sum(rate(http_requests_total[5m])) by (route)

      - record: api:error_rate:5m
        expr: |
          sum(rate(http_requests_total{status_code=~"5.."}[5m]))
          / sum(rate(http_requests_total[5m]))

      - record: api:latency_p95:5m
        expr: |
          histogram_quantile(0.95,
            sum by (route, le) (rate(http_request_duration_seconds_bucket[5m]))
          )
```

## Grafana

### Dashboard Design Principles

1. **USE method** for infrastructure: Utilization, Saturation, Errors
2. **RED method** for services: Rate, Errors, Duration
3. **Four Golden Signals** (Google SRE): Latency, Traffic, Errors, Saturation

### Dashboard JSON Model (Service Overview)

```json
{
  "title": "API Service Overview",
  "panels": [
    {
      "title": "Request Rate",
      "type": "timeseries",
      "targets": [{ "expr": "sum(rate(http_requests_total[5m]))" }]
    },
    {
      "title": "Error Rate (%)",
      "type": "stat",
      "targets": [{ "expr": "api:error_rate:5m * 100" }],
      "thresholds": [
        { "value": 0, "color": "green" },
        { "value": 1, "color": "yellow" },
        { "value": 5, "color": "red" }
      ]
    },
    {
      "title": "p95 Latency",
      "type": "timeseries",
      "targets": [{ "expr": "api:latency_p95:5m" }]
    },
    {
      "title": "Active Connections",
      "type": "gauge",
      "targets": [{ "expr": "http_active_connections" }]
    }
  ]
}
```

### Grafana Alerting (Unified Alerting)

```yaml
# Grafana alert rule (provisioned via YAML)
apiVersion: 1
groups:
  - orgId: 1
    name: api-alerts
    folder: API
    interval: 1m
    rules:
      - uid: high-error-rate
        title: High Error Rate
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: api:error_rate:5m
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              conditions:
                - evaluator:
                    type: gt
                    params: [0.05]  # 5% error rate
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Error rate above 5% for 5 minutes"
          runbook_url: "https://wiki.example.com/runbooks/high-error-rate"
```

## Alerting Strategies

### Symptom-Based Alerting (Recommended)

Alert on user-facing symptoms, not internal causes.

| Alert On (Good) | Not On (Bad) |
|------------------|-------------|
| Error rate > 5% | CPU > 80% (not always a problem) |
| Latency p95 > 2s | Single pod restart |
| Availability < 99.9% | Disk at 70% (set threshold higher) |
| Queue depth growing | Cron job duration (unless it impacts users) |

### Alert Severity Levels

```yaml
# Critical: Pages on-call, immediate action required
- alert: ServiceDown
  expr: up{job="api-server"} == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "API server is down"
    runbook_url: "https://wiki.example.com/runbooks/service-down"

# Warning: Notify via Slack, investigate during business hours
- alert: HighLatency
  expr: api:latency_p95:5m > 1.0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "p95 latency above 1 second for 10 minutes"
```

### Actionable Alert Checklist

Every alert must have:
1. **Clear title** describing the symptom
2. **Runbook URL** with investigation steps
3. **Appropriate severity** (page-worthy or not)
4. **Sufficient `for` duration** to avoid flapping (at least 2-5 minutes)
5. **Dashboard link** for immediate investigation

## SLOs and Error Budgets

### Defining SLOs

```
SLI (Service Level Indicator): The metric being measured
SLO (Service Level Objective): The target for that metric
SLA (Service Level Agreement): The contractual commitment (with consequences)

Example:
  SLI: Proportion of successful HTTP requests (non-5xx / total)
  SLO: 99.9% of requests succeed over a 30-day rolling window
  SLA: 99.5% (contractual, with credits for breach)
```

### Error Budget Calculation

```
Error Budget = 1 - SLO

For 99.9% SLO over 30 days:
  Error budget = 0.1% = 43.2 minutes of downtime
  Or: 4,320 failed requests per 4,320,000 total requests

For 99.95% SLO:
  Error budget = 0.05% = 21.6 minutes of downtime
```

### SLO Burn Rate Alert

```yaml
# Multi-window burn rate alert (Google SRE approach)
# Fast burn: consuming error budget 14.4x faster than normal
- alert: SLOBurnRateCritical
  expr: |
    (
      sum(rate(http_requests_total{status_code=~"5.."}[1h]))
      / sum(rate(http_requests_total[1h]))
    ) > (14.4 * 0.001)
    and
    (
      sum(rate(http_requests_total{status_code=~"5.."}[5m]))
      / sum(rate(http_requests_total[5m]))
    ) > (14.4 * 0.001)
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "SLO burn rate critical - error budget will be exhausted in 1 hour"
```

## Health Check Patterns

### Layered Health Checks

```typescript
// Liveness: Is the process running?
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'alive' });
});

// Readiness: Can it accept traffic?
app.get('/readyz', async (req, res) => {
  try {
    await db.query('SELECT 1');
    await redis.ping();
    res.status(200).json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});

// Startup: Has initial setup completed?
let startupComplete = false;
app.get('/startupz', (req, res) => {
  if (startupComplete) {
    res.status(200).json({ status: 'started' });
  } else {
    res.status(503).json({ status: 'starting' });
  }
});
```

## Structured Logging

### JSON Log Format

```typescript
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  redact: ['req.headers.authorization', 'password', 'ssn'],
});

// Request logging middleware with correlation ID
import { randomUUID } from 'crypto';

function requestLogger(req, res, next) {
  const correlationId = req.headers['x-correlation-id'] || randomUUID();
  req.correlationId = correlationId;
  res.setHeader('x-correlation-id', correlationId);

  req.log = logger.child({
    correlationId,
    method: req.method,
    url: req.url,
    userAgent: req.headers['user-agent'],
  });

  const start = Date.now();
  res.on('finish', () => {
    req.log.info({
      statusCode: res.statusCode,
      responseTime: Date.now() - start,
    }, 'request completed');
  });

  next();
}
```

### Log Levels

| Level | Usage | Example |
|-------|-------|---------|
| `fatal` | Application is about to crash | Unhandled exception, out of memory |
| `error` | Operation failed, needs attention | Database connection lost, 5xx response |
| `warn` | Unexpected but handled | Deprecated API called, retry succeeded |
| `info` | Normal operations | Request completed, user logged in |
| `debug` | Detailed for troubleshooting | SQL query, cache hit/miss |
| `trace` | Very verbose, development only | Function entry/exit, variable values |

### Correlation IDs Across Services

```
Service A                    Service B                    Service C
─────────────────────────   ─────────────────────────   ─────────────────────────
x-correlation-id: abc-123   x-correlation-id: abc-123   x-correlation-id: abc-123
[INFO] Received request     [INFO] Processing order     [INFO] Sending email
[INFO] Calling Service B    [INFO] Calling Service C    [INFO] Email sent
[INFO] Response: 200        [INFO] Response: 200
```

## Incident Runbooks

### Runbook Template

```markdown
# Runbook: High Error Rate

## Symptoms
- Alert: "Error rate above 5% for 5 minutes"
- Users may see 500 errors or timeouts

## Impact
- User-facing: Yes
- Data loss risk: No
- Revenue impact: High

## Investigation Steps

1. **Check error logs**
   ```bash
   kubectl logs -l app=api-server --tail=100 | jq 'select(.level == "error")'
   ```

2. **Check dependent services**
   - Database: `kubectl exec -it postgres-0 -- pg_isready`
   - Redis: `kubectl exec -it redis-0 -- redis-cli ping`

3. **Check recent deployments**
   ```bash
   kubectl rollout history deployment/api-server
   ```

4. **Check resource usage**
   - Dashboard: https://grafana.example.com/d/api-resources

## Remediation

### If caused by recent deployment:
```bash
kubectl rollout undo deployment/api-server
```

### If caused by database:
1. Check connection pool: `SELECT count(*) FROM pg_stat_activity;`
2. Restart connection pool if needed

### If cause is unknown:
1. Scale up replicas: `kubectl scale deployment/api-server --replicas=5`
2. Page the on-call engineer
3. Create incident ticket

## Escalation
- L1: On-call SRE
- L2: Backend team lead
- L3: VP Engineering
```

## Best Practices

1. **Use recording rules** for frequently queried expressions
2. **Set retention policies** (Prometheus: 15-30 days, long-term in Thanos/Mimir)
3. **Use consistent label names** across all services
4. **Redact sensitive data** from logs (PII, tokens, passwords)
5. **Propagate correlation IDs** across all service boundaries
6. **Review alerts quarterly** -- delete noisy or ignored alerts
7. **Dashboard as code** -- store Grafana dashboards in version control

## Anti-Patterns

- **Alert fatigue**: Too many alerts, team ignores them all
- **Cause-based alerting**: Alerting on CPU usage instead of user impact
- **Missing runbooks**: Alert fires but no one knows what to do
- **Unstructured logs**: Parsing free-text logs in production
- **Logging everything**: High cardinality labels or debug logs in production
- **No correlation IDs**: Cannot trace a request across services

## Sources & References

- Prometheus Documentation: https://prometheus.io/docs/introduction/overview/
- Grafana Alerting: https://grafana.com/docs/grafana/latest/alerting/
- Google SRE Book - Monitoring: https://sre.google/sre-book/monitoring-distributed-systems/
- Google SRE Book - SLOs: https://sre.google/workbook/implementing-slos/
- OpenTelemetry Documentation: https://opentelemetry.io/docs/
- Pino Logger: https://getpino.io/
- Prometheus Best Practices: https://prometheus.io/docs/practices/naming/
