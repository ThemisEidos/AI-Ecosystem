Write-Host "=== PDA COMMAND ROUTER TEST ==="

$Commands = @(
    @{ Command="/status"; Message="Health check" },
    @{ Command="/planner"; Message="Planner route test" },
    @{ Command="/reporter"; Message="Reporter route test" },
    @{ Command="/timeline"; Message="Timeline route test" },
    @{ Command="/research"; Message="Research route test" },
    @{ Command="/review"; Message="Review route test" },
    @{ Command="/execute"; Message="Execute route test" }
)

foreach ($Item in $Commands) {
    Write-Host ""
    Write-Host "Testing $($Item.Command)..."
    pwsh "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Send-PDACommand.ps1" -Command $Item.Command -Message $Item.Message
}
