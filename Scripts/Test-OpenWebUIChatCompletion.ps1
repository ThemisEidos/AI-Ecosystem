[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Model = "gemini",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedToken = "openwebui-gemini-ok",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 120,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

function Get-RedactedLogLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [int]$Tail = 20
    )

    $Lines = @()
    try {
        $RawLines = @(& docker logs --tail $Tail $ContainerName 2>&1)
        foreach ($Line in $RawLines) {
            $Text = if ($Line -is [string]) { $Line } else { $Line.ToString() }
            if ([string]::IsNullOrWhiteSpace($Text)) {
                continue
            }

            $Text = $Text -replace '(?i)(authorization\s*[:=]\s*bearer\s+)[^\s"]+', '$1[REDACTED]'
            $Text = $Text -replace '(?i)\b(api[_-]?key|token|secret|password)\b(\s*[:=]\s*)[^\s"]+', '$1$2[REDACTED]'
            $Text = $Text -replace 'sk-[A-Za-z0-9_\-]+', 'sk-[REDACTED]'
            $Lines += $Text
        }
    }
    catch {
        $Lines += ("Could not read docker logs for {0}: {1}" -f $ContainerName, $_.Exception.Message)
    }

    return @($Lines)
}

function Test-ContainerRunning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    try {
        $Running = (& docker inspect -f "{{.State.Running}}" $ContainerName 2>$null)
        return (($LASTEXITCODE -eq 0) -and (($Running | Select-Object -First 1) -eq "true"))
    }
    catch {
        return $false
    }
}

$Issues = New-Object System.Collections.Generic.List[string]

if (-not (Test-ContainerRunning -ContainerName "pda-open-webui")) {
    $Issues.Add("Container pda-open-webui is not running.")
}
if (-not (Test-ContainerRunning -ContainerName "pda-litellm")) {
    $Issues.Add("Container pda-litellm is not running.")
}

$PythonScript = @'
import json
import os
import sqlite3
import sys
import time
import uuid

import jwt
import requests


def read_env_from_pid1():
    values = {}
    for item in open("/proc/1/environ", "rb").read().split(b"\0"):
        if not item or b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        values[key.decode()] = value.decode()
    return values


def main():
    model = __MODEL__
    expected_token = __EXPECTED_TOKEN__
    timeout_seconds = __TIMEOUT_SECONDS__

    env = read_env_from_pid1()
    secret = env.get("WEBUI_SECRET_KEY", "")
    if not secret:
        print(json.dumps({"status": "fail", "error": "WEBUI_SECRET_KEY missing from container environment."}))
        return

    conn = sqlite3.connect("/app/backend/data/webui.db")
    cur = conn.cursor()
    cur.execute(
        "SELECT id, role FROM user WHERE role IN ('admin', 'user') "
        "ORDER BY CASE role WHEN 'admin' THEN 0 ELSE 1 END, created_at ASC LIMIT 1"
    )
    row = cur.fetchone()
    if not row:
        print(json.dumps({"status": "fail", "error": "No Open WebUI user found for token generation."}))
        return

    user_id, user_role = row
    token = jwt.encode(
        {
            "id": user_id,
            "jti": str(uuid.uuid4()),
            "iat": int(time.time()),
        },
        secret,
        algorithm="HS256",
    )

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    models_response = requests.get("http://localhost:8080/api/models", headers=headers, timeout=30)
    models_payload = models_response.json() if models_response.content else {}
    models = models_payload.get("data", models_payload if isinstance(models_payload, list) else [])
    model_ids = [item.get("id") for item in models if isinstance(item, dict) and item.get("id")]

    assistant_id = str(uuid.uuid4())
    user_message_id = str(uuid.uuid4())

    payload = {
        "model": model,
        "stream": False,
        "chat_id": "local:pda-healthcheck",
        "id": assistant_id,
        "parent_id": None,
        "user_message": {
            "id": user_message_id,
            "parentId": None,
            "childrenIds": [assistant_id],
            "role": "user",
            "content": f"Respond with exactly: {expected_token}",
            "timestamp": int(time.time()),
        },
        "messages": [
            {"role": "user", "content": f"Respond with exactly: {expected_token}"}
        ],
        "features": {},
        "variables": {},
        "params": {},
    }

    completion_response = requests.post(
        "http://localhost:8080/api/chat/completions",
        headers=headers,
        json=payload,
        timeout=timeout_seconds,
    )

    completion_body = None
    completion_text = None
    try:
        completion_body = completion_response.json()
    except Exception:
        completion_text = completion_response.text

    message_content = None
    finish_reason = None
    returned_model = None
    if isinstance(completion_body, dict):
        returned_model = completion_body.get("model")
        choices = completion_body.get("choices") or []
        if choices and isinstance(choices[0], dict):
            finish_reason = choices[0].get("finish_reason")
            message = choices[0].get("message") or {}
            if isinstance(message, dict):
                message_content = message.get("content")

    passed = (
        models_response.status_code == 200
        and model in model_ids
        and completion_response.status_code == 200
        and isinstance(message_content, str)
        and expected_token in message_content
    )

    result = {
        "status": "pass" if passed else "fail",
        "auth": {
            "user_role": user_role,
        },
        "models_check": {
            "status_code": models_response.status_code,
            "has_target_model": model in model_ids,
            "model_count": len(model_ids),
        },
        "request_shape": {
            "chat_id": "local:pda-healthcheck",
            "includes_id": True,
            "includes_parent_id": True,
            "includes_user_message": True,
        },
        "completion_check": {
            "status_code": completion_response.status_code,
            "returned_model": returned_model,
            "finish_reason": finish_reason,
            "content": message_content,
            "error_detail": (
                completion_body.get("detail") if isinstance(completion_body, dict) else None
            ),
            "response_text": completion_text[:500] if completion_text else None,
        },
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
'@

if ($Issues.Count -eq 0) {
    $RenderedPython = $PythonScript.
        Replace("__MODEL__", ($Model | ConvertTo-Json -Compress)).
        Replace("__EXPECTED_TOKEN__", ($ExpectedToken | ConvertTo-Json -Compress)).
        Replace("__TIMEOUT_SECONDS__", [string]$TimeoutSeconds)

    try {
        $RawResult = $RenderedPython | docker exec -i pda-open-webui python - 2>$null
        $JsonText = [string]($RawResult -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($JsonText)) {
            $Issues.Add("Open WebUI health probe returned no JSON payload.")
        }
        else {
            $Probe = $JsonText | ConvertFrom-Json
        }
    }
    catch {
        $Issues.Add("Open WebUI health probe execution failed: $($_.Exception.Message)")
    }
}

if ($Issues.Count -gt 0) {
    $Probe = [pscustomobject]@{
        status = "fail"
        auth = [pscustomobject]@{}
        models_check = [pscustomobject]@{
            status_code = $null
            has_target_model = $false
            model_count = 0
        }
        request_shape = [pscustomobject]@{
            chat_id = "local:pda-healthcheck"
            includes_id = $true
            includes_parent_id = $true
            includes_user_message = $true
        }
        completion_check = [pscustomobject]@{
            status_code = $null
            returned_model = $null
            finish_reason = $null
            content = $null
            error_detail = $null
            response_text = $null
        }
    }
}

$ReportIssues = New-Object System.Collections.Generic.List[string]
foreach ($Issue in $Issues) {
    $ReportIssues.Add($Issue)
}

if ($Probe.status -ne "pass") {
    if (-not $Probe.models_check.has_target_model) {
        $ReportIssues.Add(("Open WebUI /api/models did not expose target model '{0}'." -f $Model))
    }
    if ($Probe.completion_check.status_code -ne 200) {
        $ReportIssues.Add(("Open WebUI /api/chat/completions returned HTTP {0}." -f $Probe.completion_check.status_code))
    }
    if ([string]::IsNullOrWhiteSpace([string]$Probe.completion_check.content)) {
        $ReportIssues.Add("Assistant response content was empty.")
    }
    elseif ([string]$Probe.completion_check.content -notmatch [regex]::Escape($ExpectedToken)) {
        $ReportIssues.Add(("Assistant response did not contain expected token '{0}'." -f $ExpectedToken))
    }
}

$Report = [pscustomobject]@{
    status = if ($ReportIssues.Count -eq 0 -and $Probe.status -eq "pass") { "pass" } else { "fail" }
    target_model = $Model
    expected_token = $ExpectedToken
    root_cause = "Open WebUI's chat endpoint requires frontend-style metadata. Bare OpenAI-style payloads can leave chat metadata null, and middleware later dereferences chat_id with .startswith(...)."
    probe = $Probe
    diagnostics = [pscustomobject]@{
        open_webui_logs = if ($ReportIssues.Count -gt 0) { @(Get-RedactedLogLines -ContainerName "pda-open-webui" -Tail 20) } else { @() }
        litellm_logs = if ($ReportIssues.Count -gt 0) { @(Get-RedactedLogLines -ContainerName "pda-litellm" -Tail 20) } else { @() }
    }
    issues = @($ReportIssues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "Open WebUI chat completion validation failed."
    }
    return
}

Write-Host "[*] Open WebUI chat completion validation"
Write-Host ("Target model     : {0}" -f $Report.target_model)
Write-Host ("Model visible    : {0}" -f $Report.probe.models_check.has_target_model)
Write-Host ("Models HTTP      : {0}" -f $Report.probe.models_check.status_code)
Write-Host ("Completion HTTP  : {0}" -f $Report.probe.completion_check.status_code)
Write-Host ("Returned model   : {0}" -f $Report.probe.completion_check.returned_model)
Write-Host ("Finish reason    : {0}" -f $Report.probe.completion_check.finish_reason)
Write-Host ("Status           : {0}" -f $Report.status)

if ($Report.status -ne "pass") {
    foreach ($Issue in $Report.issues) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
}

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "Open WebUI chat completion validation failed."
}
