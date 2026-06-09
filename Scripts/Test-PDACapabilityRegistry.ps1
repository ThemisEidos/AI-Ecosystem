[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RegistryPath = Join-Path $PSScriptRoot "PDA_CapabilityRegistry.json"
$CapabilityScript = Join-Path $PSScriptRoot "Get-PDACapability.ps1"
$RequiredCapabilityIds = @(
    "research",
    "source_discovery",
    "large_context_analysis",
    "report_writing",
    "report_review",
    "code_implementation",
    "code_review",
    "repo_modification",
    "automation_design",
    "n8n_workflow_design",
    "local_restricted_analysis",
    "file_processing",
    "dashboard_status_generation",
    "memory_summarization",
    "skill_promotion_review"
)

$CloudProviderNames = @("Gemini", "Claude", "Claude Code", "Codex", "OpenAI", "Perplexity", "OpenRouter")
$RequiredFields = @(
    "capability_id",
    "display_name",
    "description",
    "category_allowed",
    "approved_agents",
    "approved_tools",
    "preferred_providers",
    "fallback_providers",
    "approval_required",
    "restricted_local_only",
    "output_types",
    "risk_level",
    "notes"
)

function New-PDACapabilityTestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    return [pscustomobject]@{
        status = $Status
        message = $Message
    }
}

$Issues = New-Object System.Collections.Generic.List[string]
$Raw = $null
$Registry = $null
$GetAll = $null
$GetOne = $null
$GetJson = $null

if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    $Issues.Add("Capability registry file not found: $RegistryPath")
}
else {
    try {
        $Raw = Get-Content -LiteralPath $RegistryPath -Raw -ErrorAction Stop
        $Registry = $Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $Issues.Add("Capability registry JSON could not be parsed: $($_.Exception.Message)")
    }
}

if ($null -ne $Registry) {
    if (-not ($Registry.PSObject.Properties.Name -contains "capabilities")) {
        $Issues.Add("Capability registry missing 'capabilities'.")
    }
    elseif ($null -eq $Registry.capabilities -or $Registry.capabilities -isnot [System.Array]) {
        $Issues.Add("Capability registry 'capabilities' must be an array.")
    }
    else {
        $Capabilities = @($Registry.capabilities)
        foreach ($CapabilityId in $RequiredCapabilityIds) {
            if (-not @($Capabilities | Where-Object { [string]$_.capability_id -ieq $CapabilityId }).Count -gt 0) {
                $Issues.Add("Missing required capability id: $CapabilityId")
            }
        }

        foreach ($Capability in $Capabilities) {
            foreach ($Field in $RequiredFields) {
                if (-not ($Capability.PSObject.Properties.Name -contains $Field)) {
                    $Issues.Add("Capability '$([string]$Capability.capability_id)' missing required field '$Field'.")
                }
            }

            if ($Capability.PSObject.Properties.Name -contains "approval_required" -and ($Capability.approval_required -isnot [bool])) {
                $Issues.Add("Capability '$([string]$Capability.capability_id)' approval_required must be boolean.")
            }

            if ([string]$Capability.capability_id -eq "local_restricted_analysis") {
                if (-not [bool]$Capability.restricted_local_only) {
                    $Issues.Add("local_restricted_analysis must be restricted_local_only.")
                }
            }

            $CategoryAllowed = @($Capability.category_allowed | ForEach-Object { [string]$_ })
            if ($CategoryAllowed -contains "category_2") {
                foreach ($FieldName in @("preferred_providers", "fallback_providers")) {
                    $Providers = @($Capability.$FieldName | ForEach-Object { [string]$_ })
                    if (@($Providers | Where-Object { $CloudProviderNames -contains $_ }).Count -gt 0) {
                        $Issues.Add("Category 2 capability '$([string]$Capability.capability_id)' contains cloud providers in $FieldName.")
                    }
                }
            }
        }
    }
}

if (Test-Path -LiteralPath $CapabilityScript -PathType Leaf) {
    try {
        $GetAllJson = & pwsh -NoProfile -File $CapabilityScript -AsJson -NoThrow
        $GetAll = if ($GetAllJson -is [string]) { $GetAllJson | ConvertFrom-Json } else { ($GetAllJson | Out-String) | ConvertFrom-Json }
    }
    catch {
        $Issues.Add("Get-PDACapability.ps1 list-all invocation failed: $($_.Exception.Message)")
    }

    try {
        $GetOneJson = & pwsh -NoProfile -File $CapabilityScript -CapabilityId research -AsJson -NoThrow
        $GetOne = if ($GetOneJson -is [string]) { $GetOneJson | ConvertFrom-Json } else { ($GetOneJson | Out-String) | ConvertFrom-Json }
    }
    catch {
        $Issues.Add("Get-PDACapability.ps1 capability retrieval failed: $($_.Exception.Message)")
    }

    try {
        $GetJsonOutput = & pwsh -NoProfile -File $CapabilityScript -CapabilityId report_writing -AsJson -NoThrow
        $GetJson = if ($GetJsonOutput -is [string]) { $GetJsonOutput | ConvertFrom-Json } else { ($GetJsonOutput | Out-String) | ConvertFrom-Json }
    }
    catch {
        $Issues.Add("Get-PDACapability.ps1 -AsJson invocation failed: $($_.Exception.Message)")
    }
}
else {
    $Issues.Add("Get-PDACapability.ps1 not found at $CapabilityScript")
}

$Status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
$Report = [pscustomobject]@{
    status = $Status
    registry_path = $RegistryPath
    capability_script = $CapabilityScript
    capability_count = if ($Registry -and ($Registry.PSObject.Properties.Name -contains "capabilities") -and $Registry.capabilities) { @($Registry.capabilities).Count } else { 0 }
    required_capability_count = $RequiredCapabilityIds.Count
    issues = @($Issues)
    registry = $Registry
    get_all = $GetAll
    get_one = $GetOne
    get_json = $GetJson
    tests = [pscustomobject]@{
        registry_exists = (Test-Path -LiteralPath $RegistryPath -PathType Leaf)
        json_valid = ($null -ne $Registry)
        required_ids_present = ($Issues | Where-Object { $_ -like "Missing required capability id:*" }).Count -eq 0
        required_fields_present = ($Issues | Where-Object { $_ -like "Capability '*' missing required field*" }).Count -eq 0
        approval_boolean_valid = ($Issues | Where-Object { $_ -like "*approval_required must be boolean*" }).Count -eq 0
        local_restricted_only_valid = ($Issues | Where-Object { $_ -like "local_restricted_analysis must be restricted_local_only*" }).Count -eq 0
        category2_cloud_free = ($Issues | Where-Object { $_ -like "Category 2 capability '*' contains cloud providers*" }).Count -eq 0
        get_all_supported = ($null -ne $GetAll -and $GetAll.status -eq "pass")
        get_one_supported = ($null -ne $GetOne -and $GetOne.status -eq "pass")
        as_json_supported = ($null -ne $GetJson -and $GetJson.status -eq "pass")
    }
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Status -ne "pass") {
        throw "PDA capability registry validation failed."
    }
    return
}

Write-Host "[*] PDA capability registry validation"
Write-Host ("Registry path   : {0}" -f $RegistryPath)
Write-Host ("Capability count: {0}" -f $Report.capability_count)
Write-Host ("Status          : {0}" -f $Status)
if ($Issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issues:"
    foreach ($Issue in $Issues) {
        Write-Host ("- {0}" -f $Issue)
    }
}

if (-not $NoThrow -and $Status -ne "pass") {
    throw "PDA capability registry validation failed."
}
