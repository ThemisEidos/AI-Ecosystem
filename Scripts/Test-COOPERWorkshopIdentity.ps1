[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$IdentityScript = Join-Path $PSScriptRoot "Get-COOPERWorkshopIdentity.ps1"
$RouterScript = Join-Path $PSScriptRoot "Invoke-COOPERTool.ps1"

$Issues = New-Object System.Collections.Generic.List[string]

$OpenIdentity = & $IdentityScript -WorkshopMode "Open Workshop"
$PrivateIdentity = & $IdentityScript -WorkshopMode "Private Workshop"

if ([string]$OpenIdentity.default_model -ne "Claude Sonnet") { $Issues.Add("Open COOPER should resolve to Claude Sonnet.") }
if ([string]$PrivateIdentity.default_model -ne "local Qwen via Ollama") { $Issues.Add("Private COOPER should resolve to local Qwen via Ollama.") }
if ([string]$OpenIdentity.registry -ne "Config/general_tool_registry.yaml") { $Issues.Add("Open COOPER should use the general registry.") }
if ([string]$PrivateIdentity.registry -ne "Config/private_tool_registry.yaml") { $Issues.Add("Private COOPER should use the private registry.") }
if ([bool]$OpenIdentity.cloud_allowed -ne $true) { $Issues.Add("Open COOPER should allow cloud usage.") }
if ([bool]$PrivateIdentity.cloud_allowed -ne $false) { $Issues.Add("Private COOPER should block cloud fallback.") }

$OpenRoute = & $RouterScript -ToolId "browser_research" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -DryRun
$PrivateRoute = & $RouterScript -ToolId "status_summary_private" -Workshop "Private Workshop" -WorkshopMode "Private Workshop" -DryRun
$PrivateToolIds = @(
    "status_summary_private",
    "registry_inspector_private",
    "restricted_dmz_writer",
    "qwen_local_assistant",
    "powershell_private",
    "python_private",
    "restricted_workflow_runner"
)

if ([string]$OpenRoute.registry_path -notmatch 'general_tool_registry\.yaml$') { $Issues.Add("Open router lookup should use the general registry.") }
if ([string]$PrivateRoute.registry_path -notmatch 'private_tool_registry\.yaml$') { $Issues.Add("Private router lookup should use the private registry.") }
if ([bool]$PrivateIdentity.cloud_allowed -ne $false) { $Issues.Add("Private COOPER must never fall back to cloud models.") }

foreach ($PrivateToolId in $PrivateToolIds) {
    $PrivateToolRoute = & $RouterScript -ToolId $PrivateToolId -Workshop "Private Workshop" -WorkshopMode "Private Workshop" -DryRun
    if ([string]$PrivateToolRoute.registry_path -notmatch 'private_tool_registry\.yaml$') {
        $Issues.Add("Private tool '$PrivateToolId' must resolve from the private registry.")
    }
    if ([string]$PrivateToolRoute.workshop -ne "Private Workshop") {
        $Issues.Add("Private tool '$PrivateToolId' must stay in Private Workshop.")
    }
}

$PrivateRejectedOpenTool = & $RouterScript -ToolId "browser_research" -Workshop "Private Workshop" -WorkshopMode "Private Workshop" -DryRun
if ([string]$PrivateRejectedOpenTool.status -eq "pass") {
    $Issues.Add("Open Workshop tools must not be routable from Private Workshop.")
}

$OpenRejectedPrivateTool = & $RouterScript -ToolId "status_summary_private" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -DryRun
if ([string]$OpenRejectedPrivateTool.status -eq "pass") {
    $Issues.Add("Private Workshop tools must not be routable from Open Workshop.")
}

if ($Issues.Count -eq 0) {
    Write-Host "[PASS] COOPER workshop identity tests passed."
    exit 0
}

Write-Host "[FAIL] COOPER workshop identity tests failed."
foreach ($Issue in $Issues) {
    Write-Host "[FAIL] $Issue"
}
exit 1
