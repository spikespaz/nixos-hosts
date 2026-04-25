<#
.SYNOPSIS
  Flash a brdboot image to a USB drive from Windows, via WSL, with SHA-256 verify.

.DESCRIPTION
  Attaches a USB drive to WSL and invokes scripts/brdboot-flash.sh from inside
  WSL so the flash + verify runs as on a native Linux host. Detaches cleanly
  on exit.

  Two attach mechanisms, chosen automatically:

    - usbipd (from usbipd-win) — preferred. Works on all Windows
      architectures and all Windows builds, including ARM64 hosts that
      predate the native wsl --mount support (build 27653+).

    - wsl --mount --bare — fallback. Native Hyper-V raw-disk attach, no
      extra Windows tooling needed; limited on older ARM64 builds.

  Detection: if `usbipd` is on PATH, the script uses the usbipd path. If not,
  it falls back to wsl --mount. Install usbipd-win for the preferred path:

    winget install dorssel.usbipd-win

  Two modes of invocation:

  Interactive (no device args) — recommended for operators:
    .\scripts\brdboot-flash.ps1
    Prompts to plug the USB in, snapshots the active path's device list to
    identify the new device, confirms the wipe, then flashes.

  Non-interactive (for scripted / confident use):
    .\scripts\brdboot-flash.ps1 -BusId <N-N>       # usbipd path
    .\scripts\brdboot-flash.ps1 -Disk <N>          # wsl --mount path
    No prompts, no wipe confirmation.

.PARAMETER BusId
  usbipd bus-id (e.g. `1-3`; from `usbipd list`). Requires usbipd-win
  installed. Omit for interactive mode.

.PARAMETER Disk
  Windows physical disk number (see `Get-Disk`). Forces the wsl --mount
  fallback path even when usbipd-win is installed. Omit for interactive.

.PARAMETER Image
  Path to a .raw or .iso image to flash. Windows path; translated to WSL's
  filesystem namespace via wslpath. Omit to let the bash-side auto-discover
  under ./result/.

.EXAMPLE
  .\scripts\brdboot-flash.ps1
  Interactive: detects whichever path is available, prompts for plug-in,
  confirms wipe, flashes the single image under ./result/.

.EXAMPLE
  .\scripts\brdboot-flash.ps1 -BusId 1-3
  Non-interactive usbipd path: attaches USB bus-id 1-3 and flashes.

.EXAMPLE
  .\scripts\brdboot-flash.ps1 -Disk 2 -Image C:\Users\op\Downloads\brdboot-immutable.raw
  Non-interactive wsl --mount path: attaches physical disk #2 and flashes a
  specific image.

.NOTES
  Requires:
   - WSL2 installed with `nix-shell` available inside the distribution.
   - Elevated PowerShell (wsl --mount / usbipd attach need admin) — gsudo works.
   - Preferred: usbipd-win (`winget install dorssel.usbipd-win`) for the
     portable-across-archs path.
   - ./result symlink from `nix build .#...images.<variant>` OR an
     explicit -Image path.
#>

#Requires -RunAsAdministrator

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
  [Parameter(ParameterSetName = 'ByBusId', Mandatory = $true,
             HelpMessage = 'usbipd bus-id (from `usbipd list`). Requires usbipd-win.')]
  [string]$BusId,

  [Parameter(ParameterSetName = 'ByDisk', Mandatory = $true,
             HelpMessage = 'Windows physical disk number. Forces wsl --mount fallback path.')]
  [int]$Disk,

  [Parameter(HelpMessage = 'Path to .raw or .iso image (Windows path). Omit to auto-discover under ./result/.')]
  [string]$Image
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$usbipdAvailable = $null -ne (Get-Command usbipd -ErrorAction SilentlyContinue)

if ($PSCmdlet.ParameterSetName -eq 'ByBusId' -and -not $usbipdAvailable) {
  throw 'usbipd-win not installed; cannot use -BusId. (`winget install dorssel.usbipd-win`, or pass -Disk for the wsl --mount fallback.)'
}

$usePath = switch ($PSCmdlet.ParameterSetName) {
  'ByBusId' { 'usbipd' }
  'ByDisk'  { 'wsl-mount' }
  default   { if ($usbipdAvailable) { 'usbipd' } else { 'wsl-mount' } }
}

$interactive = $PSCmdlet.ParameterSetName -notin @('ByBusId', 'ByDisk')

if ($Image -and -not (Test-Path -Path $Image -PathType Leaf)) {
  throw "image file not found: $Image"
}

# `usbipd state` emits stable JSON suitable for scripted automation; it
# has been the documented upstream scripting contract since usbipd-win
# v2.2.0 (March 2022). VidPid is carried inside InstanceId (format
# "USB\VID_xxxx&PID_yyyy\...") — parsed out so the caller can display it
# the same way `usbipd list` text formats it.
function Get-UsbipdDevices {
  foreach ($d in (usbipd state | ConvertFrom-Json).Devices) {
    $vidPid = if ($d.InstanceId -match '^USB\\VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
      '{0}:{1}' -f $Matches[1].ToLower(), $Matches[2].ToLower()
    }
    else { '' }
    [pscustomobject]@{
      BusId       = $d.BusId
      VidPid      = $vidPid
      Description = $d.Description
    }
  }
}

# ----- Interactive device identification -----
if ($interactive) {
  Write-Host ''
  if ($usePath -eq 'usbipd') {
    Write-Host 'interactive mode (usbipd path).'
  }
  else {
    Write-Host 'interactive mode (wsl --mount fallback — usbipd-win not installed).'
    Write-Host '  for the preferred path: winget install dorssel.usbipd-win'
  }
  Write-Host ''
  Write-Host 'for non-interactive usage:'
  if ($usePath -eq 'usbipd') {
    Write-Host '  .\scripts\brdboot-flash.ps1 -BusId <N-N>'
  }
  else {
    Write-Host '  .\scripts\brdboot-flash.ps1 -Disk <N>'
  }
  Write-Host '  Get-Help .\scripts\brdboot-flash.ps1 -Full'
  Write-Host ''
  Write-Host 'this mode assumes the USB flash drive is NOT currently plugged in.'
  Write-Host ''

  if ($usePath -eq 'usbipd') {
    $before = @(Get-UsbipdDevices).BusId
  }
  else {
    $before = @(Get-Disk).Number
  }

  Read-Host 'plug the USB drive in now, then press Enter once Windows has enumerated it'
  Start-Sleep -Seconds 1

  if ($usePath -eq 'usbipd') {
    $after = @(Get-UsbipdDevices).BusId
  }
  else {
    $after = @(Get-Disk).Number
  }

  $new = @($after | Where-Object { $before -notcontains $_ })

  if ($new.Count -eq 0) {
    throw 'no new device detected.'
  }
  elseif ($new.Count -gt 1) {
    throw ("more than one new device: {0}. plug in exactly one USB." -f ($new -join ', '))
  }

  if ($usePath -eq 'usbipd') { $BusId = $new[0] } else { $Disk = $new[0] }
}

# ----- Target announce + wipe confirm -----
if ($usePath -eq 'usbipd') {
  $dev = (Get-UsbipdDevices) | Where-Object { $_.BusId -eq $BusId }
  if (-not $dev) { throw "bus-id $BusId not found in ``usbipd list``" }
  Write-Host "target: bus-id $BusId — $($dev.Description) [$($dev.VidPid)]"
}
else {
  $target = Get-Disk -Number $Disk -ErrorAction SilentlyContinue
  if (-not $target) { throw "no disk #$Disk — run Get-Disk to list candidates" }
  $sizeGB = [math]::Round($target.Size / 1GB, 1)
  Write-Host "target: disk #$Disk — $($target.FriendlyName) ($sizeGB GB, bus $($target.BusType))"
}

if ($interactive) {
  Write-Host ''
  $confirm = Read-Host 'WIPE this device and write the brdboot image from ./result? [y/N]'
  if ($confirm -ne 'y') { Write-Host 'aborted'; exit 1 }
}

# ----- Attach via selected path -----
$beforeWsl = @((wsl bash -c 'ls /dev/sd? 2>/dev/null') -split '\s+' | Where-Object { $_ })

if ($usePath -eq 'usbipd') {
  Write-Verbose "binding and attaching bus-id $BusId via usbipd..."
  # `usbipd bind` is a prerequisite for attach and is idempotent if the
  # device is already in shared state.
  usbipd bind --busid $BusId 2>&1 | Out-Null
  usbipd attach --wsl --busid $BusId
}
else {
  Write-Verbose "attaching \\.\PHYSICALDRIVE$Disk to WSL (bare)..."
  wsl --mount "\\.\PHYSICALDRIVE$Disk" --bare
}

try {
  # Poll briefly for WSL's kernel to enumerate the new device.
  $dev = $null
  for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Milliseconds 500
    $afterWsl = @((wsl bash -c 'ls /dev/sd? 2>/dev/null') -split '\s+' | Where-Object { $_ })
    $newWsl = @($afterWsl | Where-Object { $beforeWsl -notcontains $_ })
    if ($newWsl.Count -eq 1) { $dev = $newWsl[0]; break }
  }
  if (-not $dev) { throw 'no new /dev/sdX appeared in WSL after attach (timed out after 5s)' }
  Write-Verbose "WSL sees disk as $dev"

  # Run the bash script inside WSL. Path translation happens entirely on
  # the WSL side: `wsl --cd` takes a Windows path and wsl.exe translates
  # it to /mnt/... internally. The Image (if given) is passed as a bash
  # positional argument so backslashes aren't interpreted by PowerShell
  # string interpolation or bash escape parsing — `wslpath -a "$2"`
  # inside the bash command does the translation. Nothing in PowerShell
  # constructs a /mnt/... path.
  #
  # `--exec` is mandatory here: without it, wsl.exe silently drops the
  # positional args after `bash -c '...'` (bash sees $0=bash, no $1/$2).
  # With --exec, wsl.exe execs the program directly and preserves argv.
  # `-l` makes it a login shell so /etc/profile runs — that's what puts
  # nix-shell (needed by the script's shebang) on PATH. --exec alone
  # inherits only the minimal environment wsl.exe passes through.
  Write-Verbose "running brdboot-flash.sh $dev$(if ($Image) { " $Image" }) inside WSL..."
  if ($Image) {
    wsl --cd "$(Get-Location)" --exec bash -lc './scripts/brdboot-flash.sh "$1" "$(wslpath -a "$2")"' _ $dev $Image
  }
  else {
    wsl --cd "$(Get-Location)" --exec bash -lc './scripts/brdboot-flash.sh "$1"' _ $dev
  }
}
finally {
  if ($usePath -eq 'usbipd') {
    Write-Verbose "detaching bus-id $BusId..."
    usbipd detach --busid $BusId 2>&1 | Out-Null
  }
  else {
    Write-Verbose "detaching \\.\PHYSICALDRIVE$Disk..."
    wsl --unmount "\\.\PHYSICALDRIVE$Disk" 2>&1 | Out-Null
  }
}
