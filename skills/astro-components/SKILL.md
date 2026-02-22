---
name: astro-components
description: Astro components, framework integration (React/Svelte/Vue/Solid), partial hydration (client:* directives), slots, component composition, Astro Actions, Server Islands
---

# Astro Components & Interactivity

Production-ready patterns for building components in Astro 5.x. Covers native Astro components, framework integration (React, Svelte, Vue, Solid), the partial hydration model with `client:*` directives, slot composition, Astro Actions for type-safe server functions, Server Islands, and advanced component patterns.

## Table of Contents

1. [Astro Components](#astro-components)
2. [Component Props & TypeScript](#component-props--typescript)
3. [Slots & Composition](#slots--composition)
4. [Framework Integration](#framework-integration)
5. [Partial Hydration (client:* Directives)](#partial-hydration-client-directives)
6. [Choosing a Hydration Strategy](#choosing-a-hydration-strategy)
7. [Astro Actions](#astro-actions)
8. [Server Islands](#server-islands)
9. [Sharing State Between Islands](#sharing-state-between-islands)
10. [Component Patterns](#component-patterns)
11. [Styling Components](#styling-components)
12. [Best Practices](#best-practices)
13. [Anti-Patterns](#anti-patterns)

---

## Astro Components

Astro components (`.astro` files) are the foundation of every Astro site. They consist of a frontmatter script fence (`---`) and an HTML template. They run only at build time (SSG) or request time (SSR) and ship zero JavaScript to the client.

### Basic Component

```astro
---
// src/components/Card.astro
interface Props {
  title: string;
  description: string;
  href: string;
  variant?: 'default' | 'featured';
}

const { title, description, href, variant = 'default' } = Astro.props;
---

<a href={href} class={`card card--${variant}`}>
  <h3>{title}</h3>
  <p>{description}</p>
</a>

<style>
  .card {
    display: block;
    padding: 1.5rem;
    border: 1px solid #e2e8f0;
    border-radius: 0.5rem;
    text-decoration: none;
    color: inherit;
    transition: box-shadow 0.2s;
  }

  .card:hover {
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  }

  .card--featured {
    border-color: #6366f1;
    background: linear-gradient(135deg, #eef2ff, #e0e7ff);
  }

  h3 {
    margin: 0 0 0.5rem;
    font-size: 1.25rem;
  }

  p {
    margin: 0;
    color: #64748b;
  }
</style>
```

### Key Characteristics

- Styles are **scoped by default** (only apply to the component)
- The frontmatter runs on the server; the template produces static HTML
- No JavaScript is sent to the browser unless framework components with `client:*` are used
- Supports `await` directly in the frontmatter (top-level await)

---

## Component Props & TypeScript

```astro
---
// src/components/Avatar.astro
import type { ImageMetadata } from 'astro';
import { Image } from 'astro:assets';

interface Props {
  name: string;
  image: ImageMetadata;
  size?: 'sm' | 'md' | 'lg';
  showName?: boolean;
}

const { name, image, size = 'md', showName = false } = Astro.props;

const sizeMap = {
  sm: 32,
  md: 48,
  lg: 96,
};
const dimension = sizeMap[size];
---

<div class="avatar">
  <Image
    src={image}
    alt={name}
    width={dimension}
    height={dimension}
    class="avatar__image"
  />
  {showName && <span class="avatar__name">{name}</span>}
</div>
```

### Spread Attributes

```astro
---
// src/components/Button.astro
import type { HTMLAttributes } from 'astro/types';

interface Props extends HTMLAttributes<'button'> {
  variant?: 'primary' | 'secondary' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
}

const { variant = 'primary', size = 'md', class: className, ...attrs } = Astro.props;
---

<button class:list={[`btn btn--${variant} btn--${size}`, className]} {...attrs}>
  <slot />
</button>
```

---

## Slots & Composition

Slots are Astro's mechanism for component composition, similar to React's `children` or Vue's slots.

### Default Slot

```astro
---
// src/components/Alert.astro
interface Props {
  type: 'info' | 'warning' | 'error' | 'success';
}
const { type } = Astro.props;
---

<div class={`alert alert--${type}`} role="alert">
  <slot />
</div>
```

```astro
<!-- Usage -->
<Alert type="warning">
  <strong>Warning:</strong> This action cannot be undone.
</Alert>
```

### Named Slots

```astro
---
// src/components/PageSection.astro
interface Props {
  id: string;
}
const { id } = Astro.props;
---

<section id={id} class="page-section">
  <header class="page-section__header">
    <slot name="title" />
    <slot name="subtitle" />
  </header>

  <div class="page-section__content">
    <slot />
  </div>

  <footer class="page-section__footer">
    <slot name="actions" />
  </footer>
</section>
```

```astro
<!-- Usage with named slots -->
<PageSection id="features">
  <h2 slot="title">Features</h2>
  <p slot="subtitle">Everything you need to build fast websites</p>

  <FeatureGrid />

  <div slot="actions">
    <a href="/docs">Read the Docs</a>
  </div>
</PageSection>
```

### Fallback Content

```astro
---
// src/components/EmptyState.astro
---

<div class="empty-state">
  <slot name="icon">
    <!-- Default icon if none provided -->
    <svg><!-- default icon --></svg>
  </slot>

  <slot>
    <p>No items found.</p>
  </slot>

  <slot name="action">
    <!-- No default action -->
  </slot>
</div>
```

### Checking for Slot Content

```astro
---
// src/components/Card.astro
const hasFooter = Astro.slots.has('footer');
---

<div class="card">
  <div class="card__body">
    <slot />
  </div>

  {hasFooter && (
    <div class="card__footer">
      <slot name="footer" />
    </div>
  )}
</div>
```

---

## Framework Integration

Astro supports mixing UI frameworks in a single project. Each framework requires its own integration.

### Setup

```typescript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import svelte from '@astrojs/svelte';
import vue from '@astrojs/vue';
import solid from '@astrojs/solid-js';

export default defineConfig({
  integrations: [
    react(),
    svelte(),
    vue(),
    solid({ include: ['**/solid/**'] }), // scope to avoid conflicts
  ],
});
```

### React Component in Astro

```tsx
// src/components/react/Counter.tsx
import { useState } from 'react';

interface CounterProps {
  initialCount?: number;
  label: string;
}

export default function Counter({ initialCount = 0, label }: CounterProps) {
  const [count, setCount] = useState(initialCount);

  return (
    <div className="counter">
      <span>{label}: {count}</span>
      <button onClick={() => setCount((c) => c + 1)}>+</button>
      <button onClick={() => setCount((c) => c - 1)}>-</button>
    </div>
  );
}
```

### Svelte Component in Astro

```svelte
<!-- src/components/svelte/ThemeToggle.svelte -->
<script lang="ts">
  let dark = $state(false);

  function toggle() {
    dark = !dark;
    document.documentElement.classList.toggle('dark', dark);
  }
</script>

<button on:click={toggle} aria-label="Toggle theme">
  {dark ? 'Light Mode' : 'Dark Mode'}
</button>
```

### Using Framework Components in an Astro Page

```astro
---
// src/pages/index.astro
import Counter from '../components/react/Counter.tsx';
import ThemeToggle from '../components/svelte/ThemeToggle.svelte';
import StaticCard from '../components/Card.astro';
---

<html>
  <body>
    <!-- Static Astro component: zero JS -->
    <StaticCard title="Welcome" description="No JavaScript here" href="/about" />

    <!-- React island: hydrates on load -->
    <Counter client:load label="Visitors" initialCount={0} />

    <!-- Svelte island: hydrates when visible in viewport -->
    <ThemeToggle client:visible />
  </body>
</html>
```

### Multi-Framework in One Page

It is valid to use React, Svelte, Vue, and Solid components on the same page. Each island is independently bundled and hydrated. They do not share a virtual DOM or runtime.

---

## Partial Hydration (client:* Directives)

Partial hydration is the core of Astro's islands architecture. By default, framework components render to static HTML with no JavaScript. You must explicitly opt in with a `client:*` directive to make a component interactive.

### client:load

Hydrates the component immediately on page load. Use for components that must be interactive right away (above-the-fold interactive elements, critical forms).

```astro
<SearchBar client:load />
```

### client:idle

Hydrates after the page has finished loading and the browser is idle (`requestIdleCallback`). Use for components that are important but not critical on first paint.

```astro
<ChatWidget client:idle />
```

### client:visible

Hydrates when the component scrolls into the viewport (`IntersectionObserver`). Use for below-the-fold components.

```astro
<CommentSection client:visible />
<NewsletterForm client:visible />
```

### client:media

Hydrates only when a CSS media query matches. Use for components only relevant at certain screen sizes.

```astro
<!-- Only hydrate on desktop -->
<DesktopSidebar client:media="(min-width: 768px)" />

<!-- Only hydrate for users who prefer reduced motion -->
<AnimatedHero client:media="(prefers-reduced-motion: no-preference)" />
```

### client:only

Skips server-side rendering entirely. The component renders only on the client. Use sparingly for components that depend on browser APIs and cannot SSR.

```astro
<!-- Must specify the framework -->
<MapWidget client:only="react" />
<CanvasEditor client:only="svelte" />
```

### No Directive (Static Rendering)

Without any `client:*` directive, framework components render to HTML at build/request time and ship zero JavaScript.

```astro
<!-- Rendered to static HTML, no JS shipped -->
<UserProfile user={user} />
```

---

## Choosing a Hydration Strategy

| Scenario | Directive | Why |
|---|---|---|
| Search bar in header | `client:load` | Must be interactive immediately |
| Shopping cart icon | `client:load` | Users interact with it right away |
| Cookie consent banner | `client:idle` | Important but not blocking |
| Analytics widget | `client:idle` | Can wait for idle time |
| Comment section | `client:visible` | Below the fold |
| Newsletter signup | `client:visible` | Near footer |
| Mobile nav menu | `client:media="(max-width: 768px)"` | Only needed on mobile |
| Map embed | `client:only="react"` | Requires browser APIs |
| Blog post body | No directive | Static content |
| Author bio card | No directive | Static content |

**Rule of thumb:** Start with no directive (static). Add `client:visible` if the component needs interactivity below the fold. Use `client:load` only when the user must interact with it immediately.

---

## Astro Actions

Astro Actions (stable in Astro 5) provide type-safe server functions callable from both server-side code and client-side JavaScript. They use Zod for input validation and return structured results.

### Defining Actions

```typescript
// src/actions/index.ts
import { defineAction } from 'astro:actions';
import { z } from 'astro:schema';

export const server = {
  newsletter: {
    subscribe: defineAction({
      accept: 'form',
      input: z.object({
        email: z.string().email('Please enter a valid email'),
        name: z.string().min(1, 'Name is required').optional(),
      }),
      handler: async (input) => {
        // Server-side logic
        await addToNewsletter(input.email, input.name);
        return { success: true, message: `Subscribed ${input.email}` };
      },
    }),
  },

  comments: {
    create: defineAction({
      accept: 'json',
      input: z.object({
        postId: z.string(),
        body: z.string().min(1).max(1000),
        parentId: z.string().optional(),
      }),
      handler: async (input, context) => {
        const user = context.locals.user;
        if (!user) throw new Error('Must be logged in');

        const comment = await db.comments.create({
          ...input,
          authorId: user.id,
        });
        return comment;
      },
    }),
  },

  likes: {
    toggle: defineAction({
      accept: 'json',
      input: z.object({
        postId: z.string(),
      }),
      handler: async ({ postId }, context) => {
        const userId = context.locals.user?.id;
        if (!userId) throw new Error('Unauthorized');

        const liked = await toggleLike(postId, userId);
        return { liked };
      },
    }),
  },
};
```

### Calling Actions from Astro Pages (Server-Side)

```astro
---
// src/pages/newsletter.astro
import { actions } from 'astro:actions';

const result = Astro.getActionResult(actions.newsletter.subscribe);

if (result && !result.error) {
  // Successfully subscribed
}
---

<form method="POST" action={actions.newsletter.subscribe}>
  <input type="email" name="email" required />
  <input type="text" name="name" placeholder="Name (optional)" />
  <button type="submit">Subscribe</button>

  {result?.error && (
    <p class="error">{result.error.message}</p>
  )}

  {result?.data?.success && (
    <p class="success">{result.data.message}</p>
  )}
</form>
```

### Calling Actions from Client-Side JavaScript

```tsx
// src/components/react/LikeButton.tsx
import { actions } from 'astro:actions';
import { useState } from 'react';

export default function LikeButton({ postId, initialLiked }: {
  postId: string;
  initialLiked: boolean;
}) {
  const [liked, setLiked] = useState(initialLiked);
  const [loading, setLoading] = useState(false);

  async function handleClick() {
    setLoading(true);
    const { data, error } = await actions.likes.toggle({ postId });
    if (!error) {
      setLiked(data.liked);
    }
    setLoading(false);
  }

  return (
    <button onClick={handleClick} disabled={loading}>
      {liked ? 'Unlike' : 'Like'}
    </button>
  );
}
```

---

## Server Islands

Server Islands render on the server at request time but are embedded inside an otherwise static (cached) page. They stream in after the initial page load, combining CDN-cached static content with personalized dynamic content.

### Creating a Server Island

```astro
---
// src/components/UserCart.astro
const user = await getUser(Astro.request);
const cart = user ? await getCart(user.id) : null;
---

<div class="cart-summary">
  {cart ? (
    <a href="/cart">
      Cart ({cart.itemCount}) - ${cart.total.toFixed(2)}
    </a>
  ) : (
    <a href="/login">Sign in</a>
  )}
</div>
```

### Using server:defer

```astro
---
// src/pages/index.astro
import UserCart from '../components/UserCart.astro';
import ProductGrid from '../components/ProductGrid.astro';
---

<html>
  <body>
    <header>
      <h1>Our Store</h1>
      <!-- Server Island: personalized, rendered per-request -->
      <UserCart server:defer>
        <div slot="fallback" class="cart-skeleton">
          Loading cart...
        </div>
      </UserCart>
    </header>

    <!-- Static content: cached at CDN -->
    <ProductGrid />
  </body>
</html>
```

### Server Islands vs client:* Directives

| Feature | Server Islands (`server:defer`) | Client Directives (`client:*`) |
|---|---|---|
| Runs on | Server | Client browser |
| Use case | Personalized server data | Interactive UI |
| JS shipped | None | Framework bundle |
| Data access | Database, secrets, cookies | Public APIs only |
| Example | User greeting, cart count | Search bar, theme toggle |

---

## Sharing State Between Islands

Since each island hydrates independently, sharing state requires explicit coordination.

### Nano Stores (Recommended)

```typescript
// src/stores/cart.ts
import { atom, computed } from 'nanostores';

export interface CartItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
}

export const $cartItems = atom<CartItem[]>([]);

export const $cartTotal = computed($cartItems, (items) =>
  items.reduce((sum, item) => sum + item.price * item.quantity, 0)
);

export const $cartCount = computed($cartItems, (items) =>
  items.reduce((sum, item) => sum + item.quantity, 0)
);

export function addToCart(item: Omit<CartItem, 'quantity'>) {
  const items = $cartItems.get();
  const existing = items.find((i) => i.id === item.id);
  if (existing) {
    $cartItems.set(
      items.map((i) =>
        i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i
      )
    );
  } else {
    $cartItems.set([...items, { ...item, quantity: 1 }]);
  }
}
```

```tsx
// React island
import { useStore } from '@nanostores/react';
import { $cartCount, addToCart } from '../stores/cart';

export function CartIcon() {
  const count = useStore($cartCount);
  return <span>Cart ({count})</span>;
}
```

```svelte
<!-- Svelte island -->
<script>
  import { $cartCount } from '../stores/cart';
</script>

<span>Cart ({$cartCount})</span>
```

Both islands stay in sync because they share the same nano store instance.

---

## Component Patterns

### Layout Component

```astro
---
// src/layouts/BaseLayout.astro
import { ViewTransitions } from 'astro:transitions';
import Header from '../components/Header.astro';
import Footer from '../components/Footer.astro';

interface Props {
  title: string;
  description?: string;
}

const { title, description = 'Default description' } = Astro.props;
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="description" content={description} />
    <title>{title}</title>
    <ViewTransitions />
  </head>
  <body>
    <Header />
    <main>
      <slot />
    </main>
    <Footer />
  </body>
</html>
```

### Conditional Rendering Component

```astro
---
// src/components/ConditionalRender.astro
interface Props {
  when: boolean;
}
const { when } = Astro.props;
---

{when && <slot />}
{!when && <slot name="fallback" />}
```

### List Component with Empty State

```astro
---
// src/components/ItemList.astro
interface Props {
  items: Array<{ id: string; title: string }>;
}
const { items } = Astro.props;
---

{items.length > 0 ? (
  <ul class="item-list">
    {items.map((item) => (
      <li key={item.id}>
        <slot name="item" item={item}>
          {item.title}
        </slot>
      </li>
    ))}
  </ul>
) : (
  <slot name="empty">
    <p>No items to display.</p>
  </slot>
)}
```

---

## Styling Components

### Scoped Styles (Default)

```astro
<h1>Hello</h1>

<style>
  /* Only applies to THIS component's <h1> */
  h1 {
    color: navy;
    font-size: 2rem;
  }
</style>
```

### Global Styles

```astro
<style is:global>
  /* Applies globally (escape hatch) */
  body {
    font-family: system-ui, sans-serif;
  }
</style>
```

### CSS Variables for Theming

```astro
---
interface Props {
  accentColor?: string;
}
const { accentColor = '#6366f1' } = Astro.props;
---

<div class="themed-section" style={`--accent: ${accentColor}`}>
  <slot />
</div>

<style>
  .themed-section {
    border-left: 4px solid var(--accent);
    padding-left: 1rem;
  }
</style>
```

### class:list Utility

```astro
---
const { isActive, variant, className } = Astro.props;
---

<div
  class:list={[
    'base-class',
    { active: isActive, [`variant--${variant}`]: variant },
    className,
  ]}
>
  <slot />
</div>
```

---

## Best Practices

1. **Default to Astro components** for all static content; use framework components only when interactivity is required
2. **Start with no `client:*` directive** and add one only when the component genuinely needs client-side JavaScript
3. **Prefer `client:visible`** over `client:load` for below-the-fold interactive components
4. **Use named slots** for complex component composition instead of deeply nested props
5. **Keep framework components small** so that hydration bundles remain lightweight
6. **Use Nano Stores** for sharing state between islands across different frameworks
7. **Use Astro Actions** for form submissions and server mutations instead of raw API endpoints
8. **Use Server Islands** for personalized content on otherwise cacheable static pages
9. **Scope styles by default** and only use `is:global` when styling third-party markup
10. **Define Props interfaces** with TypeScript for every component
11. **Use `class:list`** for conditional CSS class application
12. **Use `Astro.slots.has()`** to conditionally render slot wrappers

---

## Anti-Patterns

- Adding `client:load` to every component (turns Astro into a heavy SPA)
- Using `client:only` when the component can render on the server first
- Passing large data objects as props to client-hydrated components (bloats the HTML)
- Using React Context across Astro islands (each island is isolated; use Nano Stores)
- Nesting framework components without a `client:*` directive on the parent (children will not hydrate)
- Writing business logic inside `.astro` template expressions instead of utility functions
- Using `is:global` styles for component-specific styling
- Creating API endpoints for simple form submissions when Astro Actions suffice
- Using Server Islands for static content that does not vary per request
- Not providing a `fallback` slot for Server Islands (users see nothing while loading)

---

## Sources & References

- [Astro Documentation: Components](https://docs.astro.build/en/basics/astro-components/)
- [Astro Documentation: Framework Integrations](https://docs.astro.build/en/guides/framework-components/)
- [Astro Documentation: Client Directives](https://docs.astro.build/en/reference/directives-reference/#client-directives)
- [Astro Documentation: Astro Actions](https://docs.astro.build/en/guides/actions/)
- [Astro Documentation: Server Islands](https://docs.astro.build/en/guides/server-islands/)
- [Astro Documentation: Slots](https://docs.astro.build/en/basics/astro-components/#slots)
- [Nano Stores for Astro](https://docs.astro.build/en/recipes/sharing-state-islands/)
- [Astro 5.0 Blog: Actions and Server Islands](https://astro.build/blog/astro-5/)
