---
name: webflow-interactions
description: Webflow interactions — IX2 animations, scroll-based animations, Lottie integration, custom code injection (JS/CSS), Finsweet attributes, GSAP integration, page transitions
---

# Webflow Interactions & Custom Code

Production-ready interaction and animation patterns for Webflow 2026. Covers IX2 interaction system, scroll-triggered animations, Lottie integration, custom JavaScript and CSS injection, Finsweet attribute patterns, GSAP integration for advanced animations, page transitions, and performance optimization for animated sites.

## Table of Contents

1. [IX2 Interaction System](#ix2-interaction-system)
2. [Scroll-Based Animations](#scroll-based-animations)
3. [Page Load & Click Animations](#page-load--click-animations)
4. [Lottie Animations](#lottie-animations)
5. [Custom Code Injection](#custom-code-injection)
6. [Finsweet Attribute Patterns](#finsweet-attribute-patterns)
7. [GSAP Integration](#gsap-integration)
8. [Page Transitions](#page-transitions)
9. [Advanced Animation Patterns](#advanced-animation-patterns)
10. [Performance Optimization](#performance-optimization)
11. [Best Practices](#best-practices)
12. [Anti-Patterns](#anti-patterns)

---

## IX2 Interaction System

### Understanding IX2 Architecture

Webflow's Interactions 2.0 (IX2) is a visual animation engine that generates optimized CSS transforms and opacity transitions. Animations are defined as triggers + timelines.

**Trigger types:**
- **Element triggers**: Mouse hover, click, scroll into view, scroll while in view
- **Page triggers**: Page load, page scroll, mouse move in viewport
- **Device triggers**: Orientation change (limited)

**Animatable properties:**
- Transform: move, scale, rotate, skew
- Opacity
- Size (width, height)
- Background color
- Border color, width, radius
- Box shadow
- Filter (blur, brightness, contrast, etc.)
- Typography (font size, letter spacing, line height)

### IX2 Trigger Configuration

```
Interaction: "Card Hover Effect"
├── Trigger: Mouse Hover (on element: .card_component)
│   ├── Affect: "Interaction trigger" (only the hovered card)
│   ├── On Hover:
│   │   ├── Action 1: Move Y → -8px (duration: 300ms, ease: ease-out)
│   │   ├── Action 2: Box Shadow → 0 12px 24px rgba(0,0,0,0.12) (300ms)
│   │   └── Action 3: Scale → 1.02 (300ms, ease: ease-out)
│   └── On Hover Out:
│       ├── Action 1: Move Y → 0px (200ms, ease: ease-in)
│       ├── Action 2: Box Shadow → 0 4px 6px rgba(0,0,0,0.07) (200ms)
│       └── Action 3: Scale → 1 (200ms, ease: ease-in)
```

### Staggered Animations

Staggering creates a cascade effect where child elements animate with a delay between each:

```
Interaction: "Grid Items Stagger In"
├── Trigger: Scroll Into View (on element: .grid_component)
│   ├── Offset: 20% from bottom
│   └── On Scroll Into View:
│       └── Affect: Children → .grid_item (class)
│           ├── Stagger: 100ms between each child
│           ├── Action 1: Opacity 0 → 1 (500ms, ease: ease-out)
│           ├── Action 2: Move Y 40px → 0px (500ms, ease: ease-out)
│           └── Action 3: Scale 0.95 → 1 (500ms, ease: ease-out)
```

**Stagger configuration:**
- Set the trigger on the PARENT element (the grid/list container)
- Target the CHILDREN by class name
- Stagger delay applies between each child element
- All children animate with the same timeline, just offset in time

### Easing Functions in IX2

| Easing | Use Case | Feel |
|---|---|---|
| Ease | General purpose | Starts slow, speeds up, slows down |
| Ease-in | Exit animations | Starts slow, accelerates out |
| Ease-out | Enter animations | Starts fast, decelerates in |
| Ease-in-out | Continuous motion | Symmetric acceleration |
| Linear | Progress bars, counting | Constant speed |
| Custom cubic-bezier | Brand-specific | Fine-tuned control |

---

## Scroll-Based Animations

### Scroll Into View

The most common scroll animation triggers content to animate when it enters the viewport.

```
Interaction: "Fade Up On Scroll"
├── Trigger: Scroll Into View
│   ├── Element: .animate-on-scroll (applied to any element)
│   ├── Offset: 15% from bottom of viewport
│   ├── Once: Yes (animate only the first time)
│   └── Timeline:
│       ├── Start State (at trigger):
│       │   ├── Opacity: 0
│       │   └── Move Y: 30px
│       └── End State (300ms, ease-out):
│           ├── Opacity: 1
│           └── Move Y: 0px
```

### Scroll While In View (Parallax)

This trigger maps animation progress to scroll position, creating parallax and scroll-linked effects.

```
Interaction: "Parallax Background"
├── Trigger: While Scrolling In View
│   ├── Element: .parallax_image
│   ├── Scroll range: 0% (enters viewport) → 100% (exits viewport)
│   └── Timeline:
│       ├── At 0%:  Move Y → -100px
│       ├── At 50%: Move Y → 0px
│       └── At 100%: Move Y → 100px

Interaction: "Progress Bar on Scroll"
├── Trigger: While Scrolling In View
│   ├── Element: .progress_bar-wrapper
│   └── Timeline:
│       ├── At 0%:   Width → 0%
│       ├── At 100%: Width → 100%
```

### Sticky Scroll Reveal

A common pattern where content sections reveal as the user scrolls through a sticky container:

```
Interaction: "Sticky Feature Reveal"
├── Trigger: While Scrolling In View
│   ├── Element: .sticky-reveal_wrapper (set to 300vh height)
│   ├── Child: .sticky-reveal_content (position: sticky, top: 0)
│   └── Timeline:
│       ├── At 0%:
│       │   ├── .feature-1: Opacity 1
│       │   └── .feature-2: Opacity 0, Move Y 40px
│       ├── At 33%:
│       │   ├── .feature-1: Opacity 0
│       │   └── .feature-2: Opacity 1, Move Y 0px
│       ├── At 66%:
│       │   ├── .feature-2: Opacity 0
│       │   └── .feature-3: Opacity 1, Move Y 0px
│       └── At 100%:
│           └── .feature-3: Opacity 1
```

```css
/* Supporting CSS for sticky scroll reveal */
.sticky-reveal_wrapper {
  height: 300vh;
  position: relative;
}

.sticky-reveal_content {
  position: sticky;
  top: 0;
  height: 100vh;
  display: flex;
  align-items: center;
  overflow: hidden;
}

.sticky-reveal_feature {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
}
```

---

## Page Load & Click Animations

### Page Load Sequence

A well-crafted page load animation creates a professional first impression.

```
Interaction: "Page Load Sequence"
├── Trigger: Page Load (starts after page finishes loading)
│   └── Timeline:
│       ├── 0ms: Set initial states
│       │   ├── .navbar_component: Opacity 0, Move Y -20px
│       │   ├── .hero_heading: Opacity 0, Move Y 30px
│       │   ├── .hero_text: Opacity 0, Move Y 20px
│       │   └── .hero_button: Opacity 0, Scale 0.9
│       ├── 200ms: Navbar enters
│       │   └── .navbar_component: Opacity 1, Move Y 0px (400ms, ease-out)
│       ├── 400ms: Heading enters
│       │   └── .hero_heading: Opacity 1, Move Y 0px (500ms, ease-out)
│       ├── 600ms: Text enters
│       │   └── .hero_text: Opacity 1, Move Y 0px (400ms, ease-out)
│       └── 800ms: Button enters
│           └── .hero_button: Opacity 1, Scale 1 (400ms, ease-out)
```

### Click/Tap Interactions

```
Interaction: "FAQ Accordion Toggle"
├── Trigger: Click (on element: .faq_question)
│   ├── Affect: Parent → .faq_item
│   ├── First Click (open):
│   │   ├── .faq_answer: Height 0px → Auto (300ms, ease-out)
│   │   ├── .faq_answer: Opacity 0 → 1 (200ms, ease-out, 100ms delay)
│   │   └── .faq_icon: Rotate 0deg → 45deg (200ms, ease-out)
│   └── Second Click (close):
│       ├── .faq_answer: Height Auto → 0px (250ms, ease-in)
│       ├── .faq_answer: Opacity 1 → 0 (150ms, ease-in)
│       └── .faq_icon: Rotate 45deg → 0deg (200ms, ease-in)
```

```html
<!-- FAQ accordion structure -->
<div class="faq_component">
  <div class="faq_item">
    <div class="faq_question">
      <h3 class="faq_question-text heading-style-h5">How does pricing work?</h3>
      <div class="faq_icon">
        <svg width="24" height="24">
          <line x1="12" y1="4" x2="12" y2="20" stroke="currentColor" stroke-width="2"/>
          <line x1="4" y1="12" x2="20" y2="12" stroke="currentColor" stroke-width="2"/>
        </svg>
      </div>
    </div>
    <div class="faq_answer" style="height: 0px; overflow: hidden;">
      <div class="faq_answer-content">
        <p class="text-size-regular">Our pricing is based on...</p>
      </div>
    </div>
  </div>
</div>
```

---

## Lottie Animations

### Lottie in Webflow

Lottie renders JSON-based animations exported from After Effects (via Bodymovin), Figma, or online tools. Webflow has native Lottie support.

**When to use Lottie:**
- Complex vector animations (icons, illustrations, loading states)
- Scroll-linked storytelling animations
- Animated logos or hero illustrations
- Micro-interactions too complex for IX2

**When NOT to use Lottie:**
- Simple fade/slide animations (use IX2)
- Full-screen video (use video element)
- Animations with raster images (Lottie is vector-only)

### Adding Lottie to Webflow

```html
<!-- Lottie element structure in Webflow -->
<div class="lottie_component"
     data-w-id="lottie-unique-id"
     data-animation-type="lottie"
     data-src="/documents/hero-animation.json"
     data-loop="1"
     data-direction="1"
     data-autoplay="1"
     data-is-ix2-target="0"
     data-renderer="svg"
     data-duration="0">
</div>
```

### Scroll-Controlled Lottie

Map Lottie animation progress to scroll position for scroll-storytelling:

```
Interaction: "Lottie Scroll Storytelling"
├── Trigger: While Scrolling In View
│   ├── Element: .lottie-scroll_wrapper (height: 400vh)
│   └── Timeline:
│       ├── At 0%:   Lottie frame → 0%
│       ├── At 25%:  Lottie frame → 25%
│       ├── At 50%:  Lottie frame → 50%
│       ├── At 75%:  Lottie frame → 75%
│       └── At 100%: Lottie frame → 100%
```

```css
/* Lottie scroll container */
.lottie-scroll_wrapper {
  height: 400vh;
  position: relative;
}

.lottie-scroll_sticky {
  position: sticky;
  top: 0;
  height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
}

.lottie-scroll_animation {
  width: 100%;
  max-width: 800px;
}
```

### Lottie Performance Guidelines

- Keep Lottie JSON files under 200KB for optimal loading
- Use the `svg` renderer for crisp scaling (default)
- Avoid Lottie files with many layers (over 50 layers causes frame drops)
- Compress Lottie JSON with tools like lottie-compress or LottieFiles optimizer
- Do not autoplay Lottie animations that are below the fold
- Preload critical Lottie files in the `<head>` tag

---

## Custom Code Injection

### Code Injection Points

Webflow provides four injection points for custom code:

1. **Site-wide `<head>`**: Global CSS, fonts, analytics, meta tags
2. **Site-wide `</body>`**: Global JavaScript, third-party scripts
3. **Per-page `<head>`**: Page-specific CSS, structured data
4. **Per-page `</body>`**: Page-specific JavaScript

### Global CSS Custom Code

```html
<!-- Site Settings → Custom Code → Head Code -->
<style>
  /* Smooth scrolling for anchor links */
  html {
    scroll-behavior: smooth;
  }

  /* Custom scrollbar */
  ::-webkit-scrollbar {
    width: 8px;
  }
  ::-webkit-scrollbar-track {
    background: var(--color-bg-secondary);
  }
  ::-webkit-scrollbar-thumb {
    background: var(--color-text-secondary);
    border-radius: var(--radius-full);
  }

  /* Focus visible styles for accessibility */
  :focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  /* Rich text content styling */
  .w-richtext h2 {
    margin-top: 2.5rem;
    margin-bottom: 1rem;
  }
  .w-richtext h3 {
    margin-top: 2rem;
    margin-bottom: 0.75rem;
  }
  .w-richtext p + p {
    margin-top: 1.25rem;
  }
  .w-richtext img {
    border-radius: var(--radius-lg);
    margin-top: 2rem;
    margin-bottom: 2rem;
  }
  .w-richtext blockquote {
    border-left: 4px solid var(--color-primary);
    padding-left: 1.5rem;
    margin: 2rem 0;
    font-style: italic;
    color: var(--color-text-secondary);
  }

  /* CMS empty field handling */
  .w-condition-invisible {
    display: none !important;
  }
</style>
```

### Global JavaScript Custom Code

```html
<!-- Site Settings → Custom Code → Footer Code -->
<script>
  // Wait for DOM ready
  document.addEventListener('DOMContentLoaded', function() {

    // Dynamic copyright year
    const yearElements = document.querySelectorAll('[data-element="year"]');
    yearElements.forEach(el => {
      el.textContent = new Date().getFullYear();
    });

    // External links open in new tab
    document.querySelectorAll('a[href^="http"]').forEach(link => {
      if (!link.hostname.includes(window.location.hostname)) {
        link.setAttribute('target', '_blank');
        link.setAttribute('rel', 'noopener noreferrer');
      }
    });

    // Smooth scroll to anchor with offset for fixed navbar
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
      anchor.addEventListener('click', function(e) {
        const targetId = this.getAttribute('href').slice(1);
        const target = document.getElementById(targetId);
        if (target) {
          e.preventDefault();
          const navbarHeight = document.querySelector('.navbar_component')?.offsetHeight || 0;
          const targetPosition = target.getBoundingClientRect().top + window.scrollY - navbarHeight - 20;
          window.scrollTo({ top: targetPosition, behavior: 'smooth' });
        }
      });
    });

    // Navbar background on scroll
    const navbar = document.querySelector('.navbar_component');
    if (navbar) {
      const scrollThreshold = 50;
      const handleScroll = () => {
        if (window.scrollY > scrollThreshold) {
          navbar.classList.add('is-scrolled');
        } else {
          navbar.classList.remove('is-scrolled');
        }
      };
      window.addEventListener('scroll', handleScroll, { passive: true });
      handleScroll(); // Initial check
    }

  });
</script>
```

### Page-Specific Structured Data

```html
<!-- Page Settings → Custom Code → Head Code (on blog template page) -->
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "{{wf {&quot;path&quot;:&quot;name&quot;} }}",
  "description": "{{wf {&quot;path&quot;:&quot;post-summary&quot;} }}",
  "image": "{{wf {&quot;path&quot;:&quot;featured-image.url&quot;} }}",
  "datePublished": "{{wf {&quot;path&quot;:&quot;published-date&quot;} }}",
  "author": {
    "@type": "Person",
    "name": "{{wf {&quot;path&quot;:&quot;author.name&quot;} }}"
  },
  "publisher": {
    "@type": "Organization",
    "name": "Your Company",
    "logo": {
      "@type": "ImageObject",
      "url": "https://yoursite.com/logo.png"
    }
  }
}
</script>
```

---

## Finsweet Attribute Patterns

### Finsweet Attributes Library

Finsweet Attributes extend Webflow's native functionality without writing custom code. Each attribute is a self-contained feature.

**Most-used attributes (2026):**

| Attribute | Purpose | Script |
|---|---|---|
| CMS Filter | Filter collection lists | `@finsweet/attributes-cmsfilter` |
| CMS Load | Pagination / infinite scroll | `@finsweet/attributes-cmsload` |
| CMS Sort | Sort collection lists | `@finsweet/attributes-cmssort` |
| CMS Nest | Nested CMS references | `@finsweet/attributes-cmsnest` |
| CMS Combine | Merge multiple collection lists | `@finsweet/attributes-cmscombine` |
| Mirror | Mirror click/hover between elements | `@finsweet/attributes-mirror` |
| Table of Contents | Auto-generate TOC from rich text | `@finsweet/attributes-toc` |
| Accordion | Accessible accordion component | `@finsweet/attributes-accordion` |
| Tabs | Enhanced tab component | `@finsweet/attributes-tabs` |
| Slider | Enhanced slider/carousel | `@finsweet/attributes-slider` |
| Copy to Clipboard | Copy text on click | `@finsweet/attributes-copyclip` |

### Finsweet CMS Nest

CMS Nest solves the limitation of Webflow only supporting one level of reference nesting. It allows deep nesting of CMS references.

```html
<!-- Outer collection list: Blog Posts -->
<div class="w-dyn-list" fs-cmsnest-element="list">
  <div role="list" class="w-dyn-items">
    <div role="listitem" class="w-dyn-item">
      <h3>{post-title}</h3>
      <p>By: {author.name}</p>

      <!-- Inner collection target: Author's other posts -->
      <!-- This targets the "all blog posts by this author" collection -->
      <div fs-cmsnest-element="target"
           fs-cmsnest-collection="blog-posts"
           fs-cmsnest-filter-field="author"
           fs-cmsnest-filter-value="{author.slug}">
        <!-- Nested items render here -->
      </div>
    </div>
  </div>
</div>

<!-- Hidden source collection list (rendered but hidden) -->
<div class="w-dyn-list"
     fs-cmsnest-element="source"
     fs-cmsnest-collection="blog-posts"
     style="display: none;">
  <div role="list" class="w-dyn-items">
    <div role="listitem" class="w-dyn-item">
      <div fs-cmsnest-element="item">
        <a href="/blog/{slug}" class="related-post_link">
          <span fs-cmsnest-field="author">{author.slug}</span>
          <span>{title}</span>
        </a>
      </div>
    </div>
  </div>
</div>
```

### Finsweet Accordion Pattern

```html
<!-- Accessible accordion with Finsweet -->
<div class="accordion_component" fs-accordion-element="group">
  <div class="accordion_item" fs-accordion-element="accordion">
    <button class="accordion_trigger" fs-accordion-element="trigger">
      <span class="accordion_title">Question One</span>
      <div class="accordion_icon" fs-accordion-element="arrow">
        <svg width="20" height="20" viewBox="0 0 20 20">
          <polyline points="5 8 10 13 15 8" fill="none"
                    stroke="currentColor" stroke-width="2"/>
        </svg>
      </div>
    </button>
    <div class="accordion_content" fs-accordion-element="content">
      <div class="accordion_body">
        <p>Answer to question one...</p>
      </div>
    </div>
  </div>
  <!-- Repeat for each item -->
</div>

<!-- Finsweet accordion settings via attributes -->
<script>
  // Configuration via data attributes (no JS needed)
  // fs-accordion-initial="open" → opens first item by default
  // fs-accordion-simultaneous="true" → allow multiple open
  // fs-accordion-duration="300" → animation duration in ms
</script>
```

### Including Finsweet Scripts

```html
<!-- Add before </body> in site-wide custom code -->
<!-- IMPORTANT: Load only the attributes you actually use -->
<script defer src="https://cdn.jsdelivr.net/npm/@finsweet/attributes-accordion@1/accordion.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/@finsweet/attributes-cmsfilter@1/cmsfilter.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/@finsweet/attributes-cmsload@1/cmsload.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/@finsweet/attributes-cmsnest@1/cmsnest.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/@finsweet/attributes-toc@1/toc.js"></script>
```

---

## GSAP Integration

### When to Use GSAP vs IX2

**Use IX2 for:**
- Simple hover, click, and scroll animations
- Animations that non-developers need to edit
- Standard fade, slide, scale transitions
- Staggered grid reveals

**Use GSAP for:**
- Text splitting and character animations
- Complex SVG path animations
- Physics-based animations (spring, bounce)
- Scroll-linked timelines with scrub
- Animations that need to chain programmatically
- Performance-critical animations on many elements

### GSAP Setup in Webflow

```html
<!-- Before </body> in site-wide custom code -->
<script src="https://cdn.jsdelivr.net/npm/gsap@3/dist/gsap.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/gsap@3/dist/ScrollTrigger.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/gsap@3/dist/SplitText.min.js"></script>

<script>
  gsap.registerPlugin(ScrollTrigger, SplitText);
</script>
```

### GSAP ScrollTrigger Patterns

```javascript
// Fade-up on scroll (replaces IX2 scroll-into-view)
gsap.utils.toArray('.animate-on-scroll').forEach(element => {
  gsap.from(element, {
    y: 40,
    opacity: 0,
    duration: 0.8,
    ease: 'power2.out',
    scrollTrigger: {
      trigger: element,
      start: 'top 85%',
      toggleActions: 'play none none none',
    },
  });
});

// Horizontal scroll section
const horizontalSection = document.querySelector('.horizontal-scroll_track');
if (horizontalSection) {
  const panels = gsap.utils.toArray('.horizontal-scroll_panel');
  gsap.to(panels, {
    xPercent: -100 * (panels.length - 1),
    ease: 'none',
    scrollTrigger: {
      trigger: '.horizontal-scroll_wrapper',
      pin: true,
      scrub: 1,
      snap: 1 / (panels.length - 1),
      end: () => `+=${horizontalSection.offsetWidth}`,
    },
  });
}

// Parallax with GSAP (smoother than IX2)
gsap.utils.toArray('.parallax_image').forEach(image => {
  gsap.to(image, {
    yPercent: -30,
    ease: 'none',
    scrollTrigger: {
      trigger: image.closest('.parallax_wrapper'),
      start: 'top bottom',
      end: 'bottom top',
      scrub: true,
    },
  });
});
```

### Text Animation with SplitText

```javascript
// Character-by-character reveal
document.querySelectorAll('.text-reveal_heading').forEach(heading => {
  const split = new SplitText(heading, { type: 'chars,words,lines' });

  gsap.from(split.chars, {
    opacity: 0,
    y: 20,
    rotateX: -90,
    stagger: 0.02,
    duration: 0.6,
    ease: 'back.out(1.7)',
    scrollTrigger: {
      trigger: heading,
      start: 'top 80%',
      toggleActions: 'play none none none',
    },
  });
});

// Line-by-line reveal for paragraphs
document.querySelectorAll('.text-reveal_paragraph').forEach(paragraph => {
  const split = new SplitText(paragraph, {
    type: 'lines',
    linesClass: 'split-line',
  });

  // Wrap each line in an overflow container
  split.lines.forEach(line => {
    const wrapper = document.createElement('div');
    wrapper.style.overflow = 'hidden';
    line.parentNode.insertBefore(wrapper, line);
    wrapper.appendChild(line);
  });

  gsap.from(split.lines, {
    y: '100%',
    opacity: 0,
    stagger: 0.1,
    duration: 0.8,
    ease: 'power3.out',
    scrollTrigger: {
      trigger: paragraph,
      start: 'top 85%',
    },
  });
});
```

---

## Page Transitions

### Barba.js Integration

For smooth page transitions in Webflow, integrate Barba.js with GSAP:

```html
<!-- Required: wrap page content in a Barba container -->
<!-- In Webflow, set data attributes on the page wrapper -->
<div data-barba="wrapper">
  <main data-barba="container" data-barba-namespace="home" class="main-wrapper">
    <!-- Page content -->
  </main>
</div>
```

```javascript
// Page transition setup with Barba + GSAP
import barba from '@barba/core';

barba.init({
  transitions: [{
    name: 'fade',
    leave(data) {
      return gsap.to(data.current.container, {
        opacity: 0,
        y: -20,
        duration: 0.4,
        ease: 'power2.in',
      });
    },
    enter(data) {
      window.scrollTo(0, 0);
      return gsap.from(data.next.container, {
        opacity: 0,
        y: 20,
        duration: 0.5,
        ease: 'power2.out',
      });
    },
  }],
});

// Re-initialize Webflow interactions after page transition
barba.hooks.after(() => {
  Webflow.destroy();
  Webflow.ready();
  Webflow.require('ix2').init();
});
```

### Native View Transitions API (2026)

Modern browsers now support the View Transitions API natively:

```javascript
// Simple page transitions using View Transitions API
document.querySelectorAll('a[href]').forEach(link => {
  if (link.hostname === window.location.hostname) {
    link.addEventListener('click', async (e) => {
      if (!document.startViewTransition) return; // Fallback: normal navigation

      e.preventDefault();
      const href = link.getAttribute('href');

      document.startViewTransition(async () => {
        const response = await fetch(href);
        const html = await response.text();
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        document.querySelector('.main-wrapper').innerHTML =
          doc.querySelector('.main-wrapper').innerHTML;
        history.pushState(null, '', href);
      });
    });
  }
});
```

```css
/* View Transitions CSS */
::view-transition-old(root) {
  animation: fade-out 0.3s ease forwards;
}
::view-transition-new(root) {
  animation: fade-in 0.3s ease forwards;
}

@keyframes fade-out {
  from { opacity: 1; transform: translateY(0); }
  to { opacity: 0; transform: translateY(-10px); }
}
@keyframes fade-in {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}
```

---

## Advanced Animation Patterns

### Magnetic Cursor Effect

```javascript
// Magnetic button that follows cursor within range
document.querySelectorAll('[data-magnetic]').forEach(element => {
  const strength = parseFloat(element.dataset.magnetic) || 0.3;

  element.addEventListener('mousemove', (e) => {
    const rect = element.getBoundingClientRect();
    const x = e.clientX - rect.left - rect.width / 2;
    const y = e.clientY - rect.top - rect.height / 2;

    gsap.to(element, {
      x: x * strength,
      y: y * strength,
      duration: 0.4,
      ease: 'power2.out',
    });
  });

  element.addEventListener('mouseleave', () => {
    gsap.to(element, {
      x: 0,
      y: 0,
      duration: 0.6,
      ease: 'elastic.out(1, 0.3)',
    });
  });
});
```

### Custom Cursor

```javascript
// Custom cursor following mouse
const cursor = document.querySelector('.custom-cursor');
const cursorDot = document.querySelector('.custom-cursor_dot');

if (cursor && cursorDot) {
  document.addEventListener('mousemove', (e) => {
    gsap.to(cursor, {
      x: e.clientX,
      y: e.clientY,
      duration: 0.5,
      ease: 'power2.out',
    });
    gsap.to(cursorDot, {
      x: e.clientX,
      y: e.clientY,
      duration: 0.1,
    });
  });

  // Enlarge cursor on interactive elements
  document.querySelectorAll('a, button, [role="button"]').forEach(el => {
    el.addEventListener('mouseenter', () => {
      gsap.to(cursor, { scale: 2, duration: 0.3 });
    });
    el.addEventListener('mouseleave', () => {
      gsap.to(cursor, { scale: 1, duration: 0.3 });
    });
  });
}
```

```css
/* Custom cursor styles */
.custom-cursor {
  position: fixed;
  top: 0;
  left: 0;
  width: 40px;
  height: 40px;
  border: 2px solid var(--color-primary);
  border-radius: 50%;
  pointer-events: none;
  z-index: 9999;
  transform: translate(-50%, -50%);
  mix-blend-mode: difference;
}

.custom-cursor_dot {
  position: fixed;
  top: 0;
  left: 0;
  width: 6px;
  height: 6px;
  background: var(--color-primary);
  border-radius: 50%;
  pointer-events: none;
  z-index: 9999;
  transform: translate(-50%, -50%);
}

/* Hide custom cursor on touch devices */
@media (pointer: coarse) {
  .custom-cursor,
  .custom-cursor_dot {
    display: none;
  }
}
```

---

## Performance Optimization

### Animation Performance Rules

1. **Only animate `transform` and `opacity`** -- these are GPU-composited and avoid layout recalculation
2. **Avoid animating `width`, `height`, `top`, `left`** -- these trigger layout reflow
3. **Use `will-change` sparingly** -- only on elements about to animate, remove after
4. **Limit simultaneous animations** -- no more than 10-15 elements animating at once
5. **Use `requestAnimationFrame`** for custom scroll handlers
6. **Debounce resize handlers** -- recalculate scroll positions on resize with a 200ms debounce

### Performance Monitoring

```javascript
// Monitor animation frame rate
let lastTime = performance.now();
let frameCount = 0;

function checkFPS() {
  const now = performance.now();
  frameCount++;

  if (now - lastTime >= 1000) {
    const fps = Math.round(frameCount * 1000 / (now - lastTime));
    if (fps < 30) {
      console.warn(`Low FPS detected: ${fps}fps. Reduce animation complexity.`);
    }
    frameCount = 0;
    lastTime = now;
  }

  requestAnimationFrame(checkFPS);
}

if (process.env.NODE_ENV === 'development') {
  requestAnimationFrame(checkFPS);
}
```

### Reduced Motion Support

```javascript
// Respect user's reduced motion preference
const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

if (prefersReducedMotion.matches) {
  // Disable GSAP ScrollTrigger animations
  gsap.globalTimeline.timeScale(100); // Instant transitions
  ScrollTrigger.getAll().forEach(trigger => trigger.kill());

  // Disable Webflow IX2
  // (handled via CSS below)
}
```

```css
/* Disable all animations for reduced motion users */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

---

## Best Practices

1. **Use IX2 for simple animations, GSAP for complex ones** -- do not mix unnecessarily; pick the right tool for each job
2. **Animate only transform and opacity** -- all other CSS properties trigger expensive layout recalculations
3. **Stagger intelligently** -- 50-150ms between items creates a natural cascade; more feels sluggish
4. **Set initial states explicitly** -- never rely on the animation "just working" without defined start states
5. **Test reduced motion** -- always provide a meaningful experience when animations are disabled
6. **Load scripts with `defer`** -- all animation libraries should load after the page content
7. **Use Finsweet attributes over custom code** -- they handle edge cases (empty states, loading, accessibility) that custom code often misses
8. **Keep Lottie files small** -- compress and optimize before uploading; aim for under 200KB
9. **Limit page load animations to the hero** -- users came for content, not a loading show
10. **Document interactions** -- maintain a spreadsheet of all IX2 interactions with trigger, target, and purpose

---

## Anti-Patterns

- Animating `width`, `height`, `margin`, or `padding` instead of using transforms
- Using IX2 for animations that need programmatic control (conditional logic, chaining, user input)
- Loading GSAP, Barba, Lottie, and every Finsweet attribute on every page regardless of need
- Creating page load animations longer than 2 seconds (users will leave)
- Not testing animations on mobile devices where GPU resources are limited
- Using `!important` to override IX2 styles instead of fixing the interaction configuration
- Nesting multiple scroll-triggered animations within the same scroll range (creates fighting animations)
- Relying on hover animations for critical UI feedback (hover does not exist on touch devices)
- Using setInterval for animation loops instead of requestAnimationFrame
- Not providing an `is-loaded` class toggle to prevent FOUC (Flash of Unstyled Content) during page load animations

---

## Sources & References

- [Webflow Interactions & Animations Guide](https://university.webflow.com/lesson/intro-to-interactions)
- [GSAP 3 Documentation](https://gsap.com/docs/v3/)
- [GSAP ScrollTrigger Plugin](https://gsap.com/docs/v3/Plugins/ScrollTrigger/)
- [Finsweet Attributes Documentation](https://finsweet.com/attributes)
- [Lottie Web Player Documentation](https://airbnb.io/lottie/)
- [Webflow Lottie Integration Guide](https://university.webflow.com/lesson/lottie-animations)
- [MDN View Transitions API](https://developer.mozilla.org/en-US/docs/Web/API/View_Transitions_API)
- [Barba.js Page Transitions](https://barba.js.org/)
- [Web Animations Performance Best Practices](https://web.dev/animations-guide/)
