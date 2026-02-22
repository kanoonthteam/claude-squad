---
name: azure-operations
description: Production-grade Azure operations -- App Insights, Azure Monitor, Log Analytics, DevOps Pipelines, GitHub Actions, Managed Identity, Key Vault, cost management, Terraform
---

# Azure Operations -- Staff Engineer Patterns

Production-ready patterns for monitoring, CI/CD pipelines, identity management, cost optimization, and Terraform on Azure.

## Table of Contents
1. [Azure Monitor & Application Insights](#azure-monitor--application-insights)
2. [Log Analytics & KQL Queries](#log-analytics--kql-queries)
3. [Azure DevOps Pipelines](#azure-devops-pipelines)
4. [GitHub Actions for Azure](#github-actions-for-azure)
5. [Managed Identity Patterns](#managed-identity-patterns)
6. [Key Vault Integration](#key-vault-integration)
7. [Cost Management](#cost-management)
8. [Security & Compliance](#security--compliance)
9. [Terraform for Azure](#terraform-for-azure)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)
12. [Common CLI Commands](#common-cli-commands)
13. [Sources & References](#sources--references)

---

## Azure Monitor & Application Insights

### Observability Infrastructure

```bicep
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${appName}-${env}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${appName}-${env}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
  }
}

// Alert for high error rate
resource errorRateAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-high-error-rate'
  location: location
  properties: {
    displayName: 'High Error Rate Alert'
    description: 'Alert when error rate exceeds 5% over 5 minutes'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [applicationInsights.id]
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: '''
requests
| where timestamp > ago(5m)
| summarize Total = count(), Failed = countif(success == false)
| extend ErrorRate = (Failed * 100.0) / Total
| where ErrorRate > 5
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: { actionGroups: [actionGroup.id] }
  }
}

// Alert for P95 latency
resource latencyAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-high-latency'
  location: location
  properties: {
    displayName: 'High P95 Latency Alert'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [applicationInsights.id]
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: '''
requests
| where timestamp > ago(15m)
| summarize P95 = percentile(duration, 95) by bin(timestamp, 5m)
| where P95 > 300
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: { actionGroups: [actionGroup.id] }
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-oncall'
  location: 'global'
  properties: {
    groupShortName: 'OnCall'
    enabled: true
    emailReceivers: [
      {
        name: 'Engineering Team'
        emailAddress: 'oncall@company.com'
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: [
      {
        name: 'PagerDuty'
        serviceUri: 'https://events.pagerduty.com/integration/.../enqueue'
        useCommonAlertSchema: true
      }
    ]
  }
}
```

---

## Log Analytics & KQL Queries

### Production KQL Queries

```kusto
// Real-time error tracking
exceptions
| where timestamp > ago(1h)
| summarize Count = count() by problemId, outerMessage
| order by Count desc
| take 20

// Distributed trace analysis
dependencies
| where timestamp > ago(1h) and success == false
| join kind=inner (requests) on operation_Id
| project
    timestamp,
    operation_Name,
    dependency_Name = name,
    dependency_Duration = duration,
    request_Duration = duration1,
    resultCode,
    cloud_RoleName
| order by timestamp desc

// SLI/SLO Monitoring
requests
| where timestamp > ago(7d)
| summarize
    TotalRequests = count(),
    SuccessRequests = countif(success == true),
    P50 = percentile(duration, 50),
    P95 = percentile(duration, 95),
    P99 = percentile(duration, 99)
    by bin(timestamp, 1h)
| extend
    Availability = (SuccessRequests * 100.0) / TotalRequests,
    SLO_Availability = 99.9,
    SLO_Latency_P95 = 300
| extend
    AvailabilityMet = Availability >= SLO_Availability,
    LatencyMet = P95 <= SLO_Latency_P95

// User journey analysis
pageViews
| where timestamp > ago(24h)
| summarize
    Sessions = dcount(session_Id),
    AvgDuration = avg(duration),
    BounceRate = countif(itemCount == 1) * 100.0 / count()
    by name
| order by Sessions desc
```

---

## Azure DevOps Pipelines

### Multi-Stage Pipeline with Templates

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include: [main, develop]
  paths:
    exclude: [docs/**, README.md]

variables:
  - template: variables/global.yml

stages:
  - stage: Build
    displayName: 'Build & Test'
    jobs:
      - template: templates/build-job.yml
        parameters:
          nodeVersion: '20.x'

  - stage: DeployDev
    displayName: 'Deploy to Dev'
    dependsOn: Build
    condition: succeeded()
    jobs:
      - template: templates/deploy-job.yml
        parameters:
          environment: 'dev'
          azureSubscription: 'Dev-ServiceConnection'

  - stage: DeployProduction
    displayName: 'Deploy to Production'
    dependsOn: DeployStaging
    condition: succeeded()
    jobs:
      - deployment: DeployProd
        environment: 'production'
        strategy:
          runOnce:
            deploy:
              steps:
                - template: templates/deploy-steps.yml
                  parameters:
                    environment: 'production'
                    deploymentSlot: 'staging'
            routeTraffic:
              steps:
                - task: AzureAppServiceManage@0
                  inputs:
                    azureSubscription: 'Prod-ServiceConnection'
                    Action: 'Swap Slots'
                    WebAppName: 'app-myapp-prod'
                    ResourceGroupName: 'rg-app-prod'
                    SourceSlot: 'staging'
```

### Reusable Template

```yaml
# templates/deploy-steps.yml
parameters:
  - name: environment
    type: string
  - name: deploymentSlot
    type: string
    default: ''

steps:
  - task: AzureCLI@2
    displayName: 'Deploy Infrastructure'
    inputs:
      azureSubscription: '${{ parameters.environment }}-ServiceConnection'
      scriptType: 'bash'
      scriptLocation: 'inlineScript'
      inlineScript: |
        az deployment group create \
          --resource-group rg-app-${{ parameters.environment }} \
          --template-file infrastructure/main.bicep \
          --parameters @infrastructure/params.${{ parameters.environment }}.json

  - task: AzureWebApp@1
    displayName: 'Deploy Application'
    inputs:
      azureSubscription: '${{ parameters.environment }}-ServiceConnection'
      appType: 'webAppLinux'
      appName: 'app-myapp-${{ parameters.environment }}'
      deployToSlotOrASE: ${{ ne(parameters.deploymentSlot, '') }}
      slotName: '${{ parameters.deploymentSlot }}'
      package: '$(Pipeline.Workspace)/drop/*.zip'
```

---

## GitHub Actions for Azure

### OIDC-Based Deployment

```yaml
# .github/workflows/terraform.yml
name: 'Terraform'
on:
  push:
    branches: [main]
  pull_request:

permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.8.0

      - name: Terraform Init
        run: terraform init
        working-directory: ./environments/prod

      - name: Terraform Plan
        run: terraform plan -out=tfplan
        working-directory: ./environments/prod

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve tfplan
        working-directory: ./environments/prod
```

---

## Managed Identity Patterns

### Cross-Subscription Access with User-Assigned Identity

```bicep
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-app-shared'
  location: location
}

// App Service uses managed identity
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-myapp-prod'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${managedIdentity.id}': {} }
  }
  properties: {
    siteConfig: {
      appSettings: [
        { name: 'AZURE_CLIENT_ID', value: managedIdentity.properties.clientId }
      ]
    }
  }
}

// Grant Key Vault access
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Storage access
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, managedIdentity.id, 'Storage Blob Data Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

### Application Code with Managed Identity

```typescript
import { DefaultAzureCredential } from '@azure/identity';
import { SecretClient } from '@azure/keyvault-secrets';
import { BlobServiceClient } from '@azure/storage-blob';

const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.AZURE_CLIENT_ID
});

// Access Key Vault
const secretClient = new SecretClient(
  'https://kv-shared-secrets.vault.azure.net', credential
);
const secret = await secretClient.getSecret('DatabasePassword');

// Access Storage
const blobServiceClient = new BlobServiceClient(
  'https://stshareddata.blob.core.windows.net', credential
);
```

---

## Key Vault Integration

### Key Vault with RBAC

```bicep
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${appName}-${env}'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'premium' }
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
  }
}
```

---

## Cost Management

### Budget Alerts with Bicep

```bicep
var commonTags = {
  Environment: env
  CostCenter: '1234'
  Owner: 'engineering@company.com'
  Project: appName
}

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'budget-${appName}-${env}'
  properties: {
    category: 'Cost'
    amount: 10000
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '2026-01-01'
      endDate: '2026-12-31'
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: ['rg-${appName}-${env}']
      }
    }
    notifications: {
      Actual_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: ['finance@company.com']
        thresholdType: 'Actual'
      }
      Forecasted_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: ['finance@company.com', 'engineering@company.com']
        thresholdType: 'Forecasted'
      }
    }
  }
}
```

### Cost Optimization Checklist

1. **Compute**: Use Reserved Instances (1-3yr) for steady-state, Spot VMs for batch, right-size VMs
2. **Storage**: Implement lifecycle policies, use appropriate blob tiers, archive old data
3. **Networking**: Minimize cross-region transfers, use VNet peering over VPN Gateway
4. **Monitoring**: Set data retention policies, use sampling in Application Insights

---

## Security & Compliance

### Azure Policy for Governance

```bicep
resource policyAssignment 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'mcsb-${appName}'
  properties: {
    displayName: 'Microsoft Cloud Security Benchmark v2'
    policyDefinitionId: '/providers/Microsoft.Authorization/policySetDefinitions/1f3afdf9-d0c9-4c3d-847f-89da613e70a8'
    scope: resourceGroup().id
    enforcementMode: 'Default'
  }
}

// Custom policy: Require tags
resource requireTagsPolicy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: 'require-tags-policy'
  properties: {
    displayName: 'Require specific tags on resources'
    policyType: 'Custom'
    mode: 'Indexed'
    policyRule: {
      if: {
        anyOf: [
          { field: 'tags[Environment]', exists: false }
          { field: 'tags[CostCenter]', exists: false }
          { field: 'tags[Owner]', exists: false }
        ]
      }
      then: { effect: 'deny' }
    }
  }
}
```

---

## Terraform for Azure

### State Management with Azure Backend

```hcl
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstate"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
    use_oidc         = true
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
  use_oidc = true
}
```

### Reusable Module Pattern

```hcl
# modules/aks/main.tf
variable "name" { type = string }
variable "location" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = "1.29.2"

  default_node_pool {
    name                = "system"
    vm_size             = "Standard_D4s_v5"
    enable_auto_scaling = true
    min_count           = 3
    max_count           = 10
    os_sku              = "AzureLinux"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

---

## Best Practices

1. **Use Application Insights with Log Analytics** -- centralized telemetry with KQL queries
2. **Set up alerts for SLOs** -- availability (99.9%) and latency (P95 < 300ms) thresholds
3. **Use Managed Identity everywhere** -- never store credentials in app settings
4. **Enable RBAC on Key Vault** -- more granular than access policies
5. **Tag all resources** -- at minimum: Environment, CostCenter, Owner, Project
6. **Use Azure DevOps environments** with approval gates for production deployments
7. **Use OIDC** for GitHub Actions -- no long-lived service principal secrets
8. **Set budget alerts** at 50%, 80%, and 100% thresholds
9. **Use Azure Policy** for governance -- enforce tagging, encryption, network isolation
10. **Enable Defender for Cloud** on all resource types -- continuous security posture assessment

---

## Anti-Patterns

1. **Using service principal secrets** for CI/CD -- use OIDC federation instead
2. **No budget alerts** -- costs can spiral without automated monitoring
3. **Skipping staging pipeline stages** -- always deploy to staging before production
4. **Using access policies** on Key Vault -- migrate to RBAC for better control
5. **Not rotating secrets** -- automate rotation with Key Vault and Managed Identity
6. **Single action group for all alerts** -- separate oncall channels by severity
7. **Not setting Log Analytics retention** -- data retention costs grow without limits
8. **Manual infrastructure changes** -- all changes must go through IaC pipelines

---

## Common CLI Commands

```bash
# Monitor & Logs
az monitor log-analytics query \
  --workspace "log-myapp-prod" \
  --analytics-query "requests | where timestamp > ago(1h) | summarize count() by resultCode"

# Key Vault
az keyvault secret set --vault-name kv-myapp-prod --name DatabasePassword --value "SuperSecret123!"
az keyvault secret show --vault-name kv-myapp-prod --name DatabasePassword --query "value" -o tsv

# Managed Identity
az identity create --resource-group rg-myapp --name id-myapp
az role assignment create --assignee PRINCIPAL_ID \
  --role "Key Vault Secrets User" --scope /subscriptions/SUB_ID/resourceGroups/rg-myapp

# Cost Management
az consumption usage list --start-date 2026-01-01 --end-date 2026-01-31 \
  --query "[].{Date:usageStart, Cost:pretaxCost}" -o table

# Bicep
az bicep build --file main.bicep
az deployment group create --resource-group rg-myapp-prod \
  --template-file main.bicep --parameters @params.prod.json

# Resource Groups
az group create --name rg-myapp-prod --location eastus
az group list --query "[?name=='rg-myapp-prod']" -o table
```

---

## Sources & References

- [Application Insights: App Reliability](https://www.divyaakula.com/cloud-monitoring/2025/08/21/application-insights-primer.html)
- [Using KQL in Azure for Application Monitoring](https://www.cloudthat.com/resources/blog/using-kql-in-azure-for-application-monitoring-and-insights)
- [Azure DevOps Pipelines: Ultimate 2025 Guide](https://medium.com/@jornbeyers/azure-devops-pipelines-ultimate-2025-structure-guide-20700c080d42)
- [Pipeline Deployment Approvals](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals)
- [Managed Identities Best Practices](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identity-best-practice-recommendations)
- [Using Managed Identities Securely](https://medium.com/@vaibhavgujral/using-managed-identities-to-access-azure-resources-securely-03fb97cfa6f0)
- [Mastering Cost Management in Azure 2025](https://www.mscloudbros.com/2025/09/08/mastering-cost-management-and-budgets-in-azure-cost-optimization/)
- [Azure Security Best Practices 2026](https://www.sentinelone.com/cybersecurity-101/cloud-security/azure-security-best-practices/)
- [Terraform for Azure Beginners Guide](https://controlmonkey.io/resource/terraform-azure-beginners-guide/)
- [AzureRM Terraform Provider](https://scalr.com/blog/azurerm-terraform-provider-overview)
