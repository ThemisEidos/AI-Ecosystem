function Get-COOPERWorkflowDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$Path = ""
    )

    $ErrorActionPreference = "Stop"

    function ConvertTo-COOPERWorkflowValue {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Value
        )

        $Text = [string]$Value.Trim()
        if ([string]::IsNullOrWhiteSpace($Text)) {
            return ""
        }

        if ($Text -match '^(?i:true|false)$') {
            return [bool]::Parse($Text)
        }

        if ($Text -match '^\d+$') {
            return [int]$Text
        }

        return $Text
    }

    function New-COOPERWorkflowDefinition {
        param(
            [Parameter(Mandatory = $true)]
            [hashtable]$Data
        )

        $Keywords = @()
        if ($Data.ContainsKey("intent_keywords")) {
            $Keywords = @(
                @($Data.intent_keywords) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                    ForEach-Object { [string]$_ }
            )
        }

        return [pscustomobject]@{
            id = [string]$Data.id
            name = [string]$Data.name
            workshop = [string]$Data.workshop
            permission_level = $Data.permission_level
            approval_required = [bool]$Data.approval_required
            intent_keywords = @($Keywords)
            executor = [string]$Data.executor
            output_type = [string]$Data.output_type
            storage_target = [string]$Data.storage_target
            status = [string]$Data.status
            source_of_truth = "Config/workflows.yaml"
        }
    }

    function Get-COOPERWorkflowDefinitionsFallback {
        return @(
            [pscustomobject]@{
                id = "WF-002"
                name = "Codex Task Generator"
                workshop = "Open"
                permission_level = 2
                approval_required = $true
                intent_keywords = @("codex task", "implementation task", "development task", "engineering task", "project task", "action item", "work item", "create task", "task generator", "task file", "turn this into a task", "convert this into a task", "make a task from this", "turn this into a development task", "generate an implementation task", "create an engineering task", "write a task for codex", "project decision", "workflow output", "roadmap item", "finding", "issue")
                executor = "codex_task_generator"
                output_type = "markdown_file"
                storage_target = "codex_tasks"
                status = "operational"
                source_of_truth = "Config/workflows.yaml"
            }
            [pscustomobject]@{
                id = "WF-004"
                name = "Operational Status"
                workshop = "Open"
                permission_level = 1
                approval_required = $false
                intent_keywords = @("what can you do", "what workflows are available", "what capabilities do you have", "what phase are we in", "what is operational", "what is working right now", "show system status", "system status", "status report", "current status")
                executor = "operational_status"
                output_type = "status_report"
                storage_target = "read_only"
                status = "operational"
                source_of_truth = "Config/workflows.yaml"
            }
            [pscustomobject]@{
                id = "WF-001"
                name = "Research Summary"
                workshop = "Open"
                permission_level = 3
                approval_required = $true
                intent_keywords = @("research", "search", "source", "summarize", "summary", "documentation", "official", "pop os", "linux infrastructure")
                executor = "research_summary"
                output_type = "markdown_note"
                storage_target = "project_workspace"
                status = "operational"
                source_of_truth = "Config/workflows.yaml"
            }
            [pscustomobject]@{
                id = "WF-005"
                name = "Note Creation"
                workshop = "Open"
                permission_level = 2
                approval_required = $true
                intent_keywords = @("create note", "write note", "save note", "obsidian note", "note creation")
                executor = "create_note"
                output_type = "markdown_file"
                storage_target = "obsidian_drafts"
                status = "operational"
                source_of_truth = "Config/workflows.yaml"
            }
            [pscustomobject]@{
                id = "WF-006"
                name = "Knowledge Collection Import Draft"
                workshop = "Open"
                permission_level = 2
                approval_required = $true
                intent_keywords = @("prepare for collection", "knowledge collection", "import draft", "prepare for knowledge base", "add to collection")
                executor = "knowledge_collection_import_draft"
                output_type = "markdown_file"
                storage_target = "obsidian_collection_import_drafts"
                status = "operational"
                source_of_truth = "Config/workflows.yaml"
            }
        )
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $Root "Config\workflows.yaml"
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @(Get-COOPERWorkflowDefinitionsFallback)
    }

    $Workflows = @()
    $Current = $null
    $CurrentListKey = ""

    foreach ($Line in Get-Content -LiteralPath $Path) {
        $Trimmed = [string]$Line.Trim()
        if ([string]::IsNullOrWhiteSpace($Trimmed) -or $Trimmed.StartsWith("#")) {
            continue
        }

        if ($Trimmed -eq "workflows:") {
            continue
        }

        if ($Line -match '^\s*-\s*id:\s*(?<Id>.+)$') {
            if ($null -ne $Current) {
                $Workflows += (New-COOPERWorkflowDefinition -Data $Current)
            }

            $Current = [ordered]@{
                id = [string]$Matches.Id.Trim()
                intent_keywords = @()
                source_of_truth = "Config/workflows.yaml"
            }
            $CurrentListKey = ""
            continue
        }

        if ($null -eq $Current) {
            continue
        }

        if ($Line -match '^\s{4,}-\s*(?<Item>.+)$' -and -not [string]::IsNullOrWhiteSpace($CurrentListKey)) {
            $Current[$CurrentListKey] = @($Current[$CurrentListKey]) + (ConvertTo-COOPERWorkflowValue -Value $Matches.Item)
            continue
        }

        if ($Line -match '^\s{2,}(?<Key>[A-Za-z0-9_]+):\s*(?<Value>.*)$') {
            $Key = [string]$Matches.Key
            $Value = [string]$Matches.Value
            if ([string]::IsNullOrWhiteSpace($Value)) {
                $Current[$Key] = @()
                $CurrentListKey = $Key
            }
            else {
                $Current[$Key] = ConvertTo-COOPERWorkflowValue -Value $Value
                $CurrentListKey = ""
            }
        }
    }

    if ($null -ne $Current) {
        $Workflows += (New-COOPERWorkflowDefinition -Data $Current)
    }

    if ($Workflows.Count -eq 0) {
        return @(Get-COOPERWorkflowDefinitionsFallback)
    }

    return @(
        $Workflows | ForEach-Object {
            $_.intent_keywords = @(
                @($_.intent_keywords) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                    ForEach-Object { [string]$_ }
            )
            $_
        }
    )
}

if ($MyInvocation.InvocationName -ne '.') {
    Get-COOPERWorkflowDefinitions @PSBoundParameters
}
