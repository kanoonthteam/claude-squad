---
name: azure-networking
description: Production-grade Azure networking -- VNet, App Gateway, Front Door, Private Endpoints, Service Endpoints, DNS, Traffic Manager with Bicep
---

# Azure Networking -- Staff Engineer Patterns

Production-ready patterns for VNet design, Application Gateway, Front Door, Private Endpoints, Service Endpoints, DNS, and Traffic Manager using Bicep.

## Table of Contents
1. [Hub-Spoke VNet Topology](#hub-spoke-vnet-topology)
2. [Azure Front Door with WAF](#azure-front-door-with-waf)
3. [Application Gateway](#application-gateway)
4. [Private Endpoints](#private-endpoints)
5. [Service Endpoints](#service-endpoints)
6. [Private DNS Zones](#private-dns-zones)
7. [Network Security Groups](#network-security-groups)
8. [Traffic Manager](#traffic-manager)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)
11. [Common CLI Commands](#common-cli-commands)
12. [Sources & References](#sources--references)

---

## Hub-Spoke VNet Topology

### Hub VNet with Shared Services

```bicep
// Hub VNet
resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-hub'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: { addressPrefix: '10.0.0.0/26' }
      }
      {
        name: 'GatewaySubnet'
        properties: { addressPrefix: '10.0.1.0/27' }
      }
      {
        name: 'AzureBastionSubnet'
        properties: { addressPrefix: '10.0.2.0/27' }
      }
      {
        name: 'SharedServicesSubnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Spoke VNet
resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-spoke-${env}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.1.0.0/16']
    }
    subnets: [
      {
        name: 'AppSubnet'
        properties: {
          addressPrefix: '10.1.0.0/24'
          networkSecurityGroup: { id: appNsg.id }
          serviceEndpoints: [
            { service: 'Microsoft.Storage' }
            { service: 'Microsoft.Sql' }
            { service: 'Microsoft.KeyVault' }
          ]
          delegations: [
            {
              name: 'appServiceDelegation'
              properties: { serviceName: 'Microsoft.Web/serverFarms' }
            }
          ]
        }
      }
      {
        name: 'AksSubnet'
        properties: {
          addressPrefix: '10.1.1.0/24'
          networkSecurityGroup: { id: aksNsg.id }
        }
      }
      {
        name: 'PrivateEndpointSubnet'
        properties: {
          addressPrefix: '10.1.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// VNet Peering (Hub to Spoke)
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVnet
  name: 'hub-to-spoke-${env}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
    remoteVirtualNetwork: { id: spokeVnet.id }
  }
}

// VNet Peering (Spoke to Hub)
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: spokeVnet
  name: 'spoke-${env}-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: true
    remoteVirtualNetwork: { id: hubVnet.id }
  }
}
```

---

## Azure Front Door with WAF

### Global Edge Security with Premium Front Door

```bicep
resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: 'afd-${appName}'
  location: 'global'
  sku: { name: 'Premium_AzureFrontDoor' }
}

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: 'waf-frontdoor'
  location: 'global'
  sku: { name: 'Premium_AzureFrontDoor' }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
    }
    customRules: {
      rules: [
        {
          name: 'RateLimitRule'
          priority: 1
          ruleType: 'RateLimitRule'
          rateLimitThreshold: 100
          rateLimitDurationInMinutes: 1
          matchConditions: [
            {
              matchVariable: 'RemoteAddr'
              operator: 'IPMatch'
              matchValue: ['0.0.0.0/0']
            }
          ]
          action: 'Block'
        }
      ]
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
        }
      ]
    }
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoorProfile
  name: 'app-endpoint'
  location: 'global'
  properties: { enabledState: 'Enabled' }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoorProfile
  name: 'app-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: 'appgw-origin'
  properties: {
    hostName: appGwFqdn
    httpPort: 80
    httpsPort: 443
    originHostHeader: appGwFqdn
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'default-route'
  properties: {
    originGroup: { id: originGroup.id }
    supportedProtocols: ['Https']
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    cacheConfiguration: {
      queryStringCachingBehavior: 'UseQueryString'
      compressionSettings: {
        contentTypesToCompress: [
          'application/json'
          'text/html'
          'text/css'
          'application/javascript'
        ]
        isCompressionEnabled: true
      }
    }
  }
  dependsOn: [origin]
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  parent: frontDoorProfile
  name: 'security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: { id: wafPolicy.id }
      associations: [
        {
          domains: [{ id: endpoint.id }]
          patternsToMatch: ['/*']
        }
      ]
    }
  }
}
```

---

## Application Gateway

### WAF v2 Application Gateway

```bicep
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: 'appgw-${appName}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${managedIdentity.id}': {} }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: { subnet: { id: appGwSubnetId } }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: { publicIPAddress: { id: appGwPublicIP.id } }
      }
    ]
    frontendPorts: [
      { name: 'port_443', properties: { port: 443 } }
    ]
    backendAddressPools: [
      {
        name: 'appServiceBackend'
        properties: {
          backendAddresses: [{ fqdn: webApp.properties.defaultHostName }]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appServiceBackendSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 20
          pickHostNameFromBackendAddress: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes',
              'appgw-${appName}', 'health-probe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'health-probe'
        properties: {
          protocol: 'Https'
          path: '/health'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
        }
      }
    ]
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
    }
    autoscaleConfiguration: {
      minCapacity: 2
      maxCapacity: 10
    }
    sslCertificates: [
      {
        name: 'ssl-cert'
        properties: {
          keyVaultSecretId: '${keyVault.properties.vaultUri}secrets/ssl-certificate'
        }
      }
    ]
  }
}
```

---

## Private Endpoints

### Private Endpoint for App Service

```bicep
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${webApp.name}'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'pe-connection'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: ['sites']
        }
      }
    ]
  }
}

// Private endpoint for staging slot
resource stagingPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${webApp.name}-staging'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'pe-connection-staging'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: ['sites-staging']
        }
      }
    ]
  }
}
```

### Private Endpoint for Key Vault

```bicep
resource kvPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${keyVault.name}'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'kv-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}
```

---

## Service Endpoints

### Service Endpoints vs Private Endpoints

Service endpoints route traffic through the Azure backbone but keep the public endpoint. Private endpoints create a private IP in your VNet.

```bicep
// Service Endpoints (simpler, free, but less secure)
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: 'AppSubnet'
  properties: {
    addressPrefix: '10.1.0.0/24'
    serviceEndpoints: [
      { service: 'Microsoft.Storage' }
      { service: 'Microsoft.Sql' }
      { service: 'Microsoft.KeyVault' }
    ]
  }
}

// Storage account restricted to VNet
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stmyapp'
  location: location
  // ...
  properties: {
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        { id: subnet.id, action: 'Allow' }
      ]
    }
  }
}
```

---

## Private DNS Zones

### DNS Integration for Private Endpoints

```bicep
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-to-spoke'
  location: 'global'
  properties: {
    virtualNetwork: { id: spokeVnet.id }
    registrationEnabled: false
  }
}

// DNS zone group for automatic DNS record creation
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}
```

### Common Private DNS Zones

```bicep
// Standard DNS zones for Azure services
var privateDnsZones = [
  'privatelink.azurewebsites.net'       // App Service
  'privatelink.database.windows.net'     // Azure SQL
  'privatelink.documents.azure.com'      // Cosmos DB
  'privatelink.blob.core.windows.net'    // Blob Storage
  'privatelink.vaultcore.azure.net'      // Key Vault
  'privatelink.redis.cache.windows.net'  // Redis Cache
  'privatelink.postgres.database.azure.com' // PostgreSQL
]

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in privateDnsZones: {
  name: zone
  location: 'global'
}]
```

---

## Network Security Groups

### Layered NSG Rules

```bicep
resource appNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-app'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}
```

---

## Traffic Manager

### Multi-Region Traffic Routing

```bicep
resource trafficManager 'Microsoft.Network/trafficmanagerprofiles@2022-04-01' = {
  name: 'tm-${appName}'
  location: 'global'
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Performance'
    dnsConfig: {
      relativeName: appName
      ttl: 60
    }
    monitorConfig: {
      protocol: 'HTTPS'
      port: 443
      path: '/health'
      intervalInSeconds: 30
      toleratedNumberOfFailures: 3
      timeoutInSeconds: 10
    }
    endpoints: [
      {
        name: 'east-us'
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          targetResourceId: eastUsWebApp.id
          endpointStatus: 'Enabled'
          priority: 1
          weight: 100
        }
      }
      {
        name: 'west-us'
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          targetResourceId: westUsWebApp.id
          endpointStatus: 'Enabled'
          priority: 2
          weight: 100
        }
      }
    ]
  }
}
```

---

## Best Practices

1. **Use Hub-Spoke topology** -- centralized shared services with isolated workload VNets
2. **Use Private Endpoints** over Service Endpoints for production -- full network isolation
3. **Layer Front Door + Application Gateway** -- global edge security with regional WAF
4. **Enable DDoS Protection** on Hub VNet -- protects all peered spoke VNets
5. **Use Azure Firewall** in Hub for centralized egress -- inspect and log all outbound traffic
6. **Create Private DNS Zones** for each Azure service -- automatic DNS resolution for private endpoints
7. **Use NSG Flow Logs** for traffic analysis -- enable Network Watcher diagnostics
8. **Plan IP address space** carefully -- avoid overlapping CIDRs across VNets
9. **Use Application Gateway for WAF** at regional level -- OWASP rule sets with custom rules
10. **Use Traffic Manager** for DNS-based multi-region routing -- fast failover on health check failures

---

## Anti-Patterns

1. **Using Service Endpoints for highly sensitive data** -- Private Endpoints provide better isolation
2. **Deploying without NSGs** -- every subnet must have a network security group
3. **Using public IP addresses on backend services** -- expose only through Front Door/App Gateway
4. **Not using DDoS Protection** -- Azure DDoS Standard protects all public IPs in the VNet
5. **Single VNet for all environments** -- isolate dev/staging/prod in separate VNets
6. **Opening NSG to 0.0.0.0/0 for SSH/RDP** -- use Azure Bastion for secure management access
7. **Skipping Private DNS Zones** -- without them, private endpoints require manual DNS config
8. **Not planning for IP exhaustion** -- use /16 for VNets with /24 subnets minimum

---

## Common CLI Commands

```bash
# VNet
az network vnet list --query "[*].{Name:name,AddressSpace:addressSpace.addressPrefixes}" -o table
az network vnet show --resource-group rg-hub --name vnet-hub
az network vnet peering list --resource-group rg-hub --vnet-name vnet-hub -o table

# NSG
az network nsg list --query "[*].{Name:name,Rules:securityRules[*].name}" -o table
az network nsg rule list --resource-group rg-app --nsg-name nsg-app -o table

# Private Endpoints
az network private-endpoint list --query "[*].{Name:name,Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o table

# Front Door
az afd profile list --query "[*].{Name:name,Sku:sku.name}" -o table
az afd endpoint list --profile-name afd-myapp --resource-group rg-edge -o table

# Application Gateway
az network application-gateway list --query "[*].{Name:name,State:operationalState}" -o table

# Private DNS
az network private-dns zone list --query "[*].{Name:name,Records:numberOfRecordSets}" -o table

# Traffic Manager
az network traffic-manager profile list --query "[*].{Name:name,Status:profileStatus}" -o table
```

---

## Sources & References

- [Hub-Spoke Network Topology with Azure VNet Peering](https://oneuptime.com/blog/post/2026-02-16-hub-and-spoke-network-topology-azure-virtual-network-peering/view)
- [Azure Network Planning Guide: VNet Design 2025](https://networks.tools/learn/article/azure-network-planning-guide)
- [Hub-spoke network topology in Azure](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
- [Azure Front Door: Secure & Scalable Gateway](https://www.theknowledgeacademy.com/blog/azure-front-door/)
- [High Availability - Azure Front Door](https://learn.microsoft.com/en-us/azure/frontdoor/high-availability)
- [Architecture Best Practices for Azure Application Gateway v2](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-application-gateway)
- [Use Private Endpoints for Apps](https://learn.microsoft.com/en-us/azure/app-service/overview-private-endpoint)
- [Azure Private DNS zones](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
- [Azure Traffic Manager](https://learn.microsoft.com/en-us/azure/traffic-manager/traffic-manager-overview)
