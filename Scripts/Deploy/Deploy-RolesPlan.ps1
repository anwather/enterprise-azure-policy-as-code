#Requires -PSEdition Core
<#
.SYNOPSIS 
    Deploys Role assignments from a plan file.  

.PARAMETER PacEnvironmentSelector
    Defines which Policy as Code (PAC) environment we are using, if omitted, the script prompts for a value. The values are read from `$DefinitionsRootFolder/global-settings.jsonc.

.PARAMETER DefinitionsRootFolder
    Definitions folder path. Defaults to environment variable `$env:PAC_DEFINITIONS_FOLDER or './Definitions'.

.PARAMETER InputFolder
    Input folder path for plan files. Defaults to environment variable `$env:PAC_INPUT_FOLDER, `$env:PAC_OUTPUT_FOLDER or './Output'.

.PARAMETER Interactive
    Use switch to indicate interactive use

.EXAMPLE
    Deploy-RolesPlan.ps1 -PacEnvironmentSelector "dev" -DefinitionsRootFolder "C:\PAC\Definitions" -InputFolder "C:\PAC\Output" -Interactive
    Deploys Role assignments from a plan file.

.EXAMPLE
    Deploy-RolesPlan.ps1 -Interactive
    Deploys Role assignments from a plan file. The script prompts for the PAC environment and uses the default definitions and input folders.

.LINK
    https://azure.github.io/enterprise-azure-policy-as-code/#deployment-scripts

#>

[CmdletBinding()]
param (
    [parameter(HelpMessage = "Defines which Policy as Code (PAC) environment we are using, if omitted, the script prompts for a value. The values are read from `$DefinitionsRootFolder/global-settings.jsonc.",
        Position = 0
    )]
    [string] $PacEnvironmentSelector,

    [Parameter(HelpMessage = "Definitions folder path. Defaults to environment variable `$env:PAC_DEFINITIONS_FOLDER or './Definitions'.")]
    [string]$DefinitionsRootFolder,

    [Parameter(HelpMessage = "Input folder path for plan files. Defaults to environment variable `$env:PAC_INPUT_FOLDER, `$env:PAC_OUTPUT_FOLDER or './Output'.")]
    [string]$InputFolder,

    [Parameter(HelpMessage = "Use switch to indicate interactive use")]
    [switch] $Interactive
)

$PSDefaultParameterValues = @{
    "Write-Information:InformationVariable" = "+global:epacInfoStream"
}

# Dot Source Helper Scripts
. "$PSScriptRoot/../Helpers/Add-HelperScripts.ps1"

$scriptStartTime = Get-Date

# Display welcome header
Write-ModernHeader -Title "Enterprise Policy as Code (EPAC)" -Subtitle "Deploying Role Assignments Plan" -HeaderColor Magenta -SubtitleColor DarkMagenta

$pacEnvironment = Select-PacEnvironment $PacEnvironmentSelector -DefinitionsRootFolder $DefinitionsRootFolder -InputFolder $InputFolder  -Interactive $Interactive
$null = Set-AzCloudTenantSubscription -Cloud $pacEnvironment.cloud -TenantId $pacEnvironment.tenantId -Interactive $pacEnvironment.interactive -DeploymentDefaultContext $pacEnvironment.defaultContext

# Display environment information
Write-ModernSection -Title "Environment Configuration" -Color Cyan
Write-ModernStatus -Message "PAC Environment: $($pacEnvironment.pacSelector)" -Status "info" -Indent 2
Write-ModernStatus -Message "Deployment Root: $($pacEnvironment.deploymentRootScope)" -Status "info" -Indent 2
Write-ModernStatus -Message "Input Folder: $InputFolder" -Status "info" -Indent 2

# Telemetry
if ($pacEnvironment.telemetryEnabled) {
    Write-ModernStatus -Message "Telemetry is enabled" -Status "info" -Indent 2
    Submit-EPACTelemetry -Cuapid "pid-cf031290-b7d4-48ef-9ff5-4dcd7bff8c6c" -DeploymentRootScope $pacEnvironment.deploymentRootScope
}
else {
    Write-ModernStatus -Message "Telemetry is disabled" -Status "info" -Indent 2
}

$plan = Get-DeploymentPlan -PlanFile $pacEnvironment.rolesPlanInputFile -AsHashTable

if ($null -eq $plan) {
    Write-ModernSection -Title "Plan File Not Found" -Color Red
    Write-ModernStatus -Message "Plan file $($pacEnvironment.rolesPlanInputFile) does not exist" -Status "error" -Indent 2
    Write-ModernStatus -Message "Role assignments deployment will be skipped" -Status "warning" -Indent 2
    return
}

Write-ModernSection -Title "Role Assignment Plan Overview" -Color Blue
Write-ModernStatus -Message "Plan file: $($pacEnvironment.rolesPlanInputFile)" -Status "info" -Indent 2
Write-ModernStatus -Message "Plan created: $($plan.createdOn)" -Status "info" -Indent 2

if ($plan.roleAssignments.removed.psbase.Count -gt 0) {
    Write-ModernSection -Title "Removing Obsolete Role Assignments ($($plan.roleAssignments.removed.psbase.Count) items)" -Color Red
    foreach ($roleAssignment in $plan.roleAssignments.removed) {
        $roleDisplayText = "`n      Principal: $($roleAssignment.principalId)`n      Role: $($roleAssignment.roleDisplayName)`n      Scope: $($roleAssignment.scope)"
        Write-ModernStatus -Message "Removing Role Assignment: $roleDisplayText" -Status "pending" -Indent 2
        if (!$roleAssignment.crossTenant) {
            $null = Remove-AzRoleAssignmentRestMethod -RoleAssignmentId $roleAssignment.id -ApiVersion $pacEnvironment.apiVersions.roleAssignments
        }
        else {
            if ($roleAssignment.description -match "'(/subscriptions/[^']+)'") {
                $assignmentId = $matches[1]
            }
            else {
                Write-Error "AssignmentId not found in description '$($roleAssignment.description)' for cross tenant role removal.  Please report as a bug"
            }
            $null = Remove-AzRoleAssignmentRestMethod -RoleAssignmentId $roleAssignment.id -TenantId $pacEnvironment.managedTenantId -ApiVersion $pacEnvironment.apiVersions.roleAssignments -AssignmentId $assignmentId
        }
    }
}

if ($plan.roleAssignments.added.psbase.Count -gt 0) {
    Write-ModernSection -Title "Adding New Role Assignments ($($plan.roleAssignments.added.psbase.Count) items)" -Color Green

    # Get identities for policy assignments from plan or by calling the REST API to retrieve the Policy Assignment
    $assignmentById = @{}
    foreach ($roleAssignment in $plan.roleAssignments.added) {
        $principalId = $roleAssignment.properties.principalId
        $policyAssignmentId = $roleAssignment.assignmentId
        if ($null -eq $principalId) {
            $identity = $null
            $principalId = ""
            if ($assignmentById.ContainsKey($policyAssignmentId)) {
                $principalId = $assignmentById[$policyAssignmentId]
            }
            else {
                Write-ModernStatus -Message "Resolving identity for assignment: $policyAssignmentId" -Status "pending" -Indent 2
                $policyAssignment = Get-AzPolicyAssignmentRestMethod -AssignmentId $policyAssignmentId -ApiVersion $pacEnvironment.apiVersions.policyAssignments
                $identity = $policyAssignment.identity
                if ($identity -and $identity.type -ne "None") {
                    $principalId = ""
                    if ($identity.type -eq "SystemAssigned") {
                        $principalId = $identity.principalId
                    }
                    else {
                        $userAssignedIdentityId = $identity.userAssignedIdentities.PSObject.Properties.Name
                        $principalId = $identity.userAssignedIdentities.$userAssignedIdentityId.principalId
                    }
                }
                else {
                    Write-Error "Identity not found for assignment '$($policyAssignmentId)'" -ErrorAction Stop
                }
                $null = $assignmentById.Add($policyAssignmentId, $principalId)
            }
            $roleAssignment.properties.principalId = $principalId
        }
        elseif (-not $assignmentById.ContainsKey($policyAssignmentId)) {
            $null = $assignmentById.Add($policyAssignmentId, $principalId)
        }
        Write-ModernStatus -Message "Creating role assignment:`n      Principal: $principalId`n      Role: $($roleAssignment.roleDisplayName)`n      Scope: $($roleAssignment.scope)" -Status "pending" -Indent 2
        Set-AzRoleAssignmentRestMethod -RoleAssignment $roleAssignment -PacEnvironment $pacEnvironment
    }
}
if ($plan.roleAssignments.updated.psbase.Count -gt 0) {
    Write-ModernSection -Title "Updating Role Assignments ($($plan.roleAssignments.updated.psbase.Count) items)" -Color Yellow

    # Get identities for policy assignments from plan or by calling the REST API to retrieve the Policy Assignment
    foreach ($roleAssignment in $plan.roleAssignments.updated) {
        Write-ModernStatus -Message "Updating role assignment:`n      Principal: $principalId`n      Role: $($roleAssignment.roleDisplayName)`n      Scope: $($roleAssignment.scope)" -Status "pending" -Indent 2
        Set-AzRoleAssignmentRestMethod -RoleAssignment $roleAssignment -PacEnvironment $pacEnvironment
    }
}

# Calculate execution time
$scriptEndTime = Get-Date
$executionTime = $scriptEndTime - $scriptStartTime
    
# Display completion summary
Write-ModernSection -Title "Deployment Complete" -Color Green
Write-ModernStatus -Message "Plan file: $($pacEnvironment.rolesPlanInputFile)" -Status "success" -Indent 2
Write-ModernCountSummary -Title "Role Assignment Changes" -Added $plan.roleAssignments.added.psbase.Count -Updated $plan.roleAssignments.updated.psbase.Count -Removed $plan.roleAssignments.removed.psbase.Count -Indent 2
Write-ModernStatus -Message "Execution time: $($executionTime.ToString('mm\:ss'))" -Status "info" -Indent 2
Write-ModernStatus -Message "All role assignments have been successfully deployed" -Status "success" -Indent 2