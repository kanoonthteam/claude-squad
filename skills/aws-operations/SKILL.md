---
name: aws-operations
description: Production-grade AWS operations -- CloudWatch, X-Ray, CDK pipelines, CI/CD, cost optimization, tagging, multi-account, and Terraform for AWS
---

# AWS Operations -- Staff Engineer Patterns

Production-ready patterns for monitoring, observability, CI/CD, cost optimization, and operational excellence on AWS.

## Table of Contents
1. [CloudWatch Monitoring](#cloudwatch-monitoring)
2. [X-Ray Distributed Tracing](#x-ray-distributed-tracing)
3. [CloudFormation & CDK Pipelines](#cloudformation--cdk-pipelines)
4. [CI/CD with GitHub Actions](#cicd-with-github-actions)
5. [Cost Optimization & FinOps](#cost-optimization--finops)
6. [Tagging Strategy](#tagging-strategy)
7. [Multi-Account Strategy](#multi-account-strategy)
8. [EventBridge Event-Driven Architecture](#eventbridge-event-driven-architecture)
9. [Step Functions Workflow Orchestration](#step-functions-workflow-orchestration)
10. [Terraform for AWS](#terraform-for-aws)
11. [Best Practices](#best-practices)
12. [Anti-Patterns](#anti-patterns)
13. [Common CLI Commands](#common-cli-commands)
14. [Sources & References](#sources--references)

---

## CloudWatch Monitoring

### Application Signals and SLOs

```typescript
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as appsignals from 'aws-cdk-lib/aws-applicationsignals';

const fn = new lambda.Function(this, 'Function', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
  tracing: lambda.Tracing.ACTIVE,
  insightsVersion: lambda.LambdaInsightsVersion.VERSION_1_0_229_0,
});

// Service Level Objective
const slo = new appsignals.CfnServiceLevelObjective(this, 'SLO', {
  name: 'api-availability',
  goal: {
    interval: {
      rollingInterval: {
        duration: 7,
        unit: 'DAY',
      },
    },
    attainmentGoal: 99.9,
  },
});
```

### CloudWatch Logs Insights

```typescript
import * as logs from 'aws-cdk-lib/aws-logs';

const logGroup = new logs.LogGroup(this, 'AppLogs', {
  logGroupName: '/aws/lambda/my-function',
  retention: logs.RetentionDays.ONE_WEEK,
});

const queryDefinition = new logs.QueryDefinition(this, 'ErrorQuery', {
  queryDefinitionName: 'lambda-errors',
  queryString: new logs.QueryString({
    fields: ['@timestamp', '@message', 'level', 'error'],
    filter: 'level = "ERROR"',
    sort: '@timestamp desc',
  }),
  logGroups: [logGroup],
});
```

### CloudWatch Synthetics Canaries

```typescript
import * as synthetics from 'aws-cdk-lib/aws-synthetics';

const canary = new synthetics.Canary(this, 'ApiCanary', {
  canaryName: 'api-availability',
  schedule: synthetics.Schedule.rate(cdk.Duration.minutes(5)),
  test: synthetics.Test.custom({
    code: synthetics.Code.fromAsset('canary'),
    handler: 'index.handler',
  }),
  runtime: synthetics.Runtime.SYNTHETICS_NODEJS_PUPPETEER_7_0,
  environmentVariables: {
    API_ENDPOINT: 'https://api.example.com',
  },
  successRetentionPeriod: cdk.Duration.days(2),
  failureRetentionPeriod: cdk.Duration.days(7),
});
```

```typescript
// canary/index.ts
const synthetics = require('Synthetics');
const https = require('https');

const apiCanary = async function () {
  const endpoint = process.env.API_ENDPOINT;

  const result = await new Promise((resolve, reject) => {
    https.get(`${endpoint}/health`, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          resolve({ statusCode: 200, body: data });
        } else {
          reject(new Error(`Status code: ${res.statusCode}`));
        }
      });
    }).on('error', reject);
  });

  return result;
};

exports.handler = async () => {
  return await synthetics.executeHttpStep('Verify API', apiCanary);
};
```

---

## X-Ray Distributed Tracing

### X-Ray with AWS SDK Instrumentation

```typescript
// Lambda code with X-Ray instrumentation
import { captureAWS } from 'aws-xray-sdk-core';
import AWS from 'aws-sdk';

// Wrap AWS SDK with X-Ray
const dynamodb = captureAWS(new AWS.DynamoDB.DocumentClient());

export async function handler(event: any) {
  const segment = captureAWS.getSegment();
  const subsegment = segment.addNewSubsegment('custom-operation');

  try {
    const result = await dynamodb.get({
      TableName: 'MyTable',
      Key: { id: event.id },
    }).promise();

    subsegment.close();
    return result;
  } catch (error) {
    subsegment.addError(error);
    subsegment.close();
    throw error;
  }
}
```

```typescript
// CDK: Enable X-Ray on Lambda
const fn = new lambda.Function(this, 'Function', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
  tracing: lambda.Tracing.ACTIVE,
});
```

---

## CloudFormation & CDK Pipelines

### Self-Mutating CDK Pipeline

```typescript
import * as pipelines from 'aws-cdk-lib/pipelines';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';

export class PipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const repo = codecommit.Repository.fromRepositoryName(
      this, 'Repo', 'my-app-repo'
    );

    const pipeline = new pipelines.CodePipeline(this, 'Pipeline', {
      pipelineName: 'MyAppPipeline',
      synth: new pipelines.ShellStep('Synth', {
        input: pipelines.CodePipelineSource.codeCommit(repo, 'main'),
        commands: ['npm ci', 'npm run build', 'npx cdk synth'],
      }),
      selfMutation: true,
      dockerEnabledForSynth: true,
    });

    // Add deployment stages
    const devStage = new AppStage(this, 'Dev', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'dev',
    });

    const prodStage = new AppStage(this, 'Prod', {
      env: { account: '987654321098', region: 'us-east-1' },
      stage: 'prod',
    });

    pipeline.addStage(devStage);

    // Manual approval before prod
    pipeline.addStage(prodStage, {
      pre: [new pipelines.ManualApprovalStep('PromoteToProd')],
      post: [
        new pipelines.ShellStep('IntegrationTests', {
          commands: ['npm run test:integration'],
        }),
      ],
    });
  }
}
```

---

## CI/CD with GitHub Actions

### GitHub Actions with OIDC for AWS

```yaml
# .github/workflows/deploy.yml
name: Deploy to AWS
on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsDeployRole
          aws-region: us-east-1

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: CDK Deploy
        run: |
          npm run cdk synth
          npm run cdk deploy -- --require-approval never
```

---

## Cost Optimization & FinOps

### Compute Savings Plans

```typescript
import * as savingsplans from 'aws-cdk-lib/aws-savingsplans';

const plan = new savingsplans.CfnSavingsPlan(this, 'ComputeSavingsPlan', {
  savingsPlanType: 'Compute',
  commitment: 100, // $100/hour commitment
  upfrontPaymentAmount: 0,
  term: '1yr',
  paymentOption: 'No Upfront',
});
```

### Budget Alerts

```typescript
import * as budgets from 'aws-cdk-lib/aws-budgets';

const budget = new budgets.CfnBudget(this, 'MonthlyBudget', {
  budget: {
    budgetName: 'monthly-budget',
    budgetType: 'COST',
    timeUnit: 'MONTHLY',
    budgetLimit: { amount: 1000, unit: 'USD' },
    costFilters: {
      TagKeyValue: ['user:Project$web-app'],
    },
  },
  notificationsWithSubscribers: [
    {
      notification: {
        notificationType: 'ACTUAL',
        comparisonOperator: 'GREATER_THAN',
        threshold: 80,
        thresholdType: 'PERCENTAGE',
      },
      subscribers: [
        { subscriptionType: 'EMAIL', address: 'team@example.com' },
      ],
    },
  ],
});
```

---

## Tagging Strategy

### Cost Allocation Tags with CDK

```typescript
import * as cdk from 'aws-cdk-lib';

export class MyStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Your resources here...

    // Apply cost allocation tags
    cdk.Tags.of(this).add('CostCenter', 'engineering');
    cdk.Tags.of(this).add('Project', 'web-app');
    cdk.Tags.of(this).add('Environment', 'production');
    cdk.Tags.of(this).add('Owner', 'platform-team');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}
```

### CDK Aspects for Tag Enforcement

```typescript
import * as cdk from 'aws-cdk-lib';
import { IConstruct } from 'constructs';

export class StandardTags implements cdk.IAspect {
  constructor(private readonly tags: Record<string, string>) {}

  public visit(node: IConstruct): void {
    if (cdk.TagManager.isTaggable(node)) {
      Object.entries(this.tags).forEach(([key, value]) => {
        cdk.Tags.of(node).add(key, value);
      });
    }
  }
}

// Apply to entire app
cdk.Aspects.of(app).add(new StandardTags({
  Environment: 'production',
  ManagedBy: 'CDK',
  CostCenter: 'engineering',
}));
```

---

## Multi-Account Strategy

### AWS Organizations with CDK

```typescript
// Landing Zone pattern: separate accounts for workloads
// - Management account: Organizations, billing, CloudTrail
// - Security account: GuardDuty, Config, SecurityHub
// - Log Archive account: centralized logging
// - Shared Services: DNS, Active Directory, CI/CD
// - Dev/Staging/Prod workload accounts

// Cross-account deployment with CDK
const devStage = new AppStage(this, 'Dev', {
  env: { account: '111111111111', region: 'us-east-1' },
});

const prodStage = new AppStage(this, 'Prod', {
  env: { account: '222222222222', region: 'us-east-1' },
});

// Centralized logging with cross-account access
const logBucket = new s3.Bucket(this, 'CentralLogs', {
  bucketName: 'central-logs-bucket',
  encryption: s3.BucketEncryption.S3_MANAGED,
  lifecycleRules: [
    {
      transitions: [
        { storageClass: s3.StorageClass.GLACIER, transitionAfter: cdk.Duration.days(90) },
      ],
    },
  ],
});

// Allow other accounts to write logs
logBucket.addToResourcePolicy(new iam.PolicyStatement({
  actions: ['s3:PutObject'],
  resources: [`${logBucket.bucketArn}/*`],
  principals: [
    new iam.AccountPrincipal('111111111111'),
    new iam.AccountPrincipal('222222222222'),
  ],
}));
```

---

## EventBridge Event-Driven Architecture

### EventBridge with Custom Event Bus

```typescript
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';

const eventBus = new events.EventBus(this, 'AppEventBus', {
  eventBusName: 'app-events',
});

const orderHandler = new lambda.Function(this, 'OrderHandler', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
});

const rule = new events.Rule(this, 'OrderCreatedRule', {
  eventBus,
  eventPattern: {
    source: ['app.orders'],
    detailType: ['OrderCreated'],
    detail: {
      status: ['pending', 'confirmed'],
      total: [{ numeric: ['>', 100] }],
    },
  },
});

rule.addTarget(new targets.LambdaFunction(orderHandler));
```

### Publishing Events

```typescript
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';

const eventBridge = new EventBridgeClient({});

export async function publishOrderCreatedEvent(order: any) {
  await eventBridge.send(
    new PutEventsCommand({
      Entries: [
        {
          EventBusName: 'app-events',
          Source: 'app.orders',
          DetailType: 'OrderCreated',
          Detail: JSON.stringify({
            orderId: order.id,
            userId: order.userId,
            total: order.total,
            status: 'pending',
            timestamp: new Date().toISOString(),
          }),
        },
      ],
    })
  );
}
```

---

## Step Functions Workflow Orchestration

### State Machine with Error Handling

```typescript
import * as sfn from 'aws-cdk-lib/aws-stepfunctions';
import * as tasks from 'aws-cdk-lib/aws-stepfunctions-tasks';

const validateTask = new tasks.LambdaInvoke(this, 'Validate Order', {
  lambdaFunction: validateOrder,
  outputPath: '$.Payload',
  retryOnServiceExceptions: true,
});

const paymentTask = new tasks.LambdaInvoke(this, 'Process Payment', {
  lambdaFunction: processPayment,
  outputPath: '$.Payload',
});

// Retry configuration
paymentTask.addRetry({
  errors: ['States.TaskFailed'],
  interval: cdk.Duration.seconds(2),
  maxAttempts: 3,
  backoffRate: 2,
  jitterStrategy: sfn.JitterType.FULL,
});

// Catch errors and compensate
paymentTask.addCatch(compensatePayment, {
  errors: ['PaymentError'],
  resultPath: '$.error',
});

const definition = validateTask
  .next(paymentTask)
  .next(notifyTask);

const stateMachine = new sfn.StateMachine(this, 'OrderWorkflow', {
  definition,
  timeout: cdk.Duration.minutes(5),
  tracingEnabled: true,
  stateMachineType: sfn.StateMachineType.EXPRESS,
});
```

---

## Terraform for AWS

### State Management with S3 Backend

```hcl
# backend.tf
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "Terraform"
      Project     = "my-app"
    }
  }
}
```

### Reusable Module Pattern

```hcl
# modules/vpc/main.tf
variable "name" {
  description = "VPC name"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.name
  }
}

output "vpc_id" {
  value = aws_vpc.this.id
}
```

```hcl
# environments/prod/main.tf
module "vpc" {
  source = "../../modules/vpc"

  name = "prod-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

---

## Best Practices

1. **Enable CloudTrail** in all regions -- essential for audit, compliance, and incident response
2. **Set up budget alerts** before costs spiral -- 50%, 80%, 100% thresholds with email notifications
3. **Use Savings Plans** over Reserved Instances -- more flexible, applies across compute services
4. **Implement tagging from day one** -- at minimum: Environment, Project, Owner, CostCenter
5. **Use CDK Pipelines** for self-mutating CI/CD -- pipeline updates itself when you push code
6. **Enable X-Ray tracing** on all Lambda functions and API Gateway -- minimal overhead, high value
7. **Use multi-account strategy** -- separate dev/staging/prod for blast radius containment
8. **Monitor SLOs, not just metrics** -- CloudWatch Application Signals for service-level objectives
9. **Automate everything** -- ClickOps is a bug, IaC is the fix
10. **Use OIDC for CI/CD** -- no long-lived credentials in GitHub Actions or CI systems

---

## Anti-Patterns

1. **ClickOps in production** -- all infrastructure changes must go through IaC pipelines
2. **No budget alerts** -- unmonitored costs can spiral quickly in AWS
3. **Monolithic CloudFormation stacks** -- split into smaller, focused stacks with clear dependencies
4. **Skipping staging deployments** -- always deploy to staging before production
5. **Not using CDK constructs** -- raw CloudFormation templates are verbose and error-prone
6. **Ignoring CloudWatch alarms** -- configure actionable alerts, not noise
7. **Single-account for everything** -- workload isolation requires separate accounts
8. **Manual deployments** -- automate CI/CD with approval gates for production

---

## Common CLI Commands

```bash
# CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=my-function \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 --statistics Sum

# Logs
aws logs tail /aws/lambda/my-function --follow --since 1h
aws logs filter-log-events \
  --log-group-name /ecs/my-app \
  --filter-pattern "ERROR"

# CDK
cdk init app --language typescript
cdk bootstrap aws://ACCOUNT/REGION
cdk synth
cdk diff
cdk deploy --all --require-approval never
cdk watch

# Cost Explorer
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Project

# Step Functions
aws stepfunctions start-execution \
  --state-machine-arn STATE_MACHINE_ARN \
  --input '{"orderId": "123"}'

# EventBridge
aws events put-events --entries file://events.json

# Organizations
aws organizations list-accounts --query "Accounts[*].{Name:Name,Id:Id}"
```

---

## Sources & References

- [CloudWatch Application Signals](https://www.terminalworks.com/blog/post/2025/04/28/application-monitoring-with-amazon-cloudwatch-application-signals)
- [AWS Cost Optimization 2025 Guide](https://www.prosperops.com/blog/aws-cost-optimization/)
- [CDK Pipelines GitHub Integration](https://github.com/cdklabs/cdk-pipelines-github)
- [GitHub Actions with AWS OIDC](https://aws.amazon.com/blogs/devops/integrating-with-github-actions-ci-cd-pipeline-to-deploy-a-web-app-to-amazon-ec2/)
- [EventBridge Event-Driven Architecture](https://dasroot.net/posts/2026/01/aws-eventbridge-event-driven-architecture/)
- [AWS Step Functions Best Practices](https://oneuptime.com/blog/post/2026-01-30-aws-step-functions-best-practices/view)
- [AWS CDK Constructs](https://docs.aws.amazon.com/cdk/v2/guide/constructs.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
