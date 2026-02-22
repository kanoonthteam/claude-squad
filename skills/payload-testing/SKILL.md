---
name: payload-testing
description: Payload CMS 3.x testing and deployment — Vitest/Jest integration testing, API testing, seed data, migration testing, deployment patterns (Vercel/Docker), CI/CD pipelines
---

# Payload CMS 3.x Testing & Deployment

Production-ready testing and deployment patterns for Payload CMS 3.x (2025/2026). Covers integration testing with Vitest and Jest, API endpoint testing, hook testing, access control testing, seed data patterns, database migration testing, deployment to Vercel and Docker, and CI/CD pipeline configuration.

## Table of Contents

1. [Testing Architecture](#testing-architecture)
2. [Test Environment Setup](#test-environment-setup)
3. [Integration Testing with Vitest](#integration-testing-with-vitest)
4. [Collection CRUD Testing](#collection-crud-testing)
5. [Hook Testing](#hook-testing)
6. [Access Control Testing](#access-control-testing)
7. [REST API Testing](#rest-api-testing)
8. [GraphQL API Testing](#graphql-api-testing)
9. [Seed Data Patterns](#seed-data-patterns)
10. [Migration Testing](#migration-testing)
11. [Deployment — Vercel](#deployment--vercel)
12. [Deployment — Docker](#deployment--docker)
13. [CI/CD Pipeline](#cicd-pipeline)
14. [Environment Configuration](#environment-configuration)
15. [Best Practices](#best-practices)
16. [Anti-Patterns](#anti-patterns)
17. [Sources & References](#sources--references)

---

## Testing Architecture

Payload 3.x testing revolves around the **local API**. Since the local API provides direct access to all collections, hooks, and access control without HTTP overhead, it is the preferred testing approach.

```
Test Suite
  |
  +-- Unit Tests (pure functions: validators, formatters, utilities)
  |
  +-- Integration Tests (local API: CRUD, hooks, access control)
  |
  +-- API Tests (REST/GraphQL: endpoint behavior, auth flow)
  |
  +-- E2E Tests (optional: full admin panel with Playwright)
```

**Recommended test runner**: Vitest (fast, ESM-native, compatible with Payload 3.x).

---

## Test Environment Setup

### Vitest Configuration

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config'
import path from 'path'

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['./src/tests/setup.ts'],
    include: ['src/**/*.test.ts'],
    testTimeout: 30000,
    hookTimeout: 30000,
    pool: 'forks', // Use forks for database isolation
    poolOptions: {
      forks: {
        singleFork: true, // Run tests sequentially to avoid DB conflicts
      },
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@payload-config': path.resolve(__dirname, './payload.config.ts'),
    },
  },
})
```

### Test Setup with Payload Initialization

```typescript
// src/tests/setup.ts
import { beforeAll, afterAll, afterEach } from 'vitest'
import { getPayload } from 'payload'
import type { Payload } from 'payload'
import config from '../payload.config'

let payload: Payload

beforeAll(async () => {
  payload = await getPayload({ config })

  // Create test admin user
  try {
    await payload.create({
      collection: 'users',
      data: {
        email: 'admin@test.com',
        password: 'test-password-123',
        name: 'Test Admin',
        role: 'admin',
      },
    })
  } catch {
    // User may already exist from a previous run
  }
})

afterEach(async () => {
  // Clean up test data between tests
  const collections = ['posts', 'categories', 'media']
  for (const collection of collections) {
    try {
      await payload.delete({
        collection: collection as any,
        where: { id: { exists: true } },
      })
    } catch {
      // Collection may be empty
    }
  }
})

afterAll(async () => {
  // Clean up admin user
  try {
    const users = await payload.find({
      collection: 'users',
      where: { email: { equals: 'admin@test.com' } },
    })
    for (const user of users.docs) {
      await payload.delete({ collection: 'users', id: user.id })
    }
  } catch {
    // Ignore cleanup errors
  }
})

export { payload }
```

### Test Helper Utilities

```typescript
// src/tests/helpers.ts
import type { Payload } from 'payload'

export async function createTestUser(
  payload: Payload,
  overrides: Partial<{ email: string; role: string; name: string }> = {},
) {
  const user = await payload.create({
    collection: 'users',
    data: {
      email: overrides.email || `test-${Date.now()}@test.com`,
      password: 'test-password-123',
      name: overrides.name || 'Test User',
      role: overrides.role || 'editor',
      ...overrides,
    },
  })
  return user
}

export async function loginUser(
  payload: Payload,
  email: string,
  password: string = 'test-password-123',
) {
  const result = await payload.login({
    collection: 'users',
    data: { email, password },
  })
  return result
}

export async function createTestPost(
  payload: Payload,
  authorId: string,
  overrides: Partial<{ title: string; status: string; slug: string }> = {},
) {
  return payload.create({
    collection: 'posts',
    data: {
      title: overrides.title || `Test Post ${Date.now()}`,
      slug: overrides.slug || `test-post-${Date.now()}`,
      status: overrides.status || 'draft',
      author: authorId,
      ...overrides,
    },
  })
}

export async function createTestCategory(
  payload: Payload,
  overrides: Partial<{ name: string; slug: string }> = {},
) {
  return payload.create({
    collection: 'categories',
    data: {
      name: overrides.name || `Category ${Date.now()}`,
      slug: overrides.slug || `category-${Date.now()}`,
      ...overrides,
    },
  })
}
```

---

## Integration Testing with Vitest

### Basic Collection CRUD Tests

```typescript
// src/collections/Posts.test.ts
import { describe, it, expect, beforeAll, afterEach } from 'vitest'
import { getPayload } from 'payload'
import type { Payload } from 'payload'
import config from '../../payload.config'
import { createTestUser, createTestPost } from '../tests/helpers'

describe('Posts Collection', () => {
  let payload: Payload
  let adminUser: any
  let editorUser: any

  beforeAll(async () => {
    payload = await getPayload({ config })
    adminUser = await createTestUser(payload, {
      email: 'posts-admin@test.com',
      role: 'admin',
    })
    editorUser = await createTestUser(payload, {
      email: 'posts-editor@test.com',
      role: 'editor',
    })
  })

  afterEach(async () => {
    await payload.delete({
      collection: 'posts',
      where: { id: { exists: true } },
    })
  })

  describe('Create', () => {
    it('should create a post with valid data', async () => {
      const post = await payload.create({
        collection: 'posts',
        data: {
          title: 'Test Post',
          slug: 'test-post',
          content: { root: { children: [] } },
          author: adminUser.id,
          status: 'draft',
        },
      })

      expect(post.id).toBeDefined()
      expect(post.title).toBe('Test Post')
      expect(post.slug).toBe('test-post')
      expect(post.status).toBe('draft')
    })

    it('should reject post without required title', async () => {
      await expect(
        payload.create({
          collection: 'posts',
          data: {
            slug: 'no-title',
            author: adminUser.id,
          } as any,
        }),
      ).rejects.toThrow()
    })

    it('should reject duplicate slug', async () => {
      await createTestPost(payload, adminUser.id, { slug: 'unique-slug' })

      await expect(
        createTestPost(payload, adminUser.id, { slug: 'unique-slug' }),
      ).rejects.toThrow()
    })
  })

  describe('Read', () => {
    it('should find posts with pagination', async () => {
      // Create 15 posts
      for (let i = 0; i < 15; i++) {
        await createTestPost(payload, adminUser.id, {
          title: `Post ${i}`,
          slug: `post-${i}`,
        })
      }

      const result = await payload.find({
        collection: 'posts',
        limit: 10,
        page: 1,
      })

      expect(result.docs).toHaveLength(10)
      expect(result.totalDocs).toBe(15)
      expect(result.totalPages).toBe(2)
      expect(result.hasNextPage).toBe(true)
    })

    it('should filter posts by status', async () => {
      await createTestPost(payload, adminUser.id, { status: 'published', slug: 'pub-1' })
      await createTestPost(payload, adminUser.id, { status: 'draft', slug: 'draft-1' })
      await createTestPost(payload, adminUser.id, { status: 'published', slug: 'pub-2' })

      const published = await payload.find({
        collection: 'posts',
        where: { status: { equals: 'published' } },
      })

      expect(published.docs).toHaveLength(2)
    })
  })

  describe('Update', () => {
    it('should update post fields', async () => {
      const post = await createTestPost(payload, adminUser.id, {
        title: 'Original',
        slug: 'original',
      })

      const updated = await payload.update({
        collection: 'posts',
        id: post.id,
        data: { title: 'Updated Title' },
      })

      expect(updated.title).toBe('Updated Title')
      expect(updated.slug).toBe('original') // Slug unchanged
    })
  })

  describe('Delete', () => {
    it('should delete a post by ID', async () => {
      const post = await createTestPost(payload, adminUser.id, { slug: 'to-delete' })

      await payload.delete({
        collection: 'posts',
        id: post.id,
      })

      await expect(
        payload.findByID({ collection: 'posts', id: post.id }),
      ).rejects.toThrow()
    })
  })
})
```

---

## Collection CRUD Testing

### Testing Relationships

```typescript
describe('Post-Category Relationships', () => {
  it('should create post with category relationship', async () => {
    const category = await createTestCategory(payload, {
      name: 'Technology',
      slug: 'technology',
    })

    const post = await payload.create({
      collection: 'posts',
      data: {
        title: 'Tech Post',
        slug: 'tech-post',
        category: category.id,
        author: adminUser.id,
      },
    })

    // Fetch with depth to populate
    const populated = await payload.findByID({
      collection: 'posts',
      id: post.id,
      depth: 1,
    })

    expect(populated.category).toBeDefined()
    expect((populated.category as any).name).toBe('Technology')
  })

  it('should query posts by related category', async () => {
    const category = await createTestCategory(payload, {
      name: 'Design',
      slug: 'design',
    })

    await createTestPost(payload, adminUser.id, {
      title: 'Design Post',
      slug: 'design-post',
    })

    const result = await payload.find({
      collection: 'posts',
      where: {
        category: { equals: category.id },
      },
    })

    expect(result.docs).toHaveLength(1)
    expect(result.docs[0].title).toBe('Design Post')
  })
})
```

---

## Hook Testing

```typescript
// src/hooks/Posts.test.ts
describe('Post Hooks', () => {
  it('should auto-generate slug from title on create', async () => {
    const post = await payload.create({
      collection: 'posts',
      data: {
        title: 'My Amazing Blog Post',
        author: adminUser.id,
        // No slug provided - should auto-generate
      },
    })

    expect(post.slug).toBe('my-amazing-blog-post')
  })

  it('should format slug correctly with special characters', async () => {
    const post = await payload.create({
      collection: 'posts',
      data: {
        title: 'Hello World! @2025 -- Amazing',
        author: adminUser.id,
      },
    })

    expect(post.slug).toBe('hello-world-2025-amazing')
  })

  it('should auto-set publishDate when status changes to published', async () => {
    const post = await createTestPost(payload, adminUser.id, {
      status: 'draft',
      slug: 'publish-test',
    })
    expect(post.publishDate).toBeUndefined()

    const updated = await payload.update({
      collection: 'posts',
      id: post.id,
      data: { status: 'published' },
    })

    expect(updated.publishDate).toBeDefined()
    expect(new Date(updated.publishDate)).toBeInstanceOf(Date)
  })

  it('should calculate order total from line items via beforeChange', async () => {
    const order = await payload.create({
      collection: 'orders',
      data: {
        customer: adminUser.id,
        items: [
          { product: 'Widget', price: 29.99, quantity: 2 },
          { product: 'Gadget', price: 49.99, quantity: 1 },
        ],
      },
    })

    expect(order.total).toBeCloseTo(109.97, 2)
  })

  it('should prevent deletion of published posts via beforeDelete', async () => {
    const post = await createTestPost(payload, adminUser.id, {
      status: 'published',
      slug: 'no-delete',
    })

    await expect(
      payload.delete({ collection: 'posts', id: post.id }),
    ).rejects.toThrow('Cannot delete published posts')
  })
})
```

---

## Access Control Testing

```typescript
// src/access/Posts.test.ts
describe('Post Access Control', () => {
  let viewerUser: any
  let authorUser: any

  beforeAll(async () => {
    viewerUser = await createTestUser(payload, {
      email: 'viewer@test.com',
      role: 'viewer',
    })
    authorUser = await createTestUser(payload, {
      email: 'author@test.com',
      role: 'author',
    })
  })

  it('should allow unauthenticated users to read published posts only', async () => {
    await createTestPost(payload, adminUser.id, { status: 'published', slug: 'public-post' })
    await createTestPost(payload, adminUser.id, { status: 'draft', slug: 'private-draft' })

    // Simulate unauthenticated request
    const result = await payload.find({
      collection: 'posts',
      overrideAccess: false,
      // No user = unauthenticated
    })

    expect(result.docs.every((doc) => doc.status === 'published')).toBe(true)
  })

  it('should allow authors to read their own drafts', async () => {
    await createTestPost(payload, authorUser.id, {
      status: 'draft',
      slug: 'author-draft',
    })

    const result = await payload.find({
      collection: 'posts',
      overrideAccess: false,
      user: authorUser,
    })

    expect(result.docs).toHaveLength(1)
  })

  it('should prevent viewers from creating posts', async () => {
    await expect(
      payload.create({
        collection: 'posts',
        overrideAccess: false,
        user: viewerUser,
        data: {
          title: 'Unauthorized Post',
          slug: 'unauthorized',
          author: viewerUser.id,
        },
      }),
    ).rejects.toThrow()
  })

  it('should prevent authors from deleting others posts', async () => {
    const adminPost = await createTestPost(payload, adminUser.id, { slug: 'admin-post' })

    await expect(
      payload.delete({
        collection: 'posts',
        id: adminPost.id,
        overrideAccess: false,
        user: authorUser,
      }),
    ).rejects.toThrow()
  })

  it('should allow admins full access', async () => {
    const post = await createTestPost(payload, editorUser.id, { slug: 'any-post' })

    const updated = await payload.update({
      collection: 'posts',
      id: post.id,
      overrideAccess: false,
      user: adminUser,
      data: { title: 'Admin Updated' },
    })

    expect(updated.title).toBe('Admin Updated')
  })
})
```

---

## REST API Testing

```typescript
// src/api/posts.test.ts
import { describe, it, expect, beforeAll } from 'vitest'

const API_URL = process.env.PAYLOAD_PUBLIC_SERVER_URL || 'http://localhost:3000'

describe('Posts REST API', () => {
  let authToken: string

  beforeAll(async () => {
    // Login to get token
    const loginResponse = await fetch(`${API_URL}/api/users/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'admin@test.com',
        password: 'test-password-123',
      }),
    })

    const loginData = await loginResponse.json()
    authToken = loginData.token
  })

  it('GET /api/posts should return paginated posts', async () => {
    const response = await fetch(`${API_URL}/api/posts?limit=10&page=1`)
    const data = await response.json()

    expect(response.status).toBe(200)
    expect(data).toHaveProperty('docs')
    expect(data).toHaveProperty('totalDocs')
    expect(data).toHaveProperty('totalPages')
    expect(Array.isArray(data.docs)).toBe(true)
  })

  it('POST /api/posts should create with valid auth', async () => {
    const response = await fetch(`${API_URL}/api/posts`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `JWT ${authToken}`,
      },
      body: JSON.stringify({
        title: 'API Created Post',
        slug: `api-post-${Date.now()}`,
        status: 'draft',
      }),
    })

    const data = await response.json()
    expect(response.status).toBe(201)
    expect(data.doc.title).toBe('API Created Post')
  })

  it('POST /api/posts should reject without auth', async () => {
    const response = await fetch(`${API_URL}/api/posts`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        title: 'Unauthorized Post',
        slug: 'unauthorized',
      }),
    })

    expect(response.status).toBe(401)
  })

  it('GET /api/users/me should return current user', async () => {
    const response = await fetch(`${API_URL}/api/users/me`, {
      headers: {
        Authorization: `JWT ${authToken}`,
      },
    })

    const data = await response.json()
    expect(response.status).toBe(200)
    expect(data.user.email).toBe('admin@test.com')
  })
})
```

---

## GraphQL API Testing

```typescript
// src/api/graphql.test.ts
describe('Posts GraphQL API', () => {
  const graphqlRequest = async (query: string, variables?: any, token?: string) => {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' }
    if (token) headers.Authorization = `JWT ${token}`

    const response = await fetch(`${API_URL}/api/graphql`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ query, variables }),
    })

    return response.json()
  }

  it('should query posts via GraphQL', async () => {
    const result = await graphqlRequest(`
      query {
        Posts(limit: 10) {
          docs {
            id
            title
            slug
          }
          totalDocs
        }
      }
    `)

    expect(result.data.Posts).toBeDefined()
    expect(Array.isArray(result.data.Posts.docs)).toBe(true)
  })

  it('should create post via GraphQL mutation', async () => {
    const result = await graphqlRequest(
      `
      mutation CreatePost($data: mutationPostInput!) {
        createPost(data: $data) {
          id
          title
          slug
        }
      }
    `,
      {
        data: {
          title: 'GraphQL Post',
          slug: `graphql-post-${Date.now()}`,
          status: 'draft',
        },
      },
      authToken,
    )

    expect(result.data.createPost.title).toBe('GraphQL Post')
  })
})
```

---

## Seed Data Patterns

```typescript
// src/seed/index.ts
import type { Payload } from 'payload'

export async function seed(payload: Payload): Promise<void> {
  console.log('Seeding database...')

  // 1. Create admin user
  const admin = await payload.create({
    collection: 'users',
    data: {
      email: 'admin@example.com',
      password: 'admin-password-123',
      name: 'Admin User',
      role: 'admin',
    },
  })

  // 2. Create categories
  const categories = await Promise.all(
    ['Technology', 'Design', 'Business', 'Marketing'].map((name) =>
      payload.create({
        collection: 'categories',
        data: {
          name,
          slug: name.toLowerCase(),
          description: `Articles about ${name}`,
        },
      }),
    ),
  )

  // 3. Create sample posts
  const posts = [
    {
      title: 'Getting Started with Payload CMS',
      slug: 'getting-started-payload-cms',
      status: 'published',
      category: categories[0].id,
      author: admin.id,
    },
    {
      title: 'Design Systems in 2025',
      slug: 'design-systems-2025',
      status: 'published',
      category: categories[1].id,
      author: admin.id,
    },
    {
      title: 'Draft Post Example',
      slug: 'draft-post-example',
      status: 'draft',
      category: categories[2].id,
      author: admin.id,
    },
  ]

  for (const post of posts) {
    await payload.create({
      collection: 'posts',
      data: post,
    })
  }

  console.log('Seeding complete.')
}

// src/seed/run.ts - Standalone seed script
import { getPayload } from 'payload'
import config from '../../payload.config'
import { seed } from './index'

async function runSeed() {
  const payload = await getPayload({ config })
  await seed(payload)
  process.exit(0)
}

runSeed().catch((err) => {
  console.error('Seed failed:', err)
  process.exit(1)
})
```

```json
// package.json scripts
{
  "scripts": {
    "seed": "tsx src/seed/run.ts",
    "seed:fresh": "tsx src/seed/reset.ts && tsx src/seed/run.ts"
  }
}
```

---

## Migration Testing

### Testing Database Migrations

```typescript
// src/migrations/test-migration.test.ts
import { describe, it, expect } from 'vitest'
import { getPayload } from 'payload'
import config from '../../payload.config'

describe('Database Migrations', () => {
  it('should run all pending migrations without errors', async () => {
    const payload = await getPayload({ config })

    // Run migrations
    await expect(payload.db.migrate()).resolves.not.toThrow()
  })

  it('should have all expected collections after migration', async () => {
    const payload = await getPayload({ config })

    // Verify collections exist by attempting to query them
    const collections = ['users', 'posts', 'categories', 'media']

    for (const collection of collections) {
      const result = await payload.find({
        collection: collection as any,
        limit: 0,
      })
      expect(result).toHaveProperty('totalDocs')
    }
  })
})
```

### Migration Scripts

```bash
# Generate a new migration
npx payload migrate:create add_featured_field

# Run pending migrations
npx payload migrate

# Check migration status
npx payload migrate:status

# Rollback last migration (PostgreSQL only)
npx payload migrate:down
```

---

## Deployment -- Vercel

### Vercel Configuration

```typescript
// next.config.mjs
import { withPayload } from '@payloadcms/next/withPayload'

/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    reactCompiler: false,
  },
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: '**.vercel.app',
      },
    ],
  },
}

export default withPayload(nextConfig)
```

```bash
# Vercel environment variables
PAYLOAD_SECRET=your-secret-key-min-32-chars
DATABASE_URI=postgres://user:pass@host:5432/dbname
# OR for MongoDB:
# MONGODB_URI=mongodb+srv://...

# Storage (Vercel Blob)
BLOB_READ_WRITE_TOKEN=vercel-blob-token

# Optional
NEXT_PUBLIC_SITE_URL=https://your-site.vercel.app
```

### Vercel Blob Storage

```typescript
// payload.config.ts
import { vercelBlobStorage } from '@payloadcms/storage-vercel-blob'

export default buildConfig({
  plugins: [
    vercelBlobStorage({
      collections: {
        media: true,
      },
      token: process.env.BLOB_READ_WRITE_TOKEN || '',
    }),
  ],
})
```

---

## Deployment -- Docker

### Dockerfile

```dockerfile
# Dockerfile
FROM node:20-alpine AS base

# Install dependencies
FROM base AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile

# Build
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

RUN corepack enable pnpm && pnpm build

# Production
FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["node", "server.js"]
```

### Docker Compose

```yaml
# docker-compose.yml
services:
  payload:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URI=postgres://payload:payload@postgres:5432/payload
      - PAYLOAD_SECRET=${PAYLOAD_SECRET}
      - NODE_ENV=production
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: payload
      POSTGRES_USER: payload
      POSTGRES_PASSWORD: payload
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U payload"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Optional: MongoDB alternative
  # mongo:
  #   image: mongo:7
  #   environment:
  #     MONGO_INITDB_ROOT_USERNAME: payload
  #     MONGO_INITDB_ROOT_PASSWORD: payload
  #   volumes:
  #     - mongo_data:/data/db

volumes:
  postgres_data:
```

---

## CI/CD Pipeline

### GitHub Actions

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: payload_test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 9
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile

      - name: Generate Payload types
        run: pnpm payload generate:types
        env:
          DATABASE_URI: postgres://test:test@localhost:5432/payload_test
          PAYLOAD_SECRET: ci-test-secret-minimum-32-characters

      - name: Run migrations
        run: pnpm payload migrate
        env:
          DATABASE_URI: postgres://test:test@localhost:5432/payload_test
          PAYLOAD_SECRET: ci-test-secret-minimum-32-characters

      - name: Run tests
        run: pnpm test
        env:
          DATABASE_URI: postgres://test:test@localhost:5432/payload_test
          PAYLOAD_SECRET: ci-test-secret-minimum-32-characters

      - name: Build
        run: pnpm build
        env:
          DATABASE_URI: postgres://test:test@localhost:5432/payload_test
          PAYLOAD_SECRET: ci-test-secret-minimum-32-characters

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          vercel-args: '--prod'
```

---

## Environment Configuration

```typescript
// src/env.ts - Type-safe environment variables
import { z } from 'zod'

const envSchema = z.object({
  DATABASE_URI: z.string().url(),
  PAYLOAD_SECRET: z.string().min(32),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  NEXT_PUBLIC_SITE_URL: z.string().url().optional(),
  S3_BUCKET: z.string().optional(),
  S3_REGION: z.string().optional(),
  S3_ACCESS_KEY: z.string().optional(),
  S3_SECRET_KEY: z.string().optional(),
  SMTP_HOST: z.string().optional(),
  SMTP_PORT: z.coerce.number().optional(),
  SMTP_USER: z.string().optional(),
  SMTP_PASS: z.string().optional(),
})

export const env = envSchema.parse(process.env)
```

---

## Best Practices

1. **Test via the local API** - Most Payload tests should use `payload.find()`, `payload.create()`, etc.
2. **Use `overrideAccess: false` in access control tests** - Default is `true`, which bypasses access control
3. **Clean up test data between tests** - Use `afterEach` to delete test documents
4. **Test hooks by observing side effects** - Create/update documents and verify computed fields
5. **Use test helpers** - Extract `createTestUser`, `createTestPost` into shared helpers
6. **Test both positive and negative access control** - Verify what IS and IS NOT allowed
7. **Run tests sequentially for database tests** - Use `singleFork: true` in Vitest config
8. **Use a separate test database** - Never run tests against production or development databases
9. **Seed data scripts should be idempotent** - Running seed twice should not fail
10. **Use multi-stage Docker builds** - Keeps production images small
11. **Always run migrations in CI** - Catch migration issues before deployment
12. **Store PAYLOAD_SECRET securely** - Use environment variables, never commit to code

---

## Anti-Patterns

- Testing with `overrideAccess: true` (default) and assuming access control works
- Not cleaning up test data between test runs (tests depend on each other)
- Using the REST API for integration tests when the local API would be simpler
- Not testing hooks in isolation (relying on manual testing)
- Skipping access control tests ("we trust the framework")
- Running tests against the development database
- Not running migrations in CI pipelines
- Using `latest` Docker image tags in production
- Hardcoding `PAYLOAD_SECRET` in the codebase
- Not generating TypeScript types in CI (type mismatches in production)

---

## Sources & References

- [Payload CMS 3.0 Documentation - Local API](https://payloadcms.com/docs/local-api/overview)
- [Payload CMS 3.0 Documentation - Deployment](https://payloadcms.com/docs/production/deployment)
- [Payload CMS GitHub - Test Suite Examples](https://github.com/payloadcms/payload/tree/main/test)
- [Payload CMS 3.0 Documentation - Database Migrations](https://payloadcms.com/docs/database/migrations)
- [Payload CMS 3.0 Documentation - Vercel Blob Storage](https://payloadcms.com/docs/upload/storage-adapters#vercel-blob)
- [Vitest Documentation - Configuration](https://vitest.dev/config/)
- [Payload CMS Blog - Deploying to Production](https://payloadcms.com/blog/deploying-payload)
