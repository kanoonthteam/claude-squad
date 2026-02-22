---
name: payload-api
description: Payload CMS 3.x API patterns — REST API, GraphQL API, local API, access control, authentication, RBAC, custom endpoints, query operators, depth control, populate
---

# Payload CMS 3.x API & Access Control

Production-ready API and access control patterns for Payload CMS 3.x (2025/2026). Covers REST API, GraphQL API, local API, access control patterns, authentication with auth collections, role-based access control (RBAC), custom endpoints, query operators, depth control, and population strategies.

## Table of Contents

1. [API Architecture Overview](#api-architecture-overview)
2. [Local API](#local-api)
3. [REST API](#rest-api)
4. [GraphQL API](#graphql-api)
5. [Query Operators](#query-operators)
6. [Depth Control & Population](#depth-control--population)
7. [Authentication Collections](#authentication-collections)
8. [Access Control Patterns](#access-control-patterns)
9. [Role-Based Access Control (RBAC)](#role-based-access-control-rbac)
10. [Field-Level Access Control](#field-level-access-control)
11. [Custom Endpoints](#custom-endpoints)
12. [API Keys & External Auth](#api-keys--external-auth)
13. [Pagination & Sorting](#pagination--sorting)
14. [Best Practices](#best-practices)
15. [Anti-Patterns](#anti-patterns)
16. [Sources & References](#sources--references)

---

## API Architecture Overview

Payload 3.x provides three API layers, all sharing the same access control and hooks:

- **Local API** - Direct function calls within your Next.js app (server-side). Zero HTTP overhead. Recommended for internal use.
- **REST API** - Standard HTTP endpoints at `/api/{collection-slug}`. Auto-generated from collections.
- **GraphQL API** - Full GraphQL schema at `/api/graphql`. Auto-generated from collections.

All three APIs respect the same access control, hooks, and validation.

```
Next.js App / Server Components
        |
        v
    Local API (payload.find(), payload.create(), etc.)
        |
        v
    Access Control -> Hooks -> Database
        ^
        |
    REST API (/api/posts)  &  GraphQL API (/api/graphql)
        ^
        |
    External Clients (Frontend, Mobile, Third-party)
```

---

## Local API

The local API is the most performant way to interact with Payload data. It bypasses HTTP entirely and runs directly in your Node.js/Next.js process.

### Getting the Payload Instance

```typescript
// In Next.js Server Components, Route Handlers, Server Actions
import { getPayload } from 'payload'
import config from '@payload-config'

export async function getPayloadInstance() {
  return await getPayload({ config })
}

// In Next.js page (Server Component)
export default async function BlogPage() {
  const payload = await getPayload({ config })

  const posts = await payload.find({
    collection: 'posts',
    where: {
      _status: { equals: 'published' },
    },
    sort: '-publishDate',
    limit: 10,
    depth: 2,
  })

  return (
    <div>
      {posts.docs.map((post) => (
        <article key={post.id}>
          <h2>{post.title}</h2>
        </article>
      ))}
    </div>
  )
}
```

### CRUD Operations

```typescript
import { getPayload } from 'payload'
import config from '@payload-config'

const payload = await getPayload({ config })

// CREATE
const newPost = await payload.create({
  collection: 'posts',
  data: {
    title: 'My New Post',
    content: richTextContent,
    author: userId,
    status: 'draft',
  },
  // Optionally pass user for access control
  user: currentUser,
  // Skip access control (use carefully, server-side only)
  overrideAccess: false,
  // Control relationship depth
  depth: 1,
})

// READ - Find many
const posts = await payload.find({
  collection: 'posts',
  where: {
    status: { equals: 'published' },
    author: { equals: userId },
  },
  sort: '-createdAt',
  limit: 20,
  page: 1,
  depth: 2,
})
// Returns: { docs: Post[], totalDocs, totalPages, page, hasNextPage, hasPrevPage, ... }

// READ - Find by ID
const post = await payload.findByID({
  collection: 'posts',
  id: postId,
  depth: 2,
})

// UPDATE
const updated = await payload.update({
  collection: 'posts',
  id: postId,
  data: {
    title: 'Updated Title',
    status: 'published',
  },
})

// UPDATE - Bulk update
const bulkUpdated = await payload.update({
  collection: 'posts',
  where: {
    status: { equals: 'draft' },
    createdAt: { less_than: '2024-01-01' },
  },
  data: {
    status: 'archived',
  },
})

// DELETE
await payload.delete({
  collection: 'posts',
  id: postId,
})

// DELETE - Bulk delete
await payload.delete({
  collection: 'posts',
  where: {
    status: { equals: 'archived' },
  },
})

// COUNT
const count = await payload.count({
  collection: 'posts',
  where: {
    status: { equals: 'published' },
  },
})
// Returns: { totalDocs: number }
```

### Globals (Local API)

```typescript
// Read global
const siteSettings = await payload.findGlobal({
  slug: 'site-settings',
  depth: 1,
})

// Update global
await payload.updateGlobal({
  slug: 'site-settings',
  data: {
    siteName: 'My Updated Site',
    maintenanceMode: false,
  },
})
```

---

## REST API

Payload auto-generates REST endpoints for all collections.

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/{collection}` | Find documents |
| GET | `/api/{collection}/{id}` | Find by ID |
| POST | `/api/{collection}` | Create document |
| PATCH | `/api/{collection}/{id}` | Update document |
| DELETE | `/api/{collection}/{id}` | Delete document |
| GET | `/api/globals/{slug}` | Get global |
| POST | `/api/globals/{slug}` | Update global |

### Query Parameters

```bash
# Find with filters
GET /api/posts?where[status][equals]=published&where[author][equals]=user123

# Pagination
GET /api/posts?limit=10&page=2

# Sorting (prefix with - for descending)
GET /api/posts?sort=-createdAt

# Depth control
GET /api/posts?depth=2

# Select specific fields
GET /api/posts?select[title]=true&select[slug]=true&select[author]=true

# Locale (if i18n configured)
GET /api/posts?locale=es

# Draft mode
GET /api/posts?draft=true
```

### REST API Usage Examples

```typescript
// Frontend fetch example
async function fetchPosts(page = 1) {
  const response = await fetch(
    `${process.env.NEXT_PUBLIC_PAYLOAD_URL}/api/posts?` +
    new URLSearchParams({
      'where[_status][equals]': 'published',
      sort: '-publishDate',
      limit: '10',
      page: String(page),
      depth: '2',
    }),
    {
      headers: {
        'Content-Type': 'application/json',
      },
      // For authenticated requests
      // headers: { Authorization: `JWT ${token}` },
      next: { revalidate: 60 }, // Next.js ISR
    },
  )

  if (!response.ok) throw new Error('Failed to fetch posts')
  return response.json()
}

// Create via REST
async function createPost(data: CreatePostData, token: string) {
  const response = await fetch(`${process.env.NEXT_PUBLIC_PAYLOAD_URL}/api/posts`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `JWT ${token}`,
    },
    body: JSON.stringify(data),
  })

  if (!response.ok) {
    const error = await response.json()
    throw new Error(error.errors?.[0]?.message || 'Failed to create post')
  }
  return response.json()
}
```

---

## GraphQL API

Payload auto-generates a full GraphQL schema from your collections and globals.

### Schema Generation

Each collection generates the following GraphQL types and operations:

- **Query**: `Post`, `Posts` (with pagination), `countPosts`
- **Mutation**: `createPost`, `updatePost`, `deletePost`
- **Types**: `Post`, `Posts` (paginated), input types

### Query Examples

```graphql
# Find posts with pagination
query GetPosts($page: Int, $limit: Int) {
  Posts(
    page: $page
    limit: $limit
    where: { _status: { equals: published } }
    sort: "-publishDate"
  ) {
    docs {
      id
      title
      slug
      publishDate
      author {
        name
        email
      }
      featuredImage {
        url
        alt
        sizes {
          thumbnail {
            url
          }
        }
      }
    }
    totalDocs
    totalPages
    hasNextPage
  }
}

# Find single post by ID
query GetPost($id: String!) {
  Post(id: $id) {
    id
    title
    content
    author {
      name
    }
  }
}

# Create post
mutation CreatePost($data: mutationPostInput!) {
  createPost(data: $data) {
    id
    title
    slug
  }
}

# Update post
mutation UpdatePost($id: String!, $data: mutationPostUpdateInput!) {
  updatePost(id: $id, data: $data) {
    id
    title
    status
  }
}

# Delete post
mutation DeletePost($id: String!) {
  deletePost(id: $id) {
    id
  }
}
```

### GraphQL Client Usage

```typescript
// Using graphql-request
import { GraphQLClient, gql } from 'graphql-request'

const client = new GraphQLClient(`${process.env.PAYLOAD_URL}/api/graphql`, {
  headers: {
    Authorization: `JWT ${token}`,
  },
})

const GET_POSTS = gql`
  query GetPosts($status: Post__status_Input) {
    Posts(where: { _status: { equals: $status } }, limit: 10) {
      docs {
        id
        title
        slug
      }
      totalDocs
    }
  }
`

const data = await client.request(GET_POSTS, { status: 'published' })
```

---

## Query Operators

Payload supports a rich set of query operators for filtering data across all APIs.

```typescript
// Equality
where: { status: { equals: 'published' } }
where: { status: { not_equals: 'draft' } }

// Comparison
where: { price: { greater_than: 100 } }
where: { price: { greater_than_equal: 100 } }
where: { price: { less_than: 500 } }
where: { price: { less_than_equal: 500 } }

// String matching
where: { title: { like: 'payload' } }         // Case-insensitive contains
where: { title: { contains: 'CMS' } }         // Case-sensitive contains
where: { email: { like: '%@gmail.com' } }      // Wildcard

// Inclusion
where: { status: { in: ['published', 'draft'] } }
where: { status: { not_in: ['archived', 'deleted'] } }

// Existence
where: { featuredImage: { exists: true } }
where: { deletedAt: { exists: false } }

// Geo queries (point fields)
where: {
  location: {
    near: [40.7128, -74.0060, 10000, 0],  // [lat, lng, maxDistance, minDistance]
  },
}

// Logical operators
where: {
  or: [
    { status: { equals: 'published' } },
    { author: { equals: currentUserId } },
  ],
}

where: {
  and: [
    { status: { equals: 'published' } },
    { publishDate: { less_than_equal: new Date().toISOString() } },
  ],
}

// Nested relationship queries
where: {
  'author.role': { equals: 'admin' },
  'category.slug': { equals: 'technology' },
}
```

---

## Depth Control & Population

Depth controls how deeply relationships are populated (resolved from IDs to full documents).

```typescript
// depth: 0 - No population, relationships are just IDs
const shallow = await payload.find({
  collection: 'posts',
  depth: 0,
})
// { author: '64abc123...' }

// depth: 1 - Populate direct relationships
const medium = await payload.find({
  collection: 'posts',
  depth: 1,
})
// { author: { id: '64abc123...', name: 'John', role: 'admin' } }

// depth: 2 - Populate nested relationships
const deep = await payload.find({
  collection: 'posts',
  depth: 2,
})
// { author: { id: '...', name: 'John', avatar: { url: '/media/avatar.jpg', ... } } }
```

### Performance Tips for Depth

```typescript
// Use select to limit returned fields (reduces payload size)
const posts = await payload.find({
  collection: 'posts',
  depth: 1,
  select: {
    title: true,
    slug: true,
    author: true,
    featuredImage: true,
  },
})

// Use depth: 0 for list views, depth: 2 for detail views
// This dramatically reduces query time and response size
```

### Default Depth Configuration

```typescript
// payload.config.ts
export default buildConfig({
  defaultDepth: 1, // Global default
  maxDepth: 5,     // Maximum allowed depth
  collections: [
    {
      slug: 'posts',
      defaultPopulate: {
        title: true,
        slug: true,
      },
    },
  ],
})
```

---

## Authentication Collections

Payload has built-in authentication for any collection marked with `auth: true`.

```typescript
// src/collections/Users.ts
import type { CollectionConfig } from 'payload'

export const Users: CollectionConfig = {
  slug: 'users',
  auth: {
    tokenExpiration: 7200, // seconds (2 hours)
    maxLoginAttempts: 5,
    lockTime: 600000, // ms (10 minutes)
    useAPIKey: true,   // Enable API key auth
    depth: 0,          // Depth for user population in req.user
    cookies: {
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      domain: process.env.COOKIE_DOMAIN,
    },
    forgotPassword: {
      generateEmailHTML: ({ token, user }) => {
        return `<p>Reset your password: ${process.env.SITE_URL}/reset-password?token=${token}</p>`
      },
      generateEmailSubject: () => 'Reset your password',
    },
    verify: {
      generateEmailHTML: ({ token, user }) => {
        return `<p>Verify your email: ${process.env.SITE_URL}/verify?token=${token}</p>`
      },
      generateEmailSubject: () => 'Verify your email',
    },
  },
  admin: {
    useAsTitle: 'email',
    defaultColumns: ['email', 'name', 'role'],
    group: 'Admin',
  },
  access: {
    read: () => true,
    create: ({ req: { user } }) => user?.role === 'admin',
    update: ({ req: { user }, id }) => {
      if (user?.role === 'admin') return true
      return user?.id === id // Users can update themselves
    },
    delete: ({ req: { user } }) => user?.role === 'admin',
    admin: ({ req: { user } }) => user?.role === 'admin',
  },
  fields: [
    {
      name: 'name',
      type: 'text',
      required: true,
    },
    {
      name: 'role',
      type: 'select',
      required: true,
      defaultValue: 'editor',
      options: [
        { label: 'Admin', value: 'admin' },
        { label: 'Editor', value: 'editor' },
        { label: 'Viewer', value: 'viewer' },
      ],
      access: {
        update: ({ req: { user } }) => user?.role === 'admin',
      },
      admin: {
        position: 'sidebar',
      },
    },
    {
      name: 'avatar',
      type: 'upload',
      relationTo: 'media',
    },
  ],
}
```

### Auth REST Endpoints

```bash
# Login
POST /api/users/login
{ "email": "user@example.com", "password": "secret" }
# Returns: { user: {...}, token: "jwt...", exp: 1234567890 }

# Logout
POST /api/users/logout

# Get current user (from JWT or cookie)
GET /api/users/me

# Forgot password
POST /api/users/forgot-password
{ "email": "user@example.com" }

# Reset password
POST /api/users/reset-password
{ "token": "reset-token", "password": "new-password" }

# Verify email
POST /api/users/verify/{token}

# Refresh token
POST /api/users/refresh-token

# Unlock account
POST /api/users/unlock
{ "email": "user@example.com" }
```

---

## Access Control Patterns

Access control functions return either `true`, `false`, or a `Where` query constraint.

```typescript
import type { Access } from 'payload'

// Boolean access - all or nothing
const isAdmin: Access = ({ req: { user } }) => {
  return user?.role === 'admin'
}

// Query-based access - returns a Where constraint
const isOwnerOrPublished: Access = ({ req: { user } }) => {
  // Unauthenticated users only see published
  if (!user) {
    return {
      _status: { equals: 'published' },
    }
  }

  // Admins see everything
  if (user.role === 'admin') return true

  // Editors see published + their own drafts
  return {
    or: [
      { _status: { equals: 'published' } },
      { author: { equals: user.id } },
    ],
  }
}

// Using in collection config
export const Posts: CollectionConfig = {
  slug: 'posts',
  access: {
    read: isOwnerOrPublished,
    create: ({ req: { user } }) => Boolean(user),
    update: ({ req: { user }, id }) => {
      if (!user) return false
      if (user.role === 'admin') return true
      return { author: { equals: user.id } }
    },
    delete: isAdmin,
  },
  fields: [/* ... */],
}
```

---

## Role-Based Access Control (RBAC)

### Multi-Role RBAC Pattern

```typescript
// src/access/index.ts
import type { Access, FieldAccess } from 'payload'
import type { User } from '../payload-types'

type Role = 'admin' | 'editor' | 'author' | 'viewer'

// Collection-level access helpers
export const isRole = (...roles: Role[]): Access => {
  return ({ req: { user } }) => {
    if (!user) return false
    return roles.includes((user as User).role as Role)
  }
}

export const isAdminOrSelf: Access = ({ req: { user }, id }) => {
  if (!user) return false
  if ((user as User).role === 'admin') return true
  return (user as User).id === id
}

export const isPublishedOrHasAccess: Access = ({ req: { user } }) => {
  if (!user) {
    return { _status: { equals: 'published' } }
  }

  const userRole = (user as User).role

  if (userRole === 'admin' || userRole === 'editor') return true

  if (userRole === 'author') {
    return {
      or: [
        { _status: { equals: 'published' } },
        { author: { equals: user.id } },
      ],
    }
  }

  return { _status: { equals: 'published' } }
}

// Field-level access helpers
export const isAdminFieldAccess: FieldAccess = ({ req: { user } }) => {
  return (user as User)?.role === 'admin'
}

// Usage in collection
export const Posts: CollectionConfig = {
  slug: 'posts',
  access: {
    read: isPublishedOrHasAccess,
    create: isRole('admin', 'editor', 'author'),
    update: isRole('admin', 'editor'),
    delete: isRole('admin'),
  },
  fields: [
    {
      name: 'title',
      type: 'text',
      required: true,
    },
    {
      name: 'internalNotes',
      type: 'textarea',
      access: {
        read: isAdminFieldAccess,
        update: isAdminFieldAccess,
      },
    },
  ],
}
```

### Tenant-Based Access (Multi-Tenancy)

```typescript
// src/access/tenantAccess.ts
import type { Access } from 'payload'

export const tenantAccess: Access = ({ req: { user } }) => {
  if (!user) return false

  // Super admin sees all
  if (user.role === 'superadmin') return true

  // Regular users only see their tenant's data
  return {
    tenant: { equals: user.tenant },
  }
}

// Collection with tenant isolation
export const Products: CollectionConfig = {
  slug: 'products',
  access: {
    read: tenantAccess,
    create: tenantAccess,
    update: tenantAccess,
    delete: tenantAccess,
  },
  hooks: {
    beforeChange: [
      // Auto-assign tenant on create
      ({ data, req, operation }) => {
        if (operation === 'create' && req.user) {
          data.tenant = req.user.tenant
        }
        return data
      },
    ],
  },
  fields: [
    { name: 'name', type: 'text', required: true },
    {
      name: 'tenant',
      type: 'relationship',
      relationTo: 'tenants',
      required: true,
      admin: {
        position: 'sidebar',
        readOnly: true,
        condition: (data) => Boolean(data?.tenant),
      },
    },
  ],
}
```

---

## Field-Level Access Control

```typescript
{
  name: 'salary',
  type: 'number',
  access: {
    // Can read own salary, admins can read all
    read: ({ req: { user }, id, doc }) => {
      if (user?.role === 'admin') return true
      return user?.id === doc?.id
    },
    // Only admins can set salary
    create: ({ req: { user } }) => user?.role === 'admin',
    update: ({ req: { user } }) => user?.role === 'admin',
  },
}

{
  name: 'role',
  type: 'select',
  options: ['admin', 'editor', 'viewer'],
  access: {
    // Only admins can change roles
    update: ({ req: { user } }) => user?.role === 'admin',
    // Anyone authenticated can read roles
    read: ({ req: { user } }) => Boolean(user),
  },
}
```

---

## Custom Endpoints

Add custom REST endpoints to your Payload application.

```typescript
// payload.config.ts or in collection config
export default buildConfig({
  endpoints: [
    {
      path: '/health',
      method: 'get',
      handler: (req) => {
        return Response.json({ status: 'ok', timestamp: new Date().toISOString() })
      },
    },
    {
      path: '/search',
      method: 'get',
      handler: async (req) => {
        const { searchParams } = new URL(req.url)
        const query = searchParams.get('q')

        if (!query) {
          return Response.json({ error: 'Query parameter "q" is required' }, { status: 400 })
        }

        const [posts, pages] = await Promise.all([
          req.payload.find({
            collection: 'posts',
            where: {
              or: [
                { title: { like: query } },
                { excerpt: { like: query } },
              ],
              _status: { equals: 'published' },
            },
            limit: 5,
            depth: 0,
          }),
          req.payload.find({
            collection: 'pages',
            where: {
              title: { like: query },
              _status: { equals: 'published' },
            },
            limit: 5,
            depth: 0,
          }),
        ])

        return Response.json({
          posts: posts.docs,
          pages: pages.docs,
          total: posts.totalDocs + pages.totalDocs,
        })
      },
    },
  ],
})
```

### Collection-Level Custom Endpoints

```typescript
export const Posts: CollectionConfig = {
  slug: 'posts',
  endpoints: [
    {
      path: '/popular',
      method: 'get',
      handler: async (req) => {
        const posts = await req.payload.find({
          collection: 'posts',
          where: {
            _status: { equals: 'published' },
          },
          sort: '-viewCount',
          limit: 10,
          depth: 1,
        })

        return Response.json(posts)
      },
    },
    {
      path: '/:id/increment-views',
      method: 'post',
      handler: async (req) => {
        const id = req.routeParams?.id as string
        const post = await req.payload.findByID({
          collection: 'posts',
          id,
          depth: 0,
        })

        const updated = await req.payload.update({
          collection: 'posts',
          id,
          data: {
            viewCount: (post.viewCount || 0) + 1,
          },
          depth: 0,
        })

        return Response.json({ viewCount: updated.viewCount })
      },
    },
  ],
  fields: [/* ... */],
}
```

---

## API Keys & External Auth

### API Key Authentication

```typescript
export const Users: CollectionConfig = {
  slug: 'users',
  auth: {
    useAPIKey: true, // Enables API key auth
  },
  fields: [/* ... */],
}
```

```bash
# Using API key in requests
GET /api/posts
Authorization: users API-Key your-api-key-here
```

### OAuth / External Auth Integration

```typescript
// Using payload-authjs plugin for OAuth
import { authjsPlugin } from 'payload-authjs'
import GitHub from '@auth/core/providers/github'
import Google from '@auth/core/providers/google'

export default buildConfig({
  plugins: [
    authjsPlugin({
      providers: [
        GitHub({
          clientId: process.env.GITHUB_CLIENT_ID!,
          clientSecret: process.env.GITHUB_CLIENT_SECRET!,
        }),
        Google({
          clientId: process.env.GOOGLE_CLIENT_ID!,
          clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
        }),
      ],
    }),
  ],
})
```

---

## Pagination & Sorting

```typescript
// Paginated query
const result = await payload.find({
  collection: 'posts',
  page: 1,
  limit: 20,
  sort: '-createdAt', // Descending
})

// Result shape
interface PaginatedDocs<T> {
  docs: T[]
  totalDocs: number
  limit: number
  totalPages: number
  page: number
  pagingCounter: number
  hasPrevPage: boolean
  hasNextPage: boolean
  prevPage: number | null
  nextPage: number | null
}

// Multi-field sorting
const sorted = await payload.find({
  collection: 'posts',
  sort: '-featured,publishDate', // Featured first, then by date
})

// Cursor-based pagination pattern (for large datasets)
async function cursorPaginate(cursor: string | null, limit: number) {
  const where: any = { _status: { equals: 'published' } }

  if (cursor) {
    where.createdAt = { less_than: cursor }
  }

  const result = await payload.find({
    collection: 'posts',
    where,
    sort: '-createdAt',
    limit: limit + 1, // Fetch one extra to determine hasMore
    depth: 0,
  })

  const hasMore = result.docs.length > limit
  const docs = hasMore ? result.docs.slice(0, limit) : result.docs
  const nextCursor = hasMore ? docs[docs.length - 1].createdAt : null

  return { docs, hasMore, nextCursor }
}
```

---

## Best Practices

1. **Use the Local API for server-side operations** - Zero HTTP overhead, full type safety
2. **Minimize depth** - Use `depth: 0` for lists, `depth: 1-2` for detail views
3. **Use `select` to limit returned fields** - Reduces response size and query time
4. **Centralize access control functions** - Keep them in `src/access/` for reuse
5. **Return `Where` constraints from access control** - More performant than filtering in hooks
6. **Use `overrideAccess: false` explicitly** - Default is `true` for local API, be explicit
7. **Enable API keys for external integrations** - Safer than sharing user credentials
8. **Use custom endpoints for complex operations** - Keep built-in CRUD clean
9. **Validate at the field level** - Let Payload handle validation before access control
10. **Log access control decisions** - Add logging in access functions for debugging

---

## Anti-Patterns

- Using `overrideAccess: true` without understanding it bypasses all access control
- Setting `depth` higher than needed (causes N+1 queries and large responses)
- Not using query-based access control (filtering in afterRead is slower)
- Hardcoding user IDs in access control functions
- Exposing internal fields (internalNotes, adminComments) without field-level access
- Not using `select` on list queries (returns full documents unnecessarily)
- Creating custom endpoints for operations the built-in API already handles
- Not rate-limiting public API endpoints
- Storing sensitive data without field-level read access control

---

## Sources & References

- [Payload CMS 3.0 Documentation - Local API](https://payloadcms.com/docs/local-api/overview)
- [Payload CMS 3.0 Documentation - REST API](https://payloadcms.com/docs/rest-api/overview)
- [Payload CMS 3.0 Documentation - GraphQL API](https://payloadcms.com/docs/graphql/overview)
- [Payload CMS 3.0 Documentation - Access Control](https://payloadcms.com/docs/access-control/overview)
- [Payload CMS 3.0 Documentation - Authentication](https://payloadcms.com/docs/authentication/overview)
- [Payload CMS 3.0 Documentation - Query Operators](https://payloadcms.com/docs/queries/overview)
- [Payload CMS 3.0 Documentation - Custom Endpoints](https://payloadcms.com/docs/rest-api/overview#custom-endpoints)
- [Payload CMS Blog - Access Control Patterns](https://payloadcms.com/blog/access-control)
