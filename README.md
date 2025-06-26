# PRTG-Speedtest

## Overview

This repository contains a custom sensor integration for [PRTG Network Monitor](https://www.paessler.com/prtg) that allows you to measure network speed (download, upload, ping, and more) by leveraging the [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli). The sensor is designed as an **EXE/Script Advanced** sensor and outputs its results in PRTG-compatible XML.

The solution consists of two files:
- `speedtest.bat` – Batch file that acts as a wrapper to launch the PowerShell script.
- `speedtest.ps1` – PowerShell script that executes the speed test and formats the result for PRTG.

## Features

- **Measures Download, Upload, and Ping**
- **Supports binding to a specific source IP/interface**
- **Optional detailed statistics** (e.g., latency, jitter, packet loss)
- **Robust error handling**: always returns valid PRTG XML, including meaningful error messages.
- **Easy to extend** for more channels as needed.

## Usage

### 1. Requirements

- Place `speedtest.ps1`, `speedtest.bat`, and `speedtest.exe` (the Ookla CLI binary) in  
  `C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\`  
  (or the custom sensors directory you use with PRTG).

### 2. Sensor Setup in PRTG

- Add a new **EXE/Script Advanced** sensor to your probe or device.
- For the "EXE/Script" field, select `speedtest.bat`.
- (Optional) Pass parameters, e.g. for a specific interface:  
  ```
  -i 192.168.1.100
  ```
  Or for detailed output:  
  ```
  -i 192.168.1.100 -detailed
  ```
- Adjust timeout as needed (speed tests may take 10–60 seconds).

### 3. Output

- The script outputs only a single `<prtg>...</prtg>` XML block to stdout.
- Each measured value is mapped to a PRTG channel (Mbps, ms, or percent).
- If an error occurs, a valid `<prtg><error>1</error><text>...</text></prtg>` block is returned for proper PRTG alerting.

### 4. Customization

- You can add/remove channels or tweak output formatting in `speedtest.ps1`.
- All units and channel names are defined to be PRTG-compatible.

## Example Command (manual test)

To test as SYSTEM (like PRTG), use [PsExec](https://docs.microsoft.com/en-us/sysinternals/downloads/psexec):

```cmd
psexec -i -s cmd.exe
cd "C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML"
speedtest.bat -i 192.168.1.100
```

## Troubleshooting

- Ensure all files are in the EXEXML directory and have the correct names.
- Run the batch file manually as SYSTEM to confirm XML output.
- Only the `<prtg>...</prtg>` block should be output—no extra lines, headers, or errors.
- If PRTG shows only zeros, delete and recreate the sensor and restart the probe service.

## File Overview

- **speedtest.ps1** – Main logic for running and parsing the speed test.
- **speedtest.bat** – Simple batch wrapper to invoke the PowerShell script with correct parameters for PRTG.

---

© 2025 Your Company / Author.  
MIT License or as suitable.
