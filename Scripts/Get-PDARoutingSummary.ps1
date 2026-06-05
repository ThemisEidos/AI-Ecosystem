[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ResolvedLogPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
    Join-Path $Root "PDA-Logs\routing"
}
else {
    $LogPath
}

function Get-PDACountTable {
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ValueSelector
    )

    $Counts = @{}
    if ($null -eq $Records -or $Records.Count -eq 0) {
        return @()
    }

    foreach ($Record in $Records) {
        $Value = & $ValueSelector $Record
        if ([string]::IsNullOrWhiteSpace([string]$Value)) {
            $Value = "(empty)"
        }

        if (-not $Counts.ContainsKey([string]$Value)) {
            $Counts[[string]$Value] = 0
        }

        $Counts[[string]$Value]++
    }

    return @($Counts.GetEnumerator() | Sort-Object @{ Expression = "Value"; Descending = $true }, @{ Expression = "Key"; Descending = $false } | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.Key
            count = [int]$_.Value
        }
    })
}

function Get-PDARoutingUsageType {
    param([Parameter(Mandatory = $true)]$Record)

    $RoutingSurface = [string]$Record.routing_surface
    if ($RoutingSurface -eq "local-only") {
        return "local"
    }
    if ($RoutingSurface -eq "cloud-capable") {
        return "cloud"
    }

    if ([string]$Record.selected_model -eq "local-llama") {
        return "local"
    }

    return "cloud"
}

function Read-PDARoutingRecords {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    $Loaded = @()
    $Invalid = @()

    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
        return [pscustomobject]@{
            loaded = @()
            invalid = @()
            file_count = 0
        }
    }

    $Files = @(Get-ChildItem -LiteralPath $DirectoryPath -Filter *.json -File | Sort-Object Name)
    foreach ($File in $Files) {
        try {
            $Raw = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($Raw)) {
                throw "File is empty."
            }

            $Parsed = $Raw | ConvertFrom-Json -ErrorAction Stop
            $Loaded += [pscustomobject]@{
                file_name = $File.Name
                file_path = $File.FullName
                command = [string]$Parsed.command
                category = [string]$Parsed.category
                selected_model = [string]$Parsed.selected_model
                transport_model = [string]$Parsed.transport_model
                fallback_chain = @($Parsed.fallback_chain | ForEach-Object { [string]$_ })
                fallback_used = [bool]$Parsed.fallback_used
                fallback_used_known = ($Parsed.PSObject.Properties.Name -contains "fallback_used")
                routing_reason = [string]$Parsed.routing_reason
                routing_surface = [string]$Parsed.routing_surface
                cloud_allowed = if ($Parsed.PSObject.Properties.Name -contains "cloud_allowed") { [bool]$Parsed.cloud_allowed } else { $null }
                worker = [string]$Parsed.worker
                timestamp = [string]$Parsed.timestamp
                outcome = [string]$Parsed.outcome
            }
        }
        catch {
            $Invalid += [pscustomobject]@{
                file_name = $File.Name
                file_path = $File.FullName
                error = $_.Exception.Message
            }
        }
    }

    return [pscustomobject]@{
        loaded = @($Loaded)
        invalid = @($Invalid)
        file_count = $Files.Count
    }
}

$RecordSet = Read-PDARoutingRecords -DirectoryPath $ResolvedLogPath
$Records = @($RecordSet.loaded)
$ValidCount = $Records.Count
$SuccessCount = @($Records | Where-Object { [string]$_.outcome -eq "pass" }).Count
$FailureCount = @($Records | Where-Object { [string]$_.outcome -ne "pass" }).Count
$FallbackKnownRecords = @($Records | Where-Object { $_.fallback_used_known }).Count
$FallbackUsedCount = @($Records | Where-Object { $_.fallback_used_known -and $_.fallback_used }).Count
$CloudCount = @($Records | Where-Object { (Get-PDARoutingUsageType -Record $_) -eq "cloud" }).Count
$LocalCount = @($Records | Where-Object { (Get-PDARoutingUsageType -Record $_) -eq "local" }).Count
$Category1Count = @($Records | Where-Object { [string]$_.category -eq "category_1" }).Count
$Category2Count = @($Records | Where-Object { [string]$_.category -in @("category_2", "restricted_local") }).Count

$Summary = [pscustomobject]@{
    status = "pass"
    log_path = $ResolvedLogPath
    total_files = [int]$RecordSet.file_count
    valid_records = [int]$ValidCount
    invalid_records = [int]$RecordSet.invalid.Count
    success_count = [int]$SuccessCount
    failure_count = [int]$FailureCount
    success_rate = if ($ValidCount -gt 0) { [math]::Round(($SuccessCount / $ValidCount) * 100, 2) } else { 0.0 }
    failure_rate = if ($ValidCount -gt 0) { [math]::Round(($FailureCount / $ValidCount) * 100, 2) } else { 0.0 }
    fallback_usage_count = [int]$FallbackUsedCount
    fallback_usage_known_records = [int]$FallbackKnownRecords
    category_1_volume = [int]$Category1Count
    category_2_volume = [int]$Category2Count
    cloud_usage_count = [int]$CloudCount
    local_usage_count = [int]$LocalCount
    dispatches_by_command = @(Get-PDACountTable -Records $Records -ValueSelector { param($Record) $Record.command })
    dispatches_by_model = @(Get-PDACountTable -Records $Records -ValueSelector { param($Record) $Record.selected_model })
    dispatches_by_worker = @(Get-PDACountTable -Records $Records -ValueSelector { param($Record) $Record.worker })
    top_routing_reasons = @(Get-PDACountTable -Records $Records -ValueSelector { param($Record) $Record.routing_reason } | Select-Object -First 10)
    invalid_files = @($RecordSet.invalid)
}

if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
    $ExportDirectory = Split-Path -Parent $ExportPath
    if (-not [string]::IsNullOrWhiteSpace($ExportDirectory) -and -not (Test-Path -LiteralPath $ExportDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $ExportDirectory -Force | Out-Null
    }

    $Summary | ConvertTo-Json -Depth 20 | Set-Content -Path $ExportPath -Encoding UTF8
}

if ($AsJson) {
    $Summary | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Summary.status -ne "pass") {
        throw "PDA routing summary failed."
    }
    return
}

Write-Host "[PDA ROUTING SUMMARY]"
Write-Host ("Log path                : {0}" -f $Summary.log_path)
Write-Host ("Total files             : {0}" -f $Summary.total_files)
Write-Host ("Valid records           : {0}" -f $Summary.valid_records)
Write-Host ("Invalid records         : {0}" -f $Summary.invalid_records)
Write-Host ("Success / failure       : {0} / {1}" -f $Summary.success_count, $Summary.failure_count)
Write-Host ("Success rate            : {0}%" -f $Summary.success_rate)
Write-Host ("Failure rate            : {0}%" -f $Summary.failure_rate)
Write-Host ("Fallback used           : {0}" -f $Summary.fallback_usage_count)
Write-Host ("Fallback-known records  : {0}" -f $Summary.fallback_usage_known_records)
Write-Host ("Category 1 volume       : {0}" -f $Summary.category_1_volume)
Write-Host ("Category 2 volume       : {0}" -f $Summary.category_2_volume)
Write-Host ("Cloud / local usage     : {0} / {1}" -f $Summary.cloud_usage_count, $Summary.local_usage_count)

function Write-PDACountSection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [object[]]$Items
    )

    Write-Host ""
    Write-Host $Title
    if ($null -eq $Items -or $Items.Count -eq 0) {
        Write-Host "  (none)"
        return
    }

    foreach ($Item in $Items) {
        Write-Host ("  {0} : {1}" -f $Item.name, $Item.count)
    }
}

Write-PDACountSection -Title "Dispatches By Command" -Items $Summary.dispatches_by_command
Write-PDACountSection -Title "Dispatches By Model" -Items $Summary.dispatches_by_model
Write-PDACountSection -Title "Dispatches By Worker" -Items $Summary.dispatches_by_worker
Write-PDACountSection -Title "Top Routing Reasons" -Items $Summary.top_routing_reasons

if ($Summary.invalid_records -gt 0) {
    Write-Host ""
    Write-Host "Invalid Files"
    foreach ($Item in $Summary.invalid_files) {
        Write-Host ("  {0} : {1}" -f $Item.file_name, $Item.error)
    }
}
