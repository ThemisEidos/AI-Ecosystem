# AI Ecosystem

Personal Digital Analyst / PDA ecosystem infrastructure.

## Purpose

This repo stores code, workflow definitions, schemas, scripts, and documentation for the PDA automation stack.

## Do Not Commit

- API keys
- credentials
- `.env` files
- runtime task data
- logs
- Category 2 / restricted material
- sensitive source documents

## Installing on a New Machine

Full guide: [Documentation/PDA-Portable-Deployment.md](Documentation/PDA-Portable-Deployment.md)
(application list, secrets/state to carry, GPU-less servers). Short version:

```bash
sudo bash setup-linux.sh          # one-time system provisioning (--minimal for Docker-only hosts)
bash install-cooper.sh --private  # bring the stack up (omit --private for the Open stack)
```

Checklist: [Documentation/PDA-Migration-Checklist.md](Documentation/PDA-Migration-Checklist.md)

## Startup Commands

See [Documentation/AIEC-Startup-Commands.md](Documentation/AIEC-Startup-Commands.md) for the PowerShell startup and status commands for the Docker stack.
