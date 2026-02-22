---
name: react-state
description: React state management with Zustand, TanStack Query, React Hook Form + Zod, optimistic updates, and data fetching patterns
---

# React State Management & Data Fetching

Production-ready state management and data fetching patterns for React 19. Covers TanStack Query v5, Zustand v5, Jotai, React Hook Form + Zod, optimistic updates, infinite scroll, cache management, and the `use()` hook.

## Table of Contents

1. [TanStack Query v5 (Server State)](#tanstack-query-v5-server-state)
2. [Zustand v5 (Client State)](#zustand-v5-client-state)
3. [Jotai (Atomic State)](#jotai-atomic-state)
4. [React Hook Form + Zod](#react-hook-form--zod)
5. [Progressive Enhancement Forms](#progressive-enhancement-forms)
6. [Optimistic Updates](#optimistic-updates)
7. [Infinite Scroll](#infinite-scroll)
8. [Parallel Data Fetching in RSC](#parallel-data-fetching-in-rsc)
9. [Data Fetching with use() Hook](#data-fetching-with-use-hook)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)

---

## TanStack Query v5 (Server State)

```tsx
// lib/queries/users.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/api';

export function useUsers(filters?: UserFilters) {
  return useQuery({
    queryKey: ['users', filters],
    queryFn: () => api.getUsers(filters),
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
}

export function useCreateUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: api.createUser,
    onMutate: async (newUser) => {
      await queryClient.cancelQueries({ queryKey: ['users'] });
      const previous = queryClient.getQueryData(['users']);

      queryClient.setQueryData(['users'], (old: User[]) =>
        [...old, { ...newUser, id: 'temp-id' }]
      );

      return { previous };
    },
    onError: (err, variables, context) => {
      queryClient.setQueryData(['users'], context?.previous);
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
  });
}
```

---

## Zustand v5 (Client State)

```tsx
// store/ui.ts
import { create } from 'zustand';
import { devtools, persist } from 'zustand/middleware';

interface UIState {
  sidebarOpen: boolean;
  theme: 'light' | 'dark';
  toggleSidebar: () => void;
  setTheme: (theme: 'light' | 'dark') => void;
}

export const useUIStore = create<UIState>()(
  devtools(
    persist(
      (set) => ({
        sidebarOpen: true,
        theme: 'light',
        toggleSidebar: () => set((state) => ({ sidebarOpen: !state.sidebarOpen })),
        setTheme: (theme) => set({ theme }),
      }),
      { name: 'ui-store' }
    )
  )
);

// Usage
function Sidebar() {
  const { sidebarOpen, toggleSidebar } = useUIStore();

  return (
    <aside className={sidebarOpen ? 'w-64' : 'w-0'}>
      <button onClick={toggleSidebar}>Toggle</button>
    </aside>
  );
}
```

---

## Jotai (Atomic State)

```tsx
// store/atoms.ts
import { atom } from 'jotai';
import { atomWithStorage } from 'jotai/utils';

export const selectedUserIdAtom = atom<string | null>(null);

export const selectedUserAtom = atom(async (get) => {
  const id = get(selectedUserIdAtom);
  if (!id) return null;
  const response = await fetch(`/api/users/${id}`);
  return response.json();
});

export const themeAtom = atomWithStorage<'light' | 'dark'>('theme', 'light');

// Usage
function UserDetails() {
  const [selectedUser] = useAtom(selectedUserAtom);
  if (!selectedUser) return <div>Select a user</div>;
  return <div>{selectedUser.name}</div>;
}
```

---

## React Hook Form + Zod

```tsx
// schemas/user.ts
import { z } from 'zod';

export const createUserSchema = z.object({
  name: z.string().min(2, 'Name must be at least 2 characters'),
  email: z.string().email('Invalid email address'),
  age: z.coerce.number().min(18, 'Must be at least 18'),
  role: z.enum(['user', 'admin'], {
    errorMap: () => ({ message: 'Select a valid role' }),
  }),
});

export type CreateUserInput = z.infer<typeof createUserSchema>;
```

```tsx
// components/CreateUserForm.tsx
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { createUserSchema, type CreateUserInput } from '@/schemas/user';
import { createUser } from '@/app/actions/users';

export function CreateUserForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
    setError,
  } = useForm<CreateUserInput>({
    resolver: zodResolver(createUserSchema),
  });

  const onSubmit = async (data: CreateUserInput) => {
    const result = await createUser(data);

    if (!result.success && result.errors) {
      Object.entries(result.errors).forEach(([field, messages]) => {
        setError(field as keyof CreateUserInput, {
          message: messages?.[0],
        });
      });
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <div>
        <label htmlFor="name">Name</label>
        <input id="name" {...register('name')} aria-invalid={errors.name ? 'true' : 'false'} />
        {errors.name && <p role="alert" className="text-red-600">{errors.name.message}</p>}
      </div>

      <div>
        <label htmlFor="email">Email</label>
        <input id="email" type="email" {...register('email')} />
        {errors.email && <p role="alert" className="text-red-600">{errors.email.message}</p>}
      </div>

      <div>
        <label htmlFor="age">Age</label>
        <input id="age" type="number" {...register('age')} />
        {errors.age && <p role="alert" className="text-red-600">{errors.age.message}</p>}
      </div>

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Creating...' : 'Create User'}
      </button>
    </form>
  );
}
```

---

## Progressive Enhancement Forms

```tsx
'use client';

import { useActionState } from 'react';
import { createUser } from '@/app/actions/users';

export function ProgressiveForm() {
  const [state, formAction, isPending] = useActionState(createUser, null);

  // Works WITHOUT JavaScript via server action
  // WITH JavaScript, enhanced with pending states
  return (
    <form action={formAction}>
      <input name="name" required />
      {state?.errors?.name && <p>{state.errors.name}</p>}

      <input name="email" type="email" required />
      {state?.errors?.email && <p>{state.errors.email}</p>}

      <button type="submit" disabled={isPending}>
        {isPending ? 'Saving...' : 'Save'}
      </button>
    </form>
  );
}
```

---

## Optimistic Updates

```tsx
// hooks/useTodos.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';

export function useAddTodo() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (newTodo: { title: string }) =>
      fetch('/api/todos', {
        method: 'POST',
        body: JSON.stringify(newTodo),
      }).then((res) => res.json()),

    onMutate: async (newTodo) => {
      await queryClient.cancelQueries({ queryKey: ['todos'] });
      const previousTodos = queryClient.getQueryData(['todos']);

      queryClient.setQueryData(['todos'], (old: Todo[]) => [
        ...old,
        { id: Date.now(), ...newTodo, completed: false },
      ]);

      return { previousTodos };
    },

    onError: (err, newTodo, context) => {
      queryClient.setQueryData(['todos'], context?.previousTodos);
    },

    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['todos'] });
    },
  });
}
```

---

## Infinite Scroll

```tsx
'use client';

import { useInfiniteQuery } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';

export function InfiniteUserList() {
  const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useInfiniteQuery({
    queryKey: ['users'],
    queryFn: ({ pageParam = 0 }) =>
      fetch(`/api/users?page=${pageParam}&limit=20`).then((res) => res.json()),
    getNextPageParam: (lastPage) => lastPage.nextPage,
    initialPageParam: 0,
  });

  const observerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!observerRef.current) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasNextPage && !isFetchingNextPage) {
          fetchNextPage();
        }
      },
      { threshold: 1.0 }
    );

    observer.observe(observerRef.current);
    return () => observer.disconnect();
  }, [fetchNextPage, hasNextPage, isFetchingNextPage]);

  return (
    <div>
      {data?.pages.map((page, i) => (
        <div key={i}>
          {page.users.map((user: any) => (
            <div key={user.id}>{user.name}</div>
          ))}
        </div>
      ))}
      <div ref={observerRef} className="h-10">
        {isFetchingNextPage ? 'Loading more...' : null}
      </div>
    </div>
  );
}
```

---

## Parallel Data Fetching in RSC

```tsx
// app/dashboard/page.tsx
export default async function Dashboard() {
  const [user, posts, comments] = await Promise.all([
    getUser(),
    getPosts(),
    getComments(),
  ]);

  return (
    <div>
      <UserProfile user={user} />
      <PostList posts={posts} />
      <CommentList comments={comments} />
    </div>
  );
}
```

---

## Data Fetching with use() Hook

```tsx
'use client';

import { use } from 'react';

export function UserProfile({ userPromise }: { userPromise: Promise<User> }) {
  const user = use(userPromise);

  return (
    <div>
      <h1>{user.name}</h1>
      <p>{user.email}</p>
    </div>
  );
}

// Usage in Server Component
export default async function Page() {
  const userPromise = fetchUser('123');

  return (
    <Suspense fallback={<Skeleton />}>
      <UserProfile userPromise={userPromise} />
    </Suspense>
  );
}
```

---

## Best Practices

1. **Separate server state (TanStack Query) from client state (Zustand/Jotai)**
2. **Use `staleTime`** to avoid unnecessary refetches
3. **Optimistic updates** for instant UI feedback
4. **Zod schemas shared** between client validation and server actions
5. **Use `useActionState`** for forms that work without JavaScript
6. **Invalidate queries** after mutations to keep data fresh
7. **Use selectors** in Zustand to prevent unnecessary re-renders

---

## Anti-Patterns

- Using `useEffect` + `useState` for data fetching (use TanStack Query or RSC)
- Storing server-fetched data in Zustand (use TanStack Query for server state)
- Not cancelling queries on mutation (causes race conditions)
- Not handling loading and error states in queries
- Using React Context for frequently changing state (causes re-render cascades)

---

## Sources & References

- [TanStack Query v5 Documentation](https://tanstack.com/query/latest)
- [State Management in 2025: Redux Toolkit vs Zustand vs Jotai](https://medium.com/@pooja.1502/state-management-in-2025-redux-toolkit-vs-zustand-vs-jotai-vs-tanstack-store-c888e7e6f784)
- [React State Management Trends 2025](https://makersden.io/blog/react-state-management-in-2025)
- [React Hook Form + Zod + Server Actions](https://medium.com/@techwithtwin/handling-forms-in-next-js-with-react-hook-form-zod-and-server-actions-e148d4dc6dc1)
- [Advanced React Hook Form with Zod and shadcn](https://wasp.sh/blog/2025/01/22/advanced-react-hook-form-zod-shadcn)
- [React 19 Resilience: Retry, Suspense, Error Boundaries](https://medium.com/@connect.hashblock/react-19-resilience-retry-suspense-error-boundaries-40ea504b09ed)
