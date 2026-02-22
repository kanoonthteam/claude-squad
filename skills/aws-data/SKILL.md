---
name: aws-data
description: Production-grade AWS data services -- RDS/Aurora, DynamoDB, ElastiCache, S3, EFS with CDK constructs and access patterns
---

# AWS Data Services -- Staff Engineer Patterns

Production-ready patterns for RDS/Aurora, DynamoDB, ElastiCache, S3, and EFS on AWS using CDK v2.

## Table of Contents
1. [RDS & Aurora Patterns](#rds--aurora-patterns)
2. [DynamoDB Patterns](#dynamodb-patterns)
3. [ElastiCache Redis Patterns](#elasticache-redis-patterns)
4. [S3 Advanced Patterns](#s3-advanced-patterns)
5. [EFS Patterns](#efs-patterns)
6. [Best Practices](#best-practices)
7. [Anti-Patterns](#anti-patterns)
8. [Common CLI Commands](#common-cli-commands)
9. [Sources & References](#sources--references)

---

## RDS & Aurora Patterns

### Aurora Serverless v2 with Auto Scaling

```typescript
import * as cdk from 'aws-cdk-lib';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';

const cluster = new rds.DatabaseCluster(this, 'Database', {
  engine: rds.DatabaseClusterEngine.auroraPostgres({
    version: rds.AuroraPostgresEngineVersion.VER_16_6,
  }),
  vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
  writer: rds.ClusterInstance.serverlessV2('writer', {
    autoMinorVersionUpgrade: true,
  }),
  readers: [
    rds.ClusterInstance.serverlessV2('reader1', {
      scaleWithWriter: true,
    }),
    rds.ClusterInstance.serverlessV2('reader2', {
      scaleWithWriter: true,
    }),
  ],
  serverlessV2MinCapacity: 0.5,
  serverlessV2MaxCapacity: 16,
  credentials: rds.Credentials.fromGeneratedSecret('dbadmin'),
  defaultDatabaseName: 'appdb',
  backup: {
    retention: cdk.Duration.days(30),
    preferredWindow: '03:00-04:00',
  },
  storageEncrypted: true,
  deletionProtection: true,
  cloudwatchLogsRetention: logs.RetentionDays.ONE_MONTH,
  cloudwatchLogsExports: ['postgresql'],
  monitoringInterval: cdk.Duration.seconds(60),
  enableDataApi: true,
});

// Separate read-only endpoint for analytics/reporting
const readEndpoint = cluster.clusterReadEndpoint;
```

### RDS Proxy for Connection Pooling

```typescript
import * as rds from 'aws-cdk-lib/aws-rds';

const proxy = new rds.DatabaseProxy(this, 'Proxy', {
  proxyTarget: rds.ProxyTarget.fromCluster(cluster),
  secrets: [cluster.secret!],
  vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
  maxConnectionsPercent: 75,
  maxIdleConnectionsPercent: 50,
  connectionBorrowTimeout: cdk.Duration.seconds(120),
  sessionPinningFilters: [
    rds.SessionPinningFilter.EXCLUDE_VARIABLE_SETS,
  ],
  requireTLS: true,
  dbProxyName: 'my-app-proxy',
});

// Lambda uses proxy endpoint instead of cluster endpoint
const lambdaFn = new lambda.Function(this, 'Function', {
  // ... other config
  environment: {
    DB_ENDPOINT: proxy.endpoint,
    DB_PORT: '5432',
  },
});

proxy.grantConnect(lambdaFn);
```

### RDS Parameter Groups

```typescript
import * as rds from 'aws-cdk-lib/aws-rds';

const parameterGroup = new rds.ParameterGroup(this, 'ParameterGroup', {
  engine: rds.DatabaseClusterEngine.auroraPostgres({
    version: rds.AuroraPostgresEngineVersion.VER_16_6,
  }),
  parameters: {
    // Performance tuning
    'shared_preload_libraries': 'pg_stat_statements,auto_explain',
    'log_min_duration_statement': '1000',   // Log slow queries > 1s
    'auto_explain.log_min_duration': '1000',
    'auto_explain.log_analyze': 'true',

    // Connection management
    'idle_in_transaction_session_timeout': '300000', // 5 min timeout
    'statement_timeout': '60000',                     // 1 min query timeout

    // WAL and replication
    'max_wal_size': '4096',
    'checkpoint_completion_target': '0.9',

    // Query planner
    'random_page_cost': '1.1',  // SSD-optimized
    'effective_cache_size': '75% of RAM',
  },
});
```

### Multi-AZ RDS Instance

```typescript
const instance = new rds.DatabaseInstance(this, 'Database', {
  engine: rds.DatabaseInstanceEngine.postgres({
    version: rds.PostgresEngineVersion.VER_16,
  }),
  vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.R6G, ec2.InstanceSize.XLARGE),
  multiAz: true,
  storageType: rds.StorageType.GP3,
  allocatedStorage: 100,
  maxAllocatedStorage: 500,  // Auto-scaling
  iops: 3000,
  storageThroughput: 125,
  credentials: rds.Credentials.fromGeneratedSecret('dbadmin'),
  deletionProtection: true,
  storageEncrypted: true,
  performanceInsightRetention: rds.PerformanceInsightRetention.MONTHS_3,
  enablePerformanceInsights: true,
});
```

---

## DynamoDB Patterns

### Single-Table Design with GSI Overloading

```typescript
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';

const table = new dynamodb.Table(this, 'AppTable', {
  tableName: 'app-table',
  partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'SK', type: dynamodb.AttributeType.STRING },
  billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
  stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
  pointInTimeRecovery: true,
  encryption: dynamodb.TableEncryption.AWS_MANAGED,
  removalPolicy: cdk.RemovalPolicy.RETAIN,
});

// GSI1 - Overloaded for multiple access patterns
table.addGlobalSecondaryIndex({
  indexName: 'GSI1',
  partitionKey: { name: 'GSI1PK', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'GSI1SK', type: dynamodb.AttributeType.STRING },
  projectionType: dynamodb.ProjectionType.ALL,
});

// GSI2 - For status-based queries
table.addGlobalSecondaryIndex({
  indexName: 'GSI2',
  partitionKey: { name: 'GSI2PK', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'GSI2SK', type: dynamodb.AttributeType.STRING },
  projectionType: dynamodb.ProjectionType.ALL,
});
```

```typescript
// Single-table design access patterns
interface User {
  PK: string;      // USER#123
  SK: string;      // #METADATA
  GSI1PK: string;  // EMAIL#user@example.com
  GSI1SK: string;  // USER#123
  email: string;
  name: string;
}

interface Order {
  PK: string;      // USER#123
  SK: string;      // ORDER#2024-01-15#ORD-456
  GSI1PK: string;  // ORDER#ORD-456
  GSI1SK: string;  // 2024-01-15T10:30:00Z
  GSI2PK: string;  // STATUS#pending
  GSI2SK: string;  // 2024-01-15T10:30:00Z
  status: string;
  total: number;
}

// Query patterns:
// 1. Get user by ID:       PK=USER#123, SK=#METADATA
// 2. Get user by email:    GSI1PK=EMAIL#user@example.com
// 3. Get user's orders:    PK=USER#123, SK begins_with ORDER#
// 4. Get order by ID:      GSI1PK=ORDER#ORD-456
// 5. Get orders by status: GSI2PK=STATUS#pending, sorted by date
```

### DynamoDB Streams + Lambda Pattern

```typescript
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';

const streamProcessor = new lambda.Function(this, 'StreamProcessor', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
});

streamProcessor.addEventSource(
  new lambdaEventSources.DynamoEventSource(table, {
    startingPosition: lambda.StartingPosition.LATEST,
    batchSize: 100,
    bisectBatchOnError: true,
    maxBatchingWindow: cdk.Duration.seconds(10),
    retryAttempts: 3,
    parallelizationFactor: 10,
    filters: [
      lambda.FilterCriteria.filter({
        eventName: lambda.FilterRule.isEqual('INSERT'),
      }),
    ],
  })
);
```

### DynamoDB TTL Pattern

```typescript
const sessionTable = new dynamodb.Table(this, 'SessionTable', {
  partitionKey: { name: 'sessionId', type: dynamodb.AttributeType.STRING },
  billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
  timeToLiveAttribute: 'expiresAt',
});

// Usage - item will be automatically deleted after expiresAt timestamp
const item = {
  sessionId: 'session-123',
  userId: 'user-456',
  data: { /* session data */ },
  expiresAt: Math.floor(Date.now() / 1000) + (60 * 60 * 24), // 24 hours
};
```

### DAX Caching Pattern

```typescript
import * as dax from 'aws-cdk-lib/aws-dax';

const daxCluster = new dax.CfnCluster(this, 'DaxCluster', {
  iamRoleArn: role.roleArn,
  nodeType: 'dax.t3.small',
  replicationFactor: 3,
  subnetGroupName: subnetGroup.ref,
  securityGroupIds: [securityGroup.securityGroupId],
  clusterName: 'my-dax-cluster',
});

// Application uses DAX endpoint for microsecond read latency
const daxEndpoint = daxCluster.attrClusterDiscoveryEndpoint;
```

---

## ElastiCache Redis Patterns

### Redis Cluster with Multi-AZ

```typescript
import * as elasticache from 'aws-cdk-lib/aws-elasticache';

const subnetGroup = new elasticache.CfnSubnetGroup(this, 'SubnetGroup', {
  cacheSubnetGroupName: 'redis-subnet-group',
  description: 'Redis cache subnet group',
  subnetIds: vpc.privateSubnets.map(s => s.subnetId),
});

const securityGroup = new ec2.SecurityGroup(this, 'RedisSG', {
  vpc,
  description: 'Security group for Redis',
  allowAllOutbound: false,
});

securityGroup.addIngressRule(
  ec2.Peer.ipv4(vpc.vpcCidrBlock),
  ec2.Port.tcp(6379),
  'Allow Redis connections from VPC'
);

const redis = new elasticache.CfnReplicationGroup(this, 'Redis', {
  replicationGroupDescription: 'Production Redis cluster',
  engine: 'redis',
  engineVersion: '7.1',
  cacheNodeType: 'cache.r7g.large',
  numNodeGroups: 3,        // Shards for cluster mode
  replicasPerNodeGroup: 2, // Read replicas per shard
  automaticFailoverEnabled: true,
  multiAzEnabled: true,
  cacheSubnetGroupName: subnetGroup.ref,
  securityGroupIds: [securityGroup.securityGroupId],
  atRestEncryptionEnabled: true,
  transitEncryptionEnabled: true,
  autoMinorVersionUpgrade: true,
  snapshotRetentionLimit: 7,
  snapshotWindow: '05:00-06:00',
  cacheParameterGroupName: parameterGroup.ref,
});
```

### Redis Caching Strategies

```typescript
import { createClient } from 'redis';

const redis = createClient({ url: process.env.REDIS_URL });
await redis.connect();

// Cache-aside pattern
async function getUserWithCache(userId: string): Promise<User> {
  const cacheKey = `user:${userId}`;
  const cached = await redis.get(cacheKey);

  if (cached) {
    return JSON.parse(cached);
  }

  const user = await db.query('SELECT * FROM users WHERE id = $1', [userId]);

  // Set with TTL to prevent stale data
  await redis.setEx(cacheKey, 300, JSON.stringify(user)); // 5 min TTL

  return user;
}

// Write-through pattern with cache invalidation
async function updateUser(userId: string, data: Partial<User>): Promise<User> {
  const user = await db.query(
    'UPDATE users SET name=$2, email=$3 WHERE id=$1 RETURNING *',
    [userId, data.name, data.email]
  );

  // Update cache immediately
  const cacheKey = `user:${userId}`;
  await redis.setEx(cacheKey, 300, JSON.stringify(user));

  return user;
}

// Rate limiting with sliding window
async function checkRateLimit(ip: string, limit: number, windowSec: number): Promise<boolean> {
  const key = `ratelimit:${ip}`;
  const now = Date.now();
  const windowStart = now - (windowSec * 1000);

  const multi = redis.multi();
  multi.zRemRangeByScore(key, 0, windowStart);
  multi.zCard(key);
  multi.zAdd(key, { score: now, value: `${now}` });
  multi.expire(key, windowSec);

  const results = await multi.exec();
  const count = results[1] as number;

  return count < limit;
}
```

---

## S3 Advanced Patterns

### S3 Lifecycle Policies

```typescript
import * as s3 from 'aws-cdk-lib/aws-s3';

const bucket = new s3.Bucket(this, 'DataBucket', {
  bucketName: 'my-data-bucket',
  versioned: true,
  encryption: s3.BucketEncryption.S3_MANAGED,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  lifecycleRules: [
    {
      id: 'tiered-storage',
      transitions: [
        {
          storageClass: s3.StorageClass.INFREQUENT_ACCESS,
          transitionAfter: cdk.Duration.days(30),
        },
        {
          storageClass: s3.StorageClass.INTELLIGENT_TIERING,
          transitionAfter: cdk.Duration.days(90),
        },
        {
          storageClass: s3.StorageClass.GLACIER,
          transitionAfter: cdk.Duration.days(180),
        },
        {
          storageClass: s3.StorageClass.DEEP_ARCHIVE,
          transitionAfter: cdk.Duration.days(365),
        },
      ],
      expiration: cdk.Duration.days(730),
      noncurrentVersionExpiration: cdk.Duration.days(30),
    },
    {
      id: 'cleanup-multipart-uploads',
      abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
    },
  ],
});
```

### Presigned URLs for Secure Uploads

```typescript
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const s3Client = new S3Client({ region: 'us-east-1' });

export async function generateUploadUrl(
  bucket: string,
  key: string,
  expiresIn: number = 3600
): Promise<string> {
  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    ContentType: 'image/jpeg',
  });

  return await getSignedUrl(s3Client, command, { expiresIn });
}

// Usage in Lambda
export const handler = async (event: APIGatewayProxyEvent) => {
  const { filename } = JSON.parse(event.body || '{}');
  const key = `uploads/${Date.now()}-${filename}`;
  const uploadUrl = await generateUploadUrl('my-bucket', key);

  return {
    statusCode: 200,
    body: JSON.stringify({ uploadUrl }),
  };
};
```

### S3 Event Notifications to Lambda

```typescript
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';

const bucket = new s3.Bucket(this, 'UploadBucket');

const imageProcessor = new lambda.Function(this, 'ImageProcessor', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
});

bucket.addEventNotification(
  s3.EventType.OBJECT_CREATED,
  new s3n.LambdaDestination(imageProcessor),
  { prefix: 'uploads/', suffix: '.jpg' }
);
```

### Multipart Upload Pattern

```typescript
import {
  S3Client,
  CreateMultipartUploadCommand,
  UploadPartCommand,
  CompleteMultipartUploadCommand,
} from '@aws-sdk/client-s3';

async function multipartUpload(
  bucket: string,
  key: string,
  file: Buffer,
  partSize: number = 5 * 1024 * 1024 // 5MB minimum
) {
  const s3 = new S3Client({});

  const { UploadId } = await s3.send(
    new CreateMultipartUploadCommand({ Bucket: bucket, Key: key })
  );

  const numParts = Math.ceil(file.length / partSize);

  // Upload parts in parallel
  const uploadPromises = Array.from({ length: numParts }, async (_, i) => {
    const start = i * partSize;
    const end = Math.min(start + partSize, file.length);

    const { ETag } = await s3.send(
      new UploadPartCommand({
        Bucket: bucket,
        Key: key,
        PartNumber: i + 1,
        UploadId,
        Body: file.subarray(start, end),
      })
    );

    return { ETag: ETag!, PartNumber: i + 1 };
  });

  const parts = await Promise.all(uploadPromises);

  await s3.send(
    new CompleteMultipartUploadCommand({
      Bucket: bucket,
      Key: key,
      UploadId,
      MultipartUpload: { Parts: parts },
    })
  );
}
```

### S3 Express One Zone

```typescript
// S3 Express One Zone for high-performance workloads
const expressBucket = new s3.CfnBucket(this, 'ExpressBucket', {
  bucketName: 'my-express-bucket--usw2-az1--x-s3',
  dataRedundancy: 'SingleAvailabilityZone',
  type: 'Directory',
});

// Use for: ML training data, analytics, high-throughput applications
// Benefits: Sub-10ms latency, hundreds of thousands of requests/sec
```

---

## EFS Patterns

### EFS with CDK for Shared Storage

```typescript
import * as efs from 'aws-cdk-lib/aws-efs';

const fileSystem = new efs.FileSystem(this, 'SharedFileSystem', {
  vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
  performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
  throughputMode: efs.ThroughputMode.ELASTIC,
  encrypted: true,
  lifecyclePolicy: efs.LifecyclePolicy.AFTER_30_DAYS,
  transitionToArchivePolicy: efs.LifecyclePolicy.AFTER_90_DAYS,
  removalPolicy: cdk.RemovalPolicy.RETAIN,
  enableAutomaticBackups: true,
});

// Access point for application isolation
const accessPoint = fileSystem.addAccessPoint('AppAccessPoint', {
  path: '/app-data',
  createAcl: {
    ownerUid: '1001',
    ownerGid: '1001',
    permissions: '750',
  },
  posixUser: {
    uid: '1001',
    gid: '1001',
  },
});

// Mount in ECS task
const volumeName = 'efs-volume';
taskDef.addVolume({
  name: volumeName,
  efsVolumeConfiguration: {
    fileSystemId: fileSystem.fileSystemId,
    transitEncryption: 'ENABLED',
    authorizationConfig: {
      accessPointId: accessPoint.accessPointId,
      iam: 'ENABLED',
    },
  },
});

container.addMountPoints({
  containerPath: '/mnt/data',
  sourceVolume: volumeName,
  readOnly: false,
});
```

### EFS with Lambda

```typescript
const fn = new lambda.Function(this, 'Function', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
  vpc,
  filesystem: lambda.FileSystem.fromEfsAccessPoint(accessPoint, '/mnt/data'),
});
```

---

## Best Practices

1. **Use Aurora Serverless v2** for variable workloads -- scales to zero ACU, automatic failover
2. **Always use RDS Proxy** for Lambda-to-database connections -- prevents connection exhaustion
3. **Design DynamoDB tables access-pattern first** -- model GSIs around query patterns, not entities
4. **Enable Point-in-Time Recovery** on DynamoDB tables -- protects against accidental deletes
5. **Use TTL** to automatically clean up ephemeral data (sessions, caches, temp records)
6. **S3 lifecycle rules from day one** -- transition cold data to IA/Glacier automatically
7. **Block all public access** on S3 buckets -- use presigned URLs or CloudFront for access
8. **Enable versioning** on critical S3 buckets -- enables recovery from accidental deletes
9. **Use Redis cluster mode** for production -- enables horizontal scaling and data partitioning
10. **Encrypt at rest and in transit** for all data services -- enable TLS for Redis, storage encryption for RDS

---

## Anti-Patterns

1. **Using provisioned IOPS without measuring** -- start with gp3 and benchmark before paying for io2
2. **Opening RDS to 0.0.0.0/0** -- always restrict to VPC CIDRs and use private subnets
3. **Storing large objects in DynamoDB** -- max item size is 400KB; use S3 for blobs, store keys in DynamoDB
4. **Using Scan on DynamoDB** -- always use Query with partition key; Scan is O(n) and expensive
5. **Not setting connection limits on RDS** -- Lambda can easily exhaust connections without RDS Proxy
6. **Skipping S3 lifecycle policies** -- storage costs grow silently without automated tiering
7. **Using Redis without persistence config** -- configure AOF or RDB snapshots for data durability
8. **Ignoring DynamoDB hot partitions** -- distribute write load evenly across partition keys

---

## Common CLI Commands

```bash
# RDS / Aurora
aws rds describe-db-clusters --query "DBClusters[*].DBClusterIdentifier"
aws rds create-db-snapshot --db-instance-identifier my-db --db-snapshot-identifier my-snapshot
aws rds describe-db-cluster-endpoints --db-cluster-identifier my-cluster
aws rds-data execute-statement --resource-arn $CLUSTER_ARN --secret-arn $SECRET_ARN --sql "SELECT 1"

# DynamoDB
aws dynamodb scan --table-name MyTable --max-items 10
aws dynamodb query --table-name MyTable \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"USER#123"}}'
aws dynamodb describe-table --table-name MyTable --query "Table.ItemCount"
aws dynamodb batch-write-item --request-items file://items.json

# ElastiCache
aws elasticache describe-replication-groups --query "ReplicationGroups[*].ReplicationGroupId"
aws elasticache describe-cache-clusters --show-cache-node-info

# S3
aws s3 sync ./dist s3://my-bucket --delete
aws s3 presign s3://my-bucket/file.jpg --expires-in 3600
aws s3api head-object --bucket my-bucket --key path/to/file
aws s3api list-object-versions --bucket my-bucket --prefix uploads/

# EFS
aws efs describe-file-systems --query "FileSystems[*].{Id:FileSystemId,Size:SizeInBytes.Value}"
aws efs describe-mount-targets --file-system-id fs-12345
```

---

## Sources & References

- [Amazon RDS Proxy for Aurora](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy.html)
- [DynamoDB Single Table Design](https://www.serverlesslife.com/DynamoDB_Design_Patterns_for_Single_Table_Design.html)
- [S3 Lifecycle Policies Guide](https://www.astuto.ai/blogs/amazon-s3-lifecycle-policies)
- [Aurora Serverless v2 Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html)
- [ElastiCache Redis Best Practices](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/best-practices.html)
- [Amazon EFS User Guide](https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html)
- [DynamoDB DAX Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.html)
- [S3 Express One Zone](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-one-zone.html)
- [AWS CDK RDS Constructs](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_rds-readme.html)
