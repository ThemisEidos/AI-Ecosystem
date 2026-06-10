[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "pda-open-webui",

    [Parameter(Mandatory = $false)]
    [string]$FunctionId = "pda_chat_bridge",

    [Parameter(Mandatory = $false)]
    [string]$SourcePath = (Join-Path $PSScriptRoot "..\Open WebUI\PDA_ChatBridge_Pipe.py"),

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Issues = New-Object System.Collections.Generic.List[string]
$Result = [ordered]@{
    status = "fail"
    dry_run = [bool]$DryRun
    container_name = $ContainerName
    function_id = $FunctionId
    source_path = $SourcePath
    database_path = "/app/backend/data/webui.db"
    desired_name = $null
    desired_pipe_id = $null
    visible_candidate_label = $null
    visible_candidate_model_id = $null
    changed_fields = @()
    remaining_legacy_references = @()
    updated = $false
    message = ""
}

function Add-PDAIssue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [void]$Issues.Add($Message)
}

function Get-PDARegexMatchValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if ($Text -match $Pattern) {
        return $Matches[1]
    }

    return $null
}

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    Add-PDAIssue "Open WebUI pipe source file not found: $SourcePath"
}

$DesiredName = $null
$DesiredPipeId = "cooper"
if ($Issues.Count -eq 0) {
    try {
        $SourceText = Get-Content -LiteralPath $SourcePath -Raw -ErrorAction Stop
        $DesiredName = Get-PDARegexMatchValue -Text $SourceText -Pattern '(?m)^\s*title:\s*(.+?)\s*$'
        if ([string]::IsNullOrWhiteSpace($DesiredName)) {
            Add-PDAIssue "Could not determine pipe title from source file: $SourcePath"
        }

        $ParsedPipeId = Get-PDARegexMatchValue -Text $SourceText -Pattern '(?s)pipes\(\):\s*.*?return\s+\[\s*\{\s*"id":\s*"([^"]+)"\s*,\s*"name":\s*"([^"]+)"\s*\}\s*\]'
        $ParsedPipeName = $null
        if ($SourceText -match '(?s)pipes\(\):\s*.*?return\s+\[\s*\{\s*"id":\s*"([^"]+)"\s*,\s*"name":\s*"([^"]+)"\s*\}\s*\]') {
            $ParsedPipeId = $Matches[1]
            $ParsedPipeName = $Matches[2]
        }

        if (-not [string]::IsNullOrWhiteSpace($ParsedPipeId)) {
            $DesiredPipeId = $ParsedPipeId
        }
        if ([string]::IsNullOrWhiteSpace($ParsedPipeName)) {
            $ParsedPipeName = $DesiredName
        }

        $Result.desired_name = $DesiredName
        $Result.desired_pipe_id = $DesiredPipeId
        $Result.visible_candidate_label = $DesiredName
        $Result.visible_candidate_model_id = "$FunctionId.$DesiredPipeId"
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
import os
import re
import sqlite3
import sys
import time

FUNCTION_ID = $(($FunctionId | ConvertTo-Json -Compress))
DESIRED_NAME = $(($DesiredName | ConvertTo-Json -Compress))
DESIRED_PIPE_ID = $(($DesiredPipeId | ConvertTo-Json -Compress))
DB_PATH = "/app/backend/data/webui.db"
DRY_RUN = $(if ($DryRun) { "True" } else { "False" })

def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))

def safe_json_loads(text):
    if text in (None, "", "null", "None"):
        return None
    try:
        return json.loads(text)
    except Exception:
        return None

def replace_pipe_identity(text):
    if not isinstance(text, str):
        return text
    updated = text.replace("PDA Commander", DESIRED_NAME)
    updated = updated.replace("pda_commander", DESIRED_PIPE_ID)
    updated = re.sub(r'(?m)^title:\s*.*$', f"title: {DESIRED_NAME}", updated, count=1)
    return updated

def scan_sqlite(conn, needle):
    results = []
    tables = [row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
    for table in tables:
        if table.startswith("sqlite_"):
            continue
        cols = [row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')]
        for col in cols:
            try:
                rows = list(conn.execute(f'SELECT rowid, "{col}" FROM "{table}" WHERE CAST("{col}" AS TEXT) LIKE ? LIMIT 5', (f'%{needle}%',)))
            except Exception:
                continue
            if rows:
                results.append({
                    "kind": "sqlite",
                    "table": table,
                    "column": col,
                    "count": len(rows),
                    "safe": table in {"chat", "chat_message", "pinned_note", "note", "message", "feedback"},
                    "samples": [str(r[col])[:200].replace("\n", "\\n") for r in rows[:3]],
                })
    return results

def scan_files(root, needles):
    results = []
    for dirpath, dirnames, filenames in os.walk(root):
        for fn in filenames:
            path = os.path.join(dirpath, fn)
            if path.endswith((".db", ".sqlite", ".sqlite3", ".db-wal", ".db-shm")):
                continue
            try:
                if os.path.getsize(path) > 5_000_000:
                    continue
                with open(path, "rb") as handle:
                    data = handle.read()
                if any(needle in data for needle in needles):
                    results.append({
                        "kind": "file",
                        "path": path,
                        "safe": path.endswith("pda-chat-bridge-debug.jsonl") or path.endswith("pda-chat-bridge-pending.json"),
                    })
            except Exception:
                continue
    return results

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
            "updated": False,
            "changed_fields": [],
            "remaining_legacy_references": [],
            "visible_candidate_label": DESIRED_NAME,
            "visible_candidate_model_id": f"{FUNCTION_ID}.{DESIRED_PIPE_ID}",
        })
        sys.exit(0)

    original_content = row["content"] or ""
    updated_content = replace_pipe_identity(original_content)

    original_meta = row["meta"]
    updated_meta = original_meta
    meta_obj = safe_json_loads(original_meta)
    if isinstance(meta_obj, dict):
        manifest = meta_obj.get("manifest")
        if isinstance(manifest, dict):
            manifest["title"] = DESIRED_NAME
        else:
            meta_obj["manifest"] = {"title": DESIRED_NAME}
        updated_meta = json.dumps(meta_obj, ensure_ascii=False)

    updated_name = DESIRED_NAME if row["name"] != DESIRED_NAME else row["name"]
    updates = []
    values = []
    changed_fields = []

    if row["name"] != updated_name:
        updates.append("name = ?")
        values.append(updated_name)
        changed_fields.append("name")

    if updated_content != original_content:
        updates.append("content = ?")
        values.append(updated_content)
        changed_fields.append("content")

    if updated_meta != original_meta:
        updates.append("meta = ?")
        values.append(updated_meta)
        changed_fields.append("meta")

    if row["is_active"] != 1:
        updates.append("is_active = ?")
        values.append(1)
        changed_fields.append("is_active")

    if DRY_RUN:
        remaining = scan_sqlite(conn, "PDA Commander") + scan_sqlite(conn, "pda_commander") + scan_files("/app/backend/data", [b"PDA Commander", b"pda_commander"])
        unique_remaining = []
        seen = set()
        for item in remaining:
            key = tuple((k, item.get(k)) for k in ("kind", "table", "column", "path"))
            if key in seen:
                continue
            seen.add(key)
            unique_remaining.append(item)
        emit({
            "status": "pass",
            "message": f"Dry run: function '{FUNCTION_ID}' would be synchronized to '{DESIRED_NAME}'.",
            "updated": False,
            "dry_run": True,
            "changed_fields": changed_fields,
            "remaining_legacy_references": unique_remaining,
            "visible_candidate_label": DESIRED_NAME,
            "visible_candidate_model_id": f"{FUNCTION_ID}.{DESIRED_PIPE_ID}",
            "database_path": DB_PATH,
        })
        sys.exit(0)

    if updates:
        updates.append("updated_at = ?")
        values.append(int(time.time()))
        values.append(FUNCTION_ID)
        conn.execute(f"UPDATE function SET {', '.join(updates)} WHERE id = ?", values)
        conn.commit()

    legacy_refs = scan_sqlite(conn, "PDA Commander") + scan_sqlite(conn, "pda_commander") + scan_files("/app/backend/data", [b"PDA Commander", b"pda_commander"])
    unique_refs = []
    seen = set()
    for ref in legacy_refs:
        key = (ref.get("kind"), ref.get("table"), ref.get("column"), ref.get("path"))
        if key in seen:
            continue
        seen.add(key)
        unique_refs.append(ref)

    emit({
        "status": "pass",
        "message": f"Open WebUI function '{FUNCTION_ID}' synchronized to '{DESIRED_NAME}'.",
        "updated": bool(updates),
        "dry_run": False,
        "changed_fields": changed_fields,
        "remaining_legacy_references": unique_refs,
        "visible_candidate_label": DESIRED_NAME,
        "visible_candidate_model_id": f"{FUNCTION_ID}.{DESIRED_PIPE_ID}",
    })
except Exception as exc:
    emit({
        "status": "fail",
        "message": str(exc),
        "updated": False,
        "dry_run": bool(DRY_RUN),
        "changed_fields": [],
        "remaining_legacy_references": [],
        "visible_candidate_label": DESIRED_NAME,
        "visible_candidate_model_id": f"{FUNCTION_ID}.{DESIRED_PIPE_ID}",
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
                $Result.changed_fields = @($Json.changed_fields)
                $Result.remaining_legacy_references = @($Json.remaining_legacy_references)
                $Result.visible_candidate_label = [string]$Json.visible_candidate_label
                $Result.visible_candidate_model_id = [string]$Json.visible_candidate_model_id

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
    $Result | ConvertTo-Json -Depth 12
    if (-not $NoThrow -and $Result.status -ne "pass") {
        throw "Open WebUI function repair failed."
    }
    return
}

Write-Host "[*] Open WebUI function repair"
Write-Host ("Status     : {0}" -f $Result.status)
Write-Host ("Message    : {0}" -f $Result.message)
Write-Host ("Dry Run    : {0}" -f $Result.dry_run)
Write-Host ("Desired    : {0}" -f $Result.desired_name)
Write-Host ("Pipe ID    : {0}" -f $Result.desired_pipe_id)
Write-Host ("Visible    : {0} ({1})" -f $Result.visible_candidate_label, $Result.visible_candidate_model_id)
Write-Host ("Updated    : {0}" -f $Result.updated)
Write-Host ("Fields     : {0}" -f (@($Result.changed_fields) -join ", "))
Write-Host ("Legacy refs: {0}" -f (@($Result.remaining_legacy_references) | Measure-Object).Count)
Write-Host ("Issues     : {0}" -f $Issues.Count)

if (-not $NoThrow -and $Result.status -ne "pass") {
    throw "Open WebUI function repair failed."
}
