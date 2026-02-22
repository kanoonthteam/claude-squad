---
name: node-architecture
description: Node.js project architecture patterns — Express/Fastify/Hono framework selection, TypeScript 5.x, clean architecture, DI, config management, error handling, NestJS
---

# Node.js Architecture & Project Structure

Production-ready architecture patterns for Node.js 2026. Covers modern framework selection (Express vs Fastify vs Hono), TypeScript 5.x advanced features, project structure, NestJS patterns, dependency injection, configuration management, error handling architecture, and graceful shutdown.

## Table of Contents

1. [Modern Framework Selection](#modern-framework-selection)
2. [TypeScript 5.x Advanced Patterns](#typescript-5x-advanced-patterns)
3. [Fastify Production Structure](#fastify-production-structure)
4. [NestJS Advanced Architecture](#nestjs-advanced-architecture)
5. [Error Handling Architecture](#error-handling-architecture)
6. [Environment Configuration](#environment-configuration)
7. [Graceful Shutdown](#graceful-shutdown)
8. [Health Checks](#health-checks)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)

---

## Modern Framework Selection

### Express vs Fastify vs Hono (2026)

**Performance Benchmarks:**
- Express: ~15,000 req/s (baseline)
- Fastify: ~30,000 req/s (2.3x faster, 50% less latency)
- Hono: ~25,000 req/s (3x faster than Express, 30% less memory than Fastify)

**When to Use Each:**

```typescript
// Express: Traditional web apps, rapid prototyping, ecosystem maturity
import express from 'express';
const app = express();

// Pros: Largest ecosystem, battle-tested, extensive middleware
// Cons: Slower, older patterns, callback-based middleware

// Fastify: High-throughput APIs, modern Node.js apps
import Fastify from 'fastify';
const fastify = Fastify({ logger: true });

// Pros: 2-3x faster, schema-based validation, modern async/await
// Cons: Smaller ecosystem than Express

// Hono: Edge computing, multi-runtime apps (Cloudflare Workers, Bun, Deno)
import { Hono } from 'hono';
const app = new Hono();

// Pros: Cross-runtime, lightweight, edge-ready, TypeScript-first
// Cons: Newer ecosystem, less middleware available
```

**Staff Engineer Decision Matrix:**
- **Express**: Legacy systems, large existing codebases, enterprise apps with heavy middleware needs
- **Fastify**: Microservices, high-performance APIs, modern greenfield projects
- **Hono**: Serverless/edge deployments, multi-runtime requirements, modern full-stack apps

---

## TypeScript 5.x Advanced Patterns

### Const Type Parameters (TS 5.0+)

```typescript
// Preserve literal types in generics
function asArray<const T>(values: T[]): T[] {
  return values;
}

const colors = asArray(['red', 'blue', 'green']);
// Type: ('red' | 'blue' | 'green')[] instead of string[]

// Real-world use case: Type-safe route definitions
function defineRoutes<const T extends Record<string, string>>(routes: T): T {
  return routes;
}

const routes = defineRoutes({
  home: '/',
  users: '/users',
  userDetail: '/users/:id',
});
// Type: { home: '/', users: '/users', userDetail: '/users/:id' }
```

### Satisfies Operator (TS 4.9+)

```typescript
// Validate type while preserving literal information
type Route = {
  path: string;
  method: 'GET' | 'POST' | 'PUT' | 'DELETE';
};

const apiRoutes = {
  getUsers: { path: '/users', method: 'GET' },
  createUser: { path: '/users', method: 'POST' },
} satisfies Record<string, Route>;

// Can still narrow: apiRoutes.getUsers.method is 'GET', not 'GET' | 'POST' | ...
```

### Using and Await Using (TS 5.2+)

```typescript
// Automatic resource disposal
class DatabaseConnection implements Disposable {
  [Symbol.dispose]() {
    this.close();
  }

  close() {
    console.log('Connection closed');
  }

  query(sql: string) {
    console.log('Executing:', sql);
  }
}

function processData() {
  using db = new DatabaseConnection();
  db.query('SELECT * FROM users');
  // db.close() called automatically at end of scope
}

// Async version
class AsyncDatabaseConnection implements AsyncDisposable {
  async [Symbol.asyncDispose]() {
    await this.close();
  }

  async close() {
    console.log('Closing async connection');
  }
}

async function processDataAsync() {
  await using db = new AsyncDatabaseConnection();
  // Automatic cleanup even if error is thrown
}
```

### Decorators (TS 5.0+ Stage 3)

```typescript
// Modern decorator pattern (aligned with TC39 proposal)
function LogExecutionTime() {
  return function (
    target: any,
    propertyKey: string,
    descriptor: PropertyDescriptor
  ) {
    const originalMethod = descriptor.value;

    descriptor.value = async function (...args: any[]) {
      const start = Date.now();
      const result = await originalMethod.apply(this, args);
      const duration = Date.now() - start;
      console.log(`${propertyKey} took ${duration}ms`);
      return result;
    };

    return descriptor;
  };
}

class UserService {
  @LogExecutionTime()
  async findUsers() {
    // Method implementation
  }
}
```

---

## Fastify Production Structure

```
src/
├── app.ts                      # Fastify app factory
├── server.ts                   # Server entry point
├── config/
│   ├── env.ts                  # Environment config (Zod validation)
│   └── database.ts             # Database connection
├── plugins/
│   ├── auth.ts                 # Auth plugin
│   ├── cors.ts                 # CORS config
│   └── rate-limit.ts           # Rate limiting
├── routes/
│   ├── users/
│   │   ├── index.ts            # Route registration
│   │   ├── handlers.ts         # Route handlers
│   │   ├── schemas.ts          # Zod/JSON schemas
│   │   └── handlers.test.ts    # Handler tests
│   └── health/
│       └── index.ts
├── services/
│   ├── user.service.ts         # Business logic
│   ├── user.service.test.ts
│   └── email.service.ts
├── repositories/
│   ├── user.repository.ts      # Data access layer
│   └── user.repository.test.ts
├── models/
│   ├── user.model.ts           # Domain models
│   └── types.ts                # Shared types
├── middleware/
│   ├── auth.middleware.ts
│   ├── validate.middleware.ts
│   └── error.middleware.ts
├── utils/
│   ├── logger.ts               # Pino logger
│   ├── errors.ts               # Custom error classes
│   └── crypto.ts               # Encryption utilities
├── workers/
│   ├── email.worker.ts         # Background jobs
│   └── analytics.worker.ts
└── db/
    ├── migrations/
    └── seeds/
```

**Key Principles:**
- Feature-based route modules with co-located tests
- Services contain business logic, repositories handle data access
- Plugins encapsulate cross-cutting concerns (auth, CORS, rate limiting)
- Workers handle background/CPU-intensive tasks

---

## NestJS Advanced Architecture

### Custom Decorators and Guards

```typescript
// Custom decorator for role-based access
import { SetMetadata } from '@nestjs/common';
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const Roles = (...roles: string[]) => SetMetadata('roles', roles);

// Current user decorator
export const CurrentUser = createParamDecorator(
  (data: unknown, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    return request.user;
  },
);

// Usage in controller
@Controller('users')
export class UsersController {
  @Get('profile')
  @Roles('admin', 'user')
  getProfile(@CurrentUser() user: User) {
    return user;
  }
}

// Guard implementation
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<string[]>('roles', [
      context.getHandler(),
      context.getClass(),
    ]);

    if (!requiredRoles) return true;

    const { user } = context.switchToHttp().getRequest();
    return requiredRoles.some((role) => user.roles?.includes(role));
  }
}
```

### Interceptors and Pipes

```typescript
// Interceptor for response transformation
@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, Response<T>> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<Response<T>> {
    return next.handle().pipe(
      map(data => ({
        success: true,
        data,
        timestamp: new Date().toISOString(),
      })),
    );
  }
}

// Pipe for advanced validation
@Injectable()
export class ParseObjectIdPipe implements PipeTransform {
  transform(value: any, metadata: ArgumentMetadata) {
    const validObjectId = /^[0-9a-fA-F]{24}$/;
    if (!validObjectId.test(value)) {
      throw new BadRequestException('Invalid ObjectId');
    }
    return value;
  }
}
```

### Microservices Pattern

```typescript
// main.ts
const app = await NestFactory.createMicroservice<MicroserviceOptions>(
  AppModule,
  {
    transport: Transport.RMQ,
    options: {
      urls: ['amqp://localhost:5672'],
      queue: 'users_queue',
      queueOptions: { durable: false },
    },
  },
);

// Controller with message patterns
@Controller()
export class UsersController {
  @MessagePattern({ cmd: 'get_user' })
  async getUser(@Payload() id: string): Promise<User> {
    return this.usersService.findById(id);
  }

  @EventPattern('user_created')
  async handleUserCreated(@Payload() data: CreateUserDto) {
    // Handle event (no response sent)
  }
}
```

---

## Error Handling Architecture

### Custom Error Hierarchy

```typescript
// errors.ts
export class ApplicationError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public isOperational: boolean = true
  ) {
    super(message);
    this.name = this.constructor.name;
    Error.captureStackTrace(this, this.constructor);
  }
}

// Operational errors (expected, recoverable)
export class BadRequestError extends ApplicationError {
  constructor(message: string) {
    super(400, message);
  }
}

export class UnauthorizedError extends ApplicationError {
  constructor(message: string = 'Unauthorized') {
    super(401, message);
  }
}

export class ForbiddenError extends ApplicationError {
  constructor(message: string = 'Forbidden') {
    super(403, message);
  }
}

export class NotFoundError extends ApplicationError {
  constructor(resource: string) {
    super(404, `${resource} not found`);
  }
}

export class ConflictError extends ApplicationError {
  constructor(message: string) {
    super(409, message);
  }
}

export class ValidationError extends ApplicationError {
  constructor(
    message: string,
    public errors: Record<string, string[]>
  ) {
    super(422, message);
  }
}

// Database errors
export class DatabaseError extends ApplicationError {
  constructor(message: string) {
    super(500, message);
    this.isOperational = false; // Not recoverable
  }
}

// External API errors
export class ExternalServiceError extends ApplicationError {
  constructor(service: string, message: string) {
    super(503, `${service}: ${message}`);
  }
}
```

### Error Handler Middleware

```typescript
// Error handler middleware
export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) {
  if (err instanceof ApplicationError) {
    // Operational error - send response and log warning
    logger.warn({
      err,
      statusCode: err.statusCode,
      path: req.path,
      method: req.method,
    });

    return res.status(err.statusCode).json({
      error: {
        message: err.message,
        ...(err instanceof ValidationError && { errors: err.errors }),
      },
    });
  }

  // Programmer error - log full stack and crash gracefully
  logger.error({
    err,
    message: 'Unhandled error - process will exit',
    stack: err.stack,
  });

  res.status(500).json({
    error: {
      message: 'Internal server error',
    },
  });

  // Crash on programmer errors (undefined state)
  process.exit(1);
}

// Async error wrapper
export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<any>
) {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

// Usage
app.get('/users/:id', asyncHandler(async (req, res) => {
  const user = await db.user.findUnique({ where: { id: req.params.id } });
  if (!user) throw new NotFoundError('User');
  res.json(user);
}));
```

### Domain-Specific Errors

```typescript
export class InsufficientFundsError extends ApplicationError {
  constructor(available: number, required: number) {
    super(400, `Insufficient funds: ${available} available, ${required} required`);
  }
}

export class EmailAlreadyRegisteredError extends ConflictError {
  constructor(email: string) {
    super(`Email ${email} is already registered`);
  }
}
```

---

## Environment Configuration

```typescript
// config/env.ts
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']),
  PORT: z.string().transform(Number).pipe(z.number().min(1).max(65535)),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  ALLOWED_ORIGINS: z.string().transform(s => s.split(',')),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error']).default('info'),
});

export const env = envSchema.parse(process.env);
```

---

## Graceful Shutdown

```typescript
import { fastify } from 'fastify';

const app = fastify();

async function gracefulShutdown(signal: string) {
  console.log(`Received ${signal}, starting graceful shutdown`);

  // Stop accepting new requests
  await app.close();

  // Close database connections
  await db.$disconnect();

  // Close Redis connections
  await redis.quit();

  // Close message queues
  await worker.close();

  console.log('Graceful shutdown complete');
  process.exit(0);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Unhandled errors
process.on('unhandledRejection', (reason, promise) => {
  logger.error({ reason, promise }, 'Unhandled rejection');
  process.exit(1);
});

process.on('uncaughtException', (error) => {
  logger.error({ error }, 'Uncaught exception');
  process.exit(1);
});
```

---

## Health Checks

```typescript
app.get('/health', async (req, res) => {
  const checks = {
    uptime: process.uptime(),
    timestamp: Date.now(),
    database: false,
    redis: false,
  };

  // Database check
  try {
    await db.$queryRaw`SELECT 1`;
    checks.database = true;
  } catch (err) {
    logger.error({ err }, 'Database health check failed');
  }

  // Redis check
  try {
    await redis.ping();
    checks.redis = true;
  } catch (err) {
    logger.error({ err }, 'Redis health check failed');
  }

  const allHealthy = checks.database && checks.redis;

  res.status(allHealthy ? 200 : 503).send({
    status: allHealthy ? 'healthy' : 'unhealthy',
    checks,
  });
});
```

---

## Best Practices

1. **Framework selection by use case** - Express for legacy, Fastify for performance, Hono for edge
2. **Zod for environment validation** - Fail fast on missing/invalid config at startup
3. **Layered architecture** - Routes -> Services -> Repositories -> Models
4. **Custom error hierarchy** - Separate operational from programmer errors
5. **Graceful shutdown** - Close connections and stop accepting requests before exiting
6. **Health checks** - Deep checks for database, Redis, and external dependencies
7. **TypeScript 5.x features** - Use `using` for resource disposal, `satisfies` for type validation
8. **NestJS for enterprise** - Decorators, guards, interceptors, and DI for large teams

---

## Anti-Patterns

- Starting server without validating environment variables
- Missing error handler middleware (unhandled promise rejections crash the process)
- Mixing business logic in route handlers (use service layer)
- Not implementing graceful shutdown (data loss on deploy)
- Using `any` type instead of proper TypeScript generics
- Hardcoding configuration values instead of using environment variables
- Catching errors silently without logging
- Not differentiating operational vs programmer errors

---

## Sources & References

- [Fastify vs Express vs Hono: Choosing the Right Node.js Framework](https://medium.com/@arifdewi/fastify-vs-express-vs-hono-choosing-the-right-node-js-framework-for-your-project-da629adebd4e)
- [Hono vs Fastify | Better Stack Community](https://betterstack.com/community/guides/scaling-nodejs/hono-vs-fastify/)
- [TypeScript 5.x and Beyond: The New Era of Type-Safe Development](https://medium.com/@beenakumawat004/typescript-5-x-and-beyond-the-new-era-of-type-safe-development-c984eec4225f)
- [What Is NestJS? A Practical 2026 Guide](https://thelinuxcode.com/what-is-nestjs-a-practical-2026-guide-to-building-scalable-nodejs-backends/)
- [Mastering Custom Decorators and Metadata in NestJS](https://shiftasia.com/community/mastering-custom-decorators-and-metadata-in-nestjs/)
- [Node.js Error Handling Strategies for Production](https://www.grizzlypeaksoftware.com/library/nodejs-error-handling-strategies-for-production-dr9osrof)
- [Best Practices for Node.js Error-handling | Toptal](https://www.toptal.com/nodejs/node-js-error-handling)
- [Better Error Handling In NodeJS With Error Classes](https://www.smashingmagazine.com/2020/08/error-handling-nodejs-error-classes/)
