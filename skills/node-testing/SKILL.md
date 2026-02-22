---
name: node-testing
description: Node.js testing strategies — Vitest, Supertest integration tests, testcontainers, mocking, spies, fake timers, snapshots, Node.js 22+ built-in test runner
---

# Node.js Testing Strategies

Production-ready testing patterns for Node.js 2026. Covers Vitest advanced patterns, Supertest integration testing, Docker-based testing with testcontainers, mocking and spying, fake timers, snapshot testing, and Node.js 22+ built-in test runner.

## Table of Contents

1. [Vitest Configuration](#vitest-configuration)
2. [Unit Testing with Vitest](#unit-testing-with-vitest)
3. [Supertest Integration Testing](#supertest-integration-testing)
4. [Test Containers](#test-containers)
5. [Node.js 22+ Built-in Test Runner](#nodejs-22-built-in-test-runner)
6. [Module Mocking (Node.js 22.3+)](#module-mocking-nodejs-223)
7. [Built-in SQLite for Testing](#built-in-sqlite-for-testing)
8. [Best Practices](#best-practices)
9. [Anti-Patterns](#anti-patterns)

---

## Vitest Configuration

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: ['node_modules/', 'dist/', '**/*.test.ts'],
    },
    setupFiles: ['./test/setup.ts'],
  },
});

// test/setup.ts - Global test setup
import { beforeAll, afterAll, afterEach } from 'vitest';
import { db } from '../src/db';

beforeAll(async () => {
  await db.$connect();
});

afterEach(async () => {
  const tables = await db.$queryRaw`
    SELECT tablename FROM pg_tables WHERE schemaname='public'
  `;

  for (const { tablename } of tables) {
    await db.$executeRawUnsafe(`TRUNCATE TABLE "${tablename}" CASCADE`);
  }
});

afterAll(async () => {
  await db.$disconnect();
});
```

---

## Unit Testing with Vitest

### Module Mocking

```typescript
import { vi, describe, it, expect, beforeEach } from 'vitest';
import { EmailService } from './email.service';
import { UserService } from './user.service';

// Mock entire module
vi.mock('./email.service');

describe('UserService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('sends welcome email on user creation', async () => {
    const mockSendEmail = vi.fn();
    EmailService.prototype.sendWelcomeEmail = mockSendEmail;

    const userService = new UserService();
    await userService.createUser({
      email: 'test@example.com',
      name: 'Test User',
    });

    expect(mockSendEmail).toHaveBeenCalledWith('test@example.com');
  });
});

// Partial module mocking
vi.mock('./utils', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    getCurrentTime: vi.fn(() => new Date('2024-01-01')),
  };
});
```

### Snapshot Testing

```typescript
it('generates correct API response structure', () => {
  const response = formatUserResponse({
    id: '123',
    email: 'user@example.com',
    name: 'John Doe',
    createdAt: new Date('2024-01-01'),
  });

  expect(response).toMatchSnapshot();
});

// Update snapshots with: vitest -u
```

### Spies and Method Tracking

```typescript
import * as userService from './user.service';

it('tracks method calls', async () => {
  const spy = vi.spyOn(userService, 'findById');

  await userService.findById('123');

  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy).toHaveBeenCalledWith('123');

  spy.mockRestore();
});
```

### Fake Timers

```typescript
it('expires tokens after 1 hour', () => {
  vi.useFakeTimers();
  const now = new Date('2024-01-01T12:00:00Z');
  vi.setSystemTime(now);

  const token = generateToken();

  // Advance time by 1 hour
  vi.advanceTimersByTime(60 * 60 * 1000);

  expect(isTokenExpired(token)).toBe(true);

  vi.useRealTimers();
});
```

---

## Supertest Integration Testing

```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { app } from '../src/app';
import { db } from '../src/db';

describe('POST /api/users', () => {
  beforeAll(async () => {
    await db.$connect();
  });

  afterAll(async () => {
    await db.$disconnect();
  });

  it('creates user with valid data', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({
        email: 'john@example.com',
        name: 'John Doe',
      })
      .expect(201)
      .expect('Content-Type', /json/);

    expect(response.body).toMatchObject({
      email: 'john@example.com',
      name: 'John Doe',
    });
    expect(response.body.id).toBeDefined();
    expect(response.body.password).toBeUndefined(); // Should not leak password
  });

  it('returns 400 for invalid email', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({
        email: 'invalid',
        name: 'John Doe',
      })
      .expect(400);

    expect(response.body.error).toBeDefined();
  });

  it('returns 409 for duplicate email', async () => {
    // Create user
    await request(app)
      .post('/api/users')
      .send({ email: 'duplicate@example.com', name: 'User 1' });

    // Attempt duplicate
    const response = await request(app)
      .post('/api/users')
      .send({ email: 'duplicate@example.com', name: 'User 2' })
      .expect(409);

    expect(response.body.error.message).toContain('already registered');
  });

  it('requires authentication', async () => {
    await request(app)
      .get('/api/users/me')
      .expect(401);
  });

  it('allows authenticated requests', async () => {
    const token = 'valid-jwt-token';

    await request(app)
      .get('/api/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
  });
});
```

---

## Test Containers

Docker-based testing for real database and Redis instances in CI.

```typescript
import { GenericContainer, StartedTestContainer } from 'testcontainers';
import { beforeAll, afterAll } from 'vitest';

let postgresContainer: StartedTestContainer;
let redisContainer: StartedTestContainer;

beforeAll(async () => {
  // Start PostgreSQL container
  postgresContainer = await new GenericContainer('postgres:16')
    .withEnvironment({
      POSTGRES_USER: 'test',
      POSTGRES_PASSWORD: 'test',
      POSTGRES_DB: 'test',
    })
    .withExposedPorts(5432)
    .start();

  // Start Redis container
  redisContainer = await new GenericContainer('redis:7')
    .withExposedPorts(6379)
    .start();

  // Set environment variables
  process.env.DATABASE_URL = `postgresql://test:test@localhost:${postgresContainer.getMappedPort(5432)}/test`;
  process.env.REDIS_URL = `redis://localhost:${redisContainer.getMappedPort(6379)}`;
}, 60000); // Increase timeout for container startup

afterAll(async () => {
  await postgresContainer.stop();
  await redisContainer.stop();
});
```

---

## Node.js 22+ Built-in Test Runner

### Basic Testing

```typescript
// user.test.ts
import { describe, it, test, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';

describe('User Service', () => {
  let db;

  beforeEach(() => {
    db = setupTestDatabase();
  });

  afterEach(() => {
    db.cleanup();
  });

  it('creates user with valid data', async () => {
    const user = await createUser({ email: 'test@example.com' });
    assert.strictEqual(user.email, 'test@example.com');
    assert.ok(user.id);
  });

  test('throws on duplicate email', async () => {
    await createUser({ email: 'dup@example.com' });
    await assert.rejects(
      async () => createUser({ email: 'dup@example.com' }),
      { message: /already registered/ }
    );
  });
});

// Run with:
// node --test
// node --test --watch  # Watch mode
```

---

## Module Mocking (Node.js 22.3+)

```bash
# Run with experimental flag
node --test --experimental-test-module-mocks
```

```typescript
import { test, mock } from 'node:test';
import assert from 'node:assert';

test('mocks module', async (t) => {
  const emailService = await import('./email-service.js');

  // Mock function
  mock.method(emailService, 'send', async () => {
    return { success: true };
  });

  const result = await emailService.send('test@example.com', 'Hello');
  assert.deepStrictEqual(result, { success: true });

  // Verify calls
  assert.strictEqual(emailService.send.mock.calls.length, 1);
});
```

---

## Built-in SQLite for Testing

Node.js 22.5+ includes built-in SQLite support, useful for lightweight test databases.

```bash
# Run with experimental flag
node --experimental-sqlite
```

```typescript
import { DatabaseSync } from 'node:sqlite';

const db = new DatabaseSync(':memory:');

// Create table
db.exec(`
  CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL
  )
`);

// Prepared statements
const insert = db.prepare('INSERT INTO users (email, name) VALUES (?, ?)');
insert.run('user@example.com', 'John Doe');

const select = db.prepare('SELECT * FROM users WHERE email = ?');
const user = select.get('user@example.com');

console.log(user); // { id: 1, email: 'user@example.com', name: 'John Doe' }

// Transactions
db.exec('BEGIN');
try {
  insert.run('user2@example.com', 'Jane Doe');
  insert.run('user3@example.com', 'Bob Smith');
  db.exec('COMMIT');
} catch (err) {
  db.exec('ROLLBACK');
  throw err;
}

db.close();
```

---

## Best Practices

1. **Vitest for most projects** - Fast, ESM-native, compatible with Jest API
2. **Supertest for API integration tests** - Test full HTTP request/response cycle
3. **Testcontainers for CI** - Real database containers instead of mocks for integration tests
4. **Fake timers for time-dependent logic** - Token expiry, caching, scheduled tasks
5. **Snapshot testing for response structures** - Detect unintended API changes
6. **Separate unit and integration tests** - Unit tests run fast in isolation, integration tests use real dependencies
7. **Clean up after each test** - Truncate tables, clear mocks, reset state
8. **Test error paths** - 400, 401, 403, 404, 409, 500 responses
9. **Never leak secrets in test assertions** - Verify password fields are excluded from responses
10. **Use `Test.startTest()`/`Test.stopTest()` equivalent** - `vi.useFakeTimers()` and `vi.useRealTimers()` for controlled time

---

## Anti-Patterns

- Testing implementation details instead of behavior
- Sharing mutable state between tests (leads to flaky tests)
- Not cleaning up database state after each test
- Using real external services in unit tests (use mocks)
- Ignoring test coverage gaps in error handling paths
- Hardcoding test data that couples to specific database state
- Missing timeout configuration for container-based tests
- Writing tests that pass only in a specific order

---

## Sources & References

- [Node.js Test Runner: A Beginner's Guide | Better Stack](https://betterstack.com/community/guides/testing/nodejs-test-runner/)
- [How to Use SQLite in Node.js Applications](https://oneuptime.com/blog/post/2026-02-02-sqlite-nodejs/view)
- [Node.js' Built-in SQLite Support | Brian Douglass](https://bhdouglass.com/blog/nodejs-built-in-sqlite-support/)
- [Vitest in 2026: The New Standard for Modern JavaScript Testing](https://jeffbruchado.com.br/en/blog/vitest-2026-standard-modern-javascript-testing)
- [An advanced guide to Vitest testing and mocking](https://blog.logrocket.com/advanced-guide-vitest-testing-mocking/)
- [Snapshot | Guide | Vitest](https://vitest.dev/guide/snapshot)
