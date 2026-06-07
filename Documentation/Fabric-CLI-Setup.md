# Fabric CLI Setup

Fabric is used as the local CLI execution layer for PDA Fabric pattern aliases.

## Windows / PowerShell

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts\Install-PDAFabricHelper.ps1
```

If the current terminal does not see `fabric`, add the user bin directory to PATH:

```powershell
$bin = Join-Path $env:USERPROFILE '.local\bin'
$env:PATH = "$bin;$env:PATH"
```

Recommended local config:

```text
DEFAULT_VENDOR=OpenAI
DEFAULT_MODEL=llama3.2:latest
OPENAI_API_KEY=ollama
OPENAI_API_BASE_URL=http://localhost:11434/v1
PATTERNS_LOADER_GIT_REPO_URL=https://github.com/danielmiessler/fabric.git
```

After install:

```powershell
fabric --version
fabric --listpatterns
```

## Linux

```bash
curl -fsSL https://raw.githubusercontent.com/danielmiessler/fabric/main/scripts/installer/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
```

Recommended local config:

```text
DEFAULT_VENDOR=OpenAI
DEFAULT_MODEL=llama3.2:latest
OPENAI_API_KEY=ollama
OPENAI_API_BASE_URL=http://localhost:11434/v1
PATTERNS_LOADER_GIT_REPO_URL=https://github.com/danielmiessler/fabric.git
```

After install:

```bash
fabric --version
fabric --listpatterns
```

## PDA Pattern Sync

The PDA Fabric aliases use local pattern templates synced from `PDA-Fabric/` into the Fabric config patterns directory.

Supported aliases:

- `research` -> `Research/research-synthesis`
- `report` -> `Reporting/report-summary`
- `review` -> `Review/review-checklist`
- `security` -> `Security/security-triage`

Only sanitized Category 1 material should be routed into these Fabric aliases when the input could leave the local workspace.
