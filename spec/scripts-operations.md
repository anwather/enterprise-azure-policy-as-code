# EPAC Operations Scripts

Located in `Scripts/Operations/`. These scripts support day-to-day governance operations: reporting, exporting, remediating, and setting up EPAC environments.

---

## Build-PolicyDocumentation.ps1

### Purpose
Generates policy documentation from instruction files in `policyDocumentations/` by reading deployed policy resources from Azure. Produces CSV and JSON outputs suitable for IT, business, and compliance audiences.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DefinitionsRootFolder` | string | `$env:PAC_DEFINITIONS_FOLDER` / `./Definitions` | Definitions root |
| `OutputFolder` | string | `$env:PAC_OUTPUT_FOLDER` / `./Output` | Where to write documentation |
| `PacSelector` | string | — | PAC environment selector |
| `Interactive` | switch | true | Enable interactive mode |
| `WindowsNewLineCells` | switch | false | Format CSV cells with Windows newlines (for Excel) |
| `SuppressConfirmation` | switch | false | Skip deletion confirmation prompts |
| `IncludeManualPolicies` | switch | false | Include policies with `Manual` effect |
| `StrictMode` | switch | false | Fail on missing policy definitions |
| `OnlyCheckManagedAssignments` | switch | false | Only document PAC-managed assignments |

### Inputs
- Documentation spec files: `{DefinitionsRootFolder}/policyDocumentations/**/*.jsonc`
- Azure deployed policy resources (via `Get-AzPolicyResources`)

### Outputs
- `{OutputFolder}/policy-documentation/` — Policy documentation CSV and JSON files
- `{OutputFolder}/policy-documentation/services/` — Service-specific documentation subfolders

### Logic
Iterates through each documentation spec file. Each spec defines filters (by assignment name, scope, or metadata category). For each spec, retrieves deployed resources, resolves policy details via `Convert-PolicyResourcesToDetails`, and calls `Out-DocumentationForPolicyAssignments` or `Out-DocumentationForPolicySets`.

---

## Export-AzPolicyResources.ps1

### Purpose
Exports all Azure Policy resources from an EPAC environment in EPAC-compatible format for import into version control. Supports multiple operating modes for different CI/CD scenarios.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DefinitionsRootFolder` | string | — | Definitions root |
| `OutputFolder` | string | — | Output folder |
| `Interactive` | switch | true | Interactive mode |
| `IncludeChildScopes` | switch | false | Include policies from child scopes |
| `IncludeAutoAssigned` | switch | false | Include Defender for Cloud auto-assigned policies |
| `ExemptionFiles` | string | `csv` | Exemption output format: `none`, `csv`, `json` |
| `FileExtension` | string | `jsonc` | Output file extension: `json` or `jsonc` |
| `Mode` | string | `export` | See modes below |
| `InputPacSelector` | string | `*` | Limit to specific environment (default: all) |
| `SuppressEpacOutput` | switch | false | Skip EPAC format generation |

### Operating Modes

| Mode | Description |
|------|-------------|
| `export` | Connect to each EPAC environment and export in EPAC format |
| `collectRawFile` | Collect raw JSON data only (one tenant per run, for multi-tenant pipelines) |
| `exportFromRawFiles` | Read previously collected raw files and generate EPAC format |
| `exportRawToPipeline` | Export in EPAC format for downstream pipeline stages |
| `psrule` | Export in PSRule for Azure format |

### Outputs
- Policy definition files organized by category under `policyDefinitions/`
- Policy set definition files
- Assignment EPAC templates
- Exemption files (CSV or JSON)
- Policy ownership report CSV

---

## Export-NonComplianceReports.ps1

### Purpose
Queries Azure for all non-compliant resources and generates multi-view CSV reports for analysis and tracking.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PacEnvironmentSelector` | string | — | PAC environment |
| `DefinitionsRootFolder` | string | — | Definitions root |
| `OutputFolder` | string | — | Output folder |
| `Interactive` | switch | true | Interactive mode |
| `WindowsNewLineCells` | switch | false | Windows CSV formatting |
| `OnlyCheckManagedAssignments` | switch | false | Only check PAC-managed assignments |
| `PolicyDefinitionFilter` | string[] | — | Filter by policy names or IDs |
| `PolicySetDefinitionFilter` | string[] | — | Filter by policy set names or IDs |
| `PolicyAssignmentFilter` | string[] | — | Filter by assignment names or IDs |
| `PolicyEffectFilter` | string[] | — | Filter by effect (e.g., `deny`, `audit`) |
| `ExcludeManualPolicyEffect` | switch | false | Exclude `Manual` effect policies |
| `RemediationOnly` | switch | false | Only show remediable non-compliance |

### Outputs
Multiple CSV files per query:
- `*-summary.csv` — Aggregated counts by policy/resource
- `*-details.csv` — Full row-level non-compliance data

### Logic
Calls `Find-AzNonCompliantResources` with configured filters, then collates results by policy ID and resource ID. Generates management portal deep-links for quick resource navigation.

---

## Export-PolicyToEPAC.ps1

### Purpose
Exports a single policy definition or policy set from Azure, the ALZ GitHub repository, or built-in definitions to an EPAC-formatted file.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `PolicyDefinitionId` | string | Azure policy definition resource ID |
| `PolicySetDefinitionId` | string | Azure policy set definition resource ID |
| `ALZPolicyDefinitionId` | string | ALZ GitHub repository policy name |
| `ALZPolicySetDefinitionId` | string | ALZ GitHub repository policy set name |
| `OutputFolder` | string | Destination folder (default: `Output`) |
| `AutoCreateParameters` | switch | Auto-generate parameters (default: true) |
| `UseBuiltIn` | switch | Use built-in policy definitions (default: true) |
| `PacSelector` | string | EPAC environment for assignment scope |
| `GithubToken` | string | Token for GitHub API access |

### Outputs
- `{OutputFolder}/policyDefinitions/{policyName}.json`
- `{OutputFolder}/policySetDefinitions/{setName}.json`
- `{OutputFolder}/policyAssignments/{name}.jsonc` (assignment template)

### Logic
Validates source type (Azure vs ALZ vs GitHub), retrieves definition, strips deployment metadata (`pacOwnerId`, `createdBy`, `updatedOn`, etc.), and serializes to EPAC schema format.

---

## Get-AzExemptions.ps1

### Purpose
Exports all policy exemptions from an EPAC environment to JSON/JSONC and CSV files for audit tracking.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PacEnvironmentSelector` | string | — | PAC environment |
| `DefinitionsRootFolder` | string | — | Definitions root |
| `OutputFolder` | string | — | Output folder |
| `Interactive` | switch | true | Interactive mode |
| `FileExtension` | string | `json` | Output format: `json` or `jsonc` |
| `ActiveExemptionsOnly` | switch | false | Only export non-expired, non-orphaned exemptions |

### Outputs
- `{OutputFolder}/policyExemptions/*.json` — Exemption definition files
- `{OutputFolder}/policyExemptions/*.csv` — Exemption CSV report

---

## Get-AzPolicyAliasOutputCSV.ps1

### Purpose
Generates a reference CSV listing all Azure Policy property aliases, useful when writing custom policy rules.

### Behavior
Calls `Get-AzPolicyAlias`, flattens the output to a three-column CSV (namespace, resourcetype, propertyAlias), and writes `FullAliasesOutput.csv` to the current directory.

---

## New-AzPolicyReaderRole.ps1

### Purpose
Creates a custom Azure RBAC role "EPAC Resource Policy Reader" with read-only access to all policy-related resources needed for planning operations.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `PacEnvironmentSelector` | string | PAC environment (determines scope) |
| `DefinitionsRootFolder` | string | Definitions root |
| `Interactive` | switch | Interactive mode |

### Role Definition
- **Name**: EPAC Resource Policy Reader
- **Fixed GUID**: `2baa1a7c-6807-46af-8b16-5e9d03fba029`
- **Scope**: `deploymentRootScope` from the selected PAC environment
- **Permissions** (read-only): `Microsoft.Authorization/policyAssignments/read`, `policyDefinitions/read`, `policyExemptions/read`, `policySetDefinitions/read`, `roleAssignments/read`, `policyInsights/*/read`, management groups, subscriptions, resource groups

---

## New-AzRemediationTasks.ps1

### Purpose
Creates Azure Policy remediation tasks for all non-compliant resources under `deployIfNotExists` or `Modify` policies, enabling automated compliance correction.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PacEnvironmentSelector` | string | — | PAC environment |
| `DefinitionsRootFolder` | string | — | Definitions root |
| `Interactive` | switch | true | Interactive mode |
| `OnlyCheckManagedAssignments` | switch | false | Only remediate PAC-managed assignments |
| `PolicyDefinitionFilter` | string[] | — | Filter by policy names/IDs |
| `PolicySetDefinitionFilter` | string[] | — | Filter by policy set names/IDs |
| `PolicyAssignmentFilter` | string[] | — | Filter by assignment names/IDs |
| `PolicyEffectFilter` | string[] | — | Filter by effect |
| `NoWait` | switch | false | Do not wait for task completion |
| `TestRun` | switch | false | Show what would be remediated (dry run) |
| `OnlyDefaultEnforcementMode` | switch | false | Only remediate `Default` enforcement mode assignments |

### Logic
1. Call `Find-AzNonCompliantResources` with remediation filter
2. Group non-compliance by assignment ID and policy definition reference ID
3. For each group, call `New-AzRemediationDeployment` with:
   - `ResourceDiscoveryMode = ExistingNonCompliant`
   - `ResourceCount = 50000`
   - Unique task name (GUID-based)
4. Supports up to 30 concurrent remediation tasks
5. Outputs failed task list as JSON for pipeline error handling

---

## New-EPACGlobalSettings.ps1

### Purpose
Scaffolds a new `global-settings.jsonc` file for initial EPAC setup.

### Parameters

| Parameter | Position | Required | Description |
|-----------|----------|----------|-------------|
| `ManagedIdentityLocation` | 0 | Yes | Azure region for managed identities |
| `TenantId` | 1 | Yes | Azure tenant GUID |
| `DefinitionsRootFolder` | 2 | Yes | Path to create definitions root |
| `DeploymentRootScope` | 3 | Yes | Root scope in format `/providers/Microsoft.Management/managementGroups/{name}` |

### Logic
Validates inputs, generates a new GUID for `pacOwnerId`, creates the JSON template referencing the official EPAC schema, and writes to `{DefinitionsRootFolder}/global-settings.jsonc`.

---

## New-EPACPolicyAssignmentDefinition.ps1

### Purpose
Exports a deployed policy assignment from Azure to an EPAC-formatted assignment template file.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `PolicyAssignmentId` | Yes | Full Azure resource ID of the assignment |
| `OutputFolder` | No | Destination folder |

### Outputs
An EPAC assignment template file with `assignment` (name, displayName, description), `definitionEntry` (policyName or policySetName), and `parameters` sections.

---

## New-EPACPolicyDefinition.ps1

### Purpose
Exports a deployed policy or policy set definition to EPAC-formatted JSON.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `PolicyDefinitionId` | Yes | Full Azure resource ID (must contain `/providers/`) |
| `OutputFolder` | No | Destination folder |

### Outputs
EPAC-formatted policy definition JSON file with `name`, `displayName`, `mode`, `description`, `metadata`, `parameters`, and `policyRule` sections.

---

## New-PipelinesFromStarterKit.ps1

### Purpose
Copies pre-built CI/CD pipeline YAML templates from the StarterKit to the appropriate pipeline folders.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `StarterKitFolder` | string | `./StarterKit` | Path to StarterKit |
| `PipelinesFolder` | string | auto | Target pipeline folder |
| `PipelineType` | enum | `GitHubActions` | `AzureDevOps` or `GitHubActions` |
| `BranchingFlow` | enum | `Release` | `Release` or `GitHub` |
| `ScriptType` | enum | `Module` | `Module` or `Scripts` |
| `SuppressConfirm` | switch | false | Skip confirmation prompts |

### Outputs
- **GitHub Actions**: Copies to `.github/workflows/` and `.github/workflows/templates/`
- **Azure DevOps**: Copies to `Pipelines/` and `Pipelines/templates/`

---

## Convert-MarkdownGitHubAlerts.ps1 and New-AzureDevOpsBug.ps1 / New-GitHubIssue.ps1

These are supporting utilities:
- **Convert-MarkdownGitHubAlerts.ps1**: Converts GitHub-flavored markdown alert syntax for MkDocs rendering
- **New-AzureDevOpsBug.ps1**: Creates an Azure DevOps work item from pipeline output (used in exemption pipeline)
- **New-GitHubIssue.ps1**: Creates a GitHub Issue from pipeline output
