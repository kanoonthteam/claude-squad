---
name: firebase-operations
description: Production-grade Firebase operations patterns -- App Hosting, Emulator Suite, CLI, Extensions, Performance Monitoring, cost optimization, migration patterns, and framework integration
---

# Firebase Operations -- Staff Engineer Patterns

Production-ready patterns for Firebase App Hosting (Next.js SSR, Angular), Emulator Suite (configuration, seed data, CI/CD), Firebase Extensions, cost optimization (read/write reduction, bundle caching), migration patterns (RTDB to Firestore, v8 to modular SDK), and framework integration (Flutter, Next.js).

## Table of Contents
1. [Firebase App Hosting](#firebase-app-hosting)
2. [Emulator Suite](#emulator-suite)
3. [Firebase Extensions](#firebase-extensions)
4. [Cost Optimization](#cost-optimization)
5. [Migration Patterns](#migration-patterns)
6. [Framework Integration](#framework-integration)
7. [Best Practices](#best-practices)
8. [Anti-Patterns](#anti-patterns)
9. [Common Commands](#common-commands)
10. [Sources & References](#sources--references)

---

## Firebase App Hosting

### Project Structure

```
firebase.json
firestore.rules
firestore.indexes.json
storage.rules
.firebaserc
functions/
  package.json
  tsconfig.json
  .env.local
  .secret.local
  src/
    index.ts
    config/
    triggers/
    api/
    utils/
hosting/
  public/
    index.html
    404.html
emulator-data/
  auth_export/
  firestore_export/
  storage_export/
scripts/
  seed-emulator.ts
  export-production.sh
```

### Indexing Strategies

```json
// firestore.indexes.json
{
  "indexes": [
    {
      "collectionGroup": "posts",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "posts",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "authorId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "posts",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "tags", "arrayConfig": "CONTAINS" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": [
    {
      "collectionGroup": "posts",
      "fieldPath": "content",
      "indexes": [
        { "order": "ASCENDING", "queryScope": "COLLECTION" }
      ]
    }
  ]
}
```

### Next.js App Router (App Hosting)

```typescript
// app/providers.tsx
'use client';

import { createContext, useContext } from 'react';
import { FirebaseApp } from 'firebase/app';
import { getFirebaseApp } from '@/lib/firebase-config';

const FirebaseContext = createContext<FirebaseApp | null>(null);

export function FirebaseProvider({ children }: { children: React.ReactNode }) {
  const app = getFirebaseApp();
  return (
    <FirebaseContext.Provider value={app}>
      {children}
    </FirebaseContext.Provider>
  );
}

export function useFirebase() {
  const context = useContext(FirebaseContext);
  if (!context) throw new Error('useFirebase must be used within FirebaseProvider');
  return context;
}

// app/layout.tsx
import { FirebaseProvider } from './providers';

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <FirebaseProvider>{children}</FirebaseProvider>
      </body>
    </html>
  );
}
```

---

## Emulator Suite

### Emulator Configuration

```json
// firebase.json
{
  "emulators": {
    "auth": {
      "port": 9099,
      "host": "127.0.0.1"
    },
    "functions": {
      "port": 5001,
      "host": "127.0.0.1"
    },
    "firestore": {
      "port": 8080,
      "host": "127.0.0.1"
    },
    "hosting": {
      "port": 5000,
      "host": "127.0.0.1"
    },
    "storage": {
      "port": 9199,
      "host": "127.0.0.1"
    },
    "pubsub": {
      "port": 8085,
      "host": "127.0.0.1"
    },
    "ui": {
      "enabled": true,
      "port": 4000,
      "host": "127.0.0.1"
    },
    "singleProjectMode": true
  }
}
```

### Seed Data for Emulators

```bash
#!/bin/bash
# scripts/seed-emulator.sh
firebase emulators:start --import=./emulator-data --export-on-exit=./emulator-data
```

```typescript
// scripts/seed-emulator.ts
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { initializeApp } from 'firebase-admin/app';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

initializeApp();

async function seedData() {
  const db = getFirestore();
  const auth = getAuth();

  // Create test users
  const users = [
    { email: 'admin@test.com', password: 'admin123', role: 'admin' },
    { email: 'user@test.com', password: 'user123', role: 'user' },
  ];

  for (const userData of users) {
    const userRecord = await auth.createUser({
      email: userData.email,
      password: userData.password,
      emailVerified: true,
    });

    await auth.setCustomUserClaims(userRecord.uid, { role: userData.role });

    await db.collection('users').doc(userRecord.uid).set({
      email: userData.email,
      role: userData.role,
      createdAt: new Date(),
    });
  }

  // Create test posts
  const posts = Array.from({ length: 20 }, (_, i) => ({
    title: `Test Post ${i + 1}`,
    content: `This is test content for post ${i + 1}`,
    authorId: users[0].email,
    createdAt: new Date(),
    likeCount: Math.floor(Math.random() * 100),
  }));

  const batch = db.batch();
  posts.forEach((post) => {
    const ref = db.collection('posts').doc();
    batch.set(ref, post);
  });
  await batch.commit();

  console.log('Seed data created successfully');
}

seedData().catch(console.error);
```

### CI/CD Integration

```yaml
# .github/workflows/test.yml
name: Test with Firebase Emulators

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Install Firebase CLI
        run: npm install -g firebase-tools

      - name: Run tests with emulators
        run: |
          firebase emulators:exec --only firestore,auth \
            "npm test" \
            --import=./emulator-data
```

---

## Firebase Extensions

### Popular Extensions (2025)

```bash
# Install extensions via CLI
firebase ext:install firebase/firestore-bigquery-export
firebase ext:install firebase/storage-resize-images
firebase ext:install firebase/firestore-send-email
firebase ext:install firebase/firestore-counter

# Configure extension
firebase ext:configure firestore-bigquery-export
```

### Custom Extension Development

```yaml
# extension.yaml
name: custom-data-validator
version: 0.1.0
specVersion: v1beta

displayName: Custom Data Validator
description: Validates Firestore writes against custom schemas

author:
  authorName: Your Company
  url: https://yourcompany.com

license: Apache-2.0
billingRequired: true

resources:
  - name: validateData
    type: firebaseextensions.v1beta.function
    properties:
      runtime: nodejs20
      eventTrigger:
        eventType: providers/cloud.firestore/eventTypes/document.write
        resource: projects/${PROJECT_ID}/databases/(default)/documents/{collection}/{docId}

params:
  - param: COLLECTION
    label: Collection to validate
    type: string
    required: true
```

---

## Cost Optimization

### Rate Limiting Pattern

```typescript
// Cloud Function rate limiter using Firestore
import { onRequest } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';

export const rateLimitedAPI = onRequest(async (req, res) => {
  const userId = req.headers['x-user-id'] as string;
  const db = getFirestore();
  const rateLimitRef = db.collection('rateLimits').doc(userId);

  try {
    await db.runTransaction(async (t) => {
      const doc = await t.get(rateLimitRef);
      const now = Date.now();
      const windowStart = now - 60000;  // 1 minute window

      const data = doc.data();
      const requests = (data?.requests || []).filter(
        (timestamp: number) => timestamp > windowStart
      );

      if (requests.length >= 100) {
        throw new Error('Rate limit exceeded');
      }

      requests.push(now);
      t.set(rateLimitRef, { requests }, { merge: true });
    });

    res.json({ success: true });
  } catch (error: any) {
    res.status(429).json({ error: error.message });
  }
});
```

### Offline Detection & Sync Status

```typescript
import { onSnapshot, enableNetwork, disableNetwork } from 'firebase/firestore';

function setupOfflineMonitoring() {
  const db = getFirestore();

  window.addEventListener('online', () => {
    console.log('Back online, enabling Firestore network...');
    enableNetwork(db);
  });

  window.addEventListener('offline', () => {
    console.log('Offline, Firestore will use cache...');
    disableNetwork(db);
  });
}

function listenWithMetadata(postId: string) {
  const db = getFirestore();
  return onSnapshot(
    doc(db, 'posts', postId),
    { includeMetadataChanges: true },
    (snapshot) => {
      const source = snapshot.metadata.fromCache ? 'cache' : 'server';
      console.log(`Data from ${source}`);
      if (snapshot.metadata.hasPendingWrites) {
        console.log('Local changes pending sync');
      }
    }
  );
}
```

### Cost Reduction Strategies

1. **Use aggregation queries** -- `count()`, `sum()`, `average()` are billed per 1000 index entries scanned (1 read per 1000).
2. **Cache with bundles** -- Pre-generate Firestore bundles and serve from CDN to eliminate document reads on initial load.
3. **Use `getCountFromServer()` instead of fetching all docs** -- Counting 10,000 documents costs 10 reads with aggregation vs 10,000 reads by fetching.
4. **Listener optimization** -- Use `where()` and `limit()` on real-time listeners. Unfiltered collection listeners bill for every document change.
5. **Disable unused emulator ports** -- Only run emulators you need (`--only firestore,auth`).

---

## Migration Patterns

### Realtime Database to Firestore

```typescript
import { getDatabase, ref, get } from 'firebase/database';
import { getFirestore, collection, writeBatch, doc } from 'firebase/firestore';

async function migrateRTDBToFirestore() {
  const rtdb = getDatabase();
  const db = getFirestore();

  const snapshot = await get(ref(rtdb, 'posts'));
  const posts = snapshot.val();

  const batches: any[] = [];
  let currentBatch = writeBatch(db);
  let batchCount = 0;

  Object.entries(posts).forEach(([id, data]) => {
    const docRef = doc(collection(db, 'posts'));
    currentBatch.set(docRef, data);
    batchCount++;

    if (batchCount === 500) {
      batches.push(currentBatch);
      currentBatch = writeBatch(db);
      batchCount = 0;
    }
  });

  if (batchCount > 0) batches.push(currentBatch);

  await Promise.all(batches.map(batch => batch.commit()));
  console.log(`Migrated ${Object.keys(posts).length} posts`);
}
```

### v8 to Modular SDK Migration

```typescript
// Before (v8 - Namespaced API)
import firebase from 'firebase/app';
import 'firebase/firestore';

const db = firebase.firestore();
db.collection('posts').get().then(snapshot => {
  snapshot.forEach(doc => console.log(doc.data()));
});

// After (v11 - Modular API)
import { getFirestore, collection, getDocs } from 'firebase/firestore';

const db = getFirestore();
const snapshot = await getDocs(collection(db, 'posts'));
snapshot.forEach(doc => console.log(doc.data()));

// Gradual migration with compat layer
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';
import { getFirestore as getModularFirestore } from 'firebase/firestore';

const dbCompat = firebase.firestore();      // v8 compat
const dbModular = getModularFirestore();     // Modular API
// Use both during transition, then remove compat
```

---

## Framework Integration

### Flutter (FlutterFire)

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class PostsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('Error: ${snapshot.error}');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        }

        final posts = snapshot.data!.docs;
        return ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index].data() as Map<String, dynamic>;
            return ListTile(
              title: Text(post['title']),
              subtitle: Text(post['content']),
            );
          },
        );
      },
    );
  }
}
```

---

## Best Practices

1. **Use the Emulator Suite for all local development** -- Never develop against production Firestore. Emulators provide a safe, cost-free environment.

2. **Export emulator data on exit** -- Use `--export-on-exit` to preserve seed data between development sessions.

3. **Deploy rules and indexes together** -- Use `firebase deploy --only firestore:rules,firestore:indexes` to keep rules and indexes in sync.

4. **Use App Hosting for SSR frameworks** -- Firebase App Hosting supports Next.js and Angular SSR out of the box with zero-config deployment.

5. **Composite indexes for complex queries** -- Plan indexes ahead of time. Firestore requires composite indexes for queries with multiple where clauses.

6. **Extensions for common patterns** -- Use official extensions (BigQuery export, image resize, email) instead of building custom Cloud Functions.

7. **Gradual SDK migration** -- Use the compat layer during v8-to-modular migration. Migrate one module at a time.

8. **Seed data scripts for consistency** -- Create deterministic seed data scripts so all developers have the same local dataset.

---

## Anti-Patterns

1. **Developing against production** -- Always use emulators for local development. Accidental writes to production are costly and dangerous.

2. **Missing composite indexes** -- Firestore queries with multiple filters fail without indexes. Deploy `firestore.indexes.json` with your rules.

3. **Large emulator data exports** -- Do not commit multi-GB emulator exports to git. Use seed scripts instead.

4. **Ignoring offline persistence** -- Without persistence, mobile apps fail when offline. Enable `enableIndexedDbPersistence` for web and configure FlutterFire offline support.

5. **Manual deployment of rules** -- Always deploy rules through CI/CD after automated testing. Manual deploys bypass validation.

6. **Not monitoring costs** -- Set budget alerts in Google Cloud Console. Review Firestore usage daily during development.

---

## Common Commands

```bash
# Setup & Initialization
firebase login
firebase init
firebase projects:list

# Emulator Suite
firebase emulators:start
firebase emulators:start --only firestore,auth
firebase emulators:start --import=./emulator-data --export-on-exit
firebase emulators:exec --only firestore "npm test"

# Deployment
firebase deploy
firebase deploy --only functions
firebase deploy --only hosting
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only functions:functionName

# Functions
firebase functions:log
firebase functions:log --only functionName
firebase functions:secrets:set STRIPE_API_KEY

# Firestore
firebase firestore:indexes
firebase firestore:delete --all-collections

# App Hosting (2025)
firebase apphosting:backends:create
firebase apphosting:backends:deploy

# Extensions
firebase ext:install
firebase ext:list
firebase ext:update extension-instance-id

# Export/Import
gcloud firestore export gs://bucket-name/export-folder
gcloud firestore import gs://bucket-name/export-folder
```

---

## Sources & References

- [Deploy Angular & Next.js apps with App Hosting, now GA!](https://firebase.blog/posts/2025/04/apphosting-general-availability/)
- [What web frameworks does Firebase App Hosting support?](https://firebase.blog/posts/2025/06/app-hosting-frameworks/)
- [App Hosting](https://firebase.google.com/docs/app-hosting)
- [Install, configure and integrate Local Emulator Suite](https://firebase.google.com/docs/emulator-suite/install_and_configure)
- [How to Import Production Data From Cloud Firestore to the Local Emulator](https://medium.com/firebase-developers/how-to-import-production-data-from-cloud-firestore-to-the-local-emulator-e82ae1c6ed8)
- [Manage indexes in Cloud Firestore](https://firebase.google.com/docs/firestore/query-data/indexing)
- [Effective Indexing Strategies for Firestore Datasets](https://moldstud.com/articles/p-effective-indexing-strategies-for-firestore-datasets)
- [Google Firestore Pricing Guide: Real-World Costs & Optimization Tips](https://airbyte.com/data-engineering-resources/google-firestore-pricing)
- [The Hidden Costs of Firebase](https://moldstud.com/articles/p-the-hidden-costs-of-firebase-essential-tips-for-developers-to-avoid-surprises)
- [Firebase Extensions Hub](https://extensions.dev/)
- [Firebase Extensions in 2025: The Secret Superpower for Developers](https://medium.com/@ektakumari8872/firebase-extensions-in-2025-the-secret-superpower-for-developers-aec2d1275957)
- [Add Firebase to your Flutter app](https://firebase.google.com/docs/flutter/setup)
- [How to Set Up Firebase in Flutter (2025 Guide)](https://medium.com/@tiger.chirag/how-to-set-up-firebase-in-flutter-2025-guide-5eec7941cee7)
- [Upgrade from the namespaced API to the modular application](https://firebase.google.com/docs/web/modular-upgrade)
- [Use Cloud Firestore with Firebase Realtime Database](https://firebase.google.com/docs/firestore/firestore-for-rtdb)
