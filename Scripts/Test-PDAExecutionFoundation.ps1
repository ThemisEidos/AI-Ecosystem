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
        $Lines = @($Trimmed -split "\r?\n")
        $StartIndex = -1
        $EndIndex = -1
        for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
            if ($StartIndex -lt 0 -and $Lines[$Index].TrimStart().StartsWith("{")) {
                $StartIndex = $Index
            }
            if ($Lines[$Index].TrimEnd().EndsWith("}")) {
                $EndIndex = $Index
            }
        }
        if ($StartIndex -ge 0 -and $EndIndex -ge $StartIndex) {
            $Candidate = (($Lines[$StartIndex..$EndIndex]) -join "`n").Trim()
            if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
                return $Candidate | ConvertFrom-Json -ErrorAction Stop
            }
        }

        $Start = $Trimmed.IndexOf("{")
        $End = $Trimmed.LastIndexOf("}")
        if ($Start -ge 0 -and $End -gt $Start) {
            $Candidate = $Trimmed.Substring($Start, $End - $Start + 1)
            return $Candidate | ConvertFrom-Json -ErrorAction Stop
        }
        throw
    }
}

function Invoke-TestScript {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $Path = Join-Path $PSScriptRoot $RelativePath
    $Raw = & pwsh -NoProfile -File $Path -AsJson -NoThrow 2>&1
    $Text = [string]($Raw -join "`n").Trim()

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Test script returned empty output: $RelativePath"
    }

    return ConvertFrom-PDAMixedJson -Text $Text
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
