<#
.SYNOPSIS
  Idempotent installer for the devops-sysadmin IronClaw skill on a Windows 11
  fleet node.

.DESCRIPTION
  Run as local admin (jason) from the NAS packet. Installs UV into an
  AppLocker-safe path, bootstraps windows-mcp via uvx, materialises the skill
  under %USERPROFILE%\.ironclaw\skills\devops-sysadmin\, writes IronClaw MCP
  client configs, registers the 1Password service-account token in Windows
  Credential Manager (per-machine, DPAPI-cached), and schedules the preflight
  task.

.PARAMETER Pull
  Pull the latest skill bundle from the NAS before installing. Defaults to
  $true.

.PARAMETER Mode
  Install mode: Node (default) or Workstation. Workstation skips the scheduled
  task.

.PARAMETER NasPath
  NAS UNC path to the devops-sysadmin bundle.

.PARAMETER SkillInstallDir
  Target skill install directory (under %USERPROFILE%).

.PARAMETER UvRoot
  AppLocker-safe UV root (default C:\dev\.uv).

.PARAMETER NoOp
  Dry run; log actions without executing them.

.EXAMPLE
  .\install.ps1 -Pull -Mode Node
#>

[CmdletBinding()]
param(
    [switch] $Pull = $true,
    [ValidateSet('Node', 'Workstation')]
    [string] $Mode = 'Node',
    [string] $NasPath = '\\SynologyRouter\filesys3\scripts\devops-sysadmin',
    [string] $SkillInstallDir = (Join-Path $env:USERPROFILE '.ironclaw\skills\devops-sysadmin'),
    [string] $UvRoot = 'C:\dev\.uv',
    [string] $WindowsMcpVersion = '0.7.1',
    [switch] $NoOp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string] $Msg)
    $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    Write-Host "[$ts] $Msg"
}

function Invoke-Cmd {
    param([string] $Cmd, [string[]] $Args)
    Write-Step "exec: $Cmd $($Args -join ' ')"
    if ($NoOp) { return }
    & $Cmd @Args
    if ($LASTEXITCODE -ne 0) {
        throw "command failed: $Cmd ($LASTEXITCODE)"
    }
}

function Assert-LocalAdmin {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($me)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "install.ps1 must run as local admin (expected 'jason')."
    }
    if ($me.Name -notmatch 'jason$') {
        Write-Warning "Running admin is '$($me.Name)'; expected local admin 'jason'. Continuing per ADR-015."
    }
}

function Ensure-Dir {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Step "mkdir $Path"
        if (-not $NoOp) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
    }
}

function Test-Command {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# ---------- 1. preconditions ----------
Assert-LocalAdmin

Ensure-Dir $UvRoot
Ensure-Dir (Join-Path $UvRoot 'cache')
Ensure-Dir (Join-Path $UvRoot 'python')
Ensure-Dir (Join-Path $UvRoot 'venvs\windows-mcp')
Ensure-Dir $SkillInstallDir

$env:UV_CACHE_DIR = Join-Path $UvRoot 'cache'
$env:UV_PYTHON_INSTALL_DIR = Join-Path $UvRoot 'python'
$env:UV_PROJECT_ENVIRONMENT = Join-Path $UvRoot 'venvs\windows-mcp'

# Persist the three env vars at the machine scope so uvx inherits them for the
# IronClaw service account too.
foreach ($pair in @(
    @{ Name = 'UV_CACHE_DIR';           Value = $env:UV_CACHE_DIR },
    @{ Name = 'UV_PYTHON_INSTALL_DIR';  Value = $env:UV_PYTHON_INSTALL_DIR },
    @{ Name = 'UV_PROJECT_ENVIRONMENT'; Value = $env:UV_PROJECT_ENVIRONMENT }
)) {
    $current = [Environment]::GetEnvironmentVariable($pair.Name, 'Machine')
    if ($current -ne $pair.Value) {
        Write-Step "set machine env $($pair.Name)=$($pair.Value)"
        if (-not $NoOp) {
            [Environment]::SetEnvironmentVariable($pair.Name, $pair.Value, 'Machine')
        }
    }
}

# ---------- 2. install uv (winget) if missing ----------
if (-not (Test-Command 'uv')) {
    Write-Step 'installing astral-sh.uv via winget'
    Invoke-Cmd 'winget' @('install', '--id', 'astral-sh.uv', '--silent', '--accept-package-agreements', '--accept-source-agreements')
} else {
    Write-Step "uv already installed: $((uv --version) 2>$null)"
}

# ---------- 3. bootstrap uvx windows-mcp (pinned) ----------
$windowsMcpSpec = "windows-mcp@$WindowsMcpVersion"
Write-Step "bootstrapping uvx $windowsMcpSpec (AppLocker-safe path, pinned)"
if (-not $NoOp) {
    $helpOut = & uvx $windowsMcpSpec --help 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "uvx $windowsMcpSpec --help failed: $helpOut"
    }
    $helpHashInput = [System.Text.Encoding]::UTF8.GetBytes(($helpOut | Out-String))
    $sha = [System.BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($helpHashInput)).Replace('-', '').ToLower()
    $telemDir = Join-Path $SkillInstallDir 'telemetry'
    Ensure-Dir $telemDir
    Set-Content -Path (Join-Path $telemDir 'windows-mcp.sha') -Value $sha
    Set-Content -Path (Join-Path $telemDir 'windows-mcp.version') -Value $WindowsMcpVersion
    Write-Step "recorded windows-mcp version=$WindowsMcpVersion sha256=$sha"
}

# ---------- 4. install op CLI if missing ----------
if (-not (Test-Command 'op')) {
    Write-Step 'installing 1Password op CLI via winget'
    Invoke-Cmd 'winget' @('install', '--id', '1Password.op', '--silent', '--accept-package-agreements', '--accept-source-agreements')
} else {
    Write-Step "op already installed: $((op --version) 2>$null)"
}

# ---------- 5. pull / sync skill bundle ----------
if ($Pull) {
    if (-not (Test-Path $NasPath)) {
        throw "NAS path not reachable: $NasPath"
    }
    Write-Step "syncing $NasPath -> $SkillInstallDir"
    if (-not $NoOp) {
        robocopy $NasPath $SkillInstallDir /MIR /R:2 /W:5 /NFL /NDL /NJH /NJS /NP | Out-Null
    }
}

# ---------- 6. write IronClaw MCP client config ----------
$configDir = Join-Path $env:USERPROFILE '.ironclaw\config.d'
Ensure-Dir $configDir

$windowsMcpToml = @"
# Generated by skills/devops-sysadmin/install.ps1 (ADR-015)
# Pinned to windows-mcp $WindowsMcpVersion; bump via -WindowsMcpVersion and re-run.
[mcp.windows-mcp]
transport = "stdio"
command = "uvx"
args = ["$windowsMcpSpec"]

[mcp.windows-mcp.env]
ANONYMIZED_TELEMETRY = "false"
WINDOWS_MCP_SCREENSHOT_SCALE = "0.5"
WINDOWS_MCP_SCREENSHOT_BACKEND = "auto"
UV_CACHE_DIR = "$(($env:UV_CACHE_DIR).Replace('\', '/'))"
UV_PYTHON_INSTALL_DIR = "$(($env:UV_PYTHON_INSTALL_DIR).Replace('\', '/'))"
UV_PROJECT_ENVIRONMENT = "$(($env:UV_PROJECT_ENVIRONMENT).Replace('\', '/'))"
"@
$windowsMcpPath = Join-Path $configDir 'windows-mcp.toml'
Write-Step "writing $windowsMcpPath"
if (-not $NoOp) { Set-Content -Path $windowsMcpPath -Value $windowsMcpToml -Encoding UTF8 }

$opToml = @"
# Generated by skills/devops-sysadmin/install.ps1 (ADR-015)
[secrets.op]
service_account = true
cache = "dpapi"
scopes_file = "$(($SkillInstallDir).Replace('\', '/'))/op-scopes.yaml"
"@
$opTomlPath = Join-Path $configDir 'op-service-account.toml'
Write-Step "writing $opTomlPath"
if (-not $NoOp) { Set-Content -Path $opTomlPath -Value $opToml -Encoding UTF8 }

# ---------- 7. register OP_SERVICE_ACCOUNT_TOKEN in Windows Credential Manager ----------
# We never embed the token in plaintext. We look for it in an env var the
# operator sets at invocation time; if missing, emit the exact op-cli command
# they must run once on this host.
$existingCred = cmdkey /list:IronClawOpServiceAccount 2>$null
if ($LASTEXITCODE -ne 0 -or ($existingCred -notmatch 'IronClawOpServiceAccount')) {
    if ($env:OP_SERVICE_ACCOUNT_TOKEN -and $env:OP_SERVICE_ACCOUNT_TOKEN.Length -gt 20) {
        Write-Step 'registering OP_SERVICE_ACCOUNT_TOKEN in Windows Credential Manager'
        if (-not $NoOp) {
            cmdkey /generic:IronClawOpServiceAccount /user:ironclaw /pass:$env:OP_SERVICE_ACCOUNT_TOKEN | Out-Null
        }
        $env:OP_SERVICE_ACCOUNT_TOKEN = $null
    } else {
        Write-Warning 'OP_SERVICE_ACCOUNT_TOKEN not in env; run: $env:OP_SERVICE_ACCOUNT_TOKEN="ops_..."; cmdkey /generic:IronClawOpServiceAccount /user:ironclaw /pass:$env:OP_SERVICE_ACCOUNT_TOKEN'
    }
} else {
    Write-Step 'IronClawOpServiceAccount credential already registered; skipping'
}

# ---------- 8. op smoke test (fingerprint only, never the value) ----------
Write-Step 'op smoke test: MiniMax credential length+sha prefix'
if (-not $NoOp) {
    try {
        $cred = op read 'op://Cursor_IronClaw/MiniMax M2.7 highspeed API 1/credential' 2>$null
        if (-not $cred) { throw 'empty' }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($cred)
        $sha = [System.BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($bytes)).Replace('-', '').ToLower().Substring(0, 12)
        Write-Step "minimax credential: length=$($cred.Length) sha256_prefix=$sha"
        Set-Content -Path (Join-Path $SkillInstallDir 'telemetry/minimax-credential.fingerprint') -Value "length=$($cred.Length) sha256_prefix=$sha"
    } catch {
        Write-Warning "op smoke skipped: $_"
    }
}

# ---------- 9. scheduled task: preflight every 3 min ----------
if ($Mode -eq 'Node') {
    $taskName = 'IronClaw-Preflight'
    $preflight = Join-Path $SkillInstallDir 'scripts/preflight.ps1'
    if (Test-Path $preflight) {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NonInteractive -ExecutionPolicy Bypass -File `"$preflight`""
        $trigger1 = New-ScheduledTaskTrigger -AtStartup
        $trigger2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 3) -RepetitionDuration ([TimeSpan]::MaxValue)
        $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Write-Step "registering scheduled task $taskName"
        if (-not $NoOp) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigger1, $trigger2) -Principal $principal -Settings $settings | Out-Null
        }
    } else {
        Write-Warning "preflight script missing at $preflight; skipping task registration"
    }
}

Write-Step 'install.ps1 done'
exit 0
