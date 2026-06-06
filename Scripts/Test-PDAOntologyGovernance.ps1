[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Scripts\PDA_ApprovedEntrypoints.json"),

    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalScriptRoots = @(),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

function Normalize-RelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Relative = [System.IO.Path]::GetRelativePath($BasePath, $Path)
    return ($Relative -replace '/', '\')
}

function Test-PDAWriterSignature {
    param([string]$Content)

    $WriteVerbPattern = '(?is)\b(Set-Content|Move-Item|Copy-Item|New-Item|Remove-Item|Out-File|Add-Content)\b'
    $ProtectedPathPattern = '(?is)(PDA-Tasks\\(?:pending|running|approvals|results|dead-letter|staging(?:\\(?:processed|failed|generated))?))|(\bJoin-Path\b[^\r\n]*(?:pending|running|completed|failed|results|dead-letter|processed|generated|approved|rejected))'
    $IndirectDispatchPattern = '(?is)\bResolve-PDATaskDispatchContext\b.*\bTaskFile\b|\bTaskFile\b.*\bResolve-PDATaskDispatchContext\b'
    return (($Content -match $WriteVerbPattern) -and (($Content -match $ProtectedPathPattern) -or ($Content -match $IndirectDispatchPattern)))
}

function Get-PDAWriterMatches {
    param([string]$Content)

    $Found = New-Object System.Collections.Generic.List[string]
    foreach ($Token in @(
        'PDA-Tasks\pending',
        'PDA-Tasks\running',
        'PDA-Tasks\approvals',
        'PDA-Tasks\staging',
        'PDA-Tasks\results',
        'PDA-Tasks\dead-letter',
        'PDA-Tasks\staging\processed',
        'PDA-Tasks\staging\failed',
        'PDA-Tasks\staging\generated',
        'Resolve-PDATaskDispatchContext',
        'Get-PDATaskWorkerEligibility',
        'Test-PDATaskOntologyContract'
    )) {
        if ($Content -match [regex]::Escape($Token)) {
            $null = $Found.Add($Token)
        }
    }

    return @($Found)
}

function Get-PDAWriterCandidateType {
    param(
        [string]$Content,
        [string[]]$DirectSignals
    )

    $WriteVerbPattern = '(?i)\b(Set-Content|Move-Item|Copy-Item|New-Item|Remove-Item|Out-File|Add-Content)\b'
    $Lines = @($Content -split "`r?`n")

    foreach ($Line in $Lines) {
        if ($Line -notmatch $WriteVerbPattern) {
            continue
        }

        foreach ($Signal in $DirectSignals) {
            if ([string]::IsNullOrWhiteSpace($Signal)) {
                continue
            }

            if ($Line -match [regex]::Escape($Signal)) {
                return "protected_path"
            }
        }
    }

    if (($Content -match '(?is)\bResolve-PDATaskDispatchContext\b') -and
        ($Content -match '(?i)\bTaskFile\b') -and
        ($Content -match $WriteVerbPattern)) {
        return "indirect_dispatch"
    }

    return $null
}

if (-not (Test-Path $ManifestPath -PathType Leaf)) {
    throw "Approved entrypoint manifest not found: $ManifestPath"
}

$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$ApprovedEntryMap = @{}
foreach ($Entry in @($Manifest.approved_entrypoints)) {
    $Normalized = ($Entry.path -replace '/', '\')
    $ApprovedEntryMap[$Normalized] = $Entry
}

$ScriptRoots = @((Join-Path $Root "Scripts"))
if ($AdditionalScriptRoots) {
    $ScriptRoots += $AdditionalScriptRoots
}

$Candidates = foreach ($ScriptRoot in $ScriptRoots) {
    if (-not (Test-Path $ScriptRoot)) {
        continue
    }

    Get-ChildItem -Path $ScriptRoot -Recurse -File -Filter *.ps1 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.bak.ps1' }
}

$ObservedWriters = New-Object System.Collections.Generic.List[object]
$Violations = New-Object System.Collections.Generic.List[object]

$DirectWriterSignals = New-Object System.Collections.Generic.List[string]
foreach ($Entry in @($Manifest.approved_entrypoints)) {
    foreach ($Signal in @($Entry.writer_signals)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Signal)) {
            if ([string]$Signal -eq 'TaskFile' -or [string]$Signal -eq 'TaskPath') {
                continue
            }
            $null = $DirectWriterSignals.Add([string]$Signal)
        }
    }
}
$DirectWriterSignals = @($DirectWriterSignals | Sort-Object -Unique)

function Test-PDAWriterObserved {
    param(
        [string]$Content,
        [object]$Entry
    )

    $ScanMode = if ($Entry.PSObject.Properties['scan_mode']) { [string]$Entry.scan_mode } else { "direct_path" }
    $WriteVerbPattern = '(?i)\b(Set-Content|Move-Item|Copy-Item|New-Item|Remove-Item|Out-File|Add-Content)\b'
    $Signals = @($Entry.writer_signals)

    switch ($ScanMode) {
        "indirect_dispatch" {
            return (($Content -match '(?is)\bResolve-PDATaskDispatchContext\b') -and
                    ($Content -match '(?i)\bTaskFile\b') -and
                    ($Content -match $WriteVerbPattern))
        }
        default {
            foreach ($Line in @($Content -split "`r?`n")) {
                if ($Line -notmatch $WriteVerbPattern) {
                    continue
                }

                foreach ($Signal in $Signals) {
                    if ([string]::IsNullOrWhiteSpace([string]$Signal)) {
                        continue
                    }

                    if ($Line -match [regex]::Escape([string]$Signal)) {
                        return $true
                    }
                }
            }

            return $false
        }
    }
}

foreach ($File in @($Candidates | Sort-Object FullName -Unique)) {
    $Relative = Normalize-RelativePath -BasePath $Root -Path $File.FullName
    $Relative = $Relative -replace '/', '\'

    if ($Relative -like 'Scripts\Test-PDAOntologyGovernance*.ps1') {
        continue
    }

    $Content = Get-Content $File.FullName -Raw
    if ($Relative -eq 'Scripts\Test-PDAOntologyDispatch.ps1') {
        $CandidateType = if (($Content -match '(?i)\bSet-Content\b') -and ($Content -match '(?i)\bTaskPath\b')) { "protected_path" } else { $null }
    }
    else {
        $CandidateType = Get-PDAWriterCandidateType -Content $Content -DirectSignals $DirectWriterSignals
    }
    if (-not $CandidateType) {
        continue
    }

    $PathTokens = Get-PDAWriterMatches -Content $Content
    $ObservedWriters.Add([pscustomobject]@{
        path       = $Relative
        tokens     = $PathTokens
        candidate  = $CandidateType
        full_path  = $File.FullName
    })

    if (-not $ApprovedEntryMap.ContainsKey($Relative)) {
        $Violations.Add([pscustomobject]@{
            type = "unknown_writer"
            path = $Relative
            reason = "Writer is not listed in PDA_ApprovedEntrypoints.json."
        })
        continue
    }

    $Entry = $ApprovedEntryMap[$Relative]
    if (-not (Test-PDAWriterObserved -Content $Content -Entry $Entry)) {
        $Violations.Add([pscustomobject]@{
            type = "unobserved_writer"
            path = $Relative
            reason = "Approved writer is missing the expected protected-path or dispatch signature."
        })
        continue
    }

    $RequiredTokens = @($Entry.required_tokens)
    foreach ($Token in $RequiredTokens) {
        if ($Content -notmatch [regex]::Escape([string]$Token)) {
            $Violations.Add([pscustomobject]@{
                type = "missing_guard"
                path = $Relative
                reason = "Missing required token: $Token"
            })
        }
    }
}

foreach ($Entry in @($Manifest.approved_entrypoints)) {
    $Normalized = ($Entry.path -replace '/', '\')
    if (-not (@($ObservedWriters.path) -contains $Normalized)) {
        $Violations.Add([pscustomobject]@{
            type = "missing_writer"
            path = $Normalized
            reason = "Approved writer is no longer detected by the static writer scan."
        })
    }
}

$ApprovedEntrypointCount = $Manifest.approved_entrypoints.Count
$ObservedWriterCount = $ObservedWriters.Count
$ViolationCount = $Violations.Count
$Status = if ($ViolationCount -eq 0) { "pass" } else { "fail" }

$Report = [pscustomobject]@{
    generated_at             = (Get-Date).ToString("s")
    root                     = $Root
    manifest_path            = $ManifestPath
    protected_paths          = @($Manifest.protected_paths)
    approved_entrypoint_count = $ApprovedEntrypointCount
    observed_writer_count    = $ObservedWriterCount
    violation_count          = $ViolationCount
    status                   = $Status
    approved_entrypoints     = @($Manifest.approved_entrypoints)
    observed_writers         = @($ObservedWriters.ToArray())
    violations               = @($Violations.ToArray())
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
}
else {
    Write-Host "[*] PDA ontology governance scan"
    Write-Host ("Approved entrypoints : {0}" -f $Report.approved_entrypoint_count)
    Write-Host ("Observed writers     : {0}" -f $Report.observed_writer_count)
    Write-Host ("Violations           : {0}" -f $Report.violation_count)
    Write-Host ("Status               : {0}" -f $Report.status)

    if ($Violations.Count -gt 0) {
        Write-Host ""
        Write-Host "[Violations]"
        foreach ($Violation in $Violations) {
            Write-Host ("- {0}: {1} ({2})" -f $Violation.type, $Violation.path, $Violation.reason)
        }
    }
}

if ($Violations.Count -gt 0 -and -not $NoThrow) {
    throw "Ontology governance scan failed with $($Violations.Count) violation(s)."
}
