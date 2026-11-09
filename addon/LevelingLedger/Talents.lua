-- Talent plan reminders: the plan you picked on the Leveling Ledger page's Talents tab (LevelingLedgerShared.talents,
-- written into Shared.lua by the app) names the talent to take when you level up, and at login if points are waiting.
--   /ledger talents     the next picks from your plan
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "

local function plan()
  local all = rawget(_G, "LevelingLedgerShared") and LevelingLedgerShared.talents
  if type(all) ~= "table" then return nil end
  local p = all[string.lower(UnitName("player") or "")]
  if type(p) ~= "table" or type(p.picks) ~= "table" then return nil end
  return p
end
local function pick(p, level)
  local i = level - (tonumber(p.from) or 10) + 1
  return i >= 1 and p.picks[i] or nil
end
-- unspent talent points, when this client says
local function unspent()
  for _, fn in ipairs({ rawget(_G, "UnitCharacterPoints"), rawget(_G, "GetUnspentTalentPoints") }) do
    if type(fn) == "function" then
      local ok, n = pcall(fn, "player")
      if ok and tonumber(n) then return tonumber(n) end
    end
  end
  return nil
end

local function remind(level, points)
  local p = plan(); if not p then return end
  level = level or UnitLevel("player") or 0
  points = points or 1
  local list = {}
  for lv = level - points + 1, level do local t = pick(p, lv); if t then list[#list + 1] = t end end
  if #list > 0 then print(TAG .. "talent" .. (#list > 1 and "s" or "") .. " to take: |cff66ccff" .. table.concat(list, ", ") .. "|r") end
end

function ns.talentsCommand()
  local p = plan()
  if not p then print(TAG .. "no talent plan for this character. Pick one on the Talents tab of the Leveling Ledger page, then /reload once the app has written it.") return end
  local level = UnitLevel("player") or 0
  local n = unspent()
  if n and n > 0 then remind(level, n) end
  local list = {}
  for lv = level + 1, level + 5 do local t = pick(p, lv); if t then list[#list + 1] = lv .. ": " .. t end end
  print(TAG .. (#list > 0 and ("next talents: " .. table.concat(list, ", ")) or "your talent plan is complete."))
end

local f = CreateFrame("Frame")
if ns.listen then ns.listen(f, "PLAYER_LEVEL_UP"); ns.listen(f, "PLAYER_LOGIN")
else pcall(f.RegisterEvent, f, "PLAYER_LEVEL_UP"); pcall(f.RegisterEvent, f, "PLAYER_LOGIN") end
f:SetScript("OnEvent", function(_, event, level)
  if event == "PLAYER_LEVEL_UP" then
    pcall(remind, tonumber(level), 1)
  elseif event == "PLAYER_LOGIN" then
    -- points waiting from earlier levels
    local n = unspent()
    if n and n > 0 and C_Timer and C_Timer.After then C_Timer.After(6, function() pcall(remind, nil, n) end) end
  end
end)
