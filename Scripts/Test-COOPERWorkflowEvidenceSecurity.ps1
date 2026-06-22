[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$FixtureRoot = Join-Path $Root "Tests\Fixtures\Workflow_Evidence"
$InvalidRoot = Join-Path $FixtureRoot "Invalid"

$OpenCompletionFixturePath = Join-Path $FixtureRoot "workflow_completion_WF-002_20260622T000000Z-test.json"
$ApprovalFixturePath = Join-Path $FixtureRoot "approval_lifecycle_AP-20260622-000001.json"
$PrivateCompletionFixturePath = Join-Path $FixtureRoot "workflow_completion_WF-007_20260622T000000Z-private.json"

$InvalidFixtures = @(
    [pscustomobject]@{
        path = Join-Path $InvalidRoot "workflow_completion_WF-002_20260622T001000Z-open-restricted-path.json"
        expected = "open restricted path"
    },
    [pscustomobject]@{
        path = Join-Path $InvalidRoot "workflow_completion_WF-007_20260622T001100Z-private-obsidian-path.json"
        expected = "private obsidian path"
    },
    [pscustomobject]@{
        path = Join-Path $InvalidRoot "workflow_completion_WF-007_20260622T001200Z-private-external-url.json"
        expected = "private external url"
    },
    [pscustomobject]@{
        path = Join-Path $InvalidRoot "workflow_completion_WF-002_20260622T001300Z-sensitive-marker.json"
        expected = "sensitive marker"
    },
    [pscustomobject]@{
        path = Join-Path $InvalidRoot "workflow_completion_WF-007_20260622T001400Z-private-proton-path.json"
        expected = "private proton path"
    }
)

$Issues = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([Parameter(Mandatory = $true)][string]$Message)

    [void]$Issues.Add($Message)
}

function Normalize-PathText {
    param([Parameter(Mandatory = $true)][string]$Text)

    return ($Text.Trim() -replace '/', '\').ToLowerInvariant()
}

function Read-JsonFixture {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Issue "Missing workflow evidence fixture: $Path"
        return $null
    }

    try {
        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return [pscustomobject]@{
            path = $Path
            raw = $Raw
            record = ($Raw | ConvertFrom-Json -ErrorAction Stop)
        }
    }
    catch {
        Add-Issue "Invalid JSON fixture: $Path"
        return $null
    }
}

function Get-WorkflowEvidenceSecurityIssues {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$RawText,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $Issues = New-Object System.Collections.Generic.List[string]
    $ArtifactPaths = @($Record.artifact_paths)
    $WorkshopId = [string]$Record.workshop_id
    $WorkshopName = [string]$Record.workshop_name
    $IsOpen = ($WorkshopId -eq "open") -or ($WorkshopName -match '(?i)Open Workshop')
    $IsPrivate = ($WorkshopId -eq "private") -or ($WorkshopName -match '(?i)Private Workshop')

    foreach ($Marker in @(
        "api_key",
        "password",
        "secret",
        "token",
        "private_key",
        "credential",
        "client-sensitive",
        "restricted log",
        "unredacted",
        "PII"
    )) {
        if ($RawText -match "(?i)\b$([regex]::Escape($Marker))\b") {
            [void]$Issues.Add("Fixture contains sensitive marker: $Path")
            break
        }
    }

    foreach ($ArtifactPath in $ArtifactPaths) {
        if ([string]::IsNullOrWhiteSpace([string]$ArtifactPath)) {
            continue
        }

        $Normalized = Normalize-PathText -Text ([string]$ArtifactPath)
        $IsExternalUrl = $Normalized -match '^[a-z][a-z0-9+.\-]*://'
        $IsRestricted = $Normalized -match '(?:^|\\)restricted dmz workspace(?:\\|$)'
        $IsSecureVault = $Normalized -match '(?:^|\\)secure vault(?:\\|$)'
        $IsStandardNotes = $Normalized -match '(?:^|\\)standardnotes(?:\\|$)'
        $IsObsidian = $Normalized -match '(?:^|\\)obsidian(?:\\|$)'
        $IsOpenWebUI = $Normalized -match '(?:^|\\)open webui workspace(?:\\|$)'
        $IsProton = $Normalized -match 'proton drive'

        if ($IsOpen) {
            if ($IsRestricted -or $IsSecureVault -or $IsStandardNotes) {
                [void]$Issues.Add("Open Workshop artifact path references restricted storage: $Path")
            }
            if ($IsOpenWebUI -or $IsProton) {
                [void]$Issues.Add("Open Workshop artifact path references non-open storage: $Path")
            }
        }

        if ($IsPrivate) {
            if (-not $IsRestricted) {
                [void]$Issues.Add("Private Workshop artifact path is outside Restricted DMZ Workspace: $Path")
            }
            if ($IsObsidian -or $IsOpenWebUI -or $IsExternalUrl -or $IsProton) {
                [void]$Issues.Add("Private Workshop artifact path references forbidden location: $Path")
            }
            if ($Normalized -match '(?:^|\\)secure vault(?:\\|$)' -or $Normalized -match '(?:^|\\)standardnotes(?:\\|$)') {
                [void]$Issues.Add("Private Workshop artifact path references restricted personal storage: $Path")
            }
        }
    }

    return @($Issues)
}

function Assert-NoIssues {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)]$Fixture
    )

    $SecurityIssues = Get-WorkflowEvidenceSecurityIssues -Record $Fixture.record -RawText $Fixture.raw -Path $Fixture.path
    if ($SecurityIssues.Count -gt 0) {
        foreach ($Issue in $SecurityIssues) {
            Add-Issue "$Label failed: $Issue"
        }
    }
}

function Assert-ExpectedIssues {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)][string[]]$ExpectedFragments
    )

    $SecurityIssues = Get-WorkflowEvidenceSecurityIssues -Record $Fixture.record -RawText $Fixture.raw -Path $Fixture.path
    if ($SecurityIssues.Count -eq 0) {
        Add-Issue "$Label should fail security validation."
        return
    }

    foreach ($ExpectedFragment in $ExpectedFragments) {
        $Matched = $false
        foreach ($Issue in $SecurityIssues) {
            if ([string]$Issue -match [regex]::Escape($ExpectedFragment)) {
                $Matched = $true
                break
            }
        }
        if (-not $Matched) {
            Add-Issue "$Label did not report expected rule violation: $ExpectedFragment"
        }
    }
}

foreach ($Path in @($OpenCompletionFixturePath, $ApprovalFixturePath, $PrivateCompletionFixturePath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Issue "Missing workflow evidence fixture: $Path"
    }
}

$OpenCompletion = Read-JsonFixture -Path $OpenCompletionFixturePath
$ApprovalFixture = Read-JsonFixture -Path $ApprovalFixturePath
$PrivateCompletion = Read-JsonFixture -Path $PrivateCompletionFixturePath

if ($OpenCompletion) {
    Assert-NoIssues -Label "Open completion fixture" -Fixture $OpenCompletion
}
if ($ApprovalFixture) {
    Assert-NoIssues -Label "Approval fixture" -Fixture $ApprovalFixture
}
if ($PrivateCompletion) {
    Assert-NoIssues -Label "Private completion fixture" -Fixture $PrivateCompletion
}

foreach ($Case in $InvalidFixtures) {
    if (-not (Test-Path -LiteralPath $Case.path -PathType Leaf)) {
        Add-Issue "Missing workflow evidence fixture: $($Case.path)"
        continue
    }

    $Fixture = Read-JsonFixture -Path $Case.path
    if (-not $Fixture) {
        continue
    }

    switch -Wildcard ($Case.expected) {
        "open restricted path" {
            Assert-ExpectedIssues -Label $Case.path -Fixture $Fixture -ExpectedFragments @(
                "Open Workshop artifact path references restricted storage"
            )
        }
        "private obsidian path" {
            Assert-ExpectedIssues -Label $Case.path -Fixture $Fixture -ExpectedFragments @(
                "Private Workshop artifact path is outside Restricted DMZ Workspace"
            )
        }
        "private external url" {
            Assert-ExpectedIssues -Label $Case.path -Fixture $Fixture -ExpectedFragments @(
                "Private Workshop artifact path is outside Restricted DMZ Workspace"
            )
        }
        "sensitive marker" {
            Assert-ExpectedIssues -Label $Case.path -Fixture $Fixture -ExpectedFragments @(
                "Fixture contains sensitive marker"
            )
        }
        "private proton path" {
            Assert-ExpectedIssues -Label $Case.path -Fixture $Fixture -ExpectedFragments @(
                "Private Workshop artifact path is outside Restricted DMZ Workspace"
            )
        }
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    issues = @($Issues)
    source_of_truth = "Docs/Workflow_Evidence_Standard.md"
}

Write-Host "[*] COOPER workflow evidence security validation"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Fixtures : {0}" -f (@($OpenCompletionFixturePath, $ApprovalFixturePath, $PrivateCompletionFixturePath) + @($InvalidFixtures | ForEach-Object { $_.path }) -join ", "))

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] Workflow evidence security validated."
exit 0
