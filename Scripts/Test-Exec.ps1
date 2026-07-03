[CmdletBinding()]
param()
Write-Output "COOPER Workbench execution check -- OK"
Write-Output ("Timestamp : " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Output ("Host      : " + $env:COMPUTERNAME)
exit 0
