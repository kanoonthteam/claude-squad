---
name: devops-containers
description: Docker best practices, multi-stage builds, container security, and registry patterns
---

# Container Best Practices

## Purpose

Guide agents in building secure, optimized container images with proper multi-stage builds, security scanning, and registry management patterns.

## Docker Multi-Stage Builds

### Node.js Production Build

```dockerfile
# Stage 1: Install dependencies
FROM node:22-slim AS deps
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Stage 2: Build application
FROM node:22-slim AS builder
WORKDIR /app
RUN corepack enable
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm build
# Prune dev dependencies after build
RUN pnpm prune --prod

# Stage 3: Production runtime
FROM node:22-slim AS runtime
# Create non-root user
RUN groupadd --system --gid 1001 app && \
    useradd --system --uid 1001 --gid app app
WORKDIR /app

# Copy only production artifacts
COPY --from=builder --chown=app:app /app/dist ./dist
COPY --from=builder --chown=app:app /app/node_modules ./node_modules
COPY --from=builder --chown=app:app /app/package.json ./

USER app
EXPOSE 3000

# Use dumb-init or tini to handle signals properly
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r => process.exit(r.ok ? 0 : 1))"

CMD ["node", "dist/index.js"]
```

### Go Production Build (Distroless)

```dockerfile
FROM golang:1.23 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Static binary, no CGO
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server ./cmd/server

# Distroless: no shell, no package manager, minimal attack surface
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
```

### Python Production Build

```dockerfile
FROM python:3.13-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --compile-bytecode
COPY . .

FROM python:3.13-slim AS runtime
RUN groupadd --system app && useradd --system --gid app app
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src ./src
ENV PATH="/app/.venv/bin:$PATH"
USER app
CMD ["python", "-m", "src.main"]
```

## BuildKit Features (2025)

### Enable BuildKit

```bash
# Set as environment variable (default in Docker 23+)
export DOCKER_BUILDKIT=1

# Or use docker buildx
docker buildx build --platform linux/amd64,linux/arm64 -t myapp:latest .
```

### Cache Mounts for Package Managers

```dockerfile
# Cache pnpm store across builds
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

# Cache pip downloads
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Cache Go modules
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
```

### Secret Mounts (Never Bake Secrets Into Layers)

```dockerfile
# Mount secrets at build time without persisting in image layers
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) pnpm install

# Build command:
# docker build --secret id=npm_token,src=.npm_token .
```

### Multi-Platform Builds

```bash
# Build for multiple architectures
docker buildx create --name multiarch --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag myregistry/myapp:v1.0 \
  --push .
```

## Container Security Scanning

### Trivy (Recommended, Open Source)

```bash
# Scan an image for vulnerabilities
trivy image myapp:latest

# Scan with severity filter
trivy image --severity HIGH,CRITICAL myapp:latest

# Scan and fail CI if critical vulnerabilities found
trivy image --exit-code 1 --severity CRITICAL myapp:latest

# Scan filesystem (before building image)
trivy fs --scanners vuln,misconfig .
```

### GitHub Actions Integration

```yaml
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: 'myapp:${{ github.sha }}'
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload Trivy scan results
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-results.sarif'
```

### Grype (Anchore)

```bash
# Scan image
grype myapp:latest

# Fail on high severity
grype myapp:latest --fail-on high
```

### Snyk Container

```bash
snyk container test myapp:latest --severity-threshold=high
snyk container monitor myapp:latest  # Continuous monitoring
```

## Registry Patterns

### Multi-Registry Tagging Strategy

```bash
# Tag with git SHA (immutable) + semantic version + latest
IMAGE=ghcr.io/org/myapp
docker tag myapp:build $IMAGE:$GIT_SHA
docker tag myapp:build $IMAGE:v1.2.3
docker tag myapp:build $IMAGE:latest

# Push all tags
docker push $IMAGE --all-tags
```

### GitHub Container Registry (GHCR)

```yaml
# .github/workflows/publish.yml
jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha,prefix=
            type=semver,pattern={{version}}
            type=ref,event=branch

      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### AWS ECR

```bash
# Authenticate
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com

# Lifecycle policy to clean old images (set in ECR console or via CLI)
aws ecr put-lifecycle-policy --repository-name myapp --lifecycle-policy-text '{
  "rules": [{
    "rulePriority": 1,
    "description": "Keep last 10 images",
    "selection": {
      "tagStatus": "any",
      "countType": "imageCountMoreThan",
      "countNumber": 10
    },
    "action": { "type": "expire" }
  }]
}'
```

## Docker Compose for Development

```yaml
# docker-compose.yml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: deps  # Use deps stage for development
    volumes:
      - .:/app
      - /app/node_modules  # Anonymous volume to preserve container node_modules
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/myapp_dev
    depends_on:
      db:
        condition: service_healthy
    command: pnpm dev

  db:
    image: postgres:17-alpine
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: myapp_dev
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
```

## Image Optimization

### Base Image Selection Guide

| Base Image | Size | Use Case |
|------------|------|----------|
| `node:22` | ~1 GB | Development only |
| `node:22-slim` | ~200 MB | Production Node.js apps |
| `node:22-alpine` | ~130 MB | Size-critical, but musl libc edge cases |
| `gcr.io/distroless/nodejs22` | ~130 MB | Maximum security, no shell |
| `gcr.io/distroless/static` | ~2 MB | Static Go/Rust binaries |
| `scratch` | 0 MB | Absolute minimum, static binaries only |

### .dockerignore

```
# .dockerignore
node_modules
.git
.github
.env
.env.*
*.md
!README.md
dist
coverage
.turbo
.next
.nuxt
docker-compose*.yml
Dockerfile*
.dockerignore
tests
__tests__
*.test.*
*.spec.*
.vscode
.idea
```

### Layer Ordering Rules

```dockerfile
# Least frequently changed → Most frequently changed
FROM node:22-slim
WORKDIR /app

# 1. System dependencies (rarely change)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates && rm -rf /var/lib/apt/lists/*

# 2. Package manager files (change when deps change)
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

# 3. Application code (changes frequently)
COPY . .
RUN pnpm build
```

## Health Checks

### Dockerfile HEALTHCHECK

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1
```

### Application Health Endpoint

```typescript
// Comprehensive health check
app.get('/health', async (req, res) => {
  const checks = {
    status: 'healthy',
    version: process.env.APP_VERSION || 'unknown',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    checks: {
      database: await checkDatabase(),
      redis: await checkRedis(),
    },
  };

  const isHealthy = Object.values(checks.checks).every(c => c === 'ok');
  res.status(isHealthy ? 200 : 503).json({
    ...checks,
    status: isHealthy ? 'healthy' : 'degraded',
  });
});
```

## Best Practices

1. **Always use specific image tags** -- never `latest` in production
2. **Run as non-root user** in all containers
3. **Use multi-stage builds** to minimize production image size
4. **Scan images for vulnerabilities** before pushing to registry
5. **Set resource limits** (CPU/memory) in orchestrator config
6. **Use `.dockerignore`** to prevent copying unnecessary files
7. **One process per container** -- avoid running multiple services
8. **Use health checks** for proper orchestrator integration
9. **Label images** with build metadata (git SHA, build date, version)
10. **Clean up package manager caches** in the same RUN layer

## Anti-Patterns

- **Running as root** in production containers
- **Installing dev dependencies** in production images
- **Storing secrets in image layers** (use runtime secrets or secret mounts)
- **Using `ADD` when `COPY` suffices** (ADD has tar extraction and URL fetching side effects)
- **Multiple `RUN apt-get`** commands (consolidate to reduce layers)
- **Not using `--frozen-lockfile`** leading to non-deterministic builds
- **Ignoring `.dockerignore`** resulting in bloated build contexts

## Sources & References

- Docker Best Practices Guide: https://docs.docker.com/build/building/best-practices/
- Docker Multi-Stage Builds: https://docs.docker.com/build/building/multi-stage/
- BuildKit Cache Mounts: https://docs.docker.com/build/cache/backends/
- Trivy Documentation: https://aquasecurity.github.io/trivy/
- Google Distroless Images: https://github.com/GoogleContainerTools/distroless
- Snyk Container Security: https://docs.snyk.io/scan-with-snyk/snyk-container
- Docker Compose Specification: https://docs.docker.com/compose/compose-file/
- GHCR Publishing Guide: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
