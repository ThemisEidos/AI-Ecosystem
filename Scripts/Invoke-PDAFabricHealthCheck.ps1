[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Fabric.ps1")

function ConvertTo-PDAFabricHealthResult {
    param(
        [string]$Status = "fail",
        [string]$Message = "",
        [string]$Version = "",
        [string]$ExecutablePath = "",
        [string]$ConfigPath = "",
        [bool]$ConfigExists = $false,
        [string]$PatternListStatus = "missing",
        [int]$PatternCount = 0,
        [string[]]$AvailablePatterns = @(),
        [int]$PDAPatternCount = 0,
        [object[]]$PDAPatterns = @(),
        [string[]]$MissingPDAPatterns = @()
    )

    return [pscustomobject]@{
        status             = $Status
        message            = $Message
        executable_path    = $ExecutablePath
        version            = $Version
        config_path        = $ConfigPath
        config_exists      = $ConfigExists
        pattern_list_status = $PatternListStatus
        pattern_count      = $PatternCount
        available_patterns = @($AvailablePatterns)
        pda_pattern_count  = $PDAPatternCount
        pda_patterns       = @($PDAPatterns)
        missing_pda_patterns = @($MissingPDAPatterns)
        checked_at         = (Get-Date).ToUniversalTime().ToString("o")
    }
}

$ExecutablePath = Get-PDAFabricExecutablePath -Root $Root
$ConfigPath = Get-PDAFabricConfigPath
$ConfigExists = Test-Path -Path $ConfigPath -PathType Leaf
$FabricPatternsRoot = Join-Path (Split-Path $ConfigPath -Parent) "patterns"
$PDAPatternChecks = @(
    [pscustomobject]@{ alias = "research"; path = (Join-Path $FabricPatternsRoot "Research\research-synthesis\system.md") },
    [pscustomobject]@{ alias = "report"; path = (Join-Path $FabricPatternsRoot "Reporting\report-summary\system.md") },
    [pscustomobject]@{ alias = "review"; path = (Join-Path $FabricPatternsRoot "Review\review-checklist\system.md") },
    [pscustomobject]@{ alias = "security"; path = (Join-Path $FabricPatternsRoot "Security\security-triage\system.md") }
)
$Status = "fail"
$Message = ""
$Version = ""
$PatternListStatus = "missing"
$PatternCount = 0
$AvailablePatterns = @()
$PDAPatterns = @()
$MissingPDAPatterns = @()

if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $Message = "Fabric is not installed or not on PATH."
}
else {
    try {
        $Version = ([string](& $ExecutablePath --version)).Trim()
        if ([string]::IsNullOrWhiteSpace($Version)) {
            $Message = "Fabric version check returned no output."
        }
        else {
            $PatternListRaw = @(& $ExecutablePath --listpatterns 2>&1)
            $PatternListText = [string]($PatternListRaw -join "`n").Trim()
            if (-not [string]::IsNullOrWhiteSpace($PatternListText)) {
                $PatternLines = @(
                    $PatternListText -split '\r?\n' |
                    Where-Object {
                        $Line = ([string]$_).Trim()
                        -not [string]::IsNullOrWhiteSpace($Line) -and
                        $Line -notmatch '^(Available patterns|Patterns are required|No patterns found|━━━━━━━━|⚠️|Option|To fix this|fabric --setup|fabric -U)'
                    }
                )
                $AvailablePatterns = @($PatternLines)
                $PatternCount = $AvailablePatterns.Count
                $PatternListStatus = if ($PatternCount -gt 0) { "pass" } else { "empty" }
                foreach ($PatternCheck in $PDAPatternChecks) {
                    $Exists = Test-Path -Path $PatternCheck.path -PathType Leaf
                    $PDAPatterns += [pscustomobject]@{
                        alias = $PatternCheck.alias
                        path = $PatternCheck.path
                        exists = [bool]$Exists
                    }

                    if (-not $Exists) {
                        $MissingPDAPatterns += $PatternCheck.alias
                    }
                }

                $Status = if ($PatternCount -gt 0 -and $MissingPDAPatterns.Count -eq 0) { "pass" } else { "warning" }
                $Message = if ($PatternCount -gt 0 -and $MissingPDAPatterns.Count -eq 0) { "Fabric CLI is installed and PDA patterns are synced." } else { "Fabric CLI is installed, but one or more PDA patterns are missing." }
            }
            else {
                $Status = "warning"
                $Message = "Fabric CLI is installed, but pattern listing returned no output."
            }
        }
    }
    catch {
        $Status = "warning"
        $Message = "Fabric CLI is installed, but pattern listing failed: $($_.Exception.Message)"
        $PatternListStatus = "error"
    }
}

$Result = ConvertTo-PDAFabricHealthResult -Status $Status -Message $Message -Version $Version -ExecutablePath $ExecutablePath -ConfigPath $ConfigPath -ConfigExists $ConfigExists -PatternListStatus $PatternListStatus -PatternCount $PatternCount -AvailablePatterns $AvailablePatterns -PDAPatternCount $PDAPatterns.Count -PDAPatterns $PDAPatterns -MissingPDAPatterns $MissingPDAPatterns

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 10
    return
}

Write-Host "[*] Fabric health check"
Write-Host ("Status          : {0}" -f $Result.status)
Write-Host ("Message         : {0}" -f $Result.message)
Write-Host ("Executable path  : {0}" -f $Result.executable_path)
Write-Host ("Version         : {0}" -f $Result.version)
Write-Host ("Config path     : {0}" -f $Result.config_path)
Write-Host ("Config exists   : {0}" -f $Result.config_exists)
Write-Host ("Pattern status  : {0}" -f $Result.pattern_list_status)
Write-Host ("Pattern count   : {0}" -f $Result.pattern_count)

if ($Result.status -ne "pass" -and -not $NoThrow) {
    throw $Result.message
}
