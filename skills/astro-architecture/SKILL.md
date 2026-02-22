---
name: astro-architecture
description: Astro 5.x project architecture — islands architecture, SSG/SSR/hybrid rendering, file-based routing, middleware, Server Islands, View Transitions API, project structure
---

# Astro Architecture & Project Structure

Production-ready architecture patterns for Astro 5.x in 2026. Covers the islands architecture philosophy, rendering modes (SSG/SSR/hybrid), file-based routing, middleware, Server Islands, the View Transitions API, project structure conventions, and integration patterns.

## Table of Contents

1. [Islands Architecture](#islands-architecture)
2. [Astro 5 Key Features](#astro-5-key-features)
3. [Rendering Modes](#rendering-modes)
4. [File-Based Routing](#file-based-routing)
5. [Server Islands](#server-islands)
6. [View Transitions API](#view-transitions-api)
7. [Middleware](#middleware)
8. [Project Structure](#project-structure)
9. [Environment Variables & Configuration](#environment-variables--configuration)
10. [Astro Config Patterns](#astro-config-patterns)
11. [Best Practices](#best-practices)
12. [Anti-Patterns](#anti-patterns)

---

## Islands Architecture

Astro pioneered the islands architecture for the web. Every page is rendered as static HTML by default, with interactive "islands" of JavaScript hydrated independently. This results in zero JavaScript shipped unless explicitly opted in.

### Core Principles

- **HTML-first**: Pages are static HTML by default with no client-side JS
- **Opt-in interactivity**: Only components marked with `client:*` directives ship JavaScript
- **Framework-agnostic**: Islands can be React, Svelte, Vue, Solid, Preact, or Lit
- **Independent hydration**: Each island hydrates on its own schedule, not blocking others

### How Islands Work

```astro
---
// src/pages/index.astro
// This runs at build time (SSG) or request time (SSR)
import Header from '../components/Header.astro';
import HeroSection from '../components/HeroSection.astro';
import SearchWidget from '../components/SearchWidget.tsx';
import NewsletterForm from '../components/NewsletterForm.svelte';
import Footer from '../components/Footer.astro';
---

<html lang="en">
  <body>
    <!-- Static HTML - zero JS -->
    <Header />
    <HeroSection />

    <!-- Interactive island - hydrates immediately -->
    <SearchWidget client:load />

    <!-- Interactive island - hydrates when visible -->
    <NewsletterForm client:visible />

    <!-- Static HTML - zero JS -->
    <Footer />
  </body>
</html>
```

### Performance Benefit

A typical content site with Astro ships 0 KB of JS for static pages and only targeted bundles for interactive islands. Compared to SPA frameworks that ship 100-300 KB minimum, this produces Lighthouse scores of 95-100 out of the box.

---

## Astro 5 Key Features

Astro 5 (released December 2024) introduced several major changes:

### Content Layer API

The content layer replaces the old file-based content collections with a flexible, loader-based system that can pull content from any source (local files, CMS, API, database).

### Astro Actions

Type-safe server functions callable from the client, similar to server actions in Next.js but with Astro's own validation and error handling built in.

### Server Islands

Defer expensive or personalized server-rendered components inside a cached static page. Combines the performance of static pages with the dynamism of server rendering.

### Request Rewriting

Middleware can rewrite requests to different routes without a redirect, enabling A/B testing and URL rewriting patterns.

### astro:env Module

First-class environment variable management with type safety and validation, replacing manual `import.meta.env` usage.

---

## Rendering Modes

Astro supports three rendering modes, configurable globally or per-route.

### Static Site Generation (SSG) - Default

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';

export default defineConfig({
  output: 'static', // Default - all pages pre-rendered at build time
});
```

All pages are pre-rendered to HTML at build time. Best for blogs, documentation, marketing sites, and any content that does not change per-request.

### Server-Side Rendering (SSR)

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

export default defineConfig({
  output: 'server', // All pages rendered on each request
  adapter: node({
    mode: 'standalone',
  }),
});
```

Every page is rendered on demand per request. Required for personalized content, authentication-gated pages, and real-time data.

### Hybrid Rendering (Recommended for Most Apps)

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

export default defineConfig({
  output: 'hybrid', // Static by default, opt-in to SSR per route
  adapter: node({
    mode: 'standalone',
  }),
});
```

```astro
---
// src/pages/dashboard.astro
// Opt this specific page into SSR
export const prerender = false;

import { getSession } from '../lib/auth';
const session = await getSession(Astro.request);
if (!session) return Astro.redirect('/login');
---

<h1>Welcome, {session.user.name}</h1>
```

```astro
---
// src/pages/about.astro
// This page remains static (prerender = true is default in hybrid mode)
---

<h1>About Us</h1>
<p>This page is pre-rendered at build time.</p>
```

**Staff Engineer Decision Matrix:**
- **Static (`output: 'static'`)**: Content sites, docs, blogs, landing pages
- **Server (`output: 'server'`)**: Fully dynamic apps, real-time dashboards, auth-heavy apps
- **Hybrid (`output: 'hybrid'`)**: Most production apps - static marketing + dynamic dashboard

---

## File-Based Routing

Astro uses file-based routing in `src/pages/`. Every `.astro`, `.md`, `.mdx`, or `.ts` file becomes a route.

### Route Patterns

```
src/pages/
├── index.astro              -> /
├── about.astro              -> /about
├── blog/
│   ├── index.astro          -> /blog
│   ├── [slug].astro         -> /blog/:slug (dynamic)
│   └── [...path].astro      -> /blog/* (catch-all / rest)
├── api/
│   ├── users.ts             -> /api/users (API endpoint)
│   └── users/[id].ts        -> /api/users/:id
└── [...404].astro           -> Custom 404 page
```

### Dynamic Routes with SSG

```astro
---
// src/pages/blog/[slug].astro
import { getCollection } from 'astro:content';

export async function getStaticPaths() {
  const posts = await getCollection('blog');
  return posts.map((post) => ({
    params: { slug: post.id },
    props: { post },
  }));
}

const { post } = Astro.props;
const { Content } = await post.render();
---

<article>
  <h1>{post.data.title}</h1>
  <Content />
</article>
```

### API Endpoints

```typescript
// src/pages/api/users.ts
import type { APIRoute } from 'astro';

export const GET: APIRoute = async ({ request, url }) => {
  const page = Number(url.searchParams.get('page') ?? '1');
  const users = await fetchUsers({ page });

  return new Response(JSON.stringify(users), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};

export const POST: APIRoute = async ({ request }) => {
  const body = await request.json();

  // Validate and create user
  const user = await createUser(body);

  return new Response(JSON.stringify(user), {
    status: 201,
    headers: { 'Content-Type': 'application/json' },
  });
};
```

---

## Server Islands

Server Islands allow deferring expensive or personalized server-rendered content inside an otherwise static page. The static shell loads instantly, and server islands stream in asynchronously.

### Configuration

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

export default defineConfig({
  output: 'hybrid',
  adapter: node({ mode: 'standalone' }),
});
```

### Usage

```astro
---
// src/components/UserGreeting.astro
// This component is marked server:defer to run on the server at request time
const user = await getCurrentUser(Astro.request);
---

<div class="greeting">
  <p>Welcome back, {user.name}!</p>
  <p>You have {user.unreadCount} unread messages.</p>
</div>
```

```astro
---
// src/pages/index.astro (static page with a server island)
import UserGreeting from '../components/UserGreeting.astro';
import ProductGrid from '../components/ProductGrid.astro';
---

<html>
  <body>
    <!-- Static cached content -->
    <h1>Welcome to Our Store</h1>

    <!-- Server Island: rendered per-request, streams in after page load -->
    <UserGreeting server:defer>
      <div slot="fallback">Loading your profile...</div>
    </UserGreeting>

    <!-- Static cached content -->
    <ProductGrid />
  </body>
</html>
```

**Key Points:**
- The static shell is cached at the CDN edge
- Server islands make their own server request and stream the result
- The `fallback` slot shows while the island is loading
- Ideal for personalization (user greeting, cart count) on otherwise cacheable pages

---

## View Transitions API

Astro has built-in support for the View Transitions API, enabling smooth page-to-page animations without a client-side router.

### Setup

```astro
---
// src/layouts/BaseLayout.astro
import { ViewTransitions } from 'astro:transitions';
---

<html lang="en">
  <head>
    <ViewTransitions />
  </head>
  <body>
    <slot />
  </body>
</html>
```

### Transition Directives

```astro
---
// src/pages/blog/[slug].astro
import { fade, slide } from 'astro:transitions';
---

<!-- Morph animation (default) - element morphs between pages -->
<h1 transition:name="post-title">{post.data.title}</h1>

<!-- Built-in animations -->
<img
  src={post.data.cover}
  transition:name={`hero-${post.id}`}
  transition:animate={fade({ duration: '0.3s' })}
/>

<article transition:animate={slide({ duration: '0.4s' })}>
  <Content />
</article>
```

### Persisting Elements Across Pages

```astro
<!-- Audio player persists across page navigations -->
<audio id="player" transition:persist>
  <source src="/podcast.mp3" type="audio/mpeg" />
</audio>

<!-- Video continues playing across navigations -->
<iframe
  src="https://www.youtube.com/embed/..."
  transition:persist
/>
```

### Lifecycle Events

```astro
<script>
  document.addEventListener('astro:before-preparation', (event) => {
    // Before the new page is fetched
    console.log('Navigating to:', event.to);
  });

  document.addEventListener('astro:after-swap', () => {
    // After DOM is swapped, before transition completes
    // Re-initialize third-party scripts here
    initAnalytics();
  });

  document.addEventListener('astro:page-load', () => {
    // After full page load (works for both initial and subsequent loads)
    setupEventListeners();
  });
</script>
```

---

## Middleware

Astro middleware runs before every page and API request. Useful for authentication, logging, redirects, and request modification.

### Basic Middleware

```typescript
// src/middleware.ts
import { defineMiddleware, sequence } from 'astro:middleware';

const auth = defineMiddleware(async (context, next) => {
  const token = context.cookies.get('session')?.value;

  if (token) {
    const user = await verifySession(token);
    context.locals.user = user;
  }

  return next();
});

const logging = defineMiddleware(async (context, next) => {
  const start = Date.now();
  const response = await next();
  const duration = Date.now() - start;

  console.log(`${context.request.method} ${context.url.pathname} - ${duration}ms`);
  return response;
});

// Chain middleware with sequence()
export const onRequest = sequence(logging, auth);
```

### Request Rewriting (Astro 5)

```typescript
// src/middleware.ts
import { defineMiddleware } from 'astro:middleware';

export const onRequest = defineMiddleware(async (context, next) => {
  // A/B testing: rewrite to variant page without changing URL
  if (context.url.pathname === '/pricing') {
    const variant = context.cookies.get('ab-variant')?.value;
    if (variant === 'b') {
      return context.rewrite('/pricing-b');
    }
  }

  // Locale-based routing
  const locale = context.preferredLocale ?? 'en';
  if (context.url.pathname === '/') {
    return context.rewrite(`/${locale}/home`);
  }

  return next();
});
```

### Protecting Routes

```typescript
// src/middleware.ts
import { defineMiddleware } from 'astro:middleware';

const protectedRoutes = ['/dashboard', '/settings', '/admin'];

export const onRequest = defineMiddleware(async (context, next) => {
  const isProtected = protectedRoutes.some((route) =>
    context.url.pathname.startsWith(route)
  );

  if (isProtected && !context.locals.user) {
    return context.redirect('/login', 302);
  }

  // Admin-only routes
  if (context.url.pathname.startsWith('/admin') && context.locals.user?.role !== 'admin') {
    return new Response('Forbidden', { status: 403 });
  }

  return next();
});
```

---

## Project Structure

### Recommended Layout for Production Astro 5 App

```
project/
├── astro.config.mjs           # Astro configuration
├── tsconfig.json               # TypeScript config (extends Astro)
├── package.json
├── public/                     # Static assets (copied as-is)
│   ├── favicon.svg
│   ├── robots.txt
│   └── og-image.png
├── src/
│   ├── actions/                # Astro Actions (type-safe server functions)
│   │   └── index.ts
│   ├── assets/                 # Optimized assets (images, fonts)
│   │   └── images/
│   ├── components/             # UI components
│   │   ├── Header.astro        # Astro components (static)
│   │   ├── Footer.astro
│   │   ├── SearchBar.tsx       # React island
│   │   ├── ThemeToggle.svelte  # Svelte island
│   │   └── ui/                 # Shared primitives
│   ├── content/                # Content collections
│   │   └── blog/
│   │       ├── first-post.md
│   │       └── second-post.mdx
│   ├── content.config.ts       # Content collection schemas
│   ├── layouts/                # Page layouts
│   │   ├── BaseLayout.astro
│   │   ├── BlogLayout.astro
│   │   └── DocsLayout.astro
│   ├── lib/                    # Shared utilities
│   │   ├── api.ts
│   │   ├── auth.ts
│   │   └── utils.ts
│   ├── middleware.ts            # Request middleware
│   ├── pages/                  # File-based routes
│   │   ├── index.astro
│   │   ├── about.astro
│   │   ├── blog/
│   │   │   ├── index.astro
│   │   │   └── [slug].astro
│   │   └── api/
│   │       └── search.ts
│   ├── styles/                 # Global styles
│   │   └── global.css
│   └── env.d.ts                # TypeScript environment types
└── tests/                      # Test files
    ├── e2e/
    └── unit/
```

### Key Conventions

- `src/pages/` is the only directory with routing significance
- `src/components/` holds both Astro components (static) and framework components (interactive)
- `src/content/` holds content collection files
- `src/layouts/` holds reusable page layouts
- `public/` is copied verbatim to the output (no processing)
- `src/assets/` holds images and assets that Astro should optimize

---

## Environment Variables & Configuration

### astro:env Module (Astro 5)

```typescript
// astro.config.mjs
import { defineConfig, envField } from 'astro/config';

export default defineConfig({
  env: {
    schema: {
      API_URL: envField.string({
        context: 'server',
        access: 'secret',
      }),
      PUBLIC_SITE_URL: envField.string({
        context: 'client',
        access: 'public',
        default: 'http://localhost:4321',
      }),
      DATABASE_URL: envField.string({
        context: 'server',
        access: 'secret',
      }),
      ENABLE_ANALYTICS: envField.boolean({
        context: 'client',
        access: 'public',
        default: false,
      }),
    },
  },
});
```

```astro
---
// Usage in Astro components
import { API_URL, DATABASE_URL } from 'astro:env/server';
import { PUBLIC_SITE_URL, ENABLE_ANALYTICS } from 'astro:env/client';

const data = await fetch(`${API_URL}/posts`);
---

<p>Site: {PUBLIC_SITE_URL}</p>
```

### Environment Variable Rules

- `PUBLIC_` prefixed variables are exposed to the client
- Server-only variables are never sent to the browser
- Use `astro:env` for type-safe, validated access (Astro 5+)
- Legacy `import.meta.env` still works but lacks validation

---

## Astro Config Patterns

### Full Production Config

```typescript
// astro.config.mjs
import { defineConfig, envField } from 'astro/config';
import node from '@astrojs/node';
import react from '@astrojs/react';
import svelte from '@astrojs/svelte';
import tailwind from '@astrojs/tailwind';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import icon from 'astro-icon';

export default defineConfig({
  site: 'https://example.com',
  output: 'hybrid',
  adapter: node({ mode: 'standalone' }),

  integrations: [
    react(),
    svelte(),
    tailwind(),
    mdx(),
    sitemap(),
    icon(),
  ],

  image: {
    domains: ['images.unsplash.com', 'cdn.example.com'],
    remotePatterns: [
      { protocol: 'https', hostname: '**.cloudinary.com' },
    ],
  },

  vite: {
    build: {
      rollupOptions: {
        output: {
          manualChunks: {
            react: ['react', 'react-dom'],
          },
        },
      },
    },
  },

  prefetch: {
    prefetchAll: true,
    defaultStrategy: 'viewport',
  },
});
```

---

## Best Practices

1. **Default to static rendering** - Use SSG unless a page genuinely needs per-request data
2. **Use hybrid mode for mixed sites** - Static marketing pages + dynamic dashboard in one project
3. **Server Islands for personalization** - Keep the page static, defer only the user-specific parts
4. **View Transitions for navigation** - Smooth page transitions without an SPA router or JS bundle
5. **Middleware for cross-cutting concerns** - Auth, logging, redirects, locale detection
6. **astro:env for configuration** - Type-safe environment variables with validation at build time
7. **Framework components only where needed** - Use Astro components for everything static
8. **Keep pages thin** - Pages should compose layouts and components, not contain logic
9. **Use content collections for structured data** - Type-safe, validated, with relationships
10. **Prefetch links** - Enable `prefetchAll` for instant navigation feel

---

## Anti-Patterns

- Using `client:load` on every component (defeats the purpose of islands)
- Choosing SSR mode when the content is static (unnecessary server cost)
- Putting business logic in `.astro` page files instead of `src/lib/`
- Skipping the content layer and fetching markdown manually
- Not using layouts for shared page structure (duplicating HTML)
- Ignoring the `public/` vs `src/assets/` distinction (missing image optimization)
- Shipping a full SPA framework when Astro components suffice
- Not leveraging `transition:persist` for media elements during navigation
- Using `import.meta.env` without validation when `astro:env` is available

---

## Sources & References

- [Astro 5.0 Release Blog Post](https://astro.build/blog/astro-5/)
- [Astro Documentation: Project Structure](https://docs.astro.build/en/basics/project-structure/)
- [Astro Documentation: Server Islands](https://docs.astro.build/en/guides/server-islands/)
- [Astro Documentation: View Transitions](https://docs.astro.build/en/guides/view-transitions/)
- [Astro Documentation: Routing](https://docs.astro.build/en/guides/routing/)
- [Astro Documentation: Middleware](https://docs.astro.build/en/guides/middleware/)
- [Astro Documentation: Environment Variables (astro:env)](https://docs.astro.build/en/guides/environment-variables/)
- [Islands Architecture - Jason Miller](https://jasonformat.com/islands-architecture/)
