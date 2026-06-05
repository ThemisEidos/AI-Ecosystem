[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$WorkflowDir = Join-Path $Root "n8n Workflow"
$ClipboardPath = Join-Path $WorkflowDir "PDA-ChatBridge-HTTP-Clipboard.json"

New-Item -ItemType Directory -Force -Path $WorkflowDir | Out-Null

$ClipboardContent = [pscustomobject]@{
    nodes = @(
        [pscustomobject]@{
            id = "pda-http-webhook-node"
            name = "PDA HTTP Webhook"
            type = "n8n-nodes-base.webhook"
            typeVersion = 2
            position = @(0, 0)
            parameters = [pscustomobject]@{
                httpMethod = "POST"
                path = "pda-chat-bridge-http"
                responseMode = "responseNode"
                options = [pscustomobject]@{}
            }
        }
        [pscustomobject]@{
            id = "pda-http-normalize-node"
            name = "Normalize Request"
            type = "n8n-nodes-base.code"
            typeVersion = 2
            position = @(260, 0)
            parameters = [pscustomobject]@{
                jsCode = @'
const body = $json.body || $json;
const userMessage = String(body.user_message || body.message || '').trim();
const confirmDispatch = body.confirm_dispatch === true || body.confirm_dispatch === 'true' || body.confirm_dispatch === 1 || body.confirm_dispatch === '1';
const conversationId = String(body.conversation_id || body.chat_id || (body.chat && body.chat.id) || '').trim();
const sessionId = String(body.session_id || '').trim();
const userId = String(body.user_id || (body.user && body.user.id) || '').trim();
const conversationTitle = String(body.conversation_title || body.title || (body.chat && body.chat.title) || '').trim();
const url = 'http://host.docker.internal:8788/pda-chat-bridge';
return [{ json: { user_message: userMessage, confirm_dispatch: confirmDispatch, conversation_id: conversationId, session_id: sessionId, user_id: userId, conversation_title: conversationTitle, url, received_at: new Date().toISOString() } }];
'@
            }
        }
        [pscustomobject]@{
            id = "pda-http-request-node"
            name = "Invoke Local HTTP Bridge"
            type = "n8n-nodes-base.httpRequest"
            typeVersion = 4.2
            onError = "continueRegularOutput"
            position = @(520, 0)
            parameters = [pscustomobject]@{
                method = "POST"
                url = '={{ $json.url }}'
                sendBody = $true
                specifyBody = "json"
                responseFormat = "json"
                jsonBody = '={{ { user_message: $json.user_message, confirm_dispatch: $json.confirm_dispatch, conversation_id: $json.conversation_id, session_id: $json.session_id, user_id: $json.user_id, conversation_title: $json.conversation_title } }}'
                options = [pscustomobject]@{
                    timeout = 10000
                }
            }
        }
        [pscustomobject]@{
            id = "pda-http-parse-node"
            name = "Parse Bridge Response"
            type = "n8n-nodes-base.code"
            typeVersion = 2
            position = @(780, 0)
            parameters = [pscustomobject]@{
                jsCode = @'
const failClosed = (responseText, nextAction, errorDetail = '') => ({
  status: 'fail',
  response_text: responseText,
  recommended_command: '',
  intent: '',
  confidence: 0,
  requires_confirmation: false,
  dispatch_ready: false,
  dispatch_status: 'blocked',
  next_action: nextAction,
  source_of_truth: 'Scripts/PDA_CommandInterpreter.ps1',
  bridge_status: 'fail_closed',
  handoff_status: 'fail_closed',
  error_detail: errorDetail
});

const httpError = $json.error || $json.errors || null;
if (httpError) {
  const message = httpError.message || $json.message || 'Local PDA webhook server request failed.';
  return [{ json: failClosed(
    'Local PDA webhook server is unavailable.',
    'Start Scripts/Start-PDAWebhookServer.ps1 and retry the request.',
    String(message)
  ) }];
}

const payload = $json.body ?? $json.data ?? $json.json ?? $json;
let parsed = payload;
if (typeof payload === 'string') {
  try {
    parsed = JSON.parse(payload);
  } catch (error) {
    parsed = failClosed(
      'HTTP bridge returned invalid JSON.',
      'Inspect the local webhook server and PowerShell bridge logs.',
      error.message
    );
  }
}

if (!parsed || typeof parsed !== 'object') {
  parsed = failClosed(
    'HTTP bridge returned an invalid payload.',
    'Inspect the local webhook server and PowerShell bridge logs.'
  );
}

return [{ json: parsed }];
'@
            }
        }
        [pscustomobject]@{
            id = "pda-http-response-node"
            name = "Return HTTP Bridge Result"
            type = "n8n-nodes-base.respondToWebhook"
            typeVersion = 1
            position = @(1040, 0)
            parameters = [pscustomobject]@{
                respondWith = "json"
                responseBody = '={{ $json }}'
            }
        }
    )
    connections = [pscustomobject]@{
        "PDA HTTP Webhook" = [pscustomobject]@{
            main = @(
                @(
                    [pscustomobject]@{
                        node = "Normalize Request"
                        type = "main"
                        index = 0
                    }
                )
            )
        }
        "Normalize Request" = [pscustomobject]@{
            main = @(
                @(
                    [pscustomobject]@{
                        node = "Invoke Local HTTP Bridge"
                        type = "main"
                        index = 0
                    }
                )
            )
        }
        "Invoke Local HTTP Bridge" = [pscustomobject]@{
            main = @(
                @(
                    [pscustomobject]@{
                        node = "Parse Bridge Response"
                        type = "main"
                        index = 0
                    }
                )
            )
        }
        "Parse Bridge Response" = [pscustomobject]@{
            main = @(
                @(
                    [pscustomobject]@{
                        node = "Return HTTP Bridge Result"
                        type = "main"
                        index = 0
                    }
                )
            )
        }
    }
}

$ClipboardContent | ConvertTo-Json -Depth 20 | Set-Content -Path $ClipboardPath -Encoding UTF8

Write-Host "[OK] Generated n8n clipboard workflow:"
Write-Host $ClipboardPath
Write-Host "[OK] Paste instructions:"
Write-Host "1. Open n8n canvas."
Write-Host "2. Paste the contents of n8n Workflow/PDA-ChatBridge-HTTP-Clipboard.json onto the canvas."
Write-Host "3. Confirm the four nodes appear: Webhook, Normalize Request, Invoke Local HTTP Bridge, Return HTTP Bridge Result."
Write-Host "4. Save the workflow as needed."
