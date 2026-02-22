---
name: azure-compute
description: Production-grade Azure compute patterns -- App Service, AKS, Functions, Container Apps with Bicep modules
---

# Azure Compute -- Staff Engineer Patterns

Production-ready patterns for App Service, AKS, Azure Functions, and Container Apps on Azure using Bicep.

## Table of Contents
1. [Azure Container Apps](#azure-container-apps)
2. [Azure Kubernetes Service (AKS)](#azure-kubernetes-service-aks)
3. [Azure Functions](#azure-functions)
4. [App Service Advanced](#app-service-advanced)
5. [Bicep Patterns for Compute](#bicep-patterns-for-compute)
6. [Best Practices](#best-practices)
7. [Anti-Patterns](#anti-patterns)
8. [Common CLI Commands](#common-cli-commands)
9. [Sources & References](#sources--references)

---

## Azure Container Apps

### Dapr + KEDA Scaling Pattern

Event-driven microservices with state management and autoscaling.

```bicep
resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${appName}-${env}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    daprAIConnectionString: applicationInsights.properties.ConnectionString
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'D4'
        workloadProfileType: 'D4'
        minimumCount: 1
        maximumCount: 10
      }
    ]
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-order-processor-${env}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environment.id
    workloadProfileName: 'D4'
    configuration: {
      dapr: {
        enabled: true
        appId: 'order-processor'
        appProtocol: 'http'
        appPort: 3000
        enableApiLogging: true
      }
      secrets: [
        {
          name: 'servicebus-connection'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/servicebus-connection'
          identity: 'system'
        }
      ]
      ingress: {
        external: true
        targetPort: 3000
        transport: 'http'
        allowInsecure: false
        traffic: [
          { latestRevision: true, weight: 100 }
        ]
      }
    }
    template: {
      scale: {
        minReplicas: 1
        maxReplicas: 30
        rules: [
          {
            name: 'azure-servicebus-queue-rule'
            custom: {
              type: 'azure-servicebus'
              metadata: {
                queueName: 'orders'
                namespace: 'mycompany-servicebus'
                messageCount: '5'
              }
              auth: [
                { secretRef: 'servicebus-connection', triggerParameter: 'connection' }
              ]
            }
          }
          {
            name: 'http-rule'
            http: {
              metadata: { concurrentRequests: '50' }
            }
          }
        ]
      }
      containers: [
        {
          name: 'order-processor'
          image: 'myregistry.azurecr.io/order-processor:${imageTag}'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/health', port: 3000 }
              initialDelaySeconds: 15
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: { path: '/ready', port: 3000 }
              initialDelaySeconds: 10
              periodSeconds: 5
            }
          ]
        }
      ]
    }
  }
}
```

### Container Apps Jobs for Batch Processing

```bicep
resource containerJob 'Microsoft.App/jobs@2024-03-01' = {
  name: 'job-data-processor-${env}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: environment.id
    configuration: {
      triggerType: 'Schedule'
      scheduleTriggerConfig: {
        cronExpression: '0 2 * * *'
        parallelism: 5
        replicaCompletionCount: 1
      }
      replicaTimeout: 1800
      replicaRetryLimit: 3
    }
    template: {
      containers: [
        {
          name: 'batch-processor'
          image: 'myregistry.azurecr.io/batch-processor:latest'
          resources: {
            cpu: json('2.0')
            memory: '4Gi'
          }
        }
      ]
    }
  }
}
```

---

## Azure Kubernetes Service (AKS)

### Advanced AKS with KEDA + Workload Identity + GitOps

```bicep
resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: 'aks-${appName}-${env}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: 'aks-${appName}-${env}'
    kubernetesVersion: '1.29.2'
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 3
        vmSize: 'Standard_D4s_v5'
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        enableAutoScaling: true
        minCount: 3
        maxCount: 6
        vnetSubnetID: aksSubnetId
        nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
      }
      {
        name: 'workerpool'
        count: 3
        vmSize: 'Standard_D8s_v5'
        mode: 'User'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        enableAutoScaling: true
        minCount: 3
        maxCount: 20
        vnetSubnetID: aksSubnetId
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
      outboundType: 'userDefinedRouting'
      loadBalancerSku: 'standard'
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: adminGroupIds
    }
    securityProfile: {
      workloadIdentity: { enabled: true }
      imageCleaner: { enabled: true, intervalHours: 24 }
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
        securityMonitoring: { enabled: true }
      }
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
      azurepolicy: { enabled: true }
      omsagent: {
        enabled: true
        config: { logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId }
      }
    }
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
      nodeOSUpgradeChannel: 'NodeImage'
    }
    azureMonitorProfile: {
      metrics: { enabled: true }
      containerInsights: {
        enabled: true
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
      }
    }
  }
}

// Flux GitOps Configuration
resource fluxConfig 'Microsoft.KubernetesConfiguration/fluxConfigurations@2023-05-01' = {
  scope: aks
  name: 'app-gitops'
  properties: {
    scope: 'cluster'
    namespace: 'flux-system'
    sourceKind: 'GitRepository'
    gitRepository: {
      url: 'https://github.com/myorg/k8s-manifests'
      repositoryRef: { branch: 'main' }
      syncIntervalInSeconds: 60
    }
    kustomizations: {
      infra: {
        path: './infrastructure'
        syncIntervalInSeconds: 300
        prune: true
      }
      apps: {
        path: './apps/${env}'
        syncIntervalInSeconds: 300
        prune: true
        dependsOn: ['infra']
      }
    }
  }
}
```

### Workload Identity Kubernetes Manifest

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-processor
  namespace: production
  annotations:
    azure.workload.identity/client-id: "12345678-1234-1234-1234-123456789abc"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-processor
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: order-processor
  template:
    metadata:
      labels:
        app: order-processor
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: order-processor
      containers:
      - name: app
        image: myregistry.azurecr.io/order-processor:latest
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: order-processor-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: order-processor
  minReplicaCount: 3
  maxReplicaCount: 30
  triggers:
  - type: azure-servicebus
    metadata:
      queueName: orders
      namespace: mycompany-servicebus
      messageCount: "5"
    authenticationRef:
      name: servicebus-trigger-auth
```

---

## Azure Functions

### Durable Functions -- Isolated Worker Model

```csharp
[Function(nameof(OrderProcessingOrchestrator))]
public async Task<OrderResult> OrderProcessingOrchestrator(
    [OrchestrationTrigger] TaskOrchestrationContext context)
{
    var orderId = context.GetInput<string>();

    // Fan-out: Validate inventory, check payment, reserve shipping
    var tasks = new List<Task>
    {
        context.CallActivityAsync<bool>("ValidateInventory", orderId),
        context.CallActivityAsync<bool>("CheckPayment", orderId),
        context.CallActivityAsync<bool>("ReserveShipping", orderId)
    };

    await Task.WhenAll(tasks);

    if (!await tasks[0] || !await tasks[1] || !await tasks[2])
    {
        await context.CallActivityAsync("CancelOrder", orderId);
        return new OrderResult { Success = false };
    }

    // Wait for external event with timeout
    using var cts = new CancellationTokenSource();
    var timeoutTask = context.CreateTimer(
        context.CurrentUtcDateTime.AddHours(24), cts.Token);
    var confirmTask = context.WaitForExternalEvent<string>(
        "WarehouseConfirmation");

    var winner = await Task.WhenAny(confirmTask, timeoutTask);

    if (winner == timeoutTask)
    {
        await context.CallActivityAsync("CancelOrder", orderId);
        return new OrderResult { Success = false, Reason = "Timeout" };
    }

    cts.Cancel();
    await context.CallActivityAsync("CompleteOrder", orderId);
    return new OrderResult { Success = true };
}
```

### host.json Configuration

```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "maxTelemetryItemsPerSecond": 20,
        "excludedTypes": "Request"
      }
    }
  },
  "extensions": {
    "durableTask": {
      "hubName": "OrderProcessing",
      "storageProvider": {
        "connectionStringName": "AzureWebJobsStorage",
        "partitionCount": 4
      },
      "maxConcurrentActivityFunctions": 10,
      "maxConcurrentOrchestratorFunctions": 10
    }
  },
  "concurrency": {
    "dynamicConcurrencyEnabled": true,
    "maximumFunctionConcurrency": 500
  }
}
```

### Advanced Bindings with Cosmos DB and Service Bus

```csharp
[Function("CreateOrder")]
[CosmosDBOutput("%CosmosDatabase%", "%CosmosContainer%",
    Connection = "CosmosConnection",
    CreateIfNotExists = true,
    PartitionKey = "/customerId")]
[ServiceBusOutput("%OrderQueue%", Connection = "ServiceBusConnection")]
public async Task<MultiResponse> CreateOrder(
    [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
{
    var order = await req.ReadFromJsonAsync<Order>();

    return new MultiResponse
    {
        CosmosDocument = order,
        ServiceBusMessage = new ServiceBusMessage(
            JsonSerializer.Serialize(order))
        {
            MessageId = order.Id,
            PartitionKey = order.CustomerId
        },
        HttpResponse = req.CreateResponse(HttpStatusCode.Created)
    };
}
```

---

## App Service Advanced

### Deployment Slots with Auto-Scaling

```bicep
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'plan-${appName}-${env}'
  location: location
  sku: {
    name: 'P1v3'
    tier: 'PremiumV3'
    capacity: 3
  }
  kind: 'linux'
  properties: {
    reserved: true
    zoneRedundant: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${appName}-${env}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: appSubnetId
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      alwaysOn: true
      http20Enabled: true
      minTlsVersion: '1.3'
      healthCheckPath: '/health'
      autoHealEnabled: true
      autoHealRules: {
        triggers: {
          statusCodes: [
            { status: 500, subStatus: 0, count: 10, timeInterval: '00:01:00' }
          ]
        }
        actions: {
          actionType: 'Recycle'
          minProcessExecutionTime: '00:01:00'
        }
      }
    }
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
  }
}

// Staging slot for blue-green deployments
resource stagingSlot 'Microsoft.Web/sites/slots@2023-01-01' = {
  parent: webApp
  name: 'staging'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${managedIdentity.id}': {} }
  }
  properties: {
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: appSubnetId
    siteConfig: webApp.properties.siteConfig
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
  }
}

// Auto-scaling
resource autoScaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'autoscale-${appServicePlan.name}'
  location: location
  properties: {
    targetResourceUri: appServicePlan.id
    enabled: true
    profiles: [
      {
        name: 'Default'
        capacity: { minimum: '3', maximum: '10', default: '3' }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 75
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}
```

---

## Bicep Patterns for Compute

### Modular Architecture

```bicep
// main.bicep - Orchestrator
targetScope = 'subscription'

param environment string
param location string = 'eastus'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-app-${environment}'
  location: location
}

module network './modules/network.bicep' = {
  scope: rg
  name: 'networkDeployment'
  params: {
    environment: environment
    vnetAddressPrefix: '10.0.0.0/16'
  }
}

module aks './modules/aks.bicep' = {
  scope: rg
  name: 'aksDeployment'
  params: {
    environment: environment
    subnetId: network.outputs.aksSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

module monitoring './modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoringDeployment'
  params: { environment: environment }
}
```

### Module Registry with Private ACR

```json
// bicepconfig.json
{
  "moduleAliases": {
    "br": {
      "CompanyModules": {
        "registry": "mycompany.azurecr.io",
        "modulePath": "bicep/modules"
      }
    }
  },
  "analyzers": {
    "core": {
      "enabled": true,
      "rules": {
        "no-hardcoded-env-urls": { "level": "error" },
        "use-stable-vm-image": { "level": "error" },
        "no-unused-params": { "level": "warning" }
      }
    }
  }
}
```

---

## Best Practices

1. **Use Container Apps** for serverless containers -- simpler than AKS for most workloads
2. **Use AKS with Workload Identity** -- never store credentials in pods or config maps
3. **Enable GitOps with Flux** on AKS -- declarative deployments from git repositories
4. **Use Durable Functions** for long-running workflows -- built-in retry, fan-out, and compensation
5. **Enable zone redundancy** on App Service plans -- ensures HA across availability zones
6. **Use deployment slots** for blue-green deployments -- swap staging to production with zero downtime
7. **Enable auto-heal** on App Service -- automatic recycling on high error rates
8. **Use KEDA** for event-driven autoscaling -- scales to zero and responds to queue depth
9. **Separate system and user node pools** in AKS -- isolate critical system pods
10. **Use AzureLinux OS** for AKS nodes -- smaller attack surface, faster boot times

---

## Anti-Patterns

1. **Running AKS without network policies** -- always enable Azure CNI with network policy
2. **Using in-process Azure Functions model** -- migrate to isolated worker model (required by 2026)
3. **Deploying to App Service without slots** -- always use staging slots for production
4. **Over-provisioning AKS node pools** -- use cluster autoscaler with proper min/max bounds
5. **Skipping health checks** on Container Apps and App Service -- required for reliable scaling
6. **Using shared App Service plans** for production and dev -- isolate environments
7. **Not enabling Container Insights** on AKS -- critical for cluster monitoring
8. **Deploying Container Apps without Dapr** for microservices -- Dapr simplifies service-to-service calls

---

## Common CLI Commands

```bash
# AKS
az aks get-credentials --resource-group rg-myapp-prod --name aks-myapp-prod
az aks update --resource-group rg-myapp-prod --name aks-myapp-prod \
  --enable-keda --enable-workload-identity
kubectl get nodes
kubectl get pods -A

# Container Apps
az containerapp up --name my-app --resource-group rg-myapp-prod \
  --source . --ingress external --target-port 3000
az containerapp logs show --name my-app --resource-group rg-myapp-prod --follow

# App Service
az webapp deployment slot create --name app-myapp-prod \
  --resource-group rg-myapp-prod --slot staging
az webapp deployment slot swap --name app-myapp-prod \
  --resource-group rg-myapp-prod --slot staging --target-slot production

# Azure Functions
func init MyProject --worker-runtime dotnet-isolated
func new --name MyFunction --template "HTTP trigger"
func start
func azure functionapp publish my-function-app

# Bicep
az bicep build --file main.bicep
az deployment group what-if --resource-group rg-myapp-prod \
  --template-file main.bicep --parameters @params.prod.json
az deployment group create --resource-group rg-myapp-prod \
  --template-file main.bicep --parameters @params.prod.json
```

---

## Sources & References

- [Azure Container Apps: Complete 2025 Guide](https://kunaldaskd.medium.com/azure-container-apps-your-complete-2025-guide-to-serverless-container-deployment-de6ef2ef1f1a)
- [Scale Dapr Applications with KEDA Scalers](https://learn.microsoft.com/en-us/azure/container-apps/dapr-keda-scaling)
- [Advanced AKS Microservices Architecture](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks-microservices/aks-microservices-advanced)
- [GitOps with Flux on AKS](https://medium.com/@arnaud.tincelin/gitops-with-flux-on-aks-connect-to-git-repo-with-workload-identity-bc867f01d626)
- [Azure Functions in 2025](https://belitsoft.com/azure-functions)
- [Durable Functions in .NET Isolated Worker](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-functions-dotnet-isolated-overview)
- [Azure App Service Deployment Slots](https://learn.microsoft.com/en-us/azure/app-service/deploy-staging-slots)
- [Bicep Modules](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules)
- [10 Advanced Tips for Better Bicep Deployments](https://azuretechinsider.com/advanced-tips-for-better-bicep-deployments/)
