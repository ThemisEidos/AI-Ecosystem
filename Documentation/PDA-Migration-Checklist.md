# PDA Migration Checklist

Use this checklist when moving the PDA ecosystem to another workstation.

## Pre-Migration

- [ ] Confirm the source repo is clean enough to copy.
- [ ] Confirm there are no real secrets in the repo.
- [ ] Export or back up local-only runtime files separately.
- [ ] Capture any machine-specific Obsidian vault paths.
- [ ] Note the active Docker Desktop / Docker Engine version.

## Files to Move

- [ ] Repository files
- [ ] `PDA-Runtime/.env.example`
- [ ] `litellm/.env.local.example`
- [ ] Any local secret file stored outside git
- [ ] Any runtime-specific notes or backup manifests

## Files Not to Commit

- [ ] `litellm/.env.local`
- [ ] Any API key file
- [ ] Any token or credential file
- [ ] `PDA-Tasks/`
- [ ] `PDA-Backups/`
- [ ] Generated reports and logs

## Target Machine Setup

- [ ] Install PowerShell 7
- [ ] Install Git
- [ ] Install Docker Desktop or Docker Engine
- [ ] Install Python 3
- [ ] Install Ollama
- [ ] Install Fabric CLI
- [ ] Install Obsidian
- [ ] Place the repo in the desired local workspace
- [ ] Verify `docker --version`
- [ ] Verify `pwsh --version`
- [ ] Verify `git --version`
- [ ] Verify `python --version`
- [ ] Verify `fabric --version` or the fallback executable path
- [ ] Verify Obsidian launches from the installed path

## Runtime Configuration

- [ ] Copy `PDA-Runtime/.env.example` to your local secret store if needed
- [ ] Fill `litellm/.env.local` with local-only provider secrets
- [ ] Confirm `PDA-Runtime/docker-compose.yml` points LiteLLM at `../litellm/.env.local`
- [ ] Confirm Docker can reach host services as documented
- [ ] Confirm `PDA-Backups/` and `Roadmap/` working folders exist

## Post-Migration Validation

- [ ] Run `pwsh -File Scripts\Test-PDADeployment.ps1 -AsJson -NoThrow`
- [ ] Run `pwsh -File Scripts\Install-PDAEcosystem.ps1 -DryRun -AsJson -NoThrow`
- [ ] Run `pwsh -File Scripts\Test-PDAStack.ps1 -Deep -NoThrow`
- [ ] Run `pwsh -File Scripts\Test-PDAFabricHealthCheck.ps1 -AsJson -NoThrow`
- [ ] Run `pwsh -File Scripts\Test-PDANotebookLMCommand.ps1 -AsJson -NoThrow`
- [ ] Run `pwsh -File Scripts\Test-PDACapabilityRouter.ps1 -AsJson -NoThrow`

## Final Checks

- [ ] Open WebUI starts
- [ ] LiteLLM is reachable on `http://localhost:4000/v1`
- [ ] n8n is reachable on `http://localhost:5678`
- [ ] Ollama is reachable on `http://localhost:11434`
- [ ] Fabric CLI returns a version number
- [ ] NotebookLM package generation works from Category 1 notes only
- [ ] No secret-bearing files were committed
