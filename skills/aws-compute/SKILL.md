---
name: aws-compute
description: Production-grade AWS compute patterns -- ECS Fargate, Lambda, EC2 ASG, and CDK constructs for compute workloads
---

# AWS Compute -- Staff Engineer Patterns

Production-ready patterns for ECS Fargate, Lambda, and EC2 compute workloads on AWS using CDK v2.

## Table of Contents
1. [ECS Fargate Advanced Patterns](#ecs-fargate-advanced-patterns)
2. [Lambda Advanced Patterns](#lambda-advanced-patterns)
3. [EC2 and Auto Scaling Groups](#ec2-and-auto-scaling-groups)
4. [CDK Constructs for Compute](#cdk-constructs-for-compute)
5. [Best Practices](#best-practices)
6. [Anti-Patterns](#anti-patterns)
7. [Common CLI Commands](#common-cli-commands)
8. [Sources & References](#sources--references)

---

## ECS Fargate Advanced Patterns

### L3 Construct: Web Application with ECS Fargate + ALB

```typescript
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export interface FargateWebAppProps {
  vpc?: ec2.IVpc;
  stage: 'dev' | 'staging' | 'prod';
  desiredCount?: number;
  cpu?: number;
  memoryLimitMiB?: number;
}

export class FargateWebApp extends Construct {
  public readonly service: ecs.FargateService;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;

  constructor(scope: Construct, id: string, props: FargateWebAppProps) {
    super(scope, id);

    const vpc = props.vpc ?? new ec2.Vpc(this, 'Vpc', {
      maxAzs: 3,
      natGateways: props.stage === 'prod' ? 3 : 1,
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

    // ECS Cluster with Container Insights
    const cluster = new ecs.Cluster(this, 'Cluster', {
      vpc,
      containerInsights: true,
      enableFargateCapacityProviders: true,
    });

    // Task Definition with Graviton2 for cost savings
    const taskDef = new ecs.FargateTaskDefinition(this, 'TaskDef', {
      memoryLimitMiB: props.memoryLimitMiB ?? 1024,
      cpu: props.cpu ?? 512,
      runtimePlatform: {
        cpuArchitecture: ecs.CpuArchitecture.ARM64,
        operatingSystemFamily: ecs.OperatingSystemFamily.LINUX,
      },
    });

    const container = taskDef.addContainer('App', {
      image: ecs.ContainerImage.fromAsset('.', {
        platform: cdk.aws_ecr_assets.Platform.LINUX_ARM64,
      }),
      portMappings: [{ containerPort: 3000, protocol: ecs.Protocol.TCP }],
      environment: {
        NODE_ENV: 'production',
        STAGE: props.stage,
      },
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: `${props.stage}-app`,
        logRetention: logs.RetentionDays.ONE_WEEK,
      }),
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3000/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    // Fargate Service with capacity provider strategies
    this.service = new ecs.FargateService(this, 'Service', {
      cluster,
      taskDefinition: taskDef,
      desiredCount: props.desiredCount ?? 2,
      capacityProviderStrategies: [
        {
          capacityProvider: 'FARGATE_SPOT',
          weight: props.stage === 'prod' ? 0 : 1,
        },
        {
          capacityProvider: 'FARGATE',
          weight: 1,
          base: props.stage === 'prod' ? 2 : 0,
        },
      ],
      circuitBreaker: { rollback: true },
      enableECSManagedTags: true,
      enableExecuteCommand: true,
      healthCheckGracePeriod: cdk.Duration.seconds(60),
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
    });

    // Auto Scaling
    const scaling = this.service.autoScaleTaskCount({
      minCapacity: props.stage === 'prod' ? 2 : 1,
      maxCapacity: props.stage === 'prod' ? 10 : 3,
    });

    scaling.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.seconds(60),
      scaleOutCooldown: cdk.Duration.seconds(60),
    });

    scaling.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 80,
    });

    // Application Load Balancer
    this.loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'ALB', {
      vpc,
      internetFacing: true,
      dropInvalidHeaderFields: true,
      http2Enabled: true,
    });

    const listener = this.loadBalancer.addListener('Listener', {
      port: 443,
      protocol: elbv2.ApplicationProtocol.HTTPS,
      sslPolicy: elbv2.SslPolicy.TLS12_EXT,
    });

    listener.addTargets('Target', {
      port: 3000,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [this.service],
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(10),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        healthyHttpCodes: '200',
      },
      deregistrationDelay: cdk.Duration.seconds(30),
      slowStart: cdk.Duration.seconds(30),
    });

    this.service.connections.allowFrom(
      this.loadBalancer,
      ec2.Port.tcp(3000),
      'Allow traffic from ALB'
    );
  }
}
```

### ECS Service Connect for Service Mesh

```typescript
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';

const namespace = new servicediscovery.CloudMapNamespace(this, 'Namespace', {
  name: 'my-app.local',
  type: servicediscovery.NamespaceType.HTTP,
});

const backendService = new ecs.FargateService(this, 'BackendService', {
  cluster,
  taskDefinition: backendTaskDef,
  serviceConnectConfiguration: {
    namespace: namespace.namespaceName,
    services: [
      {
        portMappingName: 'api',
        dnsName: 'backend',
        port: 8080,
        discoveryName: 'backend',
      },
    ],
  },
});

// Frontend can call backend at http://backend:8080
const frontendService = new ecs.FargateService(this, 'FrontendService', {
  cluster,
  taskDefinition: frontendTaskDef,
  serviceConnectConfiguration: {
    namespace: namespace.namespaceName,
    services: [
      {
        portMappingName: 'http',
        dnsName: 'frontend',
        port: 3000,
      },
    ],
  },
});
```

### Task Placement Strategies (EC2 Launch Type)

```typescript
const service = new ecs.Ec2Service(this, 'Service', {
  cluster,
  taskDefinition,
  placementStrategies: [
    ecs.PlacementStrategy.spreadAcross(ecs.BuiltInAttributes.AVAILABILITY_ZONE),
    ecs.PlacementStrategy.packedBy(ecs.BinPackResource.MEMORY),
  ],
  placementConstraints: [
    ecs.PlacementConstraint.memberOf('attribute:ecs.instance-type =~ t3.*'),
  ],
});
```

### ECS Exec for Debugging

```bash
# Execute command in running container
aws ecs execute-command \
  --cluster my-cluster \
  --task task-id \
  --container app \
  --interactive \
  --command "/bin/bash"

# Tail logs in real-time
aws logs tail /ecs/production-app --follow --since 1h
```

---

## Lambda Advanced Patterns

### Lambda with SnapStart

```typescript
import * as lambda from 'aws-cdk-lib/aws-lambda';

const fn = new lambda.Function(this, 'MyFunction', {
  runtime: lambda.Runtime.PYTHON_3_12,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
  snapStart: lambda.SnapStartConf.ON_PUBLISHED_VERSIONS,
  memorySize: 1024,
  timeout: cdk.Duration.seconds(30),
});

const version = fn.currentVersion;
```

```python
# lambda/index.py - Python Lambda with SnapStart awareness
import os
import boto3

initialization_type = os.environ.get('AWS_LAMBDA_INITIALIZATION_TYPE')

if initialization_type == 'snap-start':
    print('Restored from SnapStart snapshot')

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('MyTable')

def handler(event, context):
    response = table.get_item(Key={'id': event['id']})
    return {
        'statusCode': 200,
        'body': response['Item']
    }
```

### Lambda Web Adapter Pattern

Run standard web frameworks (Express, FastAPI) on Lambda without code changes.

```dockerfile
FROM public.ecr.aws/lambda/nodejs:20

COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.8.4 /lambda-adapter /opt/extensions/lambda-adapter

COPY package*.json ./
RUN npm ci --production
COPY . .

ENV PORT=3000
ENV AWS_LAMBDA_EXEC_WRAPPER=/opt/bootstrap

CMD ["node", "server.js"]
```

```typescript
// server.js - Regular Express app running on Lambda
import express from 'express';

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/api/users', async (req, res) => {
  res.json({ users: [] });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

### Lambda Powertools Pattern

```typescript
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { LambdaPowertoolsLayer } from 'cdk-aws-lambda-powertools-layer';

const powertoolsLayer = new LambdaPowertoolsLayer(this, 'PowertoolsLayer', {
  version: '2.40.0',
  includeExtras: true,
});

const fn = new lambda.Function(this, 'Function', {
  runtime: lambda.Runtime.PYTHON_3_12,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
  layers: [powertoolsLayer],
  environment: {
    POWERTOOLS_SERVICE_NAME: 'my-service',
    POWERTOOLS_METRICS_NAMESPACE: 'MyApp',
    LOG_LEVEL: 'INFO',
  },
});
```

```python
# lambda/index.py - Using Powertools
from aws_lambda_powertools import Logger, Tracer, Metrics
from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools.metrics import MetricUnit
from aws_lambda_powertools.event_handler import APIGatewayRestResolver

logger = Logger()
tracer = Tracer()
metrics = Metrics()
app = APIGatewayRestResolver()

@app.get("/users")
@tracer.capture_method
def get_users():
    logger.info("Fetching users")
    metrics.add_metric(name="UsersFetched", unit=MetricUnit.Count, value=1)
    return {"users": []}

@logger.inject_lambda_context
@tracer.capture_lambda_handler
@metrics.log_metrics(capture_cold_start_metric=True)
def handler(event: dict, context: LambdaContext) -> dict:
    return app.resolve(event, context)
```

### Lambda Reserved and Provisioned Concurrency

```typescript
// Reserve concurrency for critical functions
const criticalFn = new lambda.Function(this, 'CriticalFunction', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
  reservedConcurrentExecutions: 100,
});

// Provisioned concurrency for predictable latency
const version = criticalFn.currentVersion;
const alias = new lambda.Alias(this, 'Alias', {
  aliasName: 'prod',
  version,
  provisionedConcurrentExecutions: 10,
});
```

### Lambda Extensions

```typescript
const extension = new lambda.LayerVersion(this, 'MyExtension', {
  code: lambda.Code.fromAsset('extensions'),
  compatibleRuntimes: [lambda.Runtime.NODEJS_20_X],
  description: 'Custom extension for logging',
});

const fn = new lambda.Function(this, 'Function', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
  layers: [extension],
});
```

### SST v3 Serverless Stack Pattern

```typescript
// sst.config.ts
import { SSTConfig } from 'sst';
import { API } from './stacks/API';
import { Database } from './stacks/Database';

export default {
  config(_input) {
    return { name: 'my-app', region: 'us-east-1' };
  },
  stacks(app) {
    app.stack(Database).stack(API);
  },
} satisfies SSTConfig;
```

```typescript
// stacks/API.ts
import { StackContext, Api, use } from 'sst/constructs';
import { Database } from './Database';

export function API({ stack }: StackContext) {
  const db = use(Database);

  const api = new Api(stack, 'api', {
    defaults: {
      function: {
        bind: [db],
        runtime: 'nodejs20.x',
        timeout: 20,
        environment: { DATABASE_URL: db.url },
      },
    },
    routes: {
      'GET /todos': 'packages/functions/src/list.handler',
      'POST /todos': 'packages/functions/src/create.handler',
      'GET /todos/{id}': 'packages/functions/src/get.handler',
    },
  });

  stack.addOutputs({ ApiEndpoint: api.url });
  return api;
}
```

---

## EC2 and Auto Scaling Groups

### Mixed Instances with Spot for Cost Savings

```typescript
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

const asg = new autoscaling.AutoScalingGroup(this, 'ASG', {
  vpc,
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.MEDIUM),
  machineImage: ec2.MachineImage.latestAmazonLinux2023(),
  minCapacity: 2,
  maxCapacity: 10,
  spotPrice: '0.05',
  mixedInstancesPolicy: {
    instancesDistribution: {
      onDemandBaseCapacity: 2,
      onDemandPercentageAboveBaseCapacity: 20,
      spotAllocationStrategy: autoscaling.SpotAllocationStrategy.PRICE_CAPACITY_OPTIMIZED,
    },
    launchTemplate: {
      launchTemplateSpecification: { version: '$Latest' },
      overrides: [
        { instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.MEDIUM) },
        { instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM) },
        { instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3A, ec2.InstanceSize.MEDIUM) },
      ],
    },
  },
});
```

---

## CDK Constructs for Compute

### Using CDK Aspects for Governance

```typescript
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { IConstruct } from 'constructs';

// Enforce IMDSv2 on all EC2 instances
export class EnforceIMDSv2 implements cdk.IAspect {
  public visit(node: IConstruct): void {
    if (node instanceof ec2.CfnLaunchTemplate) {
      const metadata = node.launchTemplateData as ec2.CfnLaunchTemplate.LaunchTemplateDataProperty;
      if (!metadata.metadataOptions?.httpTokens ||
          metadata.metadataOptions.httpTokens !== 'required') {
        throw new Error(`Launch Template ${node.node.path} must require IMDSv2`);
      }
    }
  }
}

// Tag all resources with standard tags
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

// Apply aspects in stack
cdk.Aspects.of(this).add(new EnforceIMDSv2());
cdk.Aspects.of(this).add(new StandardTags({
  Environment: 'production',
  ManagedBy: 'CDK',
}));
```

---

## Best Practices

1. **Use Graviton2 (ARM64)** for ECS Fargate tasks -- 20% cheaper, 40% better price-performance
2. **Enable circuit breakers** on ECS services to auto-rollback failed deployments
3. **Use ECS Exec** for debugging instead of SSH -- no need to open ports or manage keys
4. **Use Fargate Spot** for non-production workloads -- up to 70% cheaper
5. **Right-size Lambda functions** -- use AWS Lambda Power Tuning to find optimal memory
6. **Use Lambda Powertools** for structured logging, tracing, and metrics from day one
7. **Set reserved concurrency** on critical Lambda functions to prevent throttling
8. **Use SnapStart** for Java/Python Lambda functions to reduce cold start latency
9. **Enable Container Insights** on ECS clusters for detailed monitoring
10. **Use capacity provider strategies** instead of specifying launch types directly

---

## Anti-Patterns

1. **Running compute without health checks** -- always define container and ALB health checks
2. **Using Lambda for long-running tasks** -- use Step Functions or ECS for workloads > 15 minutes
3. **Hardcoding instance types** -- use mixed instances policy for cost optimization and availability
4. **Skipping auto-scaling** -- always configure scaling policies, even conservative ones
5. **Using root credentials in containers** -- use IAM task roles with least-privilege policies
6. **Over-provisioning Lambda memory** -- profile and right-size using Power Tuning
7. **Not setting timeout on Lambda** -- default 3s timeout causes silent failures
8. **Using FARGATE_SPOT for production baseline** -- always have on-demand base capacity

---

## Common CLI Commands

```bash
# ECS
aws ecs list-clusters
aws ecs list-services --cluster my-cluster
aws ecs describe-services --cluster my-cluster --services my-service
aws ecs update-service --cluster my-cluster --service my-service --force-new-deployment
aws ecs execute-command --cluster my-cluster --task TASK_ID --container app --interactive --command "/bin/bash"

# Lambda
aws lambda invoke --function-name my-function output.json
aws lambda update-function-code --function-name my-function --zip-file fileb://function.zip
aws lambda publish-version --function-name my-function
aws lambda update-alias --function-name my-function --name prod --function-version 2

# CDK
cdk init app --language typescript
cdk bootstrap aws://ACCOUNT/REGION
cdk synth
cdk diff
cdk deploy --all --require-approval never
cdk watch
```

---

## Sources & References

- [AWS CDK Constructs](https://docs.aws.amazon.com/cdk/v2/guide/constructs.html)
- [ECS Fargate Capacity Providers](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-capacity-providers.html)
- [Code and YAML patterns for Amazon ECS](https://containersonaws.com/pattern/)
- [AWS Lambda SnapStart Guide](https://www.ravipatel.cloud/mastering-aws-lambda-snapstart)
- [Lambda Web Adapter GitHub](https://github.com/awslabs/aws-lambda-web-adapter)
- [SST v3 for Modern AWS Serverless](https://spin.atomicobject.com/sst-v3-for-aws-serverless/)
- [AWS CDK Construct Levels Guide](https://towardsthecloud.com/blog/aws-cdk-construct)
- [AWS Lambda Powertools](https://docs.powertools.aws.dev/lambda/python/latest/)
- [ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)
