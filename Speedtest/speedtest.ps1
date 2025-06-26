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
$SourceIP = $null
if ($i) { $SourceIP = $i }
elseif ($ipaddress) { $SourceIP = $ipaddress }
elseif ($args.Count -ge 1) { $SourceIP = $args[0] }

# Determine if detailed output is requested
$DetailedOutput = $false
if ($d -or $detailed) { $DetailedOutput = $true }
elseif ($args -contains "-d" -or $args -contains "--detailed") { $DetailedOutput = $true }

# Validate provided IP address (IPv4 or IPv6)
$parsedIP = $null
if (-not [System.Net.IPAddress]::TryParse($SourceIP, [ref]$parsedIP)) {
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

# Run speedtest and parse output
try {
    $result = & "$speedtestPath" -i "$SourceIP" -f json 2>$null
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -or -not $result) {
        Write-Output @"
<prtg>
  <error>1</error>
  <text>Speedtest exited with code ${exitCode}. Output: $result</text>
</prtg>
"@
        exit 1
    }

    # Parse JSON result
    $data = $result | ConvertFrom-Json

    # Convert bandwidth (bytes/sec) to bits per second for PRTG (integer)
    $downloadBits = 0
    $uploadBits = 0
    if ($data.download.bandwidth -is [int] -or $data.download.bandwidth -is [double]) {
        $downloadBits = [math]::Round($data.download.bandwidth * 8)
    }
    if ($data.upload.bandwidth -is [int] -or $data.upload.bandwidth -is [double]) {
        $uploadBits = [math]::Round($data.upload.bandwidth * 8)
    }

    $pingMs = 0
    if ($data.ping.latency -is [int] -or $data.ping.latency -is [double]) {
        $pingMs = [math]::Round($data.ping.latency, 2)
    }

    # Compose summary <text> for PRTG
    $text = "Speedtest via ${SourceIP} on $($data.server.host)"
    $isp = $data.isp
    $extip = $data.interface.externalIp
    $serverip = $data.server.ip
    $serverloc = $data.server.location
    $servercountry = $data.server.country

    $extraText = @()
    if ($isp) { $extraText += "ISP: $isp" }
    if ($extip) { $extraText += "ExternalIP: $extip" }
    if ($serverip) { $extraText += "ServerIP: $serverip" }
    if ($serverloc -or $servercountry) { $extraText += "ServerLocation: $serverloc, $servercountry" }
    if ($extraText.Count -gt 0) { $text += " | " + ($extraText -join " | ") }

    # Start XML result with mandatory channels and best practices
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
    <channel>Ping - Response time</channel>
    <value>$pingMs</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@

    # Optional detailed stats if requested
    if ($DetailedOutput) {
        # Download Latency
        if ($data.download.latency.iqm) {
            $prtgResults += @"
  <result>
    <channel>Download Latency IQM</channel>
    <value>$($data.download.latency.iqm)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        if ($data.download.latency.low) {
            $prtgResults += @"
  <result>
    <channel>Download Latency Low</channel>
    <value>$($data.download.latency.low)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        if ($data.download.latency.high) {
            $prtgResults += @"
  <result>
    <channel>Download Latency High</channel>
    <value>$($data.download.latency.high)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        if ($data.download.latency.jitter) {
            $prtgResults += @"
  <result>
    <channel>Download Jitter</channel>
    <value>$($data.download.latency.jitter)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        # Upload Latency
        if ($data.upload.latency.iqm) {
            $prtgResults += @"
  <result>
    <channel>Upload Latency IQM</channel>
    <value>$($data.upload.latency.iqm)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        if ($data.upload.latency.low) {
            $prtgResults += @"
  <result>
    <channel>Upload Latency Low</channel>
    <value>$($data.upload.latency.low)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        if ($data.upload.latency.high) {
            $prtgResults += @"
  <result>
    <channel>Upload Latency High</channel>
    <value>$($data.upload.latency.high)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        if ($data.upload.latency.jitter) {
            $prtgResults += @"
  <result>
    <channel>Upload Jitter</channel>
    <value>$($data.upload.latency.jitter)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        # Ping details
        if ($data.ping.jitter) {
            $prtgResults += @"
  <result>
    <channel>Ping Jitter</channel>
    <value>$($data.ping.jitter)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        if ($data.ping.low) {
            $prtgResults += @"
  <result>
    <channel>Ping Low</channel>
    <value>$($data.ping.low)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        if ($data.ping.high) {
            $prtgResults += @"
  <result>
    <channel>Ping High</channel>
    <value>$($data.ping.high)</value>
    <Float>1</Float>
    <unit>TimeResponse</unit>
    <CustomUnit>ms</CustomUnit>
  </result>
"@
        }
        # PacketLoss
        if ($null -ne $data.packetLoss) {
            $packetLossPct = [math]::Round($data.packetLoss, 3)
            $prtgResults += @"
  <result>
    <channel>Packet Loss</channel>
    <value>$packetLossPct</value>
    <Float>1</Float>
    <unit>Percent</unit>
  </result>
"@
        }
    }

    # Close XML with summary text
    $prtgResults += "  <text>$text</text>`n</prtg>"

    # Output final PRTG XML (only this!)
    Write-Output $prtgResults
}
catch {
    # Always return PRTG error XML on exception
    Write-Output @"
<prtg>
  <error>1</error>
  <text>Speedtest failed with source ${SourceIP}: $_</text>
</prtg>
"@
}