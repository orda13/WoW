# Installs (or updates) the Leveling Ledger relay on another Windows PC: it sends this PC's add-on file to your hub.
# Run from the downloaded project's app folder:  powershell -ExecutionPolicy Bypass -File .\scripts\install-relay.ps1
# Running it again keeps the saved settings, after asking whether to change them; -Reconfigure asks straight away.
param(
  [string]$Dest = "C:\LevelingLedgerRelay",
  [string]$ServiceName = "LevelingLedgerRelay",
  [switch]$Reconfigure
)
$ErrorActionPreference = "Stop"

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Write-Host "Asking for administrator rights to install the relay service..."
  $more = if ($Reconfigure) { " -Reconfigure" } else { "" }
  Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Dest `"$Dest`" -ServiceName `"$ServiceName`"$more"
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
# Service token values: only visible ASCII. A paste into a hidden prompt can add invisible characters (Ctrl+V typed as a
# control character, a line break), which make every request fail with "invalid CF-Access-Client-Secret header".
function Clean-Token([string]$s) {
  if ($null -eq $s) { return "" }
  $s = $s -replace '[^\x21-\x7E]', ''
  # a copied header line ("CF-Access-Client-Secret: ...", or a quoted value) still holds the value: keep just the value
  $s = $s -replace '^(?i)(CF-Access-Client-(Id|Secret)|Client(Id|Secret)|Secret|Id)[:=]', ''
  return $s.Trim('"', "'", ',', ';')
}
function Describe-Bad([string]$v) {
  $odd = ($v.ToCharArray() | Where-Object { $_ -notmatch '[A-Za-z0-9.]' } | Select-Object -Unique) -join ' '
  if ($odd) { return "$($v.Length) characters, including: $odd" } else { return "$($v.Length) characters" }
}
function Read-ClientId {
  while ($true) {
    $v = Clean-Token (Read-Host "  Service token Client ID (ends in .access)")
    if ($v -match '^[A-Za-z0-9]+\.access$') { return $v }
    Write-Host "  That doesn't look like a Client ID ($(Describe-Bad $v)): it's letters and digits ending in .access. Paste just that." -ForegroundColor Yellow
  }
}
function Read-ClientSecret {
  $tries = 0
  while ($true) {
    $tries++
    if ($tries -le 2) {
      $sec = Read-Host "  Service token Client Secret (hidden; paste with right-click)" -AsSecureString
      $v = Clean-Token ([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)))
    } else {
      # hidden prompts don't always take a paste: let it show this time (it's your own screen)
      $v = Clean-Token (Read-Host "  Service token Client Secret (shown as you paste it)")
    }
    if ($v -match '^[A-Za-z0-9]{32,}$') { return $v }
    Write-Host "  That doesn't look like a Client Secret ($(Describe-Bad $v)). It's one long string of letters and digits, about 64 characters; copy just that." -ForegroundColor Yellow
  }
}
# Asks for every setting; with saved ones, Enter keeps each (the secret is never shown)
function Ask-Settings($cur) {
  Write-Host ""
  Write-Host "Your hub's Cloudflare address, and the service token you made for this PC (README: Other PCs and the Steam Deck)."
  if ($cur) { Write-Host "Press Enter to keep what's in [brackets]." }
  $h0 = if ($cur) { $cur.hubUrl } else { "" }
  $hub = Read-Host ("  Hub address (like https://ledger.example.com)" + $(if ($h0) { " [$h0]" } else { "" }))
  if (-not $hub) { $hub = $h0 }
  $cid = $null
  if ($cur -and $cur.clientId) {
    $v = Clean-Token (Read-Host "  Service token Client ID (ends in .access) [$($cur.clientId)]")
    if (-not $v) { $cid = $cur.clientId } elseif ($v -match '^[A-Za-z0-9]+\.access$') { $cid = $v } else { Write-Host "  That doesn't look like a Client ID." -ForegroundColor Yellow }
  }
  if (-not $cid) { $cid = Read-ClientId }
  $sec = $null
  if ($cur -and $cur.clientSecret) {
    $k = Read-Host "  Keep the saved Client Secret? [Y/n]"
    if ($k -notmatch '^[nN]') { $sec = $cur.clientSecret }
  }
  if (-not $sec) { $sec = Read-ClientSecret }
  $d0 = if ($cur -and $cur.device) { $cur.device } else { $env:COMPUTERNAME }
  $dev = Read-Host "  Name for this PC [$d0]"
  if (-not $dev) { $dev = $d0 }
  $guess = if ($cur -and $cur.wowFolder) { $cur.wowFolder } else { @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft", "D:\Games\World of Warcraft") | Where-Object { Test-Path $_ } | Select-Object -First 1 }
  if (-not $guess) { $guess = "C:\Program Files (x86)\World of Warcraft" }
  $wow = Read-Host "  World of Warcraft folder, the one with _forever_ in it [$guess]"
  if (-not $wow) { $wow = $guess }
  $out = [ordered]@{ hubUrl = $hub.Trim().TrimEnd("/"); clientId = $cid.Trim(); clientSecret = $sec.Trim(); device = $dev; wowFolder = $wow }
  if ($cur) { foreach ($p in $cur.PSObject.Properties) { if (-not $out.Contains($p.Name)) { $out[$p.Name] = $p.Value } } } # keep anything else (autoUpdate)
  [IO.File]::WriteAllText($cfgPath, ($out | ConvertTo-Json -Depth 3))
  return $out
}

if (-not (Test-Path $cfgPath)) {
  $cfg = Ask-Settings $null
} else {
  $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
  Write-Host ""
  Write-Host "Saved relay settings in ${cfgPath}:"
  Write-Host "  Hub address:      $($cfg.hubUrl)"
  Write-Host "  Client ID:        $($cfg.clientId)"
  Write-Host "  Client Secret:    $(if ($cfg.clientSecret) { '(saved, hidden)' } else { '(none)' })"
  Write-Host "  Name for this PC: $($cfg.device)"
  Write-Host "  WoW folder:       $($cfg.wowFolder)"
  $change = $Reconfigure
  if (-not $change) { $a = Read-Host "Change any of these (for example a new service token)? [y/N]"; $change = $a -match '^[yY]' }
  if ($change) { $cfg = Ask-Settings $cfg }
  else {
    # repair a token saved with invisible characters, or ask again when it can't be right
    $fixed = $false
    $id = Clean-Token $cfg.clientId; $sc = Clean-Token $cfg.clientSecret
    if ($id -ne $cfg.clientId -or $sc -ne $cfg.clientSecret) { $fixed = $true; Write-Host "  Removed invisible characters from the saved service token." -ForegroundColor Yellow }
    if ($id -notmatch '^[A-Za-z0-9]+\.access$') { Write-Host "  The saved Client ID doesn't look right; enter it again." -ForegroundColor Yellow; $id = Read-ClientId; $fixed = $true }
    if ($sc -notmatch '^[A-Za-z0-9]{32,}$') { Write-Host "  The saved Client Secret doesn't look right; enter it again." -ForegroundColor Yellow; $sc = Read-ClientSecret; $fixed = $true }
    if ($fixed) {
      $cfg.clientId = $id; $cfg.clientSecret = $sc
      [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 3))
    }
  }
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
