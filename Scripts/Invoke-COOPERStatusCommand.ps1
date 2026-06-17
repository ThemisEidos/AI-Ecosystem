[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkshopMode = "",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$IdentityScript = Join-Path $PSScriptRoot "Get-COOPERWorkshopIdentity.ps1"
$RouterScript = Join-Path $PSScriptRoot "Invoke-COOPERTool.ps1"
$ApprovalScript = Join-Path $PSScriptRoot "Resolve-COOPERApproval.ps1"
$WorkbenchScript = Join-Path $PSScriptRoot "Invoke-COOPERWorkbench.ps1"

function Resolve-COOPERStatusWorkshopMode {
    param([Parameter(Mandatory = $false)][string]$RequestedMode = "")

    if (-not [string]::IsNullOrWhiteSpace($RequestedMode)) {
        return [string]$RequestedMode
    }

    $EnvMode = [string]$env:COOPER_WORKSHOP_MODE
    if (-not [string]::IsNullOrWhiteSpace($EnvMode)) {
        return $EnvMode.Trim()
    }

    return "Open Workshop"
}

function Join-COOPERStatusLines {
    param([Parameter(Mandatory = $true)]$StatusOutput)

    $Lines = New-Object System.Collections.Generic.List[string]
    if ($null -eq $StatusOutput) {
        return ""
    }

    foreach ($Field in @("status_lines", "summary_lines")) {
        if ($StatusOutput.PSObject.Properties.Name -contains $Field) {
            foreach ($Line in @($StatusOutput.$Field)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$Line)) {
                    $Lines.Add([string]$Line)
                }
            }
            if ($Lines.Count -gt 0) {
                return ($Lines -join "`r`n")
            }
        }
    }

    foreach ($Field in @("workshop_mode", "workshop_name", "default_model", "cloud_allowed", "active_registry", "status_workflow")) {
        if ($StatusOutput.PSObject.Properties.Name -contains $Field -and -not [string]::IsNullOrWhiteSpace([string]$StatusOutput.$Field)) {
            $Label = switch ($Field) {
                "workshop_mode" { "Workshop Mode" }
                "workshop_name" { "Active Workshop" }
                "default_model" { "Default Model" }
                "cloud_allowed" { "Cloud Allowed" }
                "active_registry" { "Registry" }
                "status_workflow" { "Status Workflow" }
                default { $Field }
            }
            $Lines.Add(("{0}: {1}" -f $Label, [string]$StatusOutput.$Field))
        }
    }

    if ($StatusOutput.PSObject.Properties.Name -contains "security_sources" -and $StatusOutput.security_sources) {
        foreach ($Field in @("firewall_status", "ids_status", "backup_status")) {
            if ($StatusOutput.security_sources.PSObject.Properties.Name -contains $Field) {
                $Label = switch ($Field) {
                    "firewall_status" { "Firewall Status" }
                    "ids_status" { "IDS Status" }
                    "backup_status" { "Backup Status" }
                }
                $Lines.Add(("{0}: {1}" -f $Label, [string]$StatusOutput.security_sources.$Field))
            }
        }
    }

    return ($Lines -join "`r`n")
}

$ResolvedWorkshopMode = Resolve-COOPERStatusWorkshopMode -RequestedMode $WorkshopMode
if ([string]::IsNullOrWhiteSpace($ResolvedWorkshopMode)) {
    $ResolvedWorkshopMode = "Open Workshop"
}

try {
    $WorkshopIdentity = & $IdentityScript -WorkshopMode $ResolvedWorkshopMode
}
catch {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = "status_summary"
        workshop = ""
        workshop_mode = $ResolvedWorkshopMode
        executor_type = ""
        action_taken = "blocked"
        output = $null
        reason = "Unsupported workshop mode '$ResolvedWorkshopMode'. $($_.Exception.Message)"
        workshop_identity = $null
        routed_tool = $null
        approval_decision = $null
        workbench_result = $null
        response_text = ""
    }
}

$StatusToolId = if ([string]$WorkshopIdentity.workshop_label -eq "Private Workshop") { "status_summary_private" } else { "status_summary" }
$RoutedTool = & $RouterScript -ToolId $StatusToolId -Workshop ([string]$WorkshopIdentity.workshop_label) -WorkshopMode $ResolvedWorkshopMode -DryRun:$DryRun
if ([string]$RoutedTool.status -ne "pass") {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $StatusToolId
        workshop = [string]$WorkshopIdentity.workshop_label
        workshop_mode = $ResolvedWorkshopMode
        executor_type = [string]$RoutedTool.executor_type
        action_taken = "blocked"
        output = $null
        reason = [string]$RoutedTool.blocked_reason
        workshop_identity = $WorkshopIdentity
        routed_tool = $RoutedTool
        approval_decision = $null
        workbench_result = $null
        response_text = ""
    }
}

$ApprovalDecision = & $ApprovalScript -RoutedToolResult $RoutedTool
if ([bool]$ApprovalDecision.blocked -eq $true -or [bool]$ApprovalDecision.allowed -ne $true) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = [string]$ApprovalDecision.tool_id
        workshop = [string]$ApprovalDecision.workshop
        workshop_mode = [string]$ApprovalDecision.workshop_mode
        executor_type = [string]$ApprovalDecision.executor_type
        action_taken = "blocked"
        output = $null
        reason = [string]$ApprovalDecision.reason
        workshop_identity = $WorkshopIdentity
        routed_tool = $RoutedTool
        approval_decision = $ApprovalDecision
        workbench_result = $null
        response_text = ""
    }
}

$WorkbenchResult = & $WorkbenchScript -ApprovalDecision $ApprovalDecision -DryRun:$DryRun
$WorkbenchSnapshot = $WorkbenchResult | Select-Object *
$ResponseText = ""
if ($WorkbenchResult.PSObject.Properties.Name -contains "output" -and $WorkbenchResult.output) {
    $ResponseText = Join-COOPERStatusLines -StatusOutput $WorkbenchResult.output
}

$WorkbenchResult | Add-Member -NotePropertyName workshop_identity -NotePropertyValue $WorkshopIdentity -Force
$WorkbenchResult | Add-Member -NotePropertyName routed_tool -NotePropertyValue $RoutedTool -Force
$WorkbenchResult | Add-Member -NotePropertyName approval_decision -NotePropertyValue $ApprovalDecision -Force
$WorkbenchResult | Add-Member -NotePropertyName workbench_result -NotePropertyValue $WorkbenchSnapshot -Force
$WorkbenchResult | Add-Member -NotePropertyName response_text -NotePropertyValue $ResponseText -Force
$WorkbenchResult | Add-Member -NotePropertyName command -NotePropertyValue "Show system status" -Force

return $WorkbenchResult
