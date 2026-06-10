[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Tests = @(
    "Scripts\Test-PDAToolRegistry.ps1",
    "Scripts\Test-PDAAgentResolver.ps1",
    "Scripts\Test-PDAProviderResolver.ps1",
    "Scripts\Test-PDAExecutionPlanResolver.ps1",
    "Scripts\Test-PDAExecutionRequest.ps1",
    "Scripts\Test-PDAApprovalWorkflow.ps1",
    "Scripts\Test-PDAOrchestrationFiles.ps1"
)

function ConvertFrom-PDAMixedJson {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Trimmed = [string]$Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Trimmed)) {
        return $null
    }

    try {
        return $Trimmed | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $Candidates = New-Object System.Collections.Generic.List[string]
        $Depth = 0
        $StartIndex = -1
        $InString = $false
        $Escaped = $false

        for ($Index = 0; $Index -lt $Trimmed.Length; $Index++) {
            $Char = $Trimmed[$Index]

            if ($InString) {
                if ($Escaped) {
                    $Escaped = $false
                    continue
                }
                if ($Char -eq '\') {
                    $Escaped = $true
                    continue
                }
                if ($Char -eq '"') {
                    $InString = $false
                    continue
                }
                continue
            }

            switch ($Char) {
                '"' {
                    $InString = $true
                }
                '{' {
                    if ($Depth -eq 0) {
                        $StartIndex = $Index
                    }
                    $Depth++
                }
                '}' {
                    if ($Depth -gt 0) {
                        $Depth--
                        if ($Depth -eq 0 -and $StartIndex -ge 0) {
                            $Candidate = $Trimmed.Substring($StartIndex, $Index - $StartIndex + 1).Trim()
                            if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
                                $Candidates.Add($Candidate) | Out-Null
                            }
                            $StartIndex = -1
                        }
                    }
                }
            }
        }

        for ($Index = $Candidates.Count - 1; $Index -ge 0; $Index--) {
            try {
                return $Candidates[$Index] | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                continue
            }
        }

        $Lines = @($Trimmed -split "\r?\n")
        $StartLine = [Math]::Max(0, $Lines.Count - 20)
        $Tail = if ($Lines.Count -gt 0) { @($Lines[$StartLine..($Lines.Count - 1)]) -join "`n" } else { "" }
        $Preview = [pscustomobject]@{
            line_count = $Lines.Count
            candidate_count = $Candidates.Count
            tail = $Tail
        } | ConvertTo-Json -Depth 5 -Compress
        throw "Unable to extract JSON from mixed output. Diagnostics: $Preview"
    }
}

function ConvertFrom-PDAOrchestrationFilesText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Lines = @([string]$Text.Trim() -split "\r?\n")
    $Missing = New-Object System.Collections.Generic.List[string]
    foreach ($Line in $Lines) {
        if ($Line -match '^\[MISSING\]\s+(.*)$') {
            $Missing.Add([string]$Matches[1]) | Out-Null
        }
    }

    return [pscustomobject]@{
        status = $(if ($Missing.Count -eq 0) { "pass" } else { "fail" })
        issues = @($Missing | ForEach-Object { "Missing required path: $_" })
        line_count = $Lines.Count
        parser_mode = "text"
        source_of_truth = "Scripts/Test-PDAOrchestrationFiles.ps1"
    }
}

function Invoke-TestScript {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $Path = Join-Path $Root $RelativePath
    $Raw = & pwsh -NoProfile -File $Path -AsJson -NoThrow 2>&1
    $Text = [string]($Raw -join "`n").Trim()

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Test script returned empty output: $RelativePath"
    }

    try {
        return ConvertFrom-PDAMixedJson -Text $Text
    }
    catch {
        if ($RelativePath -ieq "Scripts\Test-PDAOrchestrationFiles.ps1") {
            return ConvertFrom-PDAOrchestrationFilesText -Text $Text
        }

        $PreviewLines = @([string]$Text.Trim() -split "\r?\n")
        $TailStart = [Math]::Max(0, $PreviewLines.Count - 20)
        $Tail = if ($PreviewLines.Count -gt 0) { @($PreviewLines[$TailStart..($PreviewLines.Count - 1)]) -join "`n" } else { "" }
        throw "Unable to parse JSON from $RelativePath. Tail preview: $Tail"
    }
}

$Results = @()
$Issues = New-Object System.Collections.Generic.List[string]
$Passed = 0
$Failed = 0

foreach ($Test in $Tests) {
    try {
        $Result = Invoke-TestScript -RelativePath $Test
        $Results += [pscustomobject]@{
            test = $Test
            status = [string]$Result.status
            passed = [bool]($Result.status -eq "pass")
            issues = if ($Result.PSObject.Properties.Name -contains "issues") { @($Result.issues) } else { @() }
        }

        if ([string]$Result.status -eq "pass") {
            $Passed++
        }
        else {
            $Failed++
            foreach ($Issue in @($Result.issues)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$Issue)) {
                    $Issues.Add("{0}: {1}" -f $Test, [string]$Issue)
                }
            }
        }
    }
    catch {
        $Failed++
        $Issue = "$($Test): $($_.Exception.Message)"
        $Issues.Add($Issue)
        $Results += [pscustomobject]@{
            test = $Test
            status = "error"
            passed = $false
            issues = @($Issue)
        }
    }
}

$Status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
$Report = [pscustomobject]@{
    status = $Status
    root_path = $Root
    test_count = @($Tests).Count
    passed_count = $Passed
    failed_count = $Failed
    issues = @($Issues)
    results = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if ($Status -ne "pass" -and -not $NoThrow) { throw "PDA execution foundation validation failed." }
    return
}

if ($Status -eq "pass") {
    Write-Host "[OK] PDA execution foundation validation passed."
}
else {
    Write-Host "[ERROR] PDA execution foundation validation failed."
    foreach ($Issue in @($Issues)) {
        Write-Host (" - {0}" -f $Issue)
    }
    if (-not $NoThrow) { throw "PDA execution foundation validation failed." }
}
