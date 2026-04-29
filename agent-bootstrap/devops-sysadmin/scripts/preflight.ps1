<#
.SYNOPSIS
  devops-sysadmin preflight for Windows 11 fleet nodes.

.DESCRIPTION
  Writes a small JSON report to
  %USERPROFILE%\.ironclaw\skills\devops-sysadmin\telemetry\preflight.json and
  exposes the same data as Prometheus-compatible lines via stdout so a
  pushgateway or textfile-collector can scrape it.

  Exits 0 when all required gates pass; non-zero otherwise.
#>

[CmdletBinding()]
param(
    [switch] $Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$skillDir = Join-Path $env:USERPROFILE '.ironclaw\skills\devops-sysadmin'
$telemDir = Join-Path $skillDir 'telemetry'
if (-not (Test-Path $telemDir)) { New-Item -ItemType Directory -Force -Path $telemDir | Out-Null }
$report = [ordered]@{}
$report.timestamp = (Get-Date).ToUniversalTime().ToString('o')
$report.node = $env:COMPUTERNAME
$report.user = $env:USERNAME
$fail = $false

# --- disk ---
try {
    $drive = Get-PSDrive -Name C -ErrorAction Stop
    $used_pct = [math]::Round(($drive.Used / ($drive.Used + $drive.Free)) * 100, 2)
    $report.disk_used_pct = $used_pct
    if ($used_pct -ge 90) { $fail = $true; Write-Warning "disk C: used ${used_pct}%" }
} catch { $report.disk_used_pct = 'error' }

# --- memory ---
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $mem_used_pct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 2)
    $report.memory_used_pct = $mem_used_pct
    if ($mem_used_pct -ge 95) { $fail = $true }
} catch { $report.memory_used_pct = 'error' }

# --- GPU temperature + VRAM (if nvidia-smi present) ---
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    try {
        $gpuLines = nvidia-smi --query-gpu=index,name,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits
        $gpus = @()
        foreach ($line in $gpuLines) {
            $parts = $line -split ','
            if ($parts.Count -lt 5) { continue }
            $gpus += [ordered]@{
                index = [int]($parts[0].Trim())
                name = $parts[1].Trim()
                temp_c = [int]($parts[2].Trim())
                vram_used_mb = [int]($parts[3].Trim())
                vram_total_mb = [int]($parts[4].Trim())
            }
            if ([int]($parts[2].Trim()) -gt 85) { $fail = $true; Write-Warning "GPU $($parts[0].Trim()) > 85C" }
        }
        $report.gpus = $gpus
    } catch { $report.gpus = 'error' }
}

# --- evoloop-daemon healthz (WSL side) ---
try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9301/healthz' -TimeoutSec 3 -ErrorAction Stop
    $report.evoloop_healthz = $resp.StatusCode
} catch {
    $report.evoloop_healthz = 'unreachable'
}

# --- windows-mcp bootstrap + drift check ---
try {
    $uvxPath = (Get-Command uvx -ErrorAction Stop).Source
    $report.uvx = $uvxPath
    $pinnedVersion = $null
    $versionFile = Join-Path $telemDir 'windows-mcp.version'
    if (Test-Path $versionFile) {
        $pinnedVersion = (Get-Content $versionFile -Raw).Trim()
    }
    $spec = if ($pinnedVersion) { "windows-mcp@$pinnedVersion" } else { 'windows-mcp' }
    $helpOut = & uvx $spec --help 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        $report.windows_mcp = 'ok'
        $report.windows_mcp_version = $pinnedVersion
    } else {
        $report.windows_mcp = 'failed'
    }

    $driftScript = Join-Path $skillDir 'scripts\check-windows-mcp-version.ps1'
    if (Test-Path $driftScript) {
        & $driftScript -Quiet | Out-Null
        $driftExit = $LASTEXITCODE
        $report.windows_mcp_drift = $driftExit
        if ($driftExit -ne 0) { $fail = $true; Write-Warning "windows-mcp drift exit=$driftExit" }
    }
} catch { $report.windows_mcp = 'missing' }

# --- op whoami ---
try {
    if (Get-Command op -ErrorAction SilentlyContinue) {
        $w = & op whoami 2>&1
        if ($LASTEXITCODE -eq 0) { $report.op = 'ok' } else { $report.op = 'not-signed-in' }
    } else { $report.op = 'missing' }
} catch { $report.op = 'error' }

$json = $report | ConvertTo-Json -Depth 4
$reportPath = Join-Path $telemDir 'preflight.json'
Set-Content -Path $reportPath -Value $json -Encoding UTF8

# Prometheus textfile output
$sbOut = New-Object System.Text.StringBuilder
foreach ($pair in @(
    @{Name='devops_sysadmin_preflight_disk_used_pct'; Value=$report.disk_used_pct},
    @{Name='devops_sysadmin_preflight_memory_used_pct'; Value=$report.memory_used_pct}
)) {
    if ($pair.Value -is [int] -or $pair.Value -is [double]) {
        [void]$sbOut.AppendLine("$($pair.Name){node=`"$($report.node)`"} $($pair.Value)")
    }
}
$sbOut.ToString() | Write-Output

if ($fail) { exit 1 } else { exit 0 }
