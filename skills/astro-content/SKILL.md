---
name: astro-content
description: Astro 5 content collections, Content Layer API, MDX/Markdoc, data fetching, content schemas, type-safe content, image optimization, content relationships
---

# Astro Content Collections & Data

Production-ready patterns for managing content in Astro 5.x. Covers the Content Layer API (loader-based collections), Zod schemas, MDX and Markdoc authoring, image optimization with `astro:assets`, data fetching strategies, content relationships, and integration with headless CMS platforms.

## Table of Contents

1. [Content Layer API (Astro 5)](#content-layer-api-astro-5)
2. [Content Schemas with Zod](#content-schemas-with-zod)
3. [Querying Content Collections](#querying-content-collections)
4. [MDX Authoring](#mdx-authoring)
5. [Markdoc Integration](#markdoc-integration)
6. [Image Optimization](#image-optimization)
7. [Content Relationships](#content-relationships)
8. [Remote Content & CMS Integration](#remote-content--cms-integration)
9. [Data Collections](#data-collections)
10. [Data Fetching Patterns](#data-fetching-patterns)
11. [Pagination](#pagination)
12. [Best Practices](#best-practices)
13. [Anti-Patterns](#anti-patterns)

---

## Content Layer API (Astro 5)

Astro 5 replaced the legacy file-based content collections with the Content Layer API. Collections are now defined in `src/content.config.ts` (not the old `src/content/config.ts`) and use loaders to pull content from any source: local files, APIs, databases, or headless CMS platforms.

### Configuration File

```typescript
// src/content.config.ts
import { defineCollection, z } from 'astro:content';
import { glob, file } from 'astro/loaders';

const blog = defineCollection({
  loader: glob({ pattern: '**/*.{md,mdx}', base: './src/content/blog' }),
  schema: ({ image }) =>
    z.object({
      title: z.string(),
      description: z.string().max(160),
      pubDate: z.coerce.date(),
      updatedDate: z.coerce.date().optional(),
      heroImage: image().optional(),
      tags: z.array(z.string()).default([]),
      draft: z.boolean().default(false),
      author: z.string(),
    }),
});

const authors = defineCollection({
  loader: file('./src/data/authors.json'),
  schema: ({ image }) =>
    z.object({
      name: z.string(),
      bio: z.string(),
      avatar: image().optional(),
      twitter: z.string().url().optional(),
      github: z.string().url().optional(),
    }),
});

export const collections = { blog, authors };
```

### Key Differences from Legacy Collections

- Config file is `src/content.config.ts` (not `src/content/config.ts`)
- Collections use explicit loaders (`glob`, `file`, or custom loaders)
- Content no longer requires a fixed `src/content/` directory structure
- `slug` is replaced by `id` (the `slug` field no longer exists by default)
- The `render()` method returns `{ Content, headings }` for rendering markdown/MDX
- Schemas receive an object with `image()` helper for image validation

---

## Content Schemas with Zod

Schemas provide type safety at build time. Astro validates every content entry against its schema during `astro build` and `astro dev`, catching errors early.

### Schema Patterns

```typescript
// src/content.config.ts
import { defineCollection, z, reference } from 'astro:content';
import { glob } from 'astro/loaders';

const blog = defineCollection({
  loader: glob({ pattern: '**/*.{md,mdx}', base: './src/content/blog' }),
  schema: ({ image }) =>
    z.object({
      // Required fields
      title: z.string().min(1).max(100),
      description: z.string().max(160),
      pubDate: z.coerce.date(),

      // Optional fields with defaults
      draft: z.boolean().default(false),
      featured: z.boolean().default(false),
      tags: z.array(z.string()).default([]),

      // Enum validation
      category: z.enum(['tutorial', 'guide', 'opinion', 'release']),

      // Image validation with astro:assets
      cover: image().refine((img) => img.width >= 800, {
        message: 'Cover image must be at least 800px wide',
      }),

      // References to other collections
      author: reference('authors'),
      relatedPosts: z.array(reference('blog')).default([]),

      // Computed / transform
      readingTime: z.number().optional(),
    }),
});

const docs = defineCollection({
  loader: glob({ pattern: '**/*.mdx', base: './src/content/docs' }),
  schema: z.object({
    title: z.string(),
    section: z.string(),
    order: z.number().int().nonneg(),
    badge: z.enum(['new', 'updated', 'deprecated']).optional(),
  }),
});

const changelog = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/changelog' }),
  schema: z.object({
    version: z.string().regex(/^\d+\.\d+\.\d+$/),
    date: z.coerce.date(),
    breaking: z.boolean().default(false),
  }),
});

export const collections = { blog, docs, changelog };
```

### Frontmatter Example

```yaml
---
title: "Building Islands with Astro 5"
description: "A complete guide to the islands architecture in Astro 5"
pubDate: 2025-06-15
category: tutorial
cover: ./images/islands-cover.png
author: jane-doe
tags: ["astro", "architecture", "performance"]
draft: false
relatedPosts:
  - getting-started-with-astro
  - server-islands-deep-dive
---
```

---

## Querying Content Collections

### Basic Queries

```astro
---
// src/pages/blog/index.astro
import { getCollection, getEntry } from 'astro:content';

// Get all entries in a collection
const allPosts = await getCollection('blog');

// Filter entries (e.g., exclude drafts in production)
const publishedPosts = await getCollection('blog', ({ data }) => {
  return import.meta.env.PROD ? !data.draft : true;
});

// Sort by date (newest first)
const sortedPosts = publishedPosts.sort(
  (a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf()
);

// Get a single entry by ID
const featuredPost = await getEntry('blog', 'welcome-to-astro-5');
---

<ul>
  {sortedPosts.map((post) => (
    <li>
      <a href={`/blog/${post.id}`}>
        <h2>{post.data.title}</h2>
        <time datetime={post.data.pubDate.toISOString()}>
          {post.data.pubDate.toLocaleDateString('en-US')}
        </time>
      </a>
    </li>
  ))}
</ul>
```

### Rendering Content

```astro
---
// src/pages/blog/[slug].astro
import { getCollection } from 'astro:content';

export async function getStaticPaths() {
  const posts = await getCollection('blog', ({ data }) => !data.draft);
  return posts.map((post) => ({
    params: { slug: post.id },
    props: { post },
  }));
}

const { post } = Astro.props;
const { Content, headings } = await post.render();
---

<article>
  <h1>{post.data.title}</h1>
  <p>{post.data.description}</p>

  <!-- Table of contents from headings -->
  <nav>
    <ul>
      {headings.map((h) => (
        <li style={`margin-left: ${(h.depth - 2) * 1}rem`}>
          <a href={`#${h.slug}`}>{h.text}</a>
        </li>
      ))}
    </ul>
  </nav>

  <!-- Rendered markdown/MDX content -->
  <Content />
</article>
```

### Collection Helpers

```typescript
// src/lib/content-utils.ts
import { getCollection } from 'astro:content';

export async function getPublishedPosts() {
  const posts = await getCollection('blog', ({ data }) => !data.draft);
  return posts.sort(
    (a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf()
  );
}

export async function getPostsByTag(tag: string) {
  const posts = await getPublishedPosts();
  return posts.filter((post) => post.data.tags.includes(tag));
}

export async function getAllTags() {
  const posts = await getPublishedPosts();
  const tags = new Set(posts.flatMap((post) => post.data.tags));
  return [...tags].sort();
}

export async function getFeaturedPosts(limit = 3) {
  const posts = await getPublishedPosts();
  return posts.filter((post) => post.data.featured).slice(0, limit);
}
```

---

## MDX Authoring

MDX lets you use JSX components inside Markdown. Astro supports MDX via the `@astrojs/mdx` integration.

### Setup

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';

export default defineConfig({
  integrations: [mdx()],
});
```

### MDX Content File

```mdx
---
title: "Interactive Tutorial"
description: "Learn Astro with interactive examples"
pubDate: 2025-07-01
author: jane-doe
---

import CodePlayground from '../../components/CodePlayground.tsx';
import Callout from '../../components/Callout.astro';

# Getting Started with Astro

Astro makes building fast websites easy.

<Callout type="tip">
  You can mix Markdown and components seamlessly in MDX files.
</Callout>

## Try It Yourself

<CodePlayground client:visible code={`
  console.log('Hello from Astro!');
`} />

Regular **Markdown** continues to work alongside components.
```

### Custom Components for MDX

```astro
---
// src/components/Callout.astro
interface Props {
  type: 'tip' | 'warning' | 'danger' | 'info';
}

const { type } = Astro.props;

const styles: Record<string, string> = {
  tip: 'border-green-500 bg-green-50',
  warning: 'border-yellow-500 bg-yellow-50',
  danger: 'border-red-500 bg-red-50',
  info: 'border-blue-500 bg-blue-50',
};
---

<div class={`callout border-l-4 p-4 my-4 ${styles[type]}`}>
  <slot />
</div>
```

### MDX Configuration Options

```typescript
// astro.config.mjs
import mdx from '@astrojs/mdx';
import remarkToc from 'remark-toc';
import rehypeSlug from 'rehype-slug';
import rehypeAutolinkHeadings from 'rehype-autolink-headings';

export default defineConfig({
  integrations: [mdx()],
  markdown: {
    remarkPlugins: [remarkToc],
    rehypePlugins: [
      rehypeSlug,
      [rehypeAutolinkHeadings, { behavior: 'wrap' }],
    ],
    shikiConfig: {
      theme: 'github-dark',
      langs: ['typescript', 'astro', 'jsx', 'bash'],
    },
  },
});
```

---

## Markdoc Integration

Markdoc (developed by Stripe) is an alternative to MDX that uses a tag-based syntax instead of JSX. It is more constrained and therefore safer for non-developer content authors.

### Setup

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import markdoc from '@astrojs/markdoc';

export default defineConfig({
  integrations: [markdoc()],
});
```

### Markdoc Content

```markdoc
---
title: "Markdoc Example"
---

# Welcome to Markdoc

Standard Markdown works here.

{% callout type="warning" %}
This uses Markdoc tag syntax instead of JSX.
{% /callout %}

{% tabs %}
{% tab label="JavaScript" %}
```js
console.log('Hello');
```
{% /tab %}
{% tab label="Python" %}
```python
print("Hello")
```
{% /tab %}
{% /tabs %}
```

### Markdoc Configuration

```typescript
// markdoc.config.mjs
import { defineMarkdocConfig, component, nodes } from '@astrojs/markdoc/config';

export default defineMarkdocConfig({
  tags: {
    callout: {
      render: component('./src/components/Callout.astro'),
      attributes: {
        type: { type: String, default: 'info' },
      },
    },
    tabs: {
      render: component('./src/components/Tabs.astro'),
    },
    tab: {
      render: component('./src/components/Tab.astro'),
      attributes: {
        label: { type: String, required: true },
      },
    },
  },
  nodes: {
    heading: {
      ...nodes.heading,
      render: component('./src/components/Heading.astro'),
    },
  },
});
```

---

## Image Optimization

Astro provides built-in image optimization through the `astro:assets` module. Images in `src/assets/` are processed, while images in `public/` are served as-is.

### The Image Component

```astro
---
// src/components/BlogCard.astro
import { Image } from 'astro:assets';
import heroImage from '../assets/images/hero.png';

interface Props {
  title: string;
  cover: ImageMetadata;
}

const { title, cover } = Astro.props;
---

<!-- Local image with automatic optimization -->
<Image
  src={heroImage}
  alt="Hero banner"
  width={1200}
  height={630}
  format="webp"
  quality={80}
/>

<!-- Dynamic image from props (e.g., content collection image) -->
<Image
  src={cover}
  alt={title}
  widths={[400, 800, 1200]}
  sizes="(max-width: 600px) 400px, (max-width: 900px) 800px, 1200px"
/>
```

### Images in Content Collections

```typescript
// src/content.config.ts
import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const blog = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/blog' }),
  schema: ({ image }) =>
    z.object({
      title: z.string(),
      // Validates that the image exists and resolves the path
      cover: image(),
      // Optional image with size constraints
      thumbnail: image()
        .refine((img) => img.width <= 400, {
          message: 'Thumbnail must be 400px or smaller',
        })
        .optional(),
    }),
});
```

```astro
---
// src/pages/blog/[slug].astro
import { Image } from 'astro:assets';
const { post } = Astro.props;
---

<Image
  src={post.data.cover}
  alt={post.data.title}
  width={1200}
  height={630}
/>
```

### The Picture Component

```astro
---
import { Picture } from 'astro:assets';
import heroImage from '../assets/images/hero.png';
---

<!-- Generates multiple formats (avif, webp, png) and sizes -->
<Picture
  src={heroImage}
  formats={['avif', 'webp']}
  widths={[400, 800, 1200]}
  sizes="(max-width: 600px) 400px, (max-width: 900px) 800px, 1200px"
  alt="Hero image"
/>
```

### Remote Image Configuration

```typescript
// astro.config.mjs
export default defineConfig({
  image: {
    // Allow specific domains
    domains: ['images.unsplash.com', 'cdn.example.com'],
    // Allow patterns with wildcards
    remotePatterns: [
      { protocol: 'https', hostname: '**.cloudinary.com' },
      { protocol: 'https', hostname: 'images.ctfassets.net' },
    ],
  },
});
```

```astro
---
import { Image } from 'astro:assets';
---

<!-- Remote images require explicit width and height -->
<Image
  src="https://images.unsplash.com/photo-abc123"
  alt="Remote photo"
  width={800}
  height={600}
  format="webp"
/>
```

---

## Content Relationships

Astro 5 supports typed references between collections using the `reference()` helper.

### Defining References

```typescript
// src/content.config.ts
import { defineCollection, z, reference } from 'astro:content';
import { glob, file } from 'astro/loaders';

const authors = defineCollection({
  loader: file('./src/data/authors.json'),
  schema: z.object({
    name: z.string(),
    bio: z.string(),
    email: z.string().email(),
  }),
});

const categories = defineCollection({
  loader: file('./src/data/categories.json'),
  schema: z.object({
    name: z.string(),
    description: z.string(),
    slug: z.string(),
  }),
});

const blog = defineCollection({
  loader: glob({ pattern: '**/*.mdx', base: './src/content/blog' }),
  schema: z.object({
    title: z.string(),
    // Single reference
    author: reference('authors'),
    // Single reference
    category: reference('categories'),
    // Array of references
    relatedPosts: z.array(reference('blog')).default([]),
  }),
});

export const collections = { authors, categories, blog };
```

### Resolving References

```astro
---
// src/pages/blog/[slug].astro
import { getEntry } from 'astro:content';

const { post } = Astro.props;

// Resolve referenced author
const author = await getEntry(post.data.author);

// Resolve referenced category
const category = await getEntry(post.data.category);

// Resolve multiple references
const relatedPosts = await Promise.all(
  post.data.relatedPosts.map((ref) => getEntry(ref))
);
---

<article>
  <h1>{post.data.title}</h1>
  <p>By <strong>{author.data.name}</strong></p>
  <span>Category: {category.data.name}</span>

  {relatedPosts.length > 0 && (
    <aside>
      <h2>Related Posts</h2>
      <ul>
        {relatedPosts.map((related) => (
          <li><a href={`/blog/${related.id}`}>{related.data.title}</a></li>
        ))}
      </ul>
    </aside>
  )}
</article>
```

---

## Remote Content & CMS Integration

The Content Layer API supports custom loaders for fetching content from any external source.

### Custom Loader for a Headless CMS

```typescript
// src/loaders/strapi-loader.ts
import type { Loader } from 'astro/loaders';

export function strapiLoader(contentType: string): Loader {
  return {
    name: 'strapi-loader',
    load: async ({ store, logger }) => {
      const apiUrl = import.meta.env.STRAPI_URL;

      logger.info(`Fetching ${contentType} from Strapi...`);

      const response = await fetch(
        `${apiUrl}/api/${contentType}?populate=*`
      );
      const { data } = await response.json();

      store.clear();

      for (const item of data) {
        store.set({
          id: item.id.toString(),
          data: {
            title: item.attributes.title,
            content: item.attributes.content,
            publishedAt: item.attributes.publishedAt,
            slug: item.attributes.slug,
          },
        });
      }
    },
  };
}
```

```typescript
// src/content.config.ts
import { defineCollection, z } from 'astro:content';
import { strapiLoader } from './loaders/strapi-loader';

const articles = defineCollection({
  loader: strapiLoader('articles'),
  schema: z.object({
    title: z.string(),
    content: z.string(),
    publishedAt: z.coerce.date(),
    slug: z.string(),
  }),
});

export const collections = { articles };
```

### Built-in File Loader for JSON/YAML Data

```typescript
// src/content.config.ts
import { defineCollection, z } from 'astro:content';
import { file } from 'astro/loaders';

// Single JSON file with array of entries
const team = defineCollection({
  loader: file('./src/data/team.json'),
  schema: z.object({
    name: z.string(),
    role: z.string(),
    department: z.string(),
  }),
});

// YAML file
const navigation = defineCollection({
  loader: file('./src/data/navigation.yaml'),
  schema: z.object({
    label: z.string(),
    href: z.string(),
    children: z
      .array(z.object({ label: z.string(), href: z.string() }))
      .default([]),
  }),
});

export const collections = { team, navigation };
```

---

## Data Collections

Data collections are collections without rendered body content. Use them for structured data like settings, navigation, team members, or any JSON/YAML source.

```typescript
// src/content.config.ts
import { defineCollection, z } from 'astro:content';
import { file } from 'astro/loaders';

const settings = defineCollection({
  loader: file('./src/data/settings.json'),
  schema: z.object({
    siteName: z.string(),
    siteDescription: z.string(),
    socialLinks: z.array(
      z.object({
        platform: z.string(),
        url: z.string().url(),
        icon: z.string(),
      })
    ),
  }),
});

export const collections = { settings };
```

```astro
---
import { getEntry } from 'astro:content';

const settings = await getEntry('settings', 'default');
---

<footer>
  <p>{settings.data.siteName}</p>
  <nav>
    {settings.data.socialLinks.map((link) => (
      <a href={link.url}>{link.platform}</a>
    ))}
  </nav>
</footer>
```

---

## Data Fetching Patterns

### Fetch at Build Time (SSG)

```astro
---
// src/pages/products.astro
// Runs at build time -- data is baked into static HTML
const response = await fetch('https://api.example.com/products');
const products = await response.json();
---

<ul>
  {products.map((product) => (
    <li>{product.name} - ${product.price}</li>
  ))}
</ul>
```

### Fetch at Request Time (SSR)

```astro
---
// src/pages/dashboard.astro
export const prerender = false; // Opt into SSR (in hybrid mode)

const session = Astro.cookies.get('session')?.value;
if (!session) return Astro.redirect('/login');

const response = await fetch('https://api.example.com/dashboard', {
  headers: { Authorization: `Bearer ${session}` },
});
const data = await response.json();
---

<h1>Your Dashboard</h1>
<pre>{JSON.stringify(data, null, 2)}</pre>
```

### Combining Static and Dynamic Data

```astro
---
// src/pages/product/[id].astro
import { getCollection } from 'astro:content';

// Static product catalog from content collection
export async function getStaticPaths() {
  const products = await getCollection('products');
  return products.map((product) => ({
    params: { id: product.id },
    props: { product },
  }));
}

const { product } = Astro.props;
// Dynamic stock data from API at build time
const stock = await fetch(`https://api.example.com/stock/${product.id}`)
  .then((r) => r.json());
---

<h1>{product.data.name}</h1>
<p>In stock: {stock.quantity}</p>
```

---

## Pagination

```astro
---
// src/pages/blog/[...page].astro
import type { GetStaticPaths, Page } from 'astro';
import { getCollection } from 'astro:content';

export const getStaticPaths: GetStaticPaths = async ({ paginate }) => {
  const posts = await getCollection('blog', ({ data }) => !data.draft);
  const sorted = posts.sort(
    (a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf()
  );

  return paginate(sorted, { pageSize: 10 });
};

interface Props {
  page: Page;
}

const { page } = Astro.props;
---

<h1>Blog (Page {page.currentPage})</h1>

<ul>
  {page.data.map((post) => (
    <li>
      <a href={`/blog/${post.id}`}>{post.data.title}</a>
    </li>
  ))}
</ul>

<nav>
  {page.url.prev && <a href={page.url.prev}>Previous</a>}
  <span>Page {page.currentPage} of {page.lastPage}</span>
  {page.url.next && <a href={page.url.next}>Next</a>}
</nav>
```

---

## Best Practices

1. **Use `content.config.ts`** at the `src/` root for Astro 5 content configuration
2. **Validate everything with Zod schemas** to catch content errors at build time, not runtime
3. **Use `reference()` for content relationships** instead of manual ID lookups
4. **Filter drafts in production** with `getCollection('blog', ({ data }) => !data.draft)`
5. **Use `image()` in schemas** to get build-time validation and automatic optimization
6. **Create utility functions** in `src/lib/` for common collection queries (by tag, by author)
7. **Use the glob loader** for local file content and the file loader for structured JSON/YAML data
8. **Write custom loaders** for CMS integration instead of fetching in page frontmatter
9. **Use MDX for developer content** (component-rich) and Markdoc for non-developer authors
10. **Set explicit `widths` and `sizes`** on images for responsive loading
11. **Use `Picture` component** when you need multiple image formats (avif + webp fallback)
12. **Paginate large collections** to keep build output manageable

---

## Anti-Patterns

- Using the legacy `src/content/config.ts` path instead of `src/content.config.ts` in Astro 5
- Accessing `slug` on collection entries (use `id` in Astro 5)
- Fetching CMS content in page frontmatter instead of writing a custom loader
- Placing optimizable images in `public/` instead of `src/assets/`
- Skipping the `image()` schema helper and passing raw strings for image paths
- Not filtering draft content in production builds
- Hardcoding related post IDs instead of using `reference()`
- Using `getCollection()` without type-narrowing the result with a filter callback
- Not specifying `width` and `height` for remote images (causes layout shift)
- Putting data queries directly in layout files instead of page files

---

## Sources & References

- [Astro Documentation: Content Collections](https://docs.astro.build/en/guides/content-collections/)
- [Astro Documentation: Content Layer API (Loaders)](https://docs.astro.build/en/guides/content-collections/#the-content-layer)
- [Astro Documentation: Images & Assets](https://docs.astro.build/en/guides/images/)
- [Astro Documentation: Markdown & MDX](https://docs.astro.build/en/guides/markdown-content/)
- [Astro Documentation: Markdoc Integration](https://docs.astro.build/en/guides/integrations-guide/markdoc/)
- [Astro 5.0 Release: Content Layer](https://astro.build/blog/astro-5/)
- [Astro Documentation: Routing and Pagination](https://docs.astro.build/en/guides/routing/#pagination)
