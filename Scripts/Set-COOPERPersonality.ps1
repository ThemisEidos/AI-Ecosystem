[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [int]$Humor,

    [Parameter(Mandatory = $false)]
    [int]$Sarcasm,

    [Parameter(Mandatory = $false)]
    [int]$Professionalism,

    [Parameter(Mandatory = $false)]
    [int]$Brevity,

    [Parameter(Mandatory = $false)]
    [int]$Initiative,

    [Parameter(Mandatory = $false)]
    [int]$RiskAwareness,

    [Parameter(Mandatory = $false)]
    [string]$Profile,

    [Parameter(Mandatory = $false)]
    [string]$ProfilePath,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "COOPER_PersonalityEngine.ps1")

try {
    $Current = Get-COOPERPersonality -Root $Root
    $Next = [ordered]@{}
    foreach ($Key in @("humor", "sarcasm", "professionalism", "brevity", "initiative", "risk_awareness", "profile")) {
        $Next[$Key] = $Current.personality.$Key
    }

    $Changes = @{}
    if ($PSBoundParameters.ContainsKey("Humor")) { $Next.humor = ConvertTo-COOPERPersonalityInt -Value $Humor -Name "humor"; $Changes.humor = $true }
    if ($PSBoundParameters.ContainsKey("Sarcasm")) { $Next.sarcasm = ConvertTo-COOPERPersonalityInt -Value $Sarcasm -Name "sarcasm"; $Changes.sarcasm = $true }
    if ($PSBoundParameters.ContainsKey("Professionalism")) { $Next.professionalism = ConvertTo-COOPERPersonalityInt -Value $Professionalism -Name "professionalism"; $Changes.professionalism = $true }
    if ($PSBoundParameters.ContainsKey("Brevity")) { $Next.brevity = ConvertTo-COOPERPersonalityInt -Value $Brevity -Name "brevity"; $Changes.brevity = $true }
    if ($PSBoundParameters.ContainsKey("Initiative")) { $Next.initiative = ConvertTo-COOPERPersonalityInt -Value $Initiative -Name "initiative"; $Changes.initiative = $true }
    if ($PSBoundParameters.ContainsKey("RiskAwareness")) { $Next.risk_awareness = ConvertTo-COOPERPersonalityInt -Value $RiskAwareness -Name "risk_awareness"; $Changes.risk_awareness = $true }

    $ExplicitProfile = $null
    if ($PSBoundParameters.ContainsKey("Profile") -and -not [string]::IsNullOrWhiteSpace($Profile)) {
        $ExplicitProfile = $Profile.Trim().ToLowerInvariant()
    }

    if (-not [string]::IsNullOrWhiteSpace($ExplicitProfile)) {
        $ProfileDefinition = Get-COOPERProfileDefinition -Profile $ExplicitProfile -Root $Root
        if (-not $ProfileDefinition) {
            throw "Unsupported COOPER profile '$Profile'. Available profiles: operations, cyber, investigator, engineer, trainer."
        }

        foreach ($Key in @("humor", "sarcasm", "professionalism", "brevity", "initiative", "risk_awareness")) {
            if ($ProfileDefinition.PSObject.Properties.Name -contains $Key) {
                $Next[$Key] = ConvertTo-COOPERPersonalityInt -Value $ProfileDefinition.$Key -Name $Key
            }
        }
        $Next.profile = $ExplicitProfile
        $Changes.profile = $true
    }

    $DerivedProfile = $Next.profile
    if ($PSBoundParameters.ContainsKey("Profile") -or $Changes.Count -gt 0) {
        if ($PSBoundParameters.ContainsKey("Profile") -and -not [string]::IsNullOrWhiteSpace($Profile)) {
            $ProfileDefinition = Get-COOPERProfileDefinition -Profile $Profile -Root $Root
            if ($ProfileDefinition) {
                $MatchesDefinition = $true
                foreach ($Key in @("humor", "sarcasm", "professionalism", "brevity", "initiative", "risk_awareness")) {
                    if ([int]$Next[$Key] -ne (ConvertTo-COOPERPersonalityInt -Value $ProfileDefinition.$Key -Name $Key)) {
                        $MatchesDefinition = $false
                        break
                    }
                }
                if (-not $MatchesDefinition) {
                    $DerivedProfile = "custom"
                }
            }
        }
        elseif ($Changes.Count -gt 0) {
            $DerivedProfile = "custom"
        }
    }
    $Next.profile = $DerivedProfile

    $Normalized = [pscustomobject]$Next
    $TargetPath = if ([string]::IsNullOrWhiteSpace($ProfilePath)) { Get-COOPERPersonalityStorePath -Root $Root } else { $ProfilePath }

    $Result = [pscustomobject]@{
        status = "pass"
        dry_run = [bool]$DryRun
        profile_path = $TargetPath
        previous = $Current.personality
        current = $Current.personality
        next = $Normalized
        changed_fields = @($Changes.Keys)
        profile_definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
        message = ""
    }

    if ($DryRun) {
        $Result.message = "Dry run: personality would be updated."
        $Result.next = $Normalized
        if ($AsJson) {
            $Result | ConvertTo-Json -Depth 20
            return
        }
        Write-Host "[OK] COOPER personality"
        Write-Host ("Message : {0}" -f $Result.message)
        Write-Host ("Profile : {0}" -f $Normalized.profile)
        return
    }

    $Saved = Save-COOPERPersonality -Personality $Normalized -Path $TargetPath -Root $Root -SyncLegacyMirror
    $Result.current = $Saved
    $Result.next = $Saved
    $Result.message = "Personality updated."
    $Result.changed_fields = @($Changes.Keys)

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] COOPER personality"
    Write-Host ("Profile : {0}" -f $Saved.profile)
    Write-Host ("Humor   : {0}" -f $Saved.humor)
    Write-Host ("Sarcasm : {0}" -f $Saved.sarcasm)
    Write-Host ("Pro     : {0}" -f $Saved.professionalism)
    Write-Host ("Brevity : {0}" -f $Saved.brevity)
    Write-Host ("Init    : {0}" -f $Saved.initiative)
    Write-Host ("Risk    : {0}" -f $Saved.risk_awareness)
}
catch {
    if ($AsJson) {
        [pscustomobject]@{
            status = "fail"
            message = $_.Exception.Message
            profile_path = if ([string]::IsNullOrWhiteSpace($ProfilePath)) { Get-COOPERPersonalityStorePath -Root $Root } else { $ProfilePath }
        } | ConvertTo-Json -Depth 20
        if (-not $NoThrow) {
            throw "COOPER personality update failed."
        }
        return
    }

    Write-Host "[ERR] COOPER personality"
    Write-Host ("Message : {0}" -f $_.Exception.Message)
    if (-not $NoThrow) {
        throw "COOPER personality update failed."
    }
}
