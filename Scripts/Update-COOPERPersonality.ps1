[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$ProfilePath,

    [Parameter(Mandatory = $true)]
    [string]$Setting,

    [Parameter(Mandatory = $true)]
    [object]$Value,

    [Parameter(Mandatory = $false)]
    [string]$ConversationId,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$ConversationTitle,

    [Parameter(Mandatory = $false)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [Alias("AsJson")]
    [switch]$OutputJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

function Get-COOPERPersonalityProfilePath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Override = [string]$env:COOPER_PERSONALITY_PATH
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return $Override.Trim()
    }

    return (Join-Path $Root "Scripts\COOPER_Personality.json")
}

function Get-COOPERPersonalitySpec {
    return [ordered]@{
        humor = [ordered]@{
            property = "humor_level"
            label = "Humor"
            aliases = @("humor", "humour")
        }
        honesty = [ordered]@{
            property = "honesty_level"
            label = "Honesty"
            aliases = @("honesty")
        }
        discretion = [ordered]@{
            property = "discretion_level"
            label = "Discretion"
            aliases = @("discretion")
        }
        directness = [ordered]@{
            property = "directness_level"
            label = "Directness"
            aliases = @("directness")
        }
        verbosity = [ordered]@{
            property = "verbosity_level"
            label = "Verbosity"
            aliases = @("verbosity")
        }
        confidence = [ordered]@{
            property = "confidence_level"
            label = "Confidence"
            aliases = @("confidence")
        }
        formality = [ordered]@{
            property = "formality_level"
            label = "Formality"
            aliases = @("formality")
        }
        risk_tolerance = [ordered]@{
            property = "risk_tolerance"
            label = "Risk Tolerance"
            aliases = @("risk tolerance", "risk_tolerance", "risk-tolerance")
        }
    }
}

function Resolve-COOPERPersonalitySettingSpec {
    param([Parameter(Mandatory = $true)][string]$SettingName)

    $Normalized = ([string]$SettingName).Trim().ToLowerInvariant()
    $Spec = Get-COOPERPersonalitySpec

    foreach ($Entry in $Spec.GetEnumerator()) {
        if ($Normalized -eq $Entry.Key) {
            return [pscustomobject]@{ key = $Entry.Key; property = $Entry.Value.property; label = $Entry.Value.label }
        }

        foreach ($Alias in @($Entry.Value.aliases)) {
            if ($Normalized -eq ([string]$Alias).ToLowerInvariant()) {
                return [pscustomobject]@{ key = $Entry.Key; property = $Entry.Value.property; label = $Entry.Value.label }
            }
        }
    }

    return $null
}

function ConvertTo-COOPERPersonalityInt {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputValue
    )

    $Parsed = 0.0
    if ($InputValue -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$InputValue) -or -not [double]::TryParse([string]$InputValue, [ref]$Parsed)) {
            throw "Personality values must be numeric."
        }
    }
    else {
        try {
            $Parsed = [double]$InputValue
        }
        catch {
            throw "Personality values must be numeric."
        }
    }

    if ([double]::IsNaN($Parsed) -or [double]::IsInfinity($Parsed)) {
        throw "Personality values must be numeric."
    }

    $Rounded = [int][math]::Round($Parsed, 0, [MidpointRounding]::AwayFromZero)
    if ($Rounded -lt 0 -or $Rounded -gt 100) {
        throw "Personality values must be between 0 and 100."
    }

    return $Rounded
}

function Read-COOPERPersonalityProfile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "COOPER personality profile was not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Write-COOPERJsonFile {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $Parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null

    $TemporaryPath = "$Path.tmp"
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $TemporaryPath -Encoding UTF8
    Move-Item -LiteralPath $TemporaryPath -Destination $Path -Force
}

function Write-COOPERPersonalityAuditRecord {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$AuditPath
    )

    $Parent = Split-Path -Parent $AuditPath
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
    $Record | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $AuditPath -Encoding UTF8
    Add-Content -LiteralPath $AuditPath -Value "" -Encoding UTF8
}

$Result = [ordered]@{
    status = "fail"
    dry_run = [bool]$DryRun
    profile_path = $null
    backup_path = $null
    audit_log_path = $null
    setting = [string]$Setting
    setting_key = ""
    setting_label = ""
    changed_fields = @()
    previous_value = $null
    new_value = $null
    visible_candidate_label = "COOPER"
    message = ""
    conversation_id = [string]$ConversationId
    session_id = [string]$SessionId
    user_id = [string]$UserId
    conversation_title = [string]$ConversationTitle
    source_message = [string]$Message
}

try {
    if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
        $ProfilePath = Get-COOPERPersonalityProfilePath -Root $Root
    }
    $Result.profile_path = $ProfilePath

    $Spec = Resolve-COOPERPersonalitySettingSpec -SettingName $Setting
    if (-not $Spec) {
        throw "Unsupported personality setting '$Setting'. Supported settings: Humor, Honesty, Discretion, Directness, Verbosity, Confidence, Formality, Risk Tolerance."
    }

    $Profile = Read-COOPERPersonalityProfile -Path $ProfilePath
    if (-not ($Profile.PSObject.Properties.Name -contains "personality")) {
        throw "COOPER personality profile does not contain a personality section."
    }

    $Personality = $Profile.personality
    if (-not ($Personality.PSObject.Properties.Name -contains $Spec.property)) {
        throw "COOPER personality profile is missing the '$($Spec.property)' field."
    }

    $CurrentValue = ConvertTo-COOPERPersonalityInt -InputValue $Personality.$($Spec.property)
    $NewValue = ConvertTo-COOPERPersonalityInt -InputValue $Value

    $Result.setting_key = [string]$Spec.key
    $Result.setting_label = [string]$Spec.label
    $Result.previous_value = $CurrentValue
    $Result.new_value = $NewValue

    if ($CurrentValue -eq $NewValue) {
        $Result.status = "pass"
        $Result.message = "No change required for $($Spec.label); it is already set to $NewValue."
        $Result.changed_fields = @()
        if ($OutputJson) {
            $Result | ConvertTo-Json -Depth 20
            if (-not $NoThrow -and $Result.status -ne "pass") {
                throw "COOPER personality update failed."
            }
            return
        }

        Write-Host "[OK] COOPER personality update"
        Write-Host ("Message : {0}" -f $Result.message)
        return
    }

    if ($DryRun) {
        $Result.status = "pass"
        $Result.message = "Dry run: $($Spec.label) would change from $CurrentValue to $NewValue."
        $Result.changed_fields = @($Spec.property)
        if ($OutputJson) {
            $Result | ConvertTo-Json -Depth 20
            if (-not $NoThrow -and $Result.status -ne "pass") {
                throw "COOPER personality update failed."
            }
            return
        }

        Write-Host "[OK] COOPER personality update"
        Write-Host ("Message : {0}" -f $Result.message)
        return
    }

    $Timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
    $BackupDir = Join-Path $Root "PDA-Backups\personality\$Timestamp"
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $BackupPath = Join-Path $BackupDir (Split-Path -Path $ProfilePath -Leaf)
    Copy-Item -LiteralPath $ProfilePath -Destination $BackupPath -Force

    $Personality.$($Spec.property) = $NewValue
    $Profile.personality = $Personality
    Write-COOPERJsonFile -Object $Profile -Path $ProfilePath

    $AuditPath = Join-Path $Root "PDA-Logs\personality\cooper-personality-change-audit.jsonl"
    $AuditRecord = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        action = "update"
        status = "applied"
        profile_path = $ProfilePath
        backup_path = $BackupPath
        setting_key = [string]$Spec.key
        setting_label = [string]$Spec.label
        previous_value = $CurrentValue
        new_value = $NewValue
        conversation_id = [string]$ConversationId
        session_id = [string]$SessionId
        user_id = [string]$UserId
        conversation_title = [string]$ConversationTitle
        source_message = [string]$Message
        visible_candidate_label = "COOPER"
    }
    Write-COOPERPersonalityAuditRecord -Record $AuditRecord -AuditPath $AuditPath

    $Result.status = "pass"
    $Result.backup_path = $BackupPath
    $Result.audit_log_path = $AuditPath
    $Result.changed_fields = @($Spec.property)
    $Result.message = "$($Spec.label) updated from $CurrentValue to $NewValue."

    if ($OutputJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow -and $Result.status -ne "pass") {
            throw "COOPER personality update failed."
        }
        return
    }

    Write-Host "[OK] COOPER personality update"
    Write-Host ("Setting : {0}" -f $Result.setting_label)
    Write-Host ("Before  : {0}" -f $Result.previous_value)
    Write-Host ("After   : {0}" -f $Result.new_value)
    Write-Host ("Backup  : {0}" -f $Result.backup_path)
    Write-Host ("Audit   : {0}" -f $Result.audit_log_path)
}
catch {
    $Result.status = "fail"
    $Result.message = $_.Exception.Message
    $Result.changed_fields = @()

    if ($OutputJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) {
            throw "COOPER personality update failed."
        }
        return
    }

    Write-Host "[ERR] COOPER personality update"
    Write-Host ("Message : {0}" -f $Result.message)
    if (-not $NoThrow) {
        throw "COOPER personality update failed."
    }
}
