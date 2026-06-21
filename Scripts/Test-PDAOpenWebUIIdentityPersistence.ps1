[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$PipePath = Join-Path $Root "Open WebUI\PDA_ChatBridge_Pipe.py"

$Issues = New-Object System.Collections.Generic.List[string]
$Result = [ordered]@{
    status = "fail"
    pipe_identity = $null
    api_models = @()
    api_functions = @()
    visible_model_id = ""
    visible_model_name = ""
    private_model_id = ""
    private_model_name = ""
    cooper_model_count = 0
    private_model_count = 0
    legacy_model_present = $false
    function_name = ""
    function_title = ""
    function_id = ""
    issues = @()
}

function Add-PDAIssue {
    param([Parameter(Mandatory = $true)][string]$Message)
    [void]$Issues.Add($Message)
}

if (-not (Test-Path -LiteralPath $PipePath -PathType Leaf)) {
    Add-PDAIssue "Open WebUI pipe source file not found: $PipePath"
}

if ($Issues.Count -eq 0) {
    $PipeCheck = @"
import importlib.util
import json
import pathlib

path = pathlib.Path($(($PipePath | ConvertTo-Json -Compress)))
spec = importlib.util.spec_from_file_location("pda_chat_bridge_pipe", path)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)
pipe = module.Pipe()
entries = pipe.pipes()
print(json.dumps({
    "status": "pass" if entries and entries[0].get("id") == "cooper" and entries[0].get("name") == "COOPER" else "fail",
    "entries": entries,
}, ensure_ascii=False))
"@

    try {
        $PipeRaw = @($PipeCheck | python - 2>&1)
        $PipeText = [string]($PipeRaw -join "`n").Trim()
        if ($PipeText -notmatch '"id"\s*:\s*"cooper"' -or $PipeText -notmatch '"name"\s*:\s*"COOPER"' -or $PipeText -notmatch '"status"\s*:\s*"pass"') {
            Add-PDAIssue "Local pipe identity does not expose cooper/COOPER."
        }
        else {
            $Result.pipe_identity = @(
                [pscustomobject]@{
                    id = "cooper"
                    name = "COOPER"
                }
            )
        }
    }
    catch {
        Add-PDAIssue "Failed to validate local pipe identity: $($_.Exception.Message)"
    }
}

if ($Issues.Count -eq 0) {
    $ApiCheck = @"
import json
import os
import sqlite3
import time
import uuid
import warnings

import jwt
import requests

warnings.filterwarnings("ignore", category=Warning)


def read_secret():
    env = {}
    try:
        with open("/proc/1/environ", "rb") as handle:
            for item in handle.read().split(b"\0"):
                if not item or b"=" not in item:
                    continue
                key, value = item.split(b"=", 1)
                env[key.decode()] = value.decode()
    except Exception:
        pass

    secret = env.get("WEBUI_SECRET_KEY", "")
    if secret:
        return secret

    for path in (
        "/app/backend/data/.webui_secret_key",
        "/app/backend/.webui_secret_key",
        ".webui_secret_key",
    ):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                text = handle.read().strip()
            if text:
                return text
        except Exception:
            continue

    return ""


def main():
    secret = read_secret()
    if not secret:
        print(json.dumps({"status": "fail", "error": "WEBUI secret not available."}, ensure_ascii=False))
        return

    conn = sqlite3.connect("/app/backend/data/webui.db")
    cur = conn.cursor()
    cur.execute(
        "SELECT id FROM user ORDER BY CASE role WHEN 'admin' THEN 0 ELSE 1 END, created_at ASC LIMIT 1"
    )
    row = cur.fetchone()
    if not row:
        print(json.dumps({"status": "fail", "error": "No Open WebUI user found."}, ensure_ascii=False))
        return

    token = jwt.encode(
        {
            "id": row[0],
            "jti": str(uuid.uuid4()),
            "iat": int(time.time()),
        },
        secret,
        algorithm="HS256",
    )

    headers = {"Authorization": f"Bearer {token}"}
    models_response = requests.get("http://localhost:8080/api/models", headers=headers, timeout=30)
    functions_response = requests.get("http://localhost:8080/api/v1/functions/", headers=headers, timeout=30)

    models_payload = models_response.json()
    model_entries = models_payload.get("data", models_payload if isinstance(models_payload, list) else [])
    function_entries = functions_response.json()

    legacy_present = any(
        isinstance(item, dict) and (
            item.get("id") == "pda_chat_bridge.pda_commander"
            or item.get("name") == "PDA Commander"
        )
        for item in model_entries
    )
    visible_models = [
        item
        for item in model_entries
        if isinstance(item, dict) and item.get("name") in ("COOPER", "COOPER - Private")
    ]
    cooper_models = [
        item for item in visible_models
        if item.get("name") == "COOPER"
    ]
    private_models = [
        item for item in visible_models
        if item.get("name") == "COOPER - Private"
    ]
    cooper_model = cooper_models[0] if cooper_models else None
    private_model = private_models[0] if private_models else None
    cooper_personality_present = any(
        isinstance(item, dict) and (
            item.get("id") == "cooper-personality"
            or item.get("name") == "cooper-personality"
        )
        for item in model_entries
    )
    function_record = next(
        (
            item
            for item in function_entries
            if isinstance(item, dict) and item.get("id") == "pda_chat_bridge"
        ),
        None,
    )

    passed = (
        models_response.status_code == 200
        and functions_response.status_code == 200
        and cooper_model is not None
        and private_model is not None
        and cooper_model.get("name") == "COOPER"
        and private_model.get("name") == "COOPER - Private"
        and len(cooper_models) == 1
        and len(private_models) == 1
        and cooper_model.get("id") == "pda_chat_bridge.cooper"
        and private_model.get("id") == "COOPER - Private"
        and not legacy_present
        and not cooper_personality_present
        and function_record is not None
        and function_record.get("name") == "COOPER"
        and isinstance(function_record.get("meta"), dict)
        and function_record["meta"].get("manifest", {}).get("title") == "COOPER"
    )

    print(json.dumps({
        "status": "pass" if passed else "fail",
        "target_models": visible_models,
        "target_function": function_record,
        "visible_model_id": cooper_model.get("id") if cooper_model else "",
        "visible_model_name": cooper_model.get("name") if cooper_model else "",
        "private_model_id": private_model.get("id") if private_model else "",
        "private_model_name": private_model.get("name") if private_model else "",
        "cooper_model_count": len(cooper_models),
        "private_model_count": len(private_models),
        "legacy_model_present": legacy_present,
        "cooper_personality_present": cooper_personality_present,
        "function_name": function_record.get("name") if function_record else "",
        "function_title": function_record.get("meta", {}).get("manifest", {}).get("title") if function_record else "",
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
"@

    try {
        $ApiRaw = @($ApiCheck | docker exec -i pda-open-webui python - 2>&1)
        $ApiText = [string]($ApiRaw -join "`n").Trim()
        $JsonStart = $ApiText.IndexOf("{")
        $JsonEnd = $ApiText.LastIndexOf("}")
        if ($JsonStart -ge 0 -and $JsonEnd -gt $JsonStart) {
            $ApiText = $ApiText.Substring($JsonStart, $JsonEnd - $JsonStart + 1)
        }
        $ApiJson = $ApiText | ConvertFrom-Json -ErrorAction Stop
        $Result.api_models = @($ApiJson.target_model)
        $Result.api_functions = @($ApiJson.target_function)
        $Result.visible_model_id = [string]$ApiJson.visible_model_id
        $Result.visible_model_name = [string]$ApiJson.visible_model_name
        $Result.private_model_id = [string]$ApiJson.private_model_id
        $Result.private_model_name = [string]$ApiJson.private_model_name
        $Result.cooper_model_count = [int]$ApiJson.cooper_model_count
        $Result.private_model_count = [int]$ApiJson.private_model_count
        $Result.legacy_model_present = [bool]$ApiJson.legacy_model_present
        $Result.cooper_personality_present = [bool]$ApiJson.cooper_personality_present
        $Result.function_name = [string]$ApiJson.function_name
        $Result.function_title = [string]$ApiJson.function_title

        if ([string]$ApiJson.status -ne "pass") {
            Add-PDAIssue "Open WebUI API did not expose the expected COOPER model identity."
        }
        if ($Result.cooper_model_count -ne 1) {
            Add-PDAIssue "Selectable Open WebUI COOPER model should appear exactly once."
        }
        if ($Result.private_model_count -ne 1) {
            Add-PDAIssue "Selectable Open WebUI private model should appear exactly once."
        }
        if ($Result.visible_model_id -ne "pda_chat_bridge.cooper") {
            Add-PDAIssue "Selectable Open WebUI COOPER model id should be pda_chat_bridge.cooper."
        }
        if ($Result.private_model_id -ne "COOPER - Private") {
            Add-PDAIssue "Selectable Open WebUI private model id should be COOPER - Private."
        }
        if ($Result.visible_model_name -ne "COOPER") {
            Add-PDAIssue "Selectable Open WebUI COOPER model name should be COOPER."
        }
        if ($Result.private_model_name -ne "COOPER - Private") {
            Add-PDAIssue "Selectable Open WebUI private model name should be COOPER - Private."
        }
        if ($Result.legacy_model_present) {
            Add-PDAIssue "Legacy pda_commander model id is still exposed in /api/models."
        }
        if ($Result.cooper_personality_present) {
            Add-PDAIssue "Legacy cooper-personality model name is still exposed in /api/models."
        }
        if ($Result.function_name -ne "COOPER" -or $Result.function_title -ne "COOPER") {
            Add-PDAIssue "Function metadata did not persist the COOPER identity."
        }
    }
    catch {
        Add-PDAIssue "Failed to validate Open WebUI model identity persistence: $($_.Exception.Message)"
    }
}

$Result.status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
$Result.issues = @($Issues)

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Result.status -ne "pass") {
        throw "Open WebUI identity persistence validation failed."
    }
    return
}

Write-Host "[*] Open WebUI identity persistence"
Write-Host ("Status     : {0}" -f $Result.status)
Write-Host ("Model ID   : {0}" -f $Result.visible_model_id)
Write-Host ("Model name : {0}" -f $Result.visible_model_name)
Write-Host ("Legacy id? : {0}" -f $Result.legacy_model_present)
Write-Host ("Function   : {0}" -f $Result.function_name)
Write-Host ("Title      : {0}" -f $Result.function_title)
Write-Host ("Issues     : {0}" -f $Issues.Count)

if (-not $NoThrow -and $Result.status -ne "pass") {
    throw "Open WebUI identity persistence validation failed."
}
