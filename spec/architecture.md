# EPAC Architecture

## Component Map

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EPAC Repository                              │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                   Definitions Root Folder                     │  │
│  │  global-settings.jsonc                                        │  │
│  │  policyDefinitions/   policySetDefinitions/                  │  │
│  │  policyAssignments/   policyExemptions/{env}/                │  │
│  │  policyDocumentations/                                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │              Scripts/Deploy/Build-DeploymentPlans.ps1         │  │
│  │                                                               │  │
│  │  ┌────────────────────────────┐  ┌────────────────────────┐  │  │
│  │  │  Get-AzPolicyResources     │  │  Build-PolicyPlan       │  │  │
│  │  │  (reads Azure current      │  │  Build-PolicySetPlan    │  │  │
│  │  │   state via REST)          │  │  Build-AssignmentPlan   │  │  │
│  │  └────────────────────────────┘  │  Build-ExemptionsPlan   │  │  │
│  │                                  └────────────────────────┘  │  │
│  │                              │                                │  │
│  │  Output: policy-plan.json + roles-plan.json                   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│              ┌───────────────┴───────────────┐                     │
│              ▼                               ▼                     │
│  ┌───────────────────────────┐  ┌───────────────────────────────┐ │
│  │ Deploy-PolicyPlan.ps1     │  │ Deploy-RolesPlan.ps1          │ │
│  │ Applies: definitions,     │  │ Applies: RBAC role            │ │
│  │ sets, assignments,        │  │ assignments for managed       │ │
│  │ exemptions                │  │ identities                    │ │
│  └───────────────────────────┘  └───────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Module / Script Loading

The PowerShell module (`Module/EnterprisePolicyAsCode/EnterprisePolicyAsCode.psm1`) dot-sources all `*.ps1` files from two subdirectories (not present in the slim published build — they are added at build time via `Module/build.ps1`):
- `internal/functions/` — Private helpers (not exported)
- `functions/` — Public functions (exported via `Export-ModuleMember`)

When run as standalone scripts (not via the module), each top-level script in `Scripts/Deploy/` and `Scripts/Operations/` calls `Add-HelperScripts.ps1`, which dot-sources all files in `Scripts/Helpers/` and `Scripts/Helpers/RestMethods/`.

## Data Flow: Build-DeploymentPlans

```
global-settings.jsonc
        │
        ▼
Get-GlobalSettings → Select-PacEnvironment
        │
        ├──────────────────────────────────────────────────┐
        │                                                  │
        ▼                                                  ▼
Get-AzPolicyResources (Azure REST)              Read JSON files from Definitions/
  - policies (built-in + custom)                  - policyDefinitions/**
  - policy sets                                   - policySetDefinitions/**
  - assignments (by pacOwner)                     - policyAssignments/**
  - exemptions                                    - policyExemptions/{env}/**
  - role assignments
        │                                                  │
        └──────────────────┬───────────────────────────────┘
                           │
                           ▼
                  Build-PolicyPlan
                    ├── Confirm-PacOwner
                    ├── Confirm-DeleteForStrategy
                    ├── Confirm-PolicyDefinitionsMatch
                    └── Confirm-MetadataMatches
                           │
                           ▼
                  Build-PolicySetPlan
                    ├── Build-PolicySetPolicyDefinitionIds
                    └── (same Confirm-* helpers)
                           │
                           ▼
                  Build-AssignmentPlan
                    ├── Build-AssignmentDefinitionNode (recursive)
                    ├── Build-AssignmentDefinitionEntry
                    ├── Build-AssignmentDefinitionAtLeaf
                    ├── Build-AssignmentParameterObject
                    ├── Build-AssignmentIdentityChanges
                    └── Merge-AssignmentParametersEx
                           │
                           ▼
                  Build-ExemptionsPlan
                    └── Confirm-ActiveAzExemptions
                           │
                           ▼
               ┌───────────────────────┐
               │ policy-plan.json      │
               │ roles-plan.json       │
               └───────────────────────┘
```

## Data Flow: Deploy-PolicyPlan

```
policy-plan.json
        │
        ├── Delete phase (exemptions → assignments → sets → policies)
        │     └── Remove-AzResourceByIdRestMethod
        │
        ├── Create/Update phase
        │     ├── Set-AzPolicyDefinitionRestMethod
        │     ├── Set-AzPolicySetDefinitionRestMethod
        │     ├── Set-AzPolicyAssignmentRestMethod
        │     └── Set-AzPolicyExemptionRestMethod
        │
        └── Exemptions phase (create/update new exemptions)
              └── Set-AzPolicyExemptionRestMethod
```

## Data Flow: Deploy-RolesPlan

```
roles-plan.json
        │
        ├── Remove phase
        │     └── Remove-AzRoleAssignmentRestMethod
        │
        ├── Add phase
        │     ├── Get-AzPolicyAssignmentRestMethod (resolve principal ID)
        │     └── Set-AzRoleAssignmentRestMethod
        │
        └── Update phase
              └── Set-AzRoleAssignmentRestMethod
```

## Assignment Definition Tree

Assignment files follow a **hierarchical node structure**. `Build-AssignmentDefinitionNode` recursively processes nodes from a root node down to leaf nodes.

```
Assignment JSON node
  ├── nodeName (required)
  ├── definitionEntry (or definitionEntryList) — leaf only
  ├── assignment (name, displayName, description)
  ├── parameters
  ├── overrides
  ├── resourceSelectors
  ├── enforcementMode
  ├── notScopes
  ├── nonComplianceMessages
  ├── managedIdentity (type, userAssigned, location)
  ├── scope (environment → scope list mapping)
  └── children (array of child nodes)
```

Ancestor properties cascade down to children; children can override but cannot unset ancestor properties. Parameters merge from parent to child, with child values taking precedence.

## Ownership Model

Every EPAC-managed resource has `metadata.pacOwnerId` set to the `pacOwnerId` from `global-settings.jsonc`. The `Confirm-PacOwner` helper classifies each deployed resource into one of:

| Owner Class | Meaning |
|-------------|---------|
| `thisPaC` | Created by this EPAC instance |
| `otherPaC` | Created by a different EPAC instance |
| `unknownOwner` | No pacOwnerId in metadata |
| `managedByDfcSecurityPolicies` | Microsoft Defender for Cloud Security |
| `managedByDfcDefenderPlans` | Microsoft Defender for Cloud Plans |

Delete decisions use `Confirm-DeleteForStrategy`:
- `thisPaC` → always delete (if removed from desired state)
- `otherPaC` → never delete
- `unknownOwner` → delete only in `full` strategy
- `managedByDfc*` → delete only if configured and `full` strategy

## REST API Layer

All Azure interactions go through thin wrappers in `Scripts/Helpers/RestMethods/`. Each wrapper:
1. Constructs the resource URI (resource ID + `?api-version=X`)
2. Calls `Invoke-AzRestMethod` (GET / PUT / DELETE)
3. Validates HTTP 200–299 response codes
4. Deserializes JSON response with `-Depth 100`
5. Returns the parsed object or writes a standardized error

API versions are environment-specific (set in `Select-PacEnvironment`) and differ between AzureCloud, AzureChinaCloud, and AzureUSGovernment.

## Scope Table

`Build-ScopeTableForManagementGroup` and `Build-ScopeTableForSubscription` build a flat lookup of all in-scope management groups and subscriptions, considering:
- `deploymentRootScope` (entry point)
- `excludedScopes` (wildcard-supported)
- `globalNotScopes` (automatic notScopes added to every assignment)
- `excludeSubscriptions` flag

The scope table is used by `Get-AzPolicyResources` to know where to query and by `Build-AssignmentPlan` to know where to apply assignments.

## Multi-Tenant / Lighthouse Support

When `managedTenantId` is set in a pacEnvironment, EPAC targets a delegated customer tenant for policy deployment. Role assignments for cross-tenant scenarios are tracked via the description field and removed via the managing tenant connection.
