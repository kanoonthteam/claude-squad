---
name: terraform-patterns
description: Terraform and Terragrunt patterns for infrastructure as code including modules, state management, and CI/CD
---

# Terraform Patterns

## Overview

Terraform by HashiCorp is the industry standard for infrastructure as code (IaC). It uses declarative HCL (HashiCorp Configuration Language) to provision and manage cloud resources across AWS, GCP, Azure, and 3000+ providers. This skill covers production-ready patterns, module design, state management, Terragrunt, CI/CD, and testing.

## HCL Deep-Dive

### Variables

```hcl
# variables.tf

# Simple variable with validation
variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, production)"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

# Complex variable with object type
variable "database_config" {
  type = object({
    instance_class    = string
    allocated_storage = number
    engine_version    = string
    multi_az          = bool
    backup_retention  = number
  })

  default = {
    instance_class    = "db.t3.medium"
    allocated_storage = 50
    engine_version    = "15.4"
    multi_az          = false
    backup_retention  = 7
  }
}

# Map variable
variable "tags" {
  type = map(string)
  default = {
    ManagedBy = "terraform"
    Team      = "platform"
  }
}

# List variable with sensitive flag
variable "allowed_cidrs" {
  type      = list(string)
  sensitive = false
  default   = []
}

variable "db_password" {
  type      = string
  sensitive = true  # Never shown in logs or plan output
}
```

### Locals

```hcl
# locals.tf
locals {
  # Computed values used throughout the configuration
  name_prefix = "${var.project}-${var.environment}"

  # Merge default tags with user-provided tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
  })

  # Conditional logic
  is_production = var.environment == "production"
  instance_type = local.is_production ? "m5.xlarge" : "t3.medium"

  # Complex computed value
  subnet_cidrs = {
    for idx, az in data.aws_availability_zones.available.names :
    az => cidrsubnet(var.vpc_cidr, 8, idx)
  }
}
```

### Data Sources

```hcl
# Look up existing resources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Remote state data source (cross-stack references)
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "mycompany-terraform-state"
    key    = "networking/terraform.tfstate"
    region = "us-east-1"
  }
}

# Use data source outputs
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = local.instance_type
  subnet_id     = data.terraform_remote_state.networking.outputs.private_subnet_ids[0]
}
```

### Dynamic Blocks

```hcl
# Security group with dynamic ingress rules
resource "aws_security_group" "app" {
  name_prefix = "${local.name_prefix}-app-"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Variable definition for dynamic block
variable "ingress_rules" {
  type = list(object({
    port        = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))

  default = [
    {
      port        = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS"
    },
    {
      port        = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP"
    },
  ]
}
```

## Module Design

### Composable Module Structure

```
modules/
├── networking/
│   ├── main.tf           # VPC, subnets, NAT
│   ├── variables.tf      # Input variables
│   ├── outputs.tf        # Output values
│   ├── versions.tf       # Provider/Terraform version constraints
│   └── README.md         # Module documentation
├── database/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
├── ecs-service/
│   ├── main.tf
│   ├── iam.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
└── monitoring/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

### Module Example: ECS Service

```hcl
# modules/ecs-service/main.tf
resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = var.tags
}

# modules/ecs-service/variables.tf
variable "service_name" {
  type        = string
  description = "Name of the ECS service"
}

variable "cluster_id" {
  type        = string
  description = "ECS cluster ID"
}

variable "desired_count" {
  type        = number
  description = "Number of tasks to run"
  default     = 2
}

variable "container_port" {
  type        = number
  description = "Container port to expose"
  default     = 8080
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the service"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}

# modules/ecs-service/outputs.tf
output "service_name" {
  value       = aws_ecs_service.this.name
  description = "The ECS service name"
}

output "service_id" {
  value       = aws_ecs_service.this.id
  description = "The ECS service ID"
}

output "target_group_arn" {
  value       = aws_lb_target_group.this.arn
  description = "The ALB target group ARN"
}
```

### Module Usage

```hcl
# environments/production/main.tf
module "api_service" {
  source = "../../modules/ecs-service"

  service_name  = "api"
  cluster_id    = module.ecs_cluster.id
  desired_count = 4
  container_port = 8080
  subnet_ids    = module.networking.private_subnet_ids

  tags = local.common_tags
}

module "worker_service" {
  source = "../../modules/ecs-service"

  service_name  = "worker"
  cluster_id    = module.ecs_cluster.id
  desired_count = 2
  container_port = 8081
  subnet_ids    = module.networking.private_subnet_ids

  tags = local.common_tags
}
```

### Versioned Modules (Registry)

```hcl
# Use module from Terraform Registry
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = !local.is_production

  tags = local.common_tags
}

# Use module from private Git repository
module "internal_module" {
  source = "git::https://github.com/myorg/terraform-modules.git//ecs-service?ref=v2.1.0"

  service_name = "api"
}
```

### versions.tf (Module Version Constraints)

```hcl
# modules/ecs-service/versions.tf
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

## State Management

### S3 + DynamoDB Backend (AWS)

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "production/api/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    kms_key_id     = "alias/terraform-state"
  }
}
```

```hcl
# Bootstrap: Create state backend resources
# (Run this once with local state, then migrate)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "mycompany-terraform-state"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

### GCS Backend (GCP)

```hcl
terraform {
  backend "gcs" {
    bucket = "mycompany-terraform-state"
    prefix = "production/api"
  }
}
```

### Azure Blob Backend

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "mycompanytfstate"
    container_name       = "tfstate"
    key                  = "production/api/terraform.tfstate"
  }
}
```

### State Manipulation Commands

```bash
# List resources in state
terraform state list

# Show specific resource
terraform state show aws_instance.app

# Move a resource (rename without destroy/create)
terraform state mv aws_instance.old aws_instance.new

# Remove from state (without destroying)
terraform state rm aws_instance.manually_managed

# Import existing resource into state
terraform import aws_instance.app i-1234567890abcdef0

# Pull/push remote state
terraform state pull > state.json
terraform state push state.json
```

### Moved Blocks (Terraform 1.1+)

```hcl
# Refactor without destroy/create
moved {
  from = aws_instance.app
  to   = module.compute.aws_instance.app
}

moved {
  from = module.old_name
  to   = module.new_name
}
```

## Workspaces vs Terragrunt

### Terraform Workspaces

```bash
# Create and switch workspaces
terraform workspace new staging
terraform workspace new production
terraform workspace select staging

# Use workspace in configuration
locals {
  environment = terraform.workspace
}
```

**When to use workspaces**: Simple environments with identical infrastructure that differ only in scale/naming.

**When NOT to use workspaces**: Different environments need different configurations, modules, or providers.

### Terragrunt (Recommended for Multi-Account)

```
infrastructure/
├── terragrunt.hcl              # Root config
├── _envcommon/                  # Shared config per module
│   ├── networking.hcl
│   ├── database.hcl
│   └── app.hcl
├── dev/
│   ├── account.hcl
│   ├── us-east-1/
│   │   ├── region.hcl
│   │   ├── networking/
│   │   │   └── terragrunt.hcl
│   │   ├── database/
│   │   │   └── terragrunt.hcl
│   │   └── app/
│   │       └── terragrunt.hcl
├── staging/
│   ├── account.hcl
│   └── us-east-1/
│       ├── region.hcl
│       ├── networking/
│       │   └── terragrunt.hcl
│       └── ...
└── production/
    ├── account.hcl
    └── us-east-1/
        └── ...
```

### Root terragrunt.hcl

```hcl
# infrastructure/terragrunt.hcl
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket         = "mycompany-terraform-state-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = {
      Environment = "${local.environment}"
      ManagedBy   = "terragrunt"
      Project     = "${local.project}"
    }
  }
}
EOF
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_id  = local.account_vars.locals.account_id
  aws_region  = local.region_vars.locals.aws_region
  environment = local.account_vars.locals.environment
  project     = "myproject"
}
```

### Module-Level terragrunt.hcl

```hcl
# infrastructure/production/us-east-1/database/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/database.hcl"
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders())}/../modules/database"
}

inputs = {
  instance_class    = "db.r6g.xlarge"
  allocated_storage = 500
  multi_az          = true
  backup_retention  = 35
}

# Cross-module dependency
dependency "networking" {
  config_path = "../networking"
}

inputs = merge(
  include.env.inputs,
  {
    subnet_ids = dependency.networking.outputs.private_subnet_ids
    vpc_id     = dependency.networking.outputs.vpc_id
  }
)
```

### Terragrunt run-all

```bash
# Plan all modules in an environment
terragrunt run-all plan --terragrunt-working-dir infrastructure/production/us-east-1

# Apply with dependency ordering
terragrunt run-all apply --terragrunt-working-dir infrastructure/production/us-east-1

# Destroy in reverse dependency order
terragrunt run-all destroy --terragrunt-working-dir infrastructure/staging/us-east-1
```

## CI/CD Integration

### GitHub Actions: Plan on PR, Apply on Merge

```yaml
name: Terraform
on:
  pull_request:
    branches: [main]
    paths: ['infrastructure/**']
  push:
    branches: [main]
    paths: ['infrastructure/**']

permissions:
  id-token: write    # OIDC for AWS
  contents: read
  pull-requests: write

jobs:
  plan:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/TerraformPlan
          aws-region: us-east-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.7.0

      - name: Terraform Init
        run: terraform init
        working-directory: infrastructure/production

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color -out=plan.tfplan
        working-directory: infrastructure/production
        continue-on-error: true

      - name: Comment PR with Plan
        uses: actions/github-script@v7
        with:
          script: |
            const output = `#### Terraform Plan
            \`\`\`
            ${{ steps.plan.outputs.stdout }}
            \`\`\`
            *Pushed by: @${{ github.actor }}*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })

      - name: Fail if plan failed
        if: steps.plan.outcome == 'failure'
        run: exit 1

  apply:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/TerraformApply
          aws-region: us-east-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.7.0

      - name: Terraform Init
        run: terraform init
        working-directory: infrastructure/production

      - name: Terraform Apply
        run: terraform apply -auto-approve
        working-directory: infrastructure/production
```

## Provider Patterns

### Multi-Region

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west"
  region = "eu-west-1"
}

# Use aliased provider
resource "aws_s3_bucket" "eu_assets" {
  provider = aws.eu_west
  bucket   = "myapp-assets-eu"
}
```

### Assume Role (Cross-Account)

```hcl
provider "aws" {
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::TARGET_ACCOUNT:role/TerraformRole"
    session_name = "terraform-deploy"
  }
}
```

## Testing

### terraform test (Native, Terraform 1.6+)

```hcl
# tests/vpc.tftest.hcl
provider "aws" {
  region = "us-east-1"
}

variables {
  vpc_cidr    = "10.99.0.0/16"
  environment = "test"
}

run "creates_vpc" {
  command = apply

  assert {
    condition     = aws_vpc.main.cidr_block == "10.99.0.0/16"
    error_message = "VPC CIDR block is incorrect"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_hostnames == true
    error_message = "DNS hostnames should be enabled"
  }
}

run "creates_private_subnets" {
  command = apply

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Expected 3 private subnets"
  }
}
```

### Terratest (Go)

```go
// test/vpc_test.go
package test

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/aws"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestVpcModule(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/networking",
        Vars: map[string]interface{}{
            "environment": "test",
            "vpc_cidr":    "10.99.0.0/16",
        },
    })

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    vpcId := terraform.Output(t, terraformOptions, "vpc_id")
    subnets := terraform.OutputList(t, terraformOptions, "private_subnet_ids")

    vpc := aws.GetVpcById(t, vpcId, "us-east-1")
    assert.Equal(t, "10.99.0.0/16", vpc.CidrBlock)
    assert.Equal(t, 3, len(subnets))
}
```

## Policy as Code

### Sentinel (Terraform Cloud/Enterprise)

```python
# restrict-instance-types.sentinel
import "tfplan/v2" as tfplan

allowed_types = ["t3.micro", "t3.small", "t3.medium", "m5.large", "m5.xlarge"]

ec2_instances = filter tfplan.resource_changes as _, rc {
    rc.type is "aws_instance" and
    (rc.change.actions contains "create" or rc.change.actions contains "update")
}

main = rule {
    all ec2_instances as _, instance {
        instance.change.after.instance_type in allowed_types
    }
}
```

### OPA (Open Policy Agent)

```rego
# policy/terraform.rego
package terraform

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket"
    not resource.change.after.server_side_encryption_configuration
    msg := sprintf("S3 bucket '%s' must have encryption enabled", [resource.name])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group_rule"
    resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
    resource.change.after.from_port == 22
    msg := sprintf("Security group '%s' must not allow SSH from 0.0.0.0/0", [resource.name])
}
```

## Best Practices

1. **Use modules for reusability** -- extract common patterns into versioned modules
2. **Pin provider and module versions** -- use `~>` for minor version flexibility
3. **Remote state with locking** -- always use DynamoDB/equivalent for state locking
4. **Separate state per environment** -- never share state between dev, staging, production
5. **Use `terraform plan` in CI** -- always review before applying
6. **Minimize blast radius** -- split infrastructure into small, focused state files
7. **Use `prevent_destroy` lifecycle** for critical resources (databases, S3 buckets)
8. **Tag everything** -- use `default_tags` in the provider block
9. **Use data sources** to reference resources managed in other state files
10. **Run `terraform fmt`** and `terraform validate` in CI

## Anti-Patterns

1. **Manual changes** -- all infrastructure should be in code; use `terraform import` for drift
2. **Local state** in production -- always use remote backends
3. **Monolithic state** -- one state file for all infrastructure is fragile and slow
4. **Hardcoded values** -- use variables and locals, not magic strings
5. **No version constraints** -- unversioned providers/modules break unexpectedly
6. **`terraform apply -auto-approve`** without plan review in production
7. **Secrets in state/code** -- use vault references or secret manager data sources
8. **Ignoring `terraform plan` output** -- always read the plan carefully before applying
9. **`count` for conditional resources** -- prefer `for_each` for better state management
10. **No `lifecycle` rules** -- missing `prevent_destroy` on stateful resources

## Sources & References

- https://developer.hashicorp.com/terraform/docs -- Terraform official documentation
- https://developer.hashicorp.com/terraform/language -- HCL language reference
- https://developer.hashicorp.com/terraform/language/modules/develop -- Module development guide
- https://terragrunt.gruntwork.io/docs/ -- Terragrunt documentation
- https://developer.hashicorp.com/terraform/language/testing -- Terraform native testing
- https://terratest.gruntwork.io/ -- Terratest documentation
- https://developer.hashicorp.com/sentinel -- Sentinel policy as code
- https://www.openpolicyagent.org/docs/latest/terraform/ -- OPA with Terraform
- https://github.com/terraform-aws-modules -- Community AWS modules
- https://developer.hashicorp.com/terraform/tutorials/state/state-import -- State import tutorial
