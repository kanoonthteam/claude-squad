---
name: webflow-cms
description: Webflow CMS — collection design, dynamic content, CMS API, reference fields, multi-reference, collection templates, pagination, filtering, E-commerce collections
---

# Webflow CMS & Dynamic Content

Production-ready CMS patterns for Webflow 2026. Covers collection schema design, dynamic content binding, reference and multi-reference fields, collection list templates, pagination, filtering with Finsweet CMS attributes, the Webflow CMS API (v2), E-commerce product collections, and localization strategies.

## Table of Contents

1. [CMS Architecture Principles](#cms-architecture-principles)
2. [Collection Schema Design](#collection-schema-design)
3. [Reference & Multi-Reference Fields](#reference--multi-reference-fields)
4. [Collection Templates & Dynamic Pages](#collection-templates--dynamic-pages)
5. [Collection Lists & Nested Lists](#collection-lists--nested-lists)
6. [Pagination Patterns](#pagination-patterns)
7. [Filtering & Sorting with Finsweet](#filtering--sorting-with-finsweet)
8. [Webflow CMS API v2](#webflow-cms-api-v2)
9. [E-Commerce Collections](#e-commerce-collections)
10. [CMS-Driven Components](#cms-driven-components)
11. [Performance & Limits](#performance--limits)
12. [Best Practices](#best-practices)
13. [Anti-Patterns](#anti-patterns)

---

## CMS Architecture Principles

### When to Use CMS vs Static

Not every piece of content belongs in the CMS. Use this decision framework:

**Use CMS for:**
- Content updated by non-developers (blog posts, team members, jobs)
- Repeating items with identical structure (cards, testimonials, FAQs)
- Content exceeding 20 items that will grow over time
- Content requiring categorization, filtering, or search
- SEO-critical pages needing unique slugs and meta data

**Keep static for:**
- Hero sections with rarely-changing copy
- Legal pages (privacy policy, terms)
- Site-wide configuration that rarely changes
- One-off page layouts with no repeating pattern

### Data Modeling Strategy

Before creating a single collection, model your data relationships on paper:

```
Blog Posts (Collection)
├── Title (Plain Text, required)
├── Slug (Auto-generated from Title)
├── Featured Image (Image, required)
├── Featured Image Alt (Plain Text)
├── Summary (Plain Text, max 200 chars)
├── Body (Rich Text)
├── Published Date (Date)
├── Author (Reference → Authors)
├── Category (Reference → Categories)
├── Tags (Multi-Reference → Tags)
├── Reading Time (Number, calculated)
├── SEO Title (Plain Text)
├── SEO Description (Plain Text)
├── OG Image (Image)
└── Is Featured (Switch)

Authors (Collection)
├── Name (Plain Text, required)
├── Slug (Auto-generated)
├── Photo (Image)
├── Bio (Rich Text)
├── Role (Plain Text)
├── Twitter URL (Link)
├── LinkedIn URL (Link)
└── Blog Posts (Multi-Reference → Blog Posts, reverse)

Categories (Collection)
├── Name (Plain Text, required)
├── Slug (Auto-generated)
├── Description (Plain Text)
├── Color (Color)
├── Icon (Image)
└── Sort Order (Number)

Tags (Collection)
├── Name (Plain Text, required)
├── Slug (Auto-generated)
└── Description (Plain Text)
```

**Staff Engineer Decision Matrix:**
- Under 5 collections: Simple blog or portfolio, no complex references needed
- 5-15 collections: Business site with CMS-driven sections, reference fields essential
- 15+ collections: Consider whether Webflow CMS is the right tool, or if a headless CMS (Sanity, Contentful) with the Webflow Data API is more appropriate

---

## Collection Schema Design

### Field Type Selection Guide

| Content Need | Field Type | Notes |
|---|---|---|
| Short text (titles, names) | Plain Text | Max 256 chars |
| Formatted content | Rich Text | Supports headings, lists, images, embeds |
| URLs | Link | Validates URL format, supports `target="_blank"` |
| Yes/No toggles | Switch | Use for "Is Featured", "Is Published" |
| Numeric values | Number | Use for prices, sort order, reading time |
| Dates | Date/Time | Use for publish date, event date |
| Single relationship | Reference | Links to one item in another collection |
| Multiple relationships | Multi-Reference | Links to many items, max 25 per field |
| File uploads | File | PDFs, documents up to 10MB |
| Images | Image | Supports alt text, auto-responsive srcset |
| Color values | Color | Hex color picker, useful for category badges |
| Dropdown options | Option | Predefined choices, useful for status or type |

### Collection Field Naming Conventions

Follow a consistent naming scheme across all collections:

```
# Consistent field naming (recommended)
name              # Primary identifier
slug              # URL-friendly identifier (auto)
summary           # Short description (plain text)
body              # Main content (rich text)
featured-image    # Primary image
featured-image-alt # Alt text for primary image
published-date    # Date field
sort-order        # Manual ordering number
is-featured       # Switch for featured items
is-published      # Switch for publish state
seo-title         # Override for page title
seo-description   # Override for meta description
og-image          # Social sharing image
```

### Collection Settings

Every collection should be configured with:

1. **Collection name**: Plural noun (Blog Posts, not Blog Post)
2. **Singular name**: For CMS labels (Blog Post)
3. **Primary field**: The field shown in the CMS listing (usually "Name" or "Title")
4. **Sort order**: Default sort for the collection list (usually by date or sort order)

---

## Reference & Multi-Reference Fields

### Single Reference (One-to-Many)

A reference field links one CMS item to another. This is the equivalent of a foreign key in relational databases.

```html
<!-- Blog post with author reference -->
<article class="blog-post_component">
  <div class="blog-post_meta">
    <!-- Author reference: pulls fields from the linked Authors item -->
    <div class="blog-post_author">
      <img class="blog-post_author-photo"
           src="{author.photo}"
           alt="{author.name}" />
      <div class="blog-post_author-info">
        <span class="blog-post_author-name">{author.name}</span>
        <span class="blog-post_author-role text-size-small">{author.role}</span>
      </div>
    </div>
    <!-- Category reference: pulls name and color -->
    <span class="blog-post_category"
          style="background-color: {category.color}">
      {category.name}
    </span>
  </div>
  <h1 class="blog-post_title heading-style-h1">{title}</h1>
  <div class="blog-post_body">{body}</div>
</article>
```

**Key behavior:**
- Reference fields create a dropdown selector in the CMS editor
- You can pull any field from the referenced item in templates
- Deleting a referenced item leaves a broken reference (plan for this)
- A single reference field links to exactly one item

### Multi-Reference (Many-to-Many)

Multi-reference fields link one item to multiple items in another collection. Use them for tags, categories (when items belong to multiple), related posts, or any many-to-many relationship.

```html
<!-- Blog post tags displayed as a collection list -->
<div class="blog-post_tags">
  <!-- Webflow Collection List bound to the "Tags" multi-reference field -->
  <div class="w-dyn-list">
    <div role="list" class="blog-post_tags-list w-dyn-items">
      <!-- Repeated for each linked tag -->
      <div role="listitem" class="blog-post_tag-item w-dyn-item">
        <a href="/tags/{tag.slug}" class="blog-post_tag-link">
          {tag.name}
        </a>
      </div>
    </div>
  </div>
</div>
```

**Multi-reference limitations:**
- Maximum 25 items per multi-reference field
- Cannot filter a collection list by multi-reference field natively (use Finsweet)
- Cannot sort by multi-reference field
- Multi-reference fields add a many-to-many join table internally

### Nested References Pattern

For deeper data relationships, chain references carefully:

```
Products → Category (Reference)
Products → Variants (Multi-Reference → Product Variants)
Product Variants → Size (Reference → Sizes)
Product Variants → Color (Reference → Colors)
```

In the Designer, you can only go one reference level deep in dynamic bindings. For deeper chains, use Finsweet CMS Nest or custom JavaScript.

---

## Collection Templates & Dynamic Pages

### Template Page Setup

Every CMS collection can have a template page that generates a unique URL for each item (e.g., `/blog/my-first-post`).

```html
<!-- Collection template page: /blog/{slug} -->
<body>
  <div class="page-wrapper">
    <!-- Navbar symbol -->

    <main class="main-wrapper">
      <!-- Hero with dynamic background -->
      <section class="section_blog-hero">
        <div class="blog-hero_background-wrapper">
          <img class="blog-hero_image"
               src="{featured-image}"
               alt="{featured-image-alt}" />
          <div class="blog-hero_overlay"></div>
        </div>
        <div class="padding-global">
          <div class="container-large">
            <div class="blog-hero_content">
              <span class="blog-hero_category">{category.name}</span>
              <h1 class="blog-hero_title heading-style-h1">{title}</h1>
              <div class="blog-hero_meta">
                <img class="blog-hero_author-photo"
                     src="{author.photo}"
                     alt="{author.name}" />
                <span class="blog-hero_author-name">{author.name}</span>
                <span class="blog-hero_divider">|</span>
                <time class="blog-hero_date">{published-date}</time>
                <span class="blog-hero_divider">|</span>
                <span class="blog-hero_reading-time">{reading-time} min read</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Rich text body -->
      <section class="section_blog-body">
        <div class="padding-global">
          <div class="container-medium">
            <div class="blog-body_rich-text w-richtext">
              {body}
            </div>
          </div>
        </div>
      </section>

      <!-- Related posts (collection list filtered by same category) -->
      <section class="section_related-posts">
        <div class="padding-global">
          <div class="container-large">
            <h2 class="heading-style-h3">Related Articles</h2>
            <!-- Collection list: Blog Posts, filtered by same category -->
            <div class="related-posts_grid">
              <!-- Dynamic items here -->
            </div>
          </div>
        </div>
      </section>
    </main>

    <!-- Footer symbol -->
  </div>
</body>
```

### SEO Configuration for Template Pages

Every collection template must configure dynamic SEO fields:

```
Page Settings (per template):
├── Title Tag: {seo-title} | Site Name  (fallback: {title} | Site Name)
├── Meta Description: {seo-description}  (fallback: {summary})
├── OG Title: {seo-title}  (fallback: {title})
├── OG Description: {seo-description}  (fallback: {summary})
├── OG Image: {og-image}  (fallback: {featured-image})
├── Canonical URL: auto (leave blank for self-referencing)
└── Sitemap Priority: 0.7 for blog posts, 0.8 for products
```

---

## Collection Lists & Nested Lists

### Basic Collection List

A collection list is the primary way to display multiple CMS items on a page.

```html
<!-- Blog listing page -->
<section class="section_blog-list">
  <div class="padding-global">
    <div class="container-large">
      <h1 class="heading-style-h2 margin-bottom-48">Latest Articles</h1>

      <!-- Webflow Collection List wrapper -->
      <div class="w-dyn-list">
        <div role="list" class="blog-list_grid w-dyn-items">

          <!-- Each CMS item renders this template -->
          <div role="listitem" class="blog-list_item w-dyn-item">
            <a href="/blog/{slug}" class="blog-card_link-wrapper">
              <div class="blog-card_image-wrapper">
                <img class="blog-card_image"
                     src="{featured-image}"
                     alt="{featured-image-alt}"
                     loading="lazy"
                     sizes="(max-width: 767px) 90vw, (max-width: 991px) 45vw, 30vw" />
              </div>
              <div class="blog-card_content">
                <div class="blog-card_meta">
                  <span class="blog-card_category">{category.name}</span>
                  <time class="blog-card_date">{published-date}</time>
                </div>
                <h3 class="blog-card_title heading-style-h5">{title}</h3>
                <p class="blog-card_summary text-size-regular">{summary}</p>
              </div>
            </a>
          </div>

        </div>

        <!-- Empty state when no items match -->
        <div class="w-dyn-empty">
          <p>No articles found.</p>
        </div>
      </div>
    </div>
  </div>
</section>
```

### Nested Collection Lists

Webflow allows nesting a collection list inside another collection list to display related items. The inner list can only reference a multi-reference field from the outer item.

```html
<!-- Team page with nested skills -->
<div class="w-dyn-list">
  <div role="list" class="team_grid w-dyn-items">
    <div role="listitem" class="team_item w-dyn-item">
      <img class="team_photo" src="{photo}" alt="{name}" />
      <h3 class="team_name">{name}</h3>
      <p class="team_role">{role}</p>

      <!-- Nested list: Skills multi-reference from this team member -->
      <div class="w-dyn-list">
        <div role="list" class="team_skills-list w-dyn-items">
          <div role="listitem" class="team_skill-tag w-dyn-item">
            {skill.name}
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

**Nested list constraints:**
- Maximum 5 nested items displayed per outer item (Webflow limit)
- Only multi-reference fields from the outer collection can populate the inner list
- Cannot apply conditional visibility to nested items independently
- Performance decreases with large outer collections combined with nested lists

---

## Pagination Patterns

### Native Webflow Pagination

Webflow provides built-in pagination for collection lists exceeding the items-per-page limit.

```html
<!-- Paginated blog listing -->
<div class="w-dyn-list">
  <div role="list" class="blog-list_grid w-dyn-items">
    <!-- Items render here (e.g., 12 per page) -->
  </div>

  <!-- Pagination controls (auto-generated by Webflow) -->
  <div class="w-pagination-wrapper">
    <a href="?page=1" class="w-pagination-previous">
      <svg class="w-pagination-previous-icon"><!-- arrow --></svg>
      <span>Previous</span>
    </a>
    <a href="?page=3" class="w-pagination-next">
      <span>Next</span>
      <svg class="w-pagination-next-icon"><!-- arrow --></svg>
    </a>
  </div>
</div>
```

**Pagination styling:**

```css
/* Custom pagination styles */
.w-pagination-wrapper {
  display: flex;
  justify-content: center;
  gap: 1rem;
  margin-top: 3rem;
  padding-top: 2rem;
  border-top: 1px solid var(--color-border);
}

.w-pagination-previous,
.w-pagination-next {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1.5rem;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  color: var(--color-text-primary);
  text-decoration: none;
  transition: background-color var(--transition-fast);
}

.w-pagination-previous:hover,
.w-pagination-next:hover {
  background-color: var(--color-bg-secondary);
}
```

### Infinite Scroll with Finsweet

For modern UX, replace pagination with infinite scroll using Finsweet CMS Load:

```html
<!-- Add Finsweet CMS Load attributes -->
<div class="w-dyn-list"
     fs-cmsload-element="list"
     fs-cmsload-mode="load-under"
     fs-cmsload-animation="fade"
     fs-cmsload-duration="300">
  <div role="list" class="blog-list_grid w-dyn-items">
    <!-- Items -->
  </div>

  <!-- Pagination wrapper: hidden but required for CMS Load to work -->
  <div class="w-pagination-wrapper"
       fs-cmsload-element="pagination"
       style="display: none;">
    <a class="w-pagination-next">Next</a>
  </div>
</div>

<!-- Load More button (alternative to infinite scroll) -->
<a href="#" class="button is-secondary"
   fs-cmsload-element="trigger">
  Load More Articles
</a>

<!-- Loading spinner -->
<div class="loading-spinner"
     fs-cmsload-element="loader">
  <div class="spinner"></div>
</div>
```

---

## Filtering & Sorting with Finsweet

### Finsweet CMS Filter Setup

Finsweet CMS Filter is the industry standard for adding filtering to Webflow CMS collection lists without custom code.

```html
<!-- Filter controls -->
<div class="blog-filters_component" fs-cmsfilter-element="filters">

  <!-- Category filter (radio buttons) -->
  <div class="blog-filters_group">
    <label class="blog-filters_label">Category</label>
    <div class="blog-filters_options">
      <label class="blog-filters_option">
        <input type="radio" name="category" value=""
               fs-cmsfilter-field="category"
               checked />
        <span class="blog-filters_tag">All</span>
      </label>
      <label class="blog-filters_option">
        <input type="radio" name="category" value="Engineering"
               fs-cmsfilter-field="category" />
        <span class="blog-filters_tag">Engineering</span>
      </label>
      <label class="blog-filters_option">
        <input type="radio" name="category" value="Design"
               fs-cmsfilter-field="category" />
        <span class="blog-filters_tag">Design</span>
      </label>
    </div>
  </div>

  <!-- Tag filter (checkboxes) -->
  <div class="blog-filters_group">
    <label class="blog-filters_label">Tags</label>
    <div class="blog-filters_options">
      <label class="blog-filters_option">
        <input type="checkbox" value="JavaScript"
               fs-cmsfilter-field="tags" />
        <span class="blog-filters_tag">JavaScript</span>
      </label>
      <label class="blog-filters_option">
        <input type="checkbox" value="React"
               fs-cmsfilter-field="tags" />
        <span class="blog-filters_tag">React</span>
      </label>
    </div>
  </div>

  <!-- Text search -->
  <div class="blog-filters_group">
    <label class="blog-filters_label">Search</label>
    <input type="text"
           class="blog-filters_search"
           placeholder="Search articles..."
           fs-cmsfilter-field="title,summary"
           fs-cmsfilter-type="contains" />
  </div>

  <!-- Results count -->
  <div class="blog-filters_count">
    <span fs-cmsfilter-element="results-count">0</span> articles found
  </div>

  <!-- Active filters display -->
  <div class="blog-filters_active" fs-cmsfilter-element="active">
    <!-- Active filter tags render here automatically -->
  </div>

  <!-- Reset all filters -->
  <a href="#" class="blog-filters_reset"
     fs-cmsfilter-element="reset">
    Clear All Filters
  </a>
</div>

<!-- Collection list with filter data attributes -->
<div class="w-dyn-list" fs-cmsfilter-element="list">
  <div role="list" class="blog-list_grid w-dyn-items">
    <div role="listitem" class="blog-list_item w-dyn-item">
      <!-- Hidden filter targets (for Finsweet to match against) -->
      <div class="blog-card_filter-data" style="display: none;">
        <span fs-cmsfilter-field="category">{category.name}</span>
        <span fs-cmsfilter-field="tags">{tags}</span>
      </div>
      <!-- Visible card content -->
      <a href="/blog/{slug}" class="blog-card_link-wrapper">
        <h3 class="blog-card_title">{title}</h3>
        <p class="blog-card_summary">{summary}</p>
      </a>
    </div>
  </div>
</div>
```

### CMS Sort

```html
<!-- Sort controls -->
<div class="blog-sort_component" fs-cmssort-element="sort">
  <label class="blog-sort_label">Sort by:</label>
  <select class="blog-sort_select" fs-cmssort-element="trigger">
    <option value="date-desc" fs-cmssort-field="date" fs-cmssort-order="desc">
      Newest First
    </option>
    <option value="date-asc" fs-cmssort-field="date" fs-cmssort-order="asc">
      Oldest First
    </option>
    <option value="title-asc" fs-cmssort-field="title" fs-cmssort-order="asc">
      Title A-Z
    </option>
  </select>
</div>
```

### Combining Filter + Sort + Load

The power of Finsweet comes from combining these attributes on the same collection list:

```html
<div class="w-dyn-list"
     fs-cmsfilter-element="list"
     fs-cmssort-element="list"
     fs-cmsload-element="list"
     fs-cmsload-mode="load-under">
  <!-- Items render here -->
</div>
```

Include all three Finsweet scripts in order:

```html
<!-- Site-wide custom code (before </body>) -->
<script defer src="https://cdn.jsdelivr.net/npm/@finsweet/attributes-cmsfilter@1/cmsfilter.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/@finsweet/attributes-cmssort@1/cmssort.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/@finsweet/attributes-cmsload@1/cmsload.js"></script>
```

---

## Webflow CMS API v2

### Authentication & Setup

The Webflow Data API v2 enables external systems to read and write CMS content programmatically.

```javascript
// Webflow CMS API v2 client setup
const WEBFLOW_API_TOKEN = process.env.WEBFLOW_API_TOKEN;
const SITE_ID = process.env.WEBFLOW_SITE_ID;
const BASE_URL = 'https://api.webflow.com/v2';

const headers = {
  'Authorization': `Bearer ${WEBFLOW_API_TOKEN}`,
  'Content-Type': 'application/json',
  'accept': 'application/json',
};

// List all collections for a site
async function listCollections() {
  const response = await fetch(`${BASE_URL}/sites/${SITE_ID}/collections`, {
    headers,
  });
  const data = await response.json();
  return data.collections;
}

// Get collection items with pagination
async function getCollectionItems(collectionId, offset = 0, limit = 100) {
  const url = new URL(`${BASE_URL}/collections/${collectionId}/items`);
  url.searchParams.set('offset', offset.toString());
  url.searchParams.set('limit', limit.toString());

  const response = await fetch(url.toString(), { headers });
  const data = await response.json();
  return data; // { items: [...], pagination: { limit, offset, total } }
}
```

### CRUD Operations via API

```javascript
// Create a new CMS item
async function createItem(collectionId, fields) {
  const response = await fetch(`${BASE_URL}/collections/${collectionId}/items`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      fieldData: {
        name: fields.title,
        slug: fields.slug,
        'post-summary': fields.summary,
        'post-body': fields.body,
        'published-date': fields.publishedDate,
        'is-featured': fields.isFeatured || false,
        // Reference fields use the referenced item's ID
        'author': fields.authorId,
        // Multi-reference fields use an array of IDs
        'tags': fields.tagIds,
      },
    }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Failed to create item: ${JSON.stringify(error)}`);
  }

  return response.json();
}

// Update an existing CMS item
async function updateItem(collectionId, itemId, fields) {
  const response = await fetch(
    `${BASE_URL}/collections/${collectionId}/items/${itemId}`,
    {
      method: 'PATCH',
      headers,
      body: JSON.stringify({
        fieldData: fields,
      }),
    }
  );
  return response.json();
}

// Delete a CMS item
async function deleteItem(collectionId, itemId) {
  const response = await fetch(
    `${BASE_URL}/collections/${collectionId}/items/${itemId}`,
    {
      method: 'DELETE',
      headers,
    }
  );
  if (!response.ok) {
    throw new Error(`Failed to delete item ${itemId}`);
  }
}

// Publish items (make live on the site)
async function publishItems(collectionId, itemIds) {
  const response = await fetch(
    `${BASE_URL}/collections/${collectionId}/items/publish`,
    {
      method: 'POST',
      headers,
      body: JSON.stringify({ itemIds }),
    }
  );
  return response.json();
}
```

### Bulk Operations & Rate Limits

```javascript
// Batch create with rate limit handling
async function batchCreateItems(collectionId, items) {
  const results = [];
  const RATE_LIMIT_DELAY = 1100; // Webflow API: 60 requests per minute

  for (const item of items) {
    try {
      const result = await createItem(collectionId, item);
      results.push({ success: true, item: result });
    } catch (error) {
      results.push({ success: false, item, error: error.message });
    }
    // Respect rate limits
    await new Promise(resolve => setTimeout(resolve, RATE_LIMIT_DELAY));
  }

  return results;
}

// Webflow API v2 rate limits (as of 2026):
// - 60 requests per minute per site token
// - 100 items per list request (paginate with offset)
// - 100 items per bulk publish request
// - Maximum 10,000 CMS items per collection (Basic plan)
// - Maximum 100,000 CMS items per site (Enterprise plan)
```

---

## E-Commerce Collections

### Product Collection Schema

Webflow E-commerce uses special system collections that extend standard CMS:

```
Products (E-Commerce System Collection)
├── Name (required)
├── Slug (auto)
├── Description (Rich Text)
├── SKU Settings/
│   ├── SKU (auto-generated or manual)
│   ├── Price (Currency, required)
│   ├── Compare-at Price (Currency, for sales)
│   ├── Weight (Number)
│   ├── Width, Height, Length (Number)
│   └── Inventory (Number or infinite)
├── Product Images (Multi-Image)
├── Categories (Multi-Reference → Categories)
├── Product Type (Option: Physical, Digital, Service)
├── Tax Category (Option)
├── SEO fields (auto from system)
└── Custom Fields/
    ├── Material (Plain Text)
    ├── Care Instructions (Rich Text)
    └── Size Guide (Reference → Size Guides)

SKUs (System sub-collection)
├── SKU (unique identifier)
├── Price (can override product price)
├── Compare-at Price
├── Variant Options (e.g., Size: Large, Color: Blue)
├── SKU Image (overrides product image for this variant)
├── Weight (overrides product weight)
└── Inventory Count
```

### E-Commerce Product Template

```html
<!-- Product detail template -->
<section class="section_product-detail">
  <div class="padding-global">
    <div class="container-large">
      <div class="product_layout">

        <!-- Product gallery -->
        <div class="product_gallery">
          <div class="product_main-image-wrapper">
            <img class="product_main-image"
                 src="{main-image}"
                 alt="{name}" />
          </div>
          <div class="product_thumbnail-list">
            <!-- Lightbox gallery of all product images -->
          </div>
        </div>

        <!-- Product info -->
        <div class="product_info">
          <div class="product_breadcrumbs">
            <a href="/shop">Shop</a> / <span>{category.name}</span>
          </div>
          <h1 class="product_name heading-style-h2">{name}</h1>
          <div class="product_price-wrapper">
            <span class="product_price">{price}</span>
            <span class="product_compare-price is-strikethrough">{compare-at-price}</span>
          </div>

          <!-- Add to cart form (Webflow E-Commerce) -->
          <form class="w-commerce-commerceaddtocartform">
            <!-- Variant selectors (auto-generated) -->
            <div class="product_variants">
              <label>Size</label>
              <select class="w-commerce-commerceaddtocartoptionselect">
                <!-- Options populated by SKU variants -->
              </select>
            </div>
            <div class="product_quantity">
              <label>Quantity</label>
              <input type="number"
                     class="w-commerce-commerceaddtocartquantityinput"
                     value="1" min="1" />
            </div>
            <button type="submit"
                    class="w-commerce-commerceaddtocartbutton button is-primary">
              Add to Cart
            </button>
          </form>

          <div class="product_description w-richtext">
            {description}
          </div>
        </div>
      </div>
    </div>
  </div>
</section>
```

---

## CMS-Driven Components

### Dynamic Sections from CMS

Use CMS collections to power reusable page sections, allowing content editors to manage entire sections from the CMS panel.

```html
<!-- Homepage sections driven by a "Homepage Sections" collection -->
<div class="w-dyn-list">
  <div role="list" class="homepage-sections_list w-dyn-items">
    <div role="listitem" class="homepage-sections_item w-dyn-item">
      <section class="section_dynamic"
               style="background-color: {background-color}">
        <div class="padding-global">
          <div class="container-large">
            <div class="dynamic-section_layout is-{layout-type}">
              <div class="dynamic-section_content">
                <span class="dynamic-section_eyebrow text-size-small">
                  {eyebrow}
                </span>
                <h2 class="dynamic-section_heading heading-style-h2">
                  {heading}
                </h2>
                <div class="dynamic-section_body w-richtext">
                  {body}
                </div>
                <a href="{cta-url}" class="button is-primary">
                  {cta-text}
                </a>
              </div>
              <div class="dynamic-section_media">
                <img src="{image}" alt="{image-alt}" loading="lazy" />
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</div>
```

### CMS-Powered Navigation

```html
<!-- Navigation links from CMS -->
<nav class="navbar_component">
  <div class="navbar_container">
    <a href="/" class="navbar_logo-link">
      <img src="logo.svg" class="navbar_logo" alt="Site Name" />
    </a>
    <div class="navbar_menu">
      <!-- Static main links -->
      <a href="/about" class="navbar_link">About</a>

      <!-- CMS-driven dropdown for services -->
      <div class="navbar_dropdown">
        <div class="navbar_dropdown-toggle">Services</div>
        <div class="navbar_dropdown-menu w-dyn-list">
          <div role="list" class="w-dyn-items">
            <div role="listitem" class="w-dyn-item">
              <a href="/services/{slug}" class="navbar_dropdown-link">
                <img src="{icon}" alt="" class="navbar_dropdown-icon" />
                <div>
                  <span class="navbar_dropdown-title">{name}</span>
                  <span class="navbar_dropdown-desc text-size-small">{short-description}</span>
                </div>
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</nav>
```

---

## Performance & Limits

### Webflow CMS Limits (2026)

| Plan | CMS Items | Collections | Image Size |
|---|---|---|---|
| Basic | 2,000 | 20 | 4MB |
| CMS | 10,000 | 40 | 4MB |
| Business | 10,000 | 40 | 4MB |
| Enterprise | 100,000 | 100 | 4MB |

### Performance Optimization

1. **Limit collection list items**: Display 12-24 items per page, paginate the rest
2. **Use conditional visibility**: Hide empty fields rather than rendering empty containers
3. **Lazy-load images**: All CMS images below the fold should use `loading="lazy"`
4. **Optimize image sizes**: Use Webflow's responsive images (`sizes` attribute) to serve correct size
5. **Minimize nested lists**: Each nested list multiplies DOM nodes; keep outer lists small
6. **Use Finsweet CMS Load**: Load additional items on demand instead of rendering 100+ items at once
7. **Cache API responses**: When using the CMS API, cache responses for at least 60 seconds

---

## Best Practices

1. **Model data before building** -- draw your collections, fields, and relationships before touching the Designer
2. **Use reference fields for shared data** -- author info, categories, and tags should be separate collections, not repeated text fields
3. **Set required fields** -- mark essential fields as required to prevent incomplete CMS entries
4. **Create a content style guide** -- document field character limits, image dimensions, and formatting rules for editors
5. **Use conditional visibility** -- show/hide elements based on CMS field values (e.g., hide "Sale" badge when compare-at-price is empty)
6. **Plan for empty states** -- every collection list must have a meaningful empty state message
7. **Use the CMS API for migrations** -- never manually re-enter content; script data imports via the API
8. **Version your CMS structure** -- document collection schemas in a spreadsheet or Notion for team reference
9. **Test with realistic data** -- populate at least 20 items per collection during development to catch layout issues
10. **Use switch fields for visibility** -- an "Is Published" switch field gives editors draft/publish control within the Designer

---

## Anti-Patterns

- Storing structured data in Rich Text fields instead of dedicated typed fields
- Using plain text for relationships instead of reference fields (e.g., typing "John Smith" instead of referencing an Authors item)
- Creating one collection with 30+ fields instead of splitting into related collections
- Ignoring the 5-item limit on nested collection lists and expecting more to render
- Hardcoding content that editors need to update (put it in the CMS)
- Not setting alt text fields for CMS images (accessibility and SEO failure)
- Using the CMS API without rate limiting (results in 429 errors and failed imports)
- Relying on Webflow's default sort without providing a sort-order field for manual ordering
- Creating duplicate collections instead of using reference fields to share data
- Not planning for pagination on collections that will grow beyond 20 items

---

## Sources & References

- [Webflow CMS Documentation](https://university.webflow.com/lesson/intro-to-the-cms)
- [Webflow Data API v2 Reference](https://developers.webflow.com/data/reference/cms/collection-items/list-collection-items)
- [Finsweet CMS Attributes Documentation](https://finsweet.com/attributes/cms-filter)
- [Webflow E-Commerce Documentation](https://university.webflow.com/lesson/intro-to-webflow-ecommerce)
- [Webflow CMS Best Practices Guide](https://university.webflow.com/lesson/cms-best-practices)
- [Finsweet CMS Load for Pagination](https://finsweet.com/attributes/cms-load)
- [Webflow CMS Collection Structure Guide](https://university.webflow.com/lesson/collection-fields)
- [Webflow API Rate Limits](https://developers.webflow.com/data/docs/rate-limits)
