# EPAC Cloud Adoption Framework Integration

Located in `Scripts/CloudAdoptionFramework/` (2 scripts). These scripts integrate EPAC with Microsoft's Azure Landing Zones (ALZ) ecosystem, which includes multiple governance platforms: ALZ (Azure Landing Zones), FSI (Financial Services Industry), AMBA (Azure Monitor Baseline Alerts), and SLZ (Sovereign Landing Zone).

---

## Overview

The CAF integration allows organizations to:
1. **Derive their management group hierarchy** from the standard ALZ management group structure
2. **Synchronize policy definitions and assignments** from the ALZ Library — Microsoft's curated policy repository — directly into EPAC's definitions format
3. **Stay current** with Microsoft's evolving policy recommendations by re-running the sync against new ALZ Library tags

---

## New-ALZPolicyDefaultStructure.ps1

### Purpose
Creates a `policy-structure.json` file that describes the management group hierarchy and default parameter values aligned with a chosen ALZ platform. This file is consumed by the HydrationKit and assignment plan builders to understand the organizational scope structure.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `OutputFolder` | string | `./Output` | Where to write the structure file |
| `PlatformType` | enum | `alz` | `alz`, `fsi`, `amba`, or `slz` |
| `RootManagementGroupName` | string | — | The root management group ID in your tenant |
| `IncludeResourceGroups` | switch | false | Include resource group level in the structure |

### Supported Platform Tags

| Platform | Latest Supported Tag |
|----------|---------------------|
| ALZ | `platform/alz/2026.01.3` |
| FSI | `platform/fsi/2025.03.0` |
| AMBA | `platform/amba/2025.11.0` |
| SLZ | `platform/slz/2026.02.1` |

### Logic
1. Clones the ALZ Library GitHub repository at the specified platform tag
2. Reads the architecture definition (management group names and relationships)
3. Builds a `policy-structure.json` with:
   - `managementGroupNameMappings`: display name → internal ID
   - `defaultParameterValues`: default parameter values from the ALZ platform
   - `enforcementMode`: default enforcement mode
4. Outputs to `{OutputFolder}/policy-structure.json`

### Output: policy-structure.json Format
```json
{
  "$schema": "https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/.../Schemas/policy-structure-schema.json",
  "managementGroupNameMappings": {
    "Intermediate Root": "mg-contoso",
    "Platform": "mg-contoso-platform",
    "Landing Zones": "mg-contoso-landingzones",
    ...
  },
  "defaultParameterValues": {
    "effect-ACRContainerImages": "Audit",
    "effect-AppServiceApps": "AuditIfNotExists",
    ...
  },
  "enforcementMode": "Default"
}
```

---

## Sync-ALZPolicyFromLibrary.ps1

### Purpose
Synchronizes policy definitions and policy set definitions from the ALZ Library into the EPAC definitions folder, keeping EPAC aligned with Microsoft's curated policy content.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DefinitionsRootFolder` | string | `$env:PAC_DEFINITIONS_FOLDER` / `./Definitions` | Target definitions folder |
| `PlatformType` | enum | `alz` | `alz`, `fsi`, `amba`, or `slz` |
| `LibraryTag` | string | (latest for platform) | Specific ALZ Library tag to sync from |
| `IncludeAMBAExtended` | switch | false | Include extended AMBA monitoring/alerting policies |
| `IncludeGuardrails` | switch | false | Include guardrail assignment templates |

### Logic
1. **Repository cloning**: Clones (or downloads a ZIP of) the ALZ Library repository at the specified tag from GitHub
2. **Policy definition extraction**:
   - Reads all `*.json` policy definition files from the library
   - Converts from ALZ Library format to EPAC format
   - Organizes by category into `policyDefinitions/{category}/` subfolders
   - Writes individual JSON files, one per policy
3. **Policy set definition extraction**:
   - Reads all `*.json` policy set (initiative) files from the library
   - Converts to EPAC format
   - Writes to `policySetDefinitions/{category}/`
4. **Optional AMBA extended policies**:
   - Includes additional monitoring/alerting policy sets when `IncludeAMBAExtended` is set
5. **Optional guardrail assignments**:
   - Generates assignment template files from ALZ Library assignment definitions
   - Supports assignment overrides via configuration

### ALZ Library Format vs. EPAC Format

**ALZ Library policy definition (`archetype_definition.json`):**
```json
{
  "type": "Microsoft.Authorization/policyDefinitions",
  "apiVersion": "2021-06-01",
  "name": "Deny-PublicEndpoints",
  "properties": {
    "policyType": "Custom",
    "displayName": "Deny access using private endpoints",
    ...
  }
}
```

**EPAC format (after conversion):**
```json
{
  "name": "Deny-PublicEndpoints",
  "displayName": "Deny access using private endpoints",
  "mode": "All",
  "metadata": { "category": "Network", "version": "1.0.0" },
  "parameters": { ... },
  "policyRule": { ... }
}
```

### Telemetry
Calls `Submit-EPACTelemetry` to record the sync operation for Customer Usage Attribution.

---

## Integration Workflow

The typical CAF integration workflow:

```
1. Initial setup:
   New-ALZPolicyDefaultStructure -PlatformType alz -RootManagementGroupName mg-contoso
       → Creates policy-structure.json (hierarchy + defaults)

2. Initial policy sync:
   Sync-ALZPolicyFromLibrary -PlatformType alz -DefinitionsRootFolder ./Definitions
       → Creates policyDefinitions/ALZ/**/*.json
       → Creates policySetDefinitions/ALZ/**/*.json

3. Ongoing updates (run periodically as new ALZ tags are released):
   Sync-ALZPolicyFromLibrary -PlatformType alz -LibraryTag platform/alz/2026.01.3
       → Overwrites existing ALZ policy files with updated versions
       → New policies are added, removed policies are... (requires manual review)

4. EPAC then manages these policies through the standard Build-Deploy pipeline
```

---

## ALZ Library Sources

| Platform | GitHub Org | Repository |
|----------|-----------|-----------|
| ALZ | `Azure` | `Azure/Enterprise-Scale` |
| FSI | `Azure` | `Azure/Enterprise-Scale` (FSI branch) |
| AMBA | `Azure` | `azure-monitor-baseline-alerts` |
| SLZ | `Azure` | `Azure/sovereign-landing-zone` |

---

## Notes for Future Development

- The ALZ Library evolves continuously; new policy versions are released multiple times per year
- The `LibraryTag` parameter allows pinning to a specific version for reproducibility
- When syncing, EPAC does not automatically delete policies removed from the ALZ Library — this requires manual review to avoid breaking existing assignments
- The `IncludeGuardrails` flag is advanced usage; guardrail assignments often require customization of parameters and scopes after import
