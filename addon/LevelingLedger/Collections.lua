-- Library Books ("Friend of the Library"): books found around the world and handed in to the librarian, per character.
-- Data: CollectionsData.lua (generated). A book is collected once its hidden quest is completed (handed in); one in your
-- bags is picked up but not handed in yet.
--   * Questie map pins: every book this character still needs (your faction's), with a book icon; a pin goes away when
--     you pick the book up or hand it in. Uses Questie's internals like the planned-quest pins: every call checked and in
--     pcall, so a Questie update only turns the pins off.
--   * At logout the add-on saves which books this character has, for the ledger page.
--   /ledger books            how many you have, and the next ones to get with /way lines
--   /ledger books pins off   no map pins (on brings them back)
--   /ledger chains           your step in each quest chain (Cozy Sleeping Bag), pinned on Questie's map
--   /ledger secrets          the WoW Forever secrets you haven't done yet, with /way lines; pinned on Questie's map
--   /ledger secrets pins off no secret pins (on brings them back)
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
-- ---------- quest chains (Cozy Sleeping Bag): a pin on the step you're on ----------
local CHAIN_BASE = 995000
local function qdone(q) return q and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q) or false end
local function qlog(q) return q and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q) and true or false end
local function chainSteps(c) return (c.steps or {})[myFac() or "A"] or {} end
local function stepDone(st) return st.quest and (qdone(st.quest) or (st.start and qlog(st.quest))) or false end
-- the first step still to do (optional steps are skipped), and its number
local function current(c)
  for i, st in ipairs(chainSteps(c)) do if not st.optional and not stepDone(st) then return st, i end end
end
local chainPinned = {}
local function refreshChains()
  local Map, Zone = questie("QuestieMap"), questie("ZoneDB")
  for ci, c in ipairs(ns.questChains or {}) do
    local id = CHAIN_BASE + ci
    local st, i = current(c)
    local key = st and (i .. ":" .. st.map) or nil
    if chainPinned[ci] ~= key and chainPinned[ci] and Map and type(Map.UnloadManualFrames) == "function" then pcall(Map.UnloadManualFrames, Map, id, TYP); chainPinned[ci] = nil end
    if st and pinsOn() and (UnitLevel("player") or 0) >= (c.level or 1) and not chainPinned[ci] and Map and Zone
       and type(Map.DrawManualIcon) == "function" and type(Zone.GetAreaIdByUiMapId) == "function" then
      local ok, area = pcall(Zone.GetAreaIdByUiMapId, Zone, st.map)
      if ok and type(area) == "number" then
        local data = { id = id, Icon = "Interface\\Icons\\INV_Misc_Bag_BigBagofEnchantments", Type = "manual", spawnType = "object", Name = c.name, IsObjectiveNote = false }
        data.GetIconScale = function() return 1.2 end
        data.IconScale = 1.2
        data.ManualTooltipData = { Title = c.name .. ", step " .. i .. ": " .. st.title,
          Body = { { "Step", i .. " of " .. #chainSteps(c) }, { "Where", st.zone }, { "From", "Leveling Ledger" } }, disableShiftToRemove = true }
        if pcall(Map.DrawManualIcon, Map, data, area, st.x, st.y, TYP) then chainPinned[ci] = key end
      end
    end
  end
end
function ns.chainsCommand()
  for _, c in ipairs(ns.questChains or {}) do
    local st, i = current(c)
    if not st then print(TAG .. c.name .. ": done.")
    elseif (UnitLevel("player") or 0) < (c.level or 1) then print(TAG .. c.name .. ": starts at level " .. c.level .. ".")
    else print(TAG .. c.name .. ", step " .. i .. " of " .. #chainSteps(c) .. ": " .. st.title .. " (" .. st.zone .. ") " .. string.format("/way #%d %.1f, %.1f %s", st.map, st.x, st.y, st.title)) end
  end
end

-- ---------- secrets (ns.secrets): done when the game shows it (a quest, an item, a whole set, a toy, a pet), when the
-- add-on saw it done before, or when it's ticked on the page (LevelingLedgerShared.secrets); pins on the spots of the rest ----------
local SECRET_BASE, SECRET_TYP = 996000, "LevelingLedgerSecrets"
local function myClass() return UnitClass and select(2, UnitClass("player")) or nil end
local function secretFits(sc)
  if sc.class and myClass() and sc.class ~= myClass() then return false end
  if sc.fac and myFac() and sc.fac ~= myFac() then return false end
  return true
end
local function owned(item) -- an item id or name, in bags, bank or worn
  local count = 0
  if C_Item and C_Item.GetItemCount then local ok, n = pcall(C_Item.GetItemCount, item, true); if ok then count = tonumber(n) or 0 end end
  if count == 0 and GetItemCount then local ok, n = pcall(GetItemCount, item, true); if ok then count = tonumber(n) or 0 end end
  if count == 0 and IsEquippedItem then local ok, e = pcall(IsEquippedItem, item); if ok and e then count = 1 end end
  return count > 0
end
local function hasToy(id) return id and PlayerHasToy and select(2, pcall(PlayerHasToy, id)) == true end
local function hasPet(itemID)
  if not (itemID and C_PetJournal and C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetNumCollectedInfo) then return false end
  local ok, species = pcall(function() return select(13, C_PetJournal.GetPetInfoByItemID(itemID)) end)
  if not ok or not species then return false end
  local ok2, n = pcall(C_PetJournal.GetNumCollectedInfo, species)
  return ok2 and (tonumber(n) or 0) > 0
end
local function savedSecrets()
  local db = ns.db and ns.db(); local c = db and db.chars and db.chars[(UnitName("player") or "?") .. "-" .. (GetRealmName() or "")]
  local d = {}; for _, id in ipairs(type(c) == "table" and c.secrets and c.secrets.done or {}) do d[id] = true end
  return d
end
local function ticked(id)
  local all = rawget(_G, "LevelingLedgerShared") and LevelingLedgerShared.secrets
  local mineT = type(all) == "table" and all[string.lower(UnitName("player") or "")]
  return type(mineT) == "table" and mineT[id] and true or false
end
local function secretSeen(sc) -- what the game itself shows right now
  local h = sc.have or {}
  for _, q in ipairs(h.quests or {}) do if qdone(q) then return true end end
  for _, i in ipairs(h.items or {}) do if owned(i) then return true end end
  for _, n in ipairs(h.names or {}) do if owned(n) then return true end end
  if h.allItems and #h.allItems > 0 then local all = true; for _, i in ipairs(h.allItems) do if not owned(i) then all = false; break end end; if all then return true end end
  if hasToy(h.toy) or hasPet(h.pet) then return true end
  return false
end
local function secretDone(sc, saved) return (saved or savedSecrets())[sc.id] or ticked(sc.id) or secretSeen(sc) end
local function secretPinsOn() local db = ns.db and ns.db(); return not (db and db.secretPins == false) end
local secretPinned = {}
local function refreshSecrets()
  local Map, Zone = questie("QuestieMap"), questie("ZoneDB")
  local saved, lvl = savedSecrets(), (UnitLevel("player") or 0)
  for si, sc in ipairs(ns.secrets or {}) do
    local want = secretPinsOn() and sc.status == "solved" and secretFits(sc) and lvl >= (sc.level or 1) - 3 and not secretDone(sc, saved)
    for k, st in ipairs(sc.steps or {}) do
      local id = SECRET_BASE + si * 20 + k
      if not want and secretPinned[id] then
        if Map and type(Map.UnloadManualFrames) == "function" then pcall(Map.UnloadManualFrames, Map, id, SECRET_TYP) end
        secretPinned[id] = nil
      elseif want and not secretPinned[id] and Map and Zone and type(Map.DrawManualIcon) == "function" and type(Zone.GetAreaIdByUiMapId) == "function" then
        local ok, area = pcall(Zone.GetAreaIdByUiMapId, Zone, st.map)
        if ok and type(area) == "number" then
          local data = { id = id, Icon = "Interface\\Icons\\INV_Misc_QuestionMark", Type = "manual", spawnType = "object", Name = sc.name, IsObjectiveNote = false }
          data.GetIconScale = function() return 1.1 end
          data.IconScale = 1.1
          data.ManualTooltipData = { Title = "Secret: " .. sc.name, Body = { { "Here", st.title }, { "Where", st.zone }, { "More", "/ledger secrets, or the Collectables tab" }, { "From", "Leveling Ledger" } }, disableShiftToRemove = true }
          if pcall(Map.DrawManualIcon, Map, data, area, st.x, st.y, SECRET_TYP) then secretPinned[id] = true end
        end
      end
    end
  end
end
function ns.secretsCommand(arg)
  arg = (arg or ""):match("^%s*(.-)%s*$")
  local db = ns.db and ns.db()
  if arg == "pins off" then if db then db.secretPins = false end; refreshSecrets(); print(TAG .. "Secret pins are off. /ledger secrets pins on brings them back.") return end
  if arg == "pins on" then if db then db.secretPins = nil end; refreshSecrets(); print(TAG .. "Secret pins are on (Questie's map).") return end
  local saved, have, total, list = savedSecrets(), 0, 0, {}
  for _, sc in ipairs(ns.secrets or {}) do
    if sc.status == "solved" and secretFits(sc) then
      total = total + 1
      if secretDone(sc, saved) then have = have + 1 else list[#list + 1] = sc end
    end
  end
  print(TAG .. "Secrets: " .. have .. " of " .. total .. " done (for your class and faction). Details on the page's Collectables tab.")
  for i, sc in ipairs(list) do
    if i > 8 then print("  ...and " .. (#list - 8) .. " more on the page.") break end
    local st = sc.steps and sc.steps[1]
    print("  " .. sc.name .. (sc.level and (" (level " .. sc.level .. ")") or "") .. (st and string.format(": /way #%d %.1f, %.1f %s", st.map, st.x, st.y, st.title) or ""))
  end
end

local function refresh()
  for _, b in ipairs(books()) do
    if pinsOn() and mine(b) and not done(b) and not inBags(b) then pin(b) else unpin(b) end
  end
  refreshChains()
  refreshSecrets()
end

-- ---------- what this character has, for the page ----------
-- Saved while you play (after quests and bag changes) and again at logout. At logout the game often says no quest is
-- completed and the bags are empty, so then nothing is dropped: handed-in books and completed chain quests only add
-- up (a completed quest stays completed), and the bags and quest log keep what was last seen.
local function keepList(now, before) local out, seen = {}, {}
  for _, l in ipairs({ before or {}, now }) do for _, x in ipairs(l) do if not seen[x] then seen[x] = true; out[#out + 1] = x end end end
  table.sort(out); return out
end
local function save(loggingOut)
  local db = ns.db and ns.db(); if not (db and db.chars) then return end
  local c = db.chars[(UnitName("player") or "?") .. "-" .. (GetRealmName() or "")]
  if type(c) ~= "table" then return end
  local old, oldq = c.books or {}, c.chainq or {}
  local d, g = {}, {}
  for _, b in ipairs(books()) do
    if done(b) then d[#d + 1] = b.n elseif inBags(b) then g[#g + 1] = b.n end
  end
  d = keepList(d, old.done)
  if loggingOut and #g == 0 then g = old.bags or {} end
  local held = {}; for _, n in ipairs(d) do held[n] = true end
  local g2 = {}; for _, n in ipairs(g) do if not held[n] then g2[#g2 + 1] = n end end
  c.books = { done = d, bags = g2, at = time() }
  -- the chains' quests this character has completed, or has in the quest log
  local qd, ql, seen = {}, {}, {}
  for _, ch in ipairs(ns.questChains or {}) do
    for _, st in ipairs(chainSteps(ch)) do
      local q = st.quest
      if q and not seen[q] then
        seen[q] = true
        if qdone(q) then qd[#qd + 1] = q elseif qlog(q) then ql[#ql + 1] = q end
      end
    end
  end
  qd = keepList(qd, oldq.done)
  if loggingOut and #ql == 0 then ql = oldq.log or {} end
  local isDone = {}; for _, q in ipairs(qd) do isDone[q] = true end
  local ql2 = {}; for _, q in ipairs(ql) do if not isDone[q] then ql2[#ql2 + 1] = q end end
  c.chainq = { done = qd, log = ql2, at = time() }
  -- the secrets the game shows done (once done, always kept)
  local sd = {}
  for _, sc in ipairs(ns.secrets or {}) do if secretSeen(sc) then sd[#sd + 1] = sc.id end end
  c.secrets = { done = keepList(sd, (c.secrets or {}).done), at = time() }
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
    ". Rewards at " .. table.concat(ns.libraryTiers or { 10, 20, 25 }, ", "):gsub(", (%d+)$", " and %1") .. " books.")
  local list = {}
  for _, b in ipairs(here) do list[#list + 1] = b end
  for _, b in ipairs(rest) do if #list < 5 then list[#list + 1] = b end end
  for _, b in ipairs(list) do print("  " .. b.n .. ". " .. b.name .. " (" .. b.zone .. (b.note ~= "" and (", " .. b.note) or "") .. "): " .. way(b)) end
  if not rawget(_G, "QuestieLoader") then print(TAG .. "install Questie to see the books on the map.") end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "NEW_TOY_ADDED", "NEW_PET_ADDED", "PLAYER_EQUIPMENT_CHANGED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
local pending = false
local function soon() if pending then return end pending = true
  local go = function() pending = false; if ns.safe then ns.safe(refresh); ns.safe(save) else pcall(refresh); pcall(save) end end
  if C_Timer and C_Timer.After then C_Timer.After(1, go) else go() end
end
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local api = rawget(_G, "Questie") and Questie.API
    if api and type(api.RegisterOnReady) == "function" then pcall(api.RegisterOnReady, function() soon() end) end
  elseif event == "PLAYER_LOGOUT" then pcall(save, true)
  else soon() end
end)
