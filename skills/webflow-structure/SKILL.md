---
name: webflow-structure
description: Webflow site architecture — page structure, symbols/components, class naming, responsive design, DevLink component library, Designer workflow, utility classes, global styles
---

# Webflow Site Architecture & Structure

Production-ready architecture patterns for Webflow 2026. Covers site structure, page hierarchy, reusable symbols and components, class naming conventions (Client-First methodology), responsive design system, DevLink React component bridge, Designer workflow best practices, and global style management.

## Table of Contents

1. [Site Architecture Principles](#site-architecture-principles)
2. [Page Structure & Hierarchy](#page-structure--hierarchy)
3. [Class Naming with Client-First](#class-naming-with-client-first)
4. [Symbols & Components](#symbols--components)
5. [Responsive Design System](#responsive-design-system)
6. [DevLink Component Library](#devlink-component-library)
7. [Global Styles & Variables](#global-styles--variables)
8. [Utility Class System](#utility-class-system)
9. [Layout Patterns](#layout-patterns)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)

---

## Site Architecture Principles

### Project Planning Before Design

Every Webflow project should begin with a structural plan, not a visual design. The architecture phase determines long-term maintainability, team collaboration speed, and scalability.

**Key Architecture Decisions:**
- **CMS-driven vs static**: Determine which content is dynamic before building pages
- **Component inventory**: Identify reusable patterns across all pages before building any
- **Class strategy**: Choose Client-First or a BEM variant before writing the first class
- **Breakpoint strategy**: Define breakpoints and scaling approach before any responsive work
- **Folder structure**: Organize pages into logical folders that match site navigation

### Webflow Project Hierarchy

```
Site
├── Pages/
│   ├── (root)
│   │   ├── Home
│   │   ├── About
│   │   └── Contact
│   ├── /blog
│   │   ├── Blog Index (CMS Collection Page)
│   │   └── Blog Post (CMS Template Page)
│   ├── /products
│   │   ├── Products Index
│   │   └── Product Detail (CMS Template Page)
│   └── /utility
│       ├── 404
│       ├── Style Guide
│       └── Licenses
├── Symbols/
│   ├── Navbar
│   ├── Footer
│   ├── CTA Section
│   ├── Card - Blog
│   └── Card - Product
├── CMS Collections/
│   ├── Blog Posts
│   ├── Authors
│   ├── Products
│   ├── Categories
│   └── Testimonials
└── Assets/
    ├── Images/
    ├── Fonts/
    └── Documents/
```

**Staff Engineer Decision Matrix:**
- Under 10 pages, no CMS: Static pages with symbols for repeated sections
- 10-50 pages with content updates: CMS-driven with collection templates
- 50+ pages or multi-editor teams: Full Client-First architecture with style guide page, component library, and DevLink integration

---

## Page Structure & Hierarchy

### Standard Page Layout

Every page in Webflow should follow a consistent structural pattern. This enables predictable styling, easier debugging, and reliable CMS integration.

```html
<!-- Standard Webflow page structure -->
<body>
  <!-- page-wrapper: outermost container, enables sticky footer -->
  <div class="page-wrapper">

    <!-- Navbar symbol -->
    <nav class="navbar_component">
      <div class="navbar_container">
        <a href="/" class="navbar_logo-link">
          <img src="logo.svg" class="navbar_logo" alt="Company Name" />
        </a>
        <div class="navbar_menu">
          <a href="/about" class="navbar_link">About</a>
          <a href="/blog" class="navbar_link">Blog</a>
          <a href="/contact" class="navbar_link is-button">Contact</a>
        </div>
        <div class="navbar_menu-button">
          <div class="navbar_hamburger"></div>
        </div>
      </div>
    </nav>

    <!-- main-wrapper: all page content between nav and footer -->
    <main class="main-wrapper">

      <!-- Hero section -->
      <section class="section_hero">
        <div class="padding-global">
          <div class="container-large">
            <div class="hero_component">
              <h1 class="heading-style-h1">Page Title</h1>
              <p class="text-size-large">Subtitle text</p>
            </div>
          </div>
        </div>
      </section>

      <!-- Content section -->
      <section class="section_content">
        <div class="padding-global">
          <div class="container-large">
            <!-- Section content here -->
          </div>
        </div>
      </section>

    </main>

    <!-- Footer symbol -->
    <footer class="footer_component">
      <div class="padding-global">
        <div class="container-large">
          <!-- Footer content -->
        </div>
      </div>
    </footer>

  </div>
</body>
```

### Section Pattern

Every content section follows a three-layer nesting structure that separates concerns:

1. **Section wrapper** (`section_[name]`): Controls background color, overflow, z-index
2. **Padding wrapper** (`padding-global`): Controls horizontal padding consistently
3. **Container** (`container-large`): Controls max-width and centering

```css
/* Section layer: background, position context */
.section_hero {
  position: relative;
  overflow: hidden;
}

/* Padding layer: consistent horizontal spacing */
.padding-global {
  padding-left: 5%;
  padding-right: 5%;
}

/* Container layer: max-width and centering */
.container-large {
  width: 100%;
  max-width: 80rem;
  margin-left: auto;
  margin-right: auto;
}
```

---

## Class Naming with Client-First

Client-First is the dominant Webflow class naming methodology in 2025/2026. It creates a scalable, predictable system that works across teams.

### Core Naming Rules

**Component classes**: `[block]_[element]`
- `navbar_link`, `hero_heading`, `card_image`, `footer_column`

**Utility classes**: `[property]-[value]`
- `text-size-large`, `margin-top-24`, `text-color-white`

**State classes**: `is-[state]`
- `is-active`, `is-hidden`, `is-dark`, `is-reversed`

### Naming Examples

```html
<!-- Component: header -->
<header class="header_component">
  <div class="header_content-wrapper">
    <h1 class="header_heading">Welcome</h1>
    <p class="header_text">Description</p>
    <a class="header_button">Get Started</a>
  </div>
  <div class="header_image-wrapper">
    <img class="header_image" src="hero.jpg" alt="Hero image" />
  </div>
</header>

<!-- Component: card (reusable) -->
<div class="card_component">
  <img class="card_image" src="thumb.jpg" alt="Card thumbnail" />
  <div class="card_content">
    <h3 class="card_title">Card Title</h3>
    <p class="card_description">Card description text</p>
  </div>
  <a class="card_link">Read More</a>
</div>

<!-- Utility classes for spacing and typography -->
<div class="margin-bottom-48">
  <h2 class="heading-style-h2 text-color-white">Section Title</h2>
  <p class="text-size-medium text-color-grey">Body text</p>
</div>
```

### Class Stacking Rules

1. One **component class** per element (defines structure)
2. Stack **utility classes** after the component class (modify appearance)
3. Stack **state classes** last (conditional modifications)

```html
<!-- Correct stacking order -->
<a class="card_link text-size-small text-color-blue is-active">Link</a>

<!-- WRONG: Multiple component classes on one element -->
<a class="card_link button_primary">Link</a>
```

---

## Symbols & Components

### Symbol Strategy

Symbols in Webflow are the equivalent of components in code. They enable reuse and ensure consistency across pages.

**When to create a symbol:**
- Element appears on 3+ pages (navbar, footer, CTA)
- Element has a consistent structure but varying content (cards, testimonials)
- Element needs global updates when changed (pricing tables, feature lists)

**When NOT to create a symbol:**
- One-off hero sections unique to a single page
- Layout wrappers (sections, containers)
- Elements that vary significantly between instances

### Symbol Architecture

```
Symbols/
├── Global/
│   ├── Navbar                    # Site-wide navigation
│   ├── Footer                    # Site-wide footer
│   └── CTA - Newsletter          # Newsletter signup block
├── Cards/
│   ├── Card - Blog               # Blog post card
│   ├── Card - Product            # Product card
│   ├── Card - Team               # Team member card
│   └── Card - Testimonial        # Testimonial card
├── Sections/
│   ├── Section - Feature Grid    # Feature showcase
│   ├── Section - Stats           # Statistics bar
│   └── Section - Logos           # Client logo strip
└── UI/
    ├── Button - Primary          # Primary CTA button
    ├── Button - Secondary        # Secondary button
    └── Modal - Popup             # Popup modal
```

### Component Properties with CMS Binding

When building symbols that will be populated by CMS data, structure them to accept CMS field bindings at every dynamic point:

```html
<!-- Card - Blog symbol structure -->
<div class="blog-card_component">
  <a class="blog-card_link-wrapper" href="/blog/{slug}">
    <!-- CMS Image field binding -->
    <img class="blog-card_image"
         src="{featured-image}"
         alt="{featured-image-alt}"
         loading="lazy" />
    <div class="blog-card_content">
      <!-- CMS Category reference field -->
      <div class="blog-card_category text-size-small text-color-grey">
        {category-name}
      </div>
      <!-- CMS Title field -->
      <h3 class="blog-card_title heading-style-h5">{post-title}</h3>
      <!-- CMS Summary field -->
      <p class="blog-card_summary text-size-regular">{post-summary}</p>
      <!-- CMS Date field -->
      <time class="blog-card_date text-size-small">{published-date}</time>
    </div>
  </a>
</div>
```

---

## Responsive Design System

### Breakpoint Strategy

Webflow uses a desktop-first cascade with these default breakpoints:

| Breakpoint | Width | Target |
|---|---|---|
| Desktop (base) | 992px+ | Laptops, desktops |
| Tablet | 991px and below | Tablets landscape |
| Mobile Landscape | 767px and below | Phones landscape, small tablets |
| Mobile Portrait | 478px and below | Phones portrait |

**Critical rule**: Styles cascade DOWN. Set base styles at desktop, then override only what changes at each smaller breakpoint.

### Responsive Class Patterns

```css
/* Desktop (base) - Grid layout */
.feature_grid {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 2rem;
}

/* Tablet - 2 columns */
@media screen and (max-width: 991px) {
  .feature_grid {
    grid-template-columns: 1fr 1fr;
  }
}

/* Mobile Landscape - 1 column */
@media screen and (max-width: 767px) {
  .feature_grid {
    grid-template-columns: 1fr;
    gap: 1.5rem;
  }
}

/* Mobile Portrait - Tighter spacing */
@media screen and (max-width: 478px) {
  .feature_grid {
    gap: 1rem;
  }
}
```

### Responsive Typography Scale

```css
/* Desktop base */
.heading-style-h1 { font-size: 4rem; line-height: 1.1; }
.heading-style-h2 { font-size: 3rem; line-height: 1.2; }
.heading-style-h3 { font-size: 2.25rem; line-height: 1.3; }
.heading-style-h4 { font-size: 1.75rem; line-height: 1.4; }

/* Tablet */
@media screen and (max-width: 991px) {
  .heading-style-h1 { font-size: 3rem; }
  .heading-style-h2 { font-size: 2.5rem; }
  .heading-style-h3 { font-size: 2rem; }
}

/* Mobile Portrait */
@media screen and (max-width: 478px) {
  .heading-style-h1 { font-size: 2.25rem; }
  .heading-style-h2 { font-size: 2rem; }
  .heading-style-h3 { font-size: 1.75rem; }
}
```

### Responsive Visibility

Use utility classes to show/hide elements at specific breakpoints rather than complex CSS:

```html
<!-- Show on desktop only -->
<div class="hide-tablet">Desktop navigation</div>

<!-- Show on tablet and below only -->
<div class="show-tablet">Mobile hamburger menu</div>
```

---

## DevLink Component Library

DevLink bridges Webflow Designer components to React code, enabling teams to use Webflow-designed components in Next.js or React applications.

### DevLink Setup

```bash
# Install Webflow DevLink CLI
npm install @webflow/react

# Sync components from Webflow
npx webflow devlink sync --site-id=YOUR_SITE_ID

# Generated output structure
src/
└── devlink/
    ├── index.js           # Barrel exports
    ├── Navbar.js          # Synced Navbar component
    ├── Navbar.module.css  # Scoped styles
    ├── HeroSection.js     # Synced Hero component
    ├── HeroSection.module.css
    ├── BlogCard.js
    └── BlogCard.module.css
```

### Using DevLink Components in React

```tsx
// app/page.tsx
import { HeroSection, BlogCard } from '@/devlink';

interface BlogPost {
  id: string;
  title: string;
  summary: string;
  image: string;
  slug: string;
}

export default function HomePage({ posts }: { posts: BlogPost[] }) {
  return (
    <>
      <HeroSection
        heading="Welcome to Our Blog"
        subheading="Latest articles and insights"
        ctaText="Browse All"
        ctaLink="/blog"
      />
      <section className="section_blog">
        {posts.map((post) => (
          <BlogCard
            key={post.id}
            title={post.title}
            summary={post.summary}
            image={post.image}
            link={`/blog/${post.slug}`}
          />
        ))}
      </section>
    </>
  );
}
```

### DevLink with Dynamic Data

```tsx
// components/DynamicTestimonials.tsx
'use client';

import { TestimonialCard } from '@/devlink';
import { useEffect, useState } from 'react';

interface Testimonial {
  id: string;
  quote: string;
  author: string;
  role: string;
  avatar: string;
}

export function DynamicTestimonials() {
  const [testimonials, setTestimonials] = useState<Testimonial[]>([]);

  useEffect(() => {
    fetch('/api/testimonials')
      .then(res => res.json())
      .then(setTestimonials);
  }, []);

  return (
    <div className="testimonials_grid">
      {testimonials.map((t) => (
        <TestimonialCard
          key={t.id}
          quote={t.quote}
          authorName={t.author}
          authorRole={t.role}
          authorImage={t.avatar}
        />
      ))}
    </div>
  );
}
```

---

## Global Styles & Variables

### CSS Variables in Webflow

Webflow supports CSS custom properties for design tokens. Define them at the body level for global access.

```css
/* Embed in site-wide custom code <head> */
:root {
  /* Colors */
  --color-primary: #2563eb;
  --color-primary-dark: #1d4ed8;
  --color-secondary: #7c3aed;
  --color-text-primary: #111827;
  --color-text-secondary: #6b7280;
  --color-bg-primary: #ffffff;
  --color-bg-secondary: #f9fafb;
  --color-border: #e5e7eb;

  /* Typography */
  --font-primary: 'Inter', sans-serif;
  --font-heading: 'Plus Jakarta Sans', sans-serif;
  --font-mono: 'JetBrains Mono', monospace;

  /* Spacing scale (8px base) */
  --space-1: 0.25rem;   /* 4px */
  --space-2: 0.5rem;    /* 8px */
  --space-3: 0.75rem;   /* 12px */
  --space-4: 1rem;      /* 16px */
  --space-6: 1.5rem;    /* 24px */
  --space-8: 2rem;      /* 32px */
  --space-12: 3rem;     /* 48px */
  --space-16: 4rem;     /* 64px */
  --space-24: 6rem;     /* 96px */

  /* Shadows */
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
  --shadow-md: 0 4px 6px rgba(0, 0, 0, 0.07);
  --shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.1);

  /* Border radius */
  --radius-sm: 0.375rem;
  --radius-md: 0.5rem;
  --radius-lg: 0.75rem;
  --radius-full: 9999px;

  /* Transitions */
  --transition-fast: 150ms ease;
  --transition-base: 250ms ease;
  --transition-slow: 400ms ease;
}

/* Dark mode overrides */
[data-theme="dark"] {
  --color-text-primary: #f9fafb;
  --color-text-secondary: #9ca3af;
  --color-bg-primary: #111827;
  --color-bg-secondary: #1f2937;
  --color-border: #374151;
}
```

### Style Guide Page

Every production Webflow project should include a `/style-guide` page that documents all design tokens, typography, colors, and component variants visually.

```html
<!-- /style-guide page structure -->
<section class="section_style-guide">
  <div class="padding-global">
    <div class="container-large">

      <!-- Typography showcase -->
      <h2>Typography</h2>
      <h1 class="heading-style-h1">Heading 1 — 4rem/64px</h1>
      <h2 class="heading-style-h2">Heading 2 — 3rem/48px</h2>
      <h3 class="heading-style-h3">Heading 3 — 2.25rem/36px</h3>
      <p class="text-size-large">Large body — 1.25rem/20px</p>
      <p class="text-size-regular">Regular body — 1rem/16px</p>
      <p class="text-size-small">Small body — 0.875rem/14px</p>

      <!-- Color swatches -->
      <h2>Colors</h2>
      <div class="style-guide_color-grid">
        <div class="style-guide_swatch" style="background: var(--color-primary)">
          Primary
        </div>
        <div class="style-guide_swatch" style="background: var(--color-secondary)">
          Secondary
        </div>
      </div>

      <!-- Button variants -->
      <h2>Buttons</h2>
      <a class="button is-primary">Primary Button</a>
      <a class="button is-secondary">Secondary Button</a>
      <a class="button is-outline">Outline Button</a>

    </div>
  </div>
</section>
```

---

## Utility Class System

### Spacing Utilities

```css
/* Margin utilities */
.margin-top-0 { margin-top: 0; }
.margin-top-8 { margin-top: 0.5rem; }
.margin-top-16 { margin-top: 1rem; }
.margin-top-24 { margin-top: 1.5rem; }
.margin-top-32 { margin-top: 2rem; }
.margin-top-48 { margin-top: 3rem; }
.margin-top-64 { margin-top: 4rem; }

.margin-bottom-0 { margin-bottom: 0; }
.margin-bottom-8 { margin-bottom: 0.5rem; }
.margin-bottom-16 { margin-bottom: 1rem; }
.margin-bottom-24 { margin-bottom: 1.5rem; }
.margin-bottom-32 { margin-bottom: 2rem; }
.margin-bottom-48 { margin-bottom: 3rem; }

/* Padding utilities */
.padding-vertical-24 { padding-top: 1.5rem; padding-bottom: 1.5rem; }
.padding-vertical-48 { padding-top: 3rem; padding-bottom: 3rem; }
.padding-vertical-64 { padding-top: 4rem; padding-bottom: 4rem; }
.padding-vertical-96 { padding-top: 6rem; padding-bottom: 6rem; }
```

### Typography Utilities

```css
/* Text alignment */
.text-align-center { text-align: center; }
.text-align-left { text-align: left; }
.text-align-right { text-align: right; }

/* Text weight */
.text-weight-regular { font-weight: 400; }
.text-weight-medium { font-weight: 500; }
.text-weight-semibold { font-weight: 600; }
.text-weight-bold { font-weight: 700; }

/* Text color */
.text-color-white { color: #ffffff; }
.text-color-grey { color: var(--color-text-secondary); }
.text-color-primary { color: var(--color-primary); }
```

---

## Layout Patterns

### CSS Grid in Webflow

```css
/* 12-column grid system */
.grid_component {
  display: grid;
  grid-template-columns: repeat(12, 1fr);
  gap: 2rem;
}

.grid_col-span-4 { grid-column: span 4; }
.grid_col-span-6 { grid-column: span 6; }
.grid_col-span-8 { grid-column: span 8; }
.grid_col-span-12 { grid-column: span 12; }

/* Auto-fit responsive grid (no media queries needed) */
.grid_auto-fit {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 2rem;
}

/* Tablet override */
@media screen and (max-width: 991px) {
  .grid_col-span-4,
  .grid_col-span-6,
  .grid_col-span-8 {
    grid-column: span 12;
  }
}
```

### Flexbox Patterns

```css
/* Centered content */
.flex-center {
  display: flex;
  align-items: center;
  justify-content: center;
}

/* Space between (nav, footer rows) */
.flex-between {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

/* Vertical stack with gap */
.flex-col-gap-16 {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
```

---

## Best Practices

1. **Adopt Client-First naming** from day one -- retrofitting class names is extremely expensive
2. **Create a style guide page** before building any content pages -- it serves as your design token reference
3. **Use the section/padding/container pattern** on every section for consistent horizontal spacing
4. **Build symbols for repeated elements** -- if you copy-paste a structure, it should be a symbol
5. **Set responsive styles only where they change** -- do not re-declare identical styles at smaller breakpoints
6. **Use CSS variables for design tokens** -- colors, fonts, spacing, shadows should come from variables
7. **Keep class count low on each element** -- one component class plus 1-2 utility classes maximum
8. **Use DevLink for hybrid projects** -- design in Webflow, develop dynamic logic in React/Next.js
9. **Lazy-load images below the fold** -- use native `loading="lazy"` attribute on all non-hero images
10. **Document all components on the style guide page** -- future editors need a visual reference

---

## Anti-Patterns

- Creating one-off classes like `about-page-second-section-title` instead of reusable component classes
- Nesting more than 3 levels deep in the Designer tree (flattening improves performance and readability)
- Using absolute positioning for layout instead of Flexbox/Grid
- Setting font sizes in pixels instead of rem (breaks accessibility zoom)
- Duplicating style overrides at every breakpoint instead of relying on desktop-first cascade
- Not using symbols for navbar/footer (changes require editing every page manually)
- Mixing naming conventions (BEM on some classes, Client-First on others) within a single project
- Ignoring the style guide page -- leads to inconsistent design token usage across pages
- Using Webflow's default class names (e.g., `Div Block 47`) in production

---

## Sources & References

- [Client-First Style System for Webflow](https://finsweet.com/client-first)
- [Webflow University: Web Structure](https://university.webflow.com/lesson/web-structure)
- [Webflow DevLink Documentation](https://developers.webflow.com/data/docs/devlink)
- [Webflow Designer API Reference](https://developers.webflow.com/designer/reference/introduction)
- [Responsive Design Best Practices in Webflow](https://university.webflow.com/lesson/responsive-design)
- [Webflow CSS Grid Guide](https://university.webflow.com/lesson/css-grid)
- [Finsweet Client-First Naming Conventions](https://finsweet.com/client-first/docs/naming-strategy)
- [Webflow Variables and Design Tokens](https://university.webflow.com/lesson/variables)
