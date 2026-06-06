function Assert-ValidRouteSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$RouteSource,

        [Parameter(Mandatory = $false)]
        [ValidateSet("standard", "restricted")]
        [string]$Context = "standard"
    )

    $NormalizedRouteSource = [string]$RouteSource
    $AllowedRouteSources = switch ($Context) {
        "standard" { @("command_route", "worker_route") }
        "restricted" { @("category_override", "sensitivity_override") }
    }

    if ($AllowedRouteSources -notcontains $NormalizedRouteSource) {
        throw "Invalid route_source '$NormalizedRouteSource' for context '$Context'. Allowed values: $($AllowedRouteSources -join ', ')."
    }
}
