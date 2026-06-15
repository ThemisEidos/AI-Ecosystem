[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [object]$RoutedToolResult,

    [Parameter(Mandatory = $false)]
    [switch]$Approved
)

$ErrorActionPreference = "Stop"

$ExternalExecutorTypes = @(
    "browser",
    "llm_api",
    "cloud_service",
    "web_api",
    "webhook",
    "image_provider",
    "research_api",
    "third_party_provider"
)

function Get-COOPERFieldValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($Name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $Name) {
            $Value = $Object.$Name
            if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
                return $Value
            }
        }
    }

    return $null
}

function ConvertTo-COOPERInt {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return [int]$Value
    }
    catch {
        return $null
    }
}

function ConvertTo-COOPERBool {
    param([Parameter(Mandatory = $false)]$Value)

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    if ($null -eq $Value) {
        return $null
    }

    $Text = [string]$Value
    if ($Text -match '^(?i:true|false)$') {
        return [bool]::Parse($Text)
    }

    return $null
}

$ToolId = [string](Get-COOPERFieldValue -Object $RoutedToolResult -Names @("tool_id", "selected_tool", "id"))
$Workshop = [string](Get-COOPERFieldValue -Object $RoutedToolResult -Names @("workshop"))
$ExecutorType = [string](Get-COOPERFieldValue -Object $RoutedToolResult -Names @("executor_type"))
$PermissionLevel = ConvertTo-COOPERInt -Value (Get-COOPERFieldValue -Object $RoutedToolResult -Names @("permission_level"))
$ApprovalRequiredInput = ConvertTo-COOPERBool -Value (Get-COOPERFieldValue -Object $RoutedToolResult -Names @("approval_required"))
$Enabled = ConvertTo-COOPERBool -Value (Get-COOPERFieldValue -Object $RoutedToolResult -Names @("enabled"))
$BlockedReason = [string](Get-COOPERFieldValue -Object $RoutedToolResult -Names @("blocked_reason", "reason"))
$RouteStatus = [string](Get-COOPERFieldValue -Object $RoutedToolResult -Names @("status"))
$WorkshopMode = [string](Get-COOPERFieldValue -Object $RoutedToolResult -Names @("workshop_mode"))
$CloudAllowed = ConvertTo-COOPERBool -Value (Get-COOPERFieldValue -Object $RoutedToolResult -Names @("cloud_allowed"))

if ($null -eq $Enabled) {
    $Enabled = $true
}

$PolicyApprovalRequired = $false
if ($null -ne $PermissionLevel) {
    if ($PermissionLevel -ge 2 -and $PermissionLevel -le 4) {
        $PolicyApprovalRequired = $true
    }
}

if ($null -eq $ApprovalRequiredInput) {
    $ApprovalRequiredInput = $PolicyApprovalRequired
}

$Blocked = $false
$Allowed = $false
$RequiresUserApproval = $false
$Reason = ""

if ($RouteStatus -eq "fail") {
    $Blocked = $true
    $Reason = if (-not [string]::IsNullOrWhiteSpace($BlockedReason)) { $BlockedReason } else { "Routed tool lookup failed." }
}
elseif (-not $Enabled) {
    $Blocked = $true
    $Reason = "Tool '$ToolId' is disabled."
}
elseif ($null -eq $PermissionLevel) {
    $Blocked = $true
    $Reason = "Tool '$ToolId' is missing a permission level."
}
elseif ($PermissionLevel -eq 5) {
    $Blocked = $true
    $Reason = "Level 5 actions are blocked by default."
}
elseif ($Workshop -eq "Private Workshop" -and $PermissionLevel -eq 3) {
    $Blocked = $true
    $Reason = "Private Workshop does not allow Level 3 tools."
}
elseif ($WorkshopMode -eq "Private Workshop" -and $CloudAllowed -eq $false -and ($ExternalExecutorTypes -contains $ExecutorType)) {
    $Blocked = $true
    $Reason = "Private Workshop does not allow cloud fallback or external executor types."
}
elseif ($Workshop -eq "Private Workshop" -and ($ExternalExecutorTypes -contains $ExecutorType)) {
    $Blocked = $true
    $Reason = "Private Workshop does not allow external executor types."
}
else {
    $Allowed = $true

    switch ($PermissionLevel) {
        0 {
            $RequiresUserApproval = $false
            $Reason = "Level 0 may auto-run."
        }
        1 {
            $RequiresUserApproval = $false
            $Reason = "Level 1 may auto-run inside the correct workshop."
        }
        2 {
            $RequiresUserApproval = $true
            $Reason = "Level 2 requires user approval."
        }
        3 {
            $RequiresUserApproval = $true
            $Reason = "Level 3 requires user approval and is allowed only in Open Workshop."
        }
        4 {
            $RequiresUserApproval = $true
            $Reason = "Level 4 requires user approval."
        }
        default {
            $Blocked = $true
            $Allowed = $false
            $Reason = "Unsupported permission level '$PermissionLevel'."
        }
    }
}

if ($Blocked) {
    $Allowed = $false
    if (-not [string]::IsNullOrWhiteSpace($BlockedReason)) {
        $Reason = $BlockedReason
    }
}

$ExecutionAuthorized = $false
if ($Allowed -and (-not $RequiresUserApproval -or [bool]$Approved)) {
    $ExecutionAuthorized = $true
}

[pscustomobject]@{
    tool_id = $ToolId
    workshop = $Workshop
    workshop_mode = $WorkshopMode
    permission_level = $PermissionLevel
    approval_required = [bool]$ApprovalRequiredInput
    allowed = [bool]$Allowed
    blocked = [bool]$Blocked
    reason = $Reason
    requires_user_approval = [bool]$RequiresUserApproval
    execution_authorized = [bool]$ExecutionAuthorized
}
