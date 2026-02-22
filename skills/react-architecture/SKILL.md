---
name: react-architecture
description: React 19 Server Components, Next.js 15 App Router, project structure, code splitting, error boundaries, and streaming patterns
---

# React Architecture & Server Components

Production-ready architecture patterns for React 19 and Next.js 15. Covers Server Components, Server Actions, App Router, project structure, code splitting, error boundaries, streaming with Suspense, and authentication.

## Table of Contents

1. [React 19 Server Components](#react-19-server-components)
2. [Server Actions](#server-actions)
3. [Component Composition Patterns](#component-composition-patterns)
4. [Streaming with Suspense](#streaming-with-suspense)
5. [React Compiler](#react-compiler)
6. [Code Splitting & Dynamic Imports](#code-splitting--dynamic-imports)
7. [Error Boundaries](#error-boundaries)
8. [Next.js App Router Structure](#nextjs-app-router-structure)
9. [Authentication with Auth.js v5](#authentication-with-authjs-v5)
10. [Middleware Protection](#middleware-protection)
11. [TypeScript Patterns](#typescript-patterns)
12. [Best Practices](#best-practices)
13. [Anti-Patterns](#anti-patterns)

---

## React 19 Server Components

All components are Server Components by default in React 19 + Next.js 15. Mark with `'use client'` only when needed for interactivity.

```tsx
// app/dashboard/page.tsx (Server Component - no directive needed)
import { db } from '@/lib/db';
import { UserList } from '@/components/UserList';

export default async function DashboardPage() {
  const users = await db.user.findMany({
    select: { id: true, name: true, email: true },
  });

  return (
    <main>
      <h1>Dashboard</h1>
      <UserList users={users} />
    </main>
  );
}
```

```tsx
// components/UserList.tsx (Client Component - interactive)
'use client';

import { useState } from 'react';
import type { User } from '@/types';

export function UserList({ users }: { users: User[] }) {
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <ul>
      {users.map((user) => (
        <li
          key={user.id}
          onClick={() => setSelected(user.id)}
          className={selected === user.id ? 'bg-blue-100' : ''}
        >
          {user.name}
        </li>
      ))}
    </ul>
  );
}
```

---

## Server Actions

```tsx
// app/actions/users.ts
'use server';

import { db } from '@/lib/db';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';

const createUserSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
});

export async function createUser(formData: FormData) {
  const parsed = createUserSchema.safeParse({
    name: formData.get('name'),
    email: formData.get('email'),
  });

  if (!parsed.success) {
    return { error: parsed.error.flatten().fieldErrors };
  }

  try {
    const user = await db.user.create({ data: parsed.data });
    revalidatePath('/users');
    return { success: true, user };
  } catch (error) {
    return { error: 'Failed to create user' };
  }
}
```

```tsx
// components/CreateUserForm.tsx
'use client';

import { useActionState } from 'react';
import { createUser } from '@/app/actions/users';

export function CreateUserForm() {
  const [state, formAction, isPending] = useActionState(createUser, null);

  return (
    <form action={formAction}>
      <input name="name" required aria-label="Name" />
      {state?.error?.name && <p className="text-red-600">{state.error.name}</p>}

      <input name="email" type="email" required aria-label="Email" />
      {state?.error?.email && <p className="text-red-600">{state.error.email}</p>}

      <button type="submit" disabled={isPending}>
        {isPending ? 'Creating...' : 'Create User'}
      </button>
    </form>
  );
}
```

---

## Component Composition Patterns

**Pass Server Components as children to Client Components:**

```tsx
// app/layout.tsx (Server Component)
import { Sidebar } from '@/components/Sidebar';
import { UserProfile } from '@/components/UserProfile';
import { getCurrentUser } from '@/lib/auth';

export default async function Layout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();

  return (
    <div className="flex">
      <Sidebar>
        <UserProfile user={user} />
      </Sidebar>
      <main>{children}</main>
    </div>
  );
}
```

```tsx
// components/Sidebar.tsx (Client Component)
'use client';

import { useState } from 'react';

export function Sidebar({ children }: { children: React.ReactNode }) {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <aside className={collapsed ? 'w-16' : 'w-64'}>
      <button onClick={() => setCollapsed(!collapsed)}>Toggle</button>
      {!collapsed && children}
    </aside>
  );
}
```

---

## Streaming with Suspense

```tsx
// app/dashboard/page.tsx
import { Suspense } from 'react';

export default function DashboardPage() {
  return (
    <div className="grid grid-cols-2 gap-4">
      <Suspense fallback={<StatsLoader />}>
        <UserStats />
      </Suspense>
      <Suspense fallback={<ActivityLoader />}>
        <RecentActivity />
      </Suspense>
    </div>
  );
}
```

---

## React Compiler

```js
// next.config.js
module.exports = {
  experimental: {
    reactCompiler: true,
  },
};
```

When the compiler is enabled, remove manual memoization where safe:

```tsx
// Before: Manual memoization
const sortedUsers = useMemo(() => {
  return [...users].sort((a, b) => a.name.localeCompare(b.name));
}, [users]);

// After: Compiler handles it
const sortedUsers = [...users].sort((a, b) => a.name.localeCompare(b.name));
```

Keep `useMemo`/`useCallback` for referential equality in dependency arrays and third-party libraries.

---

## Code Splitting & Dynamic Imports

```tsx
import dynamic from 'next/dynamic';

const AdminDashboard = dynamic(() => import('@/components/AdminDashboard'), {
  loading: () => <div>Loading dashboard...</div>,
  ssr: false,
});

export default function AdminPage() {
  return <AdminDashboard />;
}
```

### Virtualization for Large Lists

```tsx
'use client';

import { useVirtualizer } from '@tanstack/react-virtual';
import { useRef } from 'react';

export function VirtualUserList({ users }: { users: Array<{ id: string; name: string }> }) {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: users.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 50,
    overscan: 5,
  });

  return (
    <div ref={parentRef} className="h-screen overflow-auto">
      <div style={{ height: `${virtualizer.getTotalSize()}px`, position: 'relative' }}>
        {virtualizer.getVirtualItems().map((item) => (
          <div
            key={item.key}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: `${item.size}px`,
              transform: `translateY(${item.start}px)`,
            }}
          >
            {users[item.index].name}
          </div>
        ))}
      </div>
    </div>
  );
}
```

---

## Error Boundaries

```tsx
// app/error.tsx
'use client';

import { useEffect } from 'react';

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error('App error:', error);
  }, [error]);

  return (
    <div className="flex min-h-screen items-center justify-center">
      <div className="text-center">
        <h2 className="text-2xl font-bold">Something went wrong!</h2>
        <p className="mt-2 text-gray-600">{error.message}</p>
        <button onClick={reset} className="mt-4 px-6 py-2 bg-blue-600 text-white rounded">
          Try again
        </button>
      </div>
    </div>
  );
}
```

### Suspense + Error Boundary

```tsx
import { Suspense } from 'react';
import { ErrorBoundary } from '@/components/ErrorBoundary';

export function DataView({ userId }: { userId: string }) {
  return (
    <ErrorBoundary>
      <Suspense fallback={<div>Loading user...</div>}>
        <UserData userId={userId} />
      </Suspense>
    </ErrorBoundary>
  );
}
```

---

## Next.js App Router Structure

```
app/
├── (auth)/              # Route group for auth pages
│   ├── login/page.tsx
│   └── register/page.tsx
├── (dashboard)/         # Route group for protected pages
│   ├── layout.tsx
│   ├── users/
│   │   ├── page.tsx
│   │   └── [id]/page.tsx
│   └── settings/page.tsx
├── api/users/route.ts
├── layout.tsx
├── page.tsx
└── error.tsx

components/
├── ui/                  # Reusable primitives (shadcn)
├── features/            # Feature-specific components
└── providers.tsx

lib/
├── db.ts
├── api.ts
├── utils.ts
└── validations.ts

hooks/
├── use-users.ts
└── use-debounce.ts

actions/
├── users.ts
└── auth.ts
```

---

## Authentication with Auth.js v5

```ts
// auth.ts
import NextAuth from 'next-auth';
import Credentials from 'next-auth/providers/credentials';
import { z } from 'zod';
import bcrypt from 'bcrypt';
import { db } from '@/lib/db';

export const { auth, signIn, signOut } = NextAuth({
  providers: [
    Credentials({
      async authorize(credentials) {
        const parsed = z
          .object({ email: z.string().email(), password: z.string().min(6) })
          .safeParse(credentials);
        if (!parsed.success) return null;

        const { email, password } = parsed.data;
        const user = await db.user.findUnique({ where: { email } });
        if (!user) return null;

        const passwordsMatch = await bcrypt.compare(password, user.password);
        if (!passwordsMatch) return null;

        return user;
      },
    }),
  ],
});
```

---

## Middleware Protection

```ts
// middleware.ts
import { auth } from '@/auth';

export default auth((req) => {
  const isLoggedIn = !!req.auth;
  const isOnDashboard = req.nextUrl.pathname.startsWith('/dashboard');

  if (isOnDashboard && !isLoggedIn) {
    return Response.redirect(new URL('/login', req.nextUrl));
  }
});

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
};
```

---

## TypeScript Patterns

### Discriminated Unions

```tsx
type ApiResponse<T> =
  | { status: 'success'; data: T }
  | { status: 'error'; error: string; code: string }
  | { status: 'loading' };

function handleResponse<T>(response: ApiResponse<T>) {
  switch (response.status) {
    case 'success':
      return <div>{JSON.stringify(response.data)}</div>;
    case 'error':
      return <div>Error {response.code}: {response.error}</div>;
    case 'loading':
      return <div>Loading...</div>;
  }
}
```

### Polymorphic Components

```tsx
type ButtonAsButton = { as?: 'button' } & React.ComponentPropsWithoutRef<'button'>;
type ButtonAsLink = { as: 'a'; href: string } & React.ComponentPropsWithoutRef<'a'>;
type ButtonProps = (ButtonAsButton | ButtonAsLink) & { variant?: 'primary' | 'secondary' };

export function Button(props: ButtonProps) {
  if (props.as === 'a') {
    return <a className={`btn btn-${props.variant}`} {...props}>{props.children}</a>;
  }
  return <button className={`btn btn-${props.variant}`} {...props}>{props.children}</button>;
}
```

---

## Best Practices

1. **Use Server Components by default** - Only add `'use client'` for interactivity
2. **Validate all Server Action inputs** with Zod schemas
3. **Use Suspense boundaries** for independent data loading
4. **Parallel data fetching** with `Promise.all` in Server Components
5. **Error boundaries per section** - Not just one global boundary
6. **Use `revalidatePath` or `revalidateTag`** after mutations
7. **Keep the client bundle small** - Move logic to Server Components

---

## Anti-Patterns

- Marking entire pages as `'use client'` when only a small part is interactive
- Fetching data in Client Components when Server Components can do it
- Not using Suspense for slow data fetches (blocking the entire page)
- Passing non-serializable props from Server to Client Components
- Using `useEffect` for data fetching in App Router (use RSC or Server Actions instead)

---

## Sources & References

- [Next.js Server Components Documentation](https://nextjs.org/docs/app/getting-started/server-and-client-components)
- [React 19 Server Components Tutorial](https://www.scalablepath.com/react/react-19-server-components-server-actions)
- [React & Next.js 2025 Best Practices](https://strapi.io/blog/react-and-nextjs-in-2025-modern-best-practices)
- [React Compiler in Production at Meta](https://www.infoq.com/news/2025/12/react-compiler-meta/)
- [React Suspense Complete Guide 2025](https://natclark.com/how-to-use-react-suspense-complete-guide-for-2025/)
- [NextAuth.js v5 Migration Guide](https://authjs.dev/getting-started/migrating-to-v5)
- [RSC Limitations and Patterns](https://www.nirtamir.com/articles/the-limits-of-rsc-a-practitioners-journey)
- [Next.js 15 + React 19 Full-Stack Implementation Guide](https://medium.com/@genildocs/next-js-15-react-19-full-stack-implementation-guide-4ba0978fa0e5)
