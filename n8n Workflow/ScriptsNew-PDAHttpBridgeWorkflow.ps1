$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$WorkflowOut = Join-Path $Root "n8n Workflow\PDA-ChatBridge-HTTP.json"
$ServerOut = Join-Path $Root "Scripts\Start-PDAWebhookServer.ps1"
$Bridge = Join-Path $Root "Scripts\Invoke-PDAWebhookBridge.ps1"

$ServerScript = @"
`$Port = 8787
`$BridgeScript = "$Bridge"

`$Listener = [System.Net.HttpListener]::new()
`$Listener.Prefixes.Add("http://localhost:`$Port/")
`$Listener.Start()

Write-Host "[OK] PDA Webhook Server listening on http://localhost:`$Port/pda-chat-bridge"

while (`$Listener.IsListening) {
    `$Context = `$Listener.GetContext()
    `$Request = `$Context.Request
    `$Response = `$Context.Response

    try {
        `$Reader = [System.IO.StreamReader]::new(`$Request.InputStream)
        `$BodyRaw = `$Reader.ReadToEnd()
        `$Body = `$BodyRaw | ConvertFrom-Json

        `$Message = [string]`$Body.user_message
        `$Confirm = [bool]`$Body.confirm_dispatch

        `$Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", `$BridgeScript, "-Message", `$Message, "-AsJson")
        if (`$Confirm) { `$Args += "-ConfirmDispatch" }

        `$Output = & pwsh @Args | Out-String

        `$Bytes = [System.Text.Encoding]::UTF8.GetBytes(`$Output)
        `$Response.ContentType = "application/json"
        `$Response.StatusCode = 200
        `$Response.OutputStream.Write(`$Bytes, 0, `$Bytes.Length)
    }
    catch {
        `$ErrorObj = @{
            bridge_status = "error"
            response_text = "PDA webhook server failed."
            error = `$_.Exception.Message
            next_action = "Check Start-PDAWebhookServer.ps1"
        } | ConvertTo-Json -Depth 10

        `$Bytes = [System.Text.Encoding]::UTF8.GetBytes(`$ErrorObj)
        `$Response.ContentType = "application/json"
        `$Response.StatusCode = 500
        `$Response.OutputStream.Write(`$Bytes, 0, `$Bytes.Length)
    }
    finally {
        `$Response.Close()
    }
}
"@

Set-Content -Path $ServerOut -Value $ServerScript -Encoding UTF8

$Workflow = @{
    name = "PDA Chat Bridge HTTP"
    nodes = @(
        @{
            parameters = @{
                httpMethod = "POST"
                path = "pda-chat-bridge"
                responseMode = "responseNode"
                options = @{}
            }
            id = "webhook"
            name = "PDA Chat Webhook"
            type = "n8n-nodes-base.webhook"
            typeVersion = 2
            position = @(0,0)
        },
        @{
            parameters = @{
                jsCode = "const body = `$json.body || `$json; return [{ json: { user_message: String(body.user_message || body.message || '').trim(), confirm_dispatch: body.confirm_dispatch === true || body.confirm_dispatch === 'true' } }];"
            }
            id = "normalize"
            name = "Normalize Request"
            type = "n8n-nodes-base.code"
            typeVersion = 2
            position = @(260,0)
        },
        @{
            parameters = @{
                method = "POST"
                url = "http://host.docker.internal:8787/pda-chat-bridge"
                sendBody = $true
                contentType = "json"
                jsonBody = "={{ JSON.stringify($json) }}"
                options = @{}
            }
            id = "http"
            name = "Call PDA Webhook Server"
            type = "n8n-nodes-base.httpRequest"
            typeVersion = 4
            position = @(520,0)
        },
        @{
            parameters = @{
                respondWith = "json"
                responseBody = "={{ $json }}"
                options = @{}
            }
            id = "respond"
            name = "Respond to Webhook"
            type = "n8n-nodes-base.respondToWebhook"
            typeVersion = 1
            position = @(780,0)
        }
    )
    connections = @{
        "PDA Chat Webhook" = @{
            main = @(@(@{ node = "Normalize Request"; type = "main"; index = 0 }))
        }
        "Normalize Request" = @{
            main = @(@(@{ node = "Call PDA Webhook Server"; type = "main"; index = 0 }))
        }
        "Call PDA Webhook Server" = @{
            main = @(@(@{ node = "Respond to Webhook"; type = "main"; index = 0 }))
        }
    }
    settings = @{}
}

$Workflow | ConvertTo-Json -Depth 20 | Set-Content -Path $WorkflowOut -Encoding UTF8

Write-Host "[OK] Created server:"
Write-Host $ServerOut
Write-Host "[OK] Created workflow:"
Write-Host $WorkflowOut
