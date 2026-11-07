-- Leveling Ledger: records what you do in game so the Leveling Ledger web page can import it.
-- It only reads game information and saves it to SavedVariables (WTF\Account\<account>\SavedVariables\LevelingLedger.lua),
-- which the game writes when you log out or type /reload. It sends nothing anywhere.

local ADDON = ...
local VERSION = 3
local MAX_SESSIONS, MAX_QUESTS = 500, 3000

local f = CreateFrame("Frame")
local db, char, session
local lootSeen = {}          -- corpses already counted this session (by GUID)
local suppressPlayed = false -- hide the /played chat line for our own requests

-- ---------- helpers ----------
local function now() return time() end
local function idFromLink(link)
  if not link then return nil end
  return tonumber(link:match("item:(%d+)"))
end
local function nameFromLink(link)
  return link and link:match("%[(.-)%]") or nil
end
local function qualityFromLink(link)
  if not link then return nil end
  if C_Item and C_Item.GetItemQualityByID then
    local ok, q = pcall(C_Item.GetItemQualityByID, link)
    if ok then return q end
  end
  local ok, _, _, q = pcall(GetItemInfo, link)
  if ok then return q end
end
local function npcIdFromGUID(guid)
  if not guid then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then return tonumber(id) end
  if kind == "GameObject" then return -(tonumber(id) or 0) end -- objects stored as negative ids
end
local function zone() return GetRealZoneText() or GetZoneText() or "" end
local function position()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()
  if not x then return nil end
  return math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end
local function trim(list, max)
  while #list > max do table.remove(list, 1) end
end
local function safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and db then
    db.errors = db.errors or {}
    table.insert(db.errors, { at = now(), err = tostring(err) })
    trim(db.errors, 20)
  end
end

-- ---------- character and session ----------
local function charKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
end

local function snapshot()
  return {
    level = UnitLevel("player"), xp = UnitXP("player"), xpMax = UnitXPMax("player"),
    rested = GetXPExhaustion() or 0, money = GetMoney(), at = now(),
  }
end

local RESUME_GAP = 600 -- a /reload, disconnect or quick relog within 10 minutes continues the same session
local function startSession()
  local s = snapshot()
  local last = char.sessions[#char.sessions]
  if last and last.stop and s.at - last.stop <= RESUME_GAP and last.endLevel == s.level and last.endXP == s.xp then
    session = last
    session.stop = nil
    char.lastXP, char.lastLevel = s.xp, s.level
    return
  end
  session = {
    start = s.at, startLevel = s.level, startXP = s.xp, startXPMax = s.xpMax, startMoney = s.money, startRested = s.rested,
    xpGained = 0, levels = 0, kills = 0, quests = 0, deaths = 0, zones = {},
  }
  table.insert(char.sessions, session)
  trim(char.sessions, MAX_SESSIONS)
  char.lastXP, char.lastLevel = s.xp, s.level
end

local function closeSession()
  if not session then return end
  local s = snapshot()
  session.stop = s.at
  session.endLevel, session.endXP, session.endXPMax, session.endMoney, session.endRested = s.level, s.xp, s.xpMax, s.money, s.rested
end

-- What the character is on right now (the page shows rested XP and zone from this)
local function noteState()
  if not char then return end
  char.rested = GetXPExhaustion() or 0
  char.zone = zone()
  char.subzone = GetSubZoneText and GetSubZoneText() or ""
  char.resting = (IsResting and IsResting()) and true or false
  char.stateAt = now()
end

local function noteZone()
  if not session then return end
  local z = zone()
  if z ~= "" and session.zones[#session.zones] ~= z then
    table.insert(session.zones, z)
    trim(session.zones, 50)
  end
end

-- ---------- XP ----------
local function onXP()
  local lvl, xp = UnitLevel("player"), UnitXP("player")
  char.xpMax[lvl] = UnitXPMax("player")
  local gained
  if lvl == char.lastLevel then
    gained = xp - (char.lastXP or xp)
  elseif lvl > (char.lastLevel or lvl) then
    gained = (char.xpMax[char.lastLevel] or 0) - (char.lastXP or 0) + xp
    for l = char.lastLevel + 1, lvl - 1 do gained = gained + (char.xpMax[l] or 0) end
  end
  if session and gained and gained > 0 then session.xpGained = session.xpGained + gained end
  char.lastXP, char.lastLevel = xp, lvl
end

local function onLevelUp(newLevel)
  char.levels[newLevel] = { at = now(), zone = zone() }
  if session then session.levels = session.levels + 1 end
  suppressPlayed = true
  RequestTimePlayed()
end

local function onPlayed(total, thisLevel)
  char.played = total
  if session and not session.playedStart then session.playedStart = total end
  if session then session.playedEnd = total end
  local lvl = UnitLevel("player")
  if char.levels[lvl] and not char.levels[lvl].played then char.levels[lvl].played = total - (thisLevel or 0) end
end

-- ---------- quests ----------
local function onQuestTurnedIn(questID, xp, money)
  table.insert(char.quests, { id = questID, at = now(), xp = xp, money = money, zone = zone() })
  trim(char.quests, MAX_QUESTS)
  if session then session.quests = session.quests + 1 end
end

-- ---------- trainer ----------
local function onTrainer()
  if not GetNumTrainerServices then return end
  local npc = npcIdFromGUID(UnitGUID("npc"))
  for i = 1, GetNumTrainerServices() do
    local name, rank, category = GetTrainerServiceInfo(i)
    if name and category ~= "header" then
      local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil
      local req = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil
      char.trainer[name .. "|" .. (rank or "")] = { n = name, r = rank, cost = cost, lv = req, npc = npc, at = now(), state = category }
    end
  end
end

-- ---------- vendors ----------
local function merchantItem(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local ok, t = pcall(C_MerchantFrame.GetItemInfo, i)
    if ok and type(t) == "table" then return t.name, t.price, t.stackCount, t.numAvailable, t.hasExtendedCost end
  end
  if GetMerchantItemInfo then
    local name, _, price, qty, avail, _, _, ext = GetMerchantItemInfo(i)
    return name, price, qty, avail, ext
  end
end

local function onMerchant()
  local guid = UnitGUID("npc"); local npc = npcIdFromGUID(guid)
  if not npc or not GetMerchantNumItems then return end
  local x, y = position()
  local v = char.vendors[npc] or { items = {} }
  v.name, v.zone, v.x, v.y, v.at = UnitName("npc"), zone(), x, y, now()
  for i = 1, GetMerchantNumItems() do
    local name, price, qty, avail, ext = merchantItem(i)
    local link = GetMerchantItemLink(i)
    local id = idFromLink(link)
    if id then
      local item = { n = name or nameFromLink(link), price = price, qty = qty, q = qualityFromLink(link) }
      if avail and avail >= 0 then item.limited = avail end
      if ext and GetMerchantItemCostInfo then
        item.cur = {}
        for j = 1, (GetMerchantItemCostInfo(i) or 0) do
          local _, amount, costLink, currencyName = GetMerchantItemCostItem(i, j)
          table.insert(item.cur, { n = currencyName or nameFromLink(costLink), amount = amount, item = idFromLink(costLink) })
        end
      end
      v.items[id] = item
    end
  end
  char.vendors[npc] = v
end

-- ---------- loot ----------
local function onLoot()
  if not GetNumLootItems then return end
  local z, inInstance = zone(), IsInInstance()
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    local id = idFromLink(link)
    if id and GetLootSourceInfo then
      local src = { GetLootSourceInfo(slot) }
      for k = 1, #src, 2 do
        local guid, count = src[k], src[k + 1]
        local npc = npcIdFromGUID(guid)
        if npc then
          local e = char.loot[npc] or { opens = 0, items = {} }
          e.zone, e.instance = z, inInstance and true or nil
          if npc > 0 and not e.name and UnitExists("target") and UnitGUID("target") == guid then e.name = UnitName("target") end
          if not lootSeen[guid] then lootSeen[guid] = true; e.opens = e.opens + 1 end
          local it = e.items[id] or { n = nameFromLink(link), q = qualityFromLink(link), c = 0 }
          it.c = it.c + 1
          e.items[id] = it
          char.loot[npc] = e
        end
      end
    end
  end
end

-- ---------- events ----------
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_XP_UPDATE")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("TIME_PLAYED_MSG")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("TRAINER_UPDATE")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_UPDATE")
f:RegisterEvent("LOOT_OPENED")
f:RegisterEvent("PLAYER_DEAD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("ZONE_CHANGED_INDOORS")
f:RegisterEvent("UPDATE_EXHAUSTION")
f:RegisterEvent("PLAYER_UPDATE_RESTING")
f:RegisterEvent("PLAYER_TARGET_CHANGED")

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    LevelingLedgerDB = LevelingLedgerDB or {}
    db = LevelingLedgerDB
    db.version, db.chars = VERSION, db.chars or {}
  elseif event == "PLAYER_LOGIN" then
    safe(function()
      local key = charKey()
      char = db.chars[key] or {}
      db.chars[key] = char
      char.name, char.realm = UnitName("player"), GetRealmName()
      char.class, char.race, char.faction = select(2, UnitClass("player")), select(2, UnitRace("player")), UnitFactionGroup("player")
      char.level = UnitLevel("player")
      for _, k in ipairs({ "sessions", "levels", "xpMax", "quests", "trainer", "vendors", "loot" }) do char[k] = char[k] or {} end
      char.deaths = char.deaths or 0
      char.xpMax[char.level] = UnitXPMax("player")
      startSession(); noteZone(); noteState()
      -- Hide the chat line for /played requests the add-on makes itself (whichever handler this client uses)
      if not f.hooked then
        f.hooked = true
        if ChatFrame_DisplayTimePlayed then
          local orig = ChatFrame_DisplayTimePlayed
          ChatFrame_DisplayTimePlayed = function(...) if suppressPlayed then suppressPlayed = false; return end return orig(...) end
        end
        if ChatFrameUtil and ChatFrameUtil.DisplayTimePlayed then
          local orig = ChatFrameUtil.DisplayTimePlayed
          ChatFrameUtil.DisplayTimePlayed = function(...) if suppressPlayed then suppressPlayed = false; return end return orig(...) end
        end
      end
    end)
  elseif not char then
    return
  elseif event == "PLAYER_LOGOUT" then
    safe(function() onXP(); closeSession(); noteState(); char.level = UnitLevel("player"); db.savedAt = now() end)
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Ask for /played once per real login, not on every /reload or loading screen
    local isLogin = ...
    if isLogin then suppressPlayed = true; RequestTimePlayed() end
  elseif event == "PLAYER_XP_UPDATE" then safe(onXP); safe(noteState)
  elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then safe(noteState)
  elseif event == "PLAYER_LEVEL_UP" then local lvl = ...; safe(onLevelUp, lvl)
  elseif event == "TIME_PLAYED_MSG" then local total, thisLevel = ...; safe(onPlayed, total, thisLevel)
  elseif event == "QUEST_TURNED_IN" then local q, xp, money = ...; safe(onQuestTurnedIn, q, xp, money)
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then safe(onTrainer)
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then safe(onMerchant)
  elseif event == "LOOT_OPENED" then safe(onLoot)
  elseif event == "PLAYER_DEAD" then char.deaths = char.deaths + 1; if session then session.deaths = session.deaths + 1 end
  elseif event == "ZONE_CHANGED_NEW_AREA" then safe(noteZone); safe(noteState)
  elseif event == "PLAYER_TARGET_CHANGED" then
    -- remember names of creatures we've looted, since loot windows don't give names
    safe(function()
      local guid = UnitGUID("target"); local npc = npcIdFromGUID(guid)
      if npc and npc > 0 and char.loot[npc] and not char.loot[npc].name then char.loot[npc].name = UnitName("target") end
    end)
  end
end)

-- ---------- /ledger ----------
SLASH_LEVELINGLEDGER1 = "/ledger"
SlashCmdList.LEVELINGLEDGER = function()
  if not char then print("|cffd9aa5aLeveling Ledger|r: not ready yet."); return end
  local v, l, t = 0, 0, 0
  for _ in pairs(char.vendors) do v = v + 1 end
  for _ in pairs(char.loot) do l = l + 1 end
  for _ in pairs(char.trainer) do t = t + 1 end
  print(string.format("|cffd9aa5aLeveling Ledger|r: %d sessions, %d quests, %d trainer spells, %d vendors, %d creatures looted. This session: %d XP.",
    #char.sessions, #char.quests, t, v, l, session and session.xpGained or 0))
  print("|cffd9aa5aLeveling Ledger|r: type /reload or log out to save; the Leveling Ledger app imports it within a few seconds.")
end
