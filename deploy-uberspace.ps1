# =========================
# deploy-uberspace.ps1
# =========================
# Mirror ASD's baked site to Uberspace via SFTP (WinSCP .NET).
# - NO BAKING here (run your bake separately)
# - Uploads parametric-static/ -> ~/html
# - Preserves timestamps, mirrors changes
# - Excludes ASD scripts/backups and executables
# PowerShell 5.1 compatible.

param(
  [string]$LocalPath  = (Join-Path $PSScriptRoot 'parametric-static'),
  [string]$HostName   = 'maestro.uberspace.de',   # e.g., stardust.uberspace.de
  [int]   $Port       = 22,
  [string]$UserName   = 'maestro',
  [string]$RemotePath = '~/html',
  [string]$KeyFile    = $null,                      # optional: path to your private key (e.g., C:\Users\You\.ssh\id_ed25519)
  [string]$SshHostKeyFingerprint = $null,           # optional: e.g., "ssh-ed25519 256 Xx:.."
  [switch]$RemoveRemoteExtras                         # mirror-delete remote files not present locally
)

function Import-WinScp {
  $candidates = @(
    'C:\Program Files (x86)\WinSCP\WinSCPnet.dll',
    'C:\Program Files\WinSCP\WinSCPnet.dll'
  )
  foreach ($p in $candidates) { if (Test-Path $p) { Add-Type -Path $p; return } }
  throw "WinSCP .NET assembly not found. Install WinSCP from https://winscp.net/ and rerun."
}

function ConvertTo-Plain([SecureString]$s) {
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

if (-not (Test-Path $LocalPath)) { throw "LocalPath not found: $LocalPath" }
$localIndex = Join-Path $LocalPath 'index.html'
if (-not (Test-Path $localIndex)) {
  Write-Warning "index.html not found in $LocalPath. Did you bake? (Continuing anyway.)"
}

Import-WinScp
Write-Host "[WinSCP] .NET assembly loaded" -ForegroundColor DarkGray

$sessionOptions = New-Object WinSCP.SessionOptions
$sessionOptions.Protocol   = [WinSCP.Protocol]::Sftp
$sessionOptions.HostName   = $HostName
$sessionOptions.PortNumber = $Port
$sessionOptions.UserName   = $UserName

if ($KeyFile) {
  if (-not (Test-Path $KeyFile)) { throw "Key file not found: $KeyFile" }
  $sessionOptions.SshPrivateKeyPath = $KeyFile
} else {
  $sec = Read-Host "Enter SSH password for $UserName@$HostName" -AsSecureString
  $sessionOptions.Password = ConvertTo-Plain $sec
}

if ($SshHostKeyFingerprint) {
  $sessionOptions.SshHostKeyFingerprint = $SshHostKeyFingerprint
} else {
  Write-Warning "No SSH host key fingerprint set. First connect once via WinSCP GUI to cache it, or supply -SshHostKeyFingerprint for strict security."
}

$transferOptions = New-Object WinSCP.TransferOptions
$transferOptions.TransferMode      = [WinSCP.TransferMode]::Binary
$transferOptions.PreserveTimestamp = $true
# Use TransferOptions.FileMask for broad compatibility (avoids overload mismatch)
$transferOptions.FileMask = "| scripts/; scripts.__bak__*/; *.ps1; *.psm1; *.bat; *.cmd; *.sh; *.py; *.exe; *.dll; *.msi"

$session = New-Object WinSCP.Session
try {
  Write-Host "[SFTP] Connecting to $HostName…" -ForegroundColor Cyan
  $session.Open($sessionOptions)

  # Ensure remote dir exists
  $session.CreateDirectory($RemotePath) | Out-Null

  Write-Host "[SFTP] Syncing $LocalPath -> $RemotePath" -ForegroundColor Cyan
  $result = $session.SynchronizeDirectories(
    [WinSCP.SynchronizationMode]::Remote,
    $LocalPath,
    $RemotePath,
    $RemoveRemoteExtras.IsPresent,   # removeFiles (false by default)
    $true,                           # mirror
    [WinSCP.SynchronizationCriteria]::Time,
    $transferOptions
  )

  $result.Check()
  Write-Host "[DONE] Uploaded $($result.Uploads.Count) file(s). Failures: $($result.Failures.Count)" -ForegroundColor Green
}
finally {
  if ($session -ne $null) { $session.Dispose() }
}
