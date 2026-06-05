[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkerName,

    [Parameter(Mandatory = $false)]
    [string]$TaskType,

    [Parameter(Mandatory = $false)]
    [string]$Command,

    [Parameter(Mandatory = $false)]
    [string]$Category,

    [Parameter(Mandatory = $false)]
    [string]$Sensitivity = "standard",

    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [string]$PolicyPath,

    [Parameter(Mandatory = $false)]
    [string]$Endpoint = "http://localhost:4000/v1/chat/completions"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RouteScript = Join-Path $PSScriptRoot "Get-PDAModelRoute.ps1"
$ResolvedPolicyPath = if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    Join-Path $PSScriptRoot "PDA_ModelRouting.json"
} else {
    $PolicyPath
}

function ConvertTo-PDAHashtable {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            if ($null -eq $Value[$Key]) {
                $Copy[$Key] = $null
            }
            else {
                $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
            }
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            if ($null -eq $Item) {
                $List += $null
            }
            else {
                $List += ,(ConvertTo-PDAHashtable -Value $Item)
            }
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            if ($null -eq $Prop.Value) {
                $Copy[$Prop.Name] = $null
            }
            else {
                $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
            }
        }
        return $Copy
    }

    return $Value
}

function Get-PDAJsonText {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [string]) {
        return [string]$Value
    }

    try {
        return ($Value | ConvertTo-Json -Depth 20 -Compress)
    }
    catch {
        return [string]$Value
    }
}

function Get-PDAChatContent {
    param([Parameter(Mandatory = $false)]$Payload)

    if ($null -eq $Payload) {
        return ""
    }

    if ($Payload -is [string]) {
        return [string]$Payload
    }

    foreach ($PropertyName in @("response_text", "content", "text", "message")) {
        if ($Payload.PSObject.Properties.Name -contains $PropertyName) {
            $PropertyValue = $Payload.$PropertyName
            if ($PropertyName -eq "message" -and $PropertyValue) {
                if ($PropertyValue.PSObject.Properties.Name -contains "content" -and -not [string]::IsNullOrWhiteSpace([string]$PropertyValue.content)) {
                    return [string]$PropertyValue.content
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$PropertyValue)) {
                return [string]$PropertyValue
            }
        }
    }

    foreach ($ContainerName in @("choices", "data", "body", "json")) {
        if ($Payload.PSObject.Properties.Name -contains $ContainerName) {
            $Container = $Payload.$ContainerName
            if ($Container -is [System.Collections.IEnumerable] -and $Container -isnot [string]) {
                foreach ($Item in @($Container)) {
                    $Text = Get-PDAChatContent -Payload $Item
                    if (-not [string]::IsNullOrWhiteSpace($Text)) {
                        return $Text
                    }
                }
            }
            else {
                $Text = Get-PDAChatContent -Payload $Container
                if (-not [string]::IsNullOrWhiteSpace($Text)) {
                    return $Text
                }
            }
        }
    }

    foreach ($Property in $Payload.PSObject.Properties) {
        if ($Property.Value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$Property.Value)) {
            return [string]$Property.Value
        }
    }

    return ""
}

function Get-PDAChatUsage {
    param([Parameter(Mandatory = $false)]$Payload)

    if ($null -eq $Payload) {
        return $null
    }

    foreach ($ContainerName in @("usage", "data", "body", "json")) {
        if ($Payload.PSObject.Properties.Name -contains $ContainerName) {
            $Container = $Payload.$ContainerName
            if ($Container -and $Container.PSObject.Properties.Name -contains "usage") {
                return ConvertTo-PDAHashtable -Value $Container.usage
            }
            if ($ContainerName -eq "usage") {
                return ConvertTo-PDAHashtable -Value $Container
            }
        }
    }

    if ($Payload.PSObject.Properties.Name -contains "usage") {
        return ConvertTo-PDAHashtable -Value $Payload.usage
    }

    return $null
}

function Get-PDAModelTransportModel {
    param([Parameter(Mandatory = $true)][string]$LogicalModel)

    return [string]$LogicalModel
}

function Get-PDARequiredEnvironmentVariable {
    param([Parameter(Mandatory = $true)][string]$Name)

    $Value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "LITELLM_MASTER_KEY is not set. Configure it in the approved runtime secret source."
    }

    return [string]$Value
}

function Invoke-PDAModelAttempt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogicalModel,

        [Parameter(Mandatory = $true)]
        [string]$PromptText,

        [Parameter(Mandatory = $true)]
        [array]$MessagesText,

        [Parameter(Mandatory = $true)]
        [string]$EndpointText,

        [Parameter(Mandatory = $true)]
        [hashtable]$HeadersText
    )

    $AttemptTransportModel = Get-PDAModelTransportModel -LogicalModel $LogicalModel
    $RequestBody = [ordered]@{
        model = $AttemptTransportModel
        messages = $MessagesText
        temperature = 0.0
        stream = $false
    }

    $RequestJson = $RequestBody | ConvertTo-Json -Depth 20

    try {
        $Response = Invoke-WebRequest -Uri $EndpointText -Method Post -Headers $HeadersText -ContentType "application/json" -Body $RequestJson -UseBasicParsing -TimeoutSec 120
        $HttpStatus = [int]$Response.StatusCode
        $HttpStatusDescription = [string]$Response.StatusDescription
        $ResponsePayload = $null
        if (-not [string]::IsNullOrWhiteSpace($Response.Content)) {
            $ResponsePayload = $Response.Content | ConvertFrom-Json -ErrorAction Stop
        }

        $ResponseText = Get-PDAChatContent -Payload $ResponsePayload
        $Usage = Get-PDAChatUsage -Payload $ResponsePayload
        $Choice = $null
        if ($ResponsePayload -and $ResponsePayload.PSObject.Properties.Name -contains "choices") {
            $Choice = @($ResponsePayload.choices) | Select-Object -First 1
        }

        return [pscustomobject]@{
            success = ($HttpStatus -ge 200 -and $HttpStatus -lt 300 -and -not [string]::IsNullOrWhiteSpace($ResponseText))
            logical_model = $LogicalModel
            transport_model = $AttemptTransportModel
            http_status = $HttpStatus
            http_status_description = $HttpStatusDescription
            response_payload = $ResponsePayload
            response_text = $ResponseText
            usage = $Usage
            choice = $Choice
            error_message = ""
            error_payload = $null
        }
    }
    catch {
        $Exception = $_.Exception
        $ErrorPayload = $null
        if ($Exception.Response) {
            try {
                $Stream = $Exception.Response.GetResponseStream()
                if ($Stream) {
                    $Reader = New-Object System.IO.StreamReader($Stream)
                    $ErrorContent = $Reader.ReadToEnd()
                    if (-not [string]::IsNullOrWhiteSpace($ErrorContent)) {
                        $ErrorPayload = $ErrorContent | ConvertFrom-Json -ErrorAction SilentlyContinue
                    }
                }
            }
            catch {}
        }

        return [pscustomobject]@{
            success = $false
            logical_model = $LogicalModel
            transport_model = $AttemptTransportModel
            http_status = if ($Exception.Response -and $Exception.Response.StatusCode) { [int]$Exception.Response.StatusCode } else { $null }
            http_status_description = if ($Exception.Response -and $Exception.Response.StatusDescription) { [string]$Exception.Response.StatusDescription } else { "" }
            response_payload = $null
            response_text = ""
            usage = $null
            choice = $null
            error_message = $Exception.Message
            error_payload = if ($ErrorPayload) { ConvertTo-PDAHashtable -Value $ErrorPayload } else { $null }
        }
    }
}

if (-not (Test-Path -Path $RouteScript -PathType Leaf)) {
    throw "Model routing script missing: $RouteScript"
}
if (-not (Test-Path -Path $ResolvedPolicyPath -PathType Leaf)) {
    throw "Model routing policy missing: $ResolvedPolicyPath"
}

$RouteArgs = @(
    "-WorkerName", $WorkerName,
    "-Sensitivity", $Sensitivity,
    "-Category", $Category,
    "-PolicyPath", $ResolvedPolicyPath,
    "-AsJson"
)
if (-not [string]::IsNullOrWhiteSpace($TaskType)) {
    $RouteArgs += @("-TaskType", $TaskType)
}
if (-not [string]::IsNullOrWhiteSpace($Command)) {
    $RouteArgs += @("-Command", $Command)
}

$RouteRaw = & pwsh -NoProfile -File $RouteScript @RouteArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Routing lookup failed for worker '$WorkerName'."
}

$RouteJson = [string]($RouteRaw -join "`n").Trim()
if ([string]::IsNullOrWhiteSpace($RouteJson)) {
    throw "Routing lookup returned no output."
}

$Route = $RouteJson | ConvertFrom-Json
if (-not $Route) {
    throw "Routing lookup returned invalid JSON."
}

$NormalizedSensitivity = [string]$Route.sensitivity
$NormalizedCategory = [string]$Route.category
$PrimaryModel = [string]$Route.primary_model
$SelectedModel = [string]$Route.selected_model
$FallbackChain = @($Route.fallback_chain | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
$CloudAllowed = [bool]$Route.cloud_allowed

if ($NormalizedCategory -in @("category_2", "restricted_local") -and $SelectedModel -ne "local-llama") {
    throw "Category 2 and restricted_local tasks must route to local-llama only."
}
if ([string]::IsNullOrWhiteSpace($SelectedModel)) {
    throw "Routing lookup did not resolve a model."
}
if (($NormalizedCategory -in @("category_2", "restricted_local")) -and $CloudAllowed) {
    throw "Category 2 and restricted_local routes cannot allow cloud fallback."
}

$MasterKey = Get-PDARequiredEnvironmentVariable -Name "LITELLM_MASTER_KEY"
$SystemPrompt = "You are the PDA model invocation adapter. Respond directly and concisely."

$Messages = @(
    [ordered]@{
        role = "system"
        content = $SystemPrompt
    }
    [ordered]@{
        role = "user"
        content = $Prompt
    }
)

$Headers = @{
    Authorization = "Bearer $MasterKey"
}

$LogicalCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($SelectedModel)) {
    $LogicalCandidates += $SelectedModel
}
foreach ($Candidate in $FallbackChain) {
    if ($LogicalCandidates -notcontains $Candidate) {
        $LogicalCandidates += $Candidate
    }
}
$AllowFallback = ($CloudAllowed -and $FallbackChain.Count -gt 0)
if (-not $AllowFallback) {
    $LogicalCandidates = @($SelectedModel)
}

$Attempts = @()
$SuccessfulAttempt = $null
foreach ($LogicalCandidate in $LogicalCandidates) {
    $Attempt = Invoke-PDAModelAttempt -LogicalModel $LogicalCandidate -PromptText $Prompt -MessagesText $Messages -EndpointText $Endpoint -HeadersText $Headers
    $Attempts += $Attempt
    if ($Attempt.success) {
        $SuccessfulAttempt = $Attempt
        break
    }
}

$FinalAttempt = if ($SuccessfulAttempt) { $SuccessfulAttempt } elseif ($Attempts.Count -gt 0) { $Attempts[-1] } else { $null }
$FallbackUsed = $false
if ($SuccessfulAttempt -and $Attempts.Count -gt 1) {
    $FallbackUsed = $true
}

if (-not $SuccessfulAttempt) {
    $FailureMessage = if ($FinalAttempt -and -not [string]::IsNullOrWhiteSpace($FinalAttempt.error_message)) { $FinalAttempt.error_message } elseif ($FinalAttempt -and $FinalAttempt.http_status) { "HTTP $($FinalAttempt.http_status) from LiteLLM." } else { "PDA model invocation failed." }
    $Failure = [pscustomobject]@{
        status = "fail"
        adapter = "Invoke-PDAModel.ps1"
        routing = [pscustomobject]@{
            worker_name = $WorkerName
            task_type = $TaskType
            sensitivity = $NormalizedSensitivity
            route_source = [string]$Route.route_source
            routing_surface = [string]$Route.routing_surface
            routing_gateway = [string]$Route.routing_gateway
            via_litellm = [bool]$Route.via_litellm
            command = [string]$Route.command
            category = $NormalizedCategory
            requested_model = $PrimaryModel
            primary_model = $PrimaryModel
            selected_model = if ($FinalAttempt) { [string]$FinalAttempt.logical_model } else { $SelectedModel }
            transport_model = if ($FinalAttempt) { [string]$FinalAttempt.transport_model } else { Get-PDAModelTransportModel -LogicalModel $SelectedModel }
            fallback_chain = @($FallbackChain)
            model_candidates = @($LogicalCandidates)
            provider_families = @($Route.provider_families)
            routing_reason = [string]$Route.routing_reason
            reason = [string]$Route.routing_reason
            cloud_allowed = $CloudAllowed
        }
        fallback = [pscustomobject]@{
            allowed = [bool]$AllowFallback
            used = $FallbackUsed
            attempt_count = $Attempts.Count
            from_model = if ($FallbackUsed) { [string]$Attempts[0].logical_model } else { "" }
            to_model = if ($SuccessfulAttempt) { [string]$SuccessfulAttempt.logical_model } else { "" }
            attempts = @($Attempts | ForEach-Object {
                [pscustomobject]@{
                    logical_model = [string]$_.logical_model
                    transport_model = [string]$_.transport_model
                    success = [bool]$_.success
                    http_status = $_.http_status
                    error_message = [string]$_.error_message
                }
            })
        }
        request = [pscustomobject]@{
            endpoint = $Endpoint
            method = "POST"
            model = if ($FinalAttempt) { [string]$FinalAttempt.transport_model } else { Get-PDAModelTransportModel -LogicalModel $SelectedModel }
            temperature = 0.0
            stream = $false
            messages = $Messages
            prompt = $Prompt
        }
        response = [pscustomobject]@{
            http_status = if ($FinalAttempt) { $FinalAttempt.http_status } else { $null }
            http_status_description = if ($FinalAttempt) { [string]$FinalAttempt.http_status_description } else { "" }
            id = ""
            model = if ($FinalAttempt) { [string]$FinalAttempt.transport_model } else { Get-PDAModelTransportModel -LogicalModel $SelectedModel }
            created = $null
            finish_reason = ""
            usage = $null
            error = if ($FinalAttempt -and $FinalAttempt.error_payload) { $FinalAttempt.error_payload } else { $null }
            error_message = $FailureMessage
        }
        response_text = ""
        normalized_response_text = ""
        next_action = "Inspect LiteLLM routing, upstream provider credentials, and the local proxy logs."
        source_of_truth = "Scripts/Get-PDAModelRoute.ps1"
    }

    if ($AsJson) {
        $Failure | ConvertTo-Json -Depth 20
        if (-not $NoThrow) {
            throw "PDA model invocation failed."
        }
        return
    }

    Write-Host "[ERR] PDA model invocation failed"
    Write-Host ("Reason : {0}" -f $FailureMessage)
    if (-not $NoThrow) {
        throw "PDA model invocation failed."
    }
    return
}

$Normalized = [pscustomobject]@{
    status = "pass"
    adapter = "Invoke-PDAModel.ps1"
        routing = [pscustomobject]@{
            worker_name = $WorkerName
            task_type = $TaskType
            sensitivity = $NormalizedSensitivity
            route_source = [string]$Route.route_source
            routing_surface = [string]$Route.routing_surface
            routing_gateway = [string]$Route.routing_gateway
            via_litellm = [bool]$Route.via_litellm
            command = [string]$Route.command
            category = $NormalizedCategory
            requested_model = $PrimaryModel
            primary_model = $PrimaryModel
            selected_model = [string]$SuccessfulAttempt.logical_model
            transport_model = [string]$SuccessfulAttempt.transport_model
            fallback_chain = @($FallbackChain)
            model_candidates = @($LogicalCandidates)
            provider_families = @($Route.provider_families)
            routing_reason = [string]$Route.routing_reason
            reason = [string]$Route.routing_reason
            cloud_allowed = $CloudAllowed
        }
    fallback = [pscustomobject]@{
        allowed = [bool]$AllowFallback
        used = $FallbackUsed
        attempt_count = $Attempts.Count
        from_model = if ($FallbackUsed) { [string]$Attempts[0].logical_model } else { "" }
        to_model = [string]$SuccessfulAttempt.logical_model
        attempts = @($Attempts | ForEach-Object {
            [pscustomobject]@{
                logical_model = [string]$_.logical_model
                transport_model = [string]$_.transport_model
                success = [bool]$_.success
                http_status = $_.http_status
                error_message = [string]$_.error_message
            }
        })
    }
    request = [pscustomobject]@{
        endpoint = $Endpoint
        method = "POST"
        model = [string]$SuccessfulAttempt.transport_model
        temperature = 0.0
        stream = $false
        messages = $Messages
        prompt = $Prompt
    }
    response = [pscustomobject]@{
        http_status = $SuccessfulAttempt.http_status
        http_status_description = [string]$SuccessfulAttempt.http_status_description
        id = if ($SuccessfulAttempt.response_payload -and $SuccessfulAttempt.response_payload.PSObject.Properties.Name -contains "id") { [string]$SuccessfulAttempt.response_payload.id } else { "" }
        model = if ($SuccessfulAttempt.response_payload -and $SuccessfulAttempt.response_payload.PSObject.Properties.Name -contains "model") { [string]$SuccessfulAttempt.response_payload.model } else { [string]$SuccessfulAttempt.transport_model }
        created = if ($SuccessfulAttempt.response_payload -and $SuccessfulAttempt.response_payload.PSObject.Properties.Name -contains "created") { $SuccessfulAttempt.response_payload.created } else { $null }
        finish_reason = if ($SuccessfulAttempt.choice -and $SuccessfulAttempt.choice.PSObject.Properties.Name -contains "finish_reason") { [string]$SuccessfulAttempt.choice.finish_reason } else { "" }
        usage = $SuccessfulAttempt.usage
        raw = ConvertTo-PDAHashtable -Value $SuccessfulAttempt.response_payload
    }
    response_text = [string]$SuccessfulAttempt.response_text
    normalized_response_text = [string]$SuccessfulAttempt.response_text
    next_action = if (-not [string]::IsNullOrWhiteSpace([string]$SuccessfulAttempt.response_text)) { "Use the response text or inspect the raw response if you need provider metadata." } else { "Inspect LiteLLM routing, upstream provider credentials, and the local proxy logs." }
    source_of_truth = "Scripts/Get-PDAModelRoute.ps1"
}

if ($AsJson) {
    $Normalized | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Normalized.status -ne "pass") {
        throw "PDA model invocation failed."
    }
    return
}

Write-Host "[PDA MODEL INVOCATION]"
Write-Host ("Worker          : {0}" -f $WorkerName)
Write-Host ("Task type       : {0}" -f $(if ($TaskType) { $TaskType } else { "(none)" }))
Write-Host ("Sensitivity     : {0}" -f $NormalizedSensitivity)
Write-Host ("Selected model  : {0}" -f $SuccessfulAttempt.logical_model)
Write-Host ("Transport model : {0}" -f $SuccessfulAttempt.transport_model)
Write-Host ("HTTP status     : {0}" -f $SuccessfulAttempt.http_status)
Write-Host ("Fallback used   : {0}" -f $FallbackUsed)
Write-Host ("Response text   : {0}" -f $SuccessfulAttempt.response_text)

if (-not $NoThrow -and $Normalized.status -ne "pass") {
    throw "PDA model invocation failed."
}
