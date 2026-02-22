---
name: node-performance
description: Node.js performance optimization — clustering, worker threads, streaming, multi-layer caching (LRU + Redis), memory management, observability, message queues, monorepos
---

# Node.js Performance & Observability

Production-ready performance patterns for Node.js 2026. Covers clustering for multi-core CPUs, worker threads for CPU-intensive tasks, streaming for large data, multi-layer caching (LRU + Redis), HTTP caching headers, memory leak detection, structured logging with Pino, OpenTelemetry, BullMQ/RabbitMQ message queues, and Turborepo monorepos.

## Table of Contents

1. [Clustering for Multi-Core CPUs](#clustering-for-multi-core-cpus)
2. [Worker Threads](#worker-threads)
3. [Streaming for Large Responses](#streaming-for-large-responses)
4. [Memory Leak Detection](#memory-leak-detection)
5. [Multi-Layer Caching](#multi-layer-caching)
6. [HTTP Caching Headers](#http-caching-headers)
7. [Structured Logging with Pino](#structured-logging-with-pino)
8. [OpenTelemetry Integration](#opentelemetry-integration)
9. [BullMQ Background Jobs](#bullmq-background-jobs)
10. [RabbitMQ Event-Driven Architecture](#rabbitmq-event-driven-architecture)
11. [Monorepo Patterns](#monorepo-patterns)
12. [Best Practices](#best-practices)
13. [Anti-Patterns](#anti-patterns)

---

## Clustering for Multi-Core CPUs

```typescript
import cluster from 'cluster';
import os from 'os';
import { createServer } from './app';

const numCPUs = os.cpus().length;

if (cluster.isPrimary) {
  console.log(`Primary ${process.pid} is running`);

  // Fork workers
  for (let i = 0; i < numCPUs; i++) {
    cluster.fork();
  }

  cluster.on('exit', (worker, code, signal) => {
    console.log(`Worker ${worker.process.pid} died. Restarting...`);
    cluster.fork();
  });
} else {
  // Workers share the TCP connection
  createServer().listen(3000, () => {
    console.log(`Worker ${process.pid} started`);
  });
}
```

---

## Worker Threads

Use worker threads for CPU-intensive tasks that would block the event loop.

```typescript
import { Worker } from 'worker_threads';

function runWorker<T>(workerData: any): Promise<T> {
  return new Promise((resolve, reject) => {
    const worker = new Worker('./worker.js', { workerData });

    worker.on('message', resolve);
    worker.on('error', reject);
    worker.on('exit', (code) => {
      if (code !== 0) {
        reject(new Error(`Worker stopped with exit code ${code}`));
      }
    });
  });
}

// Main thread
app.post('/analyze', async (req, res) => {
  const result = await runWorker({ data: req.body.data });
  res.json(result);
});

// worker.js
import { parentPort, workerData } from 'worker_threads';

function analyzeData(data) {
  // CPU-intensive operation
  return data.map(/* heavy computation */);
}

const result = analyzeData(workerData.data);
parentPort.postMessage(result);
```

---

## Streaming for Large Responses

```typescript
import { pipeline } from 'stream/promises';
import { createReadStream } from 'fs';
import { Transform } from 'stream';

// Stream large file downloads
app.get('/export/users', async (req, res) => {
  const userStream = db.user.findManyStream();

  const jsonTransform = new Transform({
    objectMode: true,
    transform(chunk, encoding, callback) {
      callback(null, JSON.stringify(chunk) + '\n');
    },
  });

  res.setHeader('Content-Type', 'application/x-ndjson');
  res.setHeader('Content-Disposition', 'attachment; filename="users.ndjson"');

  await pipeline(userStream, jsonTransform, res);
});

// Stream file uploads
app.post('/upload', (req, res) => {
  const writeStream = createWriteStream('./uploads/file.dat');

  req.pipe(writeStream);

  writeStream.on('finish', () => {
    res.json({ success: true });
  });

  writeStream.on('error', (err) => {
    res.status(500).json({ error: err.message });
  });
});
```

---

## Memory Leak Detection

```typescript
import v8 from 'v8';

// Enable heap profiling in production
if (process.env.ENABLE_HEAP_PROFILING === 'true') {
  setInterval(() => {
    const heapSnapshot = v8.writeHeapSnapshot();
    console.log('Heap snapshot written to', heapSnapshot);
  }, 60000);
}

// Monitor memory usage
setInterval(() => {
  const usage = process.memoryUsage();
  logger.info({
    rss: `${Math.round(usage.rss / 1024 / 1024)}MB`,
    heapTotal: `${Math.round(usage.heapTotal / 1024 / 1024)}MB`,
    heapUsed: `${Math.round(usage.heapUsed / 1024 / 1024)}MB`,
    external: `${Math.round(usage.external / 1024 / 1024)}MB`,
  }, 'Memory usage');
}, 30000);

// On-demand heap dump endpoint
import * as heapdump from 'heapdump';

app.get('/admin/heapdump', (req, res) => {
  heapdump.writeSnapshot((err, filename) => {
    if (err) return res.status(500).send(err);
    res.send(`Heap dump written to ${filename}`);
  });
});
```

---

## Multi-Layer Caching

### LRU + Redis (L1 + L2)

```typescript
import { LRUCache } from 'lru-cache';
import { createClient } from 'redis';

// Layer 1: In-memory LRU cache (fastest)
const lruCache = new LRUCache<string, any>({
  max: 500,
  ttl: 1000 * 60 * 5, // 5 minutes
  updateAgeOnGet: true,
});

// Layer 2: Redis (shared across instances)
const redis = createClient();
await redis.connect();

async function getCachedUser(userId: string) {
  // Check L1 cache
  let user = lruCache.get(userId);
  if (user) {
    logger.debug({ userId, cache: 'L1' }, 'Cache hit');
    return user;
  }

  // Check L2 cache
  const cached = await redis.get(`user:${userId}`);
  if (cached) {
    user = JSON.parse(cached);
    lruCache.set(userId, user);
    logger.debug({ userId, cache: 'L2' }, 'Cache hit');
    return user;
  }

  // Cache miss - fetch from database
  user = await db.user.findUnique({ where: { id: userId } });
  if (user) {
    lruCache.set(userId, user);
    await redis.setEx(`user:${userId}`, 300, JSON.stringify(user));
  }

  logger.debug({ userId, cache: 'miss' }, 'Cache miss');
  return user;
}

// Cache invalidation
async function updateUser(userId: string, data: any) {
  const user = await db.user.update({
    where: { id: userId },
    data,
  });

  // Invalidate caches
  lruCache.delete(userId);
  await redis.del(`user:${userId}`);

  return user;
}
```

### Cache-Aside and Write-Through Patterns

```typescript
// Cache-aside pattern
async function getProduct(productId: string) {
  const cacheKey = `product:${productId}`;
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached);

  const product = await db.product.findUnique({
    where: { id: productId },
    include: { category: true, images: true },
  });

  if (product) {
    await redis.setEx(cacheKey, 3600, JSON.stringify(product));
  }

  return product;
}

// Write-through pattern
async function updateProduct(productId: string, data: any) {
  const product = await db.product.update({
    where: { id: productId },
    data,
  });

  await redis.setEx(
    `product:${productId}`,
    3600,
    JSON.stringify(product)
  );

  return product;
}
```

---

## HTTP Caching Headers

```typescript
import crypto from 'crypto';

// ETags for conditional requests
app.get('/api/users', async (req, res) => {
  const users = await db.user.findMany();

  const etag = crypto
    .createHash('md5')
    .update(JSON.stringify(users))
    .digest('hex');

  if (req.headers['if-none-match'] === etag) {
    return res.status(304).end();
  }

  res.setHeader('ETag', etag);
  res.setHeader('Cache-Control', 'private, max-age=300');
  res.json(users);
});

// No caching for sensitive data
app.get('/api/users/me', (req, res) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  res.json(req.user);
});
```

---

## Structured Logging with Pino

```typescript
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  serializers: {
    req: pino.stdSerializers.req,
    res: pino.stdSerializers.res,
    err: pino.stdSerializers.err,
  },
  redact: {
    paths: [
      'req.headers.authorization',
      'req.body.password',
      'req.body.confirmPassword',
    ],
    remove: true,
  },
  base: {
    env: process.env.NODE_ENV,
    service: 'api',
  },
});

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();

  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info({
      req, res, duration,
      method: req.method,
      url: req.url,
      statusCode: res.statusCode,
    });
  });

  next();
});

// Child loggers for context
const userLogger = logger.child({ module: 'users' });
userLogger.info({ userId: '123' }, 'Creating user');
```

---

## OpenTelemetry Integration

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'api-service',
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'http://localhost:4318/v1/traces',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

// Graceful shutdown
process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => console.log('Tracing terminated'))
    .catch((error) => console.error('Error terminating tracing', error))
    .finally(() => process.exit(0));
});

// Pino + OpenTelemetry correlation
import { PinoInstrumentation } from '@opentelemetry/instrumentation-pino';

const pinoInstrumentation = new PinoInstrumentation({
  logHook: (span, record) => {
    record['trace_id'] = span.spanContext().traceId;
    record['span_id'] = span.spanContext().spanId;
  },
});
```

---

## BullMQ Background Jobs

```typescript
import { Queue, Worker, QueueEvents } from 'bullmq';
import { createClient } from 'redis';

const connection = createClient();
await connection.connect();

// Create queue
const emailQueue = new Queue('emails', { connection });

// Add job to queue
async function sendWelcomeEmail(userId: string) {
  await emailQueue.add('welcome', {
    userId,
    template: 'welcome',
  }, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 2000 },
    removeOnComplete: 100,
    removeOnFail: 1000,
  });
}

// Worker to process jobs
const worker = new Worker('emails', async (job) => {
  if (job.name === 'welcome') {
    const { userId } = job.data;
    const user = await db.user.findUnique({ where: { id: userId } });
    await sendEmail({
      to: user.email,
      subject: 'Welcome!',
      template: 'welcome',
      data: { name: user.name },
    });
  }
  return { success: true };
}, {
  connection,
  concurrency: 5,
  limiter: { max: 10, duration: 1000 },
});

// Scheduled jobs
await emailQueue.add('digest', { type: 'weekly' }, {
  repeat: { pattern: '0 9 * * 1' }, // Every Monday at 9 AM
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  await worker.close();
  await emailQueue.close();
  await connection.quit();
});
```

---

## RabbitMQ Event-Driven Architecture

```typescript
import amqp from 'amqplib';

// Publisher
async function publishEvent(exchange: string, routingKey: string, message: any) {
  const connection = await amqp.connect('amqp://localhost');
  const channel = await connection.createChannel();

  await channel.assertExchange(exchange, 'topic', { durable: true });

  channel.publish(
    exchange,
    routingKey,
    Buffer.from(JSON.stringify(message)),
    { persistent: true }
  );

  await channel.close();
  await connection.close();
}

// Consumer with Dead Letter Queue
async function setupDLQ() {
  const connection = await amqp.connect('amqp://localhost');
  const channel = await connection.createChannel();

  // Main queue with DLQ
  await channel.assertQueue('main_queue', {
    durable: true,
    deadLetterExchange: 'dlx',
    deadLetterRoutingKey: 'failed',
    messageTtl: 60000,
  });

  // Dead letter exchange and queue
  await channel.assertExchange('dlx', 'direct', { durable: true });
  await channel.assertQueue('dlq', { durable: true });
  await channel.bindQueue('dlq', 'dlx', 'failed');
}

// Usage
await publishEvent('user.events', 'user.created', {
  userId: '123',
  email: 'user@example.com',
});
```

---

## Monorepo Patterns

### Turborepo + pnpm Workspaces

```
monorepo/
├── apps/
│   ├── api/                    # Express/Fastify API
│   └── web/                    # Next.js frontend
├── packages/
│   ├── database/               # Shared Prisma schema
│   ├── shared/                 # Shared types and utilities
│   ├── ui/                     # Shared UI components
│   └── tsconfig/               # Shared TypeScript configs
├── package.json
├── pnpm-workspace.yaml
└── turbo.json
```

```json
// turbo.json
{
  "$schema": "https://turbo.build/schema.json",
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**"]
    },
    "test": {
      "dependsOn": ["build"],
      "outputs": ["coverage/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```

**Monorepo Best Practices:**
- Use `workspace:*` for internal dependencies
- Hoist common devDependencies to root
- Use namespace prefix (`@acme/`) to avoid conflicts
- Leverage Turborepo caching (30s build to 0.2s cached)
- Configure separate tsconfig for each package type

---

## Best Practices

1. **Clustering in production** - Use all available CPU cores
2. **Worker threads for CPU work** - Image processing, data analysis, encryption
3. **Streaming over buffering** - Never load entire large files into memory
4. **Two-layer caching** - LRU for hot data, Redis for shared state
5. **Pino for structured logging** - JSON output, automatic serializers, redaction
6. **OpenTelemetry for tracing** - Distributed traces across microservices
7. **BullMQ for job queues** - Reliable background processing with retry
8. **RabbitMQ for event-driven** - Pub/sub with dead letter queues for resilience
9. **Monitor memory** - Track heap usage and detect leaks early
10. **Turborepo for monorepos** - Fast builds with intelligent caching

---

## Anti-Patterns

- Running CPU-intensive work on the main event loop thread
- Loading entire large files into memory (use streams)
- Cache without invalidation strategy (stale data)
- Logging sensitive data (passwords, tokens, PII)
- Missing dead letter queues for failed messages
- Not implementing graceful shutdown for workers and queues
- Single-process Node.js in production (wastes CPU cores)
- Storing large objects in LRU cache without size limits

---

## Sources & References

- [Node.js 2026: Mastering Worker Threads & Clustering](https://medium.com/@beenakumawat004/node-js-2026-mastering-worker-threads-clustering-for-high-performance-apps-3fd4f14e68d4)
- [Preventing and Debugging Memory Leaks in Node.js](https://betterstack.com/community/guides/scaling-nodejs/high-performance-nodejs/nodejs-memory-leaks/)
- [How to Build Multi-Layer Caching with Redis in Node.js](https://oneuptime.com/blog/post/2026-01-25-multi-layer-caching-redis-nodejs/view)
- [API Caching Strategies - Redis, ETags & HTTP Headers](https://medium.com/@priyanshu011109/%EF%B8%8F-api-caching-strategies-redis-etags-http-headers-demystified-63c211d3fda6)
- [Node.js Structured Logging with pino + OpenTelemetry](https://medium.com/@hadiyolworld007/node-js-structured-logging-with-pino-opentelemetry-correlated-traces-logs-and-metrics-in-one-2c28b10c4fa0)
- [Pino Logger: Complete Node.js Guide with Examples](https://signoz.io/guides/pino-logger/)
- [BullMQ Vs RabbitMQ: Which Message Queue Should You Choose?](https://expertbeacon.com/bullmq-vs-rabbitmq-which-message-queue-should-you-choose/)
- [Building a Monorepo with pnpm and Turborepo](https://vinayak-hegde.medium.com/building-a-monorepo-with-pnpm-and-turborepo-a-journey-to-efficiency-cfeec5d182f5)
