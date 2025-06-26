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
$SourceIP = $i ?? $ipaddress ?? $args[0]

# Determine if detailed output is requested
if ($d -or $detailed) {
  $DetailedOutput = $true
} elseif ($args -contains "-d" -or $args -contains "--detailed") {
if ($SourceIP -and -not [System.Net.IPAddress]::TryParse($SourceIP, [ref]$null)) {
  # Log the invalid IP for debugging purposes
  Write-Host "Debug: Invalid IP address provided - '${SourceIP}'" | Out-File -FilePath "debug.log" -Append

  Write-Output @"
<prtg>
  <error>1</error>
  <text>Invalid source IP address specified: '${SourceIP}'. Please provide a valid IPv4 or IPv6 address.</text>
</prtg>
"@
  exit 1
}
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
$data = $null

# Validate $SourceIP before executing the command
if ($SourceIP -and -not [System.Net.IPAddress]::TryParse($SourceIP, [ref]$null)) {
  Write-Output @"
<prtg>
  <error>1</error>
  <text>Invalid or empty source IP address specified: '${SourceIP}'. Please provide a valid IPv4 or IPv6 address.</text>
</prtg>
"@
  exit 1
}
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
<prtg>
  <error>1</error>
  <text>Speedtest failed: Unable to retrieve valid data.</text>
</prtg>
"@
  exit 1
$text = "Speedtest via $SourceIP on $($data.server.host)"
$extraText = @()
if ($data.isp) { $extraText += "ISP: $($data.isp)" }
if ($data.interface.externalIp) { $extraText += "ExternalIP: $($data.interface.externalIp)" }
if ($data.server.ip) { $extraText += "ServerIP: $($data.server.ip)" }
if ($data.server.location -or $data.server.country) { $extraText += "ServerLocation: $($data.server.location), $($data.server.country)" }
if ($extraText.Count -gt 0) { $text = "$text | $($extraText -join ' | ')" }
# Compose summary <text> for PRTG
$text = "Speedtest via ${SourceIP} on $($data.server.host)"
$extraText = @()
if ($data.isp) { $extraText += "ISP: $($data.isp)" }
if ($data.interface.externalIp) { $extraText += "ExternalIP: $($data.interface.externalIp)" }
if ($data.server.ip) { $extraText += "ServerIP: $($data.server.ip)" }
if ($data.server.location -or $data.server.country) { $extraText += "ServerLocation: $($data.server.location), $($data.server.country)" }
if ($extraText.Count -gt 0) { $text += " | " + ($extraText -join " | ") }

# Start XML result with mandatory channels and best practices
$prtgResults = New-Object -TypeName System.Text.StringBuilder
<prtg>
  # Each <result> block represents a monitored metric in PRTG.
  # The <channel> specifies the name of the metric.
  # The <value> provides the measured value for the metric.
  # The <unit> and optional <CustomUnit> define the unit of measurement.
  # Additional tags like <Float> or <SpeedSize> provide further details about the metric.

  <result>
  <channel>Download Speed</channel>  # Channel for download speed in Mbps.
  <value>$downloadBits</value>       # Value of download speed in bits per second.
  <unit>SpeedNet</unit>              # Unit type for network speed.
  <SpeedSize>MegaBit</SpeedSize>     # Specifies the size unit as Megabits.
  </result>

  <result>
  <channel>Upload Speed</channel>    # Channel for upload speed in Mbps.
  <value>$uploadBits</value>         # Value of upload speed in bits per second.
  <unit>SpeedNet</unit>              # Unit type for network speed.
  <SpeedSize>MegaBit</SpeedSize>     # Specifies the size unit as Megabits.
  </result>

  <result>
  <channel>Ping - Response time</channel>  # Channel for ping response time in milliseconds.
  <value>$pingMs</value>                  # Value of ping response time.
  <Float>1</Float>                        # Indicates the value is a floating-point number.
  <unit>TimeResponse</unit>               # Unit type for response time.
  <CustomUnit>ms</CustomUnit>             # Specifies the custom unit as milliseconds.
  </result>
  </result>
"@) | Out-Null

# Optional detailed stats if requested
if ($DetailedOutput) {
  foreach ($key in @("download", "upload", "ping")) {
    if ($data.$key -and $data.$key.latency) {
      foreach ($latencyKey in @("iqm", "low", "high", "jitter")) {
        if ($data.$key.latency.$latencyKey) {
          $prtgResults.AppendLine(@"
  <result>
  <channel>$($key.Capitalize()) Latency $($latencyKey.Capitalize())</channel>
  <value>$($data.$key.latency.$latencyKey)</value>
  <Float>1</Float>
  <unit>TimeResponse</unit>
  <CustomUnit>ms</CustomUnit>
  </result>
"@) | Out-Null
        }
      }
    }
  }
  if ($data.packetLoss -ne $null) {
    $prtgResults.AppendLine(@"
  <result>
  <channel>Packet Loss</channel>
  <value>$([math]::Round($data.packetLoss, 3))</value>
  <Float>1</Float>
  <unit>Percent</unit>
  </result>
"@) | Out-Null
  }
}

# Close XML with summary text
$prtgResults.AppendLine("  <text>$text</text>`n</prtg>") | Out-Null

# Output final PRTG XML (only this!)
Write-Output $prtgResults.ToString()