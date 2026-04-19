# brdboot-flash.ps1 — canonical brdboot flash + verify from Windows, via WSL.
#
# Orchestrates WSL to expose a USB drive as a raw block device and invokes
# scripts/brdboot-flash.sh from inside WSL so the bash-side flash + SHA-256
# verify runs as on a native Linux host.
#
# Usage:
#   .\scripts\brdboot-flash.ps1 -Disk <N> [-Image <path>]
#
# -Disk   required: Windows physical disk number (see `Get-Disk`).
# -Image  optional: path to a .raw or .iso image (Windows path). When
#         omitted, the bash script auto-discovers under ./result/.
#
# The USB drive must not be mounted in Windows (unmount any drive letters
# first, or use diskpart "offline disk").
#
# Requirements:
#   - WSL2 installed and a default distribution configured.
#   - `nix-shell` available inside the WSL distribution (the bash script's
#     shebang depends on it; NixOS-WSL and nix-installed Ubuntu both work).
#   - Must be run from an elevated PowerShell (admin) — `wsl --mount` needs
#     it to attach a physical disk.
#   - Run from a directory containing a ./result symlink produced by
#     `nix build .#...images.<variant>`, OR pass -Image explicitly.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, HelpMessage = 'Windows physical disk number (see Get-Disk)')]
  [int]$Disk,

  [Parameter(HelpMessage = 'Path to .raw or .iso image (Windows path). Omit to auto-discover under ./result/.')]
  [string]$Image
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($Image -and -not (Test-Path -Path $Image -PathType Leaf)) {
  throw "image file not found: $Image"
}

# Sanity-check the target disk
$target = Get-Disk -Number $Disk -ErrorAction SilentlyContinue
if (-not $target) {
  Write-Error "no disk #$Disk found — run Get-Disk to list candidates"
  exit 1
}
$sizeGB = [math]::Round($target.Size / 1GB, 1)
Write-Host "target: disk #$Disk — $($target.FriendlyName) ($sizeGB GB, bus $($target.BusType))"

if ($target.BusType -ne 'USB') {
  $confirm = Read-Host "WARNING: disk #$Disk is bus type $($target.BusType), not USB. Continue? [y/N]"
  if ($confirm -ne 'y') { Write-Host 'aborted'; exit 1 }
}

# Snapshot WSL block devices before mount so we can identify the new one
$beforeRaw = wsl bash -c 'ls /dev/sd? 2>/dev/null | tr "\n" " "'
$before = $beforeRaw.Trim() -split '\s+' | Where-Object { $_ }

Write-Verbose "attaching \\.\PHYSICALDRIVE$Disk to WSL (bare)..."
wsl --mount "\\.\PHYSICALDRIVE$Disk" --bare

try {
  Start-Sleep -Seconds 1  # let the WSL kernel enumerate the new device
  $afterRaw = wsl bash -c 'ls /dev/sd? 2>/dev/null | tr "\n" " "'
  $after = $afterRaw.Trim() -split '\s+' | Where-Object { $_ }
  $new = $after | Where-Object { $before -notcontains $_ }

  if ($new.Count -ne 1) {
    throw "expected exactly one new /dev/sdX after mount; got $($new.Count): $($new -join ', ')"
  }
  $dev = $new[0]
  Write-Verbose "WSL sees disk as $dev"

  # Run the bash script from the current Windows directory (must contain
  # ./result unless -Image is given).
  $pwdWsl = (wsl wslpath -a "$(Get-Location)").Trim()

  if ($Image) {
    $imageWsl = (wsl wslpath -a "$Image").Trim()
    Write-Verbose "running brdboot-flash.sh $dev $imageWsl from $pwdWsl..."
    wsl bash -c "cd '$pwdWsl' && ./scripts/brdboot-flash.sh $dev '$imageWsl'"
  }
  else {
    Write-Verbose "running brdboot-flash.sh $dev from $pwdWsl..."
    wsl bash -c "cd '$pwdWsl' && ./scripts/brdboot-flash.sh $dev"
  }
}
finally {
  Write-Verbose "detaching \\.\PHYSICALDRIVE$Disk..."
  wsl --unmount "\\.\PHYSICALDRIVE$Disk" 2>&1 | Out-Null
}
