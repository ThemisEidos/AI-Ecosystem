[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 8788,

    [Parameter(Mandatory = $false)]
    [string]$Prefix = "/pda-chat-bridge"
)

$ErrorActionPreference = "Stop"

$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$OutputParsingScript = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (-not (Test-Path -Path $BridgeScript -PathType Leaf)) {
    throw "Chat bridge missing: $BridgeScript"
}
if (Test-Path -LiteralPath $OutputParsingScript -PathType Leaf) {
    . $OutputParsingScript
}

$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "PDA-Logs"
$LogPath = Join-Path $LogDir "PDAWebhookServer.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$NormalizedPrefix = "/" + $Prefix.Trim("/")
$HealthPath = "$NormalizedPrefix/healthz"

function Get-PDAStatusText {
    param(
        [Parameter(Mandatory = $true)]
        [int]$StatusCode
    )

    switch ($StatusCode) {
        200 { return "OK" }
        400 { return "Bad Request" }
        404 { return "Not Found" }
        405 { return "Method Not Allowed" }
        500 { return "Internal Server Error" }
        default { return "OK" }
    }
}

function Find-PDAByteSequence {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Haystack,

        [Parameter(Mandatory = $true)]
        [byte[]]$Needle
    )

    if ($Haystack.Length -lt $Needle.Length) {
        return -1
    }

    for ($Index = 0; $Index -le $Haystack.Length - $Needle.Length; $Index++) {
        $Match = $true
        for ($Offset = 0; $Offset -lt $Needle.Length; $Offset++) {
            if ($Haystack[$Index + $Offset] -ne $Needle[$Offset]) {
                $Match = $false
                break
            }
        }

        if ($Match) {
            return $Index
        }
    }

    return -1
}

function Read-PDARawRequest {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream
    )

    $Buffer = New-Object byte[] 4096
    $Bytes = New-Object System.Collections.Generic.List[byte]
    $HeaderMarker = [byte[]](13, 10, 13, 10)
    $HeaderEnd = -1

    while ($HeaderEnd -lt 0) {
        $ReadCount = $Stream.Read($Buffer, 0, $Buffer.Length)
        if ($ReadCount -le 0) {
            break
        }

        for ($Index = 0; $Index -lt $ReadCount; $Index++) {
            [void]$Bytes.Add($Buffer[$Index])
        }

        if ($Bytes.Count -gt 1048576) {
            throw "Request header is too large."
        }

        $HeaderEnd = Find-PDAByteSequence -Haystack ($Bytes.ToArray()) -Needle $HeaderMarker
    }

    if ($HeaderEnd -lt 0) {
        throw "No HTTP request data received."
    }

    $AllBytes = $Bytes.ToArray()
    $HeaderText = [System.Text.Encoding]::UTF8.GetString($AllBytes, 0, $HeaderEnd)
    $HeaderLines = $HeaderText -split "`r`n"
    if ($HeaderLines.Count -lt 1) {
        throw "Invalid HTTP request header."
    }

    $RequestLine = $HeaderLines[0]
    if ($RequestLine -notmatch '^(?<Method>\S+)\s+(?<Path>\S+)\s+HTTP/\d\.\d$') {
        throw "Invalid HTTP request line: $RequestLine"
    }

    $RequestMethod = $Matches.Method
    $RequestPath = $Matches.Path

    $Headers = @{}
    for ($Index = 1; $Index -lt $HeaderLines.Count; $Index++) {
        $Line = $HeaderLines[$Index]
        if ($Line -match '^(?<Key>[^:]+):\s*(?<Value>.*)$') {
            $Headers[$Matches.Key.ToLowerInvariant()] = $Matches.Value.Trim()
        }
    }

    $ContentLength = 0
    if ($Headers.ContainsKey("content-length")) {
        [void][int]::TryParse($Headers["content-length"], [ref]$ContentLength)
    }

    $TotalNeeded = $HeaderEnd + 4 + $ContentLength
    while ($Bytes.Count -lt $TotalNeeded) {
        $ReadCount = $Stream.Read($Buffer, 0, $Buffer.Length)
        if ($ReadCount -le 0) {
            break
        }

        for ($Index = 0; $Index -lt $ReadCount; $Index++) {
            [void]$Bytes.Add($Buffer[$Index])
        }
    }

    if ($Bytes.Count -lt $TotalNeeded) {
        throw "HTTP request body was truncated."
    }

    $BodyBytes = New-Object byte[] $ContentLength
    if ($ContentLength -gt 0) {
        [Array]::Copy($Bytes.ToArray(), $HeaderEnd + 4, $BodyBytes, 0, $ContentLength)
    }

    return [pscustomobject]@{
        Method = $RequestMethod
        Path = $RequestPath
        Headers = $Headers
        BodyText = if ($ContentLength -gt 0) { [System.Text.Encoding]::UTF8.GetString($BodyBytes) } else { "" }
    }
}

function Write-PDARawResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory = $true)]
        [object]$Payload,

        [Parameter(Mandatory = $false)]
        [int]$StatusCode = 200
    )

    $Json = $Payload | ConvertTo-Json -Depth 20
    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $StatusText = Get-PDAStatusText -StatusCode $StatusCode
    $HeaderText = @(
        "HTTP/1.1 $StatusCode $StatusText"
        "Content-Type: application/json; charset=utf-8"
        "Content-Length: $($BodyBytes.Length)"
        "Connection: close"
        ""
        ""
    ) -join "`r`n"
    $HeaderBytes = [System.Text.Encoding]::UTF8.GetBytes($HeaderText)
    $Stream.Write($HeaderBytes, 0, $HeaderBytes.Length)
    $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
    $Stream.Flush()
}

$Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$Listener.Start()

Write-Host "[OK] PDA webhook server listening on:"
Write-Host ("[OK]   http://localhost:{0}{1}/" -f $Port, $NormalizedPrefix)
Write-Host ("[OK]   http://localhost:{0}{1}" -f $Port, $HealthPath)
Write-Host ("[OK]   http://host.docker.internal:{0}{1}/" -f $Port, $NormalizedPrefix)
Write-Host ("[OK]   http://gateway.docker.internal:{0}{1}/" -f $Port, $NormalizedPrefix)
Write-Host ("[OK]   http://0.0.0.0:{0}{1}/" -f $Port, $NormalizedPrefix)
            Write-Host "[OK] Bridge script: $BridgeScript"
Write-Host "[OK] Stop with Ctrl+C"

try {
    while ($true) {
        $Client = $Listener.AcceptTcpClient()
        try {
            $Stream = $Client.GetStream()
            $Request = Read-PDARawRequest -Stream $Stream
            Add-Content -Path $LogPath -Value ("{0} remote={1} method={2} path={3}" -f (Get-Date -Format o), $Client.Client.RemoteEndPoint, $Request.Method, $Request.Path)

            if ($Request.Path -eq $HealthPath) {
                Write-PDARawResponse -Stream $Stream -StatusCode 200 -Payload ([pscustomobject]@{
                    status = "ok"
                    service = "pda-webhook-server"
                    port = $Port
                    bridge_path = $NormalizedPrefix
                    health_path = $HealthPath
                    timestamp = (Get-Date -Format o)
                })
                continue
            }

            if ($Request.Path -notlike "$NormalizedPrefix*") {
                Write-PDARawResponse -Stream $Stream -StatusCode 404 -Payload ([pscustomobject]@{
                    status = "fail"
                    error = "Not found"
                })
                continue
            }

            if ($Request.Method -ne "POST") {
                Write-PDARawResponse -Stream $Stream -StatusCode 405 -Payload ([pscustomobject]@{
                    status = "fail"
                    error = "Method not allowed"
                })
                continue
            }

            if ([string]::IsNullOrWhiteSpace($Request.BodyText)) {
                Write-PDARawResponse -Stream $Stream -StatusCode 400 -Payload ([pscustomobject]@{
                    status = "fail"
                    error = "Request body is empty or invalid JSON."
                })
                continue
            }

            try {
                $Body = $Request.BodyText | ConvertFrom-Json
            }
            catch {
                Write-PDARawResponse -Stream $Stream -StatusCode 400 -Payload ([pscustomobject]@{
                    status = "fail"
                    error = "Request body is empty or invalid JSON."
                })
                continue
            }

            $Message = [string]($Body.user_message ?? $Body.message ?? "")
            $ConfirmDispatch = $false
            if ($Body.PSObject.Properties.Name -contains "confirm_dispatch") {
                $ConfirmDispatch = [bool](
                    $Body.confirm_dispatch -eq $true -or
                    $Body.confirm_dispatch -eq "true" -or
                    $Body.confirm_dispatch -eq 1 -or
                    $Body.confirm_dispatch -eq "1"
                )
            }

            $ConversationId = ""
            if ($Body.PSObject.Properties.Name -contains "conversation_id") {
                $ConversationId = [string]$Body.conversation_id
            }
            elseif ($Body.PSObject.Properties.Name -contains "chat_id") {
                $ConversationId = [string]$Body.chat_id
            }

            $SessionId = ""
            if ($Body.PSObject.Properties.Name -contains "session_id") {
                $SessionId = [string]$Body.session_id
            }

            $UserId = ""
            if ($Body.PSObject.Properties.Name -contains "user_id") {
                $UserId = [string]$Body.user_id
            }

            $ConversationTitle = ""
            if ($Body.PSObject.Properties.Name -contains "conversation_title") {
                $ConversationTitle = [string]$Body.conversation_title
            }
            elseif ($Body.PSObject.Properties.Name -contains "title") {
                $ConversationTitle = [string]$Body.title
            }
            elseif ($Body.PSObject.Properties.Name -contains "chat") {
                try {
                    if ($Body.chat.PSObject.Properties.Name -contains "title") {
                        $ConversationTitle = [string]$Body.chat.title
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Body.chat.id) -and [string]::IsNullOrWhiteSpace($ConversationId)) {
                        $ConversationId = [string]$Body.chat.id
                    }
                }
                catch {}
            }

            if ([string]::IsNullOrWhiteSpace($Message)) {
                Write-PDARawResponse -Stream $Stream -StatusCode 400 -Payload ([pscustomobject]@{
                    status = "fail"
                    error = "user_message is required."
                })
                continue
            }

            try {
                Add-Content -Path $LogPath -Value ("{0} payload conversation_id={1} session_id={2} user_id={3} title={4} body={5}" -f (Get-Date -Format o), $(if ($ConversationId) { $ConversationId } else { "" }), $(if ($SessionId) { $SessionId } else { "" }), $(if ($UserId) { $UserId } else { "" }), $(if ($ConversationTitle) { $ConversationTitle } else { "" }), ($Request.BodyText -replace "`r?`n", " "))
            }
            catch {
                # Ignore debug log failures.
            }

            $BridgeParams = @{
                Message = $Message
                AsJson = $true
            }
            if ($ConfirmDispatch) {
                $BridgeParams.ConfirmDispatch = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
                $BridgeParams.ConversationId = $ConversationId
            }
            if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
                $BridgeParams.SessionId = $SessionId
            }
            if (-not [string]::IsNullOrWhiteSpace($UserId)) {
                $BridgeParams.UserId = $UserId
            }
            if (-not [string]::IsNullOrWhiteSpace($ConversationTitle)) {
                $BridgeParams.ConversationTitle = $ConversationTitle
            }

            $Raw = & $BridgeScript @BridgeParams 2>&1

            $JsonText = [string]($Raw -join "`n").Trim()
            if ([string]::IsNullOrWhiteSpace($JsonText)) {
                throw "Bridge returned no output."
            }

            try {
                if (Get-Command -Name ConvertFrom-PDAMixedJson -ErrorAction SilentlyContinue) {
                    $Payload = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName "PDA webhook bridge"
                }
                else {
                    $Payload = $JsonText | ConvertFrom-Json
                }
            }
            catch {
                Add-Content -Path $LogPath -Value ("{0} bridge-raw {1}" -f (Get-Date -Format o), ($JsonText -replace "`r?`n", " "))
                throw
            }
            Write-PDARawResponse -Stream $Stream -Payload $Payload -StatusCode 200
        }
        catch {
            try {
                Add-Content -Path $LogPath -Value ("{0} ERROR {1}" -f (Get-Date -Format o), $_.Exception.Message)
            }
            catch {
                # Ignore log write failures.
            }
            try {
                Write-PDARawResponse -Stream $Client.GetStream() -StatusCode 500 -Payload ([pscustomobject]@{
                    status = "fail"
                    error = $_.Exception.Message
                    source_of_truth = "Scripts/PDA_CommandInterpreter.ps1"
                })
            }
            catch {
                # Ignore secondary failures during error reporting.
            }
        }
        finally {
            $Client.Close()
        }
    }
}
finally {
    $Listener.Stop()
}



