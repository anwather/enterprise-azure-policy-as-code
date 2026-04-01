# EPAC Configuration

## global-settings.jsonc

The primary configuration file that defines all EPAC environments. Located at `{DefinitionsRootFolder}/global-settings.jsonc`.

### Root Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `pacOwnerId` | string (GUID) | Yes | Unique identifier for this EPAC instance; embedded in `metadata.pacOwnerId` of every managed resource |
| `telemetryOptOut` | boolean | No (default: false) | Disable Customer Usage Attribution telemetry |
| `pacEnvironments` | array | Yes | One or more environment definitions |

### pacEnvironments Entry

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `pacSelector` | string | Yes | Short identifier (e.g., `EPAC-DEV`, `Tenant`); must be lowercase; correlates to folder names and CI/CD parameters |
| `cloud` | enum | Yes | `AzureCloud`, `AzureChinaCloud`, `AzureUSGovernment`, `AzureGermanCloud` |
| `tenantId` | string (GUID) | Yes | Entra ID tenant GUID |
| `deploymentRootScope` | string | Yes | Absolute scope: `/providers/Microsoft.Management/managementGroups/{name}` or `/subscriptions/{guid}` |
| `managedIdentityLocation` | string | Yes | Azure region for system-assigned managed identities (e.g., `eastus2`) |
| `desiredState` | object | Yes | See below |
| `deployedBy` | string | No | Custom metadata tag; defaults to `epac/{pacOwnerId}/{pacSelector}` |
| `managedTenantId` | string | No | Target tenant for Lighthouse/multi-tenant deployments |
| `defaultContext` | string | No | Subscription name or ID for Azure Resource Graph queries |
| `globalNotScopes` | string[] | No | Resource IDs automatically excluded from every assignment scope |
| `skipResourceValidationForExemptions` | boolean | No (default: false) | Skip resource existence validation for exemptions |

### desiredState Object

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `strategy` | enum | Yes | `full` (manage + delete unmanaged) or `ownedOnly` (only manage owned resources) |
| `keepDfcSecurityAssignments` | boolean | Yes | Preserve Microsoft Defender for Cloud security assignments |
| `keepDfcPlanAssignments` | boolean | No (default: true) | Preserve Defender-deployed plan assignments |
| `cleanupObsoleteExemptions` | boolean | No | Remove expired/orphaned exemptions |
| `doNotDisableDeprecatedPolicies` | boolean | No | Do not disable deprecated policies |
| `excludedScopes` | string[] | No | Scopes to exclude; supports `*` wildcards |
| `excludedPolicyDefinitions` | string[] | No | Policy definition IDs protected from reconciliation |
| `excludedPolicySetDefinitions` | string[] | No | Policy set definition IDs protected |
| `excludedPolicyAssignments` | string[] | No | Policy assignment IDs protected |
| `excludeSubscriptions` | boolean | No (default: false) | Exclude all subscriptions from management |

### Minimal Example

```jsonc
{
  "pacOwnerId": "11111111-2222-3333-4444-555555555555",
  "pacEnvironments": [
    {
      "pacSelector": "EPAC-DEV",
      "cloud": "AzureCloud",
      "tenantId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "deploymentRootScope": "/providers/Microsoft.Management/managementGroups/epac-dev",
      "managedIdentityLocation": "eastus2",
      "desiredState": {
        "strategy": "ownedOnly",
        "keepDfcSecurityAssignments": true
      }
    }
  ]
}
```

---

## Definitions Folder Structure

```
Definitions/                          ← DefinitionsRootFolder (env: PAC_DEFINITIONS_FOLDER)
├── global-settings.jsonc             ← Environment config (schema: global-settings-schema.json)
├── policyDefinitions/                ← Custom policy definitions
│   └── {category}/
│       └── {policyName}.json         ← (schema: policy-definition-schema.json)
├── policySetDefinitions/             ← Custom policy set definitions (initiatives)
│   └── {category}/
│       └── {setName}.jsonc           ← (schema: policy-set-definition-schema.json)
├── policyAssignments/                ← Assignment tree
│   └── {rootNode}.jsonc              ← (schema: policy-assignment-schema.json)
├── policyExemptions/
│   └── {pacSelector}/                ← One folder per environment selector
│       └── {exemptions}.jsonc        ← (schema: policy-exemption-schema.json)
└── policyDocumentations/             ← Documentation generation instructions
    └── {docConfig}.jsonc             ← (schema: policy-documentation-schema.json)
```

The folder paths are resolved by `Get-PacFolders`:
- `policyDefinitionsFolder` → `{DefinitionsRootFolder}/policyDefinitions`
- `policySetDefinitionsFolder` → `{DefinitionsRootFolder}/policySetDefinitions`
- `policyAssignmentsFolder` → `{DefinitionsRootFolder}/policyAssignments`
- `policyExemptionsFolder` → `{DefinitionsRootFolder}/policyExemptions`
- `policyDocumentationsFolder` → `{DefinitionsRootFolder}/policyDocumentations`

---

## Output / Plan Folder Structure

```
Output/                               ← OutputFolder / InputFolder (env: PAC_OUTPUT_FOLDER / PAC_INPUT_FOLDER)
└── plans-{pacSelector}/
    ├── policy-plan.json              ← Policy deployment plan
    └── roles-plan.json               ← Role assignments deployment plan
```

---

## JSON Schemas (Schemas/)

### global-settings-schema.json (~180 lines)
Validates `global-settings.jsonc`. Key constraints:
- `pacOwnerId` must be a non-empty string
- `pacEnvironments` must be a non-empty array
- Each environment entry requires `pacSelector`, `cloud`, `tenantId`, `deploymentRootScope`, `managedIdentityLocation`, `desiredState`
- `desiredState.strategy` must be `full` or `ownedOnly`
- `cloud` must be one of the four allowed cloud enum values

### policy-definition-schema.json (~151 lines)
Validates individual policy definition files. Key constraints:
- Required: `displayName`, `mode`, `policyRule`
- `mode` must be `All`, `Indexed`, or `Microsoft.{provider}.{resourceType}`
- `metadata` may include `category`, `version`, `preview`, `deprecated`
- `parameters` is a key→definition map with `type`, `defaultValue`, `allowedValues`, `metadata`

### policy-set-definition-schema.json (~134 lines)
Validates policy set (initiative) definition files. Key constraints:
- Required: `displayName`, `policyDefinitions`
- `policyDefinitions` array entries require `policyDefinitionId` and `policyDefinitionReferenceId`
- Supports `groupDefinitions` for grouping policies within the set

### policy-assignment-schema.json (~481 lines)
The most complex schema. Validates assignment tree nodes. Key structures:
- Root and child nodes both require `nodeName`
- Leaf nodes require `definitionEntry` (or `definitionEntryList`)
- `definitionEntry` contains: `policyName`/`policySetName`/`policyId`/`policySetId` (one of four)
- `assignment` block: `name` (≤24 chars), `displayName` (≤128 chars), `description`
- `scope` is a map from `{pacSelector}` to array of scope strings
- `parameters` is a map from parameter name to value or `{value: X}`
- `overrides` for modifying effect/parameters without redeploying
- `resourceSelectors` for targeting specific resource types
- `nonComplianceMessages` for custom non-compliance messages
- `managedIdentity` block: `systemAssigned` or `userAssigned` with `userAssignedIdentityId`
- `enforcementMode`: `Default` or `DoNotEnforce`
- `children` array for hierarchical nesting

### policy-exemption-schema.json (~116 lines)
Validates exemption definition files. Key constraints:
- Required: `name`, `displayName`, `exemptionCategory`, `scope`, `policyAssignmentId`
- `exemptionCategory`: `Waiver` or `Mitigated`
- Optional: `expiresOn` (ISO 8601 date), `policyDefinitionReferenceIds`, `resourceSelectors`, `metadata`

### policy-documentation-schema.json (~371 lines)
Validates documentation generation config. Key structures:
- `documentAssignments` array: each entry specifies assignment filters and output format
- `documentPolicySets` array: for documenting specific policy sets
- Filter options: by assignment names, scopes, metadata categories

### policy-structure-schema.json (~373 lines)
Validates management group hierarchy config used by the HydrationKit / CAF integration. Key structures:
- `managementGroupNameMappings`: display name → internal ID mappings
- `defaultParameterValues`: default parameter values across the hierarchy
- `enforcementMode`: hierarchy-wide enforcement setting

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PAC_DEFINITIONS_FOLDER` | `./Definitions` | Path to definitions root folder |
| `PAC_OUTPUT_FOLDER` | `./Output` | Path to write plan files |
| `PAC_INPUT_FOLDER` | `$PAC_OUTPUT_FOLDER` | Path to read plan files (defaults to output folder) |

---

## API Version Matrix

API versions differ by cloud environment and are set in `Select-PacEnvironment`:

| Resource | AzureCloud | AzureChinaCloud | AzureUSGovernment |
|----------|-----------|-----------------|-------------------|
| policyDefinitions | 2023-04-01 | 2021-06-01 | 2023-04-01 |
| policySetDefinitions | 2023-04-01 | 2023-04-01 | 2023-04-01 |
| policyAssignments | 2023-04-01 | 2022-06-01 | 2023-04-01 |
| policyExemptions | 2022-07-01-preview | 2022-07-01-preview | 2024-12-01-preview |
| roleAssignments | 2022-04-01 | 2022-04-01 | 2022-04-01 |
