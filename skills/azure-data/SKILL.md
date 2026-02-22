---
name: azure-data
description: Production-grade Azure data services -- Azure SQL, Cosmos DB, PostgreSQL Flexible, Blob Storage, Table Storage, Redis Cache with Bicep
---

# Azure Data Services -- Staff Engineer Patterns

Production-ready patterns for Azure SQL, Cosmos DB, PostgreSQL Flexible Server, Blob Storage, Table Storage, and Redis Cache using Bicep.

## Table of Contents
1. [Cosmos DB Advanced Patterns](#cosmos-db-advanced-patterns)
2. [Azure SQL Patterns](#azure-sql-patterns)
3. [PostgreSQL Flexible Server](#postgresql-flexible-server)
4. [Azure Blob Storage](#azure-blob-storage)
5. [Table Storage](#table-storage)
6. [Azure Cache for Redis](#azure-cache-for-redis)
7. [Event Grid & Service Bus](#event-grid--service-bus)
8. [Best Practices](#best-practices)
9. [Anti-Patterns](#anti-patterns)
10. [Sources & References](#sources--references)

---

## Cosmos DB Advanced Patterns

### Multi-Region Write with Hierarchical Partition Keys

```bicep
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: 'cosmos-${appName}-${env}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
      maxIntervalInSeconds: 5
      maxStalenessPrefix: 100
    }
    locations: [
      { locationName: 'East US', failoverPriority: 0, isZoneRedundant: true }
      { locationName: 'West US', failoverPriority: 1, isZoneRedundant: true }
    ]
    databaseAccountOfferType: 'Standard'
    enableMultipleWriteLocations: true
    enableAutomaticFailover: true
    backupPolicy: {
      type: 'Continuous'
      continuousModeProperties: { tier: 'Continuous7Days' }
    }
    publicNetworkAccess: 'Disabled'
    networkAclBypass: 'AzureServices'
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: 'ecommerce'
  properties: {
    resource: { id: 'ecommerce' }
  }
}

// Hierarchical partition key (Cosmos DB v3)
resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: 'orders'
  properties: {
    resource: {
      id: 'orders'
      partitionKey: {
        paths: ['/tenantId', '/customerId', '/orderDate']
        kind: 'MultiHash'
        version: 2
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          { path: '/status/?' }
          { path: '/orderDate/?' }
        ]
        excludedPaths: [
          { path: '/metadata/*' }
        ]
        compositeIndexes: [
          [
            { path: '/customerId', order: 'ascending' }
            { path: '/orderDate', order: 'descending' }
          ]
        ]
      }
      uniqueKeyPolicy: {
        uniqueKeys: [
          { paths: ['/orderId'] }
        ]
      }
    }
    options: {
      autoscaleSettings: { maxThroughput: 4000 }
    }
  }
}
```

### Change Feed Pattern with Azure Functions

```csharp
[Function("OrderChangeFeedProcessor")]
public async Task ProcessOrderChanges(
    [CosmosDBTrigger(
        databaseName: "ecommerce",
        containerName: "orders",
        Connection = "CosmosConnection",
        LeaseContainerName = "leases",
        CreateLeaseContainerIfNotExists = true,
        StartFromBeginning = false,
        MaxItemsPerInvocation = 100,
        FeedPollDelay = 1000)]
    IReadOnlyList<Order> input,
    FunctionContext context)
{
    var logger = context.GetLogger(nameof(ProcessOrderChanges));

    foreach (var order in input)
    {
        logger.LogInformation("Order {OrderId} changed. Status: {Status}",
            order.Id, order.Status);

        await _eventPublisher.PublishAsync(new OrderChangedEvent
        {
            OrderId = order.Id,
            CustomerId = order.CustomerId,
            Status = order.Status,
            Timestamp = DateTime.UtcNow
        });
    }
}
```

---

## Azure SQL Patterns

### Azure SQL with Elastic Pool

```bicep
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: 'sql-${appName}-${env}'
  location: location
  properties: {
    administratorLogin: 'sqladmin'
    administratorLoginPassword: sqlAdminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource elasticPool 'Microsoft.Sql/servers/elasticPools@2023-05-01-preview' = {
  parent: sqlServer
  name: 'pool-${appName}'
  location: location
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 4
  }
  properties: {
    maxSizeBytes: 107374182400 // 100GB
    perDatabaseSettings: {
      minCapacity: json('0.25')
      maxCapacity: json('4')
    }
    zoneRedundant: true
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: 'db-${appName}'
  location: location
  sku: {
    name: 'ElasticPool'
    tier: 'GeneralPurpose'
  }
  properties: {
    elasticPoolId: elasticPool.id
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 53687091200 // 50GB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: true
  }
}

// Auditing
resource auditSettings 'Microsoft.Sql/servers/auditingSettings@2023-05-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    storageEndpoint: storageAccount.properties.primaryEndpoints.blob
    storageAccountAccessKey: storageAccount.listKeys().keys[0].value
    retentionDays: 90
    auditActionsAndGroups: [
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'BATCH_COMPLETED_GROUP'
    ]
  }
}
```

---

## PostgreSQL Flexible Server

### Production PostgreSQL with HA

```bicep
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: 'psql-${appName}-${env}'
  location: location
  sku: {
    name: 'Standard_D4ds_v5'
    tier: 'GeneralPurpose'
  }
  properties: {
    version: '16'
    administratorLogin: 'pgadmin'
    administratorLoginPassword: pgAdminPassword
    storage: {
      storageSizeGB: 128
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 35
      geoRedundantBackup: 'Enabled'
    }
    highAvailability: {
      mode: 'ZoneRedundant'
      standbyAvailabilityZone: '2'
    }
    network: {
      delegatedSubnetResourceId: pgSubnetId
      privateDnsZoneArmResourceId: privateDnsZone.id
    }
    maintenanceWindow: {
      customWindow: 'Enabled'
      dayOfWeek: 0  // Sunday
      startHour: 2
      startMinute: 0
    }
  }
}

// Server parameters
resource pgConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  parent: postgres
  name: 'shared_preload_libraries'
  properties: {
    value: 'pg_stat_statements,auto_explain'
    source: 'user-override'
  }
}
```

---

## Azure Blob Storage

### Lifecycle Management and Cost Optimization

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${appName}${env}${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'Standard_GRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_3'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    encryption: {
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 7 }
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
    changeFeed: { enabled: true, retentionInDays: 7 }
    isVersioningEnabled: true
    lastAccessTimeTrackingPolicy: {
      enable: true
      name: 'AccessTimeTracking'
      trackingGranularityInDays: 1
      blobType: ['blockBlob']
    }
  }
}

// Lifecycle management policy
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'MoveToCool'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['documents/', 'backups/']
            }
            actions: {
              baseBlob: {
                tierToCool: { daysAfterModificationGreaterThan: 30 }
                tierToArchive: { daysAfterModificationGreaterThan: 90 }
                delete: { daysAfterModificationGreaterThan: 365 }
              }
              snapshot: {
                delete: { daysAfterCreationGreaterThan: 90 }
              }
            }
          }
        }
        {
          name: 'DeleteOldLogs'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['logs/']
            }
            actions: {
              baseBlob: {
                delete: { daysAfterLastAccessTimeGreaterThan: 30 }
              }
            }
          }
        }
      ]
    }
  }
}

// Immutability policy for compliance
resource auditContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'audit-logs'
  properties: {
    immutableStorageWithVersioning: { enabled: true }
    publicAccess: 'None'
  }
}
```

### Application Code -- Azure SDK

```typescript
import { DefaultAzureCredential } from '@azure/identity';
import { BlobServiceClient } from '@azure/storage-blob';

const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.AZURE_CLIENT_ID
});

const blobServiceClient = new BlobServiceClient(
  'https://stmyapp.blob.core.windows.net',
  credential
);

const containerClient = blobServiceClient.getContainerClient('data');

// Upload blob
await containerClient.uploadBlockBlob('file.txt', Buffer.from('content'), 7);

// Download blob
const blobClient = containerClient.getBlobClient('file.txt');
const downloadResponse = await blobClient.download();
```

---

## Table Storage

### Table Storage for Simple Key-Value Patterns

```typescript
import { TableClient } from '@azure/data-tables';
import { DefaultAzureCredential } from '@azure/identity';

const credential = new DefaultAzureCredential();
const tableClient = new TableClient(
  'https://stmyapp.table.core.windows.net',
  'sessions',
  credential
);

// Create entity
await tableClient.createEntity({
  partitionKey: 'user-123',
  rowKey: 'session-456',
  data: JSON.stringify({ role: 'admin' }),
  expiresAt: new Date(Date.now() + 86400000),
});

// Query entities
const entities = tableClient.listEntities({
  queryOptions: {
    filter: `PartitionKey eq 'user-123'`,
  },
});

for await (const entity of entities) {
  console.log(entity.rowKey);
}
```

---

## Azure Cache for Redis

### Production Redis with Bicep

```bicep
resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: 'redis-${appName}-${env}'
  location: location
  properties: {
    sku: {
      name: 'Premium'
      family: 'P'
      capacity: 1
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisVersion: '7'
    replicasPerMaster: 1
    replicasPerPrimary: 1
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
      'maxmemory-reserved': '200'
    }
    publicNetworkAccess: 'Disabled'
  }
  zones: ['1', '2']
}

// Private endpoint
resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${redis.name}'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'redis-connection'
        properties: {
          privateLinkServiceId: redis.id
          groupIds: ['redisCache']
        }
      }
    ]
  }
}
```

---

## Event Grid & Service Bus

### Event-Driven Architecture Pattern

```bicep
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2023-01-01-preview' = {
  name: 'sb-${appName}-${env}'
  location: location
  sku: { name: 'Premium', tier: 'Premium', capacity: 1 }
  properties: {
    zoneRedundant: true
    publicNetworkAccess: 'Disabled'
  }
}

resource orderTopic 'Microsoft.ServiceBus/namespaces/topics@2023-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'orders'
  properties: {
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enablePartitioning: true
    supportOrdering: true
  }
}

resource processingSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2023-01-01-preview' = {
  parent: orderTopic
  name: 'order-processing'
  properties: {
    requiresSession: true
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
    defaultMessageTimeToLive: 'P14D'
    lockDuration: 'PT5M'
  }
}
```

---

## Best Practices

1. **Use Cosmos DB hierarchical partition keys** -- enables efficient multi-tenant data modeling
2. **Enable continuous backup** on Cosmos DB -- point-in-time restore within 7 or 30 days
3. **Use Change Feed** for event sourcing -- react to data changes without polling
4. **Set autoscale throughput** on Cosmos DB -- avoid manual RU provisioning
5. **Use lifecycle management** on Blob Storage -- automate tier transitions for cost savings
6. **Enable zone redundancy** on Azure SQL and Redis -- cross-zone HA at no extra cost
7. **Use private endpoints** for all data services -- keep traffic on Azure backbone
8. **Enable auditing** on Azure SQL -- required for compliance and security forensics
9. **Use Premium tier Redis** for production -- supports clustering, geo-replication, persistence
10. **Use Managed Identity** for all data access -- never store connection strings in code

---

## Anti-Patterns

1. **Using Cosmos DB without indexing policy** -- default indexes everything, costing unnecessary RUs
2. **Cross-partition queries as primary access pattern** -- design partition keys for your queries
3. **Storing blobs in Hot tier forever** -- implement lifecycle policies for cost savings
4. **Using Basic tier Redis for production** -- no SLA, no persistence, no clustering
5. **Connection strings in app settings** -- use Managed Identity and Key Vault references
6. **Not enabling soft delete** on Blob Storage -- data loss is permanent without it
7. **Using single-region Cosmos DB for production** -- always enable multi-region for HA
8. **Over-provisioning Azure SQL DTUs** -- use elastic pools and serverless tier for variable workloads

---

## Sources & References

- [Cosmos DB Change Feed Design Patterns](https://learn.microsoft.com/en-us/azure/cosmos-db/change-feed-design-patterns)
- [Cosmos DB Partitioning](https://learn.microsoft.com/en-us/azure/cosmos-db/partitioning)
- [Mastering Azure Cosmos DB](https://medium.com/emerline-tech-talk/mastering-azure-cosmos-db-the-ultimate-guide-for-developers-7e4d6d29caff)
- [Azure Storage 2026](https://azure.microsoft.com/en-us/blog/beyond-boundaries-the-future-of-azure-storage-in-2026/)
- [Azure Blob Storage Lifecycle Management](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview)
- [Optimize Azure Blob Storage Costs](https://oneuptime.com/blog/post/2026-02-16-how-to-optimize-azure-blob-storage-costs-with-lifecycle-management-policies/view)
- [Azure Cache for Redis Best Practices](https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-best-practices)
- [Azure Service Bus Topics](https://oneuptime.com/blog/post/2026-01-30-azure-service-bus-topics/view)
- [Compare Azure Messaging Services](https://learn.microsoft.com/en-us/azure/service-bus-messaging/compare-messaging-services)
