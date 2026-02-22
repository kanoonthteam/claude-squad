---
name: webflow-testing
description: Webflow QA — staging/publishing workflow, cross-browser testing, responsive testing, SEO audit, performance optimization, accessibility compliance, backup/restore strategies
---

# Webflow Testing & Quality Assurance

Production-ready QA patterns for Webflow 2026. Covers staging and publishing workflows, cross-browser and responsive testing, SEO auditing, Core Web Vitals optimization, WCAG accessibility compliance, backup and versioning strategies, and pre-launch checklists.

## Table of Contents

1. [QA Workflow Overview](#qa-workflow-overview)
2. [Staging & Publishing](#staging--publishing)
3. [Cross-Browser Testing](#cross-browser-testing)
4. [Responsive Testing](#responsive-testing)
5. [SEO Audit & Optimization](#seo-audit--optimization)
6. [Performance Optimization](#performance-optimization)
7. [Accessibility Compliance](#accessibility-compliance)
8. [Backup & Restore](#backup--restore)
9. [Pre-Launch Checklist](#pre-launch-checklist)
10. [Monitoring & Maintenance](#monitoring--maintenance)
11. [Best Practices](#best-practices)
12. [Anti-Patterns](#anti-patterns)

---

## QA Workflow Overview

### Testing Phases

Every Webflow project should follow a structured QA pipeline before going live:

```
Phase 1: Design QA (during build)
├── Visual fidelity: matches design comp
├── Component consistency: symbols render correctly everywhere
├── Content accuracy: no placeholder text remains
└── Interaction review: all animations fire correctly

Phase 2: Functional QA (pre-staging)
├── Link audit: all internal and external links work
├── Form testing: all forms submit and redirect correctly
├── CMS verification: dynamic content renders on all template pages
├── E-commerce flow: cart, checkout, confirmation tested end-to-end
└── Custom code: all JavaScript executes without console errors

Phase 3: Cross-Platform QA (on staging)
├── Browser testing: Chrome, Safari, Firefox, Edge (latest 2 versions)
├── Device testing: Desktop, tablet, mobile (iOS + Android)
├── Responsive testing: all 4 Webflow breakpoints verified
└── OS testing: macOS, Windows, iOS, Android

Phase 4: Performance & SEO QA (pre-launch)
├── Core Web Vitals: LCP < 2.5s, FID < 100ms, CLS < 0.1
├── Lighthouse score: 90+ on Performance, Accessibility, SEO, Best Practices
├── SEO meta tags: title, description, OG tags on every page
├── Sitemap & robots.txt: validated and submitted
└── Structured data: JSON-LD validates in Google Rich Results Test

Phase 5: Launch & Post-Launch
├── DNS configuration: domain connected, SSL active
├── Analytics: tracking code verified (GA4, GTM, etc.)
├── Redirects: old URLs redirect to new pages (301)
├── Monitor: uptime monitoring enabled
└── Backup: pre-launch backup saved
```

### QA Documentation Template

Maintain a QA spreadsheet for every project:

```
| Page/Component | Browser | Device    | Status | Issue           | Assignee | Fixed |
|---|---|---|---|---|---|---|
| Homepage       | Chrome  | Desktop   | Pass   | -               | -        | -     |
| Homepage       | Safari  | iPhone 15 | Fail   | Hero text clips | John     | Yes   |
| Blog Template  | Firefox | Desktop   | Pass   | -               | -        | -     |
| Contact Form   | Edge    | Desktop   | Fail   | Submit 500 err  | Jane     | Yes   |
| Product Page   | Safari  | iPad Pro  | Pass   | -               | -        | -     |
```

---

## Staging & Publishing

### Webflow Staging vs Production

Webflow provides two environments:

1. **Staging** (`*.webflow.io`): Auto-publishes on every save. Used for internal review and testing. Free SSL.
2. **Production** (custom domain): Only updates when you explicitly click "Publish". This is the live site.

**Key differences:**
- Staging reflects the latest saved state of the Designer
- Production only updates on manual publish
- CMS changes can be published independently (without publishing site design changes)
- Form submissions on staging go to the same inbox as production (be careful)

### Publishing Workflow

```
Development Workflow:
1. Make changes in Designer
2. Save (auto-publishes to staging)
3. Test on staging URL (yoursite.webflow.io)
4. Get approval from client/stakeholder
5. Publish to production (custom domain)

CMS Content Workflow:
1. Editor creates/edits CMS item
2. Item saved as Draft (visible in Designer, not on production)
3. Editor marks item as "Ready for Review"
4. Reviewer approves and publishes CMS items
5. CMS items go live without republishing the entire site

Rollback Workflow:
1. Identify the issue on production
2. Open Dashboard → Backups
3. Select the backup from before the issue
4. Restore backup (reverts Designer state)
5. Publish to production again
```

### Staging Environment Protection

```html
<!-- Add to staging site's custom code to prevent indexing -->
<!-- Site Settings → Custom Code → Head Code -->
<script>
  // Block staging from being indexed
  if (window.location.hostname.includes('webflow.io')) {
    const meta = document.createElement('meta');
    meta.name = 'robots';
    meta.content = 'noindex, nofollow';
    document.head.appendChild(meta);
  }
</script>

<!-- Optional: Add a staging banner for reviewers -->
<script>
  if (window.location.hostname.includes('webflow.io')) {
    const banner = document.createElement('div');
    banner.innerHTML = 'STAGING ENVIRONMENT — Not for public use';
    banner.style.cssText = `
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      background: #ef4444;
      color: white;
      text-align: center;
      padding: 8px;
      font-size: 14px;
      font-weight: 600;
      z-index: 99999;
    `;
    document.body.appendChild(banner);
  }
</script>
```

---

## Cross-Browser Testing

### Browser Support Matrix (2026)

| Browser | Versions | Market Share | Priority |
|---|---|---|---|
| Chrome | Latest 2 | ~63% | Critical |
| Safari | Latest 2 | ~19% | Critical |
| Edge | Latest 2 | ~5% | High |
| Firefox | Latest 2 | ~3% | High |
| Samsung Internet | Latest | ~3% | Medium |
| Opera | Latest | ~2% | Low |

### Common Browser Issues in Webflow

**Safari-specific issues:**
- Flexbox gap not supported in Safari < 14.1
- `backdrop-filter` needs `-webkit-backdrop-filter` prefix
- Smooth scroll behavior inconsistent
- Video autoplay requires `muted` and `playsinline` attributes
- 100vh includes the address bar (use `100dvh` or `100svh` instead)

**Firefox-specific issues:**
- CSS `scroll-snap` behavior differs slightly from Chrome
- Webflow's lightbox may render differently
- Custom fonts may render with different weight/spacing

**Edge-specific issues:**
- Generally Chrome-compatible (Chromium-based)
- Older Edge (pre-Chromium) no longer needs support

### Cross-Browser Testing Checklist

```
For each target browser + device combination:

Layout & Structure:
[ ] Page layout renders correctly (no overflow, no misalignment)
[ ] Grid and flexbox layouts match design
[ ] Fixed/sticky elements position correctly
[ ] Z-index stacking correct (no overlapping issues)
[ ] Overflow hidden works on all containers

Typography:
[ ] Fonts load correctly (check FOUT/FOIT)
[ ] Font weights render accurately
[ ] Line heights and letter spacing consistent
[ ] Text truncation with ellipsis works
[ ] Rich text content styled correctly

Images & Media:
[ ] All images load (check for broken src paths)
[ ] Responsive images serve correct size (srcset)
[ ] SVGs render correctly
[ ] Videos autoplay and loop where expected
[ ] Lottie animations render without artifacts

Interactions & Animations:
[ ] Hover states work (desktop only)
[ ] Click/tap interactions fire correctly
[ ] Scroll animations trigger at correct positions
[ ] Page load animations complete
[ ] Transitions smooth (no jank or flicker)

Forms:
[ ] All form fields render correctly
[ ] Validation messages display
[ ] Form submission succeeds
[ ] Success/error states display
[ ] File uploads work (if applicable)

Navigation:
[ ] All links navigate to correct pages
[ ] Dropdown menus open and close
[ ] Mobile menu toggles correctly
[ ] Anchor links scroll to correct position
[ ] Back button works as expected
```

### Automated Browser Testing with Playwright

```javascript
// playwright.config.js
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  use: {
    baseURL: 'https://your-site.webflow.io', // Test against staging
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'Chrome Desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'Safari Desktop', use: { ...devices['Desktop Safari'] } },
    { name: 'Firefox Desktop', use: { ...devices['Desktop Firefox'] } },
    { name: 'iPhone 15', use: { ...devices['iPhone 15'] } },
    { name: 'iPad Pro', use: { ...devices['iPad Pro 11'] } },
    { name: 'Pixel 7', use: { ...devices['Pixel 7'] } },
  ],
});
```

```javascript
// tests/visual-regression.spec.js
import { test, expect } from '@playwright/test';

const pages = [
  { name: 'Home', path: '/' },
  { name: 'About', path: '/about' },
  { name: 'Blog', path: '/blog' },
  { name: 'Contact', path: '/contact' },
];

for (const page of pages) {
  test(`${page.name} page visual regression`, async ({ page: browserPage }) => {
    await browserPage.goto(page.path);
    // Wait for fonts and images to load
    await browserPage.waitForLoadState('networkidle');
    // Wait for Webflow interactions to initialize
    await browserPage.waitForTimeout(1000);

    await expect(browserPage).toHaveScreenshot(`${page.name}.png`, {
      fullPage: true,
      maxDiffPixelRatio: 0.02, // Allow 2% pixel difference
    });
  });
}

test('navigation links work correctly', async ({ page }) => {
  await page.goto('/');

  // Test each nav link
  const navLinks = page.locator('.navbar_link');
  const linkCount = await navLinks.count();

  for (let i = 0; i < linkCount; i++) {
    const link = navLinks.nth(i);
    const href = await link.getAttribute('href');
    if (href && !href.startsWith('#')) {
      const [response] = await Promise.all([
        page.waitForNavigation(),
        link.click(),
      ]);
      expect(response?.status()).toBe(200);
      await page.goto('/'); // Navigate back
    }
  }
});

test('contact form submits successfully', async ({ page }) => {
  await page.goto('/contact');

  await page.fill('input[name="Name"]', 'Test User');
  await page.fill('input[name="Email"]', 'test@example.com');
  await page.fill('textarea[name="Message"]', 'This is an automated test.');

  await page.click('input[type="submit"]');

  // Check for success message
  await expect(page.locator('.w-form-done')).toBeVisible({ timeout: 5000 });
});
```

---

## Responsive Testing

### Breakpoint Testing Strategy

Test every page at each Webflow breakpoint plus critical widths:

```
Test Widths:
├── 1920px  (Full HD desktop)
├── 1440px  (Standard laptop)
├── 1280px  (Small laptop)
├── 1024px  (iPad landscape / large tablet)
├── 991px   ← Webflow Tablet breakpoint trigger
├── 768px   (iPad portrait)
├── 767px   ← Webflow Mobile Landscape breakpoint trigger
├── 480px   (Large phone)
├── 478px   ← Webflow Mobile Portrait breakpoint trigger
├── 375px   (iPhone SE / small phone)
├── 320px   (Minimum supported width)
```

### Responsive Issues to Check

```
At each breakpoint, verify:

Layout:
[ ] No horizontal scroll (body overflow-x: hidden)
[ ] Content does not overflow containers
[ ] Grid columns collapse correctly
[ ] Flex items wrap as expected
[ ] Images scale within their containers
[ ] Spacing (padding/margin) reduces proportionally

Navigation:
[ ] Desktop nav hidden on mobile breakpoints
[ ] Hamburger menu visible on mobile breakpoints
[ ] Mobile menu opens/closes correctly
[ ] Mobile menu scrollable if many links
[ ] Dropdown menus accessible on mobile

Typography:
[ ] Headings readable at all sizes
[ ] Body text minimum 16px on mobile (prevents iOS zoom)
[ ] Line length stays between 45-75 characters
[ ] Text does not overflow or clip

Interactive Elements:
[ ] Touch targets minimum 44x44px on mobile
[ ] Hover interactions gracefully degrade on touch
[ ] Forms usable on mobile (fields large enough)
[ ] Buttons full-width on mobile portrait

Media:
[ ] Hero images crop well at all sizes
[ ] Background images position correctly
[ ] Videos responsive (16:9 maintained)
[ ] Lottie animations scale proportionally
```

### Responsive Testing in Code

```javascript
// Automated responsive screenshot testing
import { test, expect } from '@playwright/test';

const viewports = [
  { name: 'Desktop', width: 1440, height: 900 },
  { name: 'Tablet', width: 991, height: 1024 },
  { name: 'Mobile-Landscape', width: 767, height: 375 },
  { name: 'Mobile-Portrait', width: 375, height: 812 },
];

const pages = ['/', '/about', '/blog', '/contact'];

for (const viewport of viewports) {
  for (const pagePath of pages) {
    test(`${pagePath} at ${viewport.name}`, async ({ page }) => {
      await page.setViewportSize({
        width: viewport.width,
        height: viewport.height,
      });
      await page.goto(pagePath);
      await page.waitForLoadState('networkidle');

      // Check no horizontal overflow
      const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
      expect(bodyWidth).toBeLessThanOrEqual(viewport.width);

      // Visual regression
      await expect(page).toHaveScreenshot(
        `${pagePath.replace('/', 'home')}-${viewport.name}.png`,
        { fullPage: true }
      );
    });
  }
}
```

---

## SEO Audit & Optimization

### Technical SEO Checklist

```
Meta Tags (every page):
[ ] Unique <title> tag (50-60 characters)
[ ] Unique <meta description> (120-160 characters)
[ ] Canonical URL set (self-referencing or pointing to preferred version)
[ ] Open Graph tags: og:title, og:description, og:image, og:url
[ ] Twitter Card tags: twitter:card, twitter:title, twitter:description, twitter:image
[ ] Viewport meta tag present (Webflow adds this automatically)

Crawlability:
[ ] robots.txt allows crawling of important pages
[ ] robots.txt blocks /cdn-cgi/ and other system paths
[ ] XML sitemap generated and accessible at /sitemap.xml
[ ] Sitemap submitted to Google Search Console
[ ] No unintentional noindex tags on public pages
[ ] staging.webflow.io has noindex (prevent duplicate content)

Page Structure:
[ ] Single <h1> per page
[ ] Heading hierarchy logical (h1 → h2 → h3, no skips)
[ ] Images have descriptive alt text
[ ] Links have descriptive anchor text (not "click here")
[ ] Internal linking strategy implemented
[ ] 404 page exists and is useful

URL Structure:
[ ] Clean, descriptive URLs (no /page-1, /untitled)
[ ] CMS slugs are human-readable
[ ] No duplicate content across multiple URLs
[ ] Trailing slashes consistent (Webflow uses trailing slash)
[ ] Old URLs have 301 redirects to new URLs
```

### SEO Audit Script

```javascript
// Automated SEO audit for Webflow sites
async function auditSEO(baseUrl) {
  const issues = [];

  // Fetch the page
  const response = await fetch(baseUrl);
  const html = await response.text();
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, 'text/html');

  // Check title tag
  const title = doc.querySelector('title')?.textContent || '';
  if (!title) issues.push({ severity: 'critical', message: 'Missing <title> tag' });
  if (title.length > 60) issues.push({ severity: 'warning', message: `Title too long: ${title.length} chars` });
  if (title.length < 30) issues.push({ severity: 'warning', message: `Title too short: ${title.length} chars` });

  // Check meta description
  const metaDesc = doc.querySelector('meta[name="description"]')?.getAttribute('content') || '';
  if (!metaDesc) issues.push({ severity: 'critical', message: 'Missing meta description' });
  if (metaDesc.length > 160) issues.push({ severity: 'warning', message: `Meta description too long: ${metaDesc.length} chars` });

  // Check heading hierarchy
  const h1Tags = doc.querySelectorAll('h1');
  if (h1Tags.length === 0) issues.push({ severity: 'critical', message: 'No <h1> found' });
  if (h1Tags.length > 1) issues.push({ severity: 'warning', message: `Multiple <h1> tags: ${h1Tags.length}` });

  // Check images without alt text
  const images = doc.querySelectorAll('img');
  let missingAlt = 0;
  images.forEach(img => {
    if (!img.getAttribute('alt') && !img.getAttribute('role')?.includes('presentation')) {
      missingAlt++;
    }
  });
  if (missingAlt > 0) issues.push({ severity: 'warning', message: `${missingAlt} images missing alt text` });

  // Check Open Graph tags
  const ogTitle = doc.querySelector('meta[property="og:title"]');
  const ogDesc = doc.querySelector('meta[property="og:description"]');
  const ogImage = doc.querySelector('meta[property="og:image"]');
  if (!ogTitle) issues.push({ severity: 'warning', message: 'Missing og:title' });
  if (!ogDesc) issues.push({ severity: 'warning', message: 'Missing og:description' });
  if (!ogImage) issues.push({ severity: 'warning', message: 'Missing og:image' });

  // Check canonical
  const canonical = doc.querySelector('link[rel="canonical"]');
  if (!canonical) issues.push({ severity: 'warning', message: 'Missing canonical URL' });

  return issues;
}
```

### Structured Data Validation

```html
<!-- Organization schema (site-wide) -->
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "Your Company",
  "url": "https://yoursite.com",
  "logo": "https://yoursite.com/images/logo.png",
  "sameAs": [
    "https://twitter.com/yourcompany",
    "https://linkedin.com/company/yourcompany"
  ],
  "contactPoint": {
    "@type": "ContactPoint",
    "telephone": "+1-555-123-4567",
    "contactType": "customer service"
  }
}
</script>

<!-- Breadcrumb schema (on inner pages) -->
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    {
      "@type": "ListItem",
      "position": 1,
      "name": "Home",
      "item": "https://yoursite.com"
    },
    {
      "@type": "ListItem",
      "position": 2,
      "name": "Blog",
      "item": "https://yoursite.com/blog"
    },
    {
      "@type": "ListItem",
      "position": 3,
      "name": "{{wf {&quot;path&quot;:&quot;name&quot;} }}"
    }
  ]
}
</script>
```

---

## Performance Optimization

### Core Web Vitals Targets

| Metric | Good | Needs Improvement | Poor |
|---|---|---|---|
| LCP (Largest Contentful Paint) | < 2.5s | 2.5-4.0s | > 4.0s |
| INP (Interaction to Next Paint) | < 200ms | 200-500ms | > 500ms |
| CLS (Cumulative Layout Shift) | < 0.1 | 0.1-0.25 | > 0.25 |

### Image Optimization

```
Image Optimization Checklist:
[ ] Use WebP format (Webflow auto-converts uploaded images)
[ ] Set explicit width and height on all <img> elements (prevents CLS)
[ ] Use loading="lazy" on below-the-fold images
[ ] Use sizes attribute for responsive images
[ ] Hero images: max 200KB, preloaded
[ ] Thumbnails: max 50KB
[ ] Background images: use CSS background-image with responsive breakpoints
[ ] Remove unused images from Assets panel
```

```html
<!-- Responsive image with proper sizing -->
<img class="hero_image"
     src="hero-1600.webp"
     srcset="hero-400.webp 400w,
             hero-800.webp 800w,
             hero-1200.webp 1200w,
             hero-1600.webp 1600w"
     sizes="(max-width: 478px) 100vw,
            (max-width: 991px) 100vw,
            50vw"
     alt="Hero description"
     width="1600"
     height="900"
     loading="eager"
     fetchpriority="high" />
```

### Font Optimization

```html
<!-- Preload critical fonts -->
<link rel="preload" href="/fonts/inter-var.woff2"
      as="font" type="font/woff2" crossorigin />

<!-- Font display strategy -->
<style>
  @font-face {
    font-family: 'Inter';
    src: url('/fonts/inter-var.woff2') format('woff2');
    font-weight: 100 900;
    font-display: swap; /* Show fallback immediately, swap when loaded */
  }
</style>
```

### Script Loading Optimization

```html
<!-- Correct script loading order -->
<!-- 1. Critical scripts: inline in <head> (small, blocking) -->
<script>
  // Set theme immediately to prevent flash
  const theme = localStorage.getItem('theme') || 'light';
  document.documentElement.setAttribute('data-theme', theme);
</script>

<!-- 2. Third-party scripts: defer (non-blocking) -->
<script defer src="https://cdn.jsdelivr.net/npm/gsap@3/dist/gsap.min.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/gsap@3/dist/ScrollTrigger.min.js"></script>

<!-- 3. Analytics: async (non-blocking, order doesn't matter) -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXXX"></script>

<!-- 4. Heavy scripts: load after interaction -->
<script>
  // Lazy-load chat widget after user interacts with page
  let chatLoaded = false;
  function loadChat() {
    if (chatLoaded) return;
    chatLoaded = true;
    const script = document.createElement('script');
    script.src = 'https://chat-widget.example.com/widget.js';
    document.body.appendChild(script);
  }
  window.addEventListener('scroll', loadChat, { once: true, passive: true });
  window.addEventListener('click', loadChat, { once: true });
</script>
```

### Lighthouse Audit Automation

```javascript
// Run Lighthouse audit via CLI
// npm install -g lighthouse

// Basic audit
// lighthouse https://yoursite.com --output json --output html --output-path ./reports/lighthouse

// Programmatic audit
import lighthouse from 'lighthouse';
import chromeLauncher from 'chrome-launcher';

async function runLighthouseAudit(url) {
  const chrome = await chromeLauncher.launch({ chromeFlags: ['--headless'] });

  const result = await lighthouse(url, {
    port: chrome.port,
    output: 'json',
    onlyCategories: ['performance', 'accessibility', 'seo', 'best-practices'],
  });

  await chrome.kill();

  const { categories } = result.lhr;
  return {
    performance: Math.round(categories.performance.score * 100),
    accessibility: Math.round(categories.accessibility.score * 100),
    seo: Math.round(categories.seo.score * 100),
    bestPractices: Math.round(categories['best-practices'].score * 100),
  };
}
```

---

## Accessibility Compliance

### WCAG 2.2 AA Requirements for Webflow

```
Perceivable:
[ ] All images have meaningful alt text (or empty alt for decorative)
[ ] Color contrast ratio >= 4.5:1 for normal text, >= 3:1 for large text
[ ] Content is readable at 200% zoom
[ ] No information conveyed by color alone
[ ] Video has captions, audio has transcripts
[ ] Text resizes without loss of content (no overflow clipping)

Operable:
[ ] All interactive elements keyboard accessible (Tab, Enter, Escape)
[ ] Focus indicators visible on all focusable elements
[ ] No keyboard traps (user can Tab out of any component)
[ ] Skip-to-content link present (first focusable element)
[ ] Animations can be paused or disabled (prefers-reduced-motion)
[ ] Touch targets minimum 44x44px on mobile
[ ] Dropdown menus navigable with keyboard

Understandable:
[ ] Language attribute set on <html> element
[ ] Form fields have visible labels
[ ] Error messages are descriptive and associated with fields
[ ] Navigation is consistent across pages
[ ] Abbreviations are explained

Robust:
[ ] Valid HTML (no unclosed tags, duplicate IDs)
[ ] ARIA roles used correctly
[ ] Custom components have appropriate ARIA attributes
[ ] Page works without JavaScript (core content accessible)
```

### Accessibility Implementation in Webflow

```html
<!-- Skip to content link (add as first element in page-wrapper) -->
<a href="#main-content" class="skip-link">
  Skip to main content
</a>

<style>
  .skip-link {
    position: absolute;
    top: -40px;
    left: 0;
    background: var(--color-primary);
    color: white;
    padding: 8px 16px;
    z-index: 100000;
    transition: top 0.2s;
  }
  .skip-link:focus {
    top: 0;
  }
</style>

<!-- Main content landmark -->
<main id="main-content" class="main-wrapper" role="main">
  <!-- Page content -->
</main>

<!-- Accessible hamburger menu button -->
<button class="navbar_menu-button"
        aria-label="Toggle navigation menu"
        aria-expanded="false"
        aria-controls="nav-menu">
  <span class="navbar_hamburger"></span>
</button>

<nav id="nav-menu" class="navbar_menu" role="navigation" aria-label="Main navigation">
  <!-- Nav links -->
</nav>
```

```javascript
// Accessible mobile menu toggle
const menuButton = document.querySelector('.navbar_menu-button');
const navMenu = document.querySelector('.navbar_menu');

if (menuButton && navMenu) {
  menuButton.addEventListener('click', () => {
    const isExpanded = menuButton.getAttribute('aria-expanded') === 'true';
    menuButton.setAttribute('aria-expanded', !isExpanded);
    navMenu.classList.toggle('is-open');

    // Trap focus within menu when open
    if (!isExpanded) {
      const focusableElements = navMenu.querySelectorAll(
        'a, button, input, select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      if (focusableElements.length > 0) {
        focusableElements[0].focus();
      }
    }
  });

  // Close menu on Escape
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && menuButton.getAttribute('aria-expanded') === 'true') {
      menuButton.setAttribute('aria-expanded', 'false');
      navMenu.classList.remove('is-open');
      menuButton.focus();
    }
  });
}
```

### Automated Accessibility Testing

```javascript
// axe-core integration for accessibility testing
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const pages = ['/', '/about', '/blog', '/contact'];

for (const pagePath of pages) {
  test(`Accessibility audit: ${pagePath}`, async ({ page }) => {
    await page.goto(pagePath);
    await page.waitForLoadState('networkidle');

    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag22aa'])
      .exclude('.w-webflow-badge') // Exclude Webflow badge
      .analyze();

    const violations = accessibilityScanResults.violations;

    // Log violations for debugging
    if (violations.length > 0) {
      console.log(`Accessibility violations on ${pagePath}:`);
      violations.forEach(v => {
        console.log(`  [${v.impact}] ${v.id}: ${v.description}`);
        v.nodes.forEach(n => {
          console.log(`    - ${n.html}`);
        });
      });
    }

    // Fail on critical and serious violations
    const criticalViolations = violations.filter(
      v => v.impact === 'critical' || v.impact === 'serious'
    );
    expect(criticalViolations).toHaveLength(0);
  });
}
```

---

## Backup & Restore

### Webflow Backup System

Webflow automatically creates backups that can be restored from the Dashboard.

```
Backup Types:
├── Automatic: Created on every publish (last 25 retained)
├── Manual: Created from Dashboard → Backups → "Create backup"
└── Export: Full site code export (HTML, CSS, JS, assets)

What backups include:
├── Page structure and styles
├── Symbols and components
├── Interactions and animations
├── Custom code
├── Site settings
└── CMS structure (not CMS content)

What backups do NOT include:
├── CMS item data (content)
├── E-commerce orders
├── Form submissions
├── Analytics data
└── Domain/hosting settings
```

### Manual Backup Strategy

```
Pre-Launch Backup Procedure:
1. Create manual backup in Webflow Dashboard
2. Export site code (Settings → Export Code → Download .zip)
3. Export CMS data via API:

   curl -X GET "https://api.webflow.com/v2/collections/{id}/items?limit=100" \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Accept: application/json" \
     > backup-collection-name.json

4. Store exports in version-controlled repository or cloud storage
5. Document the backup with date, version, and reason
```

### CMS Data Backup Script

```javascript
// Backup all CMS collections to JSON files
const fs = require('fs');
const path = require('path');

const API_TOKEN = process.env.WEBFLOW_API_TOKEN;
const SITE_ID = process.env.WEBFLOW_SITE_ID;
const BACKUP_DIR = path.join(__dirname, 'backups', new Date().toISOString().split('T')[0]);

async function backupAllCollections() {
  // Create backup directory
  fs.mkdirSync(BACKUP_DIR, { recursive: true });

  // Get all collections
  const collectionsResponse = await fetch(
    `https://api.webflow.com/v2/sites/${SITE_ID}/collections`,
    { headers: { Authorization: `Bearer ${API_TOKEN}` } }
  );
  const { collections } = await collectionsResponse.json();

  for (const collection of collections) {
    console.log(`Backing up: ${collection.displayName}`);

    let allItems = [];
    let offset = 0;
    const limit = 100;

    // Paginate through all items
    while (true) {
      const response = await fetch(
        `https://api.webflow.com/v2/collections/${collection.id}/items?offset=${offset}&limit=${limit}`,
        { headers: { Authorization: `Bearer ${API_TOKEN}` } }
      );
      const data = await response.json();
      allItems = allItems.concat(data.items);

      if (data.items.length < limit) break;
      offset += limit;

      // Rate limit: wait 1.1 seconds between requests
      await new Promise(r => setTimeout(r, 1100));
    }

    // Save to file
    const filename = `${collection.slug}-${collection.id}.json`;
    fs.writeFileSync(
      path.join(BACKUP_DIR, filename),
      JSON.stringify({ collection: collection.displayName, items: allItems }, null, 2)
    );

    console.log(`  Saved ${allItems.length} items to ${filename}`);
  }

  console.log(`\nBackup complete: ${BACKUP_DIR}`);
}

backupAllCollections().catch(console.error);
```

---

## Pre-Launch Checklist

### Complete Pre-Launch Verification

```
Content & Design:
[ ] All placeholder text replaced with final content
[ ] All images are final (no stock photo watermarks)
[ ] Favicon uploaded (32x32 and 180x180 for Apple Touch)
[ ] Webflow badge removed or repositioned (paid plans)
[ ] 404 page designed and tested
[ ] Password page styled (if using password protection)
[ ] Form success/error messages customized
[ ] Empty states designed for CMS collection lists

Technical:
[ ] All console errors resolved (check DevTools)
[ ] All forms submit correctly and send to correct inbox
[ ] All internal links work (no broken links)
[ ] All external links open in new tab with rel="noopener"
[ ] CMS items all have required fields populated
[ ] Custom code executes without errors
[ ] Third-party integrations connected (analytics, chat, etc.)

SEO:
[ ] Every page has unique title and meta description
[ ] Open Graph tags configured on all pages
[ ] Sitemap.xml generated and accessible
[ ] robots.txt allows crawling (no accidental noindex)
[ ] 301 redirects configured for old URLs
[ ] Google Search Console connected
[ ] Structured data validates (schema.org)

Performance:
[ ] Lighthouse Performance score >= 90
[ ] LCP under 2.5 seconds
[ ] CLS under 0.1
[ ] Images optimized and lazy-loaded
[ ] Fonts preloaded
[ ] Unused CSS/JS minimized

Accessibility:
[ ] axe-core reports 0 critical violations
[ ] Keyboard navigation works throughout
[ ] Color contrast passes WCAG AA
[ ] Focus indicators visible
[ ] Screen reader tested (VoiceOver or NVDA)
[ ] Skip-to-content link present

Domain & Hosting:
[ ] Custom domain connected
[ ] SSL certificate active (HTTPS)
[ ] WWW/non-WWW redirect configured
[ ] DNS propagation complete
[ ] CDN configured (Webflow handles this)

Monitoring:
[ ] Uptime monitoring configured (UptimeRobot, Pingdom)
[ ] Google Analytics / GA4 tracking verified
[ ] Google Search Console submitted
[ ] Error tracking configured (Sentry, if using custom code)
[ ] Backup created before launch
```

---

## Monitoring & Maintenance

### Post-Launch Monitoring

```
Weekly Checks:
[ ] Uptime report (target: 99.9%)
[ ] Form submissions arriving correctly
[ ] CMS content publishing correctly
[ ] No new console errors
[ ] Analytics data flowing

Monthly Checks:
[ ] Core Web Vitals in Search Console
[ ] Broken link scan
[ ] SSL certificate expiry (auto-renewed by Webflow, but verify)
[ ] Third-party script updates
[ ] Lighthouse audit (compare to baseline)

Quarterly Checks:
[ ] Full accessibility audit
[ ] SEO performance review
[ ] CMS content audit (stale content, broken references)
[ ] Browser support review (drop old versions, add new)
[ ] Backup verification (test restore process)
```

### Automated Monitoring Script

```javascript
// Monthly automated health check
async function healthCheck(siteUrl) {
  const results = {
    timestamp: new Date().toISOString(),
    url: siteUrl,
    checks: {},
  };

  // Check site is up
  try {
    const response = await fetch(siteUrl);
    results.checks.uptime = {
      status: response.ok ? 'pass' : 'fail',
      statusCode: response.status,
    };
  } catch (error) {
    results.checks.uptime = { status: 'fail', error: error.message };
  }

  // Check SSL
  try {
    const url = new URL(siteUrl);
    results.checks.ssl = {
      status: url.protocol === 'https:' ? 'pass' : 'fail',
    };
  } catch (error) {
    results.checks.ssl = { status: 'fail' };
  }

  // Check sitemap
  try {
    const sitemapResponse = await fetch(`${siteUrl}/sitemap.xml`);
    results.checks.sitemap = {
      status: sitemapResponse.ok ? 'pass' : 'fail',
    };
  } catch (error) {
    results.checks.sitemap = { status: 'fail' };
  }

  // Check robots.txt
  try {
    const robotsResponse = await fetch(`${siteUrl}/robots.txt`);
    const robotsText = await robotsResponse.text();
    const hasDisallowAll = robotsText.includes('Disallow: /');
    results.checks.robots = {
      status: robotsResponse.ok && !hasDisallowAll ? 'pass' : 'warn',
      note: hasDisallowAll ? 'robots.txt blocks all crawling' : 'OK',
    };
  } catch (error) {
    results.checks.robots = { status: 'fail' };
  }

  return results;
}
```

---

## Best Practices

1. **Test on staging before every production publish** -- never push untested changes live
2. **Create a backup before every major change** -- especially before redesigns or CMS structure changes
3. **Use a QA spreadsheet** -- track issues per page per browser per device with status and assignee
4. **Automate visual regression testing** -- use Playwright screenshots to catch unintended layout changes
5. **Run Lighthouse monthly** -- performance degrades over time as content and scripts are added
6. **Test with real content** -- 20+ CMS items per collection reveals layout issues that 3 items do not
7. **Verify accessibility with axe-core** -- automated scanning catches 30-40% of issues; manual testing catches the rest
8. **Check Core Web Vitals in Search Console** -- lab data (Lighthouse) and field data (CrUX) often differ
9. **Document all redirects** -- maintain a spreadsheet mapping old URLs to new URLs for migration
10. **Test forms end-to-end** -- verify the email arrives, the data is correct, and the success message displays

---

## Anti-Patterns

- Publishing to production without testing on staging first
- Skipping cross-browser testing on Safari (the second-largest browser)
- Testing only on desktop and assuming mobile "probably works"
- Relying solely on Lighthouse lab scores without checking real-user metrics in CrUX
- Not having a 404 page or leaving the default Webflow 404
- Ignoring console errors as "just warnings"
- Testing with 2-3 CMS items instead of 20+ (hides overflow and layout bugs)
- Not setting up 301 redirects before relaunch (destroys SEO equity)
- Skipping accessibility testing entirely because "we will do it later"
- Not creating backups before major redesigns or CMS restructuring
- Testing only on fast WiFi and ignoring 3G/4G performance
- Using "click here" as link text instead of descriptive anchor text

---

## Sources & References

- [Webflow University: Publishing & Hosting](https://university.webflow.com/lesson/publishing-your-site)
- [Google Core Web Vitals Documentation](https://web.dev/vitals/)
- [WCAG 2.2 Quick Reference](https://www.w3.org/WAI/WCAG22/quickref/)
- [axe-core Accessibility Testing](https://github.com/dequelabs/axe-core)
- [Playwright Cross-Browser Testing](https://playwright.dev/docs/browsers)
- [Google Lighthouse Documentation](https://developer.chrome.com/docs/lighthouse/)
- [Webflow SEO Best Practices](https://university.webflow.com/lesson/seo-title-and-meta-description)
- [Google Search Console Help](https://support.google.com/webmasters/)
- [Schema.org Structured Data Reference](https://schema.org/)
