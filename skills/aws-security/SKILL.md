---
name: aws-security
description: Production-grade AWS security patterns -- IAM, Secrets Manager, KMS, WAF, VPC networking, GuardDuty, and compliance with CDK
---

# AWS Security -- Staff Engineer Patterns

Production-ready patterns for IAM, Secrets Manager, KMS, WAF, Security Groups, NACLs, VPC design, and threat detection on AWS using CDK v2.

## Table of Contents
1. [IAM Best Practices](#iam-best-practices)
2. [Secrets Management](#secrets-management)
3. [KMS Encryption](#kms-encryption)
4. [WAF Patterns](#waf-patterns)
5. [VPC Networking & Security](#vpc-networking--security)
6. [GuardDuty & Threat Detection](#guardduty--threat-detection)
7. [Best Practices](#best-practices)
8. [Anti-Patterns](#anti-patterns)
9. [Common CLI Commands](#common-cli-commands)
10. [Sources & References](#sources--references)

---

## IAM Best Practices

### Least Privilege Policies

```typescript
import * as iam from 'aws-cdk-lib/aws-iam';

// DO NOT DO THIS -- too permissive
const badPolicy = new iam.PolicyStatement({
  actions: ['s3:*'],
  resources: ['*'],
});

// DO THIS -- specific actions and resources
const goodPolicy = new iam.PolicyStatement({
  actions: ['s3:GetObject', 's3:PutObject'],
  resources: ['arn:aws:s3:::my-bucket/uploads/*'],
});

const role = new iam.Role(this, 'AppRole', {
  assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
  managedPolicies: [
    iam.ManagedPolicy.fromAwsManagedPolicyName(
      'service-role/AWSLambdaBasicExecutionRole'
    ),
  ],
});

role.addToPolicy(goodPolicy);
```

### Permission Boundaries

```typescript
const permissionBoundary = new iam.ManagedPolicy(this, 'Boundary', {
  statements: [
    new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['s3:*', 'dynamodb:*', 'lambda:*'],
      resources: ['*'],
    }),
    new iam.PolicyStatement({
      effect: iam.Effect.DENY,
      actions: ['iam:*', 'organizations:*', 'account:*'],
      resources: ['*'],
    }),
  ],
});

const role = new iam.Role(this, 'DeveloperRole', {
  assumedBy: new iam.AccountPrincipal('123456789012'),
  permissionsBoundary: permissionBoundary,
});
```

### Attribute-Based Access Control (ABAC)

```typescript
// ABAC policy using tags -- users can only access resources tagged with their team
const abacPolicy = new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: ['s3:GetObject', 's3:PutObject'],
  resources: ['arn:aws:s3:::*/*'],
  conditions: {
    StringEquals: {
      's3:ExistingObjectTag/Team': '${aws:PrincipalTag/Team}',
    },
  },
});

const role = new iam.Role(this, 'TeamRole', {
  assumedBy: new iam.AccountPrincipal('123456789012'),
});
role.addToPolicy(abacPolicy);

// Tag resources and principals with Team tag
cdk.Tags.of(bucket).add('Team', 'engineering');
```

### Cross-Account Access with Assume Role

```typescript
// In Account A (123456789012) - Role to be assumed
const crossAccountRole = new iam.Role(this, 'CrossAccountRole', {
  roleName: 'CrossAccountS3Access',
  assumedBy: new iam.AccountPrincipal('987654321098'),
  externalIds: ['unique-external-id-12345'],
  maxSessionDuration: cdk.Duration.hours(4),
});

crossAccountRole.addToPolicy(
  new iam.PolicyStatement({
    actions: ['s3:GetObject', 's3:ListBucket'],
    resources: [
      'arn:aws:s3:::shared-bucket',
      'arn:aws:s3:::shared-bucket/*',
    ],
  })
);

// In Account B (987654321098) - Lambda that assumes role
const lambdaRole = new iam.Role(this, 'LambdaRole', {
  assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
});

lambdaRole.addToPolicy(
  new iam.PolicyStatement({
    actions: ['sts:AssumeRole'],
    resources: ['arn:aws:iam::123456789012:role/CrossAccountS3Access'],
  })
);
```

```typescript
// Lambda code to assume cross-account role
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';

const sts = new STSClient({});

export async function handler(event: any) {
  const { Credentials } = await sts.send(
    new AssumeRoleCommand({
      RoleArn: 'arn:aws:iam::123456789012:role/CrossAccountS3Access',
      RoleSessionName: 'lambda-session',
      ExternalId: 'unique-external-id-12345',
      DurationSeconds: 3600,
    })
  );

  const s3 = new S3Client({
    credentials: {
      accessKeyId: Credentials!.AccessKeyId!,
      secretAccessKey: Credentials!.SecretAccessKey!,
      sessionToken: Credentials!.SessionToken!,
    },
  });

  const response = await s3.send(
    new GetObjectCommand({ Bucket: 'shared-bucket', Key: 'data.json' })
  );

  return { statusCode: 200, body: 'Success' };
}
```

### GitHub Actions OIDC Provider

```typescript
const githubProvider = new iam.OpenIdConnectProvider(this, 'GithubProvider', {
  url: 'https://token.actions.githubusercontent.com',
  clientIds: ['sts.amazonaws.com'],
  thumbprints: ['6938fd4d98bab03faadb97b34396831e3780aea1'],
});

const githubRole = new iam.Role(this, 'GitHubActionsRole', {
  roleName: 'GitHubActionsDeployRole',
  assumedBy: new iam.FederatedPrincipal(
    githubProvider.openIdConnectProviderArn,
    {
      StringEquals: {
        'token.actions.githubusercontent.com:aud': 'sts.amazonaws.com',
      },
      StringLike: {
        'token.actions.githubusercontent.com:sub': 'repo:myorg/myrepo:*',
      },
    },
    'sts:AssumeRoleWithWebIdentity'
  ),
  maxSessionDuration: cdk.Duration.hours(1),
});
```

---

## Secrets Management

### Secrets Manager with Auto-Rotation

```typescript
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

const dbSecret = new secretsmanager.Secret(this, 'DBSecret', {
  secretName: 'prod/db/credentials',
  generateSecretString: {
    secretStringTemplate: JSON.stringify({ username: 'dbadmin' }),
    generateStringKey: 'password',
    excludePunctuation: true,
    passwordLength: 32,
  },
});

// Enable automatic rotation
dbSecret.addRotationSchedule('RotationSchedule', {
  automaticallyAfter: cdk.Duration.days(30),
  hostedRotation: secretsmanager.HostedRotation.postgresqlSingleUser(),
});
```

### Parameter Store Hierarchical Configuration

```typescript
import * as ssm from 'aws-cdk-lib/aws-ssm';

// Hierarchical parameter structure
const params = {
  '/myapp/prod/api/endpoint': 'https://api.example.com',
  '/myapp/prod/api/key': 'secure-api-key',
  '/myapp/prod/feature/new-ui': 'true',
  '/myapp/prod/db/host': 'db.example.com',
};

Object.entries(params).forEach(([name, value]) => {
  new ssm.StringParameter(this, name.replace(/\//g, '-'), {
    parameterName: name,
    stringValue: value,
    tier: ssm.ParameterTier.STANDARD,
  });
});
```

```typescript
// Lambda reading hierarchical parameters
import { SSMClient, GetParametersByPathCommand } from '@aws-sdk/client-ssm';

const ssm = new SSMClient({});

export async function loadConfig(path: string) {
  const { Parameters } = await ssm.send(
    new GetParametersByPathCommand({
      Path: path,
      Recursive: true,
      WithDecryption: true,
    })
  );

  const config: Record<string, string> = {};
  Parameters?.forEach(param => {
    const key = param.Name!.split('/').pop()!;
    config[key] = param.Value!;
  });

  return config;
}
```

### Secrets Manager + Parameter Store Integration

```typescript
const apiKey = new secretsmanager.Secret(this, 'ApiKey', {
  secretName: 'prod/external-api/key',
});

// Reference secret from Parameter Store
const param = new ssm.StringParameter(this, 'ApiKeyParam', {
  parameterName: '/myapp/prod/api-key',
  stringValue: `{{resolve:secretsmanager:${apiKey.secretArn}}}`,
});
```

---

## KMS Encryption

### Customer-Managed Key for Cross-Service Encryption

```typescript
import * as kms from 'aws-cdk-lib/aws-kms';

const key = new kms.Key(this, 'AppKey', {
  alias: 'alias/my-app-key',
  description: 'KMS key for application data encryption',
  enableKeyRotation: true,
  rotationPeriod: cdk.Duration.days(365),
  pendingWindow: cdk.Duration.days(7),
  removalPolicy: cdk.RemovalPolicy.RETAIN,
  policy: new iam.PolicyDocument({
    statements: [
      // Allow key administration
      new iam.PolicyStatement({
        actions: ['kms:*'],
        resources: ['*'],
        principals: [new iam.AccountRootPrincipal()],
      }),
      // Allow key usage by specific roles
      new iam.PolicyStatement({
        actions: [
          'kms:Encrypt',
          'kms:Decrypt',
          'kms:ReEncrypt*',
          'kms:GenerateDataKey*',
          'kms:DescribeKey',
        ],
        resources: ['*'],
        principals: [appRole],
      }),
    ],
  }),
});

// Use CMK for S3 encryption
const bucket = new s3.Bucket(this, 'Bucket', {
  encryption: s3.BucketEncryption.KMS,
  encryptionKey: key,
  bucketKeyEnabled: true, // Reduces KMS API calls
});

// Use CMK for DynamoDB encryption
const table = new dynamodb.Table(this, 'Table', {
  partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
  encryption: dynamodb.TableEncryption.CUSTOMER_MANAGED,
  encryptionKey: key,
});
```

---

## WAF Patterns

### WAF v2 with CloudFront

```typescript
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';

const webAcl = new wafv2.CfnWebACL(this, 'WebACL', {
  name: 'api-protection',
  scope: 'CLOUDFRONT', // or 'REGIONAL' for ALB/API Gateway
  defaultAction: { allow: {} },
  visibilityConfig: {
    cloudWatchMetricsEnabled: true,
    metricName: 'WebACL',
    sampledRequestsEnabled: true,
  },
  rules: [
    // Rate limiting
    {
      name: 'RateLimit',
      priority: 1,
      action: { block: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: 'RateLimit',
        sampledRequestsEnabled: true,
      },
      statement: {
        rateBasedStatement: {
          limit: 2000,
          aggregateKeyType: 'IP',
        },
      },
    },
    // AWS Managed Rules - Common Rule Set
    {
      name: 'AWSManagedRulesCommon',
      priority: 2,
      overrideAction: { none: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: 'CommonRules',
        sampledRequestsEnabled: true,
      },
      statement: {
        managedRuleGroupStatement: {
          vendorName: 'AWS',
          name: 'AWSManagedRulesCommonRuleSet',
        },
      },
    },
    // SQL injection protection
    {
      name: 'AWSManagedRulesSQLi',
      priority: 3,
      overrideAction: { none: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: 'SQLiRules',
        sampledRequestsEnabled: true,
      },
      statement: {
        managedRuleGroupStatement: {
          vendorName: 'AWS',
          name: 'AWSManagedRulesSQLiRuleSet',
        },
      },
    },
    // Bot control
    {
      name: 'AWSManagedRulesBotControl',
      priority: 4,
      overrideAction: { none: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: 'BotControl',
        sampledRequestsEnabled: true,
      },
      statement: {
        managedRuleGroupStatement: {
          vendorName: 'AWS',
          name: 'AWSManagedRulesBotControlRuleSet',
          managedRuleGroupConfigs: [
            { awsManagedRulesBotControlRuleSet: { inspectionLevel: 'COMMON' } },
          ],
        },
      },
    },
  ],
});
```

---

## VPC Networking & Security

### Multi-Tier VPC with Transit Gateway

```typescript
import * as ec2 from 'aws-cdk-lib/aws-ec2';

const sharedVpc = new ec2.Vpc(this, 'SharedVpc', {
  cidr: '10.0.0.0/16',
  maxAzs: 3,
  subnetConfiguration: [
    { name: 'Public', subnetType: ec2.SubnetType.PUBLIC, cidrMask: 24 },
    { name: 'Private', subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, cidrMask: 24 },
  ],
  flowLogs: {
    cloudwatch: {
      destination: ec2.FlowLogDestination.toCloudWatchLogs(),
      trafficType: ec2.FlowLogTrafficType.REJECT,
    },
  },
});

const prodVpc = new ec2.Vpc(this, 'ProdVpc', { cidr: '10.1.0.0/16', maxAzs: 3 });
const devVpc = new ec2.Vpc(this, 'DevVpc', { cidr: '10.2.0.0/16', maxAzs: 2 });

// Transit Gateway to connect VPCs
const tgw = new ec2.CfnTransitGateway(this, 'TransitGateway', {
  amazonSideAsn: 64512,
  defaultRouteTableAssociation: 'enable',
  defaultRouteTablePropagation: 'enable',
  dnsSupport: 'enable',
  vpnEcmpSupport: 'enable',
});

[sharedVpc, prodVpc, devVpc].forEach((vpc, i) => {
  new ec2.CfnTransitGatewayAttachment(this, `Attachment${i}`, {
    transitGatewayId: tgw.ref,
    vpcId: vpc.vpcId,
    subnetIds: vpc.privateSubnets.map(s => s.subnetId),
  });
});
```

### VPC Endpoints for AWS Services

```typescript
// Interface endpoints (cost per hour + data transfer)
vpc.addInterfaceEndpoint('SecretsEndpoint', {
  service: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
  privateDnsEnabled: true,
});

vpc.addInterfaceEndpoint('STSEndpoint', {
  service: ec2.InterfaceVpcEndpointAwsService.STS,
});

// Gateway endpoints (free)
vpc.addGatewayEndpoint('S3GatewayEndpoint', {
  service: ec2.GatewayVpcEndpointAwsService.S3,
  subnets: [{ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }],
});

vpc.addGatewayEndpoint('DynamoGatewayEndpoint', {
  service: ec2.GatewayVpcEndpointAwsService.DYNAMODB,
});
```

### Security Groups and NACLs

```typescript
// Application security group
const appSg = new ec2.SecurityGroup(this, 'AppSG', {
  vpc,
  description: 'Application security group',
  allowAllOutbound: false,
});

appSg.addIngressRule(
  ec2.Peer.securityGroupId(albSg.securityGroupId),
  ec2.Port.tcp(3000),
  'Allow traffic from ALB only'
);

appSg.addEgressRule(
  ec2.Peer.securityGroupId(dbSg.securityGroupId),
  ec2.Port.tcp(5432),
  'Allow traffic to database'
);

appSg.addEgressRule(
  ec2.Peer.prefixList(s3PrefixListId),
  ec2.Port.tcp(443),
  'Allow HTTPS to S3 via gateway endpoint'
);

// Network ACL for additional defense layer
const nacl = new ec2.NetworkAcl(this, 'PrivateNACL', {
  vpc,
  subnetSelection: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
});

nacl.addEntry('AllowHTTPSInbound', {
  ruleNumber: 100,
  cidr: ec2.AclCidr.ipv4('10.0.0.0/8'),
  traffic: ec2.AclTraffic.tcpPort(443),
  direction: ec2.TrafficDirection.INGRESS,
  ruleAction: ec2.Action.ALLOW,
});

nacl.addEntry('DenyAllInbound', {
  ruleNumber: 200,
  cidr: ec2.AclCidr.anyIpv4(),
  traffic: ec2.AclTraffic.allTraffic(),
  direction: ec2.TrafficDirection.INGRESS,
  ruleAction: ec2.Action.DENY,
});
```

### PrivateLink for Service-to-Service Communication

```typescript
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';

// Service provider side
const nlb = new elbv2.NetworkLoadBalancer(this, 'NLB', {
  vpc: providerVpc,
  internetFacing: false,
});

const vpcEndpointService = new ec2.VpcEndpointService(this, 'EndpointService', {
  vpcEndpointServiceLoadBalancers: [nlb],
  acceptanceRequired: true,
  allowedPrincipals: [
    new iam.ArnPrincipal('arn:aws:iam::123456789012:root'),
  ],
});

// Service consumer side
const endpoint = new ec2.InterfaceVpcEndpoint(this, 'ServiceEndpoint', {
  vpc: consumerVpc,
  service: new ec2.InterfaceVpcEndpointService(
    vpcEndpointService.vpcEndpointServiceName
  ),
  privateDnsEnabled: false,
});
```

---

## GuardDuty & Threat Detection

### GuardDuty with Findings Notification

```typescript
import * as guardduty from 'aws-cdk-lib/aws-guardduty';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';

// Enable GuardDuty
const detector = new guardduty.CfnDetector(this, 'Detector', {
  enable: true,
  dataSources: {
    s3Logs: { enable: true },
    kubernetes: { auditLogs: { enable: true } },
    malwareProtection: {
      scanEc2InstanceWithFindings: {
        ebsVolumes: true,
      },
    },
  },
  findingPublishingFrequency: 'FIFTEEN_MINUTES',
});

// SNS topic for security alerts
const securityTopic = new sns.Topic(this, 'SecurityAlerts', {
  topicName: 'guardduty-findings',
});

// EventBridge rule to forward high-severity findings
const rule = new events.Rule(this, 'HighSeverityFindings', {
  eventPattern: {
    source: ['aws.guardduty'],
    detailType: ['GuardDuty Finding'],
    detail: {
      severity: [{ numeric: ['>=', 7] }],
    },
  },
});

rule.addTarget(new targets.SnsTopic(securityTopic));
```

### AWS Config Rules for Compliance

```typescript
import * as config from 'aws-cdk-lib/aws-config';

// Ensure S3 buckets are encrypted
new config.ManagedRule(this, 'S3BucketEncryption', {
  identifier: 'S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED',
  configRuleName: 's3-bucket-encryption',
});

// Ensure RDS instances are encrypted
new config.ManagedRule(this, 'RDSEncryption', {
  identifier: 'RDS_STORAGE_ENCRYPTED',
  configRuleName: 'rds-storage-encrypted',
});

// Ensure no public S3 buckets
new config.ManagedRule(this, 'S3PublicAccess', {
  identifier: 'S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED',
  configRuleName: 's3-bucket-public-access-prohibited',
});
```

---

## Best Practices

1. **Use IAM roles, not access keys** -- rotate to short-lived credentials via STS
2. **Enable MFA on all root accounts** -- use hardware tokens for production AWS accounts
3. **Apply permission boundaries** to limit what developers can grant to their own roles
4. **Use ABAC over RBAC** when possible -- tag-based access scales better than per-resource policies
5. **Rotate secrets automatically** -- Secrets Manager with Lambda rotation every 30 days
6. **Use customer-managed KMS keys** for regulated data -- enables key rotation and audit
7. **Enable VPC Flow Logs** on all VPCs -- essential for security forensics
8. **Use Security Groups as primary firewall** and NACLs as secondary defense
9. **Enable GuardDuty** in all accounts and regions -- low cost, high value threat detection
10. **Use VPC endpoints** for all AWS service calls from private subnets -- reduces attack surface

---

## Anti-Patterns

1. **Using wildcard (*) in IAM policies** -- always scope to specific actions and resources
2. **Embedding secrets in code or environment variables** -- use Secrets Manager or Parameter Store
3. **Opening Security Groups to 0.0.0.0/0** -- restrict to known CIDRs, use Bastion or SSM
4. **Sharing IAM access keys** -- each person/service gets their own role with unique credentials
5. **Disabling CloudTrail** -- keep it enabled in all regions for audit and compliance
6. **Using default VPC for production** -- always create custom VPCs with proper subnet design
7. **Not using VPC endpoints** -- traffic to AWS services should stay on the AWS backbone
8. **Ignoring GuardDuty findings** -- triage and remediate findings within SLA

---

## Common CLI Commands

```bash
# IAM
aws iam list-roles --query "Roles[*].RoleName"
aws iam get-role --role-name MyRole
aws iam simulate-principal-policy --policy-source-arn ROLE_ARN --action-names s3:GetObject
aws sts get-caller-identity

# Secrets Manager
aws secretsmanager create-secret --name my-secret --secret-string '{"key":"value"}'
aws secretsmanager get-secret-value --secret-id my-secret
aws secretsmanager rotate-secret --secret-id my-secret

# Parameter Store
aws ssm put-parameter --name /myapp/config/api-key --value "secret-key" --type SecureString
aws ssm get-parameters-by-path --path /myapp/config --with-decryption

# KMS
aws kms create-key --description "Application encryption key"
aws kms enable-key-rotation --key-id KEY_ID
aws kms list-aliases

# VPC & Security Groups
aws ec2 describe-security-groups --query "SecurityGroups[*].{Name:GroupName,Id:GroupId}"
aws ec2 describe-flow-logs --query "FlowLogs[*].{Id:FlowLogId,Status:FlowLogStatus}"

# GuardDuty
aws guardduty list-detectors
aws guardduty get-findings --detector-id DETECTOR_ID --finding-ids FINDING_IDS

# Config
aws configservice get-compliance-summary-by-config-rule
```

---

## Sources & References

- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS Secrets Manager vs Parameter Store](https://oneuptime.com/blog/post/2026-02-12-secrets-manager-vs-parameter-store/view)
- [AWS KMS Developer Guide](https://docs.aws.amazon.com/kms/latest/developerguide/overview.html)
- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/waf-chapter.html)
- [AWS VPC Networking Guide 2025](https://networks.tools/learn/article/aws-network-planning-guide)
- [Amazon GuardDuty User Guide](https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html)
- [GitHub Actions with AWS OIDC](https://aws.amazon.com/blogs/devops/integrating-with-github-actions-ci-cd-pipeline-to-deploy-a-web-app-to-amazon-ec2/)
- [AWS Config Rules](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html)
- [VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html)
