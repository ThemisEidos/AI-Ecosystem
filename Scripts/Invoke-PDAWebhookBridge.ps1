[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmDispatch,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [string]$ConversationId,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$ConversationTitle
)

$ErrorActionPreference = "Stop"

$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$ParsingHelpers = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"

if (-not (Test-Path -Path $BridgeScript -PathType Leaf)) {
    throw "Chat bridge missing: $BridgeScript"
}
if (-not (Test-Path -Path $ParsingHelpers -PathType Leaf)) {
    throw "Parsing helpers missing: $ParsingHelpers"
}

. $ParsingHelpers

function Write-PDAWebhookBridgeFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Failure = [pscustomobject]@{
        original_message      = $Message
        response_text         = "Webhook bridge failed: $Reason"
        recommended_command   = ""
        intent                = ""
        confidence            = 0
        requires_confirmation = $false
        dispatch_ready        = $false
        dispatch_status       = "blocked"
        next_action           = "Inspect the webhook bridge, chat bridge, and PowerShell logs before retrying."
        bridge_status         = "fail_closed"
        handoff_status        = "fail_closed"
        source_of_truth       = "Scripts/PDA_CommandInterpreter.ps1"
        confirmation_mode     = [bool]$ConfirmDispatch
        dispatch_path         = ""
        dispatch_category     = ""
        conversation_id       = $(if ($ConversationId) { $ConversationId } else { "" })
        session_id            = $SessionId
        bridge_mode           = "webhook_bridge"
    }

    if ($AsJson) {
        $Failure | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[ERR] Webhook bridge failed:"
    Write-Host ("Reason               : {0}" -f $Reason)
    Write-Host ("Original message     : {0}" -f $Message)
    return
}

try {
    $BridgeArgs = @(
        "-Message", $Message,
        "-AsJson"
    )

    if ($ConfirmDispatch) {
        $BridgeArgs += "-ConfirmDispatch"
    }
    if ($ConversationId) {
        $BridgeArgs += @("-ConversationId", $ConversationId)
    }
    if ($SessionId) {
        $BridgeArgs += @("-SessionId", $SessionId)
    }
    if ($UserId) {
        $BridgeArgs += @("-UserId", $UserId)
    }
    if ($ConversationTitle) {
        $BridgeArgs += @("-ConversationTitle", $ConversationTitle)
    }

    $Raw = & pwsh -NoProfile -File $BridgeScript @BridgeArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Chat bridge returned exit code $LASTEXITCODE."
    }

    $JsonText = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "Chat bridge returned no output."
    }

    $Parsed = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName "PDA chat bridge"
    if (-not $Parsed) {
        throw "Chat bridge returned invalid JSON."
    }

    if ($AsJson) {
        $Parsed | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] PDA webhook bridge result:"
    Write-Host ("Response text        : {0}" -f $Parsed.response_text)
    Write-Host ("Recommended command  : {0}" -f $(if ($Parsed.recommended_command) { $Parsed.recommended_command } else { "(none)" }))
    Write-Host ("Intent               : {0}" -f $(if ($Parsed.intent) { $Parsed.intent } else { "(none)" }))
    Write-Host ("Confidence           : {0}" -f $Parsed.confidence)
    Write-Host ("Dispatch status      : {0}" -f $Parsed.dispatch_status)
    Write-Host ("Next action          : {0}" -f $Parsed.next_action)
}
catch {
    Write-PDAWebhookBridgeFailure -Reason $_.Exception.Message -Message $Message
    if (-not $AsJson) {
        throw
    }
}
