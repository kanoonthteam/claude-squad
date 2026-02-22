---
name: salesforce-apex
description: Salesforce Apex patterns — fflib enterprise patterns (Selector/Domain/Service/UoW), trigger framework, governor limits, bulkification, async processing, SOQL/SOSL, Custom Metadata, Platform Events
---

# Salesforce Apex & Enterprise Patterns

Staff-engineer-level Salesforce Apex patterns. Covers fflib enterprise patterns (Selector, Domain, Service, Unit of Work), one-trigger-per-object pattern, governor limits and bulkification, asynchronous processing (future, Queueable, Batch, Schedulable), SOQL/SOSL optimization, Custom Metadata, Platform Events, and Change Data Capture.

## Table of Contents

1. [SFDX Project Structure](#sfdx-project-structure)
2. [fflib Selector Layer](#fflib-selector-layer)
3. [fflib Domain Layer](#fflib-domain-layer)
4. [fflib Service Layer](#fflib-service-layer)
5. [Governor Limits & Bulkification](#governor-limits--bulkification)
6. [SOQL/SOSL Optimization](#soqlsosl-optimization)
7. [Asynchronous Processing](#asynchronous-processing)
8. [Platform Events & CDC](#platform-events--cdc)
9. [Custom Metadata](#custom-metadata)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)

---

## SFDX Project Structure

```
force-app/main/default/
├── classes/
│   ├── domains/          # Domain layer (fflib)
│   │   ├── Accounts.cls
│   │   └── AccountsTest.cls
│   ├── selectors/        # Selector layer (queries)
│   │   ├── AccountsSelector.cls
│   │   └── AccountsSelectorTest.cls
│   ├── services/         # Service layer (business logic)
│   │   ├── AccountService.cls
│   │   └── AccountServiceTest.cls
│   └── triggers/
│       └── AccountTriggerHandler.cls
├── triggers/
│   └── AccountTrigger.trigger
├── objects/
│   └── Account/
│       └── fields/
├── customMetadata/
└── permissionsets/
```

**Key Principles:**
- One trigger per object
- Separation of concerns (Selector, Domain, Service, Unit of Work)
- Source tracking with scratch orgs

---

## fflib Selector Layer

Centralizes all SOQL queries for an object.

```apex
public inherited sharing class AccountsSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return Account.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField> {
            Account.Id, Account.Name, Account.Industry,
            Account.AnnualRevenue, Account.Type, Account.BillingCountry
        };
    }

    public List<Account> selectById(Set<Id> accountIds) {
        return (List<Account>) Database.query(
            newQueryFactory()
                .setCondition('Id IN :accountIds')
                .toSOQL()
        );
    }

    public List<Account> selectByIdWithContacts(Set<Id> accountIds) {
        fflib_QueryFactory accountQuery = newQueryFactory();

        fflib_QueryFactory contactsSubQuery = new ContactsSelector()
            .addQueryFactorySubselect(accountQuery);

        return (List<Account>) Database.query(
            accountQuery.setCondition('Id IN :accountIds').toSOQL()
        );
    }
}
```

---

## fflib Domain Layer

Encapsulates business logic for a single sObject type.

```apex
public inherited sharing class Accounts extends fflib_SObjectDomain {

    public Accounts(List<Account> records) {
        super(records);
    }

    public class Constructor implements fflib_SObjectDomain.IConstructable {
        public fflib_SObjectDomain construct(List<SObject> sObjectList) {
            return new Accounts(sObjectList);
        }
    }

    public override void onValidate() {
        for (Account acc : (List<Account>) Records) {
            if (acc.AnnualRevenue != null && acc.AnnualRevenue < 0) {
                acc.AnnualRevenue.addError('Annual Revenue cannot be negative');
            }
        }
    }

    public override void onBeforeInsert() {
        setDefaultStatus();
        assignAccountOwner();
    }

    public override void onAfterInsert() {
        createDefaultOpportunities();
    }

    private void setDefaultStatus() {
        for (Account acc : (List<Account>) Records) {
            if (String.isBlank(acc.Status__c)) {
                acc.Status__c = 'New';
            }
        }
    }

    private void createDefaultOpportunities() {
        List<Opportunity> oppsToCreate = new List<Opportunity>();

        for (Account acc : (List<Account>) Records) {
            if (acc.Type == 'Prospect') {
                oppsToCreate.add(new Opportunity(
                    Name = acc.Name + ' - Initial Opportunity',
                    AccountId = acc.Id,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30)
                ));
            }
        }

        if (!oppsToCreate.isEmpty()) {
            fflib_ISObjectUnitOfWork uow = new fflib_SObjectUnitOfWork(
                new List<Schema.SObjectType> { Opportunity.SObjectType }
            );
            uow.registerNew(oppsToCreate);
            uow.commitWork();
        }
    }
}

// Trigger - ONE TRIGGER PER OBJECT
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete) {

    fflib_SObjectDomain.triggerHandler(Accounts.class);
}
```

---

## fflib Service Layer

Orchestrates business processes across multiple objects.

```apex
public with sharing class AccountService {

    @InvocableMethod(label='Process Account Tier Update')
    public static void processAccountTierUpdate(List<AccountTierRequest> requests) {
        Set<Id> accountIds = new Set<Id>();
        for (AccountTierRequest req : requests) {
            accountIds.add(req.accountId);
        }

        fflib_ISObjectUnitOfWork uow = new fflib_SObjectUnitOfWork(
            new List<Schema.SObjectType> {
                Account.SObjectType, Opportunity.SObjectType, Task.SObjectType
            }
        );

        List<Account> accounts = new AccountsSelector().selectById(accountIds);

        for (AccountTierRequest req : requests) {
            Account acc = findAccountById(accounts, req.accountId);
            if (acc != null) {
                updateAccountTier(acc, req.newTier, uow);
                createFollowUpTasks(acc, req.newTier, uow);
            }
        }

        uow.commitWork();
    }

    private static void updateAccountTier(Account acc, String newTier,
                                          fflib_ISObjectUnitOfWork uow) {
        Account accountToUpdate = new Account(
            Id = acc.Id,
            Tier__c = newTier,
            Tier_Updated_Date__c = Date.today()
        );
        uow.registerDirty(accountToUpdate);
    }

    public class AccountTierRequest {
        @InvocableVariable(required=true)
        public Id accountId;

        @InvocableVariable(required=true)
        public String newTier;
    }
}
```

---

## Governor Limits & Bulkification

### Key Limits (2026)

| Limit | Synchronous | Asynchronous |
|-------|-------------|--------------|
| SOQL Queries | 100 | 200 |
| Records retrieved by SOQL | 50,000 | 50,000 |
| DML Statements | 150 | 150 |
| Heap Size | 6 MB | 12 MB |
| CPU Time | 10,000 ms | 60,000 ms |

### Bulkification Patterns

```apex
// BAD: SOQL in loop
for (Account acc : Trigger.new) {
    List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acc.Id];
}

// GOOD: Bulkified query
Set<Id> accountIds = new Map<Id, Account>((List<Account>) Trigger.new).keySet();
Map<Id, List<Contact>> contactsByAccountId = new Map<Id, List<Contact>>();

for (Contact c : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds]) {
    if (!contactsByAccountId.containsKey(c.AccountId)) {
        contactsByAccountId.put(c.AccountId, new List<Contact>());
    }
    contactsByAccountId.get(c.AccountId).add(c);
}

// GOOD: Aggregate SOQL for counts
Map<Id, Integer> opportunityCountByAccount = new Map<Id, Integer>();
for (AggregateResult ar : [
    SELECT AccountId, COUNT(Id) oppCount
    FROM Opportunity WHERE AccountId IN :accountIds
    GROUP BY AccountId
]) {
    opportunityCountByAccount.put(
        (Id) ar.get('AccountId'), (Integer) ar.get('oppCount')
    );
}

// GOOD: Maps for O(1) lookups
Map<Id, Account> accountMap = new Map<Id, Account>(
    [SELECT Id, Name, Industry FROM Account WHERE Id IN :accountIds]
);
```

---

## SOQL/SOSL Optimization

```apex
// Use WITH SECURITY_ENFORCED (user mode)
List<Account> accounts = [
    SELECT Id, Name FROM Account
    WHERE Industry = 'Technology'
    WITH SECURITY_ENFORCED
];

// NEW in Spring '26 - User Mode
List<Account> accounts = [
    SELECT Id, Name FROM Account
    WHERE Industry = 'Technology'
    WITH USER_MODE
];

// Polymorphic SOQL with TYPEOF
List<Task> tasks = [
    SELECT Id, Subject,
        TYPEOF What
            WHEN Account THEN Name, Industry
            WHEN Opportunity THEN Name, StageName
            ELSE Name
        END
    FROM Task WHERE OwnerId = :UserInfo.getUserId()
];

// Cursor-Based Pagination (Spring '26)
Database.Cursor cursor = Database.getCursor([
    SELECT Id, Name FROM Account WHERE Industry = 'Technology'
]);
while (cursor.hasNext()) {
    List<Account> batch = (List<Account>) cursor.next(200);
    // Process batch
}

// SOSL for text search across multiple objects
List<List<SObject>> searchResults = [
    FIND 'Acme' IN ALL FIELDS
    RETURNING
        Account(Id, Name WHERE Industry = 'Technology'),
        Contact(Id, Name, Email),
        Opportunity(Id, Name, StageName)
    LIMIT 50
];
```

---

## Asynchronous Processing

### Queueable with Finalizer

```apex
public class AccountTierUpdateQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> accountIds;
    private String tier;

    public AccountTierUpdateQueueable(List<Id> accountIds, String tier) {
        this.accountIds = accountIds;
        this.tier = tier;
    }

    public void execute(QueueableContext context) {
        System.attachFinalizer(new AccountQueueableFinalizer(context.getJobId()));

        List<Account> accounts = [SELECT Id FROM Account WHERE Id IN :accountIds];
        for (Account acc : accounts) {
            acc.Tier__c = tier;
        }
        update accounts;

        // Chain another job
        if (!accounts.isEmpty()) {
            System.enqueueJob(new OpportunityTierUpdateQueueable(accountIds, tier));
        }
    }
}

public class AccountQueueableFinalizer implements System.Finalizer {
    private Id jobId;

    public AccountQueueableFinalizer(Id jobId) {
        this.jobId = jobId;
    }

    public void execute(System.FinalizerContext context) {
        if (context.getResult() == System.ParentJobResult.SUCCESS) {
            System.debug('Job succeeded: ' + jobId);
        } else {
            // Log error and optionally retry
            Error_Log__c log = new Error_Log__c(
                Job_Id__c = jobId,
                Error_Message__c = context.getException().getMessage()
            );
            insert log;
        }
    }
}
```

### Batch Apex

```apex
public class AccountBatchProcessor implements Database.Batchable<SObject>, Database.Stateful {

    private Integer recordsProcessed = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, AnnualRevenue FROM Account
            WHERE LastModifiedDate >= LAST_N_DAYS:30
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        List<Account> toUpdate = new List<Account>();
        for (Account acc : scope) {
            if (acc.AnnualRevenue > 10000000) {
                acc.Tier__c = 'Enterprise';
                toUpdate.add(acc);
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
            recordsProcessed += toUpdate.size();
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Records processed: ' + recordsProcessed);
    }
}

// Execute: Database.executeBatch(new AccountBatchProcessor(), 200);
```

---

## Platform Events & CDC

```apex
// Publish Platform Event
public class AccountEventPublisher {
    public static void publishAccountUpdates(List<Account> accounts) {
        List<Account_Update__e> events = new List<Account_Update__e>();
        for (Account acc : accounts) {
            events.add(new Account_Update__e(
                Account_Id__c = acc.Id,
                Status__c = acc.Status__c
            ));
        }
        List<Database.SaveResult> results = EventBus.publish(events);
    }
}

// Subscribe via Trigger
trigger AccountUpdateEventTrigger on Account_Update__e (after insert) {
    for (Account_Update__e event : Trigger.new) {
        AccountEventProcessor.processAsync(event);
    }
}
```

---

## Custom Metadata

```apex
// Query Custom Metadata (no SOQL limit!)
List<Integration_Config__mdt> configs = [
    SELECT Endpoint__c, Timeout__c, API_Key__c
    FROM Integration_Config__mdt
    WHERE Environment__c = 'Production'
];

// Use getInstance for single record
public class IntegrationService {
    private static Integration_Config__mdt getConfig() {
        return Integration_Config__mdt.getInstance('Production_API');
    }

    public static void callExternalSystem() {
        Integration_Config__mdt config = getConfig();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.Endpoint__c);
        req.setTimeout(Integer.valueOf(config.Timeout__c));
    }
}
```

---

## Best Practices

1. **fflib patterns for enterprise** - Selector, Domain, Service, Unit of Work
2. **One trigger per object** - Delegate to Domain layer
3. **Bulkify everything** - Design for 200+ records in trigger context
4. **Maps for O(1) lookups** - Never iterate lists for lookups
5. **Aggregate queries** - Use COUNT, SUM instead of Python-style loops
6. **WITH USER_MODE in SOQL** - Enforce FLS and CRUD checks (Spring '26+)
7. **Queueable with Finalizer** - Guaranteed error handling for async jobs
8. **Custom Metadata for config** - Deployable, no SOQL limit, packageable
9. **Platform Events for decoupling** - Behavior-based event-driven architecture

---

## Anti-Patterns

- SOQL or DML inside loops (governor limit violations)
- Single-record trigger handlers (not bulk-safe)
- Business logic in triggers (use Domain/Service layers)
- Hardcoding IDs or endpoints (use Custom Metadata)
- Missing `WITH SECURITY_ENFORCED` or `WITH USER_MODE`
- Using `@future` when `Queueable` would be better (no chaining, no monitoring)
- Not using `Database.SaveResult` with partial success for bulk DML
- Processing 50M records with synchronous SOQL (use Batch Apex)

---

## Sources & References

- [fflib Apex Enterprise Framework](https://fflib.dev/docs)
- [Salesforce Governor Limits 2025 Guide](https://medium.com/@dev-nkp/salesforce-governor-limits-2025-complete-guide-to-understanding-and-managing-platform-boundaries-b52f886dc995)
- [SOQL Polymorphic Relationships](https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_soql_relationships_and_polymorph_keys.htm)
- [Platform Events vs Change Data Capture](https://developer.salesforce.com/blogs/2022/10/design-considerations-for-change-data-capture-and-platform-events)
- [Salesforce Asynchronous Apex Guide](https://sfdcprep.com/salesforce-apex-future-vs-queueable-vs-batch-vs-schedulable/)
- [Custom Metadata Types vs Custom Settings](https://medium.com/@kalachnancy/when-to-use-custom-metadata-custom-settings-or-custom-labels-in-salesforce-d34467e3aa7e)
- [The Salesforce Developer's Guide to Winter '26](https://developer.salesforce.com/blogs/2025/09/winter26-developers)
