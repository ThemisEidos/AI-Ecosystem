[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ClipboardPath = Join-Path $Root "n8n Workflow\PDA-ChatBridge-HTTP-Clipboard.json"

if (-not (Test-Path -Path $ClipboardPath -PathType Leaf)) {
    throw "Clipboard workflow missing: $ClipboardPath"
}

$ClipboardRaw = Get-Content -Path $ClipboardPath -Raw
$Clipboard = $ClipboardRaw | ConvertFrom-Json

$Issues = New-Object System.Collections.Generic.List[string]

if (-not $Clipboard.nodes) {
    $Issues.Add("nodes array is missing.")
}
elseif (@($Clipboard.nodes).Count -eq 0) {
    $Issues.Add("nodes array is empty.")
}

if ($ClipboardRaw -match 'executeCommand|Submit-PDATask\.ps1|Invoke-PDAWorker\.ps1|process-pda-queue\.ps1|Start-PDAQueueWorker\.ps1') {
    $Issues.Add("Clipboard workflow contains a queue or worker bypass.")
}

if (
    $ClipboardRaw -match [regex]::Escape('={{ .url }}') -or
    $ClipboardRaw -match [regex]::Escape('={{ .user_message }}') -or
    $ClipboardRaw -match [regex]::Escape('={{ .confirm_dispatch }}')
) {
    $Issues.Add('Clipboard workflow contains broken n8n expressions without $json.')
}

$RequiredNodeNames = @(
    "PDA HTTP Webhook",
    "Normalize Request",
    "Invoke Local HTTP Bridge",
    "Return HTTP Bridge Result"
)

foreach ($Name in $RequiredNodeNames) {
    if ($ClipboardRaw -notmatch [regex]::Escape($Name)) {
        $Issues.Add("Missing node: $Name")
    }
}

if ($ClipboardRaw -notmatch 'http://host\.docker\.internal:8788/pda-chat-bridge') {
    $Issues.Add("HTTP Request node does not target the required local bridge endpoint.")
}

if ($ClipboardRaw -notmatch 'timeout') {
    $Issues.Add("HTTP Request node does not declare a timeout.")
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    clipboard_path = $ClipboardPath
    node_count = if ($Clipboard.nodes) { @($Clipboard.nodes).Count } else { 0 }
    has_connections = [bool]$Clipboard.connections
    contains_http_request = ($ClipboardRaw -match 'n8n-nodes-base\.httpRequest')
    contains_execute_command = ($ClipboardRaw -match 'executeCommand')
    issues = @($Issues)
    import_instruction = "Open the n8n canvas and paste the JSON from Scripts/New-PDAN8nClipboardWorkflow.ps1 output or from n8n Workflow/PDA-ChatBridge-HTTP-Clipboard.json."
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA n8n clipboard workflow validation failed."
    }
    return
}

Write-Host "[*] PDA n8n clipboard workflow validation"
Write-Host ("Clipboard path       : {0}" -f $Report.clipboard_path)
Write-Host ("Node count           : {0}" -f $Report.node_count)
Write-Host ("Has connections      : {0}" -f $Report.has_connections)
Write-Host ("Contains HTTP request: {0}" -f $Report.contains_http_request)
Write-Host ("Contains executeCmd  : {0}" -f $Report.contains_execute_command)
Write-Host ("Status               : {0}" -f $Report.status)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA n8n clipboard workflow validation failed."
}
