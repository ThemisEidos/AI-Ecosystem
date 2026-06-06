[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-PDALifecyclePolicyPath {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Scripts\PDA_LifecyclePolicy.json")
}

function Get-PDALifecyclePolicySchemaPath {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Scripts\PDA_LifecyclePolicy.schema.json")
}

function Read-PDALifecycleJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$NotFoundMessage,

        [Parameter(Mandatory = $true)]
        [string]$ParseMessage
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw $NotFoundMessage
    }

    try {
        return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
    }
    catch {
        throw $ParseMessage
    }
}

function Import-PDALifecyclePolicy {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $PolicyPath = Get-PDALifecyclePolicyPath -Root $Root
    return Read-PDALifecycleJsonFile -Path $PolicyPath -NotFoundMessage "PDA lifecycle policy not found: $PolicyPath" -ParseMessage "PDA lifecycle policy JSON could not be parsed at '$PolicyPath'."
}

function Test-PDALifecyclePolicyContract {
    [CmdletBinding()]
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $PolicyPath = Get-PDALifecyclePolicyPath -Root $Root
    $SchemaPath = Get-PDALifecyclePolicySchemaPath -Root $Root
    $Issues = New-Object System.Collections.Generic.List[object]

    foreach ($Path in @($PolicyPath, $SchemaPath)) {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "missing_file"
                path       = $Path
                detail     = "Missing required file"
            })
        }
    }

    if ($Issues.Count -gt 0) {
        return [pscustomobject]@{
            valid       = $false
            issue_count = $Issues.Count
            issues      = @($Issues.ToArray())
            policy_path = $PolicyPath
            schema_path = $SchemaPath
        }
    }

    $Policy = Import-PDALifecyclePolicy -Root $Root
    $Schema = Read-PDALifecycleJsonFile -Path $SchemaPath -NotFoundMessage "PDA lifecycle schema not found: $SchemaPath" -ParseMessage "PDA lifecycle policy schema JSON could not be parsed at '$SchemaPath'."

    foreach ($Property in @("schema_version", "policy_name", "policy_version", "history_field", "artifact", "memory")) {
        if (-not ($Policy.PSObject.Properties.Name -contains $Property)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "missing_property"
                path       = $PolicyPath
                property   = $Property
                detail     = "Missing lifecycle property"
            })
        }
    }

    foreach ($SectionName in @("artifact", "memory")) {
        if (-not ($Policy.PSObject.Properties.Name -contains $SectionName)) {
            continue
        }

        $Section = $Policy.$SectionName
        foreach ($Property in @("default_state", "states", "allowed_transitions")) {
            if (-not ($Section.PSObject.Properties.Name -contains $Property)) {
                $Issues.Add([pscustomobject]@{
                    issue_type = "missing_property"
                    path       = $PolicyPath
                    property   = "$SectionName.$Property"
                    detail     = "Missing lifecycle section property"
                })
            }
        }
    }

    $AllowedArtifactStates = @($Policy.artifact.states) | ForEach-Object { [string]$_ }
    $AllowedMemoryStates = @($Policy.memory.states) | ForEach-Object { [string]$_ }

    if (($AllowedArtifactStates | Sort-Object -Unique).Count -ne $AllowedArtifactStates.Count) {
        $Issues.Add([pscustomobject]@{
            issue_type = "duplicate_values"
            path       = $PolicyPath
            property   = "artifact.states"
            detail     = "Duplicate artifact lifecycle states"
        })
    }

    if (($AllowedMemoryStates | Sort-Object -Unique).Count -ne $AllowedMemoryStates.Count) {
        $Issues.Add([pscustomobject]@{
            issue_type = "duplicate_values"
            path       = $PolicyPath
            property   = "memory.states"
            detail     = "Duplicate memory lifecycle states"
        })
    }

    foreach ($StateSet in @(@{ name = "artifact"; states = $AllowedArtifactStates; transitions = $Policy.artifact.allowed_transitions }, @{ name = "memory"; states = $AllowedMemoryStates; transitions = $Policy.memory.allowed_transitions })) {
        foreach ($State in $StateSet.states) {
            if (-not ($StateSet.transitions.PSObject.Properties.Name -contains $State)) {
                $Issues.Add([pscustomobject]@{
                    issue_type = "missing_transition"
                    path       = $PolicyPath
                    property   = "$($StateSet.name).allowed_transitions.$State"
                    detail     = "Missing lifecycle transition entry"
                })
            }
        }
    }

    return [pscustomobject]@{
        valid       = ($Issues.Count -eq 0)
        issue_count = $Issues.Count
        issues      = @($Issues.ToArray())
        policy_path = $PolicyPath
        schema_path = $SchemaPath
    }
}

function Get-PDALifecyclePolicySection {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [ValidateSet("artifact", "memory")]
        [string]$RecordType
    )

    return $Policy.$RecordType
}

function Get-PDALifecycleDefaultState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [ValidateSet("artifact", "memory")]
        [string]$RecordType
    )

    return [string](Get-PDALifecyclePolicySection -Policy $Policy -RecordType $RecordType).default_state
}

function Get-PDALifecycleRecordState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Record,

        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [ValidateSet("artifact", "memory")]
        [string]$RecordType
    )

    $CurrentState = ""
    if ($Record.PSObject.Properties.Name -contains "lifecycle_state" -and -not [string]::IsNullOrWhiteSpace([string]$Record.lifecycle_state)) {
        $CurrentState = [string]$Record.lifecycle_state
    }

    if ([string]::IsNullOrWhiteSpace($CurrentState)) {
        $CurrentState = Get-PDALifecycleDefaultState -Policy $Policy -RecordType $RecordType
    }

    return $CurrentState
}

function Test-PDALifecycleTransition {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [ValidateSet("artifact", "memory")]
        [string]$RecordType,

        [Parameter(Mandatory = $true)]
        [string]$FromState,

        [Parameter(Mandatory = $true)]
        [string]$ToState
    )

    $Section = Get-PDALifecyclePolicySection -Policy $Policy -RecordType $RecordType
    $AllowedTransitions = @()
    if ($Section.allowed_transitions.PSObject.Properties.Name -contains $FromState) {
        $AllowedTransitions = @($Section.allowed_transitions.$FromState)
    }

    return @{
        valid = ($AllowedTransitions -contains $ToState)
        from_state = $FromState
        to_state = $ToState
        record_type = $RecordType
        allowed_transitions = @($AllowedTransitions)
    }
}

function Get-PDALifecycleHistoryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RecordId,

        [Parameter(Mandatory = $true)]
        [string]$RecordType,

        [Parameter(Mandatory = $true)]
        [string]$FromState,

        [Parameter(Mandatory = $true)]
        [string]$ToState,

        [Parameter(Mandatory = $false)]
        [string]$Reason = "",

        [Parameter(Mandatory = $false)]
        [string]$Actor = "",

        [Parameter(Mandatory = $false)]
        [string]$ScriptName = ""
    )

    return [pscustomobject]@{
        changed_at = (Get-Date).ToString("o")
        record_id = $RecordId
        record_type = $RecordType
        from_state = $FromState
        to_state = $ToState
        reason = $Reason
        actor = $Actor
        source_script = $ScriptName
    }
}

function Get-PDALifecycleBackupPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [ValidateSet("artifact", "memory")]
        [string]$RecordType,

        [Parameter(Mandatory = $true)]
        [string]$RecordId
    )

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
    return (Join-Path $Root "PDA-Backups\lifecycle-transitions\$RecordType\$Timestamp-$RecordId")
}

function Invoke-PDALifecycleTransition {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [ValidateSet("artifact", "memory")]
        [string]$RecordType,

        [Parameter(Mandatory = $true)]
        [string]$RecordId,

        [Parameter(Mandatory = $true)]
        [string]$LifecycleState,

        [Parameter(Mandatory = $false)]
        [string]$Reason = "",

        [Parameter(Mandatory = $false)]
        [string]$Actor = "",

        [Parameter(Mandatory = $false)]
        [switch]$NoThrow
    )

    $Policy = Import-PDALifecyclePolicy -Root $Root
    $PolicyCheck = Test-PDALifecyclePolicyContract -Root $Root
    if (-not $PolicyCheck.valid) {
        throw "PDA lifecycle policy validation failed."
    }

    $IndexPath = if ($RecordType -eq "artifact") { Join-Path $Root "PDA_ArtifactIndex.json" } else { Join-Path $Root "PDA_MemoryIndex.json" }
    if (-not (Test-Path -Path $IndexPath -PathType Leaf)) {
        throw "PDA lifecycle target index not found: $IndexPath"
    }

    $Index = Get-Content -Path $IndexPath -Raw | ConvertFrom-Json
    $ArrayName = if ($RecordType -eq "artifact") { "artifacts" } else { "memories" }
    if (-not ($Index.PSObject.Properties.Name -contains $ArrayName)) {
        throw "PDA lifecycle index is missing '$ArrayName'."
    }

    $Records = @($Index.$ArrayName)
    $KeyName = if ($RecordType -eq "artifact") { "artifact_id" } else { "memory_id" }
    $MatchIndex = -1
    for ($i = 0; $i -lt $Records.Count; $i++) {
        if ([string]$Records[$i].$KeyName -eq $RecordId) {
            $MatchIndex = $i
            break
        }
    }

    if ($MatchIndex -lt 0) {
        throw "Lifecycle record not found: $RecordId"
    }

    $CurrentRecord = $Records[$MatchIndex]
    $FromState = Get-PDALifecycleRecordState -Record $CurrentRecord -Policy $Policy -RecordType $RecordType
    $Transition = Test-PDALifecycleTransition -Policy $Policy -RecordType $RecordType -FromState $FromState -ToState $LifecycleState
    if (-not $Transition.valid) {
        throw "Illegal lifecycle transition for ${RecordId}: ${FromState} -> ${LifecycleState}"
    }

    $HistoryField = [string]$Policy.history_field
    if ([string]::IsNullOrWhiteSpace($HistoryField)) {
        $HistoryField = "lifecycle_history"
    }

    $UpdatedRecord = [pscustomobject]@{}
    foreach ($Property in $CurrentRecord.PSObject.Properties) {
        if ($Property.Name -ne $HistoryField) {
            Add-Member -InputObject $UpdatedRecord -NotePropertyName $Property.Name -NotePropertyValue $Property.Value -Force
        }
    }

    Add-Member -InputObject $UpdatedRecord -NotePropertyName "lifecycle_state" -NotePropertyValue $LifecycleState -Force
    Add-Member -InputObject $UpdatedRecord -NotePropertyName "updated_at" -NotePropertyValue (Get-Date).ToString("o") -Force

    $ExistingHistory = @()
    if ($CurrentRecord.PSObject.Properties.Name -contains $HistoryField -and $null -ne $CurrentRecord.$HistoryField) {
        $ExistingHistory = @($CurrentRecord.$HistoryField)
    }
    $ScriptName = if (-not [string]::IsNullOrWhiteSpace([string]$MyInvocation.MyCommand.Path)) {
        Split-Path -Leaf $MyInvocation.MyCommand.Path
    }
    else {
        [string]$MyInvocation.MyCommand.Name
    }
    $HistoryEntry = Get-PDALifecycleHistoryEntry -RecordId $RecordId -RecordType $RecordType -FromState $FromState -ToState $LifecycleState -Reason $Reason -Actor $Actor -ScriptName $ScriptName
    $NewHistory = @($ExistingHistory + $HistoryEntry)
    Add-Member -InputObject $UpdatedRecord -NotePropertyName $HistoryField -NotePropertyValue $NewHistory -Force

    $Records[$MatchIndex] = $UpdatedRecord
    $Index.$ArrayName = @($Records)
    $Index.updated_at = (Get-Date).ToString("o")

    $Validation = $null
    if ($RecordType -eq "artifact") {
        $Validation = [pscustomobject]@{
            valid = $true
            issue_count = 0
        }
    }
    else {
        . (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")
        $ArtifactLookup = @{}
        if (Test-Path -Path (Join-Path $Root "PDA_ArtifactIndex.json") -PathType Leaf) {
            $ArtifactIndex = Get-Content -Path (Join-Path $Root "PDA_ArtifactIndex.json") -Raw | ConvertFrom-Json
            if ($ArtifactIndex.PSObject.Properties.Name -contains "artifacts") {
                foreach ($Artifact in @($ArtifactIndex.artifacts)) {
                    if ($Artifact.PSObject.Properties.Name -contains "artifact_id" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.artifact_id)) {
                        $ArtifactLookup[[string]$Artifact.artifact_id] = $Artifact
                    }
                }
            }
        }
        $Validation = Assert-PDAMemoryRecordTaxonomyWritable -Record $UpdatedRecord -Taxonomy (Import-PDAMemoryTaxonomy -Root $Root) -ArtifactLookup $ArtifactLookup -Root $Root
    }

    if (-not $Validation.valid) {
        throw "Lifecycle transition produced an invalid record."
    }

    $BackupPath = Get-PDALifecycleBackupPath -Root $Root -RecordType $RecordType -RecordId $RecordId
    if ($PSCmdlet.ShouldProcess($RecordId, "Set $RecordType lifecycle state to $LifecycleState")) {
        New-Item -ItemType Directory -Force -Path $BackupPath | Out-Null
        $BackupFile = (Split-Path -Leaf $IndexPath) + ".bak"
        Copy-Item -Path $IndexPath -Destination (Join-Path $BackupPath $BackupFile) -Force
        $Index | ConvertTo-Json -Depth 30 | Set-Content -Path $IndexPath -Encoding UTF8
    }

    return [pscustomobject]@{
        status = if ($WhatIfPreference) { "dry-run" } else { "pass" }
        record_type = $RecordType
        record_id = $RecordId
        from_state = $FromState
        to_state = $LifecycleState
        backup_path = if ($WhatIfPreference) { "" } else { (Join-Path $BackupPath ((Split-Path -Leaf $IndexPath) + ".bak")) }
        validation_valid = [bool]$Validation.valid
        validation_issue_count = [int]$Validation.issue_count
        history_count = @($NewHistory).Count
        lifecycle_field = $HistoryField
    }
}

function Get-PDALifecycleCounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [ValidateSet("artifact", "memory")]
        [string]$RecordType
    )

    $Policy = Import-PDALifecyclePolicy -Root $Root
    $IndexPath = if ($RecordType -eq "artifact") { Join-Path $Root "PDA_ArtifactIndex.json" } else { Join-Path $Root "PDA_MemoryIndex.json" }
    $ArrayName = if ($RecordType -eq "artifact") { "artifacts" } else { "memories" }
    $Records = @((Get-Content -Path $IndexPath -Raw | ConvertFrom-Json).$ArrayName)

    $Counts = @{}
    foreach ($State in @((Get-PDALifecyclePolicySection -Policy $Policy -RecordType $RecordType).states)) {
        $Counts[[string]$State] = 0
    }

    foreach ($Record in $Records) {
        $State = Get-PDALifecycleRecordState -Record $Record -Policy $Policy -RecordType $RecordType
        if (-not $Counts.ContainsKey($State)) {
            $Counts[$State] = 0
        }
        $Counts[$State]++
    }

    return [pscustomobject]@{
        record_type = $RecordType
        counts = $Counts
        total = $Records.Count
        active = if ($Counts.ContainsKey("active")) { $Counts["active"] } else { 0 }
        archived = if ($Counts.ContainsKey("archived")) { $Counts["archived"] } else { 0 }
        deprecated = if ($Counts.ContainsKey("deprecated")) { $Counts["deprecated"] } else { 0 }
        retired = if ($Counts.ContainsKey("retired")) { $Counts["retired"] } else { 0 }
        promoted = if ($Counts.ContainsKey("promoted")) { $Counts["promoted"] } else { 0 }
        draft = if ($Counts.ContainsKey("draft")) { $Counts["draft"] } else { 0 }
    }
}
