$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$TempDir = Join-Path $Root "PDA-Tasks\temp\approval-tests"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

function New-TestTask {
    param(
        [string]$Name,
        [string]$Command,
        [string]$Category,
        [string]$RoutingSurface,
        [string]$Message
    )

    $Path = Join-Path $TempDir "$Name.json"

    $Task = @{
        task_id = [guid]::NewGuid().ToString()
        command = $Command
        assigned_worker = ($Command.TrimStart("/") + "-worker")
        category = $Category
        routing_surface = $RoutingSurface
        message = $Message
        status = "test"
        created_at = (Get-Date).ToString("s")
    }

    $Task | ConvertTo-Json -Depth 8 | Set-Content $Path -Encoding UTF8
    return $Path
}

Write-Host "[*] Testing approval policy..."

$Planner = New-TestTask -Name "allow-planner" -Command "/planner" -Category "category_1" -RoutingSurface "local-only" -Message "Planner test"
$Execute = New-TestTask -Name "approval-execute" -Command "/execute" -Category "category_1" -RoutingSurface "local-only" -Message "Execute approval test"
$Category2 = New-TestTask -Name "approval-category2" -Command "/review" -Category "category_2" -RoutingSurface "local-only" -Message "Category 2 approval test"
$CloudBlock = New-TestTask -Name "block-category2-cloud" -Command "/review" -Category "category_2" -RoutingSurface "cloud-api" -Message "Category 2 cloud route test"
$SecretBlock = New-TestTask -Name "block-secret" -Command "/planner" -Category "category_1" -RoutingSurface "local-only" -Message "api_key=TEST_SHOULD_BLOCK"

$Tests = @(
    @{ path = $Planner; expected = 0; name = "planner allow" },
    @{ path = $Execute; expected = 3; name = "execute approval required" },
    @{ path = $Category2; expected = 3; name = "category2 approval required" },
    @{ path = $CloudBlock; expected = 2; name = "category2 cloud blocked" },
    @{ path = $SecretBlock; expected = 2; name = "secret blocked" }
)

foreach ($t in $Tests) {
    Write-Host "[TEST] $($t.name)"
    pwsh -NoProfile -File (Join-Path $PSScriptRoot "Invoke-PDAApprovalGate.ps1") -TaskPath $t.path
    $code = $LASTEXITCODE

    if ($code -ne $t.expected) {
        throw "Approval test failed: $($t.name). Expected exit $($t.expected), got $code"
    }
}

pwsh -NoProfile -File (Join-Path $PSScriptRoot "Get-PDAApprovalStatus.ps1")

Write-Host "[OK] Approval policy tests passed."
