---
name: salesforce-lwc
description: Salesforce Lightning Web Components — @wire reactive data, lifecycle hooks, event handling, Lightning Message Service, SLDS, accessibility, dynamic imports, Agentforce AI
---

# Salesforce Lightning Web Components

Staff-engineer-level LWC patterns for 2026. Covers @wire for reactive data fetching, lifecycle hooks, event handling and composition, Lightning Message Service (LMS) for pub/sub, memoization and performance, dynamic imports for code splitting, complex expressions (Spring '26), and Agentforce AI integration.

## Table of Contents

1. [Component Architecture](#component-architecture)
2. [Lifecycle Hooks](#lifecycle-hooks)
3. [Performance Patterns](#performance-patterns)
4. [Event Handling & LMS](#event-handling--lms)
5. [Complex Expressions (Spring '26)](#complex-expressions-spring-26)
6. [Flow vs Apex Decision Framework](#flow-vs-apex-decision-framework)
7. [Agentforce AI Integration](#agentforce-ai-integration)
8. [Best Practices](#best-practices)
9. [Anti-Patterns](#anti-patterns)

---

## Component Architecture

### Reactive with @wire

```javascript
// accountCard.js
import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import updateAccountStatus from '@salesforce/apex/AccountService.updateAccountStatus';

import ACCOUNT_NAME from '@salesforce/schema/Account.Name';
import ACCOUNT_INDUSTRY from '@salesforce/schema/Account.Industry';
import ACCOUNT_REVENUE from '@salesforce/schema/Account.AnnualRevenue';
import ACCOUNT_STATUS from '@salesforce/schema/Account.Status__c';

const FIELDS = [ACCOUNT_NAME, ACCOUNT_INDUSTRY, ACCOUNT_REVENUE, ACCOUNT_STATUS];

export default class AccountCard extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    account;

    get accountName() {
        return getFieldValue(this.account.data, ACCOUNT_NAME);
    }

    get accountIndustry() {
        return getFieldValue(this.account.data, ACCOUNT_INDUSTRY);
    }

    get isActive() {
        return getFieldValue(this.account.data, ACCOUNT_STATUS) === 'Active';
    }

    // Use imperative Apex for user actions
    async handleActivate() {
        try {
            await updateAccountStatus({
                accountId: this.recordId,
                status: 'Active'
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Account activated successfully',
                variant: 'success'
            }));

            return refreshApex(this.account);

        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error activating account',
                message: error.body.message,
                variant: 'error'
            }));
        }
    }
}
```

---

## Lifecycle Hooks

```javascript
import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class DataStreamComponent extends LightningElement {
    subscription = {};
    isFirstRender = true;

    // Called when inserted into DOM
    connectedCallback() {
        this.initializeComponent();
        this.subscribeToEvents();

        onError(error => {
            console.error('EMP API error:', error);
        });
    }

    // Called after every render
    renderedCallback() {
        // NEVER update @wire or @api properties here - causes infinite loops
        // Use for DOM manipulation only
        if (this.isFirstRender) {
            this.initializeThirdPartyLibrary();
            this.isFirstRender = false;
        }
    }

    // Called when removed from DOM
    disconnectedCallback() {
        // CRITICAL: Clean up resources to prevent memory leaks
        this.unsubscribeFromEvents();
        this.clearTimers();
        this.destroyThirdPartyLibraries();
    }

    // Error boundary - catches errors in child components
    errorCallback(error, stack) {
        console.error('Error in component tree:', error);
        this.error = error;
        this.logErrorToService(error, stack);
    }

    subscribeToEvents() {
        const messageCallback = (response) => {
            this.handlePlatformEvent(response);
        };

        subscribe('/event/Account_Update__e', -1, messageCallback)
            .then(response => {
                this.subscription = response;
            });
    }

    unsubscribeFromEvents() {
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }
}
```

---

## Performance Patterns

### Memoization

```javascript
import { LightningElement, wire } from 'lwc';
import getAccountData from '@salesforce/apex/AccountService.getAccountData';

export default class OptimizedComponent extends LightningElement {
    accountDataCache = new Map();

    @wire(getAccountData, { accountId: '$recordId' })
    wiredAccountData({ data, error }) {
        if (data) {
            const cacheKey = this.recordId;
            if (!this.accountDataCache.has(cacheKey)) {
                this.accountDataCache.set(cacheKey, this.processData(data));
            }
            this.processedData = this.accountDataCache.get(cacheKey);
        }
    }

    processData(data) {
        // Expensive computation here
        return data;
    }
}
```

### Dynamic Imports for Code Splitting

```javascript
import { LightningElement } from 'lwc';

export default class ChartComponent extends LightningElement {
    chartLibraryLoaded = false;

    async loadChartLibrary() {
        if (!this.chartLibraryLoaded) {
            await import('c/chartJsLibrary');
            this.chartLibraryLoaded = true;
        }
    }

    async handleShowChart() {
        await this.loadChartLibrary();
        this.renderChart();
    }
}
```

### Versioned Event Contracts

```javascript
// Publisher
export default class PublisherComponent extends LightningElement {
    notifyUpdate() {
        const event = new CustomEvent('product:updated:v2', {
            detail: {
                productId: this.productId,
                timestamp: Date.now(),
                changes: ['price', 'inventory']
            },
            bubbles: true,
            composed: true
        });
        this.dispatchEvent(event);
    }
}

// Consumer
export default class SubscriberComponent extends LightningElement {
    handleProductUpdate(event) {
        const { productId, changes } = event.detail;
        // Handle v2 event structure
    }
}
```

---

## Event Handling & LMS

### Lightning Message Service (Pub/Sub)

```javascript
import { LightningElement, wire } from 'lwc';
import { publish, subscribe, MessageContext } from 'lightning/messageService';
import ACCOUNT_UPDATED_CHANNEL from '@salesforce/messageChannel/Account_Updated__c';

// Publisher
export default class AccountPublisher extends LightningElement {
    @wire(MessageContext)
    messageContext;

    publishAccountUpdate() {
        const payload = {
            accountId: this.recordId,
            status: 'Updated'
        };
        publish(this.messageContext, ACCOUNT_UPDATED_CHANNEL, payload);
    }
}

// Subscriber
export default class AccountSubscriber extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription = null;

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            ACCOUNT_UPDATED_CHANNEL,
            (message) => this.handleAccountUpdate(message)
        );
    }

    handleAccountUpdate(message) {
        console.log('Account updated:', message.accountId);
    }
}
```

### EMP API for Platform Events

```javascript
import { LightningElement } from 'lwc';
import { subscribe, onError } from 'lightning/empApi';

export default class AccountEventSubscriber extends LightningElement {
    subscription = {};

    connectedCallback() {
        this.handleSubscribe();
        this.registerErrorListener();
    }

    handleSubscribe() {
        const messageCallback = (response) => {
            const event = response.data.payload;
            console.log('Account updated:', event.Account_Id__c);
        };

        subscribe('/event/Account_Update__e', -1, messageCallback)
            .then(response => {
                this.subscription = response;
            });
    }

    registerErrorListener() {
        onError(error => {
            console.error('EMP API error:', error);
        });
    }
}
```

---

## Complex Expressions (Spring '26)

```html
<!-- NEW in Spring '26 - Complex expressions directly in markup -->
<template>
    <div if:true={account.AnnualRevenue > 1000000 && account.Status === 'Active'}>
        <p>Premium Active Account</p>
    </div>

    <p>{account.CreatedDate.toLocaleDateString('en-US')}</p>

    <!-- No need for getters for simple logic -->
    <p class={isActive ? 'active-class' : 'inactive-class'}></p>
</template>
```

---

## Flow vs Apex Decision Framework

### Decision Tree

```
START
  |
  +-- Can Flow do this reliably?
  |   +-- YES -> Use Flow (faster, admin-friendly)
  |   +-- NO -> Continue
  |
  +-- Is it simple CRUD with basic logic?
  |   +-- YES -> Use Flow
  |   +-- NO -> Continue
  |
  +-- Does it require complex loops or collections?
  |   +-- YES -> Use Apex
  |   +-- NO -> Continue
  |
  +-- Does it need external API callouts?
  |   +-- YES -> Use Apex (or Invocable Apex from Flow)
  |   +-- NO -> Continue
  |
  +-- Is it processing >1000 records at once?
  |   +-- YES -> Use Apex (bulkification required)
  |   +-- NO -> Try Flow first
```

### Hybrid Approach: Invocable Apex

```apex
public class AccountInvocableActions {

    @InvocableMethod(label='Calculate Account Score'
                     description='Complex scoring logic')
    public static List<Result> calculateAccountScore(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Decimal score = performComplexCalculation(req.accountId);
            results.add(new Result(score));
        }

        return results;
    }

    public class Request {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    public class Result {
        @InvocableVariable
        public Decimal score;

        public Result(Decimal score) {
            this.score = score;
        }
    }
}
```

---

## Agentforce AI Integration

```apex
public class AgentforceAccountActions {

    @InvocableMethod(
        label='Analyze Account Health'
        description='AI-powered account health analysis'
        category='Agentforce'
    )
    public static List<AnalysisResult> analyzeAccountHealth(List<Request> requests) {
        Set<Id> accountIds = new Set<Id>();
        for (Request req : requests) {
            accountIds.add(req.accountId);
        }

        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, Name, AnnualRevenue,
                (SELECT Id, StageName, Amount FROM Opportunities WHERE IsClosed = false),
                (SELECT Id, Status FROM Cases WHERE IsClosed = false)
            FROM Account WHERE Id IN :accountIds
        ]);

        List<AnalysisResult> results = new List<AnalysisResult>();
        for (Request req : requests) {
            Account acc = accountMap.get(req.accountId);
            AnalysisResult result = new AnalysisResult();

            Decimal healthScore = calculateHealthScore(acc);
            result.healthScore = healthScore;
            result.insights = generateInsights(acc, healthScore);
            result.recommendations = generateRecommendations(acc, healthScore);

            results.add(result);
        }

        return results;
    }

    private static Decimal calculateHealthScore(Account acc) {
        Decimal score = 50;
        if (acc.AnnualRevenue != null && acc.AnnualRevenue > 10000000) score += 20;

        Decimal openOppAmount = 0;
        for (Opportunity opp : acc.Opportunities) {
            openOppAmount += opp.Amount != null ? opp.Amount : 0;
        }
        if (openOppAmount > 500000) score += 15;

        Integer openCases = acc.Cases.size();
        if (openCases == 0) score += 15;
        else if (openCases > 10) score -= 20;

        return Math.min(100, Math.max(0, score));
    }

    public class Request {
        @InvocableVariable(required=true label='Account ID')
        public Id accountId;
    }

    public class AnalysisResult {
        @InvocableVariable(label='Health Score')
        public Decimal healthScore;

        @InvocableVariable(label='Insights')
        public String insights;

        @InvocableVariable(label='Recommendations')
        public String recommendations;
    }
}
```

---

## Best Practices

1. **@wire for reactive data** - Automatic refresh when parameters change
2. **Imperative Apex for actions** - User-triggered operations with try/catch
3. **Lifecycle cleanup** - Always unsubscribe and clear resources in `disconnectedCallback`
4. **LMS for cross-component** - Pub/sub between unrelated components
5. **Memoize expensive computations** - Cache processed data in Maps
6. **Dynamic imports** - Lazy load heavy libraries for faster initial render
7. **Event versioning** - Use versioned event names for backward compatibility
8. **Invocable Apex from Flow** - Hybrid approach for complex calculations
9. **Agentforce structured data** - Return `@InvocableVariable` results for AI actions

---

## Anti-Patterns

- Updating @wire or @api properties in `renderedCallback` (infinite loops)
- Missing `disconnectedCallback` cleanup (memory leaks from subscriptions)
- Using imperative Apex when @wire would auto-refresh
- Not using `refreshApex()` after imperative data modifications
- Complex business logic in LWC JavaScript (move to Apex service layer)
- Hardcoded record IDs in components
- Not handling @wire errors (only checking `data`, ignoring `error`)
- Polling instead of using Platform Events for real-time updates

---

## Sources & References

- [LWC Best Practices in 2025](https://medium.com/@saurabh.samirs/lwc-best-practices-in-2025-performance-optimization-anti-patterns-to-avoid-25c315a38202)
- [Advanced Patterns in Salesforce LWC](https://dzone.com/articles/salesforce-lwc-reusable-components-performance-optimization)
- [Salesforce Spring '26 Release Guide](https://www.jitendrazaa.com/blog/salesforce/salesforce-spring-26-release-complete-guide-2026/)
- [Salesforce Flow vs Apex Decision Guide](https://medium.com/@akash15_dev/salesforce-flow-vs-apex-when-to-use-what-5ccf12735a8f)
- [Agentforce Assistant Documentation](https://www.salesforce.com/agentforce/einstein-copilot/)
- [The Salesforce Developer's Guide to Winter '26](https://developer.salesforce.com/blogs/2025/09/winter26-developers)
