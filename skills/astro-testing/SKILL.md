---
name: astro-testing
description: Testing Astro apps with Vitest, Playwright, Astro Container API, performance testing, deployment (Vercel/Netlify/Cloudflare), CI/CD pipelines
---

# Astro Testing & Deployment

Production-ready patterns for testing, performance validation, and deploying Astro 5.x sites. Covers unit testing with Vitest, the Astro Container API for component testing, end-to-end testing with Playwright, performance audits, and deployment to Vercel, Netlify, and Cloudflare Pages with CI/CD pipelines.

## Table of Contents

1. [Vitest Setup for Astro](#vitest-setup-for-astro)
2. [Unit Testing Utilities & Logic](#unit-testing-utilities--logic)
3. [Astro Container API (Component Testing)](#astro-container-api-component-testing)
4. [Testing Framework Components](#testing-framework-components)
5. [Playwright E2E Testing](#playwright-e2e-testing)
6. [Testing Content Collections](#testing-content-collections)
7. [Testing Astro Actions](#testing-astro-actions)
8. [Performance Testing](#performance-testing)
9. [Accessibility Testing](#accessibility-testing)
10. [Deployment: Vercel](#deployment-vercel)
11. [Deployment: Netlify](#deployment-netlify)
12. [Deployment: Cloudflare Pages](#deployment-cloudflare-pages)
13. [CI/CD Pipeline](#cicd-pipeline)
14. [Best Practices](#best-practices)
15. [Anti-Patterns](#anti-patterns)

---

## Vitest Setup for Astro

Vitest is the recommended test runner for Astro projects. It shares the same Vite-based config pipeline.

### Installation

```bash
pnpm add -D vitest @vitest/ui
```

### Configuration

```typescript
// vitest.config.ts
import { getViteConfig } from 'astro/config';

export default getViteConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['src/**/*.test.ts', 'tests/**/*.test.ts'],
    exclude: ['tests/e2e/**'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      include: ['src/lib/**', 'src/actions/**'],
      thresholds: {
        statements: 80,
        branches: 80,
        functions: 80,
        lines: 80,
      },
    },
  },
});
```

**Important:** Use `getViteConfig` from `astro/config` instead of `defineConfig` from Vitest. This ensures Astro-specific aliases like `astro:content` resolve correctly in tests.

### Package Scripts

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:ui": "vitest --ui",
    "test:coverage": "vitest run --coverage",
    "test:e2e": "playwright test"
  }
}
```

---

## Unit Testing Utilities & Logic

Test pure TypeScript utilities, helpers, and business logic without any Astro-specific imports.

```typescript
// src/lib/format.ts
export function formatDate(date: Date, locale = 'en-US'): string {
  return date.toLocaleDateString(locale, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

export function slugify(text: string): string {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_]+/g, '-')
    .replace(/-+/g, '-');
}

export function readingTime(text: string, wordsPerMinute = 200): number {
  const words = text.trim().split(/\s+/).length;
  return Math.ceil(words / wordsPerMinute);
}

export function truncate(text: string, maxLength: number): string {
  if (text.length <= maxLength) return text;
  return text.slice(0, maxLength).trimEnd() + '...';
}
```

```typescript
// src/lib/format.test.ts
import { describe, it, expect } from 'vitest';
import { formatDate, slugify, readingTime, truncate } from './format';

describe('formatDate', () => {
  it('formats a date in US locale', () => {
    const date = new Date('2025-06-15');
    expect(formatDate(date)).toBe('June 15, 2025');
  });

  it('supports custom locales', () => {
    const date = new Date('2025-06-15');
    expect(formatDate(date, 'de-DE')).toBe('15. Juni 2025');
  });
});

describe('slugify', () => {
  it('converts text to URL-safe slug', () => {
    expect(slugify('Hello World!')).toBe('hello-world');
  });

  it('handles multiple spaces and dashes', () => {
    expect(slugify('  too   many  spaces  ')).toBe('too-many-spaces');
  });

  it('removes special characters', () => {
    expect(slugify('Astro 5.0: What\'s New?')).toBe('astro-50-whats-new');
  });
});

describe('readingTime', () => {
  it('calculates reading time for short text', () => {
    const text = Array(200).fill('word').join(' ');
    expect(readingTime(text)).toBe(1);
  });

  it('rounds up to next minute', () => {
    const text = Array(201).fill('word').join(' ');
    expect(readingTime(text)).toBe(2);
  });

  it('accepts custom words-per-minute', () => {
    const text = Array(300).fill('word').join(' ');
    expect(readingTime(text, 100)).toBe(3);
  });
});

describe('truncate', () => {
  it('returns full text if shorter than max', () => {
    expect(truncate('short', 10)).toBe('short');
  });

  it('truncates and adds ellipsis', () => {
    expect(truncate('This is a long sentence', 10)).toBe('This is a...');
  });
});
```

---

## Astro Container API (Component Testing)

Astro 5 introduced the Container API (experimental) for rendering Astro components in isolation during tests, without starting a dev server.

### Setup

```typescript
// src/components/Greeting.test.ts
import { experimental_AstroContainer as AstroContainer } from 'astro/container';
import { describe, it, expect } from 'vitest';
import Greeting from './Greeting.astro';

describe('Greeting', () => {
  it('renders with the provided name', async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Greeting, {
      props: { name: 'Alice' },
    });

    expect(result).toContain('Hello, Alice');
  });

  it('renders with default name when none provided', async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Greeting, {
      props: {},
    });

    expect(result).toContain('Hello, World');
  });
});
```

### Testing Components with Slots

```typescript
// src/components/Alert.test.ts
import { experimental_AstroContainer as AstroContainer } from 'astro/container';
import { describe, it, expect } from 'vitest';
import Alert from './Alert.astro';

describe('Alert', () => {
  it('renders the default slot content', async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Alert, {
      props: { type: 'warning' },
      slots: {
        default: '<strong>Watch out!</strong> Something happened.',
      },
    });

    expect(result).toContain('Watch out!');
    expect(result).toContain('alert--warning');
  });

  it('renders named slots', async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Alert, {
      props: { type: 'info' },
      slots: {
        default: 'Main content',
        icon: '<svg class="custom-icon"></svg>',
      },
    });

    expect(result).toContain('Main content');
    expect(result).toContain('custom-icon');
  });
});
```

### Testing Components with Astro Locals

```typescript
// src/components/UserBadge.test.ts
import { experimental_AstroContainer as AstroContainer } from 'astro/container';
import { describe, it, expect } from 'vitest';
import UserBadge from './UserBadge.astro';

describe('UserBadge', () => {
  it('shows the user name from locals', async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(UserBadge, {
      locals: {
        user: { name: 'Alice', role: 'admin' },
      },
    });

    expect(result).toContain('Alice');
    expect(result).toContain('admin');
  });
});
```

---

## Testing Framework Components

Test React, Svelte, or Vue components used in Astro islands with their standard testing libraries.

### React Component Testing

```tsx
// src/components/react/SearchBar.test.tsx
import { render, screen, waitFor } from '@testing-library/react';
import { userEvent } from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';
import SearchBar from './SearchBar';

describe('SearchBar', () => {
  it('calls onSearch with debounced input', async () => {
    const onSearch = vi.fn();
    const user = userEvent.setup();

    render(<SearchBar onSearch={onSearch} />);

    const input = screen.getByRole('searchbox');
    await user.type(input, 'astro');

    await waitFor(() => {
      expect(onSearch).toHaveBeenCalledWith('astro');
    });
  });

  it('shows clear button when input has value', async () => {
    const user = userEvent.setup();
    render(<SearchBar onSearch={vi.fn()} />);

    const input = screen.getByRole('searchbox');
    await user.type(input, 'test');

    expect(screen.getByRole('button', { name: /clear/i })).toBeInTheDocument();
  });
});
```

### Vitest Config for React/Svelte Testing

```typescript
// vitest.config.ts
import { getViteConfig } from 'astro/config';

export default getViteConfig({
  test: {
    globals: true,
    environment: 'jsdom', // Use jsdom for framework component tests
    setupFiles: ['./tests/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
```

```typescript
// tests/setup.ts
import '@testing-library/jest-dom/vitest';
```

---

## Playwright E2E Testing

Playwright tests verify the full user experience including hydration, navigation, and View Transitions.

### Setup

```bash
pnpm add -D @playwright/test
npx playwright install
```

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,

  use: {
    baseURL: 'http://localhost:4321',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'mobile', use: { ...devices['iPhone 14'] } },
  ],

  webServer: {
    command: 'pnpm preview',
    port: 4321,
    reuseExistingServer: !process.env.CI,
  },
});
```

### E2E Test Examples

```typescript
// tests/e2e/navigation.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Site navigation', () => {
  test('navigates between pages with View Transitions', async ({ page }) => {
    await page.goto('/');

    // Click navigation link
    await page.getByRole('link', { name: 'Blog' }).click();
    await expect(page).toHaveURL('/blog');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Blog');

    // Click a blog post
    await page.getByRole('link', { name: /getting started/i }).click();
    await expect(page.getByRole('article')).toBeVisible();
  });

  test('search returns matching results', async ({ page }) => {
    await page.goto('/');

    const searchInput = page.getByRole('searchbox');
    await searchInput.fill('astro');

    // Wait for search results to appear (island hydration)
    await expect(page.getByTestId('search-results')).toBeVisible();
    await expect(page.getByTestId('search-results')).toContainText('Astro');
  });

  test('newsletter form submits via Astro Action', async ({ page }) => {
    await page.goto('/');

    await page.getByLabel('Email').fill('test@example.com');
    await page.getByRole('button', { name: /subscribe/i }).click();

    await expect(page.getByText(/successfully subscribed/i)).toBeVisible();
  });
});
```

### Testing Island Hydration

```typescript
// tests/e2e/hydration.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Island hydration', () => {
  test('counter hydrates and is interactive', async ({ page }) => {
    await page.goto('/');

    const counter = page.getByTestId('counter');
    await expect(counter).toBeVisible();

    // Wait for hydration (button becomes clickable)
    const incrementBtn = counter.getByRole('button', { name: '+' });
    await incrementBtn.click();

    await expect(counter.getByText('1')).toBeVisible();
  });

  test('lazy-loaded island hydrates on scroll', async ({ page }) => {
    await page.goto('/');

    const commentSection = page.getByTestId('comments');

    // Should not be hydrated yet (below fold)
    await expect(commentSection).not.toBeVisible();

    // Scroll to comments section
    await commentSection.scrollIntoViewIfNeeded();

    // Wait for hydration
    await expect(
      commentSection.getByRole('textbox', { name: /comment/i })
    ).toBeVisible({ timeout: 5000 });
  });
});
```

---

## Testing Content Collections

```typescript
// src/lib/content-utils.test.ts
import { describe, it, expect, vi } from 'vitest';

// Mock astro:content
vi.mock('astro:content', () => ({
  getCollection: vi.fn(),
  getEntry: vi.fn(),
}));

import { getCollection } from 'astro:content';
import { getPublishedPosts, getPostsByTag } from './content-utils';

describe('getPublishedPosts', () => {
  it('excludes draft posts and sorts by date descending', async () => {
    const mockPosts = [
      { id: 'old', data: { title: 'Old', pubDate: new Date('2025-01-01'), draft: false, tags: [] } },
      { id: 'new', data: { title: 'New', pubDate: new Date('2025-06-01'), draft: false, tags: [] } },
      { id: 'draft', data: { title: 'Draft', pubDate: new Date('2025-07-01'), draft: true, tags: [] } },
    ];

    vi.mocked(getCollection).mockResolvedValue(mockPosts as any);

    const posts = await getPublishedPosts();

    expect(posts).toHaveLength(2);
    expect(posts[0].id).toBe('new');
    expect(posts[1].id).toBe('old');
  });
});

describe('getPostsByTag', () => {
  it('returns posts matching the given tag', async () => {
    const mockPosts = [
      { id: 'a', data: { title: 'A', pubDate: new Date(), draft: false, tags: ['astro', 'ssr'] } },
      { id: 'b', data: { title: 'B', pubDate: new Date(), draft: false, tags: ['react'] } },
      { id: 'c', data: { title: 'C', pubDate: new Date(), draft: false, tags: ['astro'] } },
    ];

    vi.mocked(getCollection).mockResolvedValue(mockPosts as any);

    const posts = await getPostsByTag('astro');

    expect(posts).toHaveLength(2);
    expect(posts.map((p) => p.id)).toEqual(expect.arrayContaining(['a', 'c']));
  });
});
```

---

## Testing Astro Actions

```typescript
// src/actions/newsletter.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Test the handler logic directly
import { subscribeHandler } from './handlers/newsletter';

describe('newsletter subscribe action', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('subscribes a valid email', async () => {
    const result = await subscribeHandler({
      email: 'test@example.com',
      name: 'Alice',
    });

    expect(result).toEqual({
      success: true,
      message: 'Subscribed test@example.com',
    });
  });

  it('handles duplicate subscription gracefully', async () => {
    // First call succeeds
    await subscribeHandler({ email: 'test@example.com' });

    // Second call should still succeed (idempotent)
    const result = await subscribeHandler({ email: 'test@example.com' });
    expect(result.success).toBe(true);
  });
});
```

---

## Performance Testing

### Lighthouse CI

```bash
pnpm add -D @lhci/cli
```

```json
// lighthouserc.json
{
  "ci": {
    "collect": {
      "url": [
        "http://localhost:4321/",
        "http://localhost:4321/blog",
        "http://localhost:4321/blog/first-post"
      ],
      "startServerCommand": "pnpm preview",
      "numberOfRuns": 3
    },
    "assert": {
      "assertions": {
        "categories:performance": ["error", { "minScore": 0.9 }],
        "categories:accessibility": ["error", { "minScore": 0.95 }],
        "categories:best-practices": ["error", { "minScore": 0.9 }],
        "categories:seo": ["error", { "minScore": 0.9 }]
      }
    },
    "upload": {
      "target": "temporary-public-storage"
    }
  }
}
```

### Bundle Size Check

```typescript
// tests/performance/bundle-size.test.ts
import { describe, it, expect } from 'vitest';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

function getDirectorySize(dir: string): number {
  let total = 0;
  for (const file of readdirSync(dir, { recursive: true }) as string[]) {
    const filePath = join(dir, file);
    const stat = statSync(filePath, { throwIfNoEntry: false });
    if (stat?.isFile()) {
      total += stat.size;
    }
  }
  return total;
}

describe('Bundle size', () => {
  it('total JS output is under 100KB', () => {
    const jsSize = getDirectorySize('dist/_astro');
    const jsKB = jsSize / 1024;

    console.log(`Total JS bundle: ${jsKB.toFixed(1)} KB`);
    expect(jsKB).toBeLessThan(100);
  });
});
```

### Core Web Vitals with Playwright

```typescript
// tests/e2e/performance.spec.ts
import { test, expect } from '@playwright/test';

test('home page meets Core Web Vitals thresholds', async ({ page }) => {
  await page.goto('/');

  // Measure Largest Contentful Paint
  const lcp = await page.evaluate(() => {
    return new Promise<number>((resolve) => {
      new PerformanceObserver((list) => {
        const entries = list.getEntries();
        const last = entries[entries.length - 1];
        resolve(last.startTime);
      }).observe({ type: 'largest-contentful-paint', buffered: true });
    });
  });

  expect(lcp).toBeLessThan(2500); // Good LCP is under 2.5s

  // Measure Cumulative Layout Shift
  const cls = await page.evaluate(() => {
    return new Promise<number>((resolve) => {
      let shift = 0;
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries() as any[]) {
          if (!entry.hadRecentInput) {
            shift += entry.value;
          }
        }
        resolve(shift);
      }).observe({ type: 'layout-shift', buffered: true });

      setTimeout(() => resolve(shift), 3000);
    });
  });

  expect(cls).toBeLessThan(0.1); // Good CLS is under 0.1
});
```

---

## Accessibility Testing

```typescript
// tests/e2e/accessibility.spec.ts
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test.describe('Accessibility', () => {
  test('home page has no accessibility violations', async ({ page }) => {
    await page.goto('/');

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
      .analyze();

    expect(results.violations).toEqual([]);
  });

  test('blog post page is accessible', async ({ page }) => {
    await page.goto('/blog/first-post');

    const results = await new AxeBuilder({ page })
      .exclude('.third-party-widget') // Exclude third-party content
      .analyze();

    expect(results.violations).toEqual([]);
  });

  test('focus management works with View Transitions', async ({ page }) => {
    await page.goto('/');

    // Navigate via keyboard
    await page.keyboard.press('Tab');
    await page.keyboard.press('Enter');

    // After View Transition, focus should be managed
    await page.waitForURL('/blog');
    const focusedElement = await page.evaluate(() =>
      document.activeElement?.tagName
    );

    // Focus should be on a meaningful element, not stuck on body
    expect(focusedElement).not.toBe('BODY');
  });
});
```

---

## Deployment: Vercel

### Adapter Setup

```bash
pnpm add @astrojs/vercel
```

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import vercel from '@astrojs/vercel';

export default defineConfig({
  output: 'hybrid',
  adapter: vercel({
    imageService: true,       // Use Vercel's image optimization
    isr: {
      expiration: 60 * 60,   // ISR: revalidate every hour
    },
    webAnalytics: {
      enabled: true,
    },
  }),
});
```

### Vercel Configuration

```json
// vercel.json
{
  "framework": "astro",
  "buildCommand": "pnpm build",
  "outputDirectory": "dist",
  "headers": [
    {
      "source": "/_astro/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    }
  ]
}
```

---

## Deployment: Netlify

### Adapter Setup

```bash
pnpm add @astrojs/netlify
```

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import netlify from '@astrojs/netlify';

export default defineConfig({
  output: 'hybrid',
  adapter: netlify({
    edgeMiddleware: true, // Use Netlify Edge Functions for middleware
  }),
});
```

### Netlify Configuration

```toml
# netlify.toml
[build]
  command = "pnpm build"
  publish = "dist"

[[headers]]
  for = "/_astro/*"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"

[[redirects]]
  from = "/old-path"
  to = "/new-path"
  status = 301
```

---

## Deployment: Cloudflare Pages

### Adapter Setup

```bash
pnpm add @astrojs/cloudflare
```

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import cloudflare from '@astrojs/cloudflare';

export default defineConfig({
  output: 'hybrid',
  adapter: cloudflare({
    platformProxy: {
      enabled: true, // Access KV, D1, R2 via platform.env
    },
  }),
});
```

### Wrangler Configuration

```toml
# wrangler.toml
name = "my-astro-site"
compatibility_date = "2025-01-01"
pages_build_output_dir = "dist"

[[kv_namespaces]]
binding = "CACHE"
id = "abc123"

[[d1_databases]]
binding = "DB"
database_name = "my-database"
database_id = "def456"
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
    steps:
      - uses: actions/checkout@v4

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 9

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'pnpm'

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Type check
        run: pnpm astro check

      - name: Lint
        run: pnpm lint

      - name: Unit tests
        run: pnpm test

      - name: Build
        run: pnpm build

      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium

      - name: E2E tests
        run: pnpm test:e2e

      - name: Lighthouse CI
        run: npx @lhci/cli autorun
        env:
          LHCI_GITHUB_APP_TOKEN: ${{ secrets.LHCI_GITHUB_APP_TOKEN }}

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 9

      - name: Install and build
        run: pnpm install --frozen-lockfile && pnpm build

      - name: Deploy to Vercel
        uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          vercel-args: '--prod'
```

### Preview Deployments for PRs

```yaml
# .github/workflows/preview.yml
name: Preview

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - run: pnpm install --frozen-lockfile && pnpm build

      - name: Deploy preview
        uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}

      - name: Comment PR with preview URL
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `Preview deployed: ${{ steps.deploy.outputs.preview-url }}`
            });
```

---

## Best Practices

1. **Use `getViteConfig`** from `astro/config` in `vitest.config.ts` so Astro aliases resolve correctly
2. **Separate unit and E2E tests** in different directories with different configs
3. **Use the Container API** for testing Astro component output (props, slots, locals)
4. **Test framework components** with their standard testing libraries (RTL for React, Svelte Testing Library, etc.)
5. **Mock `astro:content`** in unit tests with `vi.mock()` to avoid file system dependencies
6. **Run Lighthouse CI** on every PR to catch performance regressions
7. **Test island hydration** in Playwright to verify interactivity works after the page loads
8. **Set coverage thresholds** for `src/lib/` and `src/actions/` to enforce quality
9. **Use preview deployments** so reviewers can test changes before merge
10. **Cache static assets** with immutable cache headers in production (`/_astro/*`)
11. **Run `astro check`** in CI to catch TypeScript and Astro template errors
12. **Test accessibility** with axe-core in Playwright on every page template

---

## Anti-Patterns

- Using `defineConfig` from Vitest instead of `getViteConfig` from Astro (breaks `astro:content` imports)
- Testing Astro component internals by parsing HTML strings instead of using the Container API
- Skipping E2E tests for hydrated islands (unit tests do not verify client-side behavior)
- Not testing View Transitions navigation (broken transitions degrade user experience)
- Running Lighthouse only locally instead of in CI (performance drifts without automated checks)
- Deploying without `astro check` in CI (type errors in templates go undetected)
- Hardcoding localhost URLs in tests instead of using `baseURL` in Playwright config
- Not setting up preview deployments for pull requests (slows down review)
- Caching SSR pages without setting appropriate revalidation headers
- Deploying SSR without the correct adapter for the target platform

---

## Sources & References

- [Astro Documentation: Testing](https://docs.astro.build/en/guides/testing/)
- [Astro Documentation: Container API](https://docs.astro.build/en/reference/container-reference/)
- [Astro Documentation: Deploy Guides](https://docs.astro.build/en/guides/deploy/)
- [Playwright Documentation](https://playwright.dev)
- [Vitest Documentation](https://vitest.dev)
- [Lighthouse CI](https://github.com/GoogleChrome/lighthouse-ci)
- [Axe-Core Playwright](https://github.com/dequelabs/axe-core-npm/tree/develop/packages/playwright)
