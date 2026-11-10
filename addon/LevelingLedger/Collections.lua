-- Library Books ("Friend of the Library"): books found around the world and handed in to the librarian, per character.
-- Data: CollectionsData.lua (generated). A book is collected once its hidden quest is completed (handed in); one in your
-- bags is picked up but not handed in yet.
--   * Questie map pins: every book this character still needs (your faction's), with a book icon; a pin goes away when
--     you pick the book up or hand it in. Uses Questie's internals like the planned-quest pins: every call checked and in
--     pcall, so a Questie update only turns the pins off.
--   * At logout the add-on saves which books this character has, for the ledger page.
--   /ledger books            how many you have, and the next ones to get with /way lines
--   /ledger books pins off   no map pins (on brings them back)
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local TYP = "LevelingLedgerBooks"
local BASE = 990000

local function books() return ns.libraryBooks or {} end
local function myFac() local f = UnitFactionGroup and UnitFactionGroup("player"); return f == "Horde" and "H" or f == "Alliance" and "A" or nil end
local function mine(b) return not b.fac or not myFac() or b.fac == myFac() end
local function done(b)
  return b.quest and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(b.quest) or false
end
local function inBags(b)
  if not b.item then return false end
  local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(b.item)) or (GetItemCount and GetItemCount(b.item)) or 0
  return (tonumber(count) or 0) > 0
end
local function questie(name)
  local L = rawget(_G, "QuestieLoader")
  if type(L) ~= "table" or type(L.ImportModule) ~= "function" then return nil end
  local ok, m = pcall(L.ImportModule, L, name)
  return ok and type(m) == "table" and m or nil
end
local function pinsOn() local db = ns.db and ns.db(); return not (db and db.bookPins == false) end

-- ---------- map pins ----------
local pinned = {}
local function unpin(b)
  if not pinned[b.n] then return end
  local Map = questie("QuestieMap")
  if Map and type(Map.UnloadManualFrames) == "function" then pcall(Map.UnloadManualFrames, Map, BASE + b.n, TYP) end
  pinned[b.n] = nil
end
local function pin(b)
  if pinned[b.n] then return end
  local Map, Zone = questie("QuestieMap"), questie("ZoneDB")
  if not (Map and Zone and type(Map.DrawManualIcon) == "function" and type(Zone.GetAreaIdByUiMapId) == "function") then return end
  local ok, area = pcall(Zone.GetAreaIdByUiMapId, Zone, b.map)
  if not ok or type(area) ~= "number" then return end
  local turnIn = (ns.libraryTurnIn or {})[myFac() or "A"]
  local data = { id = BASE + b.n, Icon = ICON, Type = "manual", spawnType = "object", Name = b.name, IsObjectiveNote = false }
  data.GetIconScale = function() return 1.1 end
  data.IconScale = 1.1
  data.ManualTooltipData = {
    Title = "Library Book: " .. b.name,
    Body = { { "Book", "#" .. b.n .. " of " .. #books() }, { "Note", b.note or "" },
      { "Hand in to", turnIn and (turnIn.n .. ", " .. turnIn.zone) or "the librarian" }, { "From", "Leveling Ledger" } },
    disableShiftToRemove = true,
  }
  if pcall(Map.DrawManualIcon, Map, data, area, b.x, b.y, TYP) then pinned[b.n] = true end
end
local function refresh()
  for _, b in ipairs(books()) do
    if pinsOn() and mine(b) and not done(b) and not inBags(b) then pin(b) else unpin(b) end
  end
end

-- ---------- what this character has, for the page ----------
local function save()
  local db = ns.db and ns.db(); if not (db and db.chars) then return end
  local c = db.chars[(UnitName("player") or "?") .. "-" .. (GetRealmName() or "")]
  if type(c) ~= "table" then return end
  local d, g = {}, {}
  for _, b in ipairs(books()) do
    if done(b) then d[#d + 1] = b.n elseif inBags(b) then g[#g + 1] = b.n end
  end
  c.books = { done = d, bags = g, at = time() }
end

-- ---------- /ledger books ----------
local function way(b) return string.format("/way #%d %.1f, %.1f %s", b.map, b.x, b.y, b.name) end
function ns.booksCommand(arg)
  arg = (arg or ""):match("^%s*(.-)%s*$")
  local db = ns.db and ns.db()
  if arg == "pins off" then if db then db.bookPins = false end; refresh(); print(TAG .. "Library Book pins are off. /ledger books pins on brings them back.") return end
  if arg == "pins on" then if db then db.bookPins = nil end; refresh(); print(TAG .. "Library Book pins are on (Questie's map).") return end
  local have, held, total, zone = 0, 0, 0, GetRealZoneText and GetRealZoneText() or ""
  local here, rest = {}, {}
  for _, b in ipairs(books()) do
    if mine(b) then
      total = total + 1
      if done(b) then have = have + 1
      elseif inBags(b) then held = held + 1
      elseif b.zone == zone then here[#here + 1] = b
      else rest[#rest + 1] = b end
    end
  end
  local turnIn = (ns.libraryTurnIn or {})[myFac() or "A"]
  print(TAG .. "Library Books: " .. have .. " of " .. total .. " handed in" .. (held > 0 and (", " .. held .. " in your bags to hand in to " .. (turnIn and turnIn.n or "the librarian")) or "") ..
    ". Rewards at 10 and 20.")
  local list = {}
  for _, b in ipairs(here) do list[#list + 1] = b end
  for _, b in ipairs(rest) do if #list < 5 then list[#list + 1] = b end end
  for _, b in ipairs(list) do print("  " .. b.n .. ". " .. b.name .. " (" .. b.zone .. (b.note ~= "" and (", " .. b.note) or "") .. "): " .. way(b)) end
  if not rawget(_G, "QuestieLoader") then print(TAG .. "install Questie to see the books on the map.") end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
local pending = false
local function soon() if pending then return end pending = true
  local go = function() pending = false; if ns.safe then ns.safe(refresh) else pcall(refresh) end end
  if C_Timer and C_Timer.After then C_Timer.After(1, go) else go() end
end
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local api = rawget(_G, "Questie") and Questie.API
    if api and type(api.RegisterOnReady) == "function" then pcall(api.RegisterOnReady, function() soon() end) end
  elseif event == "PLAYER_LOGOUT" then pcall(save)
  else soon() end
end)
