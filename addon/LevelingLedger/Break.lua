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

-- Its own small window, not Blizzard's StaticPopup: adding to StaticPopupDialogs taints Blizzard's popups
-- (release spirit, delete item, ...) and gets the add-on blamed for blocked actions.
local win
-- (the window holds a secure button, so it can't hide during a fight: that waits for the fight to end)
local hideAfterFight = false
local function later()
  if B then B.next = now() + SNOOZE end
  if not win then return end
  if InCombatLockdown and InCombatLockdown() then hideAfterFight = true else win:Hide() end
end
local function build()
  if win then return win end
  win = CreateFrame("Frame", "LevelingLedgerWater", UIParent, ns.BACKDROP_TEMPLATE)
  if ns.styleFrame then ns.styleFrame(win, 0.95) end
  win:SetSize(340, 132); win:SetPoint("TOP", UIParent, "TOP", 0, -140)
  win:SetFrameStrata("DIALOG"); win:SetClampedToScreen(true)
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -14); title:SetText("Water break!")
  win.text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  win.text:SetPoint("TOPLEFT", 16, -40); win.text:SetPoint("TOPRIGHT", -16, -40); win.text:SetJustifyH("CENTER")
  -- a secure /reload button: the game blocks ReloadUI from add-on code
  local ok = ns.secureReload and ns.secureReload(nil, win, "UIPanelButtonTemplate") or CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  ok:SetSize(120, 22); ok:SetPoint("BOTTOMRIGHT", win, "BOTTOM", -6, 14); ok:SetText("Reload now")
  ok:SetScript("PreClick", function() if B then B.since = now() end end)
  local no = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); no:SetSize(120, 22); no:SetPoint("BOTTOMLEFT", win, "BOTTOM", 6, 14); no:SetText("Later")
  no:SetScript("OnClick", later)
  win.ok, win.later = ok, no
  win:Hide()
  return win
end

local function remind()
  pending = false
  local played = mins(now() - (B.since or now()))
  B.shownAt = now(); B.next = now() + every()  -- "Later" moves this up to 15 minutes from now
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  print(TAG .. "|cff66ccffwater break!|r Drink some water, then type /reload to save your ledger.")
  local w = build()
  w.text:SetText("You've been playing for " .. played .. ".\nDrink a glass of water, stretch a bit,\nand reload to save your Leveling Ledger.")
  w:Show()
end

local function check()
  if not B then return end
  B.alive = now()
  if not due() or pending then return end
  if InCombatLockdown and InCombatLockdown() or UnitAffectingCombat and UnitAffectingCombat("player") then pending = true return end
  remind()
end

local f = CreateFrame("Frame")
if ns.listen then ns.listen(f, "PLAYER_LOGIN") else pcall(f.RegisterEvent, f, "PLAYER_LOGIN") end
if ns.listen then ns.listen(f, "PLAYER_REGEN_ENABLED") else pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED") end
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    LevelingLedgerDB = LevelingLedgerDB or {}
    LevelingLedgerDB.breaks = LevelingLedgerDB.breaks or { every = 60 }
    B = LevelingLedgerDB.breaks
    -- a /reload keeps the clock running; coming back after time away, or reloading right after a reminder, starts it fresh
    if not B.alive or now() - B.alive > AWAY or not B.next then B.since = now(); B.next = now() + every()
    elseif B.shownAt and now() - B.shownAt < 5 * 60 then B.since = now(); B.next = now() + every(); B.shownAt = nil end
    B.alive = now()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if hideAfterFight and win then hideAfterFight = false; win:Hide() end
    if pending then pending = false; check() end
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
