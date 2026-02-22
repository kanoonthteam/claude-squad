---
name: observability-practices
description: Observability with OpenTelemetry, traces/metrics/logs correlation, Grafana stack, and SLO-driven alerting
---

# Observability Practices

## Overview

Observability is the ability to understand the internal state of a system by examining its external outputs. Unlike monitoring (which tells you when something is broken), observability helps you understand why it is broken and what is happening in systems you have never seen fail before.

## Observability vs Monitoring

| Aspect | Monitoring | Observability |
|--------|-----------|---------------|
| Approach | Predefined dashboards and alerts | Exploratory, ad-hoc investigation |
| Questions | "Is X broken?" | "Why is X broken? What else is affected?" |
| Data | Metrics and uptime checks | Traces + metrics + logs correlated |
| Coverage | Known failure modes | Unknown unknowns |
| Cardinality | Low (aggregate metrics) | High (per-request detail) |

## OpenTelemetry

OpenTelemetry (OTel) is the CNCF standard for instrumentation, providing vendor-neutral APIs, SDKs, and tools for collecting telemetry data.

### SDK Setup (Node.js)

```typescript
// tracing.ts -- Initialize BEFORE importing application code
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { Resource } from '@opentelemetry/resources';
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
  ATTR_DEPLOYMENT_ENVIRONMENT,
} from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: 'api-service',
    [ATTR_SERVICE_VERSION]: process.env.APP_VERSION || '0.0.0',
    [ATTR_DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV || 'development',
  }),

  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces',
  }),

  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/metrics',
    }),
    exportIntervalMillis: 15000,
  }),

  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-http': {
        ignoreIncomingPaths: ['/health', '/metrics'],
      },
      '@opentelemetry/instrumentation-express': {},
      '@opentelemetry/instrumentation-pg': {},
      '@opentelemetry/instrumentation-redis': {},
    }),
  ],
});

sdk.start();
console.log('OpenTelemetry SDK initialized');

process.on('SIGTERM', () => {
  sdk.shutdown().then(() => process.exit(0));
});
```

### Manual Instrumentation (Custom Spans)

```typescript
import { trace, SpanStatusCode, context } from '@opentelemetry/api';

const tracer = trace.getTracer('order-service');

async function createOrder(orderData: OrderInput): Promise<Order> {
  return tracer.startActiveSpan('createOrder', async (span) => {
    try {
      span.setAttribute('order.customer_id', orderData.customerId);
      span.setAttribute('order.item_count', orderData.items.length);

      // Child span for validation
      const validatedData = await tracer.startActiveSpan('validateOrder', async (validationSpan) => {
        const result = validateOrderInput(orderData);
        validationSpan.setAttribute('validation.passed', result.valid);
        validationSpan.end();
        return result;
      });

      // Child span for database operation
      const order = await tracer.startActiveSpan('saveOrder', async (dbSpan) => {
        dbSpan.setAttribute('db.operation', 'INSERT');
        dbSpan.setAttribute('db.table', 'orders');
        const saved = await db.orders.create(validatedData);
        dbSpan.end();
        return saved;
      });

      // Child span for notification
      await tracer.startActiveSpan('sendConfirmation', async (notifySpan) => {
        notifySpan.setAttribute('notification.type', 'email');
        await emailService.sendOrderConfirmation(order);
        notifySpan.end();
      });

      span.setAttribute('order.id', order.id);
      span.setStatus({ code: SpanStatusCode.OK });
      return order;
    } catch (error) {
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error.message,
      });
      span.recordException(error);
      throw error;
    } finally {
      span.end();
    }
  });
}
```

### Custom Metrics

```typescript
import { metrics } from '@opentelemetry/api';

const meter = metrics.getMeter('order-service');

// Counter - monotonically increasing value
const orderCounter = meter.createCounter('orders.created', {
  description: 'Number of orders created',
  unit: '1',
});

// Histogram - distribution of values (latency, size)
const orderDuration = meter.createHistogram('orders.duration', {
  description: 'Time to process an order',
  unit: 'ms',
  advice: {
    explicitBucketBoundaries: [10, 50, 100, 250, 500, 1000, 2500, 5000],
  },
});

// Up-down counter - value that goes up and down
const activeOrders = meter.createUpDownCounter('orders.active', {
  description: 'Number of orders currently being processed',
});

// Observable gauge - async value read on demand
meter.createObservableGauge('orders.queue_depth', {
  description: 'Current depth of order processing queue',
}, async (result) => {
  const depth = await queue.getDepth();
  result.observe(depth);
});

// Usage in application code
async function processOrder(order: Order) {
  activeOrders.add(1);
  const startTime = Date.now();

  try {
    await fulfillOrder(order);
    orderCounter.add(1, {
      'order.type': order.type,
      'order.region': order.region,
    });
  } finally {
    activeOrders.add(-1);
    orderDuration.record(Date.now() - startTime, {
      'order.type': order.type,
    });
  }
}
```

### OpenTelemetry Collector

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024

  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128

  attributes:
    actions:
      - key: environment
        value: production
        action: upsert

  tail_sampling:
    decision_wait: 10s
    num_traces: 100000
    policies:
      - name: errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: slow-traces
        type: latency
        latency: { threshold_ms: 1000 }
      - name: probabilistic
        type: probabilistic
        probabilistic: { sampling_percentage: 10 }

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

  prometheusremotewrite:
    endpoint: http://mimir:9009/api/v1/push

  loki:
    endpoint: http://loki:3100/loki/api/v1/push

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, tail_sampling]
      exporters: [otlp/tempo]

    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]

    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, attributes]
      exporters: [loki]
```

## Traces/Metrics/Logs Correlation

### Trace ID Propagation

```typescript
// Structured logging with trace context
import { context, trace } from '@opentelemetry/api';
import pino from 'pino';

const logger = pino({
  mixin() {
    const span = trace.getSpan(context.active());
    if (span) {
      const spanContext = span.spanContext();
      return {
        trace_id: spanContext.traceId,
        span_id: spanContext.spanId,
        trace_flags: spanContext.traceFlags,
      };
    }
    return {};
  },
});

// Every log line now includes trace_id for correlation
logger.info({ orderId: 'ord-123' }, 'Processing order');
// Output: {"level":30,"trace_id":"abc123...","span_id":"def456...","orderId":"ord-123","msg":"Processing order"}
```

### Grafana: Jump from Logs to Traces

In Grafana, configure data source correlations:
1. Loki logs include `trace_id` field
2. Configure Loki derived field: `trace_id` -> link to Tempo
3. Click trace ID in log line -> opens trace in Tempo

## Grafana Stack (LGTM)

### Docker Compose Setup

```yaml
services:
  # Loki - Log aggregation
  loki:
    image: grafana/loki:3.0.0
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/config.yaml
    volumes:
      - ./config/loki.yaml:/etc/loki/config.yaml

  # Tempo - Distributed tracing
  tempo:
    image: grafana/tempo:2.4.0
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
    command: -config.file=/etc/tempo/config.yaml
    volumes:
      - ./config/tempo.yaml:/etc/tempo/config.yaml

  # Mimir - Metrics (Prometheus-compatible)
  mimir:
    image: grafana/mimir:2.12.0
    ports:
      - "9009:9009"
    command: -config.file=/etc/mimir/config.yaml
    volumes:
      - ./config/mimir.yaml:/etc/mimir/config.yaml

  # Grafana - Visualization
  grafana:
    image: grafana/grafana:11.0.0
    ports:
      - "3001:3000"
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
    volumes:
      - ./config/grafana/provisioning:/etc/grafana/provisioning
```

## SLIs, SLOs, and Golden Signals

### The Four Golden Signals

| Signal | What It Measures | Example Metric |
|--------|-----------------|----------------|
| Latency | Time to serve a request | `http_request_duration_seconds` |
| Traffic | Demand on the system | `http_requests_total` |
| Errors | Rate of failed requests | `http_requests_total{status=~"5.."}` |
| Saturation | How "full" the system is | CPU utilization, queue depth |

### SLI/SLO Definitions

```yaml
# SLO definition (Sloth format)
version: "prometheus/v1"
service: "api-service"
labels:
  team: platform
  tier: "1"

slos:
  - name: "availability"
    objective: 99.9              # 99.9% availability
    description: "API requests succeed"
    sli:
      events:
        error_query: sum(rate(http_requests_total{service="api",status=~"5.."}[{{.window}}]))
        total_query: sum(rate(http_requests_total{service="api"}[{{.window}}]))
    alerting:
      name: ApiAvailability
      labels:
        severity: critical
      annotations:
        summary: "API availability SLO at risk"
      page_alert:
        labels:
          severity: critical
      ticket_alert:
        labels:
          severity: warning

  - name: "latency"
    objective: 99.0
    description: "API requests complete within 500ms"
    sli:
      events:
        error_query: sum(rate(http_request_duration_seconds_bucket{service="api",le="0.5"}[{{.window}}]))
        total_query: sum(rate(http_request_duration_seconds_count{service="api"}[{{.window}}]))
```

### Error Budget Calculation

```
Error Budget = 1 - SLO Objective

For 99.9% availability over 30 days:
- Total minutes: 30 * 24 * 60 = 43,200
- Error budget: 43,200 * 0.001 = 43.2 minutes of downtime allowed

Burn Rate Alert:
- 1x burn rate = consuming budget at expected rate (over 30 days)
- 14.4x burn rate = consuming 30-day budget in ~2 days -> page immediately
- 6x burn rate = consuming budget in ~5 days -> ticket
- 1x burn rate = on track, no alert
```

### Burn Rate Alerts (Prometheus)

```yaml
# Prometheus alerting rules
groups:
  - name: slo-burn-rate
    rules:
      # Fast burn: 14.4x over 1h (pages immediately)
      - alert: ApiHighErrorBurnRate
        expr: |
          (
            sum(rate(http_requests_total{service="api",status=~"5.."}[1h]))
            /
            sum(rate(http_requests_total{service="api"}[1h]))
          ) > (14.4 * 0.001)
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "API error burn rate is 14.4x budget"

      # Slow burn: 6x over 6h (creates ticket)
      - alert: ApiModerateErrorBurnRate
        expr: |
          (
            sum(rate(http_requests_total{service="api",status=~"5.."}[6h]))
            /
            sum(rate(http_requests_total{service="api"}[6h]))
          ) > (6 * 0.001)
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "API error burn rate is 6x budget"
```

## Profiling (Continuous)

### Pyroscope Integration

```typescript
// Continuous profiling with Pyroscope
import Pyroscope from '@pyroscope/nodejs';

Pyroscope.init({
  serverAddress: 'http://pyroscope:4040',
  appName: 'api-service',
  tags: {
    region: process.env.AWS_REGION,
    version: process.env.APP_VERSION,
  },
});

Pyroscope.start();
```

### pprof (Go)

```go
import _ "net/http/pprof"

// Access at http://localhost:6060/debug/pprof/
go func() {
    log.Println(http.ListenAndServe("localhost:6060", nil))
}()
```

```bash
# CPU profile (30 seconds)
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Heap profile
go tool pprof http://localhost:6060/debug/pprof/heap

# Goroutine dump
go tool pprof http://localhost:6060/debug/pprof/goroutine
```

## Developer-Focused Local Observability

### Docker Compose for Local Dev

```yaml
# docker-compose.observability.yaml
services:
  jaeger:
    image: jaegertracing/all-in-one:1.54
    ports:
      - "16686:16686"  # Jaeger UI
      - "4317:4317"    # OTLP gRPC
      - "4318:4318"    # OTLP HTTP
    environment:
      - COLLECTOR_OTLP_ENABLED=true

  prometheus:
    image: prom/prometheus:v2.51.0
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana:11.0.0
    ports:
      - "3001:3000"
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
```

```bash
# Start local observability stack
docker compose -f docker-compose.observability.yaml up -d

# Jaeger UI: http://localhost:16686
# Grafana:   http://localhost:3001
# Prometheus: http://localhost:9090
```

## Alert Fatigue Prevention

### Alert Design Principles

1. **Alert on SLOs, not symptoms** -- "Error budget burning fast" beats "CPU high"
2. **Every alert must be actionable** -- if you cannot do anything about it, remove the alert
3. **Route appropriately** -- critical = page, warning = ticket, info = dashboard only
4. **Use burn rate windows** -- avoid alerting on momentary spikes
5. **Group related alerts** -- reduce noise with Alertmanager grouping

### Alertmanager Configuration

```yaml
# alertmanager.yml
route:
  receiver: default
  group_by: ['alertname', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    - match:
        severity: critical
      receiver: pagerduty
      repeat_interval: 5m
      continue: true

    - match:
        severity: warning
      receiver: slack-engineering
      repeat_interval: 1h

    - match:
        severity: info
      receiver: slack-observability
      repeat_interval: 24h

receivers:
  - name: pagerduty
    pagerduty_configs:
      - service_key: YOUR_PD_KEY
        severity: critical

  - name: slack-engineering
    slack_configs:
      - api_url: https://hooks.slack.com/services/XXX
        channel: '#engineering-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ['service']
```

## Best Practices

1. **Instrument with OpenTelemetry** -- vendor-neutral, future-proof
2. **Correlate all signals** -- trace ID in logs, exemplars in metrics
3. **Use structured logging** -- JSON with consistent field names
4. **Define SLOs before alerting** -- alert on user impact, not internal metrics
5. **Sample traces intelligently** -- keep all errors, sample successful requests
6. **Dashboard hierarchy** -- overview -> service -> component -> request detail
7. **Label metrics consistently** -- use OpenTelemetry semantic conventions
8. **Automate instrumentation** -- auto-instrumentation for frameworks, manual for business logic
9. **Profile in production** -- continuous profiling catches issues load testing misses
10. **Review alert efficacy** quarterly -- delete alerts nobody acts on

## Anti-Patterns

1. **Logging everything** -- high cardinality labels and verbose logging increase cost without value
2. **Alerting on CPU/memory** -- these are symptoms, not causes; alert on user-facing SLOs
3. **Dashboard sprawl** -- 50 dashboards nobody looks at; curate ruthlessly
4. **No trace sampling** -- storing 100% of traces is expensive and unnecessary
5. **Ignoring logs in observability** -- logs provide context traces and metrics cannot
6. **Metrics without labels** -- `http_requests_total` without status code is useless
7. **Alert on every error** -- some errors are expected; alert on error rate changes
8. **No runbook links** in alerts -- the alert fires but nobody knows what to do

## Sources & References

- https://opentelemetry.io/docs/ -- OpenTelemetry official documentation
- https://opentelemetry.io/docs/languages/js/ -- OpenTelemetry JavaScript SDK
- https://grafana.com/docs/loki/latest/ -- Grafana Loki documentation
- https://grafana.com/docs/tempo/latest/ -- Grafana Tempo documentation
- https://grafana.com/docs/mimir/latest/ -- Grafana Mimir documentation
- https://sre.google/sre-book/monitoring-distributed-systems/ -- Google SRE: Monitoring
- https://sre.google/workbook/alerting-on-slos/ -- SRE Workbook: Alerting on SLOs
- https://sloth.dev/ -- Sloth SLO generator
- https://pyroscope.io/docs/ -- Pyroscope continuous profiling
- https://www.honeycomb.io/blog/observability-101 -- Observability 101 by Honeycomb
