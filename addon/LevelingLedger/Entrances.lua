-- Dungeon and raid entrances on the map (through Questie, like the book and secret pins).
-- Data: EntranceData.lua (generated): each entrance spot with the instances entered there, their kind and level range.
-- Dungeons the data doesn't place yet (the newest Forever ones) come from the game's own entrance list, where the client
-- has one (C_EncounterJournal.GetDungeonEntrancesForMap). Every Questie and game call is feature-checked and in pcall.
--   /ledger dungeons            the entrances for your level, nearest levels first, with /way lines
--   /ledger dungeons pins off   no entrance pins (on brings them back)
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local TYP = "LevelingLedgerEntrances"
local BASE = 997000
local ICON = { D = "Interface\\Icons\\INV_Misc_Key_13", R = "Interface\\Icons\\INV_Misc_Head_Dragon_Black" }
local KIND = { D = "Dungeon", R = "Raid" }

local function questie(name)
  local L = rawget(_G, "QuestieLoader")
  if type(L) ~= "table" or type(L.ImportModule) ~= "function" then return nil end
  local ok, m = pcall(L.ImportModule, L, name)
  return ok and type(m) == "table" and m or nil
end
local function pinsOn() local db = ns.db and ns.db(); return not (db and db.entrancePins == false) end
local function levels(i) return i.lv and (i.lv[1] == i.lv[2] and ("level " .. i.lv[1]) or ("levels " .. i.lv[1] .. "-" .. i.lv[2])) or "" end
-- how an instance fits this character: "now", "soon" (within 5 levels), "later" or "past"
local function fit(i)
  local lv = UnitLevel and UnitLevel("player") or 0
  if not i.lv then return "unknown" end
  if lv <= 0 then return "now" end
  if lv > i.lv[2] then return "past" elseif lv >= i.lv[1] - 2 then return "now" elseif lv >= i.lv[1] - 7 then return "soon" end
  return "later"
end
local FIT = { unknown = "|cff9d9d9dlevel not known yet|r", now = "|cff40ff40right for your level|r", soon = "|cffffd100a few levels away|r", later = "|cffff8040above your level|r", past = "|cff9d9d9dbelow your level|r" }

-- every spot: the generated ones, plus what the game lists for dungeons the data doesn't place
local extra, extraDone = {}, false
local function gameEntrances()
  if extraDone then return extra end
  extraDone = true
  local EJ = rawget(_G, "C_EncounterJournal")
  if not (EJ and type(EJ.GetDungeonEntrancesForMap) == "function" and C_Map and type(C_Map.GetMapChildrenInfo) == "function") then return extra end
  local known = {}
  for _, s in ipairs(ns.entrances or {}) do for _, i in ipairs(s.list) do known[i.n:lower()] = true end end
  local seen = {}
  for _, top in ipairs({ 1414, 1415, 947 }) do -- Kalimdor, Eastern Kingdoms, Azeroth (for new islands)
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, top, Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3, true)
    for _, m in ipairs(ok and type(kids) == "table" and kids or {}) do
      if m.mapID and not seen[m.mapID] then
        seen[m.mapID] = true
        local ok2, list = pcall(EJ.GetDungeonEntrancesForMap, m.mapID)
        for _, e in ipairs(ok2 and type(list) == "table" and list or {}) do
          local n = e.name and tostring(e.name) or nil
          local x, y = e.position and e.position.x, e.position and e.position.y
          if n and x and y and not known[n:lower()] then
            known[n:lower()] = true
            local info = (ns.entranceInfo or {})[n:lower()] or {}
            local raid = e.atlasName and tostring(e.atlasName):lower():find("raid") and true or false
            extra[#extra + 1] = { map = m.mapID, x = x * 100, y = y * 100, list = { { n = n, k = info.k or (raid and "R" or "D"), lv = info.lv } }, game = true }
          end
        end
      end
    end
  end
  return extra
end
local function spots()
  local all = {}
  for _, s in ipairs(ns.entrances or {}) do all[#all + 1] = s end
  for _, s in ipairs(gameEntrances()) do all[#all + 1] = s end
  return all
end

local pinned = {}
local function clear()
  local Map = questie("QuestieMap")
  for id in pairs(pinned) do
    if Map and type(Map.UnloadManualFrames) == "function" then pcall(Map.UnloadManualFrames, Map, id, TYP) end
    pinned[id] = nil
  end
end
local function draw()
  local Map, Zone = questie("QuestieMap"), questie("ZoneDB")
  if not (Map and type(Map.DrawManualIcon) == "function") then return end
  for k, s in ipairs(spots()) do
    local id = BASE + k
    if not pinned[id] then
      local area = s.area
      if not area and Zone and type(Zone.GetAreaIdByUiMapId) == "function" then local ok, a = pcall(Zone.GetAreaIdByUiMapId, Zone, s.map); if ok then area = a end end
      if type(area) == "number" then
        local first, raid = s.list[1], false
        for _, i in ipairs(s.list) do if i.k == "R" then raid = true end end
        local body = {}
        for _, i in ipairs(s.list) do body[#body + 1] = { i.n, KIND[i.k] .. (i.lv and (", " .. levels(i) .. ": " .. FIT[fit(i)]) or "") } end
        body[#body + 1] = { "From", "Leveling Ledger" .. (s.game and " (the game's entrance list)" or "") }
        local title = #s.list > 1 and ((first.n:find("^Blackrock") and "Blackrock Mountain" or (s.list[1].n .. " and more")) .. ": entrance") or (first.n .. ": " .. KIND[first.k]:lower() .. " entrance")
        local data = { id = id, Icon = ICON[(not raid or first.k == "R") and first.k or "D"], Type = "manual", spawnType = "object", Name = first.n, IsObjectiveNote = false }
        data.GetIconScale = function() return 1.15 end
        data.IconScale = 1.15
        data.ManualTooltipData = { Title = title, Body = body, disableShiftToRemove = true }
        if pcall(Map.DrawManualIcon, Map, data, area, s.x, s.y, TYP) then pinned[id] = true end
      end
    end
  end
end
local function refresh() if pinsOn() then draw() else clear() end end
ns.refreshEntrances = refresh

function ns.dungeonsCommand(arg)
  arg = (arg or ""):match("^%s*(.-)%s*$")
  local db = ns.db and ns.db()
  if arg == "pins off" then if db then db.entrancePins = false end; refresh(); print(TAG .. "Dungeon entrance pins are off. /ledger dungeons pins on brings them back.") return end
  if arg == "pins on" then if db then db.entrancePins = nil end; refresh(); print(TAG .. "Dungeon and raid entrance pins are on (Questie's map).") return end
  local now, soon = {}, {}
  for _, s in ipairs(spots()) do
    for _, i in ipairs(s.list) do
      local f = fit(i)
      local row = { i = i, s = s }
      if f == "now" then now[#now + 1] = row elseif f == "soon" then soon[#soon + 1] = row end
    end
  end
  local function show(rows, head)
    if #rows == 0 then return end
    print(TAG .. head)
    local seen = {}
    for _, r in ipairs(rows) do
      if not seen[r.i.n] then
        seen[r.i.n] = true
        print(string.format("  %s (%s%s): /way #%d %.1f, %.1f", r.i.n, KIND[r.i.k], r.i.lv and (", " .. levels(r.i)) or "", r.s.map, r.s.x, r.s.y))
      end
    end
  end
  show(now, "Dungeons and raids for your level:")
  show(soon, "A few levels away:")
  if #now == 0 and #soon == 0 then print(TAG .. "No dungeon fits your level right now.") end
  if not rawget(_G, "QuestieLoader") then print(TAG .. "install Questie to see the entrances on the map.")
  elseif not pinsOn() then print(TAG .. "Entrance pins are off: /ledger dungeons pins on.") end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
local function soon()
  local go = function() if ns.safe then ns.safe(refresh) else pcall(refresh) end end
  if C_Timer and C_Timer.After then C_Timer.After(2, go) else go() end
end
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local api = rawget(_G, "Questie") and Questie.API
    if api and type(api.RegisterOnReady) == "function" then pcall(api.RegisterOnReady, soon) end
  else
    -- the tooltips say how each instance fits your level: redraw them
    clear(); soon()
  end
end)
