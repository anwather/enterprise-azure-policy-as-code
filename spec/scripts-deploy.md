# EPAC Deploy Scripts

Located in `Scripts/Deploy/`. These are the core pipeline scripts invoked in every CI/CD workflow.

---

## Build-DeploymentPlans.ps1

### Purpose
Compares the desired policy state (JSON files in the Definitions folder) against the current Azure state (queried via REST) and produces JSON plan files describing every required change. This is the **plan/what-if** stage — no changes are made to Azure.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PacEnvironmentSelector` | string | — | Selects the pacEnvironment (from `global-settings.jsonc`). If omitted and only one environment exists, that one is used; otherwise interactive prompt |
| `DefinitionsRootFolder` | string | `$env:PAC_DEFINITIONS_FOLDER` or `./Definitions` | Path to Definitions root folder |
| `OutputFolder` | string | `$env:PAC_OUTPUT_FOLDER` or `./Output` | Path to write plan files |
| `Interactive` | switch | false | Enable interactive mode (prompts for environment selection, confirmations) |
| `DevOpsType` | string | — | If set to `ado` or `gitlab`, sets pipeline variables `deployPolicyChanges` and `deployRoleChanges` instead of writing plan files |
| `BuildExemptionsOnly` | switch | false | Skip policy/assignment plans; build only the exemptions plan |
| `SkipExemptions` | switch | false | Skip exemptions plan |
| `SkipNotScopedExemptions` | switch | false | Exclude exemptions not scoped to the deployment root |
| `DetailedOutput` | switch | false | Show per-resource change details (similar to `terraform plan`) |

### Inputs
- `{DefinitionsRootFolder}/global-settings.jsonc`
- `{DefinitionsRootFolder}/policyDefinitions/**/*.json`
- `{DefinitionsRootFolder}/policySetDefinitions/**/*.jsonc`
- `{DefinitionsRootFolder}/policyAssignments/**/*.jsonc`
- `{DefinitionsRootFolder}/policyExemptions/{pacSelector}/**/*.jsonc`
- Azure current state (via `Get-AzPolicyResources`)

### Outputs
- `{OutputFolder}/plans-{pacSelector}/policy-plan.json` — Plans for policies, policy sets, assignments, and exemptions
- `{OutputFolder}/plans-{pacSelector}/roles-plan.json` — Plans for role assignments
- Pipeline variables (if `DevOpsType` is set): `deployPolicyChanges = 'yes'/'no'`, `deployRoleChanges = 'yes'/'no'`

### Key Logic Flow
1. Call `Select-PacEnvironment` → validates environment, sets cloud/tenant context via `Set-AzCloudTenantSubscription`
2. Call `Get-AzPolicyResources` → retrieves all deployed policy resources
3. (Unless `BuildExemptionsOnly`) Call `Build-PolicyPlan` → compares custom policy definitions
4. (Unless `BuildExemptionsOnly`) Call `Build-PolicySetPlan` → compares policy set definitions
5. Call `Convert-PolicyResourcesToDetails` → enriches definitions for assignment processing
6. (Unless `BuildExemptionsOnly`) Call `Build-AssignmentPlan` → compares assignments and generates role plan
7. (Unless `SkipExemptions`) Call `Build-ExemptionsPlan` → compares exemptions
8. Write plan files to disk or set DevOps pipeline variables
9. Print summary counts: new / update / replace / delete per resource type

### Dependencies (helper functions called)
- `Select-PacEnvironment`, `Set-AzCloudTenantSubscription`
- `Get-AzPolicyResources`
- `Build-PolicyPlan`, `Build-PolicySetPlan`, `Build-AssignmentPlan`, `Build-ExemptionsPlan`
- `Convert-PolicyResourcesToDetails`, `Get-CalculatedPolicyAssignmentsAndReferenceIds`
- `Add-HelperScripts` (loads all helpers)

---

## Deploy-PolicyPlan.ps1

### Purpose
Reads the `policy-plan.json` produced by `Build-DeploymentPlans.ps1` and applies all changes to Azure — in the correct dependency order (delete first, then create/update, then exemptions).

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PacEnvironmentSelector` | string | — | PAC environment to deploy to |
| `DefinitionsRootFolder` | string | `$env:PAC_DEFINITIONS_FOLDER` or `./Definitions` | Definitions root (for environment lookup) |
| `InputFolder` | string | `$env:PAC_INPUT_FOLDER` → `$env:PAC_OUTPUT_FOLDER` → `./Output` | Where to read the plan file |
| `Interactive` | switch | false | Enable interactive mode |
| `SkipExemptions` | switch | false | Do not deploy exemption changes |
| `FailOnExemptionError` | switch | false | Fail deployment if exemption creation returns HTTP 403 |

### Inputs
- `{InputFolder}/plans-{pacSelector}/policy-plan.json`

### Outputs
- Azure resource changes (no local file output)
- Console log of what was deployed, with timing

### Key Logic Flow

**Delete phase** (if not `SkipExemptions`):
1. Delete exemptions marked for deletion or replacement
2. Delete assignments marked for deletion or replacement
3. Delete policy sets marked for deletion or replacement
4. Delete policies marked for replacement

**Create/Update phase**:
5. Create/update policy definitions (new, replace, update — in that order)
6. Create/update policy set definitions
7. Delete policies no longer needed (cleanup after sets updated)
8. Create/update assignments (new, replace, update)

**Exemptions phase** (if not `SkipExemptions`):
9. Create/update exemptions (new, replace, update)

### Deployment Order Rationale
- Exemptions and assignments must be deleted before policy sets, which must be deleted before policies (reverse dependency order)
- Policies must be created/updated before policy sets, which must be created before assignments
- Exemptions are applied last because they reference assignments

### Dependencies
- `Remove-AzResourceByIdRestMethod`
- `Set-AzPolicyDefinitionRestMethod`
- `Set-AzPolicySetDefinitionRestMethod`
- `Set-AzPolicyAssignmentRestMethod`
- `Set-AzPolicyExemptionRestMethod`

---

## Deploy-RolesPlan.ps1

### Purpose
Reads `roles-plan.json` and applies RBAC role assignment changes for managed identities created by policy assignments. Always run **after** `Deploy-PolicyPlan.ps1` so that the managed identity principal IDs exist.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PacEnvironmentSelector` | string | — | PAC environment |
| `DefinitionsRootFolder` | string | `$env:PAC_DEFINITIONS_FOLDER` or `./Definitions` | For environment lookup |
| `InputFolder` | string | `$env:PAC_INPUT_FOLDER` → `$env:PAC_OUTPUT_FOLDER` → `./Output` | Where to read plan file |
| `Interactive` | switch | false | Interactive mode |

### Inputs
- `{InputFolder}/plans-{pacSelector}/roles-plan.json`

### Outputs
- Azure RBAC changes (no local file output)
- Console log with counts: added / updated / removed

### Key Logic Flow
1. **Removal phase**: Remove role assignments in `roleAssignments.removed`; for cross-tenant assignments, parse the assignment ID from the description field
2. **Addition phase**: For each entry in `roleAssignments.added`:
   - If `principalId` not already known, call `Get-AzPolicyAssignmentRestMethod` to resolve the identity from the freshly-created assignment
   - Handles both `SystemAssigned` and `UserAssigned` identity types
   - Create role assignment via `Set-AzRoleAssignmentRestMethod`
3. **Update phase**: Apply any updated role assignments

### Cross-Tenant Support
When a policy assignment uses a managed identity in a different tenant (Lighthouse scenario), the role assignment is created in the managing tenant but the role ID is stored in the description of the assignment for later cleanup.

---

## Set-AzPolicyExemptionEpac.ps1

### Purpose
Manual utility to create or update a single policy exemption outside the plan-based deployment flow. Useful for emergency exemptions or one-off changes.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Scope` | string | Yes | Resource scope (e.g., `/subscriptions/{guid}/resourceGroups/{rg}`) |
| `Name` | string | Yes | Exemption name (used in resource ID) |
| `DisplayName` | string | Yes | Human-readable display name |
| `Description` | string | No (default: `description`) | Description of the exemption |
| `ExemptionCategory` | string | No (default: `Waiver`) | `Waiver` or `Mitigated` |
| `ExpiresOn` | datetime | No | Expiration date/time |
| `PolicyAssignmentId` | string | Yes | Full resource ID of the policy assignment to exempt from |
| `PolicyDefinitionReferenceIds` | string[] | No | Specific policy IDs within a policy set to exempt |
| `AssignmentScopeValidation` | string | No (default: `Default`) | Scope validation mode |
| `ResourceSelectors` | object | No | Resource selectors to filter exemption applicability |
| `Metadata` | object | No | Custom metadata key-value pairs |
| `ApiVersion` | string | No (default: `2022-07-01-preview`) | REST API version |

### Logic
Constructs the exemption resource ID as `{Scope}/providers/Microsoft.Authorization/policyExemptions/{Name}` and calls `Set-AzPolicyExemptionRestMethod`.

---

## Remove-AzPolicyExemptionEpac.ps1

### Purpose
Manual utility to delete a single policy exemption by scope and name.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Scope` | string | Yes | Scope where the exemption lives |
| `Name` | string | Yes | Exemption name |
| `ApiVersion` | string | No (default: `2022-07-01-preview`) | REST API version |

### Logic
Constructs the exemption resource ID and calls `Remove-AzResourceByIdRestMethod`.

---

## Pipeline Execution Order

```
CI/CD Pipeline
    │
    ├─ Plan Stage
    │     Build-DeploymentPlans.ps1
    │         → Outputs policy-plan.json, roles-plan.json
    │         → Sets deployPolicyChanges / deployRoleChanges flags
    │
    ├─ Deploy Policy Stage (conditional: deployPolicyChanges == 'yes')
    │     Deploy-PolicyPlan.ps1
    │         → Applies all policy/assignment/exemption changes
    │
    └─ Deploy Roles Stage (conditional: deployRoleChanges == 'yes')
          Deploy-RolesPlan.ps1
              → Applies RBAC role assignments for managed identities
```
