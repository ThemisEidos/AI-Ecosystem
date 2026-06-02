param(
    [string]$Message = "Create a 5-step implementation plan for connecting WebUI to n8n."
)

$VaultRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Obsidian Vault"
$OutputDir = Join-Path $VaultRoot "02_Projects\AI Tool Ecosystem\Agent Findings\Planner"

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$File = Join-Path $OutputDir "planner-output-$Timestamp.md"

$RawResponse = pwsh "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Send-PDACommand.ps1" -Command "/planner" -Message $Message
$RawText = $RawResponse -join "`n"

$Markdown = @"
# PDA Planner Output

**Date:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

**Command:** /planner

**Prompt:**
$Message

---

## Raw Router Response

$RawText

---

## Notes

- Generated through PDA Command Router
- Routed through n8n
- Model access through LiteLLM
- Intended storage: Obsidian project findings
"@

$Markdown | Set-Content -Path $File -Encoding UTF8

Write-Host "Saved planner output to Obsidian project folder:"
Write-Host $File
