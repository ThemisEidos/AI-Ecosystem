[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ServerScript = Join-Path $PSScriptRoot "Start-PDAWebhookServer.ps1"
$WorkflowPath = Join-Path $Root "n8n Workflow\PDA-ChatBridge-HTTP.json"
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAWebhookBridge.ps1"

if (-not (Test-Path -Path $ServerScript -PathType Leaf)) {
    throw "HTTP bridge server missing: $ServerScript"
}

if (-not (Test-Path -Path $WorkflowPath -PathType Leaf)) {
    throw "HTTP bridge workflow missing: $WorkflowPath"
}

$ServerContent = Get-Content -Path $ServerScript -Raw
if ($ServerContent -notmatch 'Invoke-PDAWebhookBridge\.ps1') {
    throw "HTTP bridge server does not call the webhook bridge."
}
if ($ServerContent -match 'Submit-PDATask\.ps1|Invoke-PDAWorker\.ps1|process-pda-queue\.ps1|Start-PDAQueueWorker\.ps1') {
    throw "HTTP bridge server contains a queue bypass or direct worker execution path."
}
if (
    $ServerContent -notmatch '\[int\]\$Port = 8788' -or
    $ServerContent -notmatch '\[string\]\$Prefix = "/pda-chat-bridge"' -or
    $ServerContent -notmatch '\[System\.Net\.Sockets\.TcpListener\]' -or
    $ServerContent -notmatch '\[System\.Net\.IPAddress\]::Any' -or
    $ServerContent -notmatch 'http://localhost:\{0\}\{1\}/' -or
    $ServerContent -notmatch 'http://host\.docker\.internal:\{0\}\{1\}/' -or
    $ServerContent -notmatch 'http://gateway\.docker\.internal:\{0\}\{1\}/' -or
    $ServerContent -notmatch 'http://0\.0\.0\.0:\{0\}\{1\}/'
) {
    throw "HTTP bridge server does not advertise the required listener endpoints."
}

$Workflow = Get-Content -Path $WorkflowPath -Raw | ConvertFrom-Json
$WorkflowText = Get-Content -Path $WorkflowPath -Raw

$Issues = New-Object System.Collections.Generic.List[string]
$TimeoutMatch = [regex]::Match($WorkflowText, '"timeout"\s*:\s*(\d+)')
$TimeoutValue = if ($TimeoutMatch.Success) { [int]$TimeoutMatch.Groups[1].Value } else { 0 }

if ($Workflow.name -ne "PDA Chat Bridge HTTP") {
    $Issues.Add("Workflow name mismatch.")
}

if ($WorkflowText -match 'executeCommand') {
    $Issues.Add("Workflow must not use executeCommand.")
}

if ($WorkflowText -notmatch 'http://host\.docker\.internal:8788/pda-chat-bridge') {
    $Issues.Add("Workflow does not target the reachable local HTTP bridge endpoint.")
}

if ($WorkflowText -notmatch '"n8n-nodes-base\.httpRequest"') {
    $Issues.Add("Workflow does not include an HTTP Request node.")
}

if ($WorkflowText -notmatch 'Normalize Request') {
    $Issues.Add("Workflow does not normalize the incoming request.")
}

if ($WorkflowText -notmatch 'Respond to Webhook|Return HTTP Bridge Result') {
    $Issues.Add("Workflow does not return a webhook response.")
}

if (
    $WorkflowText -match [regex]::Escape('={{ .url }}') -or
    $WorkflowText -match [regex]::Escape('={{ .user_message }}') -or
    $WorkflowText -match [regex]::Escape('={{ .confirm_dispatch }}')
) {
    $Issues.Add('Workflow contains broken n8n expressions without $json.')
}

if ($WorkflowText -notmatch 'responseFormat') {
    $Issues.Add("Workflow HTTP Request node does not declare a response format.")
}

if ($WorkflowText -notmatch 'timeout') {
    $Issues.Add("Workflow HTTP Request node does not declare a timeout.")
}
elseif ($TimeoutValue -lt 30000) {
    $Issues.Add("Workflow HTTP Request node timeout is too low ($TimeoutValue ms). Expected at least 30000 ms for host.docker.internal bridge calls.")
}

$ExpectedFields = @(
    "response_text",
    "recommended_command",
    "intent",
    "confidence",
    "requires_confirmation",
    "dispatch_status",
    "next_action"
)

foreach ($Field in $ExpectedFields) {
    if ($WorkflowText -notmatch [regex]::Escape($Field)) {
        $Issues.Add("Workflow response is missing expected field: $Field")
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    server_script = $ServerScript
    workflow_path = $WorkflowPath
    required_endpoint = "http://localhost:8788/pda-chat-bridge"
    n8n_target_endpoint = "http://host.docker.internal:8788/pda-chat-bridge"
    uses_http_request = ($WorkflowText -match '"n8n-nodes-base\.httpRequest"')
    uses_execute_command = ($WorkflowText -match 'executeCommand')
    queue_bypass_detected = ($ServerContent -match 'Submit-PDATask\.ps1|Invoke-PDAWorker\.ps1|process-pda-queue\.ps1|Start-PDAQueueWorker\.ps1' -or $WorkflowText -match 'executeCommand')
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA HTTP bridge workflow validation failed."
    }
    return
}

Write-Host "[*] PDA HTTP bridge workflow validation"
Write-Host ("Server script        : {0}" -f $Report.server_script)
Write-Host ("Workflow path        : {0}" -f $Report.workflow_path)
Write-Host ("Required endpoint    : {0}" -f $Report.required_endpoint)
Write-Host ("n8n target endpoint  : {0}" -f $Report.n8n_target_endpoint)
Write-Host ("Uses HTTP request    : {0}" -f $Report.uses_http_request)
Write-Host ("Uses executeCommand  : {0}" -f $Report.uses_execute_command)
Write-Host ("Queue bypass detected: {0}" -f $Report.queue_bypass_detected)
Write-Host ("Status               : {0}" -f $Report.status)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA HTTP bridge workflow validation failed."
}
