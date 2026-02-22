---
name: flyio-deploy
description: Production-grade Fly.io deployment patterns -- deployment strategies, Dockerfile patterns, health checks, release commands, secrets management, and CI/CD with GitHub Actions
---

# Fly.io Deploy -- Staff Engineer Patterns

Production-ready patterns for Fly.io deployment strategies (rolling, bluegreen, canary, immediate), Dockerfile patterns for Node.js/Rails/Next.js/Python, health checks, release commands, secrets management, and CI/CD with GitHub Actions (review apps, staging, production).

## Table of Contents
1. [Deployment Strategies](#deployment-strategies)
2. [Dockerfile Patterns](#dockerfile-patterns)
3. [Health Checks & Reliability](#health-checks--reliability)
4. [Secrets Management](#secrets-management)
5. [CI/CD Integration](#cicd-integration)
6. [Best Practices](#best-practices)
7. [Anti-Patterns](#anti-patterns)
8. [Common CLI Commands](#common-cli-commands)
9. [Sources & References](#sources--references)

---

## Deployment Strategies

### Strategy Configuration

```toml
# fly.toml
[deploy]
  release_command = "npm run migrate"  # Run before new version gets traffic
  strategy = "bluegreen"              # rolling | bluegreen | canary | immediate
```

**Strategy comparison:**

| Strategy | Downtime | Rollback | Use Case |
|---|---|---|---|
| rolling | None | Slow | Default, general purpose |
| bluegreen | None | Instant | Production APIs, zero-risk deploys |
| canary | None | Instant | Gradual rollout, A/B testing |
| immediate | Brief | Manual | Dev/staging, non-critical |

### Blue/Green Deployment

```toml
[deploy]
  strategy = "bluegreen"
  # New machines start, pass health checks, then old machines receive SIGTERM
  # Instant rollback: old machines are kept briefly
```

### Canary Deployment

```toml
[deploy]
  strategy = "canary"
  # Deploys to a subset of machines first
  # Use with `fly deploy --canary-count 1` to control rollout
```

### Release Commands

```toml
[deploy]
  # Runs in a temporary machine before deployment
  release_command = "node dist/migrate.js"
```

```javascript
// dist/migrate.js
import { migrate } from './db/migrations';

async function runMigrations() {
  console.log('Running database migrations...');
  await migrate();
  console.log('Migrations complete');
  process.exit(0);
}

runMigrations().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);  // Non-zero exit prevents deployment
});
```

---

## Dockerfile Patterns

### Node.js with pnpm (Multi-Stage)

```dockerfile
FROM node:20-slim AS base
RUN corepack enable
WORKDIR /app

FROM base AS deps
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

FROM base AS build
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

FROM base AS runtime
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json .

ENV NODE_ENV=production
EXPOSE 3000

CMD ["node", "dist/index.js"]
```

### Next.js Standalone

```dockerfile
FROM node:20-slim AS base
WORKDIR /app

FROM base AS deps
COPY package*.json ./
RUN npm ci

FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM base AS runner
ENV NODE_ENV=production

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

EXPOSE 3000
ENV PORT=3000

CMD ["node", "server.js"]
```

### Python FastAPI

```dockerfile
FROM python:3.12-slim AS base
WORKDIR /app

FROM base AS deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM base AS runtime
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin
COPY . .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```

### GPU Dockerfile (ML Inference)

```dockerfile
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3.10 python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY . .
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```

```toml
# fly.toml for GPU
app = "ml-inference"
primary_region = "ord"

[build]
  dockerfile = "Dockerfile.gpu"

[[vm]]
  size = "a10"  # GPU type
  memory = "32gb"
  cpus = 8

[http_service]
  internal_port = 8000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0

  [http_service.concurrency]
    type = "requests"
    soft_limit = 10
    hard_limit = 20
```

---

## Health Checks & Reliability

### HTTP Health Checks

```toml
# fly.toml
[[http_service.checks]]
  grace_period = "10s"    # Time after start before checks begin
  interval = "15s"        # Time between checks
  method = "GET"
  path = "/health"
  protocol = "http"
  timeout = "5s"

[[http_service.checks]]
  grace_period = "30s"
  interval = "60s"
  method = "GET"
  path = "/health/deep"   # Deep health check (DB, Redis, etc.)
  protocol = "http"
  timeout = "10s"
```

### Health Check Implementation

```javascript
// Comprehensive health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    region: process.env.FLY_REGION,
    isPrimary: process.env.FLY_REGION === process.env.PRIMARY_REGION,
    timestamp: new Date().toISOString(),
  });
});

app.get('/health/deep', async (req, res) => {
  const checks = {};

  try {
    await db.query('SELECT 1');
    checks.database = 'ok';
  } catch (err) {
    checks.database = 'error';
  }

  try {
    await redis.ping();
    checks.redis = 'ok';
  } catch (err) {
    checks.redis = 'error';
  }

  const allOk = Object.values(checks).every(v => v === 'ok');
  res.status(allOk ? 200 : 503).json({
    status: allOk ? 'healthy' : 'degraded',
    checks,
    region: process.env.FLY_REGION,
  });
});
```

### Graceful Shutdown

```javascript
const server = app.listen(port, () => {
  console.log(`Server running on port ${port} in region ${process.env.FLY_REGION}`);
});

let isShuttingDown = false;

process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully');
  isShuttingDown = true;

  server.close(async () => {
    await writeDb.end();
    if (readDb !== writeDb) await readDb.end();
    await redis.quit();
    console.log('Shutdown complete');
    process.exit(0);
  });

  setTimeout(() => {
    console.error('Forced shutdown after 30s');
    process.exit(1);
  }, 30000);
});

// Return 503 during shutdown
app.use((req, res, next) => {
  if (isShuttingDown) {
    res.status(503).send('Server shutting down');
  } else {
    next();
  }
});
```

---

## Secrets Management

### Setting and Using Secrets

```bash
# Set secrets (triggers redeploy)
fly secrets set DATABASE_URL="postgres://..." REDIS_URL="redis://..."

# Set without redeploying
fly secrets set --stage SECRET_KEY="value"
fly deploy  # Deploy when ready

# List secrets (names only, values hidden)
fly secrets list

# Remove a secret
fly secrets unset OLD_SECRET
```

### Build Secrets

```bash
# Set build secret (available during Docker build only)
fly secrets set --build NPM_TOKEN="..."
# Or pass on deploy
fly deploy --build-secret NPM_TOKEN=...
```

```dockerfile
# Use build secret in Dockerfile
FROM node:20-slim
WORKDIR /app

RUN --mount=type=secret,id=NPM_TOKEN \
    echo "//registry.npmjs.org/:_authToken=$(cat /run/secrets/NPM_TOKEN)" > .npmrc && \
    npm install && \
    rm .npmrc

COPY . .
CMD ["node", "dist/index.js"]
```

### Secret Rotation Pattern

```javascript
// Support multiple secrets during rotation
const validSecrets = [
  process.env.SECRET_KEY_NEW,
  process.env.SECRET_KEY_OLD,
].filter(Boolean);

function verifyToken(token) {
  for (const secret of validSecrets) {
    try {
      return jwt.verify(token, secret);
    } catch (err) {
      continue;
    }
  }
  throw new Error('Invalid token');
}
```

**Rotation process:**
1. Set new secret: `fly secrets set SECRET_KEY_NEW=...`
2. Deploy with both old and new
3. Wait for all tokens to refresh
4. Remove old secret: `fly secrets unset SECRET_KEY_OLD`

---

## CI/CD Integration

### GitHub Actions Deploy

```yaml
# .github/workflows/deploy.yml
name: Deploy to Fly.io

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - name: Deploy to Fly.io
        run: flyctl deploy --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

**Generate deploy token:**

```bash
# App-scoped token (recommended for CI)
fly tokens create deploy -x 999999h

# Org-scoped token (for multiple apps)
fly auth token
```

### Review Apps (PR Previews)

```yaml
# .github/workflows/review-app.yml
name: Review App

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - name: Deploy Review App
        id: deploy
        uses: superfly/fly-pr-review-apps@1.2.0
        with:
          name: pr-${{ github.event.number }}-my-app
          region: sin
          org: my-org
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

      - name: Comment PR
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: 'Review app deployed: https://pr-${{ github.event.number }}-my-app.fly.dev'
            })
```

### Cleanup Review Apps on PR Close

```yaml
on:
  pull_request:
    types: [closed]

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - name: Destroy Review App
        run: flyctl apps destroy pr-${{ github.event.number }}-my-app -y
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

### Staging Environment

```yaml
on:
  push:
    branches: [develop]

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - name: Deploy to Staging
        run: flyctl deploy --app my-app-staging --config fly.staging.toml
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

```toml
# fly.staging.toml
app = "my-app-staging"
primary_region = "sin"

[env]
  NODE_ENV = "staging"
  LOG_LEVEL = "debug"

[[vm]]
  size = "shared-cpu-1x"
  memory = "512mb"
```

---

## Best Practices

1. **Use bluegreen strategy for production** -- Zero-downtime deploys with instant rollback. Old machines stay alive briefly for fallback.

2. **Always set release_command for migrations** -- Run database migrations in a temporary machine before the new version gets traffic.

3. **Multi-stage Dockerfiles** -- Separate build and runtime stages to minimize image size and attack surface.

4. **Implement graceful shutdown** -- Handle SIGTERM to drain connections and close database pools before exit.

5. **Deep health checks** -- Implement `/health/deep` that verifies database, Redis, and external service connectivity.

6. **App-scoped deploy tokens** -- Use `fly tokens create deploy` for CI instead of org-level tokens. Limits blast radius if compromised.

7. **Review apps for every PR** -- Deploy review apps automatically for preview testing. Destroy on PR close to save costs.

8. **Build secrets for private registries** -- Use `--mount=type=secret` in Dockerfiles to avoid baking credentials into image layers.

---

## Anti-Patterns

1. **Using `immediate` strategy in production** -- This causes brief downtime. Use `rolling` or `bluegreen` instead.

2. **Skipping health checks** -- Without health checks, unhealthy machines receive traffic. Always configure at least a basic HTTP check.

3. **Ignoring SIGTERM** -- Abrupt shutdowns cause request failures. Always handle SIGTERM for graceful connection draining.

4. **Secrets in fly.toml** -- The `[env]` section is visible in deploys. Use `fly secrets set` for sensitive values.

5. **Org-scoped tokens in CI** -- If leaked, org tokens grant access to all apps. Use app-scoped deploy tokens.

6. **Not testing release commands** -- A failing release command blocks deployment. Test migrations locally before deploying.

---

## Common CLI Commands

```bash
# Deployment
fly deploy
fly deploy --remote-only
fly deploy --strategy bluegreen
fly deploy --app APP_NAME --config fly.staging.toml

# Secrets
fly secrets set KEY=VALUE
fly secrets set --stage KEY=VALUE
fly secrets list
fly secrets unset KEY

# Health & Status
fly status
fly checks list
fly doctor

# Releases
fly releases
fly releases show RELEASE_NUMBER

# Tokens
fly tokens create deploy -x 999999h
fly auth token

# SSH
fly ssh console
fly ssh console -s  # Select machine
```

---

## Sources & References

- [Seamless Deployments on Fly.io](https://fly.io/docs/blueprints/seamless-deployments/)
- [Health Checks](https://fly.io/docs/reference/health-checks/)
- [Secrets and Fly Apps](https://www.fly.io/docs/apps/secrets/)
- [Build Secrets](https://fly.io/docs/apps/build-secrets/)
- [Continuous Deployment with GitHub Actions](https://fly.io/docs/launch/continuous-deployment-with-github-actions/)
- [Git Branch Preview Environments on GitHub](https://fly.io/docs/blueprints/review-apps-guide/)
- [JavaScript on Fly.io](https://fly.io/docs/js/)
- [LiteFS for Rails](https://fly.io/docs/rails/advanced-guides/litefs/)
- [Fly GPUs](https://fly.io/docs/gpus/)
- [Machine Sizing](https://fly.io/docs/machines/guides-examples/machine-sizing/)
