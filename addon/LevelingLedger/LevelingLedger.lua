-- Leveling Ledger: records what you do in game so the Leveling Ledger web page can import it.
-- It only reads game information and saves it to SavedVariables (WTF\Account\<account>\SavedVariables\LevelingLedger.lua),
-- which the game writes when you log out or type /reload. It sends nothing anywhere.

local ADDON, ns = ...
ns = ns or {}
local VERSION = 11
local MAX_SESSIONS, MAX_QUESTS = 500, 3000

local f = CreateFrame("Frame")
-- Register an event only if this client has it: game updates rename or remove events, and an unknown one
-- is an error that would stop the rest of the add-on from loading.
local function listen(fr, e)
  if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(e) then return false end
  return (pcall(fr.RegisterEvent, fr, e))
end
ns.listen = listen
local db, char, session
local skinSeen = {}          -- corpses already counted as a skinning spot
local lootSeen = {}          -- corpses already counted this session (by GUID)
-- /played isn't asked for at login: the game may only allow it from a key press, so it's asked when you type /ledger
-- (and read whenever you type /played yourself).
-- Ask for /played without the chat line: the chat windows stop listening for that one reply.
-- (Replacing Blizzard's chat function instead would taint it, and the game would blame the add-on for blocked actions.)
local muted = nil
local function unmutePlayed()
  if not muted then return end
  for _, cf in ipairs(muted) do pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG") end
  muted = nil
end
local function after(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) return end
  local t, w = 0, CreateFrame("Frame")
  w:SetScript("OnUpdate", function(self, dt) t = t + (dt or 0); if t >= sec then self:SetScript("OnUpdate", nil); fn() end end)
end
local function requestPlayed()
  if not muted then
    muted = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local cf = _G["ChatFrame" .. i]
      if cf and cf.IsEventRegistered and cf:IsEventRegistered("TIME_PLAYED_MSG") then cf:UnregisterEvent("TIME_PLAYED_MSG"); muted[#muted + 1] = cf end
    end
    after(10, unmutePlayed) -- in case no reply comes
  end
  RequestTimePlayed()
end
local lastMoney              -- money at the last PLAYER_MONEY, to work out each change
local where = {}             -- which money windows are open: merchant, trainer, mail, auction

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
-- WoW Forever has no realms: a character is a first name and a surname, unique together (UnitNameUnmodified gives
-- both; UnitName only the first). Two characters can share a first name, so the full name is the key there.
local function nameParts()
  local first, surname = UnitName("player"), nil
  if type(UnitNameUnmodified) == "function" then
    local ok, a, b = pcall(UnitNameUnmodified, "player")
    if ok and type(a) == "string" and a ~= "" then first = a; if type(b) == "string" and b ~= "" then surname = b end end
  end
  return first or "?", surname
end
local function oldKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "") end
local function charKey()
  local first, surname = nameParts()
  if surname then return first .. " " .. surname end
  return oldKey()
end
ns.nameParts, ns.charKey = nameParts, charKey
-- the names the page files plans and ticks under, most specific first: "talwyn orda", then "talwyn" (older pages)
function ns.whoKeys()
  local first, surname = nameParts()
  local t = {}
  if surname then t[#t + 1] = (first .. " " .. surname):lower() end
  t[#t + 1] = first:lower()
  return t
end
function ns.forMe(all)
  if type(all) ~= "table" then return nil end
  for _, k in ipairs(ns.whoKeys()) do if all[k] ~= nil then return all[k] end end
end

-- While you log out the game often answers with nothing: no rested XP, no zone, not resting, 0 gold, level 0, 0 XP.
-- So every reading goes through read(): while you play it's remembered, and at logout an empty answer gives the last
-- one seen instead (then what was saved before). Everything here is also updated by events while you play.
local EMPTY = { rested = 0, zone = "", subzone = "", resting = false, money = 0, level = 0, xp = 0, xpMax = 0 }
local good, loggingOut = {}, false
local function read(k, v)
  if v == nil then v = EMPTY[k] end
  if not loggingOut then good[k] = v; return v end
  if v == EMPTY[k] and good[k] ~= nil then return good[k] end
  return v
end
local function lvlNow() return read("level", UnitLevel("player")) end
local function xpNow() return read("xp", UnitXP("player")) end
local function xpMaxNow() return read("xpMax", UnitXPMax("player")) end

local function snapshot()
  return {
    level = lvlNow(), xp = xpNow(), xpMax = xpMaxNow(),
    rested = read("rested", GetXPExhaustion()), money = read("money", GetMoney and GetMoney()), at = now(),
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
    lastMoney = s.money
    return
  end
  lastMoney = s.money
  session = {
    start = s.at, startLevel = s.level, startXP = s.xp, startXPMax = s.xpMax, startMoney = s.money, startRested = s.rested,
    xpGained = 0, levels = 0, kills = 0, killXP = 0, questXP = 0, quests = 0, deaths = 0, zones = {},
  }
  table.insert(char.sessions, session)
  trim(char.sessions, MAX_SESSIONS)
  char.lastXP, char.lastLevel = s.xp, s.level
end

-- XP and time per zone and per level, for the leveling report: time since the last tick goes to the zone and level
-- you were in, then XP to where you are now.
local tickAt, tickZone, tickLevel
local function tick(xp)
  if not session then return end
  local t = now()
  session.byZone = session.byZone or {}; session.byLevel = session.byLevel or {}
  if tickAt and tickZone and tickZone ~= "" then
    local z = session.byZone[tickZone] or { xp = 0, sec = 0 }; z.sec = z.sec + (t - tickAt); session.byZone[tickZone] = z
  end
  if tickAt and tickLevel then
    local l = session.byLevel[tickLevel] or { xp = 0, sec = 0 }; l.sec = l.sec + (t - tickAt); session.byLevel[tickLevel] = l
  end
  -- XP goes where you were until now (at a level-up that's the level you just finished)
  if xp and xp > 0 then
    local zn, lv = tickZone or read("zone", zone()), tickLevel or lvlNow()
    if zn ~= "" then local z = session.byZone[zn] or { xp = 0, sec = 0 }; z.xp = z.xp + xp; session.byZone[zn] = z end
    local l = session.byLevel[lv] or { xp = 0, sec = 0 }; l.xp = l.xp + xp; session.byLevel[lv] = l
  end
  tickAt, tickZone, tickLevel = t, read("zone", zone()), lvlNow()
end
local function closeSession()
  if not session then return end
  tick()
  local s = snapshot()
  session.stop = s.at
  session.endLevel, session.endXP, session.endXPMax, session.endMoney, session.endRested = s.level, s.xp, s.xpMax, s.money, s.rested
end

-- What the character is on right now (the page shows rested XP and zone from this)
-- At logout empty answers fall back to the last ones seen (read() above).
local function noteState()
  if not char then return end
  char.rested = read("rested", GetXPExhaustion())
  char.zone = read("zone", zone())
  char.subzone = read("subzone", GetSubZoneText and GetSubZoneText())
  char.resting = read("resting", (IsResting and IsResting()) and true or false)
  char.money = read("money", GetMoney and GetMoney())
  char.level = lvlNow()
  xpNow(); xpMaxNow()
  char.stateAt = now()
end

-- ---------- bags and bank ----------
-- Item counts by item id. Bags are read whenever they change; the bank only while it's open (the game has no bank data otherwise).
-- An item's name: from its link, else asked of the game by id. When the game hasn't loaded the item yet the link
-- has an empty name; then it's requested and recorded when GET_ITEM_INFO_RECEIVED arrives (never saved empty).
local wantNames = {}
local function itemNameNow(id, link)
  local n = nameFromLink(link)
  if n and n ~= "" then return n end
  if C_Item and C_Item.GetItemNameByID then local ok, x = pcall(C_Item.GetItemNameByID, id); if ok and type(x) == "string" and x ~= "" then return x end end
  if GetItemInfo then local ok, x = pcall(GetItemInfo, id); if ok and type(x) == "string" and x ~= "" then return x end end
end
local function noteItemName(id, link)
  db.items = db.items or {}
  local have = db.items[id]
  if have and type(have.n) == "string" and have.n ~= "" then return end
  local n = itemNameNow(id, link)
  if n then
    db.items[id] = { n = n, q = qualityFromLink(link) or qualityFromLink(id) }
    wantNames[id] = nil
  else
    wantNames[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  end
end
-- at login: every item in your characters' bags and bank still without a name (bank items otherwise wait for a visit)
local function askMissingNames()
  db.items = db.items or {}
  local asked = 0
  for _, c in pairs(db.chars or {}) do
    for _, where in ipairs({ c.bags, c.bank }) do
      for id in pairs(where or {}) do
        local have = db.items[id]
        if asked < 400 and not (have and type(have.n) == "string" and have.n ~= "") then noteItemName(id); asked = asked + 1 end
      end
    end
  end
end
ns.onItemInfo = function(id) id = tonumber(id); if id and wantNames[id] then noteItemName(id) end end
local function slotCount(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function slotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount, info.hyperlink end
    return
  end
  if GetContainerItemInfo then
    local _, count, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
    link = link or (GetContainerItemLink and GetContainerItemLink(bag, slot))
    return id or idFromLink(link), count, link
  end
end
local function scanContainers(bags)
  local out = {}
  for _, bag in ipairs(bags) do
    for slot = 1, slotCount(bag) do
      local id, count, link = slotItem(bag, slot)
      if id then out[id] = (out[id] or 0) + (count or 1); if link then noteItemName(id, link) end end
    end
  end
  return out
end
local bankOpen = false
-- The bag items sitting in bag slots (not their contents): equipped bags, the reagent bag, the bank's bag slots
local function bagItemIn(bag)
  local inv = (C_Container and C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag))
    or (ContainerIDToInventoryID and ContainerIDToInventoryID(bag))
  return inv and GetInventoryItemID and GetInventoryItemID("player", inv) or nil
end
local function bagItemsIn(first, last)
  local out = {}
  for b = first, last do local ok, id = pcall(bagItemIn, b); if ok and id then out[#out + 1] = id end end
  return out
end
-- Bags are read whenever they change, not at logout (the game often reports them empty then).
local function scanBags()
  local n = NUM_BAG_SLOTS or 4
  local list = {}
  for b = 0, n do list[#list + 1] = b end
  local got = scanContainers(list)
  char.bags = got
  char.bagsAt = now()
  -- the reagent bag slot, where this client has one (its own bag index)
  local BI = Enum and Enum.BagIndex
  local eq = bagItemsIn(1, n)
  local rb = BI and BI.ReagentBag
  if rb then local ok, id = pcall(bagItemIn, rb); if ok and id then eq[#eq + 1] = id end end
  char.bagItems = eq
end
local function scanBank()
  if not bankOpen then return end
  local n, nb = NUM_BAG_SLOTS or 4, NUM_BANKBAGSLOTS or 6
  local list = { BANK_CONTAINER or -1 }
  for b = n + 1, n + nb do list[#list + 1] = b end
  char.bank = scanContainers(list)
  char.bankAt = now()
  local BI = Enum and Enum.BagIndex
  local first = (BI and BI.BankBag_1) or (n + 1)
  char.bankBagItems = bagItemsIn(first, first + nb - 1)
end

local function noteZone()
  if not session then return end
  tick()
  local z = zone()
  if z ~= "" and session.zones[#session.zones] ~= z then
    table.insert(session.zones, z)
    trim(session.zones, 50)
  end
end

-- ---------- XP ----------
local function onXP()
  local lvl, xp = lvlNow(), xpNow()
  if lvl < 1 then return end
  local mx = xpMaxNow(); if mx > 0 then char.xpMax[lvl] = mx end
  local gained
  if lvl == char.lastLevel then
    gained = xp - (char.lastXP or xp)
  elseif lvl > (char.lastLevel or lvl) then
    gained = (char.xpMax[char.lastLevel] or 0) - (char.lastXP or 0) + xp
    for l = char.lastLevel + 1, lvl - 1 do gained = gained + (char.xpMax[l] or 0) end
  end
  if session and gained and gained > 0 then session.xpGained = session.xpGained + gained end
  if session then tick(gained) end
  char.lastXP, char.lastLevel = xp, lvl
end

local function onLevelUp(newLevel)
  char.levels[newLevel] = { at = now(), zone = zone() }
  if session then session.levels = session.levels + 1 end
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
  table.insert(char.quests, { id = questID, at = now(), xp = xp, money = money, zone = zone(), took = ns.questTook and ns.questTook(questID) or nil })
  trim(char.quests, MAX_QUESTS)
  if session then
    session.quests = session.quests + 1
    session.questXP = (session.questXP or 0) + (tonumber(xp) or 0)
  end
end

-- ---------- gold ----------
-- Every change in money, filed by where it happened. In: quest, vendor (selling), mail, other (mostly looting).
-- Out: training, vendor (buying and repairs), mail (postage and auction fees), other.
local lastTurnIn, lastOther = 0, nil
local function addMoney(dir, kind, amt)
  if not session or amt <= 0 then return end
  local key = dir == "in" and "moneyIn" or "moneyOut"
  session[key] = session[key] or {}
  session[key][kind] = (session[key][kind] or 0) + amt
end
local function onMoney()
  if loggingOut then return end
  local m = GetMoney()
  if lastMoney == nil then lastMoney = m; return end
  local d = m - lastMoney
  lastMoney = m
  if d == 0 then return end
  local t = GetTime and GetTime() or now()
  if d > 0 then
    if where.mail or where.auction then addMoney("in", "mail", d)
    elseif where.merchant then addMoney("in", "vendor", d)
    elseif t - lastTurnIn < 2 then addMoney("in", "quest", d)
    else addMoney("in", "other", d); lastOther = { t = t, amt = d } end
  else
    d = -d
    if where.trainer then addMoney("out", "training", d)
    elseif where.merchant then addMoney("out", "vendor", d)
    elseif where.mail or where.auction then addMoney("out", "mail", d)
    else addMoney("out", "other", d) end
  end
end
-- Quest money can arrive just before or just after QUEST_TURNED_IN; either way it ends up under quest.
local function onQuestMoney(money)
  money = tonumber(money) or 0
  local t = GetTime and GetTime() or now()
  lastTurnIn = t
  if money > 0 and lastOther and t - lastOther.t < 2 and session and session.moneyIn and session.moneyIn.other then
    local mv = math.min(money, lastOther.amt, session.moneyIn.other)
    session.moneyIn.other = session.moneyIn.other - mv
    addMoney("in", "quest", mv)
    lastOther = nil
  end
end

-- ---------- professions ----------
-- Skill levels from the skill list; recipe lists when a profession window is open.
local PROFS = {
  Alchemy = "primary", Blacksmithing = "primary", Enchanting = "primary", Engineering = "primary", Herbalism = "primary",
  Leatherworking = "primary", Mining = "primary", Skinning = "primary", Tailoring = "primary", Jewelcrafting = "primary",
  Cooking = "secondary", ["First Aid"] = "secondary", Fishing = "secondary",
}
-- Profession skills, as { name, rank, max, kind }: the classic skill lines, or (this client, newer engine)
-- GetProfessions / GetProfessionInfo
local function readSkills()
  local out = {}
  if GetNumSkillLines and GetSkillLineInfo then
    local header
    local primaryHeader = TRADE_SKILLS or "Professions"
    local secondaryHeader = SECONDARY_SKILLS or "Secondary Skills"
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if isHeader then header = name
      elseif name then
        local kind = PROFS[name] or (header == primaryHeader and "primary") or (header == secondaryHeader and "secondary")
        if kind then out[#out + 1] = { name = name, rank = rank, max = maxRank, kind = kind } end
      end
    end
  elseif GetProfessions and GetProfessionInfo then
    for _, idx in pairs({ GetProfessions() }) do
      if idx then
        local ok, name, _, rank, maxRank = pcall(GetProfessionInfo, idx)
        if ok and name then out[#out + 1] = { name = name, rank = rank or 0, max = maxRank, kind = PROFS[name] or "secondary" } end
      end
    end
  end
  return out
end
local function scanSkills()
  local list = readSkills()
  if #list == 0 then return end
  char.skills = char.skills or {}
  for _, sk in ipairs(list) do
    local old = char.skills[sk.name]
    if session and old and sk.rank > (old.rank or 0) then
      session.skillups = session.skillups or {}
      local su = session.skillups[sk.name] or { from = old.rank }
      su.to = sk.rank
      session.skillups[sk.name] = su
    end
    char.skills[sk.name] = { rank = sk.rank, max = sk.max, kind = sk.kind }
  end
  char.skillsAt = now()
end

-- Every recipe in the open profession window (trade skills, and the craft window Enchanting uses)
local function noteRecipes(prof, names)
  if not prof or prof == "" or prof == "UNKNOWN" then return end
  char.recipes = char.recipes or {}
  local have = {}
  for _, n in ipairs(char.recipes[prof] or {}) do have[n] = true end
  local list = char.recipes[prof] or {}
  for _, n in ipairs(names) do if not have[n] then have[n] = true; table.insert(list, n) end end
  table.sort(list)
  char.recipes[prof] = list
  char.recipesAt = now()
end
local function scanTradeSkills()
  local prof, names = nil, {}
  if GetTradeSkillLine and GetNumTradeSkills then
    prof = GetTradeSkillLine()
    for i = 1, GetNumTradeSkills() do
      local n, kind = GetTradeSkillInfo(i)
      if n and kind ~= "header" then table.insert(names, n) end
    end
  elseif C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
    -- newer engine: the open profession, and every recipe you've learned in it
    local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    prof = info and info.professionName
    if not prof and C_TradeSkillUI.GetTradeSkillLine then prof = select(2, C_TradeSkillUI.GetTradeSkillLine()) end
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
      local r = C_TradeSkillUI.GetRecipeInfo(id)
      if r and r.learned and r.name then table.insert(names, r.name) end
    end
  end
  if prof and #names > 0 then noteRecipes(prof, names) end
end
local function scanCrafts()
  if not GetCraftDisplaySkillLine or not GetNumCrafts then return end
  local prof = GetCraftDisplaySkillLine()
  local names = {}
  for i = 1, GetNumCrafts() do
    local n, _, kind = GetCraftInfo(i)
    if n and kind ~= "header" then table.insert(names, n) end
  end
  noteRecipes(prof, names)
end

-- "You have learned how to create a new item: <name>." (pattern from the client's own text)
local learnPattern
local function onSystemMessage(msg)
  if not msg then return end
  if not learnPattern then
    local fmt = ERR_LEARN_RECIPE_S or "You have learned how to create a new item: %s."
    learnPattern = "^" .. fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
  end
  local n = msg:match(learnPattern)
  if not n then return end
  char.learned = char.learned or {}
  table.insert(char.learned, { n = n, at = now() })
  trim(char.learned, 500)
  if session then
    session.recipesLearned = session.recipesLearned or {}
    table.insert(session.recipesLearned, n)
    trim(session.recipesLearned, 50)
  end
end

-- ---------- reputation ----------
-- Values are the game's running totals (they keep counting across standings), so gains are simple subtraction.
local function factionRows()
  local rows = {}
  if GetNumFactions and GetFactionInfo then
    for i = 1, GetNumFactions() do
      local name, _, standing, bMin, bMax, bVal, _, _, isHeader, _, hasRep, _, _, id = GetFactionInfo(i)
      if name and (not isHeader or hasRep) and standing then
        rows[#rows + 1] = { name = name, standing = standing, min = bMin, max = bMax, value = bVal, id = id }
      end
    end
  elseif C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    for i = 1, C_Reputation.GetNumFactions() do
      local f = C_Reputation.GetFactionDataByIndex(i)
      if f and f.name and (not f.isHeader or f.isHeaderWithRep) and f.reaction then
        rows[#rows + 1] = { name = f.name, standing = f.reaction, min = f.currentReactionThreshold, max = f.nextReactionThreshold, value = f.currentStanding, id = f.factionID }
      end
    end
  end
  return rows
end
local function scanReps()
  char.reps = char.reps or {}
  for _, r in ipairs(factionRows()) do
    local old = char.reps[r.name]
    if session and old and old.value and r.value ~= old.value then
      session.repGains = session.repGains or {}
      local g = session.repGains[r.name] or { from = old.value, fromStanding = old.standing }
      g.to, g.toStanding, g.min, g.max = r.value, r.standing, r.min, r.max
      session.repGains[r.name] = g
    end
    char.reps[r.name] = { standing = r.standing, value = r.value, min = r.min, max = r.max, id = r.id }
  end
  char.repsAt = now()
end

-- ---------- kills ----------
-- Kills are counted from the kill-XP message below. (Not the combat log: this game client doesn't let add-ons read
-- it, and asking for it gets the add-on blocked at login.) Kills that give no XP aren't counted.
-- Kill XP and kills: "<mob> dies, you gain <n> experience." (also kills by your group that give you XP).
-- The pattern comes from the game's own text, so it works in any language.
local killXPPattern
local function buildKillPattern()
  local fmt = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
  local cut = fmt:find("%%d") -- keep the text up to and including the XP number
  if not cut then return "^.- dies, you gain (%d+) experience" end
  local head = fmt:sub(1, cut + 1)
  local pat = head:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1"):gsub("%%s", ".-"):gsub("%%d", "(%%d+)")
  return "^" .. pat
end
local function onXPMessage(msg)
  if not session or not msg then return end
  killXPPattern = killXPPattern or buildKillPattern()
  local n = tonumber(msg:match(killXPPattern) or "")
  if n then session.killXP = (session.killXP or 0) + n; session.kills = (session.kills or 0) + 1 end
end

-- ---------- trainer ----------
-- Every ability the trainer has: the window's filters (available / too high a level / already known) are switched
-- on while it's read, then put back, so costs for abilities you've learned or can't learn yet are recorded too.
local scanningTrainer, lastTrainerNote = false, 0
local TRAINER_STATUS = { available = true, unavailable = true, used = true, header = true }
local function passOk(ok, ...) if ok then return ... end return nil end
local function call(fn, ...) if not fn then return nil end return passOk(pcall(fn, ...)) end
local function onTrainer()
  if scanningTrainer or not GetNumTrainerServices then return end
  scanningTrainer = true
  local saved = {}
  if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
    for _, k in ipairs({ "available", "unavailable", "used" }) do
      local v = call(GetTrainerServiceTypeFilter, k)
      saved[k] = (v == true or v == 1)
      if not saved[k] then call(SetTrainerServiceTypeFilter, k, 1) end
    end
  end
  local npc, npcName, n, priced = nil, nil, 0, 0
  local ok, err = pcall(function()
  npc = npcIdFromGUID(call(UnitGUID, "npc"))
  npcName = call(UnitName, "npc")
  n = call(GetNumTrainerServices) or 0
  for i = 1, n do
    -- older clients give name, rank, status; this one gives name, status, icon (and no rank text)
    local name, x, y = call(GetTrainerServiceInfo, i)
    local rank, category = x, y
    if TRAINER_STATUS[x] then rank, category = nil, x end
    if name and category ~= "header" then
      local cost = call(GetTrainerServiceCost, i)
      local line = call(GetTrainerServiceSkillLine, i)            -- profession trainers: which profession
      local sk, skr = call(GetTrainerServiceSkillReq, i)          -- and the skill it needs (e.g. Alchemy 50)
      local lv = call(GetTrainerServiceLevelReq, i)
      -- name, rank and level: this client's trainer has no rank text, so the level keeps each rank apart
      char.trainer[name .. "|" .. (rank or "") .. "|" .. (lv or "")] = { n = name, r = rank, cost = cost, lv = lv, npc = npc, npcName = npcName,
        at = now(), state = category, line = line, sk = sk, skr = skr }
      if cost then priced = priced + 1 end
    end
  end
  end)
  for k, v in pairs(saved) do if not v then call(SetTrainerServiceTypeFilter, k, 0) end end
  scanningTrainer = false
  if not ok then safe(error, "trainer scan: " .. tostring(err), 0) return end
  if priced > 0 and now() - lastTrainerNote > 30 then
    lastTrainerNote = now()
    print("|cffd9aa5aLeveling Ledger|r: recorded " .. priced .. " training cost" .. (priced == 1 and "" or "s") .. (npcName and (" from " .. npcName) or "") .. ". Type /reload to send them to the ledger.")
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
          if not lootSeen[guid] then
            lootSeen[guid] = true; e.opens = e.opens + 1
            -- an object (herb, ore, chest): where you gathered it, for the page's gathering map
            if npc < 0 and not inInstance then safe(function()
              local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
              local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
              local x, y = nil, nil
              if pos and pos.GetXY then x, y = pos:GetXY() end
              if x and y and x > 0 and y > 0 then
                char.gathers = char.gathers or {}
                table.insert(char.gathers, { o = -npc, z = z, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10, at = now() })
                trim(char.gathers, 3000)
              end
            end) end
          end
          -- leather or hide from a creature: a skinning spot (once per corpse), for the gathering map
          if npc > 0 and not inInstance and not skinSeen[guid] and GetItemInfoInstant then
            local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(id)
            if classID == 7 and subClassID == 6 then
              skinSeen[guid] = true
              safe(function()
                local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
                local x, y = nil, nil
                if pos and pos.GetXY then x, y = pos:GetXY() end
                if x and y and x > 0 and y > 0 then
                  char.gathers = char.gathers or {}
                  table.insert(char.gathers, { o = npc, s = 1, z = z, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10, at = now() })
                  trim(char.gathers, 3000)
                end
              end)
            end
          end
          local it = e.items[id] or { n = nameFromLink(link), q = qualityFromLink(link), c = 0 }
          it.c = it.c + 1
          e.items[id] = it
          char.loot[npc] = e
        end
      end
    end
  end
end

-- ---------- in-game panel ----------
-- A small movable window: session time, XP and XP per hour, time to level, kills, gold earned, rested XP.
-- /ledger show | hide | lock | unlock | reset
local panel, lines
local function fmtNum(n)
  local str = tostring(math.floor((n or 0) + 0.5))
  local k
  repeat str, k = str:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return str
end
local function fmtClock(sec)
  sec = math.max(0, math.floor(sec or 0))
  local h, m, x = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, x) end
  return string.format("%d:%02d", m, x)
end
local function fmtDur(sec)
  if not sec or sec ~= sec or sec <= 0 or sec == math.huge then return "-" end
  local m = math.floor(sec / 60 + 0.5)
  if m < 60 then return m .. "m" end
  return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end
local function fmtMoney(c)
  c = math.floor(c or 0)
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. "g" end
  if sv > 0 then t[#t + 1] = sv .. "s" end
  if cp > 0 or #t == 0 then t[#t + 1] = cp .. "c" end
  return table.concat(t, " ")
end

-- ---------- look: WoW's own tooltip border, gold labels, the game's icons ----------
local GOLD, BLUE, WHITE = "|cffffd100", "|cff4d8ff0", "|r"
local RED, GREEN = "|cffff5040", "|cff40d060"

-- Training: from the latest visit to your class trainer, what you can train now, or else what the next level costs.
local function nextTraining(lvl)
  local last = 0
  for _, t in pairs(char.trainer or {}) do if t.cost and not t.sk and t.line ~= "Riding" then last = math.max(last, t.at or 0) end end
  if last == 0 then return nil end
  local nowCost, nowN, nextLv, nextCost, nextN = 0, 0, nil, 0, 0
  for _, t in pairs(char.trainer) do
    local st = TRAINER_STATUS[t.r] and t.r or t.state
    if t.cost and not t.sk and t.line ~= "Riding" and (t.at or 0) >= last - 300 then
      if st == "available" then nowCost, nowN = nowCost + t.cost, nowN + 1
      elseif st == "unavailable" and (t.lv or 0) > lvl and (not nextLv or t.lv < nextLv) then nextLv = t.lv end
    end
  end
  if nextLv then
    for _, t in pairs(char.trainer) do
      local st = TRAINER_STATUS[t.r] and t.r or t.state
      if t.cost and not t.sk and t.line ~= "Riding" and (t.at or 0) >= last - 300 and st == "unavailable" and t.lv == nextLv then nextCost, nextN = nextCost + t.cost, nextN + 1 end
    end
  end
  return nowCost, nowN, nextLv, nextCost, nextN
end
-- The most rested other character on this account (estimated since they logged out; 5% of a level per 8 hours resting,
-- a quarter of that outside, up to one and a half levels)
local function bestAlt(cap)
  local best, bestPct
  for _, c in pairs(db.chars or {}) do
    local bar = c.xpMax and c.level and c.xpMax[c.level]
    if c ~= char and bar and bar > 0 and (c.level or 0) < cap and c.stateAt then
      local gained = bar * 0.05 * ((now() - c.stateAt) / 28800) * (c.resting and 1 or 0.25)
      local pct = math.min(1.5, ((c.rested or 0) + gained) / bar)
      if pct >= 0.25 and (not bestPct or pct > bestPct) then best, bestPct = c, pct end
    end
  end
  return best, bestPct
end
-- frames get a BackdropTemplate where the client needs it (modern clients), plain frames otherwise
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local function styleFrame(fr, alpha)
  if fr.SetBackdrop then
    fr:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    fr:SetBackdropColor(0.07, 0.05, 0.03, alpha or 0.9)
    fr:SetBackdropBorderColor(0.85, 0.68, 0.3, 1)
  else
    local bg = fr:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    if bg.SetColorTexture then bg:SetColorTexture(0.07, 0.05, 0.03, alpha or 0.9) else bg:SetTexture(0, 0, 0, alpha or 0.9) end
  end
end
-- money with the game's coin icons where the client has them
local function coins(c)
  if GetCoinTextureString then local ok, s = pcall(GetCoinTextureString, math.floor(c or 0)); if ok and s then return s end end
  return fmtMoney(c)
end
local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12:12|t"

local function updatePanel()
  if not panel or not panel:IsShown() then return end
  if not session or not char then
    lines[1]:SetText("Waiting for your character...")
    for i = 2, #lines do lines[i]:SetText("") end
    return
  end
  local el = now() - (session.start or now())
  local xp = session.xpGained or 0
  local rate = (el >= 60 and xp > 0) and xp / el * 3600 or nil
  local lvl, cap = UnitLevel("player"), (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
  local togo = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
  lines[1]:SetText(GOLD .. "Session" .. WHITE .. "  " .. fmtClock(el))
  lines[2]:SetText(GOLD .. "XP" .. WHITE .. "  " .. fmtNum(xp) .. (rate and ("   " .. GOLD .. "per hour" .. WHITE .. " " .. fmtNum(rate)) or ""))
  if lvl >= cap then lines[3]:SetText(GOLD .. "Max level" .. WHITE)
  else lines[3]:SetText(GOLD .. "Level " .. (lvl + 1) .. " in" .. WHITE .. "  " .. (rate and fmtDur(togo / rate * 3600) or "-") .. "   " .. fmtNum(togo) .. " XP to go") end
  local earned = 0
  for k, v in pairs(session.moneyIn or {}) do if k ~= "mail" then earned = earned + v end end
  local rested = GetXPExhaustion() or 0
  lines[4]:SetText(SKULL .. " " .. fmtNum(session.kills or 0) .. "    +" .. coins(earned) .. (rested > 0 and ("    " .. BLUE .. "Rested " .. fmtNum(rested) .. WHITE) or ""))
  -- training: now, or the next level, against the gold you carry
  local nowCost, nowN, nextLv, nextCost = nextTraining(lvl)
  local gold = GetMoney() or 0
  if not nowCost then lines[5]:SetText(GOLD .. "Training" .. WHITE .. "  visit your trainer to record costs")
  elseif nowN > 0 then lines[5]:SetText(GOLD .. "Train now" .. WHITE .. "  " .. coins(nowCost) .. (gold < nowCost and ("  " .. RED .. "short " .. WHITE .. coins(nowCost - gold)) or ""))
  elseif nextLv then lines[5]:SetText(GOLD .. "Level " .. nextLv .. " training" .. WHITE .. "  " .. coins(nextCost) .. "  " .. (gold < nextCost and (RED .. "short " .. WHITE .. coins(nextCost - gold)) or (GREEN .. "covered" .. WHITE)))
  else lines[5]:SetText(GOLD .. "Training" .. WHITE .. "  nothing left to train") end
  local alt, pct = bestAlt(cap)
  lines[6]:SetText(alt and (GOLD .. "Best alt" .. WHITE .. "  " .. alt.name .. "  " .. BLUE .. math.floor(pct * 100 + 0.5) .. "% of a level rested" .. WHITE) or "")
end

local function placePanel()
  panel:ClearAllPoints()
  local p = db.panel
  if p.point then panel:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
  else panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -200) end
end

local function createPanel()
  if panel or not CreateFrame or not UIParent then return end
  db.panel = db.panel or { shown = true }
  local p = CreateFrame("Frame", "LevelingLedgerPanel", UIParent, BACKDROP_TEMPLATE)
  p:SetSize(290, 116)
  p:SetFrameStrata("MEDIUM")
  p:SetClampedToScreen(true)
  p:SetMovable(true)
  p:EnableMouse(true)
  p:RegisterForDrag("LeftButton")
  -- (the panel holds a secure Save button, so it can't move during a fight)
  p:SetScript("OnDragStart", function(self) if not db.panel.locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
  p:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.panel.point, db.panel.relPoint, db.panel.x, db.panel.y = point, relPoint, x, y
  end)
  styleFrame(p, 0.82)
  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", 9, -8)
  title:SetText("|TInterface\\Icons\\INV_Misc_Book_09:14:14|t Leveling Ledger")
  local save = ns.secureReload(nil, p, "UIPanelButtonTemplate")
  save:SetSize(52, 18); save:SetPoint("TOPRIGHT", -6, -5); save:SetText("Save")
  save:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Save to the ledger"); GameTooltip:AddLine("Reloads the interface so the page updates in a few seconds.", 1, 1, 1, true); GameTooltip:Show() end end)
  save:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  lines = {}
  for i = 1, 6 do
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 10, -10 - i * 15)
    fs:SetJustifyH("LEFT")
    lines[i] = fs
  end
  panel = p
  placePanel()
  local acc = 0
  p:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc >= 1 then acc = 0; safe(updatePanel) end
  end)
  if db.panel.shown == false then p:Hide() else p:Show(); safe(updatePanel) end
end

-- ---------- events ----------
listen(f, "ADDON_LOADED")
listen(f, "PLAYER_LOGIN")
listen(f, "PLAYER_LOGOUT")
listen(f, "PLAYER_XP_UPDATE")
listen(f, "PLAYER_LEVEL_UP")
listen(f, "TIME_PLAYED_MSG")
listen(f, "ADDON_ACTION_FORBIDDEN")
listen(f, "ADDON_ACTION_BLOCKED")
listen(f, "QUEST_TURNED_IN")
listen(f, "TRAINER_SHOW")
listen(f, "TRAINER_UPDATE")
listen(f, "MERCHANT_SHOW")
listen(f, "MERCHANT_UPDATE")
listen(f, "LOOT_OPENED")
listen(f, "PLAYER_DEAD")
listen(f, "ZONE_CHANGED_NEW_AREA")
listen(f, "ZONE_CHANGED")
listen(f, "ZONE_CHANGED_INDOORS")
listen(f, "UPDATE_EXHAUSTION")
listen(f, "PLAYER_UPDATE_RESTING")
listen(f, "PLAYER_TARGET_CHANGED")
listen(f, "PLAYER_MONEY")
for _, e in ipairs({ "UPDATE_FACTION", "CHAT_MSG_COMBAT_FACTION_CHANGE", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "CHAT_MSG_SYSTEM", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do listen(f, e) end
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do listen(f, e) end
for _, e in ipairs({ "MERCHANT_CLOSED", "TRAINER_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do listen(f, e) end
listen(f, "CHAT_MSG_COMBAT_XP_GAIN")

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    LevelingLedgerDB = LevelingLedgerDB or {}
    db = LevelingLedgerDB
    db.version, db.chars = VERSION, db.chars or {}
  elseif event == "PLAYER_LOGIN" then
    safe(function()
      local key, first, surname = charKey(), nameParts()
      -- before 1.0.46 every character was filed under first name and realm, so two characters with one first name
      -- shared (and overwrote) one entry: it goes to the character of its class, the other starts its own
      local old = oldKey()
      if old ~= key and not db.chars[key] and type(db.chars[old]) == "table" then
        local o = db.chars[old]
        if not o.class or o.class == select(2, UnitClass("player")) then db.chars[key] = o; db.chars[old] = nil end
      end
      char = db.chars[key] or {}
      db.chars[key] = char
      char.name, char.realm = first, GetRealmName()
      char.surname = surname
      char.guid = UnitGUID and UnitGUID("player") or char.guid
      char.class, char.race, char.faction = select(2, UnitClass("player")), select(2, UnitRace("player")), UnitFactionGroup("player")
      char.level = UnitLevel("player")
      for _, k in ipairs({ "sessions", "levels", "xpMax", "quests", "trainer", "vendors", "loot" }) do char[k] = char[k] or {} end
      char.deaths = char.deaths or 0
      char.xpMax[char.level] = UnitXPMax("player")
      startSession(); noteZone(); noteState(); scanSkills(); scanReps(); scanBags(); askMissingNames()
      createPanel()
    end)
  elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
    -- the game stopped something this add-on did: say what, here and on the Settings page
    local who, what = ...
    if who == ADDON and db then
      local msg = (event == "ADDON_ACTION_FORBIDDEN" and "The game blocked " or "The game blocked (taint) ") .. tostring(what or "an action")
      db.errors = db.errors or {}; table.insert(db.errors, { at = now(), err = msg }); trim(db.errors, 20)
      print("|cffd9aa5aLeveling Ledger|r: " .. msg .. ". Please tell the add-on's maintainer.")
    end
  elseif not char then
    return
  elseif event == "PLAYER_LOGOUT" then
    -- the save time first: the app only imports a file whose save time is newer, so a failing step below mustn't block it
    db.savedAt = now()
    loggingOut = true
    safe(onXP); safe(closeSession); safe(noteState)
  elseif event == "PLAYER_XP_UPDATE" then safe(onXP); safe(noteState)
  elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then safe(noteState)
  elseif event == "PLAYER_LEVEL_UP" then local lvl = ...; safe(onLevelUp, lvl)
  elseif event == "TIME_PLAYED_MSG" then local total, thisLevel = ...; safe(onPlayed, total, thisLevel); after(0.5, unmutePlayed) -- after every chat window has had this reply
  elseif event == "QUEST_TURNED_IN" then local q, xp, money = ...; safe(onQuestTurnedIn, q, xp, money); safe(onQuestMoney, money)
  elseif event == "PLAYER_MONEY" then safe(onMoney); safe(noteState)
  elseif event == "BAG_UPDATE_DELAYED" then safe(scanBags); safe(scanBank)
  elseif event == "GET_ITEM_INFO_RECEIVED" then local id = ...; safe(ns.onItemInfo, id)
  elseif event == "BANKFRAME_OPENED" then bankOpen = true; safe(scanBank)
  elseif event == "PLAYERBANKSLOTS_CHANGED" then safe(scanBank)
  elseif event == "BANKFRAME_CLOSED" then bankOpen = false
  elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then safe(scanSkills)
  elseif event == "UPDATE_FACTION" or event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then safe(scanReps)
  elseif event == "CHAT_MSG_SYSTEM" then local msg = ...; safe(onSystemMessage, msg)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "TRADE_SKILL_LIST_UPDATE" then safe(scanTradeSkills)
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then safe(scanCrafts)
  elseif event == "MERCHANT_CLOSED" then where.merchant = nil
  elseif event == "TRAINER_CLOSED" then where.trainer = nil
  elseif event == "MAIL_SHOW" then where.mail = true
  elseif event == "MAIL_CLOSED" then where.mail = nil
  elseif event == "AUCTION_HOUSE_SHOW" then where.auction = true
  elseif event == "AUCTION_HOUSE_CLOSED" then where.auction = nil
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then where.trainer = true; safe(onTrainer)
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then where.merchant = true; safe(onMerchant)
  elseif event == "LOOT_OPENED" then safe(onLoot)
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then local msg = ...; safe(onXPMessage, msg)
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

-- ---------- shared with Alts.lua ----------
ns.db = function() return db end
ns.char = function() return char end
ns.safe = safe
ns.now = now
ns.idFromLink = idFromLink
ns.fmtMoney = fmtMoney
ns.fmtNum = fmtNum
ns.styleFrame = styleFrame
ns.coins = coins
ns.BACKDROP_TEMPLATE = BACKDROP_TEMPLATE

-- ---------- Save: reload the interface, which makes the game write the add-on's file; the app imports it in seconds ----------
-- This client blocks ReloadUI from add-on code, even on a click. A secure button running the /reload macro is
-- allowed (it's how macros and action bars work), so every Save is one: the key binding clicks a hidden one
-- (Options, Keybindings, AddOns: Leveling Ledger), and the panel and the water break have their own.
BINDING_HEADER_LEVELINGLEDGER = "Leveling Ledger"
_G["BINDING_NAME_CLICK LevelingLedgerSaveButton:LeftButton"] = "Save to the ledger (reload)"
function ns.secureReload(name, parent, extraTemplate)
  local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate" .. (extraTemplate and (", " .. extraTemplate) or ""))
  b:SetAttribute("type", "macro"); b:SetAttribute("macrotext", "/reload")
  b:RegisterForClicks("AnyUp", "AnyDown")
  return b
end
do -- the key binding's button: invisible, off to the side (created at load, out of combat)
  local b = ns.secureReload("LevelingLedgerSaveButton", UIParent)
  b:SetSize(1, 1); b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10); b:SetAlpha(0)
end
function LevelingLedger_Save()
  print("|cffd9aa5aLeveling Ledger|r: type /reload, or press your Save key (Options, Keybindings, AddOns), or the panel's Save button. The game doesn't let add-on code reload by itself.")
end

-- ---------- /ledger ----------
SLASH_LEVELINGLEDGER1 = "/ledger"
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local function panelCommand(cmd)
  if not panel then print(TAG .. "the panel isn't ready yet."); return true end
  if InCombatLockdown and InCombatLockdown() and (cmd == "show" or cmd == "hide" or cmd == "reset") then print(TAG .. "try again once the fight is over."); return true end
  if cmd == "show" then db.panel.shown = true; panel:Show(); safe(updatePanel); print(TAG .. "panel shown.")
  elseif cmd == "hide" then db.panel.shown = false; panel:Hide(); print(TAG .. "panel hidden. /ledger show brings it back.")
  elseif cmd == "lock" then db.panel.locked = true; print(TAG .. "panel locked in place.")
  elseif cmd == "unlock" then db.panel.locked = false; print(TAG .. "panel unlocked; drag it to move it.")
  elseif cmd == "reset" then db.panel.point, db.panel.relPoint, db.panel.x, db.panel.y = nil, nil, nil, nil; db.panel.locked = false; placePanel(); print(TAG .. "panel moved back to its starting spot.")
  else return false end
  return true
end
SlashCmdList.LEVELINGLEDGER = function(msg)
  local cmd = strtrim and strtrim((msg or ""):lower()) or (msg or ""):lower():match("^%s*(.-)%s*$")
  if cmd == "alts" then if ns.toggleAlts then ns.toggleAlts() end return end
  if cmd == "plan" then if ns.planCommand then ns.planCommand() end return end
  if cmd == "save" then LevelingLedger_Save() return end
  if cmd == "recipes" then if ns.recipesCommand then ns.recipesCommand() end return end
  if cmd == "scan" then if ns.ahScanCommand then ns.ahScanCommand() end return end
  if cmd == "chains" or cmd == "chain" then if ns.chainsCommand then ns.chainsCommand() end return end
  local sc = cmd:match("^secrets?%s*(.*)$")
  if sc and ns.secretsCommand then ns.secretsCommand(sc) return end
  local bk = cmd:match("^books?%s*(.*)$")
  if bk and ns.booksCommand then ns.booksCommand(bk) return end
  if cmd == "talents" or cmd == "talent" then if ns.talentsCommand then ns.talentsCommand() end return end
  local w = cmd:match("^water%s*(.*)$")
  if w and ns.waterCommand then ns.waterCommand(w) return end
  if cmd ~= "" and panelCommand(cmd) then return end
  if not char then print("|cffd9aa5aLeveling Ledger|r: not ready yet."); return end
  pcall(requestPlayed) -- typed, so the game allows it; the chat line stays hidden
  local v, l, t = 0, 0, 0
  for _ in pairs(char.vendors) do v = v + 1 end
  for _ in pairs(char.loot) do l = l + 1 end
  for _ in pairs(char.trainer) do t = t + 1 end
  print(string.format("|cffd9aa5aLeveling Ledger|r: %d sessions, %d quests, %d trainer spells, %d vendors, %d creatures looted. This session: %d XP, %d kills.",
    #char.sessions, #char.quests, t, v, l, session and session.xpGained or 0, session and session.kills or 0))
  local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ver = meta and meta(ADDON, "Version")
  print("|cffd9aa5aLeveling Ledger|r" .. (ver and " " .. ver or "") .. ": type /reload or log out to save; the Leveling Ledger app imports it within a few seconds.")
  print("|cffd9aa5aLeveling Ledger|r: panel: /ledger show, hide, lock, unlock or reset. Your characters, bags and bank: /ledger alts. Water breaks: /ledger water. Planned quests: /ledger plan. Recipes to buy: /ledger recipes. Save now: /ledger save (or bind a key: Options, Keybindings, AddOns)")
end
