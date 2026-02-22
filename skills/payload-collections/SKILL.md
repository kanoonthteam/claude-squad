---
name: payload-collections
description: Payload CMS 3.x collection configuration — field types (text, richText, relationship, upload, blocks, array, tabs, group), validation, hooks, custom fields, versioning, drafts, access control, TypeScript types
---

# Payload CMS 3.x Collections & Fields

Production-ready collection configuration patterns for Payload CMS 3.x (2025/2026). Covers all field types, collection hooks, field-level validation, custom field types, versioning and drafts, slug generation, and TypeScript-first configuration.

## Table of Contents

1. [Collection Configuration Basics](#collection-configuration-basics)
2. [Field Types Reference](#field-types-reference)
3. [Relationship Fields & Polymorphic Relations](#relationship-fields--polymorphic-relations)
4. [Upload Fields & Media Collections](#upload-fields--media-collections)
5. [Blocks & Flexible Content](#blocks--flexible-content)
6. [Array, Group, and Tabs Fields](#array-group-and-tabs-fields)
7. [Field Validation](#field-validation)
8. [Collection Hooks](#collection-hooks)
9. [Custom Field Types](#custom-field-types)
10. [Versioning & Drafts](#versioning--drafts)
11. [Slug Generation Patterns](#slug-generation-patterns)
12. [TypeScript & Generated Types](#typescript--generated-types)
13. [Best Practices](#best-practices)
14. [Anti-Patterns](#anti-patterns)
15. [Sources & References](#sources--references)

---

## Collection Configuration Basics

Every Payload collection is defined as a TypeScript object conforming to the `CollectionConfig` type. Collections map to database tables (PostgreSQL via Drizzle) or MongoDB collections. Payload 3.x is fully integrated with Next.js and uses a config-driven approach.

```typescript
// src/collections/Posts.ts
import type { CollectionConfig } from 'payload'

export const Posts: CollectionConfig = {
  slug: 'posts',
  labels: {
    singular: 'Post',
    plural: 'Posts',
  },
  admin: {
    useAsTitle: 'title',
    defaultColumns: ['title', 'status', 'author', 'updatedAt'],
    listSearchableFields: ['title', 'slug'],
    group: 'Content',
    description: 'Blog posts and articles',
  },
  access: {
    read: () => true,
    create: ({ req: { user } }) => Boolean(user),
    update: ({ req: { user } }) => Boolean(user),
    delete: ({ req: { user } }) => user?.role === 'admin',
  },
  timestamps: true,
  fields: [
    {
      name: 'title',
      type: 'text',
      required: true,
      minLength: 3,
      maxLength: 200,
    },
    {
      name: 'slug',
      type: 'text',
      required: true,
      unique: true,
      admin: {
        position: 'sidebar',
      },
      index: true,
    },
    {
      name: 'status',
      type: 'select',
      defaultValue: 'draft',
      options: [
        { label: 'Draft', value: 'draft' },
        { label: 'Published', value: 'published' },
        { label: 'Archived', value: 'archived' },
      ],
      admin: {
        position: 'sidebar',
      },
    },
    {
      name: 'content',
      type: 'richText',
    },
    {
      name: 'author',
      type: 'relationship',
      relationTo: 'users',
      required: true,
      admin: {
        position: 'sidebar',
      },
    },
  ],
}
```

### Registering Collections in payload.config.ts

```typescript
// payload.config.ts
import { buildConfig } from 'payload'
import { postgresAdapter } from '@payloadcms/db-postgres'
import { lexicalEditor } from '@payloadcms/richtext-lexical'
import { Posts } from './collections/Posts'
import { Users } from './collections/Users'
import { Media } from './collections/Media'
import { Categories } from './collections/Categories'

export default buildConfig({
  collections: [Posts, Users, Media, Categories],
  editor: lexicalEditor(),
  db: postgresAdapter({
    pool: {
      connectionString: process.env.DATABASE_URI,
    },
  }),
  typescript: {
    outputFile: './src/payload-types.ts',
  },
  secret: process.env.PAYLOAD_SECRET || '',
})
```

---

## Field Types Reference

Payload 3.x provides a comprehensive set of field types. Each field has a `name`, `type`, and optional configuration.

### Text Fields

```typescript
// Simple text
{ name: 'title', type: 'text', required: true, minLength: 1, maxLength: 300 }

// Textarea
{ name: 'excerpt', type: 'textarea', maxLength: 500 }

// Email
{ name: 'contactEmail', type: 'email', required: true }

// Number
{ name: 'price', type: 'number', min: 0, max: 999999, hasMany: false }

// Date
{
  name: 'publishDate',
  type: 'date',
  admin: {
    date: {
      pickerAppearance: 'dayAndTime',
      displayFormat: 'MMM d, yyyy h:mm a',
    },
  },
}

// Point (geolocation)
{ name: 'location', type: 'point' }

// JSON
{ name: 'metadata', type: 'json' }

// Checkbox
{ name: 'featured', type: 'checkbox', defaultValue: false }

// Radio
{
  name: 'priority',
  type: 'radio',
  options: [
    { label: 'Low', value: 'low' },
    { label: 'Medium', value: 'medium' },
    { label: 'High', value: 'high' },
  ],
  defaultValue: 'medium',
}

// Select (single or multi)
{
  name: 'tags',
  type: 'select',
  hasMany: true,
  options: [
    { label: 'Technology', value: 'technology' },
    { label: 'Design', value: 'design' },
    { label: 'Business', value: 'business' },
  ],
}

// Code field
{
  name: 'codeSnippet',
  type: 'code',
  admin: {
    language: 'typescript',
  },
}
```

### Rich Text (Lexical Editor in Payload 3.x)

Payload 3.x uses the Lexical rich text editor by default, replacing Slate from v2.

```typescript
import {
  lexicalEditor,
  BlocksFeature,
  LinkFeature,
  UploadFeature,
  HeadingFeature,
} from '@payloadcms/richtext-lexical'

{
  name: 'content',
  type: 'richText',
  editor: lexicalEditor({
    features: ({ defaultFeatures }) => [
      ...defaultFeatures,
      HeadingFeature({ enabledHeadingSizes: ['h2', 'h3', 'h4'] }),
      LinkFeature({
        enabledCollections: ['pages', 'posts'],
      }),
      UploadFeature({
        collections: {
          media: {
            fields: [
              {
                name: 'caption',
                type: 'text',
              },
            ],
          },
        },
      }),
      BlocksFeature({
        blocks: [CallToActionBlock, CodeBlock],
      }),
    ],
  }),
}
```

---

## Relationship Fields & Polymorphic Relations

### Single Relationship

```typescript
{
  name: 'author',
  type: 'relationship',
  relationTo: 'users',
  required: true,
  hasMany: false,
  filterOptions: {
    role: { equals: 'author' },
  },
}
```

### Polymorphic Relationship (Multiple Collection Types)

```typescript
{
  name: 'relatedContent',
  type: 'relationship',
  relationTo: ['posts', 'pages', 'case-studies'],
  hasMany: true,
}
// Returns: { relationTo: 'posts', value: '64abc...' }
```

### Join Field (Payload 3.x)

Join fields allow querying reverse relationships without storing data redundantly.

```typescript
// In the Categories collection
{
  name: 'posts',
  type: 'join',
  collection: 'posts',
  on: 'category',
  // Fetches all posts that have this category selected
}
```

---

## Upload Fields & Media Collections

### Media Collection with Image Sizes

```typescript
// src/collections/Media.ts
import type { CollectionConfig } from 'payload'

export const Media: CollectionConfig = {
  slug: 'media',
  upload: {
    staticDir: 'media',
    mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml', 'application/pdf'],
    imageSizes: [
      {
        name: 'thumbnail',
        width: 300,
        height: 300,
        position: 'centre',
      },
      {
        name: 'card',
        width: 768,
        height: 1024,
        position: 'centre',
      },
      {
        name: 'hero',
        width: 1920,
        height: undefined,
        position: 'centre',
      },
    ],
    adminThumbnail: 'thumbnail',
    focalPoint: true,
    crop: true,
  },
  access: {
    read: () => true,
  },
  fields: [
    {
      name: 'alt',
      type: 'text',
      required: true,
    },
    {
      name: 'caption',
      type: 'textarea',
    },
  ],
}
```

### Using Upload in Other Collections

```typescript
{
  name: 'featuredImage',
  type: 'upload',
  relationTo: 'media',
  required: true,
  filterOptions: {
    mimeType: { contains: 'image' },
  },
}
```

### Cloud Storage (S3, Vercel Blob, GCS)

```typescript
// payload.config.ts
import { s3Storage } from '@payloadcms/storage-s3'

export default buildConfig({
  plugins: [
    s3Storage({
      collections: {
        media: {
          prefix: 'media',
          generateFileURL: ({ filename, prefix }) =>
            `https://cdn.example.com/${prefix}/${filename}`,
        },
      },
      bucket: process.env.S3_BUCKET!,
      config: {
        region: process.env.S3_REGION!,
        credentials: {
          accessKeyId: process.env.S3_ACCESS_KEY!,
          secretAccessKey: process.env.S3_SECRET_KEY!,
        },
      },
    }),
  ],
})
```

---

## Blocks & Flexible Content

Blocks allow editors to build flexible, component-based content. Each block is a reusable set of fields.

```typescript
import type { Block } from 'payload'

const CallToAction: Block = {
  slug: 'cta',
  labels: {
    singular: 'Call to Action',
    plural: 'Calls to Action',
  },
  fields: [
    {
      name: 'heading',
      type: 'text',
      required: true,
    },
    {
      name: 'description',
      type: 'textarea',
    },
    {
      name: 'link',
      type: 'group',
      fields: [
        { name: 'label', type: 'text', required: true },
        { name: 'url', type: 'text', required: true },
        {
          name: 'appearance',
          type: 'select',
          defaultValue: 'primary',
          options: ['primary', 'secondary', 'outline'],
        },
      ],
    },
    {
      name: 'backgroundImage',
      type: 'upload',
      relationTo: 'media',
    },
  ],
}

const ContentBlock: Block = {
  slug: 'content',
  fields: [
    {
      name: 'columns',
      type: 'array',
      minRows: 1,
      maxRows: 3,
      fields: [
        {
          name: 'size',
          type: 'select',
          defaultValue: 'full',
          options: ['oneThird', 'half', 'twoThirds', 'full'],
        },
        {
          name: 'richText',
          type: 'richText',
        },
      ],
    },
  ],
}

// Using blocks in a collection
{
  name: 'layout',
  type: 'blocks',
  blocks: [CallToAction, ContentBlock],
  required: true,
}
```

---

## Array, Group, and Tabs Fields

### Array Fields

```typescript
{
  name: 'socialLinks',
  type: 'array',
  label: 'Social Media Links',
  minRows: 0,
  maxRows: 10,
  labels: {
    singular: 'Social Link',
    plural: 'Social Links',
  },
  admin: {
    initCollapsed: true,
    components: {
      RowLabel: '/src/admin/components/SocialLinkRowLabel',
    },
  },
  fields: [
    {
      name: 'platform',
      type: 'select',
      required: true,
      options: ['twitter', 'linkedin', 'github', 'youtube'],
    },
    {
      name: 'url',
      type: 'text',
      required: true,
    },
  ],
}
```

### Group Fields

Groups organize related fields without creating a separate collection. Data is nested in the document.

```typescript
{
  name: 'seo',
  type: 'group',
  label: 'SEO Settings',
  admin: {
    condition: (data) => data.status === 'published',
  },
  fields: [
    { name: 'title', type: 'text', maxLength: 60 },
    { name: 'description', type: 'textarea', maxLength: 160 },
    { name: 'image', type: 'upload', relationTo: 'media' },
    { name: 'noIndex', type: 'checkbox', defaultValue: false },
  ],
}
```

### Tabs Fields

Tabs organize fields into separate admin UI tabs without affecting data structure (when using named tabs).

```typescript
{
  type: 'tabs',
  tabs: [
    {
      label: 'Content',
      fields: [
        { name: 'title', type: 'text', required: true },
        { name: 'content', type: 'richText' },
      ],
    },
    {
      label: 'Media',
      fields: [
        { name: 'featuredImage', type: 'upload', relationTo: 'media' },
        { name: 'gallery', type: 'array', fields: [
          { name: 'image', type: 'upload', relationTo: 'media' },
          { name: 'caption', type: 'text' },
        ]},
      ],
    },
    {
      name: 'meta',
      label: 'SEO & Metadata',
      fields: [
        { name: 'metaTitle', type: 'text', maxLength: 60 },
        { name: 'metaDescription', type: 'textarea', maxLength: 160 },
      ],
    },
  ],
}
```

**Named tabs** (with `name` property) nest data under that key. **Unnamed tabs** (without `name`) keep fields at the top level.

---

## Field Validation

### Built-in Validation

```typescript
{
  name: 'email',
  type: 'email',
  required: true,
  unique: true,
}

{
  name: 'age',
  type: 'number',
  min: 0,
  max: 150,
  required: true,
}

{
  name: 'username',
  type: 'text',
  minLength: 3,
  maxLength: 30,
  required: true,
  unique: true,
}
```

### Custom Validation Functions

```typescript
{
  name: 'slug',
  type: 'text',
  required: true,
  validate: (value: string | undefined | null) => {
    if (!value) return 'Slug is required'
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value)) {
      return 'Slug must be lowercase alphanumeric with hyphens only'
    }
    return true
  },
}

{
  name: 'endDate',
  type: 'date',
  validate: (value, { siblingData }) => {
    if (value && siblingData.startDate && new Date(value) <= new Date(siblingData.startDate)) {
      return 'End date must be after start date'
    }
    return true
  },
}

// Async validation (check uniqueness, call external API)
{
  name: 'externalId',
  type: 'text',
  validate: async (value, { payload, id }) => {
    if (!value) return true
    const existing = await payload.find({
      collection: 'products',
      where: {
        externalId: { equals: value },
        id: { not_equals: id },
      },
      limit: 1,
    })
    if (existing.docs.length > 0) {
      return 'This external ID is already in use'
    }
    return true
  },
}
```

---

## Collection Hooks

Hooks run at specific points in the document lifecycle. They are the primary way to add business logic.

### Hook Types

- **beforeValidate** - Modify data before validation runs
- **beforeChange** - Modify data before it is persisted (runs after validation)
- **afterChange** - Run side effects after document is saved
- **beforeRead** - Modify query before fetching
- **afterRead** - Transform data after fetching (e.g., compute virtual fields)
- **beforeDelete** - Run checks before deletion
- **afterDelete** - Run cleanup after deletion
- **afterOperation** - Runs after any CRUD operation

```typescript
import type { CollectionConfig } from 'payload'

export const Orders: CollectionConfig = {
  slug: 'orders',
  hooks: {
    beforeChange: [
      // Auto-calculate total
      async ({ data, operation }) => {
        if (data.items && data.items.length > 0) {
          data.total = data.items.reduce(
            (sum: number, item: { price: number; quantity: number }) =>
              sum + item.price * item.quantity,
            0,
          )
        }
        return data
      },
    ],
    afterChange: [
      // Send notification email on new order
      async ({ doc, operation, req }) => {
        if (operation === 'create') {
          await sendOrderConfirmation(doc.customerEmail, doc)
        }
        // For status changes
        if (operation === 'update' && doc.status === 'shipped') {
          await sendShippingNotification(doc.customerEmail, doc)
        }
      },
    ],
    beforeDelete: [
      // Prevent deletion of fulfilled orders
      async ({ id, req }) => {
        const order = await req.payload.findByID({
          collection: 'orders',
          id,
        })
        if (order.status === 'fulfilled') {
          throw new Error('Cannot delete fulfilled orders')
        }
      },
    ],
    afterRead: [
      // Add computed field
      ({ doc }) => {
        doc.displayName = `Order #${doc.orderNumber} - ${doc.customerName}`
        return doc
      },
    ],
  },
  fields: [
    // ... fields
  ],
}
```

### Field-Level Hooks

```typescript
{
  name: 'password',
  type: 'text',
  hooks: {
    beforeChange: [
      async ({ value, originalDoc }) => {
        // Only hash if password changed
        if (value && value !== originalDoc?.password) {
          return await bcrypt.hash(value, 12)
        }
        return value
      },
    ],
    afterRead: [
      // Never expose password
      () => undefined,
    ],
  },
}
```

---

## Custom Field Types

Payload 3.x allows creating reusable custom field configurations.

```typescript
// src/fields/slug.ts
import type { Field } from 'payload'
import { formatSlug } from '../utilities/formatSlug'

export const slugField = (sourceField: string = 'title'): Field => ({
  name: 'slug',
  type: 'text',
  required: true,
  unique: true,
  index: true,
  admin: {
    position: 'sidebar',
    description: `Auto-generated from ${sourceField}. Edit manually if needed.`,
  },
  hooks: {
    beforeValidate: [
      ({ value, siblingData }) => {
        if (!value && siblingData[sourceField]) {
          return formatSlug(siblingData[sourceField])
        }
        return value ? formatSlug(value) : value
      },
    ],
  },
})

// src/fields/seo.ts
import type { Field } from 'payload'

export const seoFields: Field = {
  name: 'seo',
  type: 'group',
  label: 'SEO',
  admin: {
    position: 'sidebar',
  },
  fields: [
    {
      name: 'title',
      type: 'text',
      maxLength: 60,
      admin: {
        description: 'Recommended: 50-60 characters',
      },
    },
    {
      name: 'description',
      type: 'textarea',
      maxLength: 160,
      admin: {
        description: 'Recommended: 120-160 characters',
      },
    },
    {
      name: 'image',
      type: 'upload',
      relationTo: 'media',
    },
  ],
}

// Usage in a collection
import { slugField } from '../fields/slug'
import { seoFields } from '../fields/seo'

export const Pages: CollectionConfig = {
  slug: 'pages',
  fields: [
    { name: 'title', type: 'text', required: true },
    slugField('title'),
    { name: 'content', type: 'richText' },
    seoFields,
  ],
}
```

---

## Versioning & Drafts

Payload 3.x has built-in versioning and draft support.

```typescript
export const Posts: CollectionConfig = {
  slug: 'posts',
  versions: {
    drafts: {
      autosave: {
        interval: 1500, // milliseconds
      },
      validate: false, // Skip validation on draft save
    },
    maxPerDoc: 25, // Keep last 25 versions
  },
  access: {
    // Only show published docs to public
    read: ({ req: { user } }) => {
      if (user) return true
      return {
        _status: { equals: 'published' },
      }
    },
  },
  fields: [
    { name: 'title', type: 'text', required: true },
    {
      name: 'publishDate',
      type: 'date',
      admin: {
        position: 'sidebar',
        date: { pickerAppearance: 'dayAndTime' },
        condition: (data) => data._status === 'published',
      },
    },
    { name: 'content', type: 'richText' },
  ],
}
```

### Publishing Workflow

```typescript
// Publish a draft via local API
await payload.update({
  collection: 'posts',
  id: postId,
  data: {
    _status: 'published',
    publishDate: new Date().toISOString(),
  },
})

// Revert to a previous version
await payload.restoreVersion({
  collection: 'posts',
  id: versionId,
})

// Query only published posts
const published = await payload.find({
  collection: 'posts',
  where: {
    _status: { equals: 'published' },
  },
})
```

---

## Slug Generation Patterns

```typescript
// src/utilities/formatSlug.ts
export const formatSlug = (val: string): string =>
  val
    .replace(/ /g, '-')
    .replace(/[^\w-]+/g, '')
    .toLowerCase()

// Auto-generate slug from title with beforeValidate hook
{
  name: 'slug',
  type: 'text',
  required: true,
  unique: true,
  index: true,
  hooks: {
    beforeValidate: [
      ({ value, siblingData, operation }) => {
        // Auto-generate on create, preserve manual edits on update
        if (operation === 'create' && !value && siblingData?.title) {
          return formatSlug(siblingData.title)
        }
        if (value) {
          return formatSlug(value)
        }
        return value
      },
    ],
  },
  admin: {
    position: 'sidebar',
  },
}
```

---

## TypeScript & Generated Types

Payload 3.x auto-generates TypeScript types from your collection configs.

```bash
# Generate types (automatically runs with payload dev)
npx payload generate:types
```

```typescript
// Using generated types
import type { Post, User, Media } from '../payload-types'

// In hooks and access control
import type { CollectionBeforeChangeHook } from 'payload'

const populateAuthor: CollectionBeforeChangeHook<Post> = async ({
  data,
  req,
  operation,
}) => {
  if (operation === 'create' && req.user) {
    data.author = req.user.id
  }
  return data
}

// In custom endpoints or utilities
async function getPublishedPosts(payload: Payload): Promise<Post[]> {
  const result = await payload.find({
    collection: 'posts',
    where: {
      _status: { equals: 'published' },
    },
    sort: '-publishDate',
    limit: 10,
  })
  return result.docs
}
```

---

## Best Practices

1. **One collection per file** - Keep collection configs in separate files under `src/collections/`
2. **Reusable field functions** - Extract common field patterns (slug, SEO, timestamps) into shared utilities
3. **Typed hooks** - Always use generic hook types (`CollectionBeforeChangeHook<Post>`) for type safety
4. **Index frequently queried fields** - Add `index: true` on fields used in `where` clauses
5. **Use `admin.condition`** - Conditionally show/hide fields based on other field values
6. **Use `admin.position: 'sidebar'`** - Place metadata fields in the sidebar to keep the main editor clean
7. **Leverage `defaultValue`** - Set sensible defaults to reduce editor friction
8. **Named tabs for nested data** - Use named tabs when you want data grouped under a key; unnamed for flat structure
9. **Use `filterOptions` on relationships** - Limit relationship options to relevant documents
10. **Enable `focalPoint` and `crop`** on upload collections for responsive images

---

## Anti-Patterns

- Defining all collections in a single file (makes maintenance difficult)
- Using `any` types in hooks instead of generated Payload types
- Not setting `index: true` on fields used in queries and filters
- Storing derived/computed data instead of using `afterRead` hooks
- Using overly permissive access control (`() => true` for write operations)
- Not enabling versioning on content collections that editors will manage
- Hardcoding values in hooks instead of using environment variables or globals
- Creating deeply nested blocks/arrays beyond 3 levels (impacts admin UI performance)
- Using `json` fields when structured field types (group, array) would be more appropriate

---

## Sources & References

- [Payload CMS 3.0 Documentation - Collections](https://payloadcms.com/docs/configuration/collections)
- [Payload CMS 3.0 Documentation - Fields Overview](https://payloadcms.com/docs/fields/overview)
- [Payload CMS 3.0 Documentation - Hooks](https://payloadcms.com/docs/hooks/overview)
- [Payload CMS 3.0 Documentation - Versions & Drafts](https://payloadcms.com/docs/versions/overview)
- [Payload CMS 3.0 Documentation - Upload](https://payloadcms.com/docs/upload/overview)
- [Payload CMS 3.0 Documentation - Access Control](https://payloadcms.com/docs/access-control/overview)
- [Payload CMS Blog - Building with Blocks](https://payloadcms.com/blog/building-with-blocks)
- [Payload CMS GitHub - Example Projects](https://github.com/payloadcms/payload/tree/main/examples)
