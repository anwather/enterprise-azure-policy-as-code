# Enterprise Policy as Code (EPAC) — Specification Index

This folder contains detailed specifications for the EPAC codebase. These specs are intended to aid agents in a Ralph loop for future development, refactoring, and feature addition.

## Files

| File | Description |
|------|-------------|
| [overview.md](overview.md) | High-level project overview, purpose, and key concepts |
| [architecture.md](architecture.md) | Component architecture, dependencies, and end-to-end data flows |
| [configuration.md](configuration.md) | Configuration file formats: global settings, JSON schemas, folder layouts |
| [module.md](module.md) | PowerShell module structure and export mechanics |
| [scripts-deploy.md](scripts-deploy.md) | Deploy pipeline scripts (plan, deploy-policy, deploy-roles, exemptions) |
| [scripts-operations.md](scripts-operations.md) | Operational/reporting scripts (export, document, remediate, etc.) |
| [scripts-helpers.md](scripts-helpers.md) | Helper function library organized by category |
| [scripts-hydration.md](scripts-hydration.md) | HydrationKit bootstrapping wizard |
| [scripts-cloud-adoption-framework.md](scripts-cloud-adoption-framework.md) | Azure Landing Zones / CAF integration |
| [ci-cd-pipelines.md](ci-cd-pipelines.md) | CI/CD pipeline templates for Azure DevOps, GitHub Actions, and GitLab |

## How to Use These Specs

Each spec file describes the **purpose**, **inputs/outputs**, **key logic**, and **dependencies** for each component. When adding new features or modifying existing ones, consult the relevant spec first to understand the expected contracts and patterns.

## Repository Layout (top-level)

```
enterprise-azure-policy-as-code/
├── Docs/               # MkDocs documentation source
├── Examples/           # Real-world EPAC configuration examples
├── Module/             # EnterprisePolicyAsCode PowerShell module
├── Schemas/            # JSON Schema definitions for config validation
├── Scripts/
│   ├── CloudAdoptionFramework/   # ALZ library integration scripts
│   ├── Deploy/                   # Primary deployment pipeline scripts
│   ├── Helpers/                  # Internal helper function library (128+ files)
│   ├── HydrationKit/             # Interactive bootstrap wizard scripts
│   └── Operations/               # Operational reporting and export scripts
├── StarterKit/         # CI/CD pipeline templates and starter definitions
└── spec/               # ← This folder
```
