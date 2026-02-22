---
name: salesforce-testing
description: Salesforce testing patterns — TestDataFactory, @TestSetup, bulk testing, System.runAs, HttpCalloutMock, Stub API, Jest for LWC, test best practices
---

# Salesforce Testing Patterns

Staff-engineer-level Salesforce testing patterns. Covers TestDataFactory for reusable test data, @TestSetup for shared data, bulk testing (200+ records), System.runAs for permission testing, HttpCalloutMock for callout mocking, Stub API for dependency injection, Jest testing for LWC, and testing best practices.

## Table of Contents

1. [Test Data Factory](#test-data-factory)
2. [Test Class Patterns](#test-class-patterns)
3. [HTTP Callout Mocking](#http-callout-mocking)
4. [Stub API for Mocking](#stub-api-for-mocking)
5. [LWC Jest Testing](#lwc-jest-testing)
6. [Permission Testing](#permission-testing)
7. [Best Practices](#best-practices)
8. [Anti-Patterns](#anti-patterns)

---

## Test Data Factory

Centralized, reusable test data creation.

```apex
@isTest
public class TestDataFactory {

    public static List<Account> createAccounts(Integer count, Boolean doInsert) {
        List<Account> accounts = new List<Account>();

        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Industry = 'Technology',
                AnnualRevenue = 1000000 + (i * 100000),
                Status__c = 'Active',
                BillingCountry = 'USA'
            ));
        }

        if (doInsert) {
            insert accounts;
        }

        return accounts;
    }

    public static List<Contact> createContacts(List<Account> accounts,
                                                Integer contactsPerAccount,
                                                Boolean doInsert) {
        List<Contact> contacts = new List<Contact>();

        for (Account acc : accounts) {
            for (Integer i = 0; i < contactsPerAccount; i++) {
                contacts.add(new Contact(
                    FirstName = 'Test',
                    LastName = 'Contact ' + i,
                    AccountId = acc.Id,
                    Email = 'test' + i + '@example.com'
                ));
            }
        }

        if (doInsert) {
            insert contacts;
        }

        return contacts;
    }

    public static User createTestUser(String profileName, Boolean doInsert) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];

        User u = new User(
            Alias = 'testU',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + System.now().getTime() + '@example.com'
        );

        if (doInsert) {
            insert u;
        }

        return u;
    }

    public static List<Opportunity> createOpportunities(List<Account> accounts,
                                                         Integer oppsPerAccount,
                                                         Boolean doInsert) {
        List<Opportunity> opps = new List<Opportunity>();

        for (Account acc : accounts) {
            for (Integer i = 0; i < oppsPerAccount; i++) {
                opps.add(new Opportunity(
                    Name = acc.Name + ' Opp ' + i,
                    AccountId = acc.Id,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30),
                    Amount = 50000 + (i * 10000)
                ));
            }
        }

        if (doInsert) {
            insert opps;
        }

        return opps;
    }
}
```

---

## Test Class Patterns

### Full Test Class with @TestSetup

```apex
@isTest
private class AccountServiceTest {

    // Create data once for all tests
    @TestSetup
    static void setupTestData() {
        List<Account> accounts = TestDataFactory.createAccounts(200, true);
        List<Contact> contacts = TestDataFactory.createContacts(accounts, 3, true);
    }

    @isTest
    static void testGetActiveAccounts_BulkScenario() {
        // Arrange
        List<Account> accounts = [SELECT Id FROM Account];
        Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();

        // Act
        Test.startTest();
        List<Account> result = AccountService.getActiveAccounts(accountIds);
        Test.stopTest();

        // Assert
        System.assertEquals(200, result.size(), 'Should return all test accounts');
        System.assertNotEquals(null, result[0].Name, 'Name should be populated');
    }

    @isTest
    static void testUpdateAccountStatus_Success() {
        // Arrange
        List<Account> accounts = [SELECT Id FROM Account LIMIT 10];

        // Act
        Test.startTest();
        AccountService.updateAccountStatus(accounts, 'Inactive');
        Test.stopTest();

        // Assert
        List<Account> updated = [
            SELECT Id, Status__c FROM Account WHERE Id IN :accounts
        ];
        for (Account acc : updated) {
            System.assertEquals('Inactive', acc.Status__c, 'Status should be updated');
        }
    }

    @isTest
    static void testUpdateAccountStatus_EmptyList() {
        // Act
        Test.startTest();
        AccountService.updateAccountStatus(new List<Account>(), 'Inactive');
        Test.stopTest();

        // Assert - should not throw
        System.assert(true, 'Should handle empty list gracefully');
    }

    @isTest
    static void testProcessAccountTierUpdate_Platinum() {
        // Arrange
        Account acc = [SELECT Id FROM Account LIMIT 1];

        AccountService.AccountTierRequest req = new AccountService.AccountTierRequest();
        req.accountId = acc.Id;
        req.newTier = 'Platinum';

        // Act
        Test.startTest();
        AccountService.processAccountTierUpdate(new List<AccountService.AccountTierRequest>{req});
        Test.stopTest();

        // Assert
        Account updated = [SELECT Tier__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Platinum', updated.Tier__c);

        // Verify follow-up task was created
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :acc.Id];
        System.assert(!tasks.isEmpty(), 'Follow-up task should be created for Platinum');
    }
}
```

---

## HTTP Callout Mocking

```apex
@isTest
global class ExternalSystemMock implements HttpCalloutMock {

    private Integer statusCode;
    private String responseBody;

    global ExternalSystemMock(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
    }

    global HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(responseBody);
        res.setHeader('Content-Type', 'application/json');
        return res;
    }
}

@isTest
private class IntegrationServiceTest {

    @isTest
    static void testCallExternalSystem_Success() {
        // Arrange
        String mockResponse = '{"status": "success", "message": "Data received"}';
        Test.setMock(HttpCalloutMock.class, new ExternalSystemMock(200, mockResponse));

        // Act
        Test.startTest();
        String result = IntegrationService.callExternalSystem();
        Test.stopTest();

        // Assert
        System.assertEquals('success', result, 'Should return success status');
    }

    @isTest
    static void testCallExternalSystem_ServerError() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new ExternalSystemMock(500, 'Server Error'));

        // Act
        Test.startTest();
        String result = IntegrationService.callExternalSystem();
        Test.stopTest();

        // Assert
        System.assertEquals(null, result, 'Should handle error gracefully');
    }

    @isTest
    static void testCallExternalSystem_Timeout() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new ExternalSystemMock(408, 'Request Timeout'));

        // Act & Assert
        Test.startTest();
        try {
            IntegrationService.callExternalSystem();
        } catch (CalloutException e) {
            System.assert(true, 'Should throw callout exception on timeout');
        }
        Test.stopTest();
    }
}
```

### Multi-Callout Mock

```apex
@isTest
global class MultiCalloutMock implements HttpCalloutMock {

    Map<String, HttpResponse> responseMap = new Map<String, HttpResponse>();

    public void addResponse(String endpoint, Integer statusCode, String body) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(body);
        responseMap.put(endpoint, res);
    }

    global HttpResponse respond(HttpRequest req) {
        String endpoint = req.getEndpoint();
        for (String key : responseMap.keySet()) {
            if (endpoint.contains(key)) {
                return responseMap.get(key);
            }
        }
        // Default response
        HttpResponse defaultRes = new HttpResponse();
        defaultRes.setStatusCode(404);
        defaultRes.setBody('Not Found');
        return defaultRes;
    }
}
```

---

## Stub API for Mocking

```apex
@isTest
private class AccountServiceMockTest {

    private class AccountSelectorStub implements System.StubProvider {
        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            Type returnType,
            List<Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            if (stubbedMethodName == 'selectById') {
                return new List<Account>{
                    new Account(Id = '001000000000001', Name = 'Mock Account')
                };
            }
            return null;
        }
    }

    @isTest
    static void testWithMockedSelector() {
        // Create stub
        AccountsSelector mockSelector = (AccountsSelector) Test.createStub(
            AccountsSelector.class,
            new AccountSelectorStub()
        );

        // Use mocked selector
        List<Account> accounts = mockSelector.selectById(new Set<Id>{'001000000000001'});

        // Assert
        System.assertEquals(1, accounts.size());
        System.assertEquals('Mock Account', accounts[0].Name);
    }
}
```

---

## LWC Jest Testing

```javascript
// accountCard.test.js
import { createElement } from 'lwc';
import AccountCard from 'c/accountCard';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import { getRecord } from 'lightning/uiRecordApi';

const mockGetRecord = registerLdsTestWireAdapter(getRecord);

describe('c-account-card', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('displays account name when data is loaded', () => {
        // Arrange
        const element = createElement('c-account-card', {
            is: AccountCard
        });
        element.recordId = '001000000000001';
        document.body.appendChild(element);

        // Mock wire data
        const mockAccount = {
            fields: {
                Name: { value: 'Acme Corporation' },
                Industry: { value: 'Technology' }
            }
        };

        // Act
        mockGetRecord.emit(mockAccount);

        // Assert
        return Promise.resolve().then(() => {
            const nameElement = element.shadowRoot.querySelector('p');
            expect(nameElement.textContent).toBe('Industry: Technology');
        });
    });

    it('handles error gracefully', () => {
        // Arrange
        const element = createElement('c-account-card', {
            is: AccountCard
        });
        document.body.appendChild(element);

        // Act - emit error
        mockGetRecord.error();

        // Assert
        return Promise.resolve().then(() => {
            const errorElement = element.shadowRoot.querySelector('.error');
            expect(errorElement).not.toBeNull();
        });
    });

    it('dispatches toast on successful activate', () => {
        // Arrange
        const element = createElement('c-account-card', {
            is: AccountCard
        });
        element.recordId = '001000000000001';
        document.body.appendChild(element);

        // Listen for toast event
        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        // Act
        const button = element.shadowRoot.querySelector('button');
        button.click();

        // Assert
        return Promise.resolve().then(() => {
            expect(toastHandler).toHaveBeenCalled();
        });
    });
});
```

---

## Permission Testing

```apex
@isTest
private class PermissionTest {

    @isTest
    static void testUpdateAccountStatus_NoAccess() {
        User testUser = TestDataFactory.createTestUser('Standard User', true);
        List<Account> accounts = TestDataFactory.createAccounts(10, true);

        System.runAs(testUser) {
            Test.startTest();
            try {
                AccountService.updateAccountStatus(accounts, 'Inactive');
                System.assert(false, 'Should throw security exception');
            } catch (SecurityException e) {
                System.assert(true, 'Expected security exception');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testRecordVisibility() {
        User user1 = TestDataFactory.createTestUser('Standard User', true);
        User user2 = TestDataFactory.createTestUser('Standard User', true);

        Account acc;
        System.runAs(user1) {
            acc = new Account(Name = 'User1 Account');
            insert acc;
        }

        System.runAs(user2) {
            // Depending on sharing rules, user2 may not see this account
            List<Account> visible = [SELECT Id FROM Account WHERE Id = :acc.Id];
            // Assert based on expected sharing configuration
        }
    }
}
```

---

## Best Practices

1. **Test bulk scenarios** - 200 records minimum in trigger tests
2. **Use @TestSetup** - Create shared data once, not in every method
3. **Test positive, negative, and edge cases** - Empty lists, null values, boundary conditions
4. **Test with different permissions** - Use `System.runAs()` for user context testing
5. **Mock external callouts** - Use `HttpCalloutMock` for all HTTP integrations
6. **Meaningful assertions** - Assert specific values, not just "not null"
7. **Test async with Test.startTest/stopTest** - Forces async code to execute synchronously
8. **Aim for 95%+ coverage** - Not just the 75% minimum
9. **TestDataFactory** - Centralize test data creation for consistency
10. **Clean up DOM in Jest** - Remove elements in `afterEach` to prevent test pollution
11. **Use Stub API** - Mock dependencies without database for unit tests
12. **Test event handling in LWC** - Verify both dispatch and handling of events

---

## Anti-Patterns

- Hardcoding record IDs in tests (use `@TestSetup` and queries)
- Testing with single records only (not bulk-safe)
- Testing for code coverage only, not behavior
- Not testing error paths (only happy path)
- Missing `Test.startTest()`/`Test.stopTest()` for async operations
- Sharing test data between test methods via static variables (fragile)
- Not cleaning up DOM in Jest `afterEach` (test pollution)
- Using `seeAllData=true` (accessing org data makes tests fragile)
- Not testing security with `System.runAs()` and different profiles

---

## Sources & References

- [Salesforce Mock in Apex Tests](https://blog.beyondthecloud.dev/blog/salesforce-mock-in-apex-tests)
- [Salesforce Governor Limits 2025 Guide](https://medium.com/@dev-nkp/salesforce-governor-limits-2025-complete-guide-to-understanding-and-managing-platform-boundaries-b52f886dc995)
- [Testing Patterns and Best Practices](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_testing.htm)
- [LWC Jest Testing Documentation](https://developer.salesforce.com/docs/component-library/documentation/en/lwc/lwc.testing)
- [fflib Apex Enterprise Framework](https://fflib.dev/docs)
- [Build CI/CD Pipeline with GitHub Actions](https://www.salesforceben.com/build-your-own-ci-cd-pipeline-in-salesforce-using-github-actions/)
