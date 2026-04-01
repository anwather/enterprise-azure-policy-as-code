# EPAC PowerShell Module

## Location

```
Module/
├── EnterprisePolicyAsCode.prerelease.psd1   ← Pre-release manifest template
├── EnterprisePolicyAsCode.release.psd1      ← Release manifest template
├── EnterprisePolicyAsCode/
│   └── EnterprisePolicyAsCode.psm1          ← Module root
└── build.ps1                                ← Build script (assembles the publishable module)
```

## Module Root (EnterprisePolicyAsCode.psm1)

The `.psm1` does only three things:

1. Defines a private `Import-ModuleFile` helper that dot-sources (or `InvokeScript`-executes) a given `.ps1` file.
2. Iterates `internal/functions/**/*.ps1` and dot-sources each (private helpers, not exported).
3. Iterates `functions/**/*.ps1`, dot-sources each, and calls `Export-ModuleMember $function.BaseName` for every file — thus **the file name is the exported function name**.

```powershell
foreach ($function in (Get-ChildItem "$ModuleRoot\internal\functions" -Recurse -File -Filter "*.ps1")) {
    . Import-ModuleFile -Path $function.FullName
}
foreach ($function in (Get-ChildItem "$ModuleRoot\functions" -Recurse -File -Filter "*.ps1")) {
    . Import-ModuleFile -Path $function.FullName
    Export-ModuleMember $function.BaseName
}
```

## Module Manifests

Both `*.psd1` files are templates (the `ModuleVersion` field is intentionally empty `''`); the `build.ps1` script stamps the correct version before publishing.

| Property | Value |
|----------|-------|
| GUID | `197a34e5-115d-4c15-a593-b004228be78b` |
| Author | Microsoft Corporation |
| MinPowerShellVersion | 7.0 |
| LicenseUri | GitHub LICENSE file |
| ProjectUri | GitHub repo |
| IconUri | `Docs/Images/epac_svg.svg` |

## Build Process (build.ps1)

The build script (`Module/build.ps1`):
1. Copies `Scripts/Deploy/*.ps1` → `Module/EnterprisePolicyAsCode/functions/`
2. Copies `Scripts/Operations/*.ps1` → `Module/EnterprisePolicyAsCode/functions/`
3. Copies `Scripts/Helpers/**/*.ps1` → `Module/EnterprisePolicyAsCode/internal/functions/`
4. Stamps the version number into the manifest
5. The result is a self-contained module folder ready for `Publish-Module`

## Public Functions (exported from the module)

The public functions exported by the module are the top-level deploy and operations scripts:

**Deploy functions:**
- `Build-DeploymentPlans`
- `Deploy-PolicyPlan`
- `Deploy-RolesPlan`
- `Set-AzPolicyExemptionEpac`
- `Remove-AzPolicyExemptionEpac`

**Operations functions:**
- `Build-PolicyDocumentation`
- `Export-AzPolicyResources`
- `Export-NonComplianceReports`
- `Export-PolicyToEPAC`
- `Get-AzExemptions`
- `Get-AzPolicyAliasOutputCSV`
- `New-AzPolicyReaderRole`
- `New-AzRemediationTasks`
- `New-AzureDevOpsBug`
- `New-EPACGlobalSettings`
- `New-EPACPolicyAssignmentDefinition`
- `New-EPACPolicyDefinition`
- `New-GitHubIssue`
- `New-PipelinesFromStarterKit`

## Module vs. Scripts Usage

The same functionality is available in two modes:

| Mode | When Used | How Loaded |
|------|-----------|-----------|
| **Module** | CI/CD pipelines that `Install-Module EnterprisePolicyAsCode` | `Import-Module EnterprisePolicyAsCode` |
| **Scripts** | Local development or custom pipelines | `Add-HelperScripts.ps1` dot-sources helpers, then top-level script runs |

In script mode, `Add-HelperScripts.ps1` dot-sources every file in `Scripts/Helpers/` and `Scripts/Helpers/RestMethods/`, making all helper functions available in the calling scope.

## Publishing

The GitHub Actions workflow `.github/workflows/automated-publish.yaml` fires on every GitHub Release event and publishes the module to the PowerShell Gallery using a NuGet API key stored as a repository secret.
