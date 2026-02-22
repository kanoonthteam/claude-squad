---
name: react-testing
description: React testing with Vitest, React Testing Library, MSW for API mocking, Playwright E2E, and accessibility testing
---

# React Testing Patterns

Production-ready testing patterns for React 19 applications. Covers Vitest + React Testing Library, user-event, MSW for API mocking, component testing, integration tests, Playwright E2E, and accessibility testing.

## Table of Contents

1. [Vitest + React Testing Library](#vitest--react-testing-library)
2. [MSW for API Mocking](#msw-for-api-mocking)
3. [Component Integration Tests](#component-integration-tests)
4. [Playwright E2E Tests](#playwright-e2e-tests)
5. [Testing TanStack Query Components](#testing-tanstack-query-components)
6. [Accessibility Testing](#accessibility-testing)
7. [Best Practices](#best-practices)
8. [Anti-Patterns](#anti-patterns)

---

## Vitest + React Testing Library

```tsx
// components/UserCard.test.tsx
import { render, screen } from '@testing-library/react';
import { userEvent } from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';
import { UserCard } from './UserCard';

describe('UserCard', () => {
  const user = {
    id: '1',
    name: 'Alice Johnson',
    email: 'alice@example.com',
  };

  it('displays user information', () => {
    render(<UserCard user={user} />);

    expect(screen.getByRole('heading', { name: 'Alice Johnson' })).toBeInTheDocument();
    expect(screen.getByText('alice@example.com')).toBeInTheDocument();
  });

  it('calls onDelete when delete button is clicked', async () => {
    const handleDelete = vi.fn();
    const userAction = userEvent.setup();

    render(<UserCard user={user} onDelete={handleDelete} />);

    const deleteButton = screen.getByRole('button', { name: /delete/i });
    await userAction.click(deleteButton);

    expect(handleDelete).toHaveBeenCalledWith('1');
  });

  it('shows confirmation dialog before deleting', async () => {
    const handleDelete = vi.fn();
    const userAction = userEvent.setup();

    render(<UserCard user={user} onDelete={handleDelete} />);

    await userAction.click(screen.getByRole('button', { name: /delete/i }));

    expect(screen.getByText('Are you sure?')).toBeInTheDocument();

    await userAction.click(screen.getByRole('button', { name: /confirm/i }));

    expect(handleDelete).toHaveBeenCalledWith('1');
  });
});
```

---

## MSW for API Mocking

```tsx
// mocks/handlers.ts
import { http, HttpResponse } from 'msw';

export const handlers = [
  http.get('/api/users', () => {
    return HttpResponse.json([
      { id: '1', name: 'Alice', email: 'alice@example.com' },
      { id: '2', name: 'Bob', email: 'bob@example.com' },
    ]);
  }),

  http.post('/api/users', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({ id: '3', ...body }, { status: 201 });
  }),

  http.delete('/api/users/:id', () => {
    return HttpResponse.json(null, { status: 204 });
  }),
];
```

```tsx
// mocks/server.ts
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

```tsx
// vitest.setup.ts
import { beforeAll, afterEach, afterAll } from 'vitest';
import { server } from './mocks/server';

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

---

## Component Integration Tests

```tsx
// components/UserList.test.tsx
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { describe, it, expect } from 'vitest';
import { UserList } from './UserList';

describe('UserList', () => {
  const createWrapper = () => {
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });

    return ({ children }: { children: React.ReactNode }) => (
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    );
  };

  it('loads and displays users from API', async () => {
    render(<UserList />, { wrapper: createWrapper() });

    expect(screen.getByText('Loading...')).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
    });
  });

  it('shows error state when API fails', async () => {
    server.use(
      http.get('/api/users', () => {
        return HttpResponse.json({ error: 'Server error' }, { status: 500 });
      })
    );

    render(<UserList />, { wrapper: createWrapper() });

    await waitFor(() => {
      expect(screen.getByText(/error/i)).toBeInTheDocument();
    });
  });
});
```

---

## Playwright E2E Tests

```tsx
// e2e/user-flow.spec.ts
import { test, expect } from '@playwright/test';

test.describe('User Management', () => {
  test('should create, edit, and delete a user', async ({ page }) => {
    await page.goto('/users');

    // Create user
    await page.getByRole('button', { name: 'Add User' }).click();
    await page.getByLabel('Name').fill('Charlie Brown');
    await page.getByLabel('Email').fill('charlie@example.com');
    await page.getByRole('button', { name: 'Save' }).click();

    await expect(page.getByText('Charlie Brown')).toBeVisible();

    // Edit user
    await page.getByRole('button', { name: 'Edit Charlie Brown' }).click();
    await page.getByLabel('Name').fill('Charlie Smith');
    await page.getByRole('button', { name: 'Save' }).click();

    await expect(page.getByText('Charlie Smith')).toBeVisible();
    await expect(page.getByText('Charlie Brown')).not.toBeVisible();

    // Delete user
    await page.getByRole('button', { name: 'Delete Charlie Smith' }).click();
    await page.getByRole('button', { name: 'Confirm' }).click();

    await expect(page.getByText('Charlie Smith')).not.toBeVisible();
  });

  test('should validate required fields', async ({ page }) => {
    await page.goto('/users/new');
    await page.getByRole('button', { name: 'Save' }).click();

    await expect(page.getByText('Name is required')).toBeVisible();
    await expect(page.getByText('Email is required')).toBeVisible();
  });
});
```

---

## Testing TanStack Query Components

```tsx
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false },
    },
  });
}

function renderWithProviders(ui: React.ReactElement) {
  const queryClient = createTestQueryClient();
  return render(
    <QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>
  );
}

describe('UserProfile', () => {
  it('fetches and displays user data', async () => {
    renderWithProviders(<UserProfile userId="1" />);

    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeInTheDocument();
    });
  });
});
```

---

## Accessibility Testing

```tsx
import { render } from '@testing-library/react';
import { axe, toHaveNoViolations } from 'jest-axe';

expect.extend(toHaveNoViolations);

describe('LoginForm accessibility', () => {
  it('should have no accessibility violations', async () => {
    const { container } = render(<LoginForm />);
    const results = await axe(container);
    expect(results).toHaveNoViolations();
  });
});

// Test ARIA attributes
it('marks invalid fields with aria-invalid', async () => {
  const user = userEvent.setup();
  render(<LoginForm />);

  await user.click(screen.getByRole('button', { name: /submit/i }));

  expect(screen.getByLabelText('Email')).toHaveAttribute('aria-invalid', 'true');
});

// Test keyboard navigation
it('supports keyboard navigation', async () => {
  const user = userEvent.setup();
  render(<Dropdown items={['One', 'Two', 'Three']} />);

  await user.tab(); // Focus trigger
  await user.keyboard('{Enter}'); // Open
  await user.keyboard('{ArrowDown}'); // Navigate
  expect(screen.getByText('One')).toHaveFocus();
});
```

---

## Best Practices

1. **Query by role, not by test-id** - `getByRole('button', { name: 'Submit' })` not `getByTestId('submit-btn')`
2. **Use `userEvent` over `fireEvent`** - More realistic user interaction simulation
3. **Use `waitFor` for async operations** - Not arbitrary delays
4. **Test behavior, not implementation** - What the user sees, not component internals
5. **Use MSW for API mocking** - Not `vi.mock` for fetch/axios
6. **Create test helpers** for common wrappers (providers, query clients)
7. **Run accessibility tests** with axe-core on every component
8. **Snapshot testing sparingly** - Only for simple, stable components

---

## Anti-Patterns

- Testing internal state or implementation details
- Using `container.querySelector` instead of semantic queries
- Not cleaning up between tests (MSW handlers, query caches)
- Writing snapshot tests for complex, frequently changing components
- Mocking too many internals instead of using MSW for API layer
- Not testing loading, error, and empty states

---

## Sources & References

- [Vitest Documentation](https://vitest.dev)
- [React Testing Library](https://testing-library.com/react)
- [MSW (Mock Service Worker)](https://mswjs.io/)
- [Playwright Documentation](https://playwright.dev)
- [Testing with Vitest + Playwright 2025](https://javascript.plainenglish.io/test-like-a-pro-in-2025-how-i-transformed-my-javascript-projects-with-vitest-playwright-and-more-9616cfb72e9b)
- [Unit Testing with Vitest, MSW, and Playwright](https://makepath.com/unit-testing-a-react-application-with-vitest-msw-and-playwright/)
- [jest-axe Accessibility Testing](https://github.com/nickcolley/jest-axe)
- [Testing Library Guiding Principles](https://testing-library.com/docs/guiding-principles)
