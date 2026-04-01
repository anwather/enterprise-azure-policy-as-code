# EPAC Overview

## Purpose

Enterprise Policy as Code (EPAC) is a Microsoft-authored PowerShell framework that manages Azure Policy resources — policy definitions, policy set definitions (initiatives), policy assignments, policy exemptions, and RBAC role assignments — through a **declarative, infrastructure-as-code** model.

Instead of manually clicking through the Azure Portal or using imperative scripts, operators declare their desired policy state in JSON/JSONC files, and EPAC reconciles that desired state against what is actually deployed in Azure, producing a **deployment plan** (diff) and then **applying** only the necessary changes.

## Core Concepts

### pacOwnerId
A GUID stored in every resource's `metadata.pacOwnerId` field to "tag" resources created by this EPAC instance. This lets multiple EPAC deployments coexist in the same tenant without interfering with each other.

### pacEnvironment
A named environment (e.g., `EPAC-DEV`, `Tenant`) defined in `global-settings.jsonc`. Each environment specifies:
- Azure cloud type (AzureCloud, AzureChinaCloud, AzureUSGovernment)
- Tenant ID
- Deployment root scope (management group or subscription)
- Desired state strategy (`full` or `ownedOnly`)
- Managed identity location
- Scope exclusions

### Desired State Strategy
- **`full`**: EPAC manages all policy resources in scope; unknown/unmanaged resources are deleted
- **`ownedOnly`**: EPAC only manages resources tagged with its own `pacOwnerId`; foreign resources are ignored

### Definitions Root Folder
A folder hierarchy (default: `./Definitions`) containing:
- `global-settings.jsonc` — Environment definitions
- `policyDefinitions/` — Custom policy definitions
- `policySetDefinitions/` — Custom policy initiatives
- `policyAssignments/` — Assignment definitions (tree structure)
- `policyExemptions/{pacSelector}/` — Exemption definitions per environment
- `policyDocumentations/` — Documentation generation config

### Three-Stage Pipeline
EPAC follows a strict Plan → Deploy Policy → Deploy Roles pipeline:
1. **Plan** (`Build-DeploymentPlans.ps1`): Read desired state from files + read current state from Azure → produce JSON plan files
2. **Deploy Policy** (`Deploy-PolicyPlan.ps1`): Apply the policy plan (definitions, sets, assignments, exemptions)
3. **Deploy Roles** (`Deploy-RolesPlan.ps1`): Apply the role assignment plan (managed identity RBAC assignments)

## Key Resource Types Managed

| Resource Type | Azure Type | Description |
|--------------|-----------|-------------|
| Policy Definition | `Microsoft.Authorization/policyDefinitions` | Custom policy rules |
| Policy Set Definition | `Microsoft.Authorization/policySetDefinitions` | Bundles of policies (initiatives) |
| Policy Assignment | `Microsoft.Authorization/policyAssignments` | Applies a policy or set to a scope |
| Policy Exemption | `Microsoft.Authorization/policyExemptions` | Excludes resources from a policy's scope |
| Role Assignment | `Microsoft.Authorization/roleAssignments` | RBAC assignments for managed identities |

## Technology Stack

- **Language**: PowerShell 7.0+
- **Azure Integration**: Azure REST APIs via `Invoke-AzRestMethod` (Az PowerShell module)
- **Module Distribution**: PowerShell Gallery (`EnterprisePolicyAsCode`)
- **CI/CD**: Azure DevOps, GitHub Actions, GitLab CI/CD
- **Documentation**: MkDocs (Material theme)
- **Schema Validation**: JSON Schema (in `Schemas/`)

## Supported Azure Environments

| Cloud | Notes |
|-------|-------|
| AzureCloud | Default; uses latest API versions |
| AzureChinaCloud | 21Vianet-operated; older API versions |
| AzureUSGovernment | Government cloud |
| AzureGermanCloud | Legacy German cloud |

## Telemetry

EPAC supports Customer Usage Attribution (CUA) telemetry, which is enabled by default. It can be disabled by setting `"telemetryOptOut": true` in `global-settings.jsonc`.

## Repository Origins

- Upstream: `Azure/enterprise-azure-policy-as-code` on GitHub
- This fork: `anwather/enterprise-azure-policy-as-code`
- Module published to PowerShell Gallery: `EnterprisePolicyAsCode`
- Documentation: https://azure.github.io/enterprise-azure-policy-as-code/
