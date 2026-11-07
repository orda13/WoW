# Leveling Ledger

A leveling companion for **World of Warcraft: Forever**. It tracks play sessions, XP per hour, quests by zone and chain, gear upgrades, dungeons, professions, collectables and talents. It runs on your own PC as a Windows service, and you can reach it from anywhere through Cloudflare with Google sign-in.

| Folder | What it is |
|---|---|
| [`app/`](app/) | The web app and Windows service: a Node.js server with no npm dependencies, plus the page and its game data. Installing it and setting up remote access are covered in [`app/README.md`](app/README.md). |
| [`addon/LevelingLedger/`](addon/LevelingLedger/) | The in-game add-on. It records sessions with exact XP, kills, gold, reputation and profession skill-ups, plus rested XP and zone, trainer costs, vendor and Merchant's Favor prices, loot and quest turn-ins to SavedVariables, and the app imports them automatically. It also shows a small panel in game (`/ledger show`, `hide`, `lock`, `unlock`, `reset`). Bags, bank and gold are recorded per character. Item tooltips show which of your other characters hold an item, `/ledger alts` opens a window with each character's details, bags and bank, and the profession window says what your alts' materials would let you make. In game this covers characters on the same WoW account; the page combines all accounts. |
| [`tools/`](tools/) | The scripts that built the game data in `app/public/*.json`, and a simulator that tests the add-on outside the game. |

## How the pieces fit

1. **In game**, the add-on records what you do. When you log out or `/reload`, the game writes `WTF\Account\<account>\SavedVariables\LevelingLedger.lua`.
2. **On your PC**, the Leveling Ledger service sees that file change and imports it within a few seconds. It also syncs your character from Blizzard's API at startup, every 6 hours and after each play session.
3. **In the browser**, the page at `http://localhost:8787` (or your Cloudflare address) updates live.

## Install

- **App:** download this repository, then follow [`app/README.md`](app/README.md). In short:

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\app\scripts\install.ps1
  ```

  After that, updates are one click: **Settings → Updates → Update now**. That updates the app and the add-on, and it can be undone. Your data and settings in `C:\LevelingLedger` are kept.
- **Add-on:** copy `addon/LevelingLedger` into your Forever game folder's `Interface\AddOns`, then enable it at character select.

## What is never committed

`.gitignore` keeps these out of the repository:
- `config.json`, which holds your Blizzard secret and sign-in settings
- your ledger data and logs
- the downloaded NSSM helper

This repository is public, so keep it that way.

## Roadmap

Planned changes are tracked in the Leveling Ledger Roadmap doc.
