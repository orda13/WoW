# Removes the Leveling Ledger service. Your data in C:\LevelingLedger\data is kept unless you pass -RemoveFiles.
param([string]$Dest = "C:\LevelingLedger", [string]$ServiceName = "LevelingLedger", [switch]$RemoveFiles)
$ErrorActionPreference = "Stop"
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" $(if ($RemoveFiles) { '-RemoveFiles' })"; exit }
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
  Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
  & "$Dest\tools\nssm.exe" remove $ServiceName confirm | Out-Null
  Write-Host "Service removed."
}
if ($RemoveFiles) { Remove-Item $Dest -Recurse -Force; Write-Host "Removed $Dest." }
else { Write-Host "Your data is still in $Dest\data." }
