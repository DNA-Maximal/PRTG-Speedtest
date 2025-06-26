<#
.SYNOPSIS
  Runs Speedtest CLI with a specific source IP and outputs PRTG-compatible XML for multi-channel monitoring.

.DESCRIPTION
  - Accepts interface IP as parameter (-i or --ipaddress or as first argument).
  - Supports optional detailed result mode.
  - Handles errors robustly and always returns valid PRTG XML.
  - Converts speedtest bandwidth to bits per second and outputs additional stats if requested.
  - Follows PRTG best practices for channel units and float handling.

.PARAMETER i
  Source IP/Interface to use for speedtest.

.PARAMETER ipaddress
  Alternative parameter for source IP.

.PARAMETER d
  Switch for detailed output.

.PARAMETER detailed
  Alternative switch for detailed output.

.EXAMPLE
  .\speedtest.ps1 -i 192.168.1.5 -detailed
#>

param(
  [string]$i,
  [string]$ipaddress,
  [switch]$d,
  [switch]$detailed
)

# Parse source IP/interface argument
if ($i -ne $null) {
    $SourceIP = $i
} elseif ($ipaddress -ne $null) {
    $SourceIP = $ipaddress
} elseif ($args.Count -gt 0) {
    $SourceIP = $args[0]
} else {
    $SourceIP = $null
}

# Determine if detailed output is requested
$DetailedOutput = $d -or $detailed

# Validate $SourceIP before proceeding
if ($SourceIP -and -not [System.Net.IPAddress]::TryParse($SourceIP, [ref]$null)) {
    Write-Output @"
<prtg>
  <error>1</error>
  <text>Invalid source IP address specified: '${SourceIP}'. Please provide a valid IPv4 or IPv6 address.</text>
</prtg>
"@
    exit 1
}

# Locate speedtest.exe in the script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$speedtestPath = Join-Path $scriptDir "speedtest.exe"

# Retry logic for Speedtest execution
$retryDelay = 10 # Initial delay in seconds
$maxRetries = 3
$retryCount = 0
$success = $false
$data = $null

while ($retryCount -lt $maxRetries -and -not $success) {
  try {
    # Dynamically include the -i argument only if $SourceIP is set
    $result = if ($SourceIP) {
      & "$speedtestPath" -i "$SourceIP" -f json 2>$null
    } else {
      & "$speedtestPath" -f json 2>$null
    }
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 429) {
      Write-Host "Rate limit hit. Retrying in $retryDelay seconds..."
      Start-Sleep -Seconds $retryDelay
      $retryCount++
      $retryDelay *= 2 # Double the delay for the next retry
    } elseif ($exitCode -ne 0 -or -not $result) {
      throw "Speedtest exited with code ${exitCode}. Output: $result"
    } else {
      $success = $true
      $data = $result | ConvertFrom-Json -ErrorAction Stop
    }
  } catch {
    if ($retryCount -ge $maxRetries) {
      Write-Output @"
<prtg>
  <error>1</error>
  <text>Speedtest failed after $maxRetries retries: $_</text>
</prtg>
"@
      exit 1
    }
  }
}

if (-not $data) {
  Write-Output @"
<prtg>
  <error>1</error>
  <text>Speedtest failed: Unable to retrieve valid data.</text>
</prtg>
"@
  exit 1
}

# Validate $data
if (-not $data -or -not $data.download -or -not $data.upload -or -not $data.ping) {
    Write-Output @"
<prtg>
  <error>1</error>
  <text>Speedtest failed: Invalid or incomplete data received.</text>
</prtg>
"@
    exit 1
}

# Escape special characters in text
function Escape-Xml {
    param ([string]$InputString)
    return $InputString -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
}

# Extract metrics
$downloadBits = if ($data.download.bandwidth -ne $null) {
    [math]::Round(($data.download.bandwidth * 8) -as [double], 0)
} else {
    0
}

$uploadBits = if ($data.upload.bandwidth -ne $null) {
    [math]::Round(($data.upload.bandwidth * 8) -as [double], 0)
} else {
    0
}

$pingMs = if ($data.ping.latency -ne $null) {
    [math]::Round($data.ping.latency, 2)
} else {
    0
}

# Compose summary <text> for PRTG
$text = if ($SourceIP) {
    Escape-Xml "Speedtest via ${SourceIP} on $($data.server.host)"
} else {
    Escape-Xml "Speedtest via Default Interface on $($data.server.host)"
}

$extraText = @()
if ($data.isp) { $extraText += "ISP: $($data.isp)" }
if ($data.interface.externalIp) { $extraText += "ExternalIP: $($data.interface.externalIp)" }
if ($data.server.ip) { $extraText += "ServerIP: $($data.server.ip)" }
if ($data.server.location -or $data.server.country) { $extraText += "ServerLocation: $($data.server.location), $($data.server.country)" }
if ($extraText.Count -gt 0) { $text += " | " + ($extraText -join " | ") }

# Output XML
$prtgResults = @"
<prtg>
  <result>
    <channel>Download Speed</channel>
    <value>$downloadBits</value>
    <unit>SpeedNet</unit>
    <SpeedSize>MegaBit</SpeedSize>
  </result>
  <result>
    <channel>Upload Speed</channel>
    <value>$uploadBits</value>
    <unit>SpeedNet</unit>
    <SpeedSize>MegaBit</SpeedSize>
  </result>
  <result>
    <channel>Ping</channel>
    <value>$pingMs</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
  <text>$text</text>
</prtg>
"@

Write-Output $prtgResults
