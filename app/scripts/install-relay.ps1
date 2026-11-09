# Installs (or updates) the Leveling Ledger relay on another Windows PC: it sends this PC's add-on file to your hub.
# Run from the downloaded project's app folder:  powershell -ExecutionPolicy Bypass -File .\scripts\install-relay.ps1
param(
  [string]$Dest = "C:\LevelingLedgerRelay",
  [string]$ServiceName = "LevelingLedgerRelay"
)
$ErrorActionPreference = "Stop"

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Write-Host "Asking for administrator rights to install the relay service..."
  Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Dest `"$Dest`" -ServiceName `"$ServiceName`""
  exit
}
$Src = Split-Path -Parent $PSScriptRoot

# --- Node.js ---
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw "Node.js wasn't found. Install it from https://nodejs.org (LTS, for all users) and run this again." }
$ver = (& $node -v).TrimStart("v").Split(".")[0]
if ([int]$ver -lt 18) { throw "Node.js $(& $node -v) is too old. Version 18 or newer is needed." }

# --- stop a running relay while files are replaced ---
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing -and $existing.Status -ne "Stopped") { Stop-Service $ServiceName -Force; Start-Sleep 2 }

# --- copy the relay (it reuses a few files from the app's lib folder) ---
New-Item -ItemType Directory -Force -Path $Dest, "$Dest\lib", "$Dest\data", "$Dest\logs", "$Dest\tools" | Out-Null
Copy-Item (Join-Path $Src "relay.js") $Dest -Force
Copy-Item (Join-Path $Src "relay-boot.js") $Dest -Force
Copy-Item -Path (Join-Path $Src "lib\*") -Destination "$Dest\lib" -Recurse -Force

# --- settings ---
$cfgPath = "$Dest\relay.json"
if (-not (Test-Path $cfgPath)) {
  Write-Host ""
  Write-Host "Your hub's Cloudflare address, and the service token you made for this PC (README: Other PCs and the Steam Deck)."
  $hub = Read-Host "  Hub address (like https://ledger.example.com)"
  $cid = Read-Host "  Service token Client ID"
  $sec = Read-Host "  Service token Client Secret" -AsSecureString
  $secPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  $dev = Read-Host "  Name for this PC [$env:COMPUTERNAME]"
  if (-not $dev) { $dev = $env:COMPUTERNAME }
  $guess = @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft", "D:\Games\World of Warcraft") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $guess) { $guess = "C:\Program Files (x86)\World of Warcraft" }
  $wow = Read-Host "  World of Warcraft folder [$guess]"
  if (-not $wow) { $wow = $guess }
  $cfg = [ordered]@{ hubUrl = $hub.Trim(); clientId = $cid.Trim(); clientSecret = $secPlain.Trim(); device = $dev; wowFolder = $wow }
  [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 3))
} else {
  $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
  Write-Host "Keeping your existing relay settings in $cfgPath"
}

# --- permissions: the relay runs as Local Service; only you, administrators and it can read the token ---
$svcAcct = "NT AUTHORITY\LocalService"
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls $cfgPath /inheritance:r /grant:r "Administrators:F" "SYSTEM:F" "${me}:M" "${svcAcct}:R" /Q | Out-Null
icacls "$Dest\data" /grant "${svcAcct}:(OI)(CI)M" /T /Q | Out-Null
icacls "$Dest\logs" /grant "${svcAcct}:(OI)(CI)M" /T /Q | Out-Null
# the relay updates itself: it may replace relay.js and lib, never relay-boot.js (its starter) or these scripts
icacls "$Dest\relay.js" /grant "${svcAcct}:M" /Q | Out-Null
icacls "$Dest\lib" /grant "${svcAcct}:(OI)(CI)M" /T /Q | Out-Null
if ($cfg.wowFolder -and (Test-Path $cfg.wowFolder)) {
  Get-ChildItem $cfg.wowFolder -Directory -Filter "_*" -ErrorAction SilentlyContinue | ForEach-Object {
    $wtf = Join-Path $_.FullName "WTF"
    if (Test-Path $wtf) { icacls $wtf /grant "${svcAcct}:(OI)(CI)RX" /Q | Out-Null }
    # the relay writes the in-game summary (Shared.lua) into the add-on's folder
    $ad = Join-Path $_.FullName "Interface\AddOns\LevelingLedger"
    if (Test-Path $ad) { icacls $ad /grant "${svcAcct}:(OI)(CI)M" /T /Q | Out-Null }
  }
}

# --- NSSM, as for the hub ---
# NSSM 2.24's official zip, by its SHA-256: whichever source it comes from, any other file is refused.
# nssm.cc is often down (503), so: an nssm.exe you put next to this script, nssm.cc (twice), the Internet Archive's
# copy of the same file, then winget.
$NssmSha = "727D1E42275C605E0F04ABA98095C38A8E1E46DEF453CDFFCE42869428AA6743"
function Get-Nssm([string]$target) {
  $own = Join-Path $PSScriptRoot "nssm.exe"
  if (Test-Path $own) { Copy-Item $own $target -Force; Write-Host "Using the nssm.exe next to this script."; return }
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $zip = Join-Path $env:TEMP "nssm-2.24.zip"
  $urls = @("https://nssm.cc/release/nssm-2.24.zip", "https://nssm.cc/release/nssm-2.24.zip",
            "https://web.archive.org/web/2024id_/https://nssm.cc/release/nssm-2.24.zip")
  Write-Host "Downloading NSSM (the service helper)..."
  foreach ($u in $urls) {
    try {
      Remove-Item $zip -Force -ErrorAction SilentlyContinue
      Invoke-WebRequest $u -OutFile $zip -UseBasicParsing -TimeoutSec 90
      if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $NssmSha) { Write-Host "  $u sent a different file; not using it."; continue }
      $x = Join-Path $env:TEMP "nssm-2.24"
      Expand-Archive $zip -DestinationPath $env:TEMP -Force
      Copy-Item "$x\win64\nssm.exe" $target -Force
      Write-Host "  Got NSSM from $u (checked)."
      return
    } catch {
      Write-Host "  $u didn't work: $(($_.Exception.Message -split "`n")[0])"
      Start-Sleep -Seconds 3
    }
  }
  Write-Host "  Trying winget..."
  try { winget install -e --id NSSM.NSSM --accept-source-agreements --accept-package-agreements | Out-Null } catch { }
  $found = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter nssm.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "win64" } | Select-Object -First 1
  if ($found) { Copy-Item $found.FullName $target -Force; Write-Host "  Got NSSM from winget."; return }
  throw "Couldn't get NSSM. Download nssm-2.24.zip (from https://nssm.cc when it's up), take win64\nssm.exe out of it, put it in $PSScriptRoot, and run this again."
}
$nssm = "$Dest\tools\nssm.exe"
if (-not (Test-Path $nssm)) {
  $hubNssm = "C:\LevelingLedger\tools\nssm.exe"
  if (Test-Path $hubNssm) { Copy-Item $hubNssm $nssm }
  else { Get-Nssm $nssm }
}
if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) { & $nssm install $ServiceName $node "`"$Dest\relay-boot.js`"" | Out-Null }
& $nssm set $ServiceName Application $node | Out-Null
& $nssm set $ServiceName AppParameters "`"$Dest\relay-boot.js`"" | Out-Null
& $nssm set $ServiceName AppDirectory $Dest | Out-Null
& $nssm set $ServiceName AppEnvironmentExtra "LL_RELAY_CONFIG=$cfgPath" "LL_RELAY_STATE=$Dest\data\relay-state.json" | Out-Null
& $nssm set $ServiceName DisplayName "Leveling Ledger relay" | Out-Null
& $nssm set $ServiceName Description "Sends this PC's Leveling Ledger add-on data to your hub." | Out-Null
& $nssm set $ServiceName Start SERVICE_AUTO_START | Out-Null
& $nssm set $ServiceName AppStdout "$Dest\logs\relay.log" | Out-Null
& $nssm set $ServiceName AppStderr "$Dest\logs\relay.log" | Out-Null
& $nssm set $ServiceName AppRotateFiles 1 | Out-Null
& $nssm set $ServiceName AppRotateBytes 1048576 | Out-Null
& $nssm set $ServiceName AppExit Default Restart | Out-Null
sc.exe config $ServiceName obj= "NT AUTHORITY\LocalService" password= "" | Out-Null

Write-Host ""
Write-Host "Checking the connection to your hub..."
$env:LL_RELAY_CONFIG = $cfgPath; $env:LL_RELAY_STATE = "$Dest\data\relay-state.json"
& $node "$Dest\relay.js" --test
Start-Service $ServiceName
Write-Host ""
Write-Host "The relay is running. It sends this PC's add-on data whenever you log out or /reload. Log: $Dest\logs\relay.log" -ForegroundColor Green
