<#
.SYNOPSIS
  Check the installed `uvx windows-mcp` version against the devops-sysadmin
  pin and emit a Prometheus textfile metric.

.DESCRIPTION
  Reads $SkillDir\telemetry\windows-mcp.version for the expected pin, runs
  `uvx windows-mcp@<pin> --help`, verifies uvx resolved the pinned version,
  re-computes the sha256 of `--help` stdout, and writes
  $SkillDir\telemetry\windows-mcp-drift.prom with two series:

    windows_mcp_version_pin{node="...",pin="..."} 1
    windows_mcp_drift{node="...",pin="..."} 0_or_1

  Exits 0 when drift=0, 1 when drift detected, 2 when telemetry missing.
#>

[CmdletBinding()]
param(
    [string] $SkillDir = (Join-Path $env:USERPROFILE '.ironclaw\skills\devops-sysadmin'),
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Out-Log { param([string] $Msg) if (-not $Quiet) { Write-Host $Msg } }

$telemDir = Join-Path $SkillDir 'telemetry'
$versionFile = Join-Path $telemDir 'windows-mcp.version'
$shaFile = Join-Path $telemDir 'windows-mcp.sha'
$promFile = Join-Path $telemDir 'windows-mcp-drift.prom'
$node = $env:COMPUTERNAME

if (-not (Test-Path $versionFile)) {
    Out-Log "telemetry missing: $versionFile -- run install.ps1 first"
    if (-not (Test-Path $telemDir)) { New-Item -ItemType Directory -Force -Path $telemDir | Out-Null }
    "windows_mcp_version_pin{node=`"$node`",pin=`"unknown`"} 0" | Set-Content -Path $promFile -Encoding UTF8
    "windows_mcp_drift{node=`"$node`",pin=`"unknown`"} 1" | Add-Content -Path $promFile -Encoding UTF8
    exit 2
}

$pinned = (Get-Content $versionFile -Raw).Trim()
if (-not $pinned) {
    Out-Log "pin file empty: $versionFile"
    exit 2
}

$spec = "windows-mcp@$pinned"
$drift = 0
$reason = 'ok'

$helpOut = & uvx $spec --help 2>&1
if ($LASTEXITCODE -ne 0) {
    Out-Log "uvx $spec --help failed (exit $LASTEXITCODE): $helpOut"
    $drift = 1
    $reason = 'uvx-failed'
} else {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($helpOut | Out-String))
    $actualSha = [System.BitConverter]::ToString(
        (New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($bytes)
    ).Replace('-', '').ToLower()

    if (Test-Path $shaFile) {
        $expectedSha = (Get-Content $shaFile -Raw).Trim()
        if ($expectedSha -and ($expectedSha -ne $actualSha)) {
            Out-Log "sha drift: expected=$expectedSha actual=$actualSha"
            $drift = 1
            $reason = 'sha-mismatch'
        }
    }
}

if (-not (Test-Path $telemDir)) { New-Item -ItemType Directory -Force -Path $telemDir | Out-Null }

$lines = @()
$lines += '# HELP windows_mcp_version_pin Pinned windows-mcp version (1 = tracked)'
$lines += '# TYPE windows_mcp_version_pin gauge'
$lines += ("windows_mcp_version_pin{{node=`"{0}`",pin=`"{1}`"}} 1" -f $node, $pinned)
$lines += '# HELP windows_mcp_drift Drift status for windows-mcp pin (0 = clean, 1 = drift)'
$lines += '# TYPE windows_mcp_drift gauge'
$lines += ("windows_mcp_drift{{node=`"{0}`",pin=`"{1}`",reason=`"{2}`"}} {3}" -f $node, $pinned, $reason, $drift)
Set-Content -Path $promFile -Value ($lines -join "`n") -Encoding UTF8

Out-Log "node=$node pin=$pinned drift=$drift reason=$reason"
exit $drift
