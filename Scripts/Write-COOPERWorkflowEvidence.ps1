[CmdletBinding()]
param(
    [string]$Root,

    [string]$RecordType,

    [string]$WorkshopId,

    [string]$WorkshopName,

    [string]$WorkflowId,

    [string]$WorkflowName,

    [string]$ExecutionId,

    [string]$Status,

    [string]$CompletionTime,

    [string]$ApprovalId,

    [object[]]$ArtifactPaths,

    [string]$ReviewStatus,

    [object]$UserAccepted,

    [string]$Notes,

    [string]$RequestedTime,

    [string]$StartedTime,

    [string]$CompletedBy,

    [string]$RequestedBy,

    [string]$Trigger,

    [object]$SourceOfTruth,

    [object]$WorkflowChain,

    [string]$ParentWorkflowId,

    [object]$RunContext,

    [object]$Limitations,

    [string]$NextAction,

    [object]$ArtifactSummary,

    [string]$ReviewNotes,

    [string]$ApprovedTime,

    [string]$CompletedTime,

    [string]$BlockedTime,

    [string]$StaleTime,

    [string]$ExpirationTime,

    [string]$Reason,

    [string]$ApprovedBy,

    [string]$BlockedBy,

    [string]$StaleBy,

    [string]$PolicyReference,

    [string]$RequestSummary,

    [string]$DecisionSummary,

    [string]$RelatedExecutionId
)

$ErrorActionPreference = "Stop"

function Get-ScriptDirectory {
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return Split-Path -Parent $PSCommandPath
    }
    if (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
        return Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    return (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-ScriptDirectory
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Test-Iso8601Utc {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $false
    }

    return ([string]$Value) -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'
}

function Get-CanonicalWorkshopName {
    param([Parameter(Mandatory = $true)][string]$Id)

    switch ($Id.ToLowerInvariant()) {
        'open' { return 'Open Workshop' }
        'private' { return 'Private Workshop' }
        default { throw "Invalid workshop_id: $Id" }
    }
}

function Normalize-PathText {
    param([Parameter(Mandatory = $true)][string]$Text)

    return ($Text.Trim() -replace '/', '\').ToLowerInvariant()
}

function Test-SecretMarkerText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }
    return $Text -match '(?i)(?:^|[^a-z0-9_])(api_key|password|secret|token|private_key|credential)(?:$|[^a-z0-9_])'
}

function Assert-NoSecretMarkers {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [string]$Path = 'record'
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -is [string]) {
        if (Test-SecretMarkerText -Text $Value) {
            throw "Secret marker rejected at $Path."
        }
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($Key in @($Value.Keys)) {
            $KeyText = [string]$Key
            if (Test-SecretMarkerText -Text $KeyText) {
                throw "Secret marker rejected in field name at $Path.$KeyText."
            }
            Assert-NoSecretMarkers -Value $Value[$Key] -Path "$Path.$KeyText"
        }
        return
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [byte[]] -and $Value -isnot [string]) {
        $Index = 0
        foreach ($Item in @($Value)) {
            Assert-NoSecretMarkers -Value $Item -Path "$Path[$Index]"
            $Index++
        }
        return
    }

    $Properties = @($Value.PSObject.Properties)
    if ($Properties.Count -gt 0) {
        foreach ($Property in $Properties) {
            if (Test-SecretMarkerText -Text $Property.Name) {
                throw "Secret marker rejected in field name at $Path.$($Property.Name)."
            }
            Assert-NoSecretMarkers -Value $Property.Value -Path "$Path.$($Property.Name)"
        }
        return
    }

    if (Test-SecretMarkerText -Text ([string]$Value)) {
        throw "Secret marker rejected at $Path."
    }
}

function Assert-RequiredString {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing required field: $Name"
    }
}

function Assert-OptionalIsoField {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)]$Value
    )

    if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value) -and -not (Test-Iso8601Utc -Value $Value)) {
        throw "$Name must be ISO 8601 UTC or null."
    }
}

function Test-IsSafeFilenameToken {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value -match '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

function Assert-OpenArtifactPathSafe {
    param(
        [Parameter(Mandatory = $true)][string]$PathText
    )

    $Normalized = Normalize-PathText -Text $PathText
    if ($Normalized -match '(^|\\)restricted dmz workspace(\\|$)' -or
        $Normalized -match '(^|\\)secure vault(\\|$)' -or
        $Normalized -match '(^|\\)standardnotes(\\|$)' -or
        $Normalized -match '(^|\\)private workshop(\\|$)') {
        throw "Open Workshop artifact path violates the compartment boundary."
    }
}

function Assert-PrivateArtifactPathSafe {
    param(
        [Parameter(Mandatory = $true)][string]$PathText
    )

    $Normalized = Normalize-PathText -Text $PathText
    if ($Normalized -notmatch '(^|\\)restricted dmz workspace\\') {
        throw "Private Workshop artifact path must remain inside Restricted DMZ Workspace."
    }
    if ($Normalized -match '(^|\\)secure vault(\\|$)' -or
        $Normalized -match '(^|\\)standardnotes(\\|$)' -or
        $Normalized -match '(^|\\)obsidian(\\|$)' -or
        $Normalized -match '^[a-z][a-z0-9+.\-]*://') {
        throw "Private Workshop artifact path violates the compartment boundary."
    }
}

function New-CompletionRecord {
    param(
        [Parameter(Mandatory = $true)][string]$CanonicalWorkshopName
    )

    Assert-RequiredString -Name 'workflow_id' -Value $WorkflowId
    Assert-RequiredString -Name 'workflow_name' -Value $WorkflowName
    Assert-RequiredString -Name 'execution_id' -Value $ExecutionId
    Assert-RequiredString -Name 'status' -Value $Status
    Assert-RequiredString -Name 'completion_time' -Value $CompletionTime
    Assert-RequiredString -Name 'review_status' -Value $ReviewStatus
    Assert-RequiredString -Name 'notes' -Value $Notes
    Assert-Condition -Condition ($UserAccepted -is [bool]) -Message 'user_accepted must be a boolean.'

    Assert-Condition -Condition ($WorkflowId -match '^WF-\d+$') -Message "workflow_id is invalid: $WorkflowId"
    Assert-Condition -Condition (Test-IsSafeFilenameToken -Value $ExecutionId) -Message "execution_id is invalid: $ExecutionId"
    Assert-Condition -Condition (Test-Iso8601Utc -Value $CompletionTime) -Message 'completion_time must be ISO 8601 UTC.'

    switch ($Status) {
        'pass' { }
        'fail' { }
        'blocked' { }
        'unknown' { }
        default { throw "Invalid completion status: $Status" }
    }

    switch ($ReviewStatus) {
        'pass' { }
        'fail' { }
        'blocked' { }
        'unknown' { }
        default { throw "Invalid review_status: $ReviewStatus" }
    }

    if ($WorkshopId -notin @('open', 'private')) {
        throw "Invalid workshop_id: $WorkshopId"
    }

    if (-not [string]::IsNullOrWhiteSpace($WorkshopName) -and $WorkshopName -ne $CanonicalWorkshopName) {
        throw "workshop_name does not match workshop_id."
    }

    $Record = [ordered]@{
        workflow_id      = $WorkflowId
        workflow_name    = $WorkflowName
        execution_id     = $ExecutionId
        status           = $Status
        completion_time  = $CompletionTime
        workshop_id      = $WorkshopId
        workshop_name    = $CanonicalWorkshopName
        approval_id      = if ($null -eq $ApprovalId) { "" } else { [string]$ApprovalId }
        artifact_paths   = @()
        review_status    = $ReviewStatus
        user_accepted    = [bool]$UserAccepted
        notes            = $Notes
    }

    if ($null -ne $ArtifactPaths) {
        $Record.artifact_paths = @($ArtifactPaths | ForEach-Object { [string]$_ })
    }

    foreach ($Field in @(
        @{ name = 'requested_time'; value = $RequestedTime },
        @{ name = 'started_time'; value = $StartedTime },
        @{ name = 'completed_by'; value = $CompletedBy },
        @{ name = 'requested_by'; value = $RequestedBy },
        @{ name = 'trigger'; value = $Trigger },
        @{ name = 'source_of_truth'; value = $SourceOfTruth },
        @{ name = 'workflow_chain'; value = $WorkflowChain },
        @{ name = 'parent_workflow_id'; value = $ParentWorkflowId },
        @{ name = 'run_context'; value = $RunContext },
        @{ name = 'limitations'; value = $Limitations },
        @{ name = 'next_action'; value = $NextAction },
        @{ name = 'artifact_summary'; value = $ArtifactSummary },
        @{ name = 'review_notes'; value = $ReviewNotes }
    )) {
        if ($null -ne $Field.value -and -not [string]::IsNullOrWhiteSpace([string]$Field.value)) {
            $Record[$Field.name] = $Field.value
        }
    }

    Assert-NoSecretMarkers -Value $Record
    return $Record
}

function New-ApprovalRecord {
    param(
        [Parameter(Mandatory = $true)][string]$CanonicalWorkshopName
    )

    Assert-RequiredString -Name 'approval_id' -Value $ApprovalId
    Assert-RequiredString -Name 'workflow_id' -Value $WorkflowId
    Assert-RequiredString -Name 'status' -Value $Status
    Assert-RequiredString -Name 'requested_time' -Value $RequestedTime
    Assert-RequiredString -Name 'reason' -Value $Reason
    Assert-RequiredString -Name 'notes' -Value $Notes

    Assert-Condition -Condition (Test-IsSafeFilenameToken -Value $ApprovalId) -Message "approval_id is invalid: $ApprovalId"
    Assert-Condition -Condition ($WorkflowId -match '^WF-\d+$') -Message "workflow_id is invalid: $WorkflowId"

    switch ($Status) {
        'pending' { }
        'approved' { }
        'completed' { }
        'stale' { }
        'blocked' { }
        'rejected' { }
        default { throw "Invalid approval status: $Status" }
    }

    foreach ($Field in @(
        @{ name = 'requested_time'; value = $RequestedTime },
        @{ name = 'approved_time'; value = $ApprovedTime },
        @{ name = 'completed_time'; value = $CompletedTime },
        @{ name = 'blocked_time'; value = $BlockedTime },
        @{ name = 'stale_time'; value = $StaleTime },
        @{ name = 'expiration_time'; value = $ExpirationTime }
    )) {
        Assert-OptionalIsoField -Name $Field.name -Value $Field.value
    }

    $Record = [ordered]@{
        approval_id      = $ApprovalId
        workflow_id      = $WorkflowId
        status           = $Status
        requested_time   = $RequestedTime
        approved_time    = $ApprovedTime
        completed_time   = $CompletedTime
        blocked_time     = $BlockedTime
        stale_time       = $StaleTime
        expiration_time  = $ExpirationTime
        reason           = $Reason
        notes            = $Notes
        workshop_id      = $WorkshopId
        workshop_name    = $CanonicalWorkshopName
    }

    foreach ($Field in @(
        @{ name = 'requested_by'; value = $RequestedBy },
        @{ name = 'approved_by'; value = $ApprovedBy },
        @{ name = 'completed_by'; value = $CompletedBy },
        @{ name = 'blocked_by'; value = $BlockedBy },
        @{ name = 'stale_by'; value = $StaleBy },
        @{ name = 'policy_reference'; value = $PolicyReference },
        @{ name = 'request_summary'; value = $RequestSummary },
        @{ name = 'decision_summary'; value = $DecisionSummary },
        @{ name = 'related_execution_id'; value = $RelatedExecutionId }
    )) {
        if ($null -ne $Field.value -and -not [string]::IsNullOrWhiteSpace([string]$Field.value)) {
            $Record[$Field.name] = $Field.value
        }
    }

    if ($null -ne $ArtifactPaths) {
        $Record.artifact_paths = @($ArtifactPaths | ForEach-Object { [string]$_ })
    }

    Assert-NoSecretMarkers -Value $Record
    return $Record
}

function Write-EvidenceFile {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)]$Record
    )

    $TargetDirectory = Split-Path -Parent $TargetPath
    New-Item -ItemType Directory -Force -Path $TargetDirectory | Out-Null
    $JsonText = $Record | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($TargetPath, $JsonText, [System.Text.UTF8Encoding]::new($false))
}

if ([string]::IsNullOrWhiteSpace($RecordType)) {
    throw "RecordType is required."
}
if ([string]::IsNullOrWhiteSpace($WorkshopId)) {
    throw "WorkshopId is required."
}
if ($WorkshopId -notin @('open', 'private')) {
    throw "Invalid workshop_id: $WorkshopId"
}

$CanonicalWorkshopName = Get-CanonicalWorkshopName -Id $WorkshopId
if (-not [string]::IsNullOrWhiteSpace($WorkshopName) -and $WorkshopName -ne $CanonicalWorkshopName) {
    throw "WorkshopName does not match workshop_id."
}

$RepoRoot = [System.IO.Path]::GetFullPath($Root)
switch ($WorkshopId) {
    'open' {
        $EvidenceRoot = Join-Path $RepoRoot 'State\Workflow_Evidence'
        $OutputRootText = Normalize-PathText -Text $EvidenceRoot
        if ($OutputRootText -match 'restricted dmz workspace|secure vault|standardnotes') {
            throw "Open Workshop evidence path violates the compartment boundary."
        }
    }
    'private' {
        $EvidenceRoot = Join-Path $RepoRoot 'Restricted DMZ Workspace\State\Workflow_Evidence'
        $OutputRootText = Normalize-PathText -Text $EvidenceRoot
        if ($OutputRootText -notmatch 'restricted dmz workspace\\state\\workflow_evidence') {
            throw "Private Workshop evidence path violates the compartment boundary."
        }
    }
}

switch ($RecordType.ToLowerInvariant()) {
    'completion' {
        $Record = New-CompletionRecord -CanonicalWorkshopName $CanonicalWorkshopName
        $FileName = "workflow_completion_{0}_{1}.json" -f $WorkflowId, $ExecutionId
        $TargetPath = Join-Path (Join-Path $EvidenceRoot 'completion') $FileName
    }
    'approval' {
        $Record = New-ApprovalRecord -CanonicalWorkshopName $CanonicalWorkshopName
        $FileName = "approval_lifecycle_{0}.json" -f $ApprovalId
        $TargetPath = Join-Path (Join-Path $EvidenceRoot 'approval') $FileName
    }
    default {
        throw "RecordType must be either 'completion' or 'approval'."
    }
}

Assert-Condition -Condition (Test-IsSafeFilenameToken -Value ([System.IO.Path]::GetFileNameWithoutExtension($TargetPath) -replace '^(workflow_completion_|approval_lifecycle_)', '')) -Message "Target filename token is invalid."

if ($RecordType -eq 'completion') {
    foreach ($ArtifactPath in @($Record.artifact_paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$ArtifactPath)) {
            continue
        }
        if ($WorkshopId -eq 'open') {
            Assert-OpenArtifactPathSafe -PathText ([string]$ArtifactPath)
        }
        else {
            Assert-PrivateArtifactPathSafe -PathText ([string]$ArtifactPath)
        }
    }
}
elseif ($RecordType -eq 'approval' -and $Record.PSObject.Properties.Name -contains 'artifact_paths') {
    foreach ($ArtifactPath in @($Record.artifact_paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$ArtifactPath)) {
            continue
        }
        if ($WorkshopId -eq 'open') {
            Assert-OpenArtifactPathSafe -PathText ([string]$ArtifactPath)
        }
        else {
            Assert-PrivateArtifactPathSafe -PathText ([string]$ArtifactPath)
        }
    }
}

Write-EvidenceFile -TargetPath $TargetPath -Record $Record

[pscustomobject]@{
    record_type = $RecordType.ToLowerInvariant()
    workshop_id = $WorkshopId
    workshop_name = $CanonicalWorkshopName
    path = $TargetPath
    record = $Record
}
