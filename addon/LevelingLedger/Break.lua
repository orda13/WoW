-- Water breaks: every so often (an hour by default) a reminder to drink some water and /reload,
-- which also saves the ledger so the app gets your progress. Never during a fight.
--   /ledger water          when the next one is
--   /ledger water 45       every 45 minutes (10 to 240)
--   /ledger water off      no reminders (/ledger water on brings them back)
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local SNOOZE = 15 * 60       -- "Later" asks again in 15 minutes
local AWAY = 10 * 60         -- logged out this long counts as a break already
local B                      -- LevelingLedgerDB.breaks: { every = minutes or 0, next, since (this stretch began), shownAt, alive }
local pending = false        -- due, waiting for the fight to end

local function now() return time() end
local function every() return (B and B.every or 60) * 60 end
local function due() return B and B.every ~= 0 and B.next and now() >= B.next end
local function mins(s)
  s = math.max(0, math.floor(s / 60 + 0.5))
  local h, m = math.floor(s / 60), s % 60
  local hp = h == 1 and "1 hour" or h .. " hours"
  local mp = m == 1 and "1 minute" or m .. " minutes"
  if h == 0 then return mp elseif m == 0 then return hp else return hp .. " " .. mp end
end

local MSG = "Water break!\n\nYou've been playing for %s. Drink a glass of water, stretch a bit, and /reload to save your Leveling Ledger."
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["LEVELINGLEDGER_WATER"] = {
  text = MSG, button1 = "Reload now", button2 = "Later",
  OnAccept = function() if B then B.since = now() end if ReloadUI then ReloadUI() end end,
  OnCancel = function() if B then B.next = now() + SNOOZE end end,
  timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

local function remind()
  pending = false
  local played = mins(now() - (B.since or now()))
  B.shownAt = now(); B.next = now() + every()  -- "Later" moves this up to 15 minutes from now
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, "Water break! Drink some water, then /reload to save.", ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 0.4, g = 0.8, b = 1 })
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
  print(TAG .. "|cff66ccffwater break!|r Drink some water, then type /reload to save your ledger.")
  if StaticPopup_Show then StaticPopup_Show("LEVELINGLEDGER_WATER", played) end
end

local function check()
  if not B then return end
  B.alive = now()
  if not due() or pending then return end
  if InCombatLockdown and InCombatLockdown() or UnitAffectingCombat and UnitAffectingCombat("player") then pending = true return end
  remind()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    LevelingLedgerDB = LevelingLedgerDB or {}
    LevelingLedgerDB.breaks = LevelingLedgerDB.breaks or { every = 60 }
    B = LevelingLedgerDB.breaks
    -- a /reload keeps the clock running; coming back after time away, or reloading right after a reminder, starts it fresh
    if not B.alive or now() - B.alive > AWAY or not B.next then B.since = now(); B.next = now() + every()
    elseif B.shownAt and now() - B.shownAt < 5 * 60 then B.since = now(); B.next = now() + every(); B.shownAt = nil end
    B.alive = now()
  elseif event == "PLAYER_REGEN_ENABLED" and pending then
    pending = false; check()
  end
end)
local acc = 0
f:SetScript("OnUpdate", function(_, dt) acc = acc + (dt or 0); if acc >= 15 then acc = 0; check() end end)

-- /ledger water ...
function ns.waterCommand(arg)
  if not B then print(TAG .. "not ready yet.") return end
  arg = (arg or ""):match("^%s*(.-)%s*$")
  local n = tonumber(arg)
  if arg == "off" then B.every = 0; print(TAG .. "water break reminders are off. /ledger water on turns them back on.")
  elseif arg == "on" then if B.every == 0 then B.every = 60 end; B.next = now() + every(); print(TAG .. "water breaks every " .. mins(every()) .. ".")
  elseif arg == "now" then remind()
  elseif n then
    n = math.floor(math.max(10, math.min(240, n))); B.every = n; B.next = now() + every()
    print(TAG .. "water breaks every " .. mins(every()) .. ".")
  elseif B.every == 0 then print(TAG .. "water break reminders are off. /ledger water on turns them back on.")
  else print(TAG .. "next water break in " .. mins((B.next or now()) - now()) .. " (every " .. mins(every()) .. "). /ledger water 45 changes it, /ledger water off stops them.") end
end
ns.water = function() return B end
