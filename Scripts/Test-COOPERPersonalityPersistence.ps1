[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$UpdateScript = Join-Path $PSScriptRoot "Update-COOPERPersonality.ps1"
$IdentityScript = Join-Path $PSScriptRoot "Get-COOPERIdentity.ps1"
$StateScript = Join-Path $PSScriptRoot "Get-PDAConversationState.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}
if (Test-Path -LiteralPath $IdentityScript -PathType Leaf) {
    . $IdentityScript
}

function Invoke-COOPERJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
}

$OriginalProfilePath = Join-Path $Root "Scripts\COOPER_Personality.json"
$TempProfilePath = Join-Path $Root "tmp\COOPER_Personality.test.$([guid]::NewGuid().ToString('N')).json"
$ConversationId = "cooper-personality-test-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
$SessionId = "sess-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
$Issues = New-Object System.Collections.Generic.List[string]
$Results = @()
$BackupStatePath = Join-Path $Root "PDA-Runtime\data\conversation-state.json"
$StateBackupPath = Join-Path $Root "tmp\conversation-state.$([guid]::NewGuid().ToString('N')).json"
$HadState = Test-Path -LiteralPath $BackupStatePath -PathType Leaf

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TempProfilePath) | Out-Null
Copy-Item -LiteralPath $OriginalProfilePath -Destination $TempProfilePath -Force
if ($HadState) {
    Copy-Item -LiteralPath $BackupStatePath -Destination $StateBackupPath -Force
}
else {
    $StateBackupPath = $null
}

$env:COOPER_PERSONALITY_PATH = $TempProfilePath

try {
    $Identity = Get-COOPERIdentity -Root $Root
    if (-not ($Identity.personality.humor_level -eq 65 -and $Identity.personality.directness_level -eq 90 -and $Identity.personality.formality_level -eq 35)) {
        $Issues.Add("Initial personality profile did not load the expected defaults.")
    }

    $ReadResult = [pscustomobject]@{
        name = "read personality"
        passed = $true
        details = "Loaded COOPER identity from the temporary personality profile."
    }
    $Results += $ReadResult

    $ProposalRaw = & pwsh -NoProfile -File $BridgeScript -Message "Set humor to 50." -ConversationId $ConversationId -SessionId $SessionId -AsJson 2>&1
    $Proposal = ConvertFrom-PDAMixedJson -Text ([string]($ProposalRaw -join "`n")) -SourceName $BridgeScript
    if ($Proposal.handoff_status -ne "personality_update") {
        $Issues.Add("Personality proposal did not route to personality_update.")
    }
    if ($Proposal.response_text -notmatch '(?i)Proposed update|Confirm\?') {
        $Issues.Add("Personality proposal did not ask for confirmation.")
    }

    $TempAfterProposal = Get-Content -LiteralPath $TempProfilePath -Raw | ConvertFrom-Json
    if ([int]$TempAfterProposal.personality.humor_level -ne 65) {
        $Issues.Add("Temporary profile changed before confirmation.")
    }

    $StateAfterProposal = Invoke-COOPERJsonScript -Path $StateScript -Arguments @("-ConversationId", $ConversationId, "-SessionId", $SessionId, "-AsJson", "-NoThrow")
    if (-not ($StateAfterProposal -and $StateAfterProposal.pending_personality_change)) {
        $Issues.Add("Pending personality change was not stored in conversation state.")
    }

    $ProposalResult = [pscustomobject]@{
        name = "propose change"
        passed = ($Proposal.handoff_status -eq "personality_update" -and $Proposal.response_text -match '(?i)Confirm\?')
        details = [string]$Proposal.response_text
    }
    $Results += $ProposalResult

    $BackupBeforeConfirm = @(Get-ChildItem -Path (Join-Path $Root "PDA-Backups\personality") -Recurse -File -ErrorAction SilentlyContinue)
    $ConfirmRaw = & pwsh -NoProfile -File $BridgeScript -Message "Confirm" -ConversationId $ConversationId -SessionId $SessionId -AsJson 2>&1
    $Confirm = ConvertFrom-PDAMixedJson -Text ([string]($ConfirmRaw -join "`n")) -SourceName $BridgeScript
    if ($Confirm.handoff_status -ne "personality_update_applied") {
        $Issues.Add("Personality confirmation did not apply the update.")
    }

    $TempAfterConfirm = Get-Content -LiteralPath $TempProfilePath -Raw | ConvertFrom-Json
    if ([int]$TempAfterConfirm.personality.humor_level -ne 50) {
        $Issues.Add("Temporary profile was not updated to the confirmed value.")
    }

    if (-not ($TempAfterConfirm.personality.PSObject.Properties.Name -contains "humor_level")) {
        $Issues.Add("Temporary profile JSON became invalid after write.")
    }

    $BackupAfterConfirm = @(Get-ChildItem -Path (Join-Path $Root "PDA-Backups\personality") -Recurse -File -ErrorAction SilentlyContinue)
    if ($BackupAfterConfirm.Count -le $BackupBeforeConfirm.Count) {
        $Issues.Add("No personality backup file was created.")
    }

    if ($Confirm.PSObject.Properties.Name -contains "personality_update" -and $Confirm.personality_update) {
        if (-not (Test-Path -LiteralPath ([string]$Confirm.personality_update.backup_path) -PathType Leaf)) {
            $Issues.Add("Reported backup path does not exist.")
        }
        if (-not (Test-Path -LiteralPath ([string]$Confirm.personality_update.audit_log_path) -PathType Leaf)) {
            $Issues.Add("Reported audit log path does not exist.")
        }
    }

    $ConfirmResult = [pscustomobject]@{
        name = "confirm change"
        passed = ($Confirm.handoff_status -eq "personality_update_applied" -and [int]$TempAfterConfirm.personality.humor_level -eq 50)
        details = [string]$Confirm.response_text
    }
    $Results += $ConfirmResult

    $CancelBridgeRaw = & pwsh -NoProfile -File $BridgeScript -Message "Set directness to 95." -ConversationId $ConversationId -SessionId $SessionId -AsJson 2>&1
    $CancelBridge = ConvertFrom-PDAMixedJson -Text ([string]($CancelBridgeRaw -join "`n")) -SourceName $BridgeScript
    $CancelRaw = & pwsh -NoProfile -File $BridgeScript -Message "Cancel personality change." -ConversationId $ConversationId -SessionId $SessionId -AsJson 2>&1
    $Cancel = ConvertFrom-PDAMixedJson -Text ([string]($CancelRaw -join "`n")) -SourceName $BridgeScript
    if ($Cancel.handoff_status -ne "personality_cancelled") {
        $Issues.Add("Personality cancellation did not clear the pending change.")
    }

    $TempAfterCancel = Get-Content -LiteralPath $TempProfilePath -Raw | ConvertFrom-Json
    if ([int]$TempAfterCancel.personality.directness_level -ne 90) {
        $Issues.Add("Personality cancel test failed to preserve the current profile state.")
    }

    $StateAfterCancel = Invoke-COOPERJsonScript -Path $StateScript -Arguments @("-ConversationId", $ConversationId, "-SessionId", $SessionId, "-AsJson", "-NoThrow")
    if ($StateAfterCancel -and $StateAfterCancel.pending_personality_change) {
        $Issues.Add("Pending personality change remained in conversation state after cancellation.")
    }

    $CancelResult = [pscustomobject]@{
        name = "cancel change"
        passed = ($Cancel.handoff_status -eq "personality_cancelled")
        details = [string]$Cancel.response_text
    }
    $Results += $CancelResult

    $InvalidRaw = & pwsh -NoProfile -File $UpdateScript -Setting humor -Value 250 -ProfilePath $TempProfilePath -AsJson -NoThrow 2>&1
    $Invalid = ConvertFrom-PDAMixedJson -Text ([string]($InvalidRaw -join "`n")) -SourceName $UpdateScript
    if ($Invalid.status -eq "pass") {
        $Issues.Add("Invalid value rejection did not fail as expected.")
    }
    if ($Invalid.message -notmatch '(?i)between 0 and 100|numeric') {
        $Issues.Add("Invalid value rejection did not explain the allowed range.")
    }

    $InvalidResult = [pscustomobject]@{
        name = "invalid value rejection"
        passed = ($Invalid.status -ne "pass")
        details = [string]$Invalid.message
    }
    $Results += $InvalidResult
}
finally {
    if ($HadState -and (Test-Path -LiteralPath $StateBackupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $StateBackupPath -Destination $BackupStatePath -Force
        Remove-Item -LiteralPath $StateBackupPath -Force -ErrorAction SilentlyContinue
    }
    elseif (-not $HadState -and (Test-Path -LiteralPath $BackupStatePath -PathType Leaf)) {
        Remove-Item -LiteralPath $BackupStatePath -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $TempProfilePath -PathType Leaf) {
        Remove-Item -LiteralPath $TempProfilePath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:\COOPER_PERSONALITY_PATH -ErrorAction SilentlyContinue
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    test_case_count = @($Results).Count
    passed_count = @($Results | Where-Object { $_.passed }).Count
    failed_count = @($Results | Where-Object { -not $_.passed }).Count
    results = @($Results)
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "COOPER personality persistence validation failed."
    }
    return
}

Write-Host "[*] COOPER personality persistence tests"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "COOPER personality persistence validation failed."
}
