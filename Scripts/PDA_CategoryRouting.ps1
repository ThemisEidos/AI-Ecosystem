function Get-PDAWorkerRegistry {
    param(
        [string]$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
    )

    $RegistryPath = Join-Path $Root "Scripts\PDA_WorkerRegistry.json"
    return Get-Content $RegistryPath -Raw | ConvertFrom-Json
}

function Get-PDAWorkerRegistryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Registry,

        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    return @($Registry.workers | Where-Object { $_.command -eq $Command } | Select-Object -First 1)[0]
}

function Resolve-PDACategoryRouting {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $true)]
        [object]$Worker
    )

    $Category = if ($Task.classification) { [string]$Task.classification } else { "category_1" }
    $RoutingSurface = if ($Worker.routing_surface) { [string]$Worker.routing_surface } else { "local-only" }
    $CloudCapable = if ($Worker.PSObject.Properties.Name -contains 'cloud_capable') { [bool]$Worker.cloud_capable } else { $false }
    $CategorySupport = if ($Worker.category_support) { @($Worker.category_support) } else { @("category_1", "category_2") }

    if ($Category -eq "category_2") {
        if ($RoutingSurface -ne "local-only" -or $CloudCapable) {
            return [ordered]@{
                allowed         = $false
                routing_profile = "restricted_local"
                routing_surface = $RoutingSurface
                routing_mode    = "fail-closed"
                reason          = "Category 2 requires local-only routing."
                safe_failure    = $true
                worker_name     = $Worker.worker_name
                command         = $Worker.command
                category        = $Category
            }
        }

        if (-not ($CategorySupport -contains "category_2")) {
            return [ordered]@{
                allowed         = $false
                routing_profile = "restricted_local"
                routing_surface = $RoutingSurface
                routing_mode    = "fail-closed"
                reason          = "Worker does not advertise category_2 support."
                safe_failure    = $true
                worker_name     = $Worker.worker_name
                command         = $Worker.command
                category        = $Category
            }
        }
    }

    return [ordered]@{
        allowed         = $true
        routing_profile = if ($Category -eq "category_2") { "restricted_local" } else { "standard" }
        routing_surface = $RoutingSurface
        routing_mode    = if ($RoutingSurface -eq "local-only") { "local" } else { "cloud-capable" }
        reason          = "Routing allowed."
        safe_failure    = $false
        worker_name     = $Worker.worker_name
        command         = $Worker.command
        category        = $Category
    }
}
