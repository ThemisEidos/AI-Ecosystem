[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "pda-open-webui",

    [Parameter(Mandatory = $false)]
    [string]$FunctionId = "pda_chat_bridge",

    [Parameter(Mandatory = $false)]
    [string]$SourcePath = (Join-Path $PSScriptRoot "..\Open WebUI\PDA_ChatBridge_Pipe.py"),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Issues = New-Object System.Collections.Generic.List[string]
$Result = [ordered]@{
    status = "fail"
    container_name = $ContainerName
    function_id = $FunctionId
    source_path = $SourcePath
    desired_name = $null
    changed_fields = @()
    updated = $false
    database_path = "/app/backend/data/webui.db"
    message = ""
}

function Add-PDAIssue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [void]$Issues.Add($Message)
}

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    Add-PDAIssue "Open WebUI pipe source file not found: $SourcePath"
}

$DesiredName = $null
if ($Issues.Count -eq 0) {
    try {
        $SourceText = Get-Content -LiteralPath $SourcePath -Raw -ErrorAction Stop
        if ($SourceText -match '(?m)^\s*title:\s*(.+?)\s*$') {
            $DesiredName = $Matches[1].Trim()
        }
        else {
            Add-PDAIssue "Could not determine pipe title from source file: $SourcePath"
        }
    }
    catch {
        Add-PDAIssue "Failed to read Open WebUI pipe source file: $($_.Exception.Message)"
    }
}

if ($Issues.Count -eq 0) {
    try {
        $Running = docker inspect -f '{{.State.Running}}' $ContainerName 2>$null
        if ([string]$Running -ne "true") {
            Add-PDAIssue "Open WebUI container is not running: $ContainerName"
        }
    }
    catch {
        Add-PDAIssue "Failed to inspect Open WebUI container '$ContainerName': $($_.Exception.Message)"
    }
}

if ($Issues.Count -eq 0) {
    $Python = @"
import json
import re
import sqlite3
import sys
import time

FUNCTION_ID = $(($FunctionId | ConvertTo-Json -Compress))
DESIRED_NAME = $(($DesiredName | ConvertTo-Json -Compress))
DB_PATH = "/app/backend/data/webui.db"

def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))

try:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    row = conn.execute(
        "SELECT id, name, type, content, meta, valves, is_active, is_global FROM function WHERE id = ?",
        (FUNCTION_ID,),
    ).fetchone()

    if row is None:
        emit({
            "status": "fail",
            "message": f"Function '{FUNCTION_ID}' was not found in {DB_PATH}.",
        })
        sys.exit(0)

    updated_name = DESIRED_NAME
    updated_content = row["content"] or ""
    updated_meta = row["meta"]

    if re.search(r"(?m)^title:\s*.*$", updated_content):
        updated_content = re.sub(
            r"(?m)^title:\s*.*$",
            f"title: {DESIRED_NAME}",
            updated_content,
            count=1,
        )

    if updated_meta and updated_meta not in ("null", "None", ""):
        try:
            meta_obj = json.loads(updated_meta)
            if isinstance(meta_obj, dict):
                manifest = meta_obj.get("manifest")
                if isinstance(manifest, dict):
                    manifest["title"] = DESIRED_NAME
                else:
                    meta_obj["manifest"] = {"title": DESIRED_NAME}
                updated_meta = json.dumps(meta_obj, ensure_ascii=False)
        except Exception:
            pass

    assignments = []
    values = []

    if row["name"] != updated_name:
        assignments.append("name = ?")
        values.append(updated_name)

    if updated_content != row["content"]:
        assignments.append("content = ?")
        values.append(updated_content)

    if updated_meta != row["meta"]:
        assignments.append("meta = ?")
        values.append(updated_meta)

    if row["is_active"] != 1:
        assignments.append("is_active = ?")
        values.append(1)

    if assignments:
        assignments.append("updated_at = ?")
        values.append(int(time.time()))
        values.append(FUNCTION_ID)
        conn.execute(f"UPDATE function SET {', '.join(assignments)} WHERE id = ?", values)
        conn.commit()
        emit({
            "status": "pass",
            "message": f"Open WebUI function '{FUNCTION_ID}' synchronized to '{DESIRED_NAME}'.",
            "updated": True,
            "changed_fields": [
                field
                for field, changed in (
                    ("name", row["name"] != updated_name),
                    ("content", updated_content != row["content"]),
                    ("meta", updated_meta != row["meta"]),
                    ("is_active", row["is_active"] != 1),
                )
                if changed
            ],
            "desired_name": DESIRED_NAME,
            "container_name": $(($ContainerName | ConvertTo-Json -Compress)),
            "function_id": FUNCTION_ID,
            "database_path": DB_PATH,
        })
    else:
        emit({
            "status": "pass",
            "message": f"Open WebUI function '{FUNCTION_ID}' is already synchronized to '{DESIRED_NAME}'.",
            "updated": False,
            "changed_fields": [],
            "desired_name": DESIRED_NAME,
            "container_name": $(($ContainerName | ConvertTo-Json -Compress)),
            "function_id": FUNCTION_ID,
            "database_path": DB_PATH,
        })
except Exception as exc:
    emit({
        "status": "fail",
        "message": str(exc),
    })
    sys.exit(0)
"@

    try {
        $Raw = $Python | docker exec -i $ContainerName python - 2>&1
        $Text = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($Text)) {
            Add-PDAIssue "Open WebUI repair script returned no output."
        }
        else {
            try {
                $Json = $Text | ConvertFrom-Json -ErrorAction Stop
                $Result.status = [string]$Json.status
                $Result.message = [string]$Json.message
                $Result.updated = [bool]$Json.updated
                $Result.desired_name = [string]$Json.desired_name
                $Result.changed_fields = @($Json.changed_fields)

                if ($Result.status -ne "pass") {
                    Add-PDAIssue $Result.message
                }
            }
            catch {
                Add-PDAIssue "Failed to parse Open WebUI repair response: $($_.Exception.Message)"
                Add-PDAIssue $Text
            }
        }
    }
    catch {
        Add-PDAIssue "Open WebUI repair command failed: $($_.Exception.Message)"
    }
}

if ($Issues.Count -gt 0) {
    $Result.status = "fail"
    if ([string]::IsNullOrWhiteSpace([string]$Result.message)) {
        $Result.message = $Issues -join "; "
    }
}

if ($AsJson) {
    $Result.issues = @($Issues)
    $Result | ConvertTo-Json -Depth 10
    if (-not $NoThrow -and $Result.status -ne "pass") {
        throw "Open WebUI function repair failed."
    }
    return
}

Write-Host "[*] Open WebUI function repair"
Write-Host ("Status     : {0}" -f $Result.status)
Write-Host ("Message    : {0}" -f $Result.message)
Write-Host ("Desired    : {0}" -f $Result.desired_name)
Write-Host ("Updated    : {0}" -f $Result.updated)
Write-Host ("Fields     : {0}" -f (@($Result.changed_fields) -join ", "))
Write-Host ("Issues     : {0}" -f $Issues.Count)

if (-not $NoThrow -and $Result.status -ne "pass") {
    throw "Open WebUI function repair failed."
}
