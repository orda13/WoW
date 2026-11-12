-- Flight points on the map (through Questie, like the entrance and book pins): every flight master for your faction,
-- and the neutral ones, with whether you've learned that flight path.
-- Data: FlightData.lua (generated from QuestieDB's Forever NPCs). Flight points the data doesn't have (new Forever
-- zones) come from the game's own list where the client has one (C_TaxiMap.GetTaxiNodesForMap), which also says
-- which ones you know. Every flight map you open is remembered too: the flight master you're talking to, and the
-- names of the flight points you can fly to (chars[...].flights). Questie and game calls are feature-checked and in pcall.
--   /ledger flights            how many you've learned, and the ones still to get by zone, with /way lines
--   /ledger flights pins off   no flight pins (on brings them back)
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local TYP = "LevelingLedgerFlights"
local BASE = 998000
local ICON = "Interface\\Minimap\\Tracking\\FlightMaster"

local function questie(name)
  local L = rawget(_G, "QuestieLoader")
  if type(L) ~= "table" or type(L.ImportModule) ~= "function" then return nil end
  local ok, m = pcall(L.ImportModule, L, name)
  return ok and type(m) == "table" and m or nil
end
local function pinsOn() local db = ns.db and ns.db(); return not (db and db.flightPins == false) end
local function myFac() local f = UnitFactionGroup and UnitFactionGroup("player"); return f == "Horde" and "H" or f == "Alliance" and "A" or nil end
local function mine(r) return r.f == "N" or not myFac() or r.f == myFac() end
local function rec() local c = ns.char and ns.char(); if not c then return nil end; c.flights = c.flights or { npcs = {}, names = {} }; c.flights.npcs = c.flights.npcs or {}; c.flights.names = c.flights.names or {}; return c.flights end

-- ---------- what the game says (newer clients): every flight point on a zone map, with its state ----------
local gameNodes = {} -- [mapID] = { { name, x, y, known }, ... }
local function nodesFor(map)
  if gameNodes[map] then return gameNodes[map] end
  local list = {}
  local T = rawget(_G, "C_TaxiMap")
  if T and type(T.GetTaxiNodesForMap) == "function" then
    local ok, nodes = pcall(T.GetTaxiNodesForMap, map)
    local S = Enum and Enum.FlightPathState
    for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
      local p = n.position
      if n.name and p and p.x and p.y then
        local known = nil
        if S and n.state ~= nil then known = (n.state == S.Current or n.state == S.Reachable) end
        local fac = n.faction
        local F = Enum and Enum.FlightPathFaction
        local side = (F and fac == F.Horde and "H") or (F and fac == F.Alliance and "A") or "N"
        list[#list + 1] = { name = tostring(n.name), x = p.x * 100, y = p.y * 100, known = known, f = side }
      end
    end
  end
  gameNodes[map] = list
  return list
end
local function nearestNode(r)
  local best, bd
  for _, n in ipairs(nodesFor(r.map)) do
    local d = (n.x - r.x) ^ 2 + (n.y - r.y) ^ 2
    if d < 9 and (not bd or d < bd) then best, bd = n, d end -- within 3 map percent
  end
  return best
end

-- ---------- learned or not ----------
local byZone = nil
local function zoneCount(z)
  if not byZone then byZone = {}; for _, r in ipairs(ns.flights or {}) do if mine(r) then byZone[r.z] = (byZone[r.z] or 0) + 1 end end end
  return byZone[z] or 0
end
-- true (learned), false (not learned) or nil (not seen yet)
local function known(r)
  local fl = rec()
  if fl and fl.npcs[r.id] then return true, nil end
  local node = r.id and nearestNode(r) or r
  if node and node.known ~= nil then return node.known, node.name end
  -- names from the flight maps you opened ("Sentinel Hill, Westfall"): a zone with one flight master for you is
  -- settled by any name there; with more, once as many names as flight masters were seen
  if fl and r.z and r.z ~= "" then
    local seen = 0
    for nm in pairs(fl.names) do if nm:match(",%s*(.-)$") == r.z then seen = seen + 1 end end
    if seen > 0 and seen >= zoneCount(r.z) then return true, nil end
    -- a flight map lists every flight path you know: a zone it never named has none learned
    if seen == 0 and fl.at and not r.game then return false, node and node.name end
  end
  return nil, node and node.name
end

-- every flight point to pin: the generated ones, plus game nodes the data doesn't have
local function points()
  local all = {}
  for _, r in ipairs(ns.flights or {}) do if mine(r) then all[#all + 1] = r end end
  local maps = {}
  for _, r in ipairs(all) do maps[r.map] = true end
  if C_Map and type(C_Map.GetMapChildrenInfo) == "function" then
    for _, top in ipairs({ 1414, 1415, 947 }) do
      local ok, kids = pcall(C_Map.GetMapChildrenInfo, top, Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3, true)
      for _, m in ipairs(ok and type(kids) == "table" and kids or {}) do if m.mapID then maps[m.mapID] = maps[m.mapID] or "new" end end
    end
  end
  for map in pairs(maps) do
    for _, n in ipairs(nodesFor(map)) do
      local near = false
      for _, r in ipairs(all) do if r.map == map and (r.x - n.x) ^ 2 + (r.y - n.y) ^ 2 < 9 then near = true; break end end
      if not near and (n.f == "N" or not myFac() or n.f == myFac()) then
        all[#all + 1] = { n = n.name, name = n.name, s = "Flight point", f = n.f, z = n.name:match(",%s*(.-)$") or "", map = map, x = n.x, y = n.y, known = n.known, game = true }
      end
    end
  end
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
  for k, r in ipairs(points()) do
    local id = BASE + k
    local area = r.area
    if not area and Zone and type(Zone.GetAreaIdByUiMapId) == "function" then local ok, a = pcall(Zone.GetAreaIdByUiMapId, Zone, r.map); if ok then area = a end end
    if type(area) == "number" then
      local k2, nodeName = known(r)
      local title = (nodeName or (r.z ~= "" and r.z) or r.n) .. ": flight point"
      local status = k2 == true and "|cff40ff40Learned|r" or k2 == false and ("|cffffd100Not learned yet|r: talk to " .. (r.game and "the flight master" or r.n))
        or "|cff9d9d9dNot seen yet|r: open any flight map to update"
      local body = { { "Flight master", r.game and "(from the game's list)" or (r.n .. ", " .. r.s) }, { "Status", status } }
      if r.z ~= "" then table.insert(body, 1, { "Zone", r.z }) end
      body[#body + 1] = { "From", "Leveling Ledger" }
      local data = { id = id, Icon = ICON, Type = "manual", spawnType = "npc", Name = r.n, IsObjectiveNote = false }
      data.GetIconScale = function() return k2 == true and 0.9 or 1.15 end
      data.IconScale = k2 == true and 0.9 or 1.15
      data.ManualTooltipData = { Title = title, Body = body, disableShiftToRemove = true }
      if pcall(Map.DrawManualIcon, Map, data, area, r.x, r.y, TYP) then pinned[id] = true end
    end
  end
end
local function refresh() gameNodes = {}; clear(); if pinsOn() then draw() end end
ns.refreshFlights = refresh

-- ---------- remember what a flight map shows ----------
local function noteTaxi()
  local fl = rec(); if not fl then return end
  local guid = UnitGUID and UnitGUID("npc")
  local npc = guid and tonumber((tostring(guid)):match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
  if npc then fl.npcs[npc] = true end
  if type(NumTaxiNodes) == "function" and type(TaxiNodeName) == "function" then
    local ok, count = pcall(NumTaxiNodes)
    for i = 1, (ok and tonumber(count)) or 0 do
      local okn, nm = pcall(TaxiNodeName, i)
      local okt, ty = pcall(TaxiNodeGetType or function() return nil end, i)
      if okn and nm and nm ~= "" and (not okt or ty == nil or ty == "CURRENT" or ty == "REACHABLE") then fl.names[nm] = true end
    end
  end
  fl.at = time and time() or nil
end

function ns.flightsCommand(arg)
  arg = (arg or ""):match("^%s*(.-)%s*$")
  local db = ns.db and ns.db()
  if arg == "pins off" then if db then db.flightPins = false end; refresh(); print(TAG .. "Flight point pins are off. /ledger flights pins on brings them back.") return end
  if arg == "pins on" then if db then db.flightPins = nil end; refresh(); print(TAG .. "Flight point pins are on (Questie's map).") return end
  local learned, todo, unseen = 0, {}, 0
  for _, r in ipairs(points()) do
    local k = known(r)
    if k == true then learned = learned + 1 elseif k == false then todo[#todo + 1] = r else unseen = unseen + 1; todo[#todo + 1] = r end
  end
  print(TAG .. "Flight points: " .. learned .. " learned, " .. #todo .. " to get" .. (unseen > 0 and (" (" .. unseen .. " not seen yet: open a flight map to update)") or "") .. ".")
  table.sort(todo, function(a, b) return (a.z or "") < (b.z or "") end)
  for i, r in ipairs(todo) do
    if i > 12 then print("  ...and " .. (#todo - 12) .. " more on the map.") break end
    print(string.format("  %s%s: /way #%d %.1f, %.1f", r.z ~= "" and (r.z .. ", ") or "", r.game and r.n or (r.n .. " (" .. r.s .. ")"), r.map, r.x, r.y))
  end
  if not rawget(_G, "QuestieLoader") then print(TAG .. "install Questie to see the flight points on the map.")
  elseif not pinsOn() then print(TAG .. "Flight pins are off: /ledger flights pins on.") end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "TAXIMAP_OPENED" }) do
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
  elseif event == "TAXIMAP_OPENED" then
    if ns.safe then ns.safe(noteTaxi) else pcall(noteTaxi) end
    soon()
  end
end)
