# EPAC HydrationKit

Located in `Scripts/HydrationKit/` (16 scripts). The HydrationKit is an interactive bootstrapping wizard that walks operators through initial EPAC configuration, management group hierarchy creation, and first-time deployment setup.

---

## Purpose

The HydrationKit solves the "blank slate" problem: when an organization has no EPAC setup, it provides a guided wizard that:
1. Asks configuration questions interactively
2. Connects to Azure and validates access
3. Creates or copies a management group hierarchy
4. Generates the `global-settings.jsonc` configuration
5. Imports existing Azure policies into EPAC definitions format
6. Scaffolds the definitions folder structure
7. Produces CI/CD pipeline files from the StarterKit

---

## Main Entry Point

### Install-HydrationEpac.ps1 (~86 KB)

The primary orchestrator. Handles the complete EPAC initialization workflow:

1. **Pre-flight validation**:
   - Checks Azure connection (`Test-HydrationConnection`)
   - Validates RBAC access (`Test-HydrationRbacAssignment`)
   - Checks module version (`Update-HydrationModuleToSupportedVersion`)

2. **Interactive Q&A** via `New-HydrationAnswerSet`:
   - Tenant ID and cloud type
   - Deployment root scope (management group or subscription)
   - PAC environment selectors (dev, prod)
   - Managed identity location
   - Desired state strategy
   - CI/CD pipeline type (ADO/GitHub Actions)
   - Branching flow (GitHub flow / Release flow)

3. **Hierarchy setup**:
   - Option A: Copy an existing management group hierarchy (`Copy-HydrationManagementGroupHierarchy`)
   - Option B: Create a CAF v3-aligned hierarchy (`New-HydrationCaf3Hierarchy`)
   - Option C: Use an existing hierarchy as-is

4. **Definitions scaffolding**:
   - Creates definitions folder structure (`New-HydrationDefinitionsFolder`)
   - Generates `global-settings.jsonc` (`New-HydrationGlobalSettingsFile`)
   - Configures PAC selectors (`New-HydrationAssignmentPacSelector`)
   - Imports existing policies from Azure (calls `Export-AzPolicyResources`)

5. **Pipeline setup**:
   - Copies appropriate pipeline templates from StarterKit
   - Configures service connection names
   - Generates answer file for replay

6. **Documentation generation**:
   - Creates initial policy documentation source files

---

## Deployment Plan Building

### Build-HydrationDeploymentPlans.ps1 (~30 KB)

A variant of `Build-DeploymentPlans.ps1` optimized for the hydration context:
- Uses `Build-HydrationPolicyPlan`, `Build-HydrationPolicySetPlan`, `Build-HydrationAssignmentPlan`
- Generates extended reporting for audit trails
- Uses `Write-Information` for logging (older pattern than the main scripts)
- Outputs the same `policy-plan.json` and `roles-plan.json` format

---

## Management Group Hierarchy Scripts

### New-HydrationCaf3Hierarchy.ps1
Creates a management group hierarchy aligned with Cloud Adoption Framework v3:
- Standard CAF structure: Platform, Landing Zones, Online, Corp, Sandboxes, Decommissioned
- Supports optional prefix/suffix for environment isolation
- Uses `New-HydrationManagementGroupChildren` recursively

### Copy-HydrationManagementGroupHierarchy.ps1
Duplicates an existing management group hierarchy with optional prefix/suffix:
- Reads source hierarchy via `Get-AzManagementGroupRestMethod` with `-Recurse`
- Creates child groups via `New-AzManagementGroup`
- Optionally moves subscriptions to the new hierarchy

### Remove-HydrationManagementGroupRecursively.ps1
Cleans up a management group hierarchy by recursively deleting children first, then parents.

### New-HydrationManagementGroupChildren
Internal helper: recursively creates management group children from a hierarchy definition object.

---

## Configuration Generators

### New-HydrationGlobalSettingsFile.ps1
Generates `global-settings.jsonc` from collected answers:
- Sets `pacOwnerId` (new GUID or from answers)
- Configures environment selectors (dev, prod)
- Sets `deploymentRootScope`, `tenantId`, `cloud`, `managedIdentityLocation`
- Applies desired state strategy

### New-HydrationDefinitionsFolder.ps1
Creates the standard definitions folder structure:
```
{DefinitionsRoot}/
├── policyDefinitions/
├── policySetDefinitions/
├── policyAssignments/
├── policyExemptions/
└── policyDocumentations/
```

### New-HydrationAssignmentPacSelector.ps1
Generates the initial assignment file with PAC environment scope mappings.

### New-HydrationPolicyDocumentationSourceFile.ps1
Creates an initial documentation spec file for policy documentation generation.

### New-FilteredExceptionFile.ps1
Creates exemption files filtered to a specific set of criteria.

---

## Interactive Q&A Infrastructure

### New-HydrationAnswerSet.ps1
Orchestrates the Q&A loop for a given `LoopId`:
1. Loads all questions via `Get-HydrationQuestionList`
2. Filters to questions matching the `LoopId`
3. Sorts questions by `questionIncrement`
4. For each question, calls the appropriate prompt function
5. Stores answers in the answer file via `New-HydrationAnswerFile`
6. Returns collected answers hashtable

### New-HydrationAnswerFile.ps1
Reads/writes the answer JSON file that persists Q&A responses for replay and audit.

### New-HydrationMultipleChoicePrompt.ps1
Renders an interactive selection menu with numbered options. Returns the selected value.

### New-HydrationContinuePrompt.ps1
Renders a yes/no confirmation prompt. Returns `$true` or `$false`.

### New-HydrationMenuResponse.ps1
Processes user input for menu-style prompts, validating against allowed values.

### New-HydrationSeparatorBlock.ps1
Renders a formatted separator/header block in the console for visual Q&A structure.

### Get-HydrationMessageBlock.ps1
Returns formatted message content for display in the Q&A flow.

### Get-HydrationQuestionList.ps1
Returns the embedded question definitions from `StarterKit/HydrationKit/questions.jsonc`. Each question entry contains:
- `loopId` — which Q&A loop it belongs to
- `questionIncrement` — ordering within the loop
- `questionText` — display text
- `questionType` — `multipleChoice`, `freeText`, `yesNo`
- `options` (for multipleChoice) — list of allowed values

---

## Validation Scripts

### Test-HydrationConnection.ps1
Validates Azure connection is active and returns the current context.

### Test-HydrationPath.ps1
Verifies that a directory path exists and is accessible.

### Test-HydrationManagementGroupName.ps1
Validates that a management group name exists in Azure.

### Test-HydrationRbacAssignment.ps1
Checks that the current identity has required RBAC permissions at the target scope.

### Test-HydrationCaf3Hierarchy.ps1
Validates that a management group hierarchy conforms to CAF v3 structure.

---

## Supporting Helpers

### Get-HydrationChildManagementGroupNameList.ps1
Returns a flat list of management group names under a parent group.

### Get-HydrationDefinitionSubfolderByContentId.ps1
Maps a policy content ID to the appropriate definitions subfolder.

### Get-HydrationEpacRepo.ps1
Returns metadata about the EPAC repository (used for version checks).

### Get-HydrationUserObjectId.ps1
Retrieves the current user's Azure AD object ID for RBAC assignment.

### Update-HydrationModuleToSupportedVersion.ps1
Checks if the installed EPAC module version is supported; prompts for update if not.

### Update-HydrationStarterKitAssignmentScope.ps1
Updates assignment scope values in StarterKit files to match the target environment.

### Copy-HydrationOrderedHashtable.ps1
Deep-copies an ordered hashtable (used for immutable Q&A answer snapshots).

### Export-HydrationObjectToJsonFile.ps1
Serializes a configuration object to a JSON file with consistent formatting.

### Write-HydrationLogFile.ps1
Appends structured audit log entries to the hydration log file (records every action taken).

### Join-HydrationHashtableToPath.ps1
Merges a configuration hashtable into a file path structure (used for generating nested config files).

### Remove-HydrationChildHierarchy.ps1
Removes child entries from a management group hierarchy definition object.

### New-HydrationChangeEntry.ps1
Creates a standardized change log entry for the hydration audit trail.

### Compare-HydrationMetadata.ps1
Compares two metadata objects for the hydration deployment plan builders (similar to `Confirm-MetadataMatches` but for hydration-specific patterns).

---

## Answer File Format

The hydration answer file (`hydration-answers.json`) stores all Q&A responses for audit and replay:

```json
{
  "tenantId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "cloud": "AzureCloud",
  "deploymentRootScope": "/providers/Microsoft.Management/managementGroups/...",
  "managedIdentityLocation": "eastus2",
  "strategy": "ownedOnly",
  "pipelineType": "GitHubActions",
  "branchingFlow": "GitHub",
  ...
}
```

---

## Hydration Flow (Simplified)

```
Install-HydrationEpac.ps1
    │
    ├─ Test-HydrationConnection / Test-HydrationRbacAssignment
    │
    ├─ New-HydrationAnswerSet (interactive Q&A)
    │     └─ Questions from questions.jsonc
    │
    ├─ Hierarchy creation
    │     ├─ New-HydrationCaf3Hierarchy (CAF v3 standard)
    │     └─ Copy-HydrationManagementGroupHierarchy (copy existing)
    │
    ├─ New-HydrationDefinitionsFolder
    ├─ New-HydrationGlobalSettingsFile
    ├─ New-HydrationAssignmentPacSelector
    │
    ├─ Export-AzPolicyResources (import existing policies)
    │
    ├─ Build-HydrationDeploymentPlans → Deploy-PolicyPlan → Deploy-RolesPlan
    │
    ├─ New-PipelinesFromStarterKit
    │
    └─ New-HydrationPolicyDocumentationSourceFile
```
