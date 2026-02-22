---
name: react-ui
description: React component patterns (compound, polymorphic, slot), Tailwind CSS v4, accessibility, keyboard navigation, and design system patterns
---

# React UI & Component Patterns

Production-ready UI patterns for React 19. Covers compound components, Radix/shadcn patterns, Tailwind CSS v4, responsive design, accessibility (ARIA, keyboard navigation, focus management), and design system conventions.

## Table of Contents

1. [Compound Components](#compound-components)
2. [Headless UI with Radix/shadcn](#headless-ui-with-radixshadcn)
3. [Render Props Pattern](#render-props-pattern)
4. [Generic Components](#generic-components)
5. [Tailwind CSS v4](#tailwind-css-v4)
6. [Container Queries](#container-queries)
7. [CSS Modules](#css-modules)
8. [Dynamic Styling with CSS Variables](#dynamic-styling-with-css-variables)
9. [Keyboard Navigation](#keyboard-navigation)
10. [Focus Management](#focus-management)
11. [ARIA Live Regions](#aria-live-regions)
12. [Skip Links](#skip-links)
13. [Best Practices](#best-practices)
14. [Anti-Patterns](#anti-patterns)

---

## Compound Components

```tsx
'use client';

import { createContext, useContext, useState, type ReactNode } from 'react';

interface TabsContextValue {
  activeTab: string;
  setActiveTab: (id: string) => void;
}

const TabsContext = createContext<TabsContextValue | null>(null);

function useTabs() {
  const context = useContext(TabsContext);
  if (!context) throw new Error('Tabs compound components must be used within Tabs');
  return context;
}

export function Tabs({ defaultTab, children }: { defaultTab: string; children: ReactNode }) {
  const [activeTab, setActiveTab] = useState(defaultTab);
  return (
    <TabsContext.Provider value={{ activeTab, setActiveTab }}>
      {children}
    </TabsContext.Provider>
  );
}

export function TabList({ children }: { children: ReactNode }) {
  return <div role="tablist" className="flex border-b">{children}</div>;
}

export function Tab({ id, children }: { id: string; children: ReactNode }) {
  const { activeTab, setActiveTab } = useTabs();
  return (
    <button
      role="tab"
      aria-selected={activeTab === id}
      aria-controls={`panel-${id}`}
      id={`tab-${id}`}
      onClick={() => setActiveTab(id)}
      className={activeTab === id ? 'border-b-2 border-blue-600' : ''}
    >
      {children}
    </button>
  );
}

export function TabPanel({ id, children }: { id: string; children: ReactNode }) {
  const { activeTab } = useTabs();
  if (activeTab !== id) return null;
  return <div role="tabpanel" id={`panel-${id}`} aria-labelledby={`tab-${id}`}>{children}</div>;
}

// Usage
function MyTabs() {
  return (
    <Tabs defaultTab="profile">
      <TabList>
        <Tab id="profile">Profile</Tab>
        <Tab id="settings">Settings</Tab>
      </TabList>
      <TabPanel id="profile"><h2>Profile Content</h2></TabPanel>
      <TabPanel id="settings"><h2>Settings Content</h2></TabPanel>
    </Tabs>
  );
}
```

---

## Headless UI with Radix/shadcn

```tsx
'use client';

import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import { cn } from '@/lib/utils';

const Dialog = DialogPrimitive.Root;
const DialogTrigger = DialogPrimitive.Trigger;

function DialogOverlay({ className, ...props }: React.ComponentPropsWithoutRef<typeof DialogPrimitive.Overlay>) {
  return (
    <DialogPrimitive.Overlay
      className={cn('fixed inset-0 z-50 bg-black/80 data-[state=open]:animate-in', className)}
      {...props}
    />
  );
}

function DialogContent({ className, children, ...props }: React.ComponentPropsWithoutRef<typeof DialogPrimitive.Content>) {
  return (
    <DialogPrimitive.Portal>
      <DialogOverlay />
      <DialogPrimitive.Content
        className={cn(
          'fixed left-[50%] top-[50%] z-50 translate-x-[-50%] translate-y-[-50%]',
          'w-full max-w-lg rounded-lg bg-white p-6 shadow-lg',
          className
        )}
        {...props}
      >
        {children}
        <DialogPrimitive.Close className="absolute right-4 top-4">
          <X className="h-4 w-4" />
          <span className="sr-only">Close</span>
        </DialogPrimitive.Close>
      </DialogPrimitive.Content>
    </DialogPrimitive.Portal>
  );
}

// Usage
function DeleteUserDialog({ user }: { user: User }) {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <button>Delete User</button>
      </DialogTrigger>
      <DialogContent>
        <h2>Are you sure?</h2>
        <p>This will permanently delete {user.name}.</p>
      </DialogContent>
    </Dialog>
  );
}
```

---

## Render Props Pattern

```tsx
import { useQuery } from '@tanstack/react-query';
import type { ReactNode } from 'react';

interface FetchDataProps<T> {
  queryKey: string[];
  queryFn: () => Promise<T>;
  children: (data: T) => ReactNode;
  loadingFallback?: ReactNode;
  errorFallback?: (error: Error) => ReactNode;
}

export function FetchData<T>({
  queryKey, queryFn, children,
  loadingFallback = <div>Loading...</div>,
  errorFallback = (error) => <div>Error: {error.message}</div>,
}: FetchDataProps<T>) {
  const { data, isLoading, error } = useQuery({ queryKey, queryFn });

  if (isLoading) return <>{loadingFallback}</>;
  if (error) return <>{errorFallback(error as Error)}</>;
  if (!data) return null;

  return <>{children(data)}</>;
}

// Usage
<FetchData queryKey={['user', userId]} queryFn={() => api.getUser(userId)}>
  {(user) => <div><h1>{user.name}</h1><p>{user.email}</p></div>}
</FetchData>
```

---

## Generic Components

```tsx
interface Option<T> {
  value: T;
  label: string;
}

interface SelectProps<T> {
  options: Option<T>[];
  value: T;
  onChange: (value: T) => void;
}

export function Select<T extends string | number>({ options, value, onChange }: SelectProps<T>) {
  return (
    <select
      value={String(value)}
      onChange={(e) => {
        const selected = options.find((opt) => String(opt.value) === e.target.value);
        if (selected) onChange(selected.value);
      }}
    >
      {options.map((option) => (
        <option key={String(option.value)} value={String(option.value)}>
          {option.label}
        </option>
      ))}
    </select>
  );
}
```

---

## Tailwind CSS v4

```css
/* app/globals.css */
@import "tailwindcss";

@theme {
  --color-primary: #3b82f6;
  --color-secondary: #8b5cf6;
  --font-sans: "Inter", system-ui, sans-serif;
}

@utility gradient-primary {
  background: linear-gradient(to right, var(--color-primary), var(--color-secondary));
}
```

---

## Container Queries

```tsx
export function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="@container">
      <div className="p-4 border rounded-lg">
        <h2 className="@lg:text-2xl @sm:text-lg text-base font-bold">{title}</h2>
        <div className="@lg:flex @lg:gap-4 space-y-2 @lg:space-y-0">
          {children}
        </div>
      </div>
    </div>
  );
}
```

---

## CSS Modules

```css
/* Button.module.css */
.button { @apply px-4 py-2 rounded font-medium transition-colors; }
.primary { @apply bg-blue-600 text-white hover:bg-blue-700; }
.secondary { @apply bg-gray-200 text-gray-800 hover:bg-gray-300; }
```

```tsx
import styles from './Button.module.css';

export function Button({ variant = 'primary', children }: { variant?: 'primary' | 'secondary'; children: React.ReactNode }) {
  return <button className={`${styles.button} ${styles[variant]}`}>{children}</button>;
}
```

---

## Dynamic Styling with CSS Variables

```tsx
'use client';

import { createContext, useContext, useState } from 'react';

type Theme = 'light' | 'dark';

const ThemeContext = createContext<{ theme: Theme; setTheme: (t: Theme) => void } | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>('light');

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      <div
        className={theme}
        style={{
          '--bg-primary': theme === 'dark' ? '#1a1a1a' : '#ffffff',
          '--text-primary': theme === 'dark' ? '#ffffff' : '#000000',
        } as React.CSSProperties}
      >
        {children}
      </div>
    </ThemeContext.Provider>
  );
}
```

---

## Keyboard Navigation

```tsx
'use client';

import { useState, useEffect } from 'react';

export function Dropdown({ trigger, items }: {
  trigger: React.ReactNode;
  items: Array<{ label: string; onClick: () => void }>;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [focusedIndex, setFocusedIndex] = useState(-1);

  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setFocusedIndex((prev) => (prev + 1) % items.length);
          break;
        case 'ArrowUp':
          e.preventDefault();
          setFocusedIndex((prev) => (prev - 1 + items.length) % items.length);
          break;
        case 'Enter':
        case ' ':
          e.preventDefault();
          if (focusedIndex >= 0) {
            items[focusedIndex].onClick();
            setIsOpen(false);
          }
          break;
        case 'Escape':
          setIsOpen(false);
          break;
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, focusedIndex, items]);

  return (
    <div className="relative">
      <button onClick={() => setIsOpen(!isOpen)} aria-haspopup="true" aria-expanded={isOpen}>
        {trigger}
      </button>
      {isOpen && (
        <div role="menu" className="absolute mt-2">
          {items.map((item, index) => (
            <button
              key={index}
              role="menuitem"
              className={focusedIndex === index ? 'bg-blue-100' : ''}
              onClick={() => { item.onClick(); setIsOpen(false); }}
              onMouseEnter={() => setFocusedIndex(index)}
            >
              {item.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
```

---

## Focus Management

```tsx
'use client';

import { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';

export function Modal({ isOpen, onClose, children }: {
  isOpen: boolean; onClose: () => void; children: React.ReactNode;
}) {
  const modalRef = useRef<HTMLDivElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    previousFocusRef.current = document.activeElement as HTMLElement;
    modalRef.current?.focus();

    const handleTab = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return;
      const focusable = modalRef.current?.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      if (!focusable?.length) return;

      const first = focusable[0] as HTMLElement;
      const last = focusable[focusable.length - 1] as HTMLElement;

      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault(); last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault(); first.focus();
      }
    };

    document.addEventListener('keydown', handleTab);
    return () => {
      document.removeEventListener('keydown', handleTab);
      previousFocusRef.current?.focus();
    };
  }, [isOpen]);

  if (!isOpen) return null;

  return createPortal(
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center" onClick={onClose}>
      <div ref={modalRef} role="dialog" aria-modal="true" tabIndex={-1}
           className="bg-white p-6 rounded-lg max-w-md" onClick={(e) => e.stopPropagation()}>
        {children}
      </div>
    </div>,
    document.body
  );
}
```

---

## ARIA Live Regions

```tsx
'use client';

import { useState, useEffect } from 'react';

export function SearchResults() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<string[]>([]);
  const [announcement, setAnnouncement] = useState('');

  useEffect(() => {
    if (!query) { setResults([]); return; }
    const filtered = mockData.filter((item) =>
      item.toLowerCase().includes(query.toLowerCase())
    );
    setResults(filtered);
    setAnnouncement(`${filtered.length} result${filtered.length !== 1 ? 's' : ''} found`);
  }, [query]);

  return (
    <div>
      <label htmlFor="search">Search</label>
      <input id="search" type="search" value={query}
             onChange={(e) => setQuery(e.target.value)} aria-describedby="search-status" />

      <div id="search-status" role="status" aria-live="polite" aria-atomic="true" className="sr-only">
        {announcement}
      </div>

      <ul>{results.map((r) => <li key={r}>{r}</li>)}</ul>
    </div>
  );
}
```

---

## Skip Links

```tsx
export function SkipLink() {
  return (
    <a href="#main-content"
       className="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:bg-blue-600 focus:text-white focus:px-4 focus:py-2 focus:rounded">
      Skip to main content
    </a>
  );
}
```

---

## Best Practices

1. **Use semantic HTML** - `<button>`, `<nav>`, `<main>`, `<article>`
2. **ARIA attributes** where native semantics are insufficient
3. **Focus visible styles** for keyboard users
4. **Minimum touch targets** of 44x44px
5. **Color contrast** ratio 4.5:1 (WCAG AA)
6. **Compound components** for related UI elements sharing state
7. **Headless UI** (Radix) for accessible, unstyled primitives
8. **Container queries** over media queries for component-level responsiveness

---

## Anti-Patterns

- Using `<div>` with `onClick` instead of `<button>` (not keyboard accessible)
- Missing `aria-label` on icon-only buttons
- Modals without focus trap
- Dropdown menus without keyboard navigation
- Not announcing dynamic content changes to screen readers
- Custom checkboxes/radios that do not work with keyboard

---

## Sources & References

- [shadcn/ui Components](https://ui.shadcn.com)
- [Radix UI Primitives](https://radix-ui.com)
- [Tailwind CSS v4 Documentation](https://tailwindcss.com/blog/tailwindcss-v4)
- [shadcn/ui + Radix Guide](https://certificates.dev/blog/starting-a-react-project-shadcnui-radix-and-base-ui-explained)
- [Tailwind v4 Container Queries](https://www.sitepoint.com/tailwind-css-v4-container-queries-modern-layouts/)
- [React Accessibility Documentation](https://legacy.reactjs.org/docs/accessibility.html)
- [React Aria Accessibility](https://react-spectrum.adobe.com/react-aria/accessibility.html)
- [Accessibility Quick Wins 2025](https://medium.com/@sureshdotariya/accessibility-quick-wins-in-reactjs-2025-skip-links-focus-traps-aria-live-regions-c926b9e44593)
