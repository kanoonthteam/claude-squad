---
name: firebase-backend
description: Production-grade Firebase backend patterns -- Firestore data modeling, Cloud Functions Gen 2, Firebase Auth, real-time patterns, and v11 modular SDK
---

# Firebase Backend -- Staff Engineer Patterns

Production-ready patterns for Firestore advanced data modeling (denormalization, subcollections, distributed counters, transactions), Cloud Functions Gen 2 (streaming callable, scheduled, idempotency), Firebase Auth (MFA, blocking functions, custom claims), real-time architecture, and the v11 modular SDK.

## Table of Contents
1. [Firebase v11 Modular SDK](#firebase-v11-modular-sdk)
2. [Firestore Data Modeling](#firestore-data-modeling)
3. [Cloud Functions Gen 2](#cloud-functions-gen-2)
4. [Firebase Auth Advanced](#firebase-auth-advanced)
5. [Real-Time Patterns](#real-time-patterns)
6. [Performance Optimization](#performance-optimization)
7. [Best Practices](#best-practices)
8. [Anti-Patterns](#anti-patterns)
9. [Sources & References](#sources--references)

---

## Firebase v11 Modular SDK

### Initialization (Singleton Pattern)

```typescript
// firebase-config.ts
import { initializeApp, getApps, FirebaseApp } from 'firebase/app';
import { getAuth, Auth, connectAuthEmulator } from 'firebase/auth';
import {
  getFirestore, Firestore, connectFirestoreEmulator,
  enableIndexedDbPersistence
} from 'firebase/firestore';
import { getFunctions, Functions, connectFunctionsEmulator } from 'firebase/functions';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};

let app: FirebaseApp;
let auth: Auth;
let db: Firestore;
let functions: Functions;

export function getFirebaseApp(): FirebaseApp {
  if (!app) {
    app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApps()[0];
  }
  return app;
}

export function getFirebaseAuth(): Auth {
  if (!auth) {
    auth = getAuth(getFirebaseApp());
    if (import.meta.env.DEV && !auth.emulatorConfig) {
      connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
    }
  }
  return auth;
}

export function getFirebaseFirestore(): Firestore {
  if (!db) {
    db = getFirestore(getFirebaseApp());
    if (import.meta.env.DEV) {
      connectFirestoreEmulator(db, '127.0.0.1', 8080);
    }
    enableIndexedDbPersistence(db).catch((err) => {
      if (err.code === 'failed-precondition') {
        console.warn('Multiple tabs open, persistence can only be enabled in one tab.');
      } else if (err.code === 'unimplemented') {
        console.warn('Current browser does not support persistence.');
      }
    });
  }
  return db;
}

export function getFirebaseFunctions(): Functions {
  if (!functions) {
    functions = getFunctions(getFirebaseApp());
    if (import.meta.env.DEV) {
      connectFunctionsEmulator(functions, '127.0.0.1', 5001);
    }
  }
  return functions;
}
```

### Tree-Shaking Optimized Imports

```typescript
// Import only what you need (80% bundle size reduction)
import { collection, query, where, getDocs, limit } from 'firebase/firestore';
import { signInWithEmailAndPassword, onAuthStateChanged } from 'firebase/auth';

async function fetchUserPosts(userId: string) {
  const db = getFirebaseFirestore();
  const q = query(
    collection(db, 'posts'),
    where('authorId', '==', userId),
    limit(10)
  );
  const snapshot = await getDocs(q);
  return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
}
```

---

## Firestore Data Modeling

### Denormalization Pattern

```typescript
// Store user display info in post document to avoid joins
interface Post {
  title: string;
  content: string;
  authorId: string;
  // Denormalized author info -- update with Cloud Function on profile change
  authorName: string;
  authorAvatarUrl: string;
  createdAt: Timestamp;
  likeCount: number;
  tags: string[];
}

// Cloud Function to propagate profile changes
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { getFirestore } from 'firebase-admin/firestore';

export const propagateProfileChanges = onDocumentUpdated(
  'users/{userId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (before?.displayName === after?.displayName &&
        before?.avatarUrl === after?.avatarUrl) {
      return;  // No relevant changes
    }

    const db = getFirestore();
    const userId = event.params.userId;

    // Batch update all user's posts
    const posts = await db.collection('posts')
      .where('authorId', '==', userId)
      .get();

    const batch = db.batch();
    posts.docs.forEach((doc) => {
      batch.update(doc.ref, {
        authorName: after?.displayName,
        authorAvatarUrl: after?.avatarUrl,
      });
    });
    await batch.commit();
  }
);
```

### Subcollection Pattern

```typescript
// Data model using subcollections for natural hierarchy
// boards/{boardId}
//   columns/{columnId}
//     cards/{cardId}
//       comments/{commentId}

import {
  collection, doc, addDoc, getDocs, query,
  orderBy, serverTimestamp
} from 'firebase/firestore';

async function addComment(boardId: string, columnId: string, cardId: string, text: string, userId: string) {
  const db = getFirebaseFirestore();
  const commentsRef = collection(
    db, 'boards', boardId, 'columns', columnId, 'cards', cardId, 'comments'
  );

  return addDoc(commentsRef, {
    text,
    authorId: userId,
    createdAt: serverTimestamp(),
  });
}

async function getComments(boardId: string, columnId: string, cardId: string) {
  const db = getFirebaseFirestore();
  const q = query(
    collection(db, 'boards', boardId, 'columns', columnId, 'cards', cardId, 'comments'),
    orderBy('createdAt', 'desc')
  );
  const snapshot = await getDocs(q);
  return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
}
```

### Distributed Counters (High-Traffic)

```typescript
import { getFirestore, doc, setDoc, increment, collection, getDocs } from 'firebase/firestore';

const SHARD_COUNT = 10;

async function incrementCounter(counterId: string) {
  const db = getFirestore();
  const shardId = Math.floor(Math.random() * SHARD_COUNT);
  const shardRef = doc(db, `counters/${counterId}/shards/${shardId}`);
  await setDoc(shardRef, { count: increment(1) }, { merge: true });
}

async function getCounterValue(counterId: string): Promise<number> {
  const db = getFirestore();
  const shardsSnapshot = await getDocs(
    collection(db, `counters/${counterId}/shards`)
  );
  let total = 0;
  shardsSnapshot.forEach(doc => { total += doc.data().count || 0; });
  return total;
}
```

### Aggregation Queries (2025)

```typescript
import { getCountFromServer, getAggregateFromServer, sum, average } from 'firebase/firestore';

async function getPostStatistics() {
  const db = getFirestore();
  const postsRef = collection(db, 'posts');

  const countSnapshot = await getCountFromServer(postsRef);
  const totalPosts = countSnapshot.data().count;

  const aggregateSnapshot = await getAggregateFromServer(postsRef, {
    totalLikes: sum('likeCount'),
    avgLikes: average('likeCount'),
  });

  return {
    totalPosts,
    totalLikes: aggregateSnapshot.data().totalLikes,
    avgLikes: aggregateSnapshot.data().avgLikes,
  };
}
// Billing: count() on 0-1000 entries = 1 document read
```

---

## Cloud Functions Gen 2

### Configuration & Secrets Management

```typescript
// src/config/secrets.ts
import { defineSecret } from 'firebase-functions/params';

export const stripeKey = defineSecret('STRIPE_API_KEY');
export const sendgridKey = defineSecret('SENDGRID_API_KEY');
export const databaseUrl = defineSecret('DATABASE_URL');
```

### HTTP Function with Secrets

```typescript
import { onRequest } from 'firebase-functions/v2/https';
import { stripeKey } from '../config/secrets';

export const createPayment = onRequest(
  {
    region: 'asia-southeast1',
    memory: '512MiB',
    timeoutSeconds: 60,
    minInstances: 1,
    maxInstances: 100,
    concurrency: 80,
    secrets: [stripeKey],
    cors: ['https://example.com'],
  },
  async (req, res) => {
    const stripe = new Stripe(stripeKey.value());
    // Payment logic
    res.json({ success: true });
  }
);
```

### Scheduled Function

```typescript
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore } from 'firebase-admin/firestore';

export const dailyCleanup = onSchedule(
  {
    schedule: '0 3 * * *',  // 3 AM daily
    timeZone: 'Asia/Bangkok',
    region: 'asia-southeast1',
    memory: '256MiB',
    retryCount: 3,
  },
  async (event) => {
    const db = getFirestore();
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const expired = await db.collection('sessions')
      .where('createdAt', '<', thirtyDaysAgo)
      .limit(500)
      .get();

    const batch = db.batch();
    expired.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();

    console.log(`Cleaned up ${expired.size} expired sessions`);
  }
);
```

### Idempotent Event Handler

```typescript
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { getFirestore } from 'firebase-admin/firestore';

export const onOrderCreated = onDocumentCreated(
  {
    document: 'orders/{orderId}',
    region: 'asia-southeast1',
    memory: '256MiB',
  },
  async (event) => {
    const db = getFirestore();
    const orderId = event.params.orderId;

    // Idempotency check: use event ID as dedup key
    const processedRef = db.collection('processedEvents').doc(event.id);
    const processed = await processedRef.get();

    if (processed.exists) {
      console.log(`Event ${event.id} already processed, skipping`);
      return;
    }

    // Process the order
    const orderData = event.data?.data();
    await sendConfirmationEmail(orderData);
    await updateInventory(orderData);

    // Mark event as processed
    await processedRef.set({
      processedAt: new Date(),
      orderId,
    });
  }
);
```

---

## Firebase Auth Advanced

### Multi-Factor Authentication Setup

```typescript
import {
  getAuth, multiFactor, PhoneMultiFactorGenerator,
  PhoneAuthProvider, RecaptchaVerifier
} from 'firebase/auth';

async function enrollMFA(phoneNumber: string) {
  const auth = getAuth();
  const user = auth.currentUser;
  if (!user) throw new Error('Not authenticated');

  const multiFactorSession = await multiFactor(user).getSession();

  const phoneAuthProvider = new PhoneAuthProvider(auth);
  const verificationId = await phoneAuthProvider.verifyPhoneNumber(
    { phoneNumber, session: multiFactorSession },
    new RecaptchaVerifier(auth, 'recaptcha-container', { size: 'invisible' })
  );

  // User enters the SMS code
  const verificationCode = await promptUserForCode();
  const phoneAuthCredential = PhoneAuthProvider.credential(verificationId, verificationCode);
  const multiFactorAssertion = PhoneMultiFactorGenerator.assertion(phoneAuthCredential);

  await multiFactor(user).enroll(multiFactorAssertion, 'Phone Number');
}
```

### Blocking Functions for Auth

```typescript
import {
  beforeUserCreated,
  beforeUserSignedIn,
} from 'firebase-functions/v2/identity';

export const validateNewUser = beforeUserCreated(async (event) => {
  const user = event.data;

  // Block disposable email domains
  const domain = user.email?.split('@')[1];
  const blockedDomains = ['tempmail.com', 'throwaway.email', 'mailinator.com'];

  if (domain && blockedDomains.includes(domain)) {
    throw new Error('Registration with disposable email addresses is not allowed.');
  }

  // Set initial custom claims
  return {
    customClaims: {
      role: 'user',
      plan: 'free',
      createdVia: 'web',
    },
  };
});

export const auditSignIn = beforeUserSignedIn(async (event) => {
  const user = event.data;

  // Check if account is disabled in Firestore
  const db = getFirestore();
  const userDoc = await db.collection('users').doc(user.uid).get();

  if (userDoc.exists && userDoc.data()?.suspended) {
    throw new Error('This account has been suspended. Contact support.');
  }

  // Log sign-in event
  await db.collection('auditLog').add({
    userId: user.uid,
    event: 'sign_in',
    ip: event.ipAddress,
    userAgent: event.userAgent,
    timestamp: new Date(),
  });
});
```

---

## Real-Time Patterns

### Presence System with RTDB + Firestore

```typescript
import { getDatabase, ref, onDisconnect, set, onValue, serverTimestamp } from 'firebase/database';
import { doc, setDoc, serverTimestamp as firestoreTimestamp } from 'firebase/firestore';

async function setupPresence(userId: string) {
  const db = getFirebaseFirestore();
  const rtdb = getDatabase();

  const userStatusDatabaseRef = ref(rtdb, `/status/${userId}`);
  const userStatusFirestoreRef = doc(db, 'status', userId);

  const isOnlineForDatabase = { state: 'online', last_changed: serverTimestamp() };
  const isOfflineForDatabase = { state: 'offline', last_changed: serverTimestamp() };
  const isOnlineForFirestore = { state: 'online', last_changed: firestoreTimestamp() };

  const connectedRef = ref(rtdb, '.info/connected');
  onValue(connectedRef, async (snapshot) => {
    if (snapshot.val() === false) return;

    await onDisconnect(userStatusDatabaseRef).set(isOfflineForDatabase);
    set(userStatusDatabaseRef, isOnlineForDatabase);
    setDoc(userStatusFirestoreRef, isOnlineForFirestore);
  });
}

// Cloud Function: Mirror RTDB presence to Firestore
import { onValueWritten } from 'firebase-functions/v2/database';

export const syncPresenceToFirestore = onValueWritten(
  '/status/{userId}',
  async (event) => {
    const userId = event.params.userId;
    const status = event.data.after.val();
    const db = getFirestore();
    await db.collection('status').doc(userId).set(status);
  }
);
```

### Real-Time Chat with Optimistic UI

```typescript
import { collection, query, orderBy, limit, onSnapshot, doc, setDoc, serverTimestamp } from 'firebase/firestore';

function listenToChatMessages(chatId: string, messageLimit: number = 50) {
  const db = getFirestore();
  const q = query(
    collection(db, `chats/${chatId}/messages`),
    orderBy('createdAt', 'desc'),
    limit(messageLimit)
  );

  return onSnapshot(q, (snapshot) => {
    snapshot.docChanges().forEach((change) => {
      if (change.type === 'added') {
        if (change.doc.metadata.fromCache) {
          console.log('Optimistic message (pending):', change.doc.data());
        } else {
          console.log('Server confirmed message:', change.doc.data());
        }
      }
    });
  });
}

async function sendMessage(chatId: string, content: string, userId: string) {
  const db = getFirestore();
  const messageRef = doc(collection(db, `chats/${chatId}/messages`));

  await setDoc(messageRef, {
    content,
    senderId: userId,
    createdAt: serverTimestamp(),
    status: 'pending',
  });
}
```

---

## Performance Optimization

### Cursor-Based Pagination

```typescript
let lastVisible: any = null;

async function paginateWithCursor(pageSize: number) {
  const db = getFirestore();

  let q = query(
    collection(db, 'posts'),
    orderBy('createdAt', 'desc'),
    limit(pageSize)
  );

  if (lastVisible) {
    q = query(q, startAfter(lastVisible));
  }

  const snapshot = await getDocs(q);

  if (snapshot.docs.length > 0) {
    lastVisible = snapshot.docs[snapshot.docs.length - 1];
  }

  return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
}
```

### Batch Reads for Related Data

```typescript
import { documentId } from 'firebase/firestore';

async function batchGetUsers(userIds: string[]) {
  const db = getFirestore();

  // Firestore allows up to 10 IDs in a single 'in' query
  const chunks = chunkArray(userIds, 10);

  const results = await Promise.all(
    chunks.map(chunk =>
      getDocs(query(collection(db, 'users'), where(documentId(), 'in', chunk)))
    )
  );

  return results.flatMap(snapshot =>
    snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }))
  );
}

function chunkArray<T>(array: T[], size: number): T[][] {
  return Array.from({ length: Math.ceil(array.length / size) }, (_, i) =>
    array.slice(i * size, i * size + size)
  );
}
```

### Cache Warming with Bundles

```typescript
// Client: Load pre-generated bundle for initial data
import { loadBundle, namedQuery, getDocs } from 'firebase/firestore';

async function loadInitialData() {
  const db = getFirestore();
  const response = await fetch('https://cdn.example.com/bundles/initial-data.bundle');
  const bundle = await response.arrayBuffer();

  await loadBundle(db, bundle);

  const query = await namedQuery(db, 'latest-posts');
  if (query) {
    const snapshot = await getDocs(query);
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }
}

// Server: Generate bundle (Cloud Function)
import { firestore } from 'firebase-admin';

async function generateBundle() {
  const db = firestore();
  const bundleId = 'latest-posts';
  const bundle = db.bundle(bundleId);

  const query = db.collection('posts').orderBy('createdAt', 'desc').limit(20);
  const snapshot = await query.get();

  bundle.add(bundleId, snapshot);
  return bundle.build();
}
```

---

## Best Practices

1. **Use modular SDK imports** -- Import only the functions you need. This enables tree-shaking and reduces bundle size by up to 80%.

2. **Denormalize for read performance** -- Firestore charges per document read. Embed frequently accessed related data to avoid multiple reads.

3. **Cloud Functions Gen 2 with concurrency** -- Set `concurrency` (up to 1000) to handle multiple requests per instance, reducing cold starts and cost.

4. **Idempotent event handlers** -- Use the event ID as a dedup key. Firestore triggers can fire more than once.

5. **Cursor-based pagination over offset** -- `offset()` still reads (and bills for) skipped documents. Use `startAfter()` with document cursors.

6. **Distributed counters for high-write documents** -- Firestore's 1 write/sec/doc limit requires sharding for popular counters.

7. **Blocking functions for auth guardrails** -- Use `beforeUserCreated` and `beforeUserSignedIn` to enforce domain restrictions, set claims, and audit logins.

8. **Offline persistence by default** -- Enable `enableIndexedDbPersistence` for web apps to provide offline-first user experience.

---

## Anti-Patterns

1. **Importing the entire Firebase SDK** -- Using `import firebase from 'firebase/app'` pulls in the entire namespace. Always use modular imports.

2. **Listening to entire collections** -- Use filtered queries with `where()` and `limit()` for real-time listeners. Unfiltered listeners bill for every document change.

3. **Using offset() for pagination** -- Firestore reads (and charges for) all skipped documents. Always use cursor-based pagination.

4. **Storing large files in Firestore** -- Document limit is 1MB. Use Cloud Storage and store download URLs in Firestore.

5. **Single document for high-write counters** -- Exceeds Firestore's 1 write/sec/doc limit. Use distributed counters with shards.

6. **Cloud Functions v1 with default concurrency** -- v1 processes 1 request per instance. Migrate to v2 and set concurrency for better cost efficiency.

---

## Sources & References

- [Understand Firebase for web](https://firebase.google.com/docs/web/learn-more)
- [Firebase JavaScript SDK best practices](https://firebase.google.com/docs/web/best-practices)
- [Upgrade from the namespaced API to the modular application](https://firebase.google.com/docs/web/modular-upgrade)
- [Build Responsive, AI-powered Apps with Cloud Functions for Firebase](https://firebase.blog/posts/2025/03/streaming-cloud-functions-genkit/)
- [Upgrade 1st gen Node.js functions to 2nd gen](https://firebase.google.com/docs/functions/2nd-gen-upgrade)
- [Tutorial: Advanced Data Modeling with Firestore by Example](https://fireship.io/lessons/advanced-firestore-nosql-data-structure-examples/)
- [7+ Google Firestore Query Performance Best Practices for 2026](https://estuary.dev/blog/firestore-query-best-practices/)
- [Control Access with Custom Claims and Security Rules](https://firebase.google.com/docs/auth/admin/custom-claims)
- [Extend Firebase Authentication with blocking functions](https://firebase.google.com/docs/auth/extend-with-blocking-functions)
- [Advanced Authentication features](https://firebase.google.com/codelabs/auth-mfa-blocking-functions)
- [Build presence in Cloud Firestore](https://firebase.google.com/docs/firestore/solutions/presence)
- [Firebase 2025: Solving Scaling Limits with Distributed Counters](https://markaicode.com/firebase-distributed-counters-scaling-2025/)
- [Summarize data with aggregation queries](https://firebase.google.com/docs/firestore/query-data/aggregation-queries)
- [Access data offline](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
