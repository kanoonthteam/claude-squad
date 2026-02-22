---
name: devops-cicd
description: CI/CD pipeline design, GitHub Actions workflows, deployment strategies, and quality gates
---

# CI/CD Best Practices

## Purpose

Guide agents in designing robust CI/CD pipelines with quality gates, caching strategies, and safe deployment patterns. Covers GitHub Actions as the primary platform with GitLab CI patterns for reference.

## Pipeline Architecture

### Quality Gate Pipeline

Every commit should pass through a structured sequence of quality gates before reaching production.

```
commit → lint → typecheck → unit-test → build → integration-test → deploy:staging → smoke-test → deploy:production
```

### Pipeline Principles (2025)

1. **Fail fast**: Run cheap checks (lint, format) before expensive ones (build, E2E)
2. **Deterministic builds**: Pin dependencies, use lockfiles, hash-based caching
3. **Immutable artifacts**: Build once, deploy the same artifact to every environment
4. **Shift left**: Catch issues as early as possible in the pipeline
5. **Pipeline as code**: All CI/CD config lives in version control, reviewed via PR

## GitHub Actions Patterns

### Reusable Workflows

Reusable workflows reduce duplication across repositories. Define once in a shared repo or locally and reference with `uses:`.

```yaml
# .github/workflows/ci-reusable.yml
name: Reusable CI

on:
  workflow_call:
    inputs:
      node-version:
        description: 'Node.js version'
        required: false
        default: '22'
        type: string
      working-directory:
        description: 'Working directory for monorepo'
        required: false
        default: '.'
        type: string
    secrets:
      NPM_TOKEN:
        required: false

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ inputs.working-directory }}
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: 'pnpm'
          cache-dependency-path: '${{ inputs.working-directory }}/pnpm-lock.yaml'

      - run: pnpm install --frozen-lockfile

      - name: Lint
        run: pnpm lint

      - name: Type Check
        run: pnpm typecheck

      - name: Unit Tests
        run: pnpm test -- --coverage

      - name: Upload coverage
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: ${{ inputs.working-directory }}/coverage/
```

### Calling a Reusable Workflow

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: ./.github/workflows/ci-reusable.yml
    with:
      node-version: '22'
    secrets: inherit
```

### Matrix Builds

Test across multiple versions and platforms in parallel.

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        node-version: [20, 22]
        os: [ubuntu-latest, macos-latest]
        exclude:
          - os: macos-latest
            node-version: 20
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
      - run: pnpm install --frozen-lockfile
      - run: pnpm test
```

### Caching Strategies

```yaml
# pnpm caching (built-in to setup-node)
- uses: actions/setup-node@v4
  with:
    node-version: '22'
    cache: 'pnpm'

# Docker layer caching
- uses: docker/build-push-action@v6
  with:
    context: .
    cache-from: type=gha
    cache-to: type=gha,mode=max
    push: true
    tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

# Custom caching (Turborepo, build artifacts)
- uses: actions/cache@v4
  with:
    path: |
      .turbo
      **/dist
    key: turbo-${{ runner.os }}-${{ hashFiles('**/pnpm-lock.yaml') }}-${{ github.sha }}
    restore-keys: |
      turbo-${{ runner.os }}-${{ hashFiles('**/pnpm-lock.yaml') }}-
      turbo-${{ runner.os }}-
```

### Environment Protection Rules

```yaml
jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Deploy to staging
        run: ./scripts/deploy.sh staging

  deploy-production:
    needs: [deploy-staging, smoke-tests]
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://app.example.com
    # Requires manual approval configured in GitHub repo settings
    steps:
      - name: Deploy to production
        run: ./scripts/deploy.sh production
        env:
          DEPLOY_TOKEN: ${{ secrets.PRODUCTION_DEPLOY_TOKEN }}
```

### Concurrency Control

Prevent multiple deployments running simultaneously.

```yaml
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true  # Cancel previous runs on same branch
```

## GitLab CI Include Patterns

```yaml
# .gitlab-ci.yml
include:
  - local: '.gitlab/ci/lint.yml'
  - local: '.gitlab/ci/test.yml'
  - local: '.gitlab/ci/deploy.yml'
  - project: 'devops/ci-templates'
    ref: 'v2.0'
    file: '/templates/node-pipeline.yml'

variables:
  NODE_VERSION: '22'

stages:
  - validate
  - test
  - build
  - deploy
```

## Deployment Strategies

### Blue-Green Deployment

Maintain two identical production environments. Route traffic to the new version atomically.

```
                    ┌─────────────┐
    Load Balancer ──┤ Blue (v1)   │  ← Currently serving traffic
                    └─────────────┘
                    ┌─────────────┐
                    │ Green (v2)  │  ← Deploy here, then switch
                    └─────────────┘
```

**Pros**: Instant rollback (switch back), zero downtime
**Cons**: Requires double infrastructure, database migrations need care

### Canary Deployment

Gradually shift traffic to the new version while monitoring for errors.

```yaml
# Example: Kubernetes canary with Argo Rollouts
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api-server
spec:
  strategy:
    canary:
      steps:
        - setWeight: 5     # 5% traffic to canary
        - pause: { duration: 5m }
        - setWeight: 25
        - pause: { duration: 10m }
        - setWeight: 50
        - pause: { duration: 10m }
        - setWeight: 100
      canaryMetadata:
        labels:
          role: canary
```

**Pros**: Low risk, gradual rollout, real user validation
**Cons**: More complex infrastructure, need good observability

### Rolling Deployment

Replace instances one at a time. Default for most container orchestrators.

```yaml
# Kubernetes rolling update
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # Extra pod during rollout
      maxUnavailable: 0  # Zero downtime
```

**Pros**: Simple, resource efficient
**Cons**: Multiple versions running simultaneously during rollout

### Feature Flags (Decouple Deploy from Release)

```typescript
// Use feature flags to deploy code without activating it
if (featureFlags.isEnabled('new-checkout-flow', { userId: user.id })) {
  return newCheckoutFlow(cart);
} else {
  return legacyCheckoutFlow(cart);
}
```

Recommended services: LaunchDarkly, Unleash (self-hosted), Flagsmith, PostHog feature flags.

## Best Practices

1. **Keep pipelines under 10 minutes** for developer feedback loops
2. **Use branch protection rules** requiring CI to pass before merge
3. **Pin action versions** to full SHA for supply-chain security: `uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11`
4. **Never store secrets in code** -- use GitHub Secrets, Vault, or cloud-native secret managers
5. **Use OIDC for cloud deployments** instead of long-lived access keys
6. **Implement automatic rollback** on deployment failure
7. **Run security scanning in CI**: Dependabot, CodeQL, Trivy
8. **Use path filters** to avoid running unnecessary jobs in monorepos
9. **Separate build and deploy**: Build once, promote the same artifact

## Anti-Patterns

- **Manual deployments** mixed with CI/CD -- pick one and commit to it
- **Long-running pipelines** (30+ minutes) that block developer flow
- **Deploying directly from local machines** bypassing CI quality gates
- **Shared mutable CI environments** that cause flaky pipelines
- **Ignoring failed pipelines** ("it's probably flaky, just re-run")
- **Using `latest` tags** for base images or dependencies in CI
- **Over-testing in CI** -- move slow E2E tests to a nightly schedule

## Monorepo Pipeline Patterns

```yaml
# Path-based filtering for monorepos
on:
  push:
    paths:
      - 'packages/api/**'
      - 'packages/shared/**'
      - 'pnpm-lock.yaml'

# Turborepo integration
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2  # For turbo --filter changes
      - run: pnpm turbo run lint test build --filter='...[HEAD^]'
```

## Sources & References

- GitHub Actions Documentation - Reusing Workflows: https://docs.github.com/en/actions/using-workflows/reusing-workflows
- GitHub Actions Security Hardening: https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions
- Argo Rollouts - Progressive Delivery: https://argoproj.github.io/rollouts/
- Martin Fowler - Continuous Delivery: https://martinfowler.com/bliki/ContinuousDelivery.html
- GitLab CI/CD Includes: https://docs.gitlab.com/ee/ci/yaml/includes.html
- Turborepo Caching in CI: https://turbo.build/repo/docs/guides/ci
- CNCF CI/CD Patterns: https://www.cncf.io/blog/2024/01/09/ci-cd-best-practices-in-2024/
