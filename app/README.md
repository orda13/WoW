# Leveling Ledger (local edition)

Your Leveling Ledger, running on your own PC as a Windows service.

- **Add-on import is automatic.** The service watches `WTF\Account\<account>\SavedVariables\LevelingLedger.lua`. Each time you log out or `/reload`, it imports the new data within a few seconds, and any open ledger page updates by itself.
- **Blizzard sync runs here.** It runs at start-up, every 6 hours, and about 1 and 6 minutes after each play session (Blizzard updates your character shortly after you log out). The **Sync from Blizzard** button runs it right away.
- **Your data stays on your PC** in `C:\LevelingLedger\data\store.json`. A copy of the previous version is kept next to it as `store.json.bak`, and a daily backup goes into `data\backups` (the last 14 days). The **Backups** section on the Ledger page lists them, with Download and Restore; a restore saves your current data first, so it can be undone.
- **From your phone or another computer**, use Cloudflare Tunnel with Google sign-in (Part 2). Nothing is opened on your router.
- **Alts:** add other characters on the **Settings** tab, one per line, as Blizzard spells them (for example `bob-smith`).
  - Each gets its own ledger, synced from Blizzard and fed from the same add-on file. Switch between them with the menu under the name.
  - Removing a character keeps its data, so adding it back restores it.

Nothing needs installing besides Node.js 18 or newer (you have it already).

---

## Part 1: Install on your PC (about 5 minutes)

1. Get the files: clone https://github.com/orda13/wow, or download it as a ZIP from GitHub and unzip it, then open the `app` folder.
2. Open PowerShell in that folder (in File Explorer: **File > Open Windows PowerShell**, or right-click with Shift held) and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
   ```

   Windows asks for administrator rights. The installer then:
   - copies the app to `C:\LevelingLedger`
   - asks for your Blizzard **Client ID** and **Client secret** (from https://develop.battle.net/access/clients; the same pair you gave the claude.ai version)
   - asks where World of Warcraft is installed (it suggests what it finds)
   - downloads NSSM, a small tool that runs Node.js as a service
   - creates the **Leveling Ledger** service. It starts with Windows and runs under the built-in *Local Service* account, which has very few rights.
   - opens http://localhost:8787

3. On a fresh install the first Blizzard sync runs about 15 seconds after start-up and fills in your character. To carry over data from somewhere else, put it in `data\seed.json` before the first start; it's only read when there's no data yet.

**To update later:** open **Settings → Updates** and press **Update now**. The service checks GitHub every 6 hours, and the health line shows **Update available** when there's something new.
- The update downloads the new version, checks it, keeps the current one, installs the new files and restarts the service. This takes a few seconds, and the page reloads itself.
- If the add-on is in your game's AddOns folder, it's updated too; type `/reload` in game.
- **Undo last update** goes back.
- Your data and settings are never touched.
- Updates replace only the app's program files and the add-on. The install scripts only change when you run them yourself.

You can still update by hand: pull or download the new version and run the install command again. Do this once to move from a version without one-click updates.

**To remove:** run `scripts\uninstall.ps1`. Your data stays in `C:\LevelingLedger\data` unless you add `-RemoveFiles`.

**Settings:** use the **Settings** tab on the page. Changes take effect right away, with no restart.
- You can change your Blizzard keys, character, sync interval, WoW folder, how many backups to keep, and the Cloudflare sign-in settings.
- The Blizzard secret is never shown again once saved.
- The Cloudflare sign-in settings can only be changed on this PC, not from your phone.

Settings are stored in `C:\LevelingLedger\config.json`. Only your Windows account, administrators and the service can open it. You can still edit it in Notepad; run `Restart-Service LevelingLedger` in an administrator PowerShell afterwards. The port can only be changed there.

| Setting | What it does |
|---|---|
| `port` | Local port (default 8787) |
| `wowFolder` | The World of Warcraft folder. All `_xxx_` versions and accounts inside are checked |
| `savedVariablesFile` | Optional: the exact path to one `LevelingLedger.lua` instead |
| `syncEveryHours` | How often to check Blizzard (default 6) |
| `backupDays` | How many daily backups to keep in `data\backups` (default 14) |
| `blizzard.character` | Character as Blizzard spells it (`talwyn-orda`) |
| `access.*` | Cloudflare sign-in settings, from Part 2 |

**Logs:** `C:\LevelingLedger\logs\service.log`. Each import and sync gets one line.

---

## Part 2: Reach it from anywhere with Google sign-in (about 20 minutes)

You need:
- a free Cloudflare account
- a domain whose DNS is on Cloudflare (any cheap domain works; Cloudflare sells them at cost)
- a Google account

Cloudflare's dashboard changes now and then, so menu names may differ slightly from these.

### A. Pick your Cloudflare Zero Trust team name
1. Go to https://one.dash.cloudflare.com and choose the free plan.
2. Pick a **team name**, for example `talwyn`. Your team domain becomes `talwyn.cloudflareaccess.com`.

### B. Create the Google sign-in
1. Go to https://console.cloud.google.com and create a project (any name).
2. Go to **APIs & Services > OAuth consent screen**.
   - Choose **External**, give the app a name, and add your email.
   - Under **Test users**, add your Gmail address. Leaving the app in "Testing" is fine for personal use.
3. Go to **APIs & Services > Credentials > Create credentials > OAuth client ID**.
   - Type: **Web application**
   - Authorized JavaScript origins: `https://<team>.cloudflareaccess.com`
   - Authorized redirect URIs: `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`
4. Copy the **Client ID** and **Client secret**.

### C. Connect Google to Cloudflare
1. In Zero Trust, go to **Settings > Authentication > Login methods > Add new > Google**.
2. Paste the Client ID and secret, save, then press **Test** and sign in.

### D. Create the tunnel
1. In an administrator PowerShell, install cloudflared:
   ```powershell
   winget install --id Cloudflare.cloudflared
   ```
2. In Zero Trust, go to **Networks > Tunnels > Create a tunnel > Cloudflared**. Name it `leveling-ledger` and choose **Windows**.
3. Copy the command it shows, which looks like `cloudflared.exe service install eyJ...`, and run it in the administrator PowerShell. cloudflared is now a Windows service too.
4. Add a **Public hostname**:
   - Subdomain: `ledger`
   - Domain: yours
   - Service: **HTTP**, `localhost:8787`

### E. Put Google sign-in in front of it
1. Go to **Access > Applications > Add an application > Self-hosted**.
   - Name: Leveling Ledger
   - Domain: `ledger.<your domain>`
   - Session duration: whatever you like (for example 1 month)
   - Identity providers: tick only **Google**, and turn on **Instant Auth**
2. Add a policy:
   - Action: **Allow**
   - Include: **Emails**, with your Gmail address
3. Save. Open the application again and copy its **Application Audience (AUD) Tag**.

### F. Tell the ledger to check the sign-in
1. On this PC, open the ledger's **Settings** tab and fill in **Remote access**: the team domain, the AUD tag and your Gmail address, then **Save settings**. It takes effect immediately. Or put the same values in `C:\LevelingLedger\config.json`:
   ```json
   "access": {
     "teamDomain": "<team>.cloudflareaccess.com",
     "aud": "<the AUD tag>",
     "allowedEmails": ["<your gmail address>"]
   }
   ```
2. If you edited `config.json` by hand, run `Restart-Service LevelingLedger` in an administrator PowerShell.
3. Open `https://ledger.<your domain>` on your phone. Sign in with Google, and the ledger opens.

**How it stays private:**
- The service only listens on this PC. Cloudflare can reach it only through the tunnel, which starts on your PC and connects out.
- Cloudflare asks for Google sign-in before anything reaches your PC.
- The ledger then checks Cloudflare's signed token itself: the right team, the right application, an allowed email, and not expired. So even a mistake in the Cloudflare policy won't let anyone else in.
- Until the `access` settings are filled in, any visit through Cloudflare is refused.

---

## Part 3: Other PCs and the Steam Deck (about 10 minutes each)

WoW keeps the add-on's file on each computer separately. A small **relay** on each other PC or Steam Deck sends that device's file to your hub through your Cloudflare address, every time the game saves.
- The hub combines everything:
  - sessions and quests from every device
  - loot counts added together
  - for skills, reputation, rested XP and vendor prices, whichever device saved last
- If the hub can't be reached, for example when the Deck is travelling, the relay keeps trying and sends the file once it can.

You need Part 2 (Cloudflare) done first.

### A. Make a service token for each device (once per device, in Cloudflare)
1. In Zero Trust, go to **Access > Service Auth > Service Tokens > Create Service Token**.
   - Name it after the device, for example `steam-deck`.
   - Choose **Non-expiring**, or a long duration.
2. Copy the **Client ID** and **Client Secret**. The secret is only shown once.
3. Go to **Access > Applications > Leveling Ledger > Policies > Add a policy**:
   - Action: **Service Auth**
   - Include: **Service Token**, and pick your device tokens
   - Save.
4. On the hub, open the ledger's **Settings** tab and paste each token's **Client ID** into **Devices allowed to send add-on data** (one per line). Save.
   - A device token can only send add-on data. It can't read your ledger or change anything.
   - To cut a device off, remove its line, or revoke the token in Cloudflare.

### B. A second Windows PC
1. Install the add-on there as usual (`addon\LevelingLedger` into `Interface\AddOns`), and Node.js from https://nodejs.org.
2. Download the project and open its `app` folder in PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\install-relay.ps1
   ```

   It asks for:
   - your hub address (`https://ledger.<your domain>`)
   - the token's Client ID and Secret
   - a name for the PC
   - the WoW folder

   It then checks the connection and starts the **Leveling Ledger relay** service. The log is in `C:\LevelingLedgerRelay\logs\relay.log`.

### C. The Steam Deck
1. Switch to **Desktop Mode**. In Firefox, download the project from GitHub as a ZIP and extract it, for example into `Downloads`.
2. Install the add-on: copy `addon/LevelingLedger` into WoW's `Interface/AddOns` folder. On the Deck that's inside Steam's Proton folder for the game, something like
   `~/.local/share/Steam/steamapps/compatdata/<number>/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns`.
3. Open **Konsole** in the project's `app` folder and run:

   ```bash
   bash scripts/install-relay.sh
   ```

   - It asks the same questions as on Windows.
   - It finds WoW inside Proton, Lutris or Bottles by itself.
   - If needed, it downloads Node.js into your home folder and checks it against nodejs.org's published checksums.
   - It installs the relay as a user service that starts with the Deck, in Game Mode too.
   - Nothing outside your home folder changes, and no password is needed.
4. Check it any time with `systemctl --user status leveling-ledger-relay`.

**Relays update themselves.** After you update the hub (**Settings → Updates**), each relay notices within 15 minutes and then:
- Downloads the matching relay and add-on files from the hub, and checks them.
- Installs its own files and restarts.
- Installs the add-on files once WoW is closed on that device, so a running game is never changed underneath you.

If an update ever leaves a relay unable to start, it goes back to the previous version by itself after three tries. It then waits for the next version.

To turn this off on a device, add `"autoUpdate": false` to its `relay.json`.

Running the relay installer again still works, for example to change settings. Relays installed before self-updating existed need it once.

**Your other devices on the hub:** the hub's Settings tab lists each device and when it last sent data.

**In game on every device:** the hub and each relay also keep `Shared.lua` in the add-on's folder up to date. It holds every character's level, gold, location, bags and bank, from all your devices and accounts.
- Item tooltips, `/ledger alts` and the profession window's "with your alts' materials" use it, so your Deck knows what your desktop alts are holding.
- For each character, whichever is newer is used: this device's own record or the summary.
- The game reads the file at login and on `/reload`.
- The first time after this update, exit and restart the game once (a `/reload` isn't enough for a new add-on file).

## Troubleshooting

- **"Couldn't find LevelingLedger.lua yet":** log out of the game or `/reload` once with the add-on enabled. If the game is somewhere unusual, set its folder on the **Settings** tab. The service rescans every 5 minutes.
- **"The service isn't allowed to save config.json yet":** run `app\scripts\install.ps1` once more; it gives the service permission to save settings.
- **Sync says Blizzard sign-in failed:** re-enter the keys on the **Settings** tab and press **Save and check Blizzard now**.
- **The service won't start:** look in `logs\service.log`.
  - If Node.js was installed only for your user, reinstall it for all users from https://nodejs.org.
- **Run it without the service** (for testing): in `C:\LevelingLedger`, run `node server.js`. Stop the service first (`Stop-Service LevelingLedger`) so the port is free.
