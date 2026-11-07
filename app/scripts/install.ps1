# Installs (or updates) Leveling Ledger as a Windows service.
# Run from the unzipped folder in PowerShell:  powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
param(
  [string]$Dest = "C:\LevelingLedger",
  [string]$ServiceName = "LevelingLedger"
)
$ErrorActionPreference = "Stop"

# --- run as administrator ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Write-Host "Asking for administrator rights to install the service..."
  Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Dest `"$Dest`" -ServiceName `"$ServiceName`""
  exit
}
$Src = Split-Path -Parent $PSScriptRoot

# --- Node.js ---
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw "Node.js wasn't found. Install it from https://nodejs.org (LTS) and run this again." }
$ver = (& $node -v).TrimStart("v").Split(".")[0]
if ([int]$ver -lt 18) { throw "Node.js $(& $node -v) is too old. Version 18 or newer is needed." }
if ($node -like "$env:USERPROFILE*") {
  Write-Warning "Node.js is installed inside your user folder ($node). The service may not be able to run it. If the service doesn't start, install Node.js for all users from https://nodejs.org."
}
Write-Host "Node.js: $node ($(& $node -v))"

# --- stop an existing service while files are replaced ---
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing -and $existing.Status -ne "Stopped") { Write-Host "Stopping the running service..."; Stop-Service $ServiceName -Force; Start-Sleep 2 }

# --- copy the app (your data and settings are kept) ---
New-Item -ItemType Directory -Force -Path $Dest, "$Dest\data", "$Dest\logs", "$Dest\tools" | Out-Null
if ((Resolve-Path $Src).Path.TrimEnd("\") -ne (Resolve-Path $Dest).Path.TrimEnd("\")) {
  foreach ($f in @("server.js", "relay.js", "package.json", "config.example.json", "README.md")) { Copy-Item (Join-Path $Src $f) $Dest -Force }
  foreach ($d in @("lib", "public", "scripts")) {
    New-Item -ItemType Directory -Force -Path "$Dest\$d" | Out-Null
    Copy-Item -Path (Join-Path $Src "$d\*") -Destination "$Dest\$d" -Recurse -Force
  }
}
if (-not (Test-Path "$Dest\data\store.json") -and (Test-Path "$Src\data\seed.json")) {
  Copy-Item "$Src\data\seed.json" "$Dest\data\seed.json" -Force
  Write-Host "Your existing ledger data will be loaded on first start."
}

# --- settings ---
$cfgPath = "$Dest\config.json"
if (-not (Test-Path $cfgPath)) {
  $cfg = Get-Content "$Dest\config.example.json" -Raw | ConvertFrom-Json
  Write-Host ""
  Write-Host "Blizzard API keys (from https://develop.battle.net/access/clients). Press Enter to skip for now."
  $cfg.blizzard.clientId = Read-Host "  Client ID"
  $sec = Read-Host "  Client secret" -AsSecureString
  $cfg.blizzard.clientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  $guess = @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft", "D:\Games\World of Warcraft") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $guess) { $guess = "C:\Program Files (x86)\World of Warcraft" }
  $wow = Read-Host "  World of Warcraft folder [$guess]"
  if (-not $wow) { $wow = $guess }
  $cfg.wowFolder = $wow
  # UTF-8 without a byte-order mark
  [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 5))
  Write-Host "Saved settings to $cfgPath"
} else {
  $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
  Write-Host "Keeping your existing settings in $cfgPath"
}

# --- permissions: the service runs as the built-in Local Service account, with only what it needs ---
$svcAcct = "NT AUTHORITY\LocalService"
icacls "$Dest\data" /grant "${svcAcct}:(OI)(CI)M" /T /Q | Out-Null
icacls "$Dest\logs" /grant "${svcAcct}:(OI)(CI)M" /T /Q | Out-Null
# settings hold your Blizzard secret: only you, administrators, the system and the service can open them
# (the service may also change them, for the Settings tab)
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls $cfgPath /inheritance:r /grant:r "Administrators:F" "SYSTEM:F" "${me}:M" "${svcAcct}:M" /Q | Out-Null
Write-Host "You ($me) can edit $cfgPath in Notepad without administrator rights."
# let the service read the add-on's saved files
if ($cfg.wowFolder -and (Test-Path $cfg.wowFolder)) {
  Get-ChildItem $cfg.wowFolder -Directory -Filter "_*" -ErrorAction SilentlyContinue | ForEach-Object {
    $wtf = Join-Path $_.FullName "WTF"
    if (Test-Path $wtf) { icacls $wtf /grant "${svcAcct}:(OI)(CI)RX" /Q | Out-Null; Write-Host "Allowed the service to read $wtf" }
  }
} else { Write-Warning "World of Warcraft folder not found ($($cfg.wowFolder)). Fix wowFolder in $cfgPath, then run this again." }

# --- one-click updates: the service may replace its own program files (never the install scripts) ---
foreach ($d in @("lib", "public")) { icacls "$Dest\$d" /grant "${svcAcct}:(OI)(CI)M" /T /Q | Out-Null }
foreach ($f in @("server.js", "relay.js", "package.json", "README.md", "config.example.json")) { if (Test-Path "$Dest\$f") { icacls "$Dest\$f" /grant "${svcAcct}:M" /Q | Out-Null } }
# record which version this is, when installing from a git clone (a ZIP download is recorded on the first one-click update)
$repoRoot = Split-Path -Parent $Src
$sha = $null
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $repoRoot ".git"))) { $sha = (& git -C $repoRoot rev-parse HEAD 2>$null) }
if ($sha -match '^[0-9a-f]{40}$') {
  $ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  [IO.File]::WriteAllText("$Dest\data\installed.json", "{""sha"":""$sha"",""at"":$ms,""message"":""Installed with install.ps1""}")
  Write-Host "Installed version $($sha.Substring(0, 7))"
} elseif (Test-Path "$Dest\data\installed.json") { Remove-Item "$Dest\data\installed.json" -Force }
# the add-on: refresh it wherever it's already installed, and let the service update it
$addonSrc = Join-Path $repoRoot "addon\LevelingLedger"
if ($cfg.wowFolder -and (Test-Path $cfg.wowFolder)) {
  Get-ChildItem $cfg.wowFolder -Directory -Filter "_*" -ErrorAction SilentlyContinue | ForEach-Object {
    $ad = Join-Path $_.FullName "Interface\AddOns\LevelingLedger"
    if (Test-Path (Join-Path $ad "LevelingLedger.toc")) {
      if (Test-Path $addonSrc) { Copy-Item -Path "$addonSrc\*" -Destination $ad -Recurse -Force; Write-Host "Updated the add-on in $ad" }
      icacls $ad /grant "${svcAcct}:(OI)(CI)M" /T /Q | Out-Null
    }
  }
}

# --- NSSM (runs Node.js as a Windows service) ---
$nssm = "$Dest\tools\nssm.exe"
if (-not (Test-Path $nssm)) {
  Write-Host "Downloading NSSM (the service helper)..."
  $zip = Join-Path $env:TEMP "nssm-2.24.zip"
  try {
    Invoke-WebRequest "https://nssm.cc/release/nssm-2.24.zip" -OutFile $zip -UseBasicParsing
    $x = Join-Path $env:TEMP "nssm-2.24"; Expand-Archive $zip -DestinationPath $env:TEMP -Force
    Copy-Item "$x\win64\nssm.exe" $nssm -Force
  } catch {
    Write-Host "Download failed; trying winget..."
    winget install -e --id NSSM.NSSM --accept-source-agreements --accept-package-agreements | Out-Null
    $found = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter nssm.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "win64" } | Select-Object -First 1
    if (-not $found) { throw "Couldn't get NSSM. Download nssm-2.24.zip from https://nssm.cc, put win64\nssm.exe in $Dest\tools, and run this again." }
    Copy-Item $found.FullName $nssm -Force
  }
}

# --- create or update the service ---
if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
  & $nssm install $ServiceName $node "`"$Dest\server.js`"" | Out-Null
}
& $nssm set $ServiceName Application $node | Out-Null
& $nssm set $ServiceName AppParameters "`"$Dest\server.js`"" | Out-Null
& $nssm set $ServiceName AppDirectory $Dest | Out-Null
& $nssm set $ServiceName DisplayName "Leveling Ledger" | Out-Null
& $nssm set $ServiceName Description "Leveling Ledger for WoW Forever: imports the add-on's data and syncs from Blizzard." | Out-Null
& $nssm set $ServiceName Start SERVICE_AUTO_START | Out-Null
& $nssm set $ServiceName AppStdout "$Dest\logs\service.log" | Out-Null
& $nssm set $ServiceName AppStderr "$Dest\logs\service.log" | Out-Null
& $nssm set $ServiceName AppRotateFiles 1 | Out-Null
& $nssm set $ServiceName AppRotateBytes 1048576 | Out-Null
& $nssm set $ServiceName AppExit Default Restart | Out-Null

# run as the built-in Local Service account (no password, few rights)
sc.exe config $ServiceName obj= "NT AUTHORITY\LocalService" password= "" | Out-Null
Start-Service $ServiceName
Start-Sleep 3
$port = if ($cfg.port) { $cfg.port } else { 8787 }
try {
  $st = Invoke-RestMethod "http://localhost:$port/api/status" -TimeoutSec 10
  Write-Host ""
  Write-Host "Leveling Ledger is running at http://localhost:$port" -ForegroundColor Green
  if ($st.files.Count) { $st.files | ForEach-Object { Write-Host "  Watching $_" } } else { Write-Host "  $($st.lastError)" -ForegroundColor Yellow }
  Start-Process "http://localhost:$port"
} catch {
  Write-Warning "The service didn't answer yet. Check $Dest\logs\service.log"
}
