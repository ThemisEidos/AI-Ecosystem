$ErrorActionPreference = "Stop"

function Test-COOPERResearchAllowedUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    try {
        $Uri = [uri]$Url
    }
    catch {
        return $false
    }

    $HostName = [string]$Uri.Host.ToLowerInvariant()
    $Path = [string]$Uri.AbsolutePath.ToLowerInvariant()

    if ($HostName -in @("support.system76.com", "system76.com")) {
        return $true
    }

    if ($HostName -eq "github.com" -and ($Path.StartsWith("/pop-os/") -or $Path.StartsWith("/system76/"))) {
        return $true
    }

    return $false
}

function Get-COOPERResearchCatalog {
    param([Parameter(Mandatory = $true)][string]$IndexPath)

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        return @()
    }

    $Entries = New-Object System.Collections.Generic.List[object]
    $Current = $null
    foreach ($Line in Get-Content -LiteralPath $IndexPath) {
        $Trimmed = [string]$Line.Trim()
        if ([string]::IsNullOrWhiteSpace($Trimmed)) {
            continue
        }

        if ($Trimmed.StartsWith("### ")) {
            if ($null -ne $Current -and $Current.url) {
                $Entries.Add([pscustomobject]$Current)
            }
            $Current = [ordered]@{
                title = [string]$Trimmed.Substring(4).Trim()
                url = ""
                category = ""
                purpose = ""
            }
            continue
        }

        if ($null -eq $Current) {
            continue
        }

        if ($Trimmed -match '^- URL:\s*(?<Value>.+)$') {
            $Current.url = [string]$Matches.Value.Trim()
            continue
        }

        if ($Trimmed -match '^- Category:\s*(?<Value>.+)$') {
            $Current.category = [string]$Matches.Value.Trim()
            continue
        }

        if ($Trimmed -match '^- Purpose:\s*(?<Value>.+)$') {
            $Current.purpose = [string]$Matches.Value.Trim()
            continue
        }
    }

    if ($null -ne $Current -and $Current.url) {
        $Entries.Add([pscustomobject]$Current)
    }

    return @($Entries | Where-Object { Test-COOPERResearchAllowedUrl -Url $_.url })
}

function Get-COOPERResearchCategoryHints {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Normalized = [string]$Text.ToLowerInvariant()
    $Hints = New-Object System.Collections.Generic.List[string]

    if ($Normalized -match '(?i)\b(install|setup|download|installing|installation)\b') {
        $Hints.Add("Installation")
    }
    if ($Normalized -match '(?i)\b(basic|desktop|launcher|dock|panel|workspace|cosmic|settings)\b') {
        $Hints.Add("System Basics")
    }
    if ($Normalized -match '(?i)\b(app|application|repository|repos?|flatpak|software)\b') {
        $Hints.Add("Package Management")
    }
    if ($Normalized -match '(?i)\b(update|upgrade|firmware|release)\b') {
        $Hints.Add("System Updates")
    }
    if ($Normalized -match '(?i)\b(recovery|repair|boot|chroot|login|drive|disk|filesystem)\b') {
        $Hints.Add("Recovery & Repair")
    }
    if ($Normalized -match '(?i)\b(shortcut|keyboard|keys)\b') {
        $Hints.Add("Keyboard Shortcuts")
    }
    if ($Normalized -match '(?i)\b(troubleshoot|troubleshooting|network|wireless|audio|failure)\b') {
        $Hints.Add("Troubleshooting")
    }
    if ($Normalized -match '(?i)\b(driver|hardware|virtualization|development|docker|container|containers|host administration)\b') {
        $Hints.Add("Advanced Administration")
    }

    if ($Hints.Count -eq 0) {
        $Hints.Add("System Basics")
        $Hints.Add("Installation")
        $Hints.Add("Package Management")
        $Hints.Add("System Updates")
        $Hints.Add("Recovery & Repair")
    }

    return @($Hints | Select-Object -Unique)
}

function Get-COOPERResearchPageSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $RetrievedAt = (Get-Date).ToUniversalTime().ToString("o")
    $Result = [ordered]@{
        title = ""
        url = $Url
        retrieved_at = $RetrievedAt
        source_domain = ""
        excerpt = ""
    }

    try {
        $Uri = [uri]$Url
        $Result.source_domain = [string]$Uri.Host.ToLowerInvariant()
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 5
        $Html = [string]$Response.Content
        if ([string]::IsNullOrWhiteSpace($Html)) {
            return $null
        }

        $TitleMatch = [regex]::Match($Html, '<title>(?<Value>.*?)</title>', 'Singleline')
        if ($TitleMatch.Success) {
            $Result.title = [string]($TitleMatch.Groups['Value'].Value -replace '\s+', ' ').Trim()
        }

        if ([string]::IsNullOrWhiteSpace([string]$Result.title)) {
            $MetaMatch = [regex]::Match($Html, '<meta\s+property="og:title"\s+content="(?<Value>[^"]+)"', 'IgnoreCase')
            if ($MetaMatch.Success) {
                $Result.title = [string]$MetaMatch.Groups['Value'].Value.Trim()
            }
        }

        $Text = $Html -replace '<script[\s\S]*?</script>', ' '
        $Text = $Text -replace '<style[\s\S]*?</style>', ' '
        $Text = $Text -replace '<[^>]+>', ' '
        $Text = [regex]::Replace($Text, '\s+', ' ').Trim()
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            $Result.excerpt = if ($Text.Length -gt 280) { $Text.Substring(0, 280).Trim() } else { $Text }
        }

        if ([string]::IsNullOrWhiteSpace([string]$Result.excerpt)) {
            $MetaDesc = [regex]::Match($Html, '<meta\s+name="description"\s+content="(?<Value>[^"]+)"', 'IgnoreCase')
            if ($MetaDesc.Success) {
                $Result.excerpt = [string]$MetaDesc.Groups['Value'].Value.Trim()
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$Result.title)) {
            $Result.title = $Url
        }

        return [pscustomobject]$Result
    }
    catch {
        return $null
    }
}

function Get-COOPERResearchSources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestText,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [int]$MaxSources = 5
    )

    $IndexPath = Join-Path $Root "Docs\Linux_Infrastructure_PopOS_Source_Index.md"
    $Catalog = @(Get-COOPERResearchCatalog -IndexPath $IndexPath)
    if ($Catalog.Count -eq 0) {
        return [pscustomobject]@{
            status = "fail"
            reason = "no_sources_collected"
            retrieved_at = (Get-Date).ToUniversalTime().ToString("o")
            source_count = 0
            sources = @()
            source_catalog_path = $IndexPath
            source_of_truth = "Scripts/Get-COOPERResearchSources.ps1"
        }
    }

    if ($RequestText -notmatch '(?i)\b(pop!?_?os|system76|linux|docker|host administration|virtualization|systemd|kvm|qemu)\b') {
        return [pscustomobject]@{
            status = "fail"
            reason = "no_sources_collected"
            retrieved_at = (Get-Date).ToUniversalTime().ToString("o")
            source_count = 0
            sources = @()
            source_catalog_path = $IndexPath
            source_of_truth = "Scripts/Get-COOPERResearchSources.ps1"
        }
    }

    $CategoryHints = Get-COOPERResearchCategoryHints -Text $RequestText
    $SelectedCatalog = @()
    $SelectedUrls = @()
    foreach ($Hint in $CategoryHints) {
        foreach ($Entry in @($Catalog | Where-Object { [string]$_.category -eq $Hint })) {
            if (@($SelectedCatalog).Count -ge $MaxSources) {
                break
            }
            if ($SelectedUrls -notcontains [string]$Entry.url) {
                $SelectedCatalog += $Entry
                $SelectedUrls += [string]$Entry.url
            }
        }
        if (@($SelectedCatalog).Count -ge $MaxSources) {
            break
        }
    }

    if (@($SelectedCatalog).Count -eq 0) {
        foreach ($Entry in $Catalog) {
            if (@($SelectedCatalog).Count -ge $MaxSources) {
                break
            }
            if ($SelectedUrls -notcontains [string]$Entry.url) {
                $SelectedCatalog += $Entry
                $SelectedUrls += [string]$Entry.url
            }
        }
    }

    $Sources = @()
    foreach ($Entry in $SelectedCatalog) {
        $Page = Get-COOPERResearchPageSummary -Url $Entry.url
        if ($null -eq $Page) {
            continue
        }

        $Page | Add-Member -NotePropertyName category -NotePropertyValue $Entry.category -Force
        $Page | Add-Member -NotePropertyName purpose -NotePropertyValue $Entry.purpose -Force
        $Sources += $Page
    }

    if (@($Sources).Count -eq 0) {
        return [pscustomobject]@{
            status = "fail"
            reason = "no_sources_collected"
            retrieved_at = (Get-Date).ToUniversalTime().ToString("o")
            source_count = 0
            sources = @()
            source_catalog_path = $IndexPath
            source_of_truth = "Scripts/Get-COOPERResearchSources.ps1"
        }
    }

    $RetrievedAt = (Get-Date).ToUniversalTime().ToString("o")

    return [pscustomobject]@{
        status = "pass"
        reason = ""
        retrieved_at = $RetrievedAt
        source_count = @($Sources).Count
        sources = @($Sources | ForEach-Object { $_ })
        source_catalog_path = $IndexPath
        source_of_truth = "Scripts/Get-COOPERResearchSources.ps1"
    }
}
