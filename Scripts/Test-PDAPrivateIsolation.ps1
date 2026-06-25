[CmdletBinding()]
param(
    [switch]$AsJson,
    [switch]$NoThrow,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if (-not $EvidencePath) {
    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $EvidencePath = Join-Path $Root ("State\Wave1_Runtime_Split\private-isolation-{0}.json" -f $Stamp)
}

$EvidenceDir = Split-Path -Parent $EvidencePath
if (-not (Test-Path -LiteralPath $EvidenceDir -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
}

function Test-ContainerRunning {
    param([Parameter(Mandatory = $true)][string]$ContainerName)
    try {
        $Running = (& docker inspect -f "{{.State.Running}}" $ContainerName 2>$null)
        return (($LASTEXITCODE -eq 0) -and (($Running | Select-Object -First 1) -eq "true"))
    }
    catch {
        return $false
    }
}

function Invoke-ContainerPython {
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][string]$PythonCode
    )

    $Raw = @($PythonCode | docker exec -i $ContainerName python - 2>&1)
    [string]($Raw -join "`n").Trim()
}

function Get-DockerJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $Raw = @(& docker @Arguments 2>$null)
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    return $Text | ConvertFrom-Json
}

$OpenContainers = @("pda-open-webui", "pda-litellm", "pda-n8n")
$PrivateContainers = @("pda-private-open-webui", "pda-private-ollama")
$Issues = New-Object System.Collections.Generic.List[string]

foreach ($ContainerName in $PrivateContainers) {
    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        $Issues.Add("Private container is not running: $ContainerName")
    }
}

$OpenInspect = @()
foreach ($ContainerName in $OpenContainers) {
    $Json = Get-DockerJson -Arguments @("inspect", $ContainerName)
    if ($Json) {
        $OpenInspect += $Json
    }
}

$PrivateInspect = @()
foreach ($ContainerName in $PrivateContainers) {
    $Json = Get-DockerJson -Arguments @("inspect", $ContainerName)
    if ($Json) {
        $PrivateInspect += $Json
    }
}

$OpenNetworks = @($OpenInspect | ForEach-Object { $_.NetworkSettings.Networks.PSObject.Properties.Name } | Select-Object -Unique)
$PrivateNetworks = @($PrivateInspect | ForEach-Object { $_.NetworkSettings.Networks.PSObject.Properties.Name } | Select-Object -Unique)
$SharedNetworks = @($OpenNetworks | Where-Object { $PrivateNetworks -contains $_ } | Select-Object -Unique)
if ($SharedNetworks.Count -gt 0) {
    $Issues.Add("Open and Private share Docker networks: $($SharedNetworks -join ', ')")
}

$OpenVolumeNames = @(
    $OpenInspect | ForEach-Object {
        @($_.Mounts | Where-Object { $_.Type -eq "volume" } | ForEach-Object { $_.Name })
    } | Select-Object -Unique
)
$PrivateVolumeNames = @(
    $PrivateInspect | ForEach-Object {
        @($_.Mounts | Where-Object { $_.Type -eq "volume" } | ForEach-Object { $_.Name })
    } | Select-Object -Unique
)
$SharedVolumes = @($OpenVolumeNames | Where-Object { $PrivateVolumeNames -contains $_ } | Select-Object -Unique)
if ($SharedVolumes.Count -gt 0) {
    $Issues.Add("Open and Private share Docker volumes: $($SharedVolumes -join ', ')")
}

$NoInternetProbe = @'
import json
import urllib.request

report = {"ok": False, "detail": ""}
try:
    urllib.request.urlopen("https://example.com", timeout=5)
    report["detail"] = "Outbound internet probe unexpectedly succeeded."
except Exception as exc:
    report["ok"] = True
    report["detail"] = str(exc)
print(json.dumps(report))
'@
$NoDnsProbe = @'
import json
import socket

report = {"ok": False, "detail": ""}
try:
    socket.getaddrinfo("example.com", 443)
    report["detail"] = "External DNS resolution unexpectedly succeeded."
except Exception as exc:
    report["ok"] = True
    report["detail"] = str(exc)
print(json.dumps(report))
'@
$NoOpenRouterProbe = @'
import json
import urllib.request

report = {"ok": False, "detail": ""}
try:
    urllib.request.urlopen("https://openrouter.ai/api/v1/models", timeout=5)
    report["detail"] = "OpenRouter probe unexpectedly succeeded."
except Exception as exc:
    report["ok"] = True
    report["detail"] = str(exc)
print(json.dumps(report))
'@
$NoPrivateWebhookProbe = @'
import json
import urllib.request

targets = [
    "http://pda-private-open-webui:8080",
    "http://pda-private-ollama:11434/api/tags",
    "http://host.docker.internal:5679/webhook-test/private",
]
results = []
all_blocked = True
for target in targets:
    item = {"target": target, "blocked": False, "detail": ""}
    try:
        urllib.request.urlopen(target, timeout=4)
        item["detail"] = "Probe unexpectedly succeeded."
        all_blocked = False
    except Exception as exc:
        item["blocked"] = True
        item["detail"] = str(exc)
    results.append(item)
print(json.dumps({"ok": all_blocked, "results": results}))
'@

$InternetResult = $null
$DnsResult = $null
$OpenRouterResult = $null
$CrossStackProbe = $null
$CloudDependencyCheck = $null

if (Test-ContainerRunning -ContainerName "pda-private-open-webui") {
    $InternetResult = Invoke-ContainerPython -ContainerName "pda-private-open-webui" -PythonCode $NoInternetProbe | ConvertFrom-Json
    if (-not $InternetResult.ok) {
        $Issues.Add("Private stack still has outbound internet access.")
    }

    $DnsResult = Invoke-ContainerPython -ContainerName "pda-private-open-webui" -PythonCode $NoDnsProbe | ConvertFrom-Json
    if (-not $DnsResult.ok) {
        $Issues.Add("Private stack can resolve external DNS.")
    }

    $OpenRouterResult = Invoke-ContainerPython -ContainerName "pda-private-open-webui" -PythonCode $NoOpenRouterProbe | ConvertFrom-Json
    if (-not $OpenRouterResult.ok) {
        $Issues.Add("Private stack can reach OpenRouter or another cloud-model endpoint.")
    }

    $Inspect = Get-DockerJson -Arguments @("inspect", "pda-private-open-webui")
    $Env = @($Inspect[0].Config.Env)
    $BadEnv = @($Env | Where-Object {
        $_ -match '^(OPENAI_API_BASE_URL|OPENAI_API_KEY|OPENROUTER_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY)=.+' -and $_ -notmatch '=$'
    })
    $CloudDependencyCheck = [pscustomobject]@{
        ok = ($BadEnv.Count -eq 0)
        disallowed_env = @($BadEnv)
    }
    if (-not $CloudDependencyCheck.ok) {
        $Issues.Add("Private Open WebUI contains cloud provider environment variables.")
    }
}

if (Test-ContainerRunning -ContainerName "pda-private-ollama") {
    $OllamaInspect = Get-DockerJson -Arguments @("inspect", "pda-private-ollama")
    $OllamaEnv = @($OllamaInspect[0].Config.Env)
    $OllamaNoCloud = @($OllamaEnv | Where-Object { $_ -eq "OLLAMA_NO_CLOUD=true" }).Count -gt 0
    if (-not $OllamaNoCloud) {
        $Issues.Add("Private Ollama does not explicitly disable cloud access.")
    }
}

if (Test-ContainerRunning -ContainerName "pda-open-webui") {
    $CrossStackProbe = Invoke-ContainerPython -ContainerName "pda-open-webui" -PythonCode $NoPrivateWebhookProbe | ConvertFrom-Json
    if (-not $CrossStackProbe.ok) {
        $Issues.Add("Open stack can directly reach a Private endpoint.")
    }
}

$WF007Script = Join-Path $PSScriptRoot "Test-COOPERPrivateLocalAnalysisWorkflow.ps1"
$WF007ExitCode = $null
$WF007Output = @()
if (Test-Path -LiteralPath $WF007Script -PathType Leaf) {
    $WF007Output = @(& $WF007Script 2>&1)
    $WF007ExitCode = $LASTEXITCODE
    if ($WF007ExitCode -ne 0) {
        $Issues.Add("WF-007 local-only verification failed.")
    }
}
else {
    $Issues.Add("WF-007 verification script is missing.")
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    evidence_path = $EvidencePath
    open_networks = @($OpenNetworks)
    private_networks = @($PrivateNetworks)
    shared_networks = @($SharedNetworks)
    open_volumes = @($OpenVolumeNames)
    private_volumes = @($PrivateVolumeNames)
    shared_volumes = @($SharedVolumes)
    no_outbound_internet = $InternetResult
    no_external_dns = $DnsResult
    no_openrouter_access = $OpenRouterResult
    no_cloud_env_dependency = $CloudDependencyCheck
    open_to_private_probe = $CrossStackProbe
    wf_007 = [pscustomobject]@{
        exit_code = $WF007ExitCode
        output = @($WF007Output)
    }
    issues = @($Issues)
}

$Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "Private isolation verification failed."
    }
    return
}

Write-Host "=== PRIVATE ISOLATION VERIFICATION ==="
Write-Host ("Status       : {0}" -f $Report.status)
Write-Host ("Evidence     : {0}" -f $EvidencePath)
Write-Host ("Open nets    : {0}" -f ($OpenNetworks -join ", "))
Write-Host ("Private nets : {0}" -f ($PrivateNetworks -join ", "))

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue) -ForegroundColor Red
    }
    if (-not $NoThrow) {
        throw "Private isolation verification failed."
    }
}
else {
    Write-Host "[PASS] Private isolation verified." -ForegroundColor Green
}
