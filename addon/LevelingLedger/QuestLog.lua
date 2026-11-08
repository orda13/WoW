-- Quests in progress: what's in your quest log, each objective's progress, and when you accepted it, so the
-- ledger can show quests in progress and how long each one took. Read from the game's quest log; when Questie
-- is installed, its official API (Questie.API.RegisterForQuestUpdates) also tells us the moment an objective moves.
local ADDON, ns = ...

local function now() return time() end
local pending = false

-- Every quest in the log as { [questID] = { t = title, lv = level, done = true/nil, ob = { { text, have, need, done } } } }
local function readLog()
  local out = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID and info.questID > 0 then
        local q = { t = info.title, lv = info.level, ob = {} }
        q.done = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)) or nil
        for _, o in ipairs((C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(info.questID)) or {}) do
          table.insert(q.ob, { text = o.text, have = o.numFulfilled, need = o.numRequired, done = o.finished or nil })
        end
        out[info.questID] = q
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, GetNumQuestLogEntries() do
      local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
      if not isHeader and questID and questID > 0 then
        local q = { t = title, lv = level, done = (isComplete == 1) or nil, ob = {} }
        for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i)) or 0 do
          local text, _, finished = GetQuestLogLeaderBoard(j, i)
          local have, need = (text or ""):match("(%d+)/(%d+)")
          table.insert(q.ob, { text = text, have = tonumber(have), need = tonumber(need), done = finished or nil })
        end
        out[questID] = q
      end
    end
  end
  return out
end

-- Keep the log in char.questLog, with the time each quest was first seen (accepted), and how long turned-in ones took
local function refresh()
  pending = false
  local char = ns.char and ns.char()
  if not char then return end
  local log = readLog()
  local old = char.questLog or {}
  for id, q in pairs(log) do q.at = (old[id] and old[id].at) or now() end
  char.questLog = log
  char.questLogAt = now()
end
local function soon() if not pending then pending = true; if C_Timer and C_Timer.After then C_Timer.After(0.5, function() ns.safe(refresh) end) else ns.safe(refresh) end end end

-- How long a quest took, for the turn-in record (called by LevelingLedger.lua before the quest leaves the log)
function ns.questTook(questID)
  local char = ns.char and ns.char()
  local q = char and char.questLog and char.questLog[questID]
  return q and q.at and (now() - q.at) or nil
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then return end
  if event == "PLAYER_LOGIN" then
    -- Questie's official API: refresh as soon as an objective moves
    local api = rawget(_G, "Questie") and Questie.API
    if api and api.RegisterOnReady and api.RegisterForQuestUpdates then
      pcall(api.RegisterOnReady, function() pcall(api.RegisterForQuestUpdates, function() soon() end) end)
    end
  end
  soon()
end)
