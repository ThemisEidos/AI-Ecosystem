[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "pda-n8n",

    [Parameter(Mandatory = $false)]
    [int]$Port = 8788,

    [Parameter(Mandatory = $false)]
    [string]$Path = "/pda-chat-bridge/",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is required for the reachability test."
}

$NodeScript = @"
const dns = require("dns").promises;
const http = require("http");

const targets = [
  "host.docker.internal",
  "gateway.docker.internal",
  "172.17.0.1",
  "172.20.10.12",
  "192.168.56.1",
  "10.2.0.2",
  "172.28.192.1"
];
const port = $Port;
const path = "/pda-chat-bridge/";
const message = "review my latest findings for container reachability";

async function probe(host) {
  const result = {
    host,
    dns_addresses: [],
    dns_error: null,
    http_status: null,
    http_error: null,
    response_json_ok: false,
    response_preview: "",
    duration_ms: null
  };

  try {
    const addresses = await dns.lookup(host, { all: true });
    result.dns_addresses = addresses.map((entry) => entry.address);
  } catch (error) {
    result.dns_error = error.message;
  }

  const body = JSON.stringify({ user_message: message, confirm_dispatch: false });
  const start = Date.now();

  await new Promise((resolve) => {
    const req = http.request(
      {
        host,
        port,
        path,
        method: "POST",
        headers: {
          "content-type": "application/json",
          "content-length": Buffer.byteLength(body)
        }
      },
      (res) => {
        let text = "";
        result.http_status = res.statusCode;
        res.on("data", (chunk) => {
          text += chunk;
        });
        res.on("end", () => {
          result.duration_ms = Date.now() - start;
          result.response_preview = text.slice(0, 200);
          try {
            JSON.parse(text);
            result.response_json_ok = true;
          } catch (error) {
            result.response_json_ok = false;
          }
          resolve();
        });
      }
    );

    req.on("error", (error) => {
      result.http_error = error.message;
      result.duration_ms = Date.now() - start;
      resolve();
    });

    const timeoutMs = (host === "host.docker.internal" || host === "gateway.docker.internal") ? 15000 : 3000;
    req.setTimeout(timeoutMs, () => {
      result.http_error = "timeout";
      req.destroy(new Error("timeout"));
    });

    req.end(body);
  });

  return result;
}

(async () => {
  const results = [];
  for (const host of targets) {
    results.push(await probe(host));
  }
  console.log(JSON.stringify({ container: "pda-n8n", port, path, results }, null, 2));
})().catch((error) => {
  console.log(JSON.stringify({ status: "fail", error: error.message }, null, 2));
  process.exit(1);
});
"@

try {
    $Raw = & docker exec -e "PDA_REACHABILITY_CONTAINER=$ContainerName" $ContainerName node -e $NodeScript 2>&1
}
catch {
    throw "Reachability probe failed to execute in container '$ContainerName': $($_.Exception.Message)"
}

if ($LASTEXITCODE -ne 0) {
    throw "Reachability probe failed in container '$ContainerName' with exit code $LASTEXITCODE."
}

$JsonText = [string]($Raw -join "`n").Trim()
if ([string]::IsNullOrWhiteSpace($JsonText)) {
    throw "Reachability probe returned no output."
}

$Parsed = $JsonText | ConvertFrom-Json

function Find-PDAReachabilityResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    return @($Parsed.results | Where-Object { $_.host -eq $HostName })[0]
}

$HostTarget = Find-PDAReachabilityResult 'host.docker.internal'
$GatewayTarget = Find-PDAReachabilityResult 'gateway.docker.internal'
$BridgeTarget = Find-PDAReachabilityResult '172.17.0.1'
$LanTargets = @(
    Find-PDAReachabilityResult '172.20.10.12'
    Find-PDAReachabilityResult '192.168.56.1'
    Find-PDAReachabilityResult '10.2.0.2'
    Find-PDAReachabilityResult '172.28.192.1'
)

$WorkingTarget = $HostTarget
if (-not ($WorkingTarget.http_status -eq 200 -and $WorkingTarget.response_json_ok)) {
    $WorkingTarget = @($LanTargets | Where-Object { $_.http_status -eq 200 -and $_.response_json_ok })[0]
}

$WorkingLanTarget = @($LanTargets | Where-Object { $_.http_status -eq 200 -and $_.response_json_ok })[0]

$Issues = New-Object System.Collections.Generic.List[string]

if (-not ($WorkingTarget -or $WorkingLanTarget)) {
    $Issues.Add("None of the host or LAN IP targets returned a valid JSON response from the local PDA server.")
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    container = $ContainerName
    endpoint = "http://localhost:${Port}${Path}"
    host_docker_internal = $HostTarget
    gateway_docker_internal = $GatewayTarget
    bridge_ip = $BridgeTarget
    lan_targets = @($LanTargets)
    working_target = $WorkingTarget
    working_lan_target = $WorkingLanTarget
    issues = @($Issues)
    run_instruction = if ($WorkingTarget) {
        "Start the PDA webhook server, then run the n8n HTTP workflow against http://$($WorkingTarget.host):${Port}${Path}"
    }
    else {
        "Start the PDA webhook server, then run the n8n HTTP workflow against the first reachable host or LAN IP on port ${Port}."
    }
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA webhook server reachability validation failed."
    }
    return
}

Write-Host "[*] PDA webhook server reachability"
Write-Host ("Container              : {0}" -f $Report.container)
Write-Host ("Endpoint               : {0}" -f $Report.endpoint)
Write-Host ("host.docker.internal    : DNS={0} HTTP={1} JSON={2}" -f (@($HostTarget.dns_addresses) -join ', '), $HostTarget.http_status, $HostTarget.response_json_ok)
Write-Host ("gateway.docker.internal : DNS={0} HTTP={1} JSON={2}" -f (@($GatewayTarget.dns_addresses) -join ', '), $GatewayTarget.http_status, $GatewayTarget.response_json_ok)
Write-Host ("172.17.0.1              : DNS={0} HTTP={1} JSON={2}" -f (@($BridgeTarget.dns_addresses) -join ', '), $BridgeTarget.http_status, $BridgeTarget.response_json_ok)
foreach ($LanTarget in $LanTargets) {
    Write-Host ("{0} : DNS={1} HTTP={2} JSON={3}" -f $LanTarget.host, (@($LanTarget.dns_addresses) -join ', '), $LanTarget.http_status, $LanTarget.response_json_ok)
}
if ($WorkingTarget) {
    Write-Host ("Working target          : {0}:{1}" -f $WorkingTarget.host, $Port)
}
if ($WorkingLanTarget -and ($WorkingTarget.host -ne $WorkingLanTarget.host)) {
    Write-Host ("Working LAN target      : {0}:{1}" -f $WorkingLanTarget.host, $Port)
}
Write-Host ("Status                  : {0}" -f $Report.status)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA webhook server reachability validation failed."
}
