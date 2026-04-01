# EPAC CI/CD Pipelines

EPAC ships with a comprehensive set of CI/CD pipeline templates in `StarterKit/Pipelines/`, covering Azure DevOps, GitHub Actions, and GitLab CI. The `.github/workflows/` folder contains repository-maintenance workflows for the EPAC project itself.

---

## Repository-Level GitHub Actions Workflows

Located in `.github/workflows/`. These run against the EPAC GitHub repository itself, not in customer deployments.

### automated-publish.yaml
**Trigger:** On GitHub Release published event  
**Purpose:** Publishes the `EnterprisePolicyAsCode` PowerShell module to the PowerShell Gallery  
**Steps:** Windows runner → installs Az module dependencies → calls `Publish-Module` with a NuGet API key from repository secrets

### publish-docs.yaml
**Trigger:** Push to `main` branch  
**Purpose:** Builds and deploys the MkDocs documentation site to GitHub Pages  
**Steps:** Python setup → install mkdocs-material → run `Convert-MarkdownGitHubAlerts.ps1` → `mkdocs gh-deploy`

### close-stale-awaiting-response.yml
**Trigger:** Daily cron at midnight UTC / manual dispatch  
**Purpose:** Automatically closes GitHub issues labeled `awaiting response` after 10 days of no activity

### check-alz-release.yaml
**Trigger:** Daily cron at 8 AM UTC  
**Purpose:** Checks for new Azure Landing Zone library releases; creates a GitHub issue if a new release is detected within 24 hours

### gh-issues-to-ado.yaml
**Trigger:** GitHub issue events (opened, edited, closed, reopened, labeled, unlabeled, assigned) and issue comments  
**Purpose:** Syncs GitHub issues to Azure DevOps work items in the `SecInfra` organization / `epac-development` project

---

## StarterKit Pipeline Templates

### Directory Layout

```
StarterKit/Pipelines/
├── AzureDevOps/
│   ├── GitHub-Flow/                    ← Feature-branch based ADO pipelines
│   ├── GitHub-Flow-With-AdoWiki/       ← Same + Azure Wiki integration
│   ├── Release-Flow/                   ← Release-branch based ADO pipelines
│   ├── templates-ps1-module/           ← Reusable pipeline step templates (module-based)
│   └── templates-ps1-scripts/          ← Reusable pipeline step templates (script-based)
├── GitHubActions/
│   ├── GitHub-Flow/                    ← Feature-branch based GitHub Actions
│   ├── Release-Flow/                   ← Release-branch based GitHub Actions
│   ├── templates-ps1-module/           ← Reusable workflow templates (module-based)
│   └── templates-ps1-scripts/          ← Reusable workflow templates (script-based)
└── GitLab/
    ├── GitHub-Flow/                    ← Feature-branch based GitLab CI
    ├── templates-ps1-module/           ← Reusable GitLab job templates
    └── templates-ps1-scripts/
```

---

## Reusable Step Templates

All platforms share the same logical step templates:

| Template | Purpose |
|----------|---------|
| `plan.yml` | Run `Build-DeploymentPlans` (or `Build-DeploymentPlans.ps1`) for a PAC environment; sets `deployPolicyChanges` / `deployRoleChanges` flags |
| `deploy-policy.yml` | Run `Deploy-PolicyPlan` (or `Deploy-PolicyPlan.ps1`); reads plan file and applies policy changes |
| `deploy-roles.yml` | Run `Deploy-RolesPlan` (or `Deploy-RolesPlan.ps1`); applies RBAC role assignments |
| `remediate.yml` | Run `New-AzRemediationTasks` for auto-remediation |
| `plan-exemptions-only.yml` | Run `Build-DeploymentPlans` with `-BuildExemptionsOnly` flag |
| `documentation.yml` | Run `Build-PolicyDocumentation` |

**Module vs. Scripts variant:** `templates-ps1-module` installs the `EnterprisePolicyAsCode` module from the PowerShell Gallery; `templates-ps1-scripts` directly calls the `.ps1` files from the repository.

---

## GitHub Flow Pattern

Feature branches → `epac-dev` environment → tenant (production) environment.

### Azure DevOps: epac-dev-pipeline.yml
**Trigger:** Push to `feature/*` branches when `Definitions/**` or `Pipelines/**` change  
**Service connections:**
- `sc-epac-plan` — read-only planning
- `sc-epac-dev` — dev environment deployment
**Jobs:**
1. `planDev` — Build deployment plan for `EPAC-DEV` environment
2. `deployPolicyDev` (if `deployPolicyChanges == 'yes'`) — Deploy policy plan to dev
3. `deployRolesDev` (if `deployRoleChanges == 'yes'`) — Deploy roles to dev
4. `planTenant` — Build plan for `Tenant` (production) environment (preview only)

### Azure DevOps: epac-tenant-pipeline.yml
**Trigger:** Manual only (`trigger: none`)  
**Service connections:** `sc-epac-tenant-deploy`, `sc-epac-tenant-roles`  
**Jobs:**
1. `planTenant` — Build deployment plan for `Tenant` environment
2. `deployPolicyTenant` (conditional) — Deploy policy plan
3. `deployRolesTenant` (conditional) — Deploy roles

### Azure DevOps: epac-exemptions-pipeline.yml
**Trigger:** Manual or scheduled  
**Purpose:** Exports current exemptions from Azure, creates PR with updated exemption files, and creates an ADO work item  
**Steps:** Export exemptions → Git commit → Create PR → Link ADO task

### Azure DevOps: epac-remediation-pipeline.yml
**Trigger:** Scheduled (daily at 5 AM UTC / midnight EST)  
**Purpose:** Auto-remediates non-compliant resources in all environments  
**Runs:** Separate remediation jobs for each environment (`EPAC-DEV`, `Tenant`)

### Azure DevOps: epac-compliance-scan-pipeline.yml
**Trigger:** Manual  
**Purpose:** Generates non-compliance reports for all environments

### Azure DevOps: epac-alz-sync-pipeline.yml
**Trigger:** Manual  
**Purpose:** Runs `Sync-ALZPolicyFromLibrary` to update ALZ policy definitions

---

## Release Flow Pattern

Release branches → nonprod environments → production environment with approval gates.

### Azure DevOps: epac-nonprod-pipeline.yml
**Trigger:** Push to `releases-nonprod/*` branches  
**Jobs:** Plan nonprod → Deploy Policy (with environment approval gate) → Deploy Roles

### Azure DevOps: epac-prod-pipeline.yml
**Trigger:** Push to `releases-prod/*` branches  
**Service connections:** `sc-epac-prod-deploy`, `sc-epac-prod-roles`  
**Jobs:** Plan prod → Deploy Policy (with environment approval gate) → Deploy Roles

### Azure DevOps: epac-prod-exemptions-only-pipeline.yml
**Trigger:** Manual  
**Purpose:** Builds and deploys only exemption changes to production (faster path for exemption-only updates)

---

## GitHub Actions Equivalents

GitHub Actions workflows mirror the ADO pipelines:

### epac-dev-workflow.yml (GitHub Flow)
**Trigger:** Push to `feature/**` branches, changes in `Definitions/**` or `.github/**`  
**Jobs:** `plan` → `deployPolicy` (conditional) → `deployRoles` (conditional) → `tenantPlan`  
**Auth:** OIDC federated identity (no stored secrets)

### epac-tenant-workflow.yml (GitHub Flow)
**Trigger:** Manual (`workflow_dispatch`)  
**Auth:** OIDC to production tenant  
**Environment:** Uses GitHub Environments with required reviewers for production protection

### epac-remediation-workflow.yml
**Trigger:** `cron: '0 5 * * *'` (daily 5 AM UTC) or `workflow_dispatch`  
**Jobs:** Separate remediation job per environment

### Release Flow Variants
- `epac-dev-workflow.yml` — Dev release
- `epac-nonprod-workflow.yml` — Non-production release
- `epac-prod-workflow.yml` — Production release with environment protection rules
- `epac-prod-exemptions-only-workflow.yml` — Production exemptions only
- `epac-remediation-workflow.yml` — Release-flow remediation

---

## GitLab CI Pipelines

### .gitlab-ci.yml (GitHub Flow)
**Trigger:** Manual input with boolean toggles for each environment  
**Stages:** `epac-dev`, `epac-prod`  
**Auth:** Federated identity via `AZURE_TENANT_ID` and `AZURE_CLIENT_ID` CI variables  
**Pattern:** `az login --federated-token` before each stage

### templates:
- `plan.yml` — GitLab CI job template for planning
- `deploy-policy.yml` — GitLab CI job template for policy deployment
- `deploy-roles.yml` — GitLab CI job template for role deployment

---

## Service Connection / Authentication Summary

| Connection | Permissions | Used By |
|-----------|-------------|---------|
| `sc-epac-plan` | Reader on deployment root scope | Planning (all environments) |
| `sc-epac-dev` | Policy Contributor + Role Based Access Control Admin at dev MG | Dev deployment |
| `sc-epac-tenant-deploy` | Policy Contributor at tenant root | Tenant policy deployment |
| `sc-epac-tenant-roles` | Role Based Access Control Admin at tenant root | Tenant role assignment |
| `sc-epac-nonprod-deploy` | Policy Contributor at nonprod MG | Non-prod deployment |
| `sc-epac-prod-deploy` | Policy Contributor at prod MG | Production policy deployment |
| `sc-epac-prod-roles` | Role Based Access Control Admin at prod MG | Production role assignment |
| `sc-epac-tenant-remediation` | Policy Contributor + Contributor at tenant root | Auto-remediation |

The `New-AzPolicyReaderRole.ps1` script creates a custom read-only role suitable for `sc-epac-plan`.

---

## Pipeline Variable Conventions

| Variable | Values | Set By | Consumed By |
|----------|--------|--------|-------------|
| `deployPolicyChanges` | `'yes'` / `'no'` | `Build-DeploymentPlans` | Deploy-Policy job condition |
| `deployRoleChanges` | `'yes'` / `'no'` | `Build-DeploymentPlans` | Deploy-Roles job condition |
| `PAC_DEFINITIONS_FOLDER` | path | Pipeline variable group | All EPAC scripts |
| `PAC_OUTPUT_FOLDER` | path | Pipeline variable group | Plan + Deploy scripts |
| `PAC_INPUT_FOLDER` | path | Pipeline variable group | Deploy scripts |

---

## Artifact Passing

Plan files are passed between pipeline stages as artifacts:
- **Plan stage** uploads: `Output/plans-{pacSelector}/policy-plan.json`, `roles-plan.json`
- **Deploy stages** download: the artifact from the plan stage before running

In ADO, this uses `publish` / `download` artifact steps.  
In GitHub Actions, this uses `actions/upload-artifact` / `actions/download-artifact`.  
In GitLab, this uses `artifacts: paths:` and `dependencies:` keys.

---

## ADO Wiki Integration (Optional)

The `GitHub-Flow-With-AdoWiki` variant adds a post-deployment step that:
1. Generates policy documentation via `Build-PolicyDocumentation`
2. Publishes the generated markdown files to an Azure DevOps Wiki
3. Requires additional `sc-epac-wiki` service connection with Wiki write permissions
