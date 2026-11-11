-- Quests planned on the Leveling Ledger page (LevelingLedgerShared.plans, written by the app into Shared.lua),
-- shown through Questie:
--   * in your quest log: tracked (the game's own quest watch, which Questie's tracker follows on Forever)
--   * not picked up yet: the quest giver is pinned on Questie's map and minimap as "Planned: <quest>"
-- The pins use Questie's internals (QuestieLoader modules), not its public API, which has nothing for this. Every
-- call is checked and wrapped in pcall: if a Questie update changes them, the pins stop and nothing else breaks.
--   /ledger plan    lists the plan and where each quest stands
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local ICON = "Interface\\AddOns\\Questie\\Icons\\available.blp"

local function plan()
  local all = rawget(_G, "LevelingLedgerShared") and LevelingLedgerShared.plans
  local p = ns.forMe and ns.forMe(all)
  return type(p) == "table" and p or {}
end
local function completed(id) return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) end
local function inLog(id) return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) end
local function questie(name)
  local L = rawget(_G, "QuestieLoader")
  if type(L) ~= "table" or type(L.ImportModule) ~= "function" then return nil end
  local ok, m = pcall(L.ImportModule, L, name)
  return ok and type(m) == "table" and m or nil
end

-- Track a planned quest that's in the log (out of combat: quest watches change the objective tracker)
local function track(id)
  if not (C_QuestLog and C_QuestLog.AddQuestWatch and inLog(id)) then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  if C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(id) ~= nil then return true end
  return (pcall(C_QuestLog.AddQuestWatch, id))
end

local pinned = {}
-- Pin the quest giver of a planned quest you haven't picked up
local function pin(id, title)
  if pinned[id] then return true end
  local DB, Map, Q = questie("QuestieDB"), questie("QuestieMap"), questie("QuestieQuest")
  if not (DB and Map and type(DB.GetQuest) == "function" and type(Map.ShowNPC) == "function") then return false end
  local ok, quest = pcall(DB.GetQuest, id)
  if not ok or type(quest) ~= "table" then return false end
  -- a quest you hid in Questie comes back
  local hidden = rawget(_G, "Questie") and Questie.db and Questie.db.char and Questie.db.char.hidden
  if Q and type(Q.UnhideQuest) == "function" and type(hidden) == "table" and hidden[id] then pcall(Q.UnhideQuest, Q, id) end
  local name = quest.name or title or ("Quest " .. id)
  local body = { { "Planned in", "Leveling Ledger" }, { "Quest", name }, { "Level", tostring(quest.level or "?") } }
  local starts, any = quest.Starts or {}, false
  for _, npc in ipairs(type(starts.NPC) == "table" and starts.NPC or {}) do
    if pcall(Map.ShowNPC, Map, npc, ICON, 1.1, "Planned: " .. name, body, true) then any = true end
  end
  if type(Map.ShowObject) == "function" then
    for _, obj in ipairs(type(starts.GameObject) == "table" and starts.GameObject or {}) do
      if pcall(Map.ShowObject, Map, obj, ICON, 1.1, "Planned: " .. name, body, true) then any = true end
    end
  end
  pinned[id] = any
  return any
end

local function apply()
  for key, title in pairs(plan()) do
    local id = tonumber(key)
    if id and not completed(id) then
      if inLog(id) then track(id) else pin(id, title) end
    end
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_ACCEPTED", "PLAYER_REGEN_ENABLED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
local function later(sec, fn) if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end end
f:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "PLAYER_LOGIN" then
    local api = rawget(_G, "Questie") and Questie.API
    if api and type(api.RegisterOnReady) == "function" then pcall(api.RegisterOnReady, function() ns.safe(apply) end) end
  elseif event == "QUEST_ACCEPTED" then
    -- a planned quest picked up: track it once Questie has registered it
    local id = tonumber(a2) or tonumber(a1)
    if id and plan()[id] then later(1.5, function() ns.safe(track, id) end) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    ns.safe(apply) -- anything held back during a fight
  end
end)

function ns.planCommand()
  local p, n = plan(), 0
  for key, title in pairs(p) do
    local id = tonumber(key); n = n + 1
    local where = completed(id) and "|cff40d060done|r" or inLog(id) and "in your quest log, tracked"
      or (pinned[id] and "quest giver pinned on the map") or (rawget(_G, "QuestieLoader") and "not pinned (Questie has no location for it)") or "install Questie to see it on the map"
    print(TAG .. tostring(title) .. " (" .. id .. "): " .. where)
  end
  if n == 0 then print(TAG .. "no planned quests for " .. (UnitName("player") or "this character") .. ". Plan some on the ledger page's Quests tab, then /reload.") end
end
