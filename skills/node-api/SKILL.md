---
name: node-api
description: Node.js API design patterns — REST with OpenAPI, tRPC, GraphQL Pothos, Prisma/Drizzle ORM, Zod validation, JWT auth, rate limiting, pagination
---

# Node.js API Design & Data Access

Production-ready API design patterns for Node.js 2026. Covers REST API with OpenAPI/Swagger, tRPC for TypeScript-first APIs, GraphQL with Pothos, ORM patterns (Prisma and Drizzle), Zod validation, JWT authentication, rate limiting, and CORS configuration.

## Table of Contents

1. [ORM Patterns - Prisma](#orm-patterns---prisma)
2. [ORM Patterns - Drizzle](#orm-patterns---drizzle)
3. [OpenAPI/Swagger with Fastify](#openapiswagger-with-fastify)
4. [tRPC TypeScript-First APIs](#trpc-typescript-first-apis)
5. [GraphQL with Pothos](#graphql-with-pothos)
6. [Authentication & Authorization](#authentication--authorization)
7. [Security Hardening](#security-hardening)
8. [Best Practices](#best-practices)
9. [Anti-Patterns](#anti-patterns)

---

## ORM Patterns - Prisma

### Schema and Transactions

```typescript
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
  previewFeatures = ["postgresqlExtensions"]
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(cuid())
  email     String   @unique
  posts     Post[]
  profile   Profile?
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@index([email])
  @@map("users")
}

// Interactive transactions (recommended for complex operations)
async function transferFunds(fromId: string, toId: string, amount: number) {
  return await prisma.$transaction(async (tx) => {
    const from = await tx.account.update({
      where: { id: fromId },
      data: { balance: { decrement: amount } },
    });

    if (from.balance < 0) {
      throw new Error('Insufficient funds');
    }

    await tx.account.update({
      where: { id: toId },
      data: { balance: { increment: amount } },
    });

    return { from, to: toId, amount };
  }, {
    maxWait: 5000,
    timeout: 10000,
  });
}
```

### Prisma Client Extensions

```typescript
// Prisma Client Extensions (middleware alternative)
const prisma = new PrismaClient().$extends({
  query: {
    user: {
      async create({ args, query }) {
        if (args.data.password) {
          args.data.password = await bcrypt.hash(args.data.password, 10);
        }
        return query(args);
      },
    },
  },
  result: {
    user: {
      fullName: {
        needs: { firstName: true, lastName: true },
        compute(user) {
          return `${user.firstName} ${user.lastName}`;
        },
      },
    },
  },
});

// Relation queries optimization
async function getUsersWithPosts() {
  return prisma.user.findMany({
    select: {
      id: true,
      email: true,
      posts: {
        select: { id: true, title: true },
        orderBy: { createdAt: 'desc' },
        take: 5,
      },
      _count: {
        select: { posts: true },
      },
    },
  });
}

// Raw queries - ALWAYS use tagged templates for security
async function complexQuery(status: string) {
  // SAFE: Parameterized query
  const users = await prisma.$queryRaw`
    SELECT u.*, COUNT(p.id) as post_count
    FROM users u
    LEFT JOIN posts p ON p.user_id = u.id
    WHERE p.status = ${status}
    GROUP BY u.id
    HAVING COUNT(p.id) > 5
  `;
  return users;
}
```

---

## ORM Patterns - Drizzle

### Schema and Type-Safe Queries

```typescript
// drizzle/schema.ts
import { pgTable, text, timestamp, uuid, index } from 'drizzle-orm/pg-core';
import { relations } from 'drizzle-orm';

export const users = pgTable('users', {
  id: uuid('id').defaultRandom().primaryKey(),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => ({
  emailIdx: index('email_idx').on(table.email),
}));

export const posts = pgTable('posts', {
  id: uuid('id').defaultRandom().primaryKey(),
  title: text('title').notNull(),
  content: text('content'),
  userId: uuid('user_id').references(() => users.id).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

// Define relations
export const usersRelations = relations(users, ({ many }) => ({
  posts: many(posts),
}));

export const postsRelations = relations(posts, ({ one }) => ({
  user: one(users, {
    fields: [posts.userId],
    references: [users.id],
  }),
}));

// drizzle/db.ts
import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import * as schema from './schema';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
export const db = drizzle(pool, { schema });
```

### Queries and Transactions

```typescript
import { eq, and, gte, sql } from 'drizzle-orm';

// Type-safe queries with full SQL control
async function findActiveUsers(since: Date) {
  return db.select()
    .from(users)
    .where(gte(users.createdAt, since))
    .limit(100);
}

// Join queries
async function getUsersWithPostCount() {
  return db.select({
    id: users.id,
    email: users.email,
    postCount: sql<number>`count(${posts.id})`,
  })
    .from(users)
    .leftJoin(posts, eq(users.id, posts.userId))
    .groupBy(users.id);
}

// Transactions
async function createUserWithPost(userData: any, postData: any) {
  return db.transaction(async (tx) => {
    const [user] = await tx.insert(users).values(userData).returning();
    const [post] = await tx.insert(posts).values({
      ...postData,
      userId: user.id,
    }).returning();
    return { user, post };
  });
}

// Type-safe enum patterns
import { pgEnum } from 'drizzle-orm/pg-core';

export const userRole = pgEnum('user_role', ['admin', 'user', 'guest']);
```

**Prisma vs Drizzle Decision Matrix:**
- **Prisma**: Schema-first, generated client, migrations, excellent DevX, abstracts SQL
- **Drizzle**: Code-first, SQL-like API, lightweight, full control over queries, closer to SQL

---

## OpenAPI/Swagger with Fastify

```typescript
import Fastify from 'fastify';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';

const app = Fastify();

await app.register(swagger, {
  openapi: {
    info: {
      title: 'User API',
      version: '1.0.0',
    },
    servers: [{ url: 'http://localhost:3000' }],
  },
});

await app.register(swaggerUi, {
  routePrefix: '/docs',
});

// Schema-based validation + auto-generated docs
const userSchema = {
  type: 'object',
  required: ['email', 'name'],
  properties: {
    email: { type: 'string', format: 'email' },
    name: { type: 'string', minLength: 1 },
  },
};

app.post('/users', {
  schema: {
    description: 'Create a new user',
    tags: ['users'],
    body: userSchema,
    response: {
      201: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          email: { type: 'string' },
          name: { type: 'string' },
        },
      },
    },
  },
}, async (request, reply) => {
  const user = await createUser(request.body);
  reply.code(201).send(user);
});
```

---

## tRPC TypeScript-First APIs

```typescript
// server/trpc.ts
import { initTRPC } from '@trpc/server';
import { z } from 'zod';

const t = initTRPC.create();

export const appRouter = t.router({
  getUser: t.procedure
    .input(z.string())
    .query(async ({ input }) => {
      const user = await db.user.findUnique({ where: { id: input } });
      return user;
    }),

  createUser: t.procedure
    .input(z.object({
      email: z.string().email(),
      name: z.string().min(1),
    }))
    .mutation(async ({ input }) => {
      const user = await db.user.create({ data: input });
      return user;
    }),
});

export type AppRouter = typeof appRouter;

// client.ts - Full type safety across network boundary
import { createTRPCProxyClient, httpBatchLink } from '@trpc/client';
import type { AppRouter } from './server/trpc';

const client = createTRPCProxyClient<AppRouter>({
  links: [
    httpBatchLink({ url: 'http://localhost:3000/trpc' }),
  ],
});

// Fully typed, autocomplete works
const user = await client.getUser.query('user-id');
//    ^? User | null
```

**When to use tRPC:**
- Full-stack TypeScript apps (Next.js, SvelteKit)
- Internal APIs, microservices within TS ecosystem
- Near-zero manual typing needed
- NOT for public APIs (requires TS client)
- NOT for multi-language environments

---

## GraphQL with Pothos

```typescript
import SchemaBuilder from '@pothos/core';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const builder = new SchemaBuilder<{
  PrismaTypes: PrismaTypes;
}>({
  plugins: ['prisma'],
  prisma: { client: prisma },
});

builder.queryType({
  fields: (t) => ({
    user: t.prismaField({
      type: 'User',
      args: {
        id: t.arg.string({ required: true }),
      },
      resolve: async (query, root, args) =>
        prisma.user.findUniqueOrThrow({
          ...query,
          where: { id: args.id },
        }),
    }),
  }),
});

builder.mutationType({
  fields: (t) => ({
    createUser: t.prismaField({
      type: 'User',
      args: {
        email: t.arg.string({ required: true }),
        name: t.arg.string({ required: true }),
      },
      resolve: async (query, root, args) =>
        prisma.user.create({
          ...query,
          data: { email: args.email, name: args.name },
        }),
    }),
  }),
});

export const schema = builder.toSchema();
```

**When to use GraphQL:**
- Complex data requirements, graph-heavy apps
- Headless CMS integrations (Shopify, Contentful)
- Mobile apps needing flexible queries
- Aggregating multiple backend sources

---

## Authentication & Authorization

### JWT with Passport.js

```typescript
import passport from 'passport';
import { Strategy as JwtStrategy, ExtractJwt } from 'passport-jwt';
import { Strategy as LocalStrategy } from 'passport-local';
import bcrypt from 'bcrypt';

// Local strategy for username/password
passport.use(new LocalStrategy(
  { usernameField: 'email' },
  async (email, password, done) => {
    try {
      const user = await db.user.findUnique({ where: { email } });
      if (!user) return done(null, false, { message: 'Invalid credentials' });

      const isValid = await bcrypt.compare(password, user.password);
      if (!isValid) return done(null, false, { message: 'Invalid credentials' });

      return done(null, user);
    } catch (error) {
      return done(error);
    }
  }
));

// JWT strategy for token-based auth
passport.use(new JwtStrategy(
  {
    jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
    secretOrKey: process.env.JWT_SECRET,
  },
  async (payload, done) => {
    try {
      const user = await db.user.findUnique({ where: { id: payload.sub } });
      if (!user) return done(null, false);
      return done(null, user);
    } catch (error) {
      return done(error, false);
    }
  }
));

// Token generation with refresh rotation
const JWT_CONFIG = {
  accessTokenExpiry: '15m',
  refreshTokenExpiry: '7d',
  algorithm: 'HS256',
};

async function generateTokens(userId: string) {
  const accessToken = jwt.sign(
    { sub: userId },
    process.env.JWT_SECRET,
    { expiresIn: JWT_CONFIG.accessTokenExpiry }
  );

  const refreshToken = jwt.sign(
    { sub: userId, type: 'refresh' },
    process.env.JWT_REFRESH_SECRET,
    { expiresIn: JWT_CONFIG.refreshTokenExpiry }
  );

  // Store refresh token in database for revocation capability
  await db.refreshToken.create({
    data: { token: refreshToken, userId },
  });

  return { accessToken, refreshToken };
}
```

---

## Security Hardening

### Helmet, Rate Limiting, CORS, Input Sanitization

```typescript
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import RedisStore from 'rate-limit-redis';
import cors from 'cors';
import { z } from 'zod';
import validator from 'validator';

// Helmet - production-ready config
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", 'data:', 'https:'],
    },
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true,
  },
}));

// Rate limiting with Redis store
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  store: new RedisStore({
    client: redisClient,
    prefix: 'rl:api:',
  }),
});

// Strict limit for auth endpoints
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  skipSuccessfulRequests: true,
  store: new RedisStore({
    client: redisClient,
    prefix: 'rl:auth:',
  }),
});

app.use('/api/', apiLimiter);
app.use('/api/auth/', authLimiter);

// CORS configuration
const corsOptions = {
  origin: (origin, callback) => {
    const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || [];
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  credentials: true,
  maxAge: 86400,
};

app.use(cors(corsOptions));

// Zod validation with sanitization
const createUserSchema = z.object({
  email: z.string().email().transform(val => validator.normalizeEmail(val)),
  name: z.string()
    .min(1)
    .max(100)
    .transform(val => validator.escape(val)),
  password: z.string()
    .min(8)
    .regex(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])/,
      'Password must contain uppercase, lowercase, number, and special character'
    ),
});
```

---

## Best Practices

1. **Prisma for rapid development** - Schema-first with great tooling and migrations
2. **Drizzle for SQL control** - When you need full query control and lightweight footprint
3. **tRPC for internal APIs** - Full-stack TypeScript with zero-cost type safety
4. **GraphQL for complex data** - When clients need flexible query capabilities
5. **OpenAPI for public APIs** - Schema-based validation and auto-generated documentation
6. **Refresh token rotation** - Short-lived access tokens, revocable refresh tokens
7. **Rate limiting by endpoint** - Stricter limits on auth endpoints
8. **Zod for all validation** - Runtime type checking with TypeScript inference

---

## Anti-Patterns

- Using `$queryRawUnsafe` with string interpolation (SQL injection)
- Missing rate limiting on authentication endpoints
- Storing JWT secrets in code instead of environment variables
- Not implementing refresh token rotation (single long-lived tokens)
- Returning database errors directly to clients (information leakage)
- Skipping CORS configuration (defaults to allow all origins)
- Using `SELECT *` equivalent queries (over-fetching data)
- Not validating request input with schemas

---

## Sources & References

- [Prisma Transactions and batch queries](https://www.prisma.io/docs/orm/prisma-client/queries/transactions)
- [Drizzle vs Prisma: Choosing the Right TypeScript ORM in 2026](https://medium.com/@codabu/drizzle-vs-prisma-choosing-the-right-typescript-orm-in-2026-deep-dive-63abb6aa882b)
- [tRPC vs GraphQL vs REST](https://sdtimes.com/graphql/trpc-vs-graphql-vs-rest-choosing-the-right-api-design-for-modern-web-applications/)
- [How to Use Passport.js for Authentication in Node.js](https://oneuptime.com/blog/post/2026-01-22-nodejs-passport-authentication/view)
- [Node.js Security Best Practices for 2026](https://medium.com/@sparklewebhelp/node-js-security-best-practices-for-2026-3b27fb1e8160)
- [OWASP Node.js Security Best Practices](https://rabson.medium.com/owasp-node-js-security-best-practices-fdf1b4f701cc)
- [How to Secure Node.js APIs Against Common Vulnerabilities](https://oneuptime.com/blog/post/2026-01-06-nodejs-api-security-owasp-top-10/view)
- [Drizzle ORM PostgreSQL Best Practices Guide](https://gist.github.com/productdevbook/7c9ce3bbeb96b3fabc3c7c2aa2abc717)
