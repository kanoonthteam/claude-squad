---
name: firebase-security
description: Production-grade Firebase security patterns -- Firestore Security Rules, Storage Security Rules, custom claims, data validation, App Check, and testing rules with emulators
---

# Firebase Security -- Staff Engineer Patterns

Production-ready patterns for Firestore Security Rules (helper functions, custom claims, data validation, role-based access), Storage Security Rules, Firebase App Check, and testing rules with the Emulator Suite.

## Table of Contents
1. [Firestore Security Rules](#firestore-security-rules)
2. [Storage Security Rules](#storage-security-rules)
3. [Custom Claims & RBAC](#custom-claims--rbac)
4. [Data Validation Rules](#data-validation-rules)
5. [Testing Rules with Emulators](#testing-rules-with-emulators)
6. [Best Practices](#best-practices)
7. [Anti-Patterns](#anti-patterns)
8. [Common Commands](#common-commands)
9. [Sources & References](#sources--references)

---

## Firestore Security Rules

### Production-Ready Rules with Helper Functions

```
// firestore.rules
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // ============ HELPER FUNCTIONS ============

    // Check if user is authenticated
    function isSignedIn() {
      return request.auth != null;
    }

    // Get user's custom claims
    function getClaims() {
      return request.auth.token;
    }

    // Check user role
    function hasRole(role) {
      return isSignedIn() && getClaims().role == role;
    }

    // Check if user has any of the specified roles
    function hasAnyRole(roles) {
      return isSignedIn() && getClaims().role in roles;
    }

    // Check if user is the resource owner
    function isOwner(userId) {
      return isSignedIn() && request.auth.uid == userId;
    }

    // Check if user is admin
    function isAdmin() {
      return hasRole('admin');
    }

    // Get the incoming data
    function incomingData() {
      return request.resource.data;
    }

    // Get existing data
    function existingData() {
      return resource.data;
    }

    // Validate string field: exists, is string, within length
    function isValidString(field, minLen, maxLen) {
      return field is string && field.size() >= minLen && field.size() <= maxLen;
    }

    // Validate that only allowed fields are being written
    function onlyAllowedFields(fields) {
      return incomingData().keys().hasOnly(fields);
    }

    // Validate timestamp is server-generated
    function isServerTimestamp(field) {
      return field == request.time;
    }

    // ============ COLLECTION RULES ============

    // Users collection
    match /users/{userId} {
      // Anyone can read public profiles
      allow read: if isSignedIn();

      // Users can only create their own profile
      allow create: if isOwner(userId)
        && onlyAllowedFields(['displayName', 'email', 'avatarUrl', 'bio', 'createdAt'])
        && isValidString(incomingData().displayName, 2, 50)
        && isServerTimestamp(incomingData().createdAt);

      // Users can update their own profile; admins can update any
      allow update: if (isOwner(userId) || isAdmin())
        && onlyAllowedFields(['displayName', 'avatarUrl', 'bio', 'updatedAt'])
        && isValidString(incomingData().displayName, 2, 50);

      // Only admins can delete users
      allow delete: if isAdmin();
    }

    // Posts collection
    match /posts/{postId} {
      // Published posts are public; drafts only visible to owner
      allow read: if existingData().status == 'published'
        || isOwner(existingData().authorId)
        || isAdmin();

      allow create: if isSignedIn()
        && onlyAllowedFields([
          'title', 'content', 'authorId', 'authorName',
          'status', 'tags', 'createdAt', 'likeCount'
        ])
        && isOwner(incomingData().authorId)
        && isValidString(incomingData().title, 3, 200)
        && isValidString(incomingData().content, 10, 50000)
        && incomingData().status in ['draft', 'published']
        && incomingData().likeCount == 0
        && isServerTimestamp(incomingData().createdAt);

      allow update: if (isOwner(existingData().authorId) || isAdmin())
        && (!('authorId' in incomingData().diff(existingData()).affectedKeys()));

      allow delete: if isOwner(existingData().authorId) || isAdmin();

      // Comments subcollection
      match /comments/{commentId} {
        allow read: if isSignedIn();

        allow create: if isSignedIn()
          && isOwner(incomingData().authorId)
          && isValidString(incomingData().text, 1, 5000)
          && isServerTimestamp(incomingData().createdAt);

        allow update: if isOwner(existingData().authorId)
          && onlyAllowedFields(['text', 'updatedAt']);

        allow delete: if isOwner(existingData().authorId) || isAdmin();
      }
    }

    // Boards (Kanban) -- hierarchical rules
    match /boards/{boardId} {
      function isBoardMember() {
        return isSignedIn() && request.auth.uid in existingData().memberIds;
      }

      function isBoardOwner() {
        return isOwner(existingData().ownerId);
      }

      allow read: if isBoardMember() || isBoardOwner() || isAdmin();
      allow create: if isSignedIn() && isOwner(incomingData().ownerId);
      allow update: if isBoardOwner() || isAdmin();
      allow delete: if isBoardOwner() || isAdmin();

      match /columns/{columnId} {
        allow read: if isBoardMember() || isBoardOwner() || isAdmin();
        allow write: if isBoardOwner() || isAdmin();
      }

      match /cards/{cardId} {
        allow read: if isBoardMember() || isBoardOwner() || isAdmin();
        allow create: if isBoardMember() || isBoardOwner();
        allow update: if isBoardMember() || isBoardOwner();
        allow delete: if isBoardOwner() || isAdmin();
      }
    }

    // Rate limits collection (write-only from Cloud Functions)
    match /rateLimits/{docId} {
      allow read: if false;
      allow write: if false;  // Only Cloud Functions (admin SDK) can write
    }

    // Processed events (idempotency tracking)
    match /processedEvents/{eventId} {
      allow read, write: if false;  // Admin SDK only
    }
  }
}
```

---

## Storage Security Rules

### Production Storage Rules

```
// storage.rules
rules_version = '2';

service firebase.storage {
  match /b/{bucket}/o {

    // Helper: check file size (in bytes)
    function maxFileSize(sizeInMB) {
      return request.resource.size < sizeInMB * 1024 * 1024;
    }

    // Helper: check content type
    function isImageType() {
      return request.resource.contentType.matches('image/(png|jpeg|gif|webp)');
    }

    function isPDFType() {
      return request.resource.contentType == 'application/pdf';
    }

    // User avatars: only owner can upload, anyone can read
    match /avatars/{userId}/{fileName} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
        && request.auth.uid == userId
        && isImageType()
        && maxFileSize(5);  // 5MB max
    }

    // Post attachments: owner can upload, members can read
    match /posts/{postId}/{fileName} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
        && (isImageType() || isPDFType())
        && maxFileSize(25);  // 25MB max
    }

    // Private documents: strict access
    match /private/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null
        && request.auth.uid == userId
        && maxFileSize(50);
    }

    // Deny all other access
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

---

## Custom Claims & RBAC

### Setting Custom Claims (Admin SDK)

```typescript
// functions/src/admin/claims.ts
import { getAuth } from 'firebase-admin/auth';

export async function setUserRole(uid: string, role: 'admin' | 'editor' | 'user') {
  const auth = getAuth();

  await auth.setCustomUserClaims(uid, {
    role,
    updatedAt: Date.now(),
  });

  // Force token refresh on next request
  const db = getFirestore();
  await db.collection('users').doc(uid).update({
    tokenRefreshRequired: true,
  });
}

// Callable function for admin to manage roles
import { onCall, HttpsError } from 'firebase-functions/v2/https';

export const setRole = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    // Verify caller is admin
    if (request.auth?.token.role !== 'admin') {
      throw new HttpsError('permission-denied', 'Only admins can set roles');
    }

    const { uid, role } = request.data;

    if (!['admin', 'editor', 'user'].includes(role)) {
      throw new HttpsError('invalid-argument', 'Invalid role');
    }

    await setUserRole(uid, role);
    return { success: true };
  }
);
```

### Client-Side Token Refresh

```typescript
import { getAuth, onIdTokenChanged } from 'firebase/auth';
import { getFirestore, doc, onSnapshot } from 'firebase/firestore';

function setupTokenRefresh() {
  const auth = getAuth();
  const user = auth.currentUser;
  if (!user) return;

  const db = getFirestore();
  const userRef = doc(db, 'users', user.uid);

  // Listen for token refresh signal
  onSnapshot(userRef, async (snapshot) => {
    if (snapshot.data()?.tokenRefreshRequired) {
      await user.getIdToken(true);  // Force refresh
      console.log('Token refreshed with new claims');
    }
  });
}
```

---

## Data Validation Rules

### Advanced Validation Patterns

```
// Additional validation helpers for firestore.rules

function isValidEmail(email) {
  return email.matches('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$');
}

function isValidUrl(url) {
  return url.matches('^https?://.*');
}

function isValidTags(tags) {
  return tags is list
    && tags.size() <= 10
    && tags.size() >= 0;
}

function isValidEnum(value, allowedValues) {
  return value in allowedValues;
}

function fieldNotChanged(field) {
  return !(field in request.resource.data.diff(resource.data).affectedKeys());
}

function isIncrement(field, max) {
  return incomingData()[field] == existingData()[field] + 1
    || incomingData()[field] == existingData()[field] - 1;
}

// Usage in rules:
// allow update: if fieldNotChanged('authorId')
//   && fieldNotChanged('createdAt')
//   && isValidTags(incomingData().tags);
```

---

## Testing Rules with Emulators

### Firestore Rules Unit Tests

```typescript
// tests/firestore.rules.test.ts
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'test-project',
    firestore: {
      rules: fs.readFileSync('firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe('Users collection', () => {
  test('authenticated user can read any profile', async () => {
    const adminCtx = testEnv.authenticatedContext('admin', { role: 'admin' });
    const db = adminCtx.firestore();

    // Seed data
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users/user1'), {
        displayName: 'Test User',
        email: 'test@example.com',
      });
    });

    const userCtx = testEnv.authenticatedContext('user2');
    await assertSucceeds(getDoc(doc(userCtx.firestore(), 'users/user1')));
  });

  test('unauthenticated user cannot read profiles', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users/user1'), {
        displayName: 'Test User',
      });
    });

    const unauth = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(unauth.firestore(), 'users/user1')));
  });

  test('user can only create their own profile', async () => {
    const userCtx = testEnv.authenticatedContext('user1');
    const db = userCtx.firestore();

    // Can create own profile
    await assertSucceeds(setDoc(doc(db, 'users/user1'), {
      displayName: 'My Name',
      email: 'me@example.com',
      avatarUrl: '',
      bio: '',
      createdAt: serverTimestamp(),
    }));

    // Cannot create another user's profile
    await assertFails(setDoc(doc(db, 'users/user2'), {
      displayName: 'Other Name',
      email: 'other@example.com',
      avatarUrl: '',
      bio: '',
      createdAt: serverTimestamp(),
    }));
  });

  test('only admin can delete users', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users/user1'), {
        displayName: 'Test User',
      });
    });

    // Regular user cannot delete
    const userCtx = testEnv.authenticatedContext('user1', { role: 'user' });
    await assertFails(deleteDoc(doc(userCtx.firestore(), 'users/user1')));

    // Admin can delete
    const adminCtx = testEnv.authenticatedContext('admin', { role: 'admin' });
    await assertSucceeds(deleteDoc(doc(adminCtx.firestore(), 'users/user1')));
  });
});

describe('Posts collection', () => {
  test('published posts are publicly readable', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'posts/post1'), {
        title: 'Public Post',
        status: 'published',
        authorId: 'author1',
      });
    });

    const userCtx = testEnv.authenticatedContext('reader');
    await assertSucceeds(getDoc(doc(userCtx.firestore(), 'posts/post1')));
  });

  test('draft posts only visible to owner', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'posts/draft1'), {
        title: 'Draft Post',
        status: 'draft',
        authorId: 'author1',
      });
    });

    // Owner can read
    const ownerCtx = testEnv.authenticatedContext('author1');
    await assertSucceeds(getDoc(doc(ownerCtx.firestore(), 'posts/draft1')));

    // Other user cannot read
    const otherCtx = testEnv.authenticatedContext('reader');
    await assertFails(getDoc(doc(otherCtx.firestore(), 'posts/draft1')));
  });
});
```

### CI/CD Integration for Rule Tests

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

## Best Practices

1. **Always deny by default** -- Start with `allow read, write: if false;` at the root level and explicitly grant access per collection.

2. **Use helper functions** -- Extract common checks (`isSignedIn()`, `isOwner()`, `hasRole()`) into reusable functions at the top of your rules file.

3. **Validate all writes** -- Check field types, lengths, allowed values, and required fields on every create and update operation.

4. **Protect immutable fields** -- Use `fieldNotChanged()` to prevent modification of `authorId`, `createdAt`, and other immutable fields on updates.

5. **Test rules with emulators** -- Write unit tests using `@firebase/rules-unit-testing` and run them in CI. Never deploy untested rules.

6. **Use custom claims for RBAC** -- Set roles via admin SDK custom claims. Check them in rules with `request.auth.token.role`.

7. **Limit Storage uploads by type and size** -- Always validate `contentType` and `size` in Storage rules to prevent abuse.

8. **Use `onlyAllowedFields()` to prevent extra fields** -- Reject writes that include unexpected fields to maintain data integrity.

---

## Anti-Patterns

1. **`allow read, write: if true;`** -- Never deploy open rules to production. This grants full access to anyone with your project config.

2. **Checking roles via Firestore reads in rules** -- Firestore rules have a 10 `get()` call limit per request. Use custom claims on the auth token instead.

3. **No validation on create** -- Always validate data shape, types, and business rules on document creation. Garbage data is expensive to clean up.

4. **Trusting client-provided timestamps** -- Use `request.time` to validate server timestamps. Never trust `Timestamp.now()` from the client.

5. **Skipping Storage content type validation** -- Without type checks, users can upload executables disguised as images. Always validate `contentType`.

6. **Not testing rules before deploy** -- Deploying untested rules can lock out legitimate users or expose private data.

---

## Common Commands

```bash
# Deploy rules
firebase deploy --only firestore:rules
firebase deploy --only storage
firebase deploy --only firestore:indexes

# Test with emulators
firebase emulators:start --only firestore,auth
firebase emulators:exec --only firestore,auth "npm test"

# View deployed rules
firebase firestore:rules:get

# List indexes
firebase firestore:indexes

# Delete all data (emulator only)
firebase firestore:delete --all-collections
```

---

## Sources & References

- [How to Write Firestore Security Rules for User-Based Access Control](https://oneuptime.com/blog/post/2026-02-17-how-to-write-firestore-security-rules-for-user-based-access-control/view)
- [Control Access with Custom Claims and Security Rules](https://firebase.google.com/docs/auth/admin/custom-claims)
- [Security Rules](https://firebase.google.com/docs/firestore/security/rules-conditions)
- [Firestore Data Modeling](https://firebase.google.com/docs/firestore/data-model)
- [Install, configure and integrate Local Emulator Suite](https://firebase.google.com/docs/emulator-suite/install_and_configure)
- [How to Import Production Data From Cloud Firestore to the Local Emulator](https://medium.com/firebase-developers/how-to-import-production-data-from-cloud-firestore-to-the-local-emulator-e82ae1c6ed8)
- [Firebase Storage Security Rules](https://firebase.google.com/docs/storage/security)
- [Firebase App Check](https://firebase.google.com/docs/app-check)
- [Test Security Rules with the Emulator Suite](https://firebase.google.com/docs/firestore/security/test-rules-emulator)
