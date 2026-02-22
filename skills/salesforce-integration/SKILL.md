---
name: salesforce-integration
description: Salesforce integration patterns — Named Credentials, REST/SOAP callouts, External Services, Platform Events, CDC, CI/CD with GitHub Actions, Large Data Volume strategies
---

# Salesforce Integration & DevOps

Staff-engineer-level Salesforce integration patterns. Covers Named Credentials for secure callouts, REST and SOAP integrations, External Services with OpenAPI, Platform Events and Change Data Capture for event-driven architecture, CI/CD with GitHub Actions and scratch orgs, Large Data Volume strategies (skinny tables, custom indexes, Big Objects), and security best practices.

## Table of Contents

1. [Named Credentials](#named-credentials)
2. [REST Callouts](#rest-callouts)
3. [External Services (OpenAPI)](#external-services-openapi)
4. [Security Best Practices](#security-best-practices)
5. [CI/CD with GitHub Actions](#cicd-with-github-actions)
6. [Large Data Volume Strategies](#large-data-volume-strategies)
7. [Best Practices](#best-practices)
8. [Anti-Patterns](#anti-patterns)

---

## Named Credentials

Store endpoint URLs and authentication without hardcoding.

```apex
public class ExternalAPIService {

    public static String callExternalAPI() {
        HttpRequest req = new HttpRequest();
        // Use Named Credential (no hardcoded URL or auth)
        req.setEndpoint('callout:External_System/api/v1/accounts');
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            return res.getBody();
        } else {
            throw new CalloutException('API call failed: ' + res.getStatus());
        }
    }
}
```

---

## REST Callouts

### Future Method for Fire-and-Forget

```apex
public class AccountProcessor {

    @future(callout=true)
    public static void syncAccountsToExternalSystem(Set<Id> accountIds) {
        List<Account> accounts = [
            SELECT Id, Name, Industry, BillingCountry
            FROM Account WHERE Id IN :accountIds
        ];

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:External_System/accounts');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(accounts));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            System.debug('Callout failed: ' + res.getBody());
        }
    }
}
```

### MuleSoft Integration

```apex
public class MuleSoftIntegration {

    @future(callout=true)
    public static void syncToMuleSoft(Set<Id> accountIds) {
        List<Account> accounts = [
            SELECT Id, Name, Industry, BillingCountry
            FROM Account WHERE Id IN :accountIds
        ];

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:MuleSoft_API/sync/accounts');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(accounts));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            System.debug('MuleSoft sync failed: ' + res.getBody());
        }
    }
}
```

---

## External Services (OpenAPI)

Generate Apex actions from OpenAPI specifications.

```yaml
# OpenAPI spec
openapi: 3.0.0
info:
  title: Account API
  version: 1.0.0
paths:
  /accounts:
    get:
      operationId: getAccounts
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Account'
```

```apex
// Auto-generated invocable action from External Service
// Can be called from Flow or Apex
ExternalService.AccountAPI_getAccounts();
```

---

## Security Best Practices

### User Mode vs System Mode

```apex
// NEW: User Mode (Spring '26) - RECOMMENDED
List<Account> accounts = [
    SELECT Id, Name FROM Account
    WHERE Industry = 'Technology'
    WITH USER_MODE
];

// System Mode (use sparingly)
List<Account> allAccounts = [
    SELECT Id, Name FROM Account
    WITH SYSTEM_MODE
];
```

### Sharing Rules

```apex
// 'with sharing' enforces record-level security
public with sharing class AccountService {
    public List<Account> getAccounts() {
        return [SELECT Id, Name FROM Account];
    }
}

// 'without sharing' runs in system context
public without sharing class SystemAccountService {
    public List<Account> getAllAccounts() {
        return [SELECT Id, Name FROM Account];
    }
}

// 'inherited sharing' inherits from caller
public inherited sharing class FlexibleService {
    public List<Account> getAccounts() {
        return [SELECT Id, Name FROM Account];
    }
}
```

### Security.stripInaccessible()

```apex
public class DataService {
    public static void updateAccounts(List<Account> accounts) {
        // Strip fields user can't update
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPDATABLE, accounts
        );
        update decision.getRecords();

        // Log removed fields
        Map<String, Set<String>> removedFields = decision.getRemovedFields();
        if (!removedFields.isEmpty()) {
            System.debug('Fields removed due to FLS: ' + removedFields);
        }
    }
}
```

### Security Summary

1. Always use `with sharing` unless you explicitly need system context
2. Use `WITH USER_MODE` in SOQL queries (Spring '26+)
3. Use `Security.stripInaccessible()` for user input
4. Never trust client-side data - validate server-side
5. Store credentials in Protected Custom Settings or Shield Encryption
6. Use Named Credentials for external system credentials
7. Never hardcode credentials in code

---

## CI/CD with GitHub Actions

### Scratch Org Validation

```yaml
# .github/workflows/salesforce-ci.yml
name: Salesforce CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Salesforce CLI
        run: |
          npm install -g @salesforce/cli
          sf version

      - name: Authenticate to DevHub
        run: |
          echo "${{ secrets.SFDX_AUTH_URL }}" > ./SFDX_AUTH_URL.txt
          sf org login sfdx-url --sfdx-url-file ./SFDX_AUTH_URL.txt \
            --set-default-dev-hub --alias DevHub

      - name: Create Scratch Org
        run: |
          sf org create scratch --definition-file config/project-scratch-def.json \
            --alias ci-scratch --set-default --duration-days 1

      - name: Deploy Source
        run: sf project deploy start --wait 20

      - name: Run Apex Tests
        run: |
          sf apex run test --test-level RunLocalTests \
            --result-format human --code-coverage --wait 20

      - name: Delete Scratch Org
        if: always()
        run: sf org delete scratch --target-org ci-scratch --no-prompt
```

### Production Deployment

```yaml
name: Deploy to Production

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Salesforce CLI
        run: npm install -g @salesforce/cli

      - name: Authenticate to Production
        run: |
          echo "${{ secrets.PROD_SFDX_AUTH_URL }}" > ./PROD_AUTH.txt
          sf org login sfdx-url --sfdx-url-file ./PROD_AUTH.txt \
            --alias Production --set-default

      - name: Validate Deployment
        run: sf project deploy start --dry-run --test-level RunLocalTests --wait 60

      - name: Deploy to Production
        run: sf project deploy start --test-level RunLocalTests --wait 60
```

### Scratch Org Commands

```bash
# Authenticate Dev Hub
sf org login web --set-default-dev-hub --alias DevHub

# Create scratch org
sf org create scratch --definition-file config/project-scratch-def.json \
  --alias my-scratch --set-default --duration-days 30

# Push/pull source
sf project deploy start
sf project retrieve start

# Run tests
sf apex run test --test-level RunLocalTests --result-format human
```

---

## Large Data Volume Strategies

### Skinny Tables

Request from Salesforce for frequently accessed fields on objects with 10M+ records.

```apex
// Before: Slow query on 50M records
List<Account> accounts = [
    SELECT Id, Name, Industry, Owner.Name, RecordType.Name
    FROM Account WHERE Industry = 'Technology'
];

// After: Skinny table denormalizes frequently used fields
// Salesforce creates and maintains the denormalized table automatically
```

### Custom Indexes and Selective Queries

```apex
// GOOD: Selective query using indexed field
List<Account> accounts = [
    SELECT Id, Name FROM Account
    WHERE CreatedDate = LAST_N_DAYS:30
      AND OwnerId = :UserInfo.getUserId()
    LIMIT 1000
];

// BAD: Non-selective query (full table scan)
List<Account> accounts = [
    SELECT Id, Name FROM Account
    WHERE Custom_Status__c = 'Active'  // Not indexed, matches 80% of records
];
```

### Big Objects for Archival

```apex
// Big Objects hold billions of records
List<Order_Archive__b> archives = new List<Order_Archive__b>();
for (Order__c order : oldOrders) {
    archives.add(new Order_Archive__b(
        Order_Id__c = order.Id,
        Order_Number__c = order.Order_Number__c,
        Created_Date__c = order.CreatedDate
    ));
}
database.insertImmediate(archives);

// Query Big Object (index required)
List<Order_Archive__b> results = [
    SELECT Order_Id__c, Order_Number__c
    FROM Order_Archive__b
    WHERE Order_Number__c = '12345'
];
```

### Batch Processing for LDV

```apex
public class LargeDataBatchProcessor implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Status__c FROM Account
            WHERE LastModifiedDate >= LAST_N_DAYS:7
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        for (Account acc : scope) {
            acc.Processed__c = true;
        }
        update scope;
    }

    public void finish(Database.BatchableContext bc) {}
}

// Execute with optimal batch size
Database.executeBatch(new LargeDataBatchProcessor(), 2000);
```

---

## Best Practices

1. **Named Credentials always** - Never hardcode endpoints or auth
2. **Retry logic for callouts** - Handle transient failures gracefully
3. **Platform Events for async** - Decouple integration triggers
4. **Idempotency keys** - Prevent duplicate processing in external systems
5. **Validate before deploy** - Always dry-run before production
6. **Scratch orgs for dev** - Isolated feature development
7. **Selective queries for LDV** - Use indexed fields in WHERE clauses
8. **Archive to Big Objects** - Move historical data off primary objects
9. **`with sharing` by default** - Only bypass when explicitly documented

---

## Anti-Patterns

- Hardcoding endpoints or credentials in Apex code
- Missing error handling for HTTP callouts
- Not using `--dry-run` before production deployments
- Processing LDV records synchronously (use Batch Apex)
- Non-selective queries on objects with millions of records
- Missing `if: always()` on scratch org cleanup in CI
- Using `without sharing` without documenting the reason
- Not monitoring integration health with Event Monitoring

---

## Sources & References

- [Salesforce Integration Patterns Guide](https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/integration_patterns_and_practices.pdf)
- [Build CI/CD Pipeline with GitHub Actions](https://www.salesforceben.com/build-your-own-ci-cd-pipeline-in-salesforce-using-github-actions/)
- [Large Data Volumes Best Practices](https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/salesforce_large_data_volumes_bp.pdf)
- [Salesforce Security Best Practices](https://security.salesforce.com/security-best-practices)
- [Platform Events vs CDC](https://developer.salesforce.com/blogs/2022/10/design-considerations-for-change-data-capture-and-platform-events)
- [Salesforce Spring '26 Release Guide](https://www.jitendrazaa.com/blog/salesforce/salesforce-spring-26-release-complete-guide-2026/)
