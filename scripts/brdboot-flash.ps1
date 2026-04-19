<#
.SYNOPSIS
  Flash a brdboot image to a USB drive from Windows, via WSL, with SHA-256 verify.

.DESCRIPTION
  Orchestrates WSL to expose a physical USB drive as a raw Linux block device
  and invokes scripts/brdboot-flash.sh from inside WSL so the flash + verify
  runs as on a native Linux host. Detaches the drive cleanly on exit.

  Two modes of invocation:

  Interactive (no arguments) — recommended for operators:
    .\scripts\brdboot-flash.ps1
    Assumes the flash drive is NOT yet plugged in. Snapshots currently-
    attached disks, prompts to plug in the USB, detects the new disk by diff,
    confirms the wipe, then flashes.

  Non-interactive (for scripted / confident use):
    .\scripts\brdboot-flash.ps1 -Disk <N> [-Image <path>]
    No prompts, no wipe confirmation. Flashes disk #N immediately.

.PARAMETER Disk
  Windows physical disk number (as reported by Get-Disk). Omit for
  interactive mode.

.PARAMETER Image
  Path to a .raw or .iso image to flash. Windows path; translated to
  WSL's filesystem namespace via wslpath. Omit to let the bash-side
  auto-discover under ./result/.

.EXAMPLE
  .\scripts\brdboot-flash.ps1
  Interactive mode: plug in the USB when prompted, confirm wipe, flash
  the single image under ./result/.

.EXAMPLE
  .\scripts\brdboot-flash.ps1 -Disk 2
  Non-interactive: wipe disk #2 and flash ./result immediately.

.EXAMPLE
  .\scripts\brdboot-flash.ps1 -Disk 2 -Image C:\Users\op\Downloads\brdboot-immutable.raw
  Non-interactive: wipe disk #2 and flash a specific image from any
  path, bypassing ./result lookup.

.NOTES
  Requires:
   - WSL2 installed with `nix-shell` available inside the distribution.
   - Elevated PowerShell (wsl --mount needs admin) — gsudo works.
   - ./result symlink from `nix build .#...images.<variant>` OR an
     explicit -Image path.
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(HelpMessage = 'Windows physical disk number (see Get-Disk). Omit for interactive mode.')]
  [int]$Disk,

  [Parameter(HelpMessage = 'Path to .raw or .iso image (Windows path). Omit to auto-discover under ./result/.')]
  [string]$Image
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$interactive = -not $PSBoundParameters.ContainsKey('Disk')

if ($Image -and -not (Test-Path -Path $Image -PathType Leaf)) {
  throw "image file not found: $Image"
}

if ($interactive) {
  Write-Host 'no -Disk argument — entering interactive mode.'
  Write-Host ''
  Write-Host 'for non-interactive usage:'
  Write-Host '  .\scripts\brdboot-flash.ps1 -Disk <N>'
  Write-Host '  Get-Help .\scripts\brdboot-flash.ps1 -Full'
  Write-Host ''
  Write-Host 'this mode assumes the USB flash drive is NOT currently plugged in.'
  Write-Host 'if it already is, press Ctrl-C and re-invoke with -Disk <N>.'
  Write-Host ''

  $before = @(Get-Disk).Number
  Read-Host 'plug the USB drive in now, then press Enter once Windows has enumerated it'

  Start-Sleep -Seconds 1
  $after = @(Get-Disk).Number
  $new = @($after | Where-Object { $before -notcontains $_ })

  if ($new.Count -eq 0) {
    Write-Error 'no new disk detected. Get-Disk to list; re-invoke with -Disk <N> if needed.'
    exit 1
  }
  elseif ($new.Count -gt 1) {
    Write-Error ("more than one new disk detected: {0}. plug in exactly one USB." -f ($new -join ', '))
    exit 1
  }

  $Disk = $new[0]
}

$target = Get-Disk -Number $Disk -ErrorAction SilentlyContinue
if (-not $target) {
  Write-Error "no disk #$Disk found — run Get-Disk to list candidates"
  exit 1
}
$sizeGB = [math]::Round($target.Size / 1GB, 1)
Write-Host "target: disk #$Disk — $($target.FriendlyName) ($sizeGB GB, bus $($target.BusType))"

if ($interactive) {
  Write-Host ''
  $confirm = Read-Host "WIPE disk #$Disk and write the brdboot image from ./result? [y/N]"
  if ($confirm -ne 'y') { Write-Host 'aborted'; exit 1 }
}

# Snapshot WSL block devices before mount so we can identify the new one
$beforeRaw = wsl bash -c 'ls /dev/sd? 2>/dev/null | tr "\n" " "'
$beforeWsl = $beforeRaw.Trim() -split '\s+' | Where-Object { $_ }

Write-Verbose "attaching \\.\PHYSICALDRIVE$Disk to WSL (bare)..."
wsl --mount "\\.\PHYSICALDRIVE$Disk" --bare

try {
  Start-Sleep -Seconds 1  # let the WSL kernel enumerate the new device
  $afterRaw = wsl bash -c 'ls /dev/sd? 2>/dev/null | tr "\n" " "'
  $afterWsl = $afterRaw.Trim() -split '\s+' | Where-Object { $_ }
  $newWsl = $afterWsl | Where-Object { $beforeWsl -notcontains $_ }

  if ($newWsl.Count -ne 1) {
    throw "expected exactly one new /dev/sdX after mount; got $($newWsl.Count): $($newWsl -join ', ')"
  }
  $dev = $newWsl[0]
  Write-Verbose "WSL sees disk as $dev"

  # Run the bash script from the current Windows directory (must
  # contain ./result unless -Image is given).
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
