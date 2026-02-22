---
name: payload-admin
description: Payload CMS 3.x admin panel customization — custom React components, live preview, custom views, dashboard widgets, Next.js admin, custom CSS, field-level admin config, branding
---

# Payload CMS 3.x Admin Panel Customization

Production-ready admin panel customization patterns for Payload CMS 3.x (2025/2026). Covers custom React components, live preview configuration, custom views and dashboard widgets, Next.js-based admin UI, CSS theming, field-level admin configuration, and branding.

## Table of Contents

1. [Admin Panel Architecture in 3.x](#admin-panel-architecture-in-3x)
2. [Branding & Theming](#branding--theming)
3. [Custom Components Overview](#custom-components-overview)
4. [Field-Level Admin Configuration](#field-level-admin-configuration)
5. [Custom Field Components](#custom-field-components)
6. [Custom Cell Components](#custom-cell-components)
7. [Custom Views](#custom-views)
8. [Dashboard Customization](#dashboard-customization)
9. [Live Preview](#live-preview)
10. [Row Labels & Description Components](#row-labels--description-components)
11. [Before & After Components](#before--after-components)
12. [Custom CSS & Styling](#custom-css--styling)
13. [Admin Conditional Logic](#admin-conditional-logic)
14. [Best Practices](#best-practices)
15. [Anti-Patterns](#anti-patterns)
16. [Sources & References](#sources--references)

---

## Admin Panel Architecture in 3.x

Payload 3.x fully integrates the admin panel with Next.js. The admin UI is a Next.js app that lives inside your project. All custom components are standard React Server Components (RSC) or Client Components. Custom components are referenced by file path strings, not direct imports.

```
src/
  app/
    (payload)/           # Payload admin routes (auto-generated)
      admin/
        [[...segments]]/
          page.tsx
      api/
        [...slug]/
          route.ts
  admin/
    components/          # Custom admin components
      BeforeDashboard.tsx
      CustomField.tsx
      Logo.tsx
  collections/
  payload.config.ts
```

### Key Differences from Payload 2.x

- Components are referenced by **file path strings** (not imported directly)
- React Server Components are supported
- Client Components must use `'use client'` directive
- The admin panel uses Next.js App Router conventions
- Custom CSS uses Next.js CSS Module patterns

---

## Branding & Theming

```typescript
// payload.config.ts
import { buildConfig } from 'payload'

export default buildConfig({
  admin: {
    meta: {
      titleSuffix: '- My CMS',
      description: 'Content management for My App',
      icons: [
        {
          rel: 'icon',
          type: 'image/png',
          url: '/favicon.png',
        },
      ],
      openGraph: {
        title: 'My CMS Admin',
        description: 'Content management panel',
        images: [{ url: '/og-image.png' }],
      },
    },
    components: {
      graphics: {
        Logo: '/src/admin/components/Logo',
        Icon: '/src/admin/components/Icon',
      },
    },
    avatar: {
      Component: '/src/admin/components/Avatar',
    },
  },
})
```

### Logo Component

```tsx
// src/admin/components/Logo.tsx
import React from 'react'
import Image from 'next/image'

const Logo: React.FC = () => {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
      <Image
        src="/logo.svg"
        alt="My CMS"
        width={150}
        height={40}
        priority
      />
    </div>
  )
}

export default Logo
```

### Icon Component (Favicon in Nav)

```tsx
// src/admin/components/Icon.tsx
import React from 'react'
import Image from 'next/image'

const Icon: React.FC = () => {
  return <Image src="/icon.svg" alt="My CMS" width={24} height={24} />
}

export default Icon
```

---

## Custom Components Overview

In Payload 3.x, all custom components are referenced by their file path relative to the project root. Payload resolves and renders them at runtime.

```typescript
// payload.config.ts - Component locations
export default buildConfig({
  admin: {
    components: {
      // Global components
      graphics: {
        Logo: '/src/admin/components/Logo',
        Icon: '/src/admin/components/Icon',
      },
      // Before/After injection points
      beforeDashboard: ['/src/admin/components/BeforeDashboard'],
      afterDashboard: ['/src/admin/components/AfterDashboard'],
      beforeLogin: ['/src/admin/components/BeforeLogin'],
      afterLogin: ['/src/admin/components/AfterLogin'],
      beforeNavLinks: ['/src/admin/components/BeforeNavLinks'],
      afterNavLinks: ['/src/admin/components/AfterNavLinks'],
      // Navigation
      Nav: '/src/admin/components/CustomNav',
      // Logout button
      logout: {
        Button: '/src/admin/components/LogoutButton',
      },
      // Actions (top-right header area)
      actions: ['/src/admin/components/HeaderAction'],
    },
  },
})
```

### Component Props Pattern

All admin components receive specific props from Payload. Use the exported types.

```tsx
// src/admin/components/CustomField.tsx
'use client'

import React, { useCallback } from 'react'
import { useField } from '@payloadcms/ui'
import type { TextFieldClientComponent } from 'payload'

const CustomTextField: TextFieldClientComponent = ({ field, path }) => {
  const { value, setValue } = useField<string>({ path })

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setValue(e.target.value)
    },
    [setValue],
  )

  return (
    <div className="field-type text">
      <label className="field-label" htmlFor={path}>
        {field.label || field.name}
        {field.required && <span className="required">*</span>}
      </label>
      <input
        id={path}
        type="text"
        value={value || ''}
        onChange={handleChange}
        placeholder={field.admin?.placeholder}
      />
      {field.admin?.description && (
        <div className="field-description">{field.admin.description}</div>
      )}
    </div>
  )
}

export default CustomTextField
```

---

## Field-Level Admin Configuration

Every field supports an `admin` property for controlling its appearance in the admin panel.

```typescript
{
  name: 'title',
  type: 'text',
  required: true,
  admin: {
    // Position in the layout
    position: 'sidebar', // 'sidebar' or default (main area)

    // Width (for fields in the main area)
    width: '50%',

    // Conditional display
    condition: (data, siblingData) => {
      return siblingData.type === 'custom'
    },

    // Visual style
    style: {
      backgroundColor: '#f5f5f5',
      padding: '16px',
      borderRadius: '4px',
    },

    // Description text below the field
    description: 'Enter a descriptive title for SEO purposes',

    // Placeholder text
    placeholder: 'Enter title...',

    // Read-only field
    readOnly: true,

    // Hidden from admin UI (still in API)
    hidden: true,

    // Disable edit (visible but not editable)
    disabled: true,

    // Custom CSS class
    className: 'custom-title-field',

    // Initial collapsed state (for group, array, collapsible)
    initCollapsed: true,

    // Custom components
    components: {
      Field: '/src/admin/components/CustomTitleField',
      Cell: '/src/admin/components/CustomTitleCell',
      Description: '/src/admin/components/TitleDescription',
      Label: '/src/admin/components/TitleLabel',
      Error: '/src/admin/components/TitleError',
    },
  },
}
```

### Layout with Row Field

Use the `row` field type to place fields side by side.

```typescript
{
  type: 'row',
  fields: [
    {
      name: 'firstName',
      type: 'text',
      required: true,
      admin: { width: '50%' },
    },
    {
      name: 'lastName',
      type: 'text',
      required: true,
      admin: { width: '50%' },
    },
  ],
}
```

### Collapsible Fields

```typescript
{
  type: 'collapsible',
  label: 'Advanced Settings',
  admin: {
    initCollapsed: true,
  },
  fields: [
    { name: 'cssClass', type: 'text' },
    { name: 'htmlId', type: 'text' },
    {
      name: 'animation',
      type: 'select',
      options: ['none', 'fadeIn', 'slideUp'],
      defaultValue: 'none',
    },
  ],
}
```

---

## Custom Field Components

### Color Picker Field

```tsx
// src/admin/components/ColorPickerField.tsx
'use client'

import React, { useCallback } from 'react'
import { useField } from '@payloadcms/ui'
import type { TextFieldClientComponent } from 'payload'
import './ColorPickerField.scss'

const ColorPickerField: TextFieldClientComponent = ({ field, path }) => {
  const { value, setValue } = useField<string>({ path })

  const presetColors = ['#000000', '#FFFFFF', '#FF0000', '#00FF00', '#0000FF', '#FFD700']

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setValue(e.target.value)
    },
    [setValue],
  )

  return (
    <div className="color-picker-field">
      <label className="field-label">
        {typeof field.label === 'string' ? field.label : field.name}
      </label>
      <div className="color-picker-controls">
        <input
          type="color"
          value={value || '#000000'}
          onChange={handleChange}
        />
        <input
          type="text"
          value={value || ''}
          onChange={handleChange}
          placeholder="#000000"
          pattern="^#[0-9A-Fa-f]{6}$"
        />
      </div>
      <div className="color-presets">
        {presetColors.map((color) => (
          <button
            key={color}
            type="button"
            className="color-preset"
            style={{ backgroundColor: color }}
            onClick={() => setValue(color)}
            aria-label={`Select ${color}`}
          />
        ))}
      </div>
      {value && (
        <div
          className="color-preview"
          style={{ backgroundColor: value, width: '100%', height: '30px', borderRadius: '4px' }}
        />
      )}
    </div>
  )
}

export default ColorPickerField
```

### Using Custom Components in Collections

```typescript
// In collection config
{
  name: 'brandColor',
  type: 'text',
  admin: {
    components: {
      Field: '/src/admin/components/ColorPickerField',
    },
  },
}
```

---

## Custom Cell Components

Cell components render content in the list view table.

```tsx
// src/admin/components/StatusCell.tsx
'use client'

import React from 'react'
import type { DefaultCellComponentProps } from 'payload'

const StatusCell: React.FC<DefaultCellComponentProps> = ({ cellData }) => {
  const statusColors: Record<string, string> = {
    draft: '#f0ad4e',
    published: '#5cb85c',
    archived: '#999999',
  }

  const status = cellData as string

  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: '6px',
        padding: '2px 8px',
        borderRadius: '12px',
        backgroundColor: `${statusColors[status] || '#ccc'}20`,
        color: statusColors[status] || '#666',
        fontSize: '13px',
        fontWeight: 500,
      }}
    >
      <span
        style={{
          width: '8px',
          height: '8px',
          borderRadius: '50%',
          backgroundColor: statusColors[status] || '#ccc',
        }}
      />
      {status}
    </span>
  )
}

export default StatusCell
```

```typescript
// In collection config
{
  name: 'status',
  type: 'select',
  options: ['draft', 'published', 'archived'],
  admin: {
    components: {
      Cell: '/src/admin/components/StatusCell',
    },
  },
}
```

---

## Custom Views

Custom views allow you to add entirely new pages to the admin panel.

### Collection-Level Custom Views

```typescript
// payload.config.ts
export default buildConfig({
  admin: {
    components: {
      views: {
        analytics: {
          Component: '/src/admin/views/Analytics',
          path: '/analytics',
          exact: true,
        },
        settings: {
          Component: '/src/admin/views/Settings',
          path: '/settings',
          exact: true,
        },
      },
    },
  },
})
```

### Custom View Component

```tsx
// src/admin/views/Analytics.tsx
import React from 'react'
import { Gutter } from '@payloadcms/ui'
import type { AdminViewProps } from 'payload'

const AnalyticsView: React.FC<AdminViewProps> = ({ initPageResult, params, searchParams }) => {
  return (
    <Gutter>
      <h1>Content Analytics</h1>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '20px', marginTop: '24px' }}>
        <div style={{ padding: '24px', backgroundColor: 'var(--theme-elevation-50)', borderRadius: '8px' }}>
          <h3>Total Posts</h3>
          <p style={{ fontSize: '36px', fontWeight: 'bold' }}>142</p>
        </div>
        <div style={{ padding: '24px', backgroundColor: 'var(--theme-elevation-50)', borderRadius: '8px' }}>
          <h3>Published</h3>
          <p style={{ fontSize: '36px', fontWeight: 'bold' }}>98</p>
        </div>
        <div style={{ padding: '24px', backgroundColor: 'var(--theme-elevation-50)', borderRadius: '8px' }}>
          <h3>Drafts</h3>
          <p style={{ fontSize: '36px', fontWeight: 'bold' }}>44</p>
        </div>
      </div>
    </Gutter>
  )
}

export default AnalyticsView
```

### Adding Navigation Links

```tsx
// src/admin/components/AfterNavLinks.tsx
'use client'

import React from 'react'
import Link from 'next/link'
import { useConfig } from '@payloadcms/ui'

const AfterNavLinks: React.FC = () => {
  const {
    config: {
      routes: { admin: adminRoute },
    },
  } = useConfig()

  return (
    <>
      <Link href={`${adminRoute}/analytics`}>
        Analytics
      </Link>
      <Link href={`${adminRoute}/settings`}>
        Settings
      </Link>
    </>
  )
}

export default AfterNavLinks
```

---

## Dashboard Customization

### Before Dashboard Component

```tsx
// src/admin/components/BeforeDashboard.tsx
import React from 'react'
import { Gutter } from '@payloadcms/ui'
import type { ServerComponentProps } from 'payload'

const BeforeDashboard: React.FC<ServerComponentProps> = async ({ payload }) => {
  // Fetch data using the local API (server component)
  const recentPosts = await payload.find({
    collection: 'posts',
    limit: 5,
    sort: '-createdAt',
  })

  const publishedCount = await payload.count({
    collection: 'posts',
    where: { _status: { equals: 'published' } },
  })

  return (
    <Gutter>
      <div style={{ marginBottom: '24px' }}>
        <h2>Welcome Back</h2>
        <p>You have {publishedCount.totalDocs} published posts and {recentPosts.totalDocs} total posts.</p>
      </div>
      <div style={{ marginBottom: '24px' }}>
        <h3>Recent Activity</h3>
        <ul>
          {recentPosts.docs.map((post) => (
            <li key={post.id}>
              <strong>{post.title}</strong> - {new Date(post.createdAt).toLocaleDateString()}
            </li>
          ))}
        </ul>
      </div>
    </Gutter>
  )
}

export default BeforeDashboard
```

```typescript
// payload.config.ts
export default buildConfig({
  admin: {
    components: {
      beforeDashboard: ['/src/admin/components/BeforeDashboard'],
      afterDashboard: ['/src/admin/components/AfterDashboard'],
    },
  },
})
```

---

## Live Preview

Payload 3.x supports live preview, showing real-time content changes on your frontend.

### Configuration

```typescript
// payload.config.ts
export default buildConfig({
  admin: {
    livePreview: {
      // Breakpoints for responsive preview
      breakpoints: [
        { label: 'Mobile', name: 'mobile', width: 375, height: 667 },
        { label: 'Tablet', name: 'tablet', width: 768, height: 1024 },
        { label: 'Desktop', name: 'desktop', width: 1440, height: 900 },
      ],
    },
  },
  collections: [
    {
      slug: 'pages',
      admin: {
        livePreview: {
          url: ({ data, locale }) => {
            return `${process.env.NEXT_PUBLIC_SITE_URL}/${data.slug}${locale ? `?locale=${locale.code}` : ''}`
          },
        },
      },
      fields: [/* ... */],
    },
  ],
})
```

### Frontend Integration (Next.js)

```tsx
// app/[slug]/page.tsx
import { RefreshRouteOnSave } from './RefreshRouteOnSave'

export default async function Page({ params }: { params: { slug: string } }) {
  const page = await getPage(params.slug)

  return (
    <>
      <RefreshRouteOnSave />
      <main>
        <h1>{page.title}</h1>
        {/* render page content */}
      </main>
    </>
  )
}

// app/[slug]/RefreshRouteOnSave.tsx
'use client'

import { RefreshRouteOnSave as PayloadLivePreview } from '@payloadcms/live-preview-react'
import { useRouter } from 'next/navigation'

export const RefreshRouteOnSave: React.FC = () => {
  const router = useRouter()

  return (
    <PayloadLivePreview
      serverURL={process.env.NEXT_PUBLIC_PAYLOAD_URL || ''}
      refresh={() => router.refresh()}
    />
  )
}
```

### useLivePreview Hook (Real-Time Field Updates)

```tsx
'use client'

import { useLivePreview } from '@payloadcms/live-preview-react'
import type { Page as PageType } from '@/payload-types'

export const PageClient: React.FC<{ initialData: PageType }> = ({ initialData }) => {
  const { data } = useLivePreview<PageType>({
    initialData,
    serverURL: process.env.NEXT_PUBLIC_PAYLOAD_URL || '',
    depth: 2,
  })

  return (
    <main>
      <h1>{data.title}</h1>
      {/* Content updates in real-time as editors type */}
    </main>
  )
}
```

---

## Row Labels & Description Components

### Custom Row Label for Array Items

```tsx
// src/admin/components/SocialLinkRowLabel.tsx
'use client'

import React from 'react'
import { useRowLabel } from '@payloadcms/ui'

const SocialLinkRowLabel: React.FC = () => {
  const { data, rowNumber } = useRowLabel<{ platform: string; url: string }>()

  return (
    <span>
      {data?.platform
        ? `${data.platform.charAt(0).toUpperCase() + data.platform.slice(1)} - ${data.url || 'No URL'}`
        : `Social Link ${String(rowNumber).padStart(2, '0')}`}
    </span>
  )
}

export default SocialLinkRowLabel
```

```typescript
// In collection config
{
  name: 'socialLinks',
  type: 'array',
  admin: {
    components: {
      RowLabel: '/src/admin/components/SocialLinkRowLabel',
    },
  },
  fields: [/* ... */],
}
```

---

## Before & After Components

Payload provides injection points throughout the admin panel.

```typescript
// payload.config.ts
export default buildConfig({
  admin: {
    components: {
      // Global injection points
      beforeLogin: ['/src/admin/components/LoginBanner'],
      afterLogin: ['/src/admin/components/LoginFooter'],
      beforeDashboard: ['/src/admin/components/DashboardStats'],
      afterDashboard: ['/src/admin/components/RecentActivity'],
      beforeNavLinks: ['/src/admin/components/NavHeader'],
      afterNavLinks: ['/src/admin/components/NavFooter'],
    },
  },
  collections: [
    {
      slug: 'posts',
      admin: {
        components: {
          // Collection-specific injection points
          beforeListTable: ['/src/admin/components/PostsFilter'],
          afterListTable: ['/src/admin/components/PostsPagination'],
          edit: {
            beforeFields: ['/src/admin/components/PostWarning'],
            afterFields: ['/src/admin/components/PostPreview'],
          },
        },
      },
      fields: [/* ... */],
    },
  ],
})
```

---

## Custom CSS & Styling

### Using Payload CSS Variables

Payload exposes CSS variables for consistent theming. Use these in custom components.

```scss
// src/admin/components/CustomComponent.scss
.custom-component {
  background-color: var(--theme-elevation-50);
  border: 1px solid var(--theme-elevation-150);
  border-radius: var(--style-radius-s);
  padding: var(--base);
  color: var(--theme-text);

  &__header {
    font-size: var(--font-size-large);
    font-weight: 600;
    margin-bottom: var(--base);
    color: var(--theme-text);
  }

  &__body {
    font-size: var(--font-size-small);
    color: var(--theme-elevation-600);
  }

  // Dark mode is handled automatically via CSS variables
  // No need for explicit dark mode styles
}

// Available CSS variables (partial list):
// --theme-bg               (background)
// --theme-text             (text color)
// --theme-elevation-50     (subtle background)
// --theme-elevation-100    (borders, separators)
// --theme-elevation-150    (darker borders)
// --theme-elevation-200    (hover states)
// --theme-elevation-400    (secondary text)
// --theme-elevation-600    (muted text)
// --theme-success-500      (success green)
// --theme-error-500        (error red)
// --theme-warning-500      (warning yellow)
// --base                   (base spacing unit)
// --font-size-small
// --font-size-large
// --style-radius-s         (small border radius)
// --style-radius-m         (medium border radius)
```

### Global Admin CSS Override

```typescript
// payload.config.ts
export default buildConfig({
  admin: {
    importMap: {
      baseDir: path.resolve(__dirname),
    },
    // Custom global CSS
    css: '/src/admin/styles/global.scss',
  },
})
```

```scss
// src/admin/styles/global.scss

// Override default styles
.collection-list {
  .cell-title {
    font-weight: 600;
  }
}

// Custom status badges
.status-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 10px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 500;

  &--published {
    background-color: rgba(92, 184, 92, 0.15);
    color: #3d8b3d;
  }

  &--draft {
    background-color: rgba(240, 173, 78, 0.15);
    color: #c77c00;
  }
}
```

---

## Admin Conditional Logic

Use `admin.condition` to dynamically show/hide fields based on document data.

```typescript
{
  name: 'type',
  type: 'select',
  options: [
    { label: 'Internal Link', value: 'internal' },
    { label: 'External Link', value: 'external' },
    { label: 'Custom', value: 'custom' },
  ],
},
{
  name: 'internalLink',
  type: 'relationship',
  relationTo: ['pages', 'posts'],
  admin: {
    condition: (data, siblingData) => siblingData?.type === 'internal',
  },
},
{
  name: 'externalUrl',
  type: 'text',
  admin: {
    condition: (data, siblingData) => siblingData?.type === 'external',
  },
},
{
  name: 'customHtml',
  type: 'code',
  admin: {
    language: 'html',
    condition: (data, siblingData) => siblingData?.type === 'custom',
  },
},
```

### Nested Conditional Logic

```typescript
// Show SEO fields only when status is published
{
  name: 'seo',
  type: 'group',
  admin: {
    condition: (data) => data._status === 'published' || data.status === 'published',
  },
  fields: [
    {
      name: 'title',
      type: 'text',
      maxLength: 60,
      admin: {
        description: ({ value }) =>
          value ? `${value.length}/60 characters` : '0/60 characters',
      },
    },
    {
      name: 'description',
      type: 'textarea',
      maxLength: 160,
    },
  ],
}
```

---

## Best Practices

1. **Use file path strings for components** - Payload 3.x resolves components by path, not import
2. **Prefer Server Components** - Use RSC for data-fetching components (BeforeDashboard, custom views)
3. **Add `'use client'`** - Only for components that need interactivity (field components, hooks)
4. **Use Payload CSS variables** - Ensures dark mode compatibility and consistent styling
5. **Keep custom components simple** - Delegate logic to hooks and access control, not UI
6. **Use `admin.condition`** - Show fields contextually to reduce editor confusion
7. **Configure `useAsTitle`** - Always set this on content collections for meaningful list displays
8. **Set `defaultColumns`** - Configure which columns appear in the list view
9. **Use `admin.group`** - Group related collections in the sidebar navigation
10. **Leverage `admin.position: 'sidebar'`** - Place metadata in the sidebar, content in the main area
11. **Use `listSearchableFields`** - Configure which fields are searchable in the list view
12. **Set `admin.description`** - Add helpful descriptions to guide editors

---

## Anti-Patterns

- Importing components directly instead of using file path strings (breaks in Payload 3.x)
- Using inline styles extensively instead of CSS variables (breaks dark mode)
- Creating overly complex custom field components when built-in fields suffice
- Not using `admin.condition` and showing irrelevant fields to editors
- Missing `'use client'` directive on interactive components (renders as RSC, fails silently)
- Overriding Payload's internal CSS classes directly (breaks on updates)
- Not setting `useAsTitle` on content collections (shows IDs in lists)
- Fetching data in client components when server components would work

---

## Sources & References

- [Payload CMS 3.0 Documentation - Admin Panel Overview](https://payloadcms.com/docs/admin/overview)
- [Payload CMS 3.0 Documentation - Custom Components](https://payloadcms.com/docs/admin/components)
- [Payload CMS 3.0 Documentation - Live Preview](https://payloadcms.com/docs/live-preview/overview)
- [Payload CMS 3.0 Documentation - Custom Views](https://payloadcms.com/docs/admin/views)
- [Payload CMS 3.0 Documentation - Admin Field Config](https://payloadcms.com/docs/fields/overview#admin-options)
- [Payload CMS Blog - Admin Panel Customization Guide](https://payloadcms.com/blog/admin-panel-customization)
- [Payload CMS GitHub - Website Template (admin examples)](https://github.com/payloadcms/payload/tree/main/templates/website)
- [Payload CMS 3.0 Documentation - Swap in Custom Components](https://payloadcms.com/docs/admin/components#swapping-in-custom-components)
