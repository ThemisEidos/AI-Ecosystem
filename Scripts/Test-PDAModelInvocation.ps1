[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InvokeScript = Join-Path $PSScriptRoot "Invoke-PDAModel.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
$RoutingLogRoot = Join-Path $Root "PDA-Logs\routing"

if (-not (Test-Path -Path $InvokeScript -PathType Leaf)) {
    throw "Model invocation adapter missing: $InvokeScript"
}
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

function Initialize-PDALiteLLMMasterKey {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:LITELLM_MASTER_KEY)) {
        return $true
    }

    $EnvFile = Join-Path $Root "litellm\.env.local"
    if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
        return $false
    }

    try {
        $KeyLine = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -match '^LITELLM_MASTER_KEY=' } | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace([string]$KeyLine)) {
            return $false
        }

        $KeyValue = ([string]$KeyLine -split '=', 2)[1]
        if ([string]::IsNullOrWhiteSpace($KeyValue)) {
            return $false
        }

        [Environment]::SetEnvironmentVariable("LITELLM_MASTER_KEY", $KeyValue, "Process")
        return $true
    }
    catch {
        return $false
    }
}

function Start-PDALocalPlainTextServer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResponseText
    )

    $TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-model-plain-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    $ServerScript = Join-Path $TempRoot "plain_text_server.py"
    $ServerCode = @'
import http.server
import socketserver
import sys

payload = sys.argv[1].encode("utf-8")
port = int(sys.argv[2])

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        if length > 0:
            self.rfile.read(length)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("127.0.0.1", port), Handler) as server:
    server.handle_request()
'@
    Set-Content -LiteralPath $ServerScript -Value $ServerCode -Encoding UTF8

    $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $Listener.Start()
    $Port = [int]$Listener.LocalEndpoint.Port
    $Listener.Stop()

    $Process = Start-Process -FilePath "python" -ArgumentList @("-u", $ServerScript, $ResponseText, [string]$Port) -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 500

    return [pscustomobject]@{
        process = $Process
        endpoint = "http://127.0.0.1:$Port/v1/chat/completions"
        temp_root = $TempRoot
    }
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$WorkerName,

        [Parameter(Mandatory = $false)]
        [string]$TaskType,

        [Parameter(Mandatory = $true)]
        [string]$Sensitivity,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
    [string]$ExpectedModel,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedToken = "",

    [Parameter(Mandatory = $false)]
    [string]$SelectedModelOverride,

    [Parameter(Mandatory = $false)]
    [string]$Endpoint = "http://localhost:4000/v1/chat/completions",

        [Parameter(Mandatory = $false)]
        [string]$ExpectedErrorPattern,

        [Parameter(Mandatory = $false)]
        [switch]$ClearMasterKey,

        [Parameter(Mandatory = $false)]
        [switch]$AllowUnavailable
    )

    $Args = @(
        "-WorkerName", $WorkerName,
        "-Sensitivity", $Sensitivity,
        "-Prompt", $Prompt,
        "-NoThrow",
        "-AsJson"
    )
    if (-not [string]::IsNullOrWhiteSpace($TaskType)) {
        $Args += @("-TaskType", $TaskType)
    }
    if (-not [string]::IsNullOrWhiteSpace($SelectedModelOverride)) {
        $Args += @("-SelectedModelOverride", $SelectedModelOverride)
    }
    if (-not [string]::IsNullOrWhiteSpace($Endpoint)) {
        $Args += @("-Endpoint", $Endpoint)
    }

    $SavedMasterKey = $null
    if ($ClearMasterKey) {
        $SavedMasterKey = [Environment]::GetEnvironmentVariable("LITELLM_MASTER_KEY")
        [Environment]::SetEnvironmentVariable("LITELLM_MASTER_KEY", $null, "Process")
    }

    try {
        $Raw = & pwsh -NoProfile -File $InvokeScript @Args 2>&1
    }
    finally {
        if ($ClearMasterKey) {
            [Environment]::SetEnvironmentVariable("LITELLM_MASTER_KEY", $SavedMasterKey, "Process")
        }
    }

    $JsonText = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "Adapter returned empty output for test case '$Name'."
    }

    $Result = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName $InvokeScript
    if (-not $Result) {
        throw "Adapter output could not be parsed as JSON for test case '$Name'."
    }
    $Issues = New-Object System.Collections.Generic.List[string]
    $Skipped = $false

    $MissingSecret = $false
    if ($Result.PSObject.Properties.Name -contains "response" -and $Result.response -and $Result.response.PSObject.Properties.Name -contains "error_message") {
        $MissingSecret = [bool]($Result.response.error_message -match '(?i)LITELLM_MASTER_KEY|approved runtime secret source')
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedErrorPattern)) {
        if ($Result.status -eq "pass") {
            $Issues.Add("Expected a failure diagnostic but got pass status.")
        }
        $CombinedError = ""
        if ($Result.PSObject.Properties.Name -contains "response" -and $Result.response -and $Result.response.PSObject.Properties.Name -contains "error_message") {
            $CombinedError = [string]$Result.response.error_message
        }
        elseif ($Result.PSObject.Properties.Name -contains "model_error_message") {
            $CombinedError = [string]$Result.model_error_message
        }
        if ([string]::IsNullOrWhiteSpace($CombinedError)) {
            $Issues.Add("Expected an error diagnostic, but no error message was returned.")
        }
        elseif ($CombinedError -notmatch $ExpectedErrorPattern) {
            $Issues.Add("Error diagnostic did not match pattern '$ExpectedErrorPattern'.")
        }
    }
    elseif (($AllowUnavailable -or $MissingSecret) -and $Result.status -ne "pass" -and ($MissingSecret -or $Result.response.http_status -in @(401, 403, 404, 429, 500, 502, 503, 504))) {
        $Skipped = $true
    }
    else {
        if ($Result.status -ne "pass") {
            $Issues.Add("Expected pass status but got '$($Result.status)'.")
        }
        if ([string]$Result.routing.selected_model -ne $ExpectedModel) {
            $Issues.Add("Expected selected model '$ExpectedModel' but got '$($Result.routing.selected_model)'.")
        }
        if ($Result.routing.sensitivity -eq "restricted_local" -and [string]$Result.routing.selected_model -ne "local-llama") {
            $Issues.Add("Restricted local route did not stay on local-llama.")
        }
        if ($Result.routing.routing_gateway -ne "litellm") {
            $Issues.Add("Routing gateway should be LiteLLM.")
        }
        if ($Result.routing.via_litellm -ne $true) {
            $Issues.Add("Adapter did not mark LiteLLM usage.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$Result.routing_audit_log)) {
            $Issues.Add("Routing audit log path is missing.")
        }
        elseif (-not (Test-Path -Path ([string]$Result.routing_audit_log) -PathType Leaf)) {
            $Issues.Add("Routing audit log file was not created.")
        }
        else {
            $AuditRecord = Get-Content -Path ([string]$Result.routing_audit_log) -Raw | ConvertFrom-Json
            if ([string]$AuditRecord.command -ne [string]$Result.routing.command) {
                $Issues.Add("Routing audit command does not match invocation output.")
            }
            if ([string]$AuditRecord.category -ne [string]$Result.routing.category) {
                $Issues.Add("Routing audit category does not match invocation output.")
            }
            if ([string]$AuditRecord.selected_model -ne [string]$Result.routing.selected_model) {
                $Issues.Add("Routing audit selected_model does not match invocation output.")
            }
            if ([string]$AuditRecord.routing_reason -ne [string]$Result.routing.routing_reason) {
                $Issues.Add("Routing audit routing_reason does not match invocation output.")
            }
            if ([string]$AuditRecord.worker -ne $WorkerName) {
                $Issues.Add("Routing audit worker does not match invocation worker.")
            }
            if ([string]$AuditRecord.outcome -ne [string]$Result.status) {
                $Issues.Add("Routing audit outcome does not match invocation status.")
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$Result.response_text) -and [string]::IsNullOrWhiteSpace($ExpectedErrorPattern)) {
            $Issues.Add("Response text is empty.")
        }
        elseif (-not [string]::IsNullOrWhiteSpace($ExpectedToken) -and $Result.response_text -notmatch [regex]::Escape($ExpectedToken)) {
            $Issues.Add("Response text did not contain expected token '$ExpectedToken'.")
        }
    }

    return [pscustomobject]@{
        name = $Name
        passed = ($Issues.Count -eq 0 -and -not $Skipped)
        skipped = $Skipped
        worker_name = $WorkerName
        task_type = $TaskType
        sensitivity = $Sensitivity
        expected_model = $ExpectedModel
        expected_token = $ExpectedToken
        selected_model = [string]$Result.routing.selected_model
        response_text = [string]$Result.response_text
        status = [string]$Result.status
        routing_surface = [string]$Result.routing.routing_surface
        route_source = [string]$Result.routing.route_source
        routing_audit_log = [string]$Result.routing_audit_log
        issues = @($Issues)
    }
}

$Cases = @(
    [pscustomobject]@{
        name = "cooper override local-llama"
        worker_name = "cooper-chat"
        task_type = "conversational"
        sensitivity = "standard"
        prompt = "Return a brief plain acknowledgement."
        expected_model = "local-llama"
        expected_token = ""
        selected_model_override = "local-llama"
    }
    [pscustomobject]@{
        name = "live context env fallback"
        worker_name = "cooper-chat"
        task_type = "conversational"
        sensitivity = "standard"
        prompt = "Return plain acknowledgement."
        expected_model = "local-llama"
        expected_token = "Acknowledged."
        selected_model_override = "local-llama"
        clear_master_key = $true
    }
    [pscustomobject]@{
        name = "restricted local invocation"
        worker_name = "review-worker"
        task_type = "review"
        sensitivity = "restricted_local"
        prompt = "Return exactly: local-ok"
        expected_model = "local-llama"
        expected_token = "local-ok"
    }
    [pscustomobject]@{
        name = "research gemini invocation"
        worker_name = "research-worker"
        task_type = "research"
        sensitivity = "standard"
        prompt = "Return exactly: gemini-ok"
        expected_model = "gemini"
        expected_token = "gemini-ok"
        allow_unavailable = $true
    }
    [pscustomobject]@{
        name = "plain text backend response"
        worker_name = "cooper-chat"
        task_type = "conversational"
        sensitivity = "standard"
        prompt = "Return plain-text-ok."
        expected_model = "local-llama"
        expected_token = "plain-text-ok"
        selected_model_override = "local-llama"
        endpoint = $null
        use_plain_text_server = $true
    }
    [pscustomobject]@{
        name = "missing backend diagnostic"
        worker_name = "cooper-chat"
        task_type = "conversational"
        sensitivity = "standard"
        prompt = "Return an error diagnostic."
        expected_model = "local-llama"
        expected_token = ""
        selected_model_override = "local-llama"
        endpoint = "http://127.0.0.1:1/v1/chat/completions"
        expected_error_pattern = '(?i)connection|refused|failed|error'
    }
)

$EnvReady = Initialize-PDALiteLLMMasterKey
$PlainTextServer = $null
foreach ($Case in $Cases) {
    if ($Case.PSObject.Properties.Name -contains "use_plain_text_server" -and [bool]$Case.use_plain_text_server) {
        if (-not $EnvReady) {
            continue
        }

        $PlainTextServer = Start-PDALocalPlainTextServer -ResponseText "plain-text-ok"
        $Case.endpoint = $PlainTextServer.endpoint
    }
}

$Results = @()
$Passed = 0
$Failed = 0
$Skipped = 0

foreach ($Case in $Cases) {
    if ($Case.PSObject.Properties.Name -contains "use_plain_text_server" -and [bool]$Case.use_plain_text_server -and -not $PlainTextServer) {
        continue
    }

    $CaseResult = Invoke-TestCase -Name $Case.name -WorkerName $Case.worker_name -TaskType $Case.task_type -Sensitivity $Case.sensitivity -Prompt $Case.prompt -ExpectedModel $Case.expected_model -ExpectedToken $Case.expected_token -SelectedModelOverride $Case.selected_model_override -Endpoint $Case.endpoint -ExpectedErrorPattern $Case.expected_error_pattern -ClearMasterKey:([bool]$Case.clear_master_key) -AllowUnavailable:([bool]$Case.allow_unavailable)
    $Results += $CaseResult
    if ($CaseResult.skipped) {
        $Skipped++
    }
    elseif ($CaseResult.passed) {
        $Passed++
    }
    else {
        $Failed++
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    adapter_path = $InvokeScript
    test_case_count = $Cases.Count
    passed_count = $Passed
    failed_count = $Failed
    skipped_count = $Skipped
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA model invocation validation failed."
    }
    return
}

Write-Host "[*] PDA model invocation tests"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)
Write-Host ("Skipped    : {0}" -f $Report.skipped_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA model invocation validation failed."
}
