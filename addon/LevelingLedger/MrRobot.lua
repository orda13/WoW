-- Ask Mr. Robot: when its add-on (Ask Mr. Robot Classic) is installed, copies what you imported into it from
-- askmrrobot.com/forever into this add-on's save at logout or /reload, so the Leveling Ledger page can show it:
-- each gear setup's item per slot (with its enchant), the items it says to sell, and the ones to keep.
-- Only reads Ask Mr. Robot's saved table (AskMrRobotDb5); never changes it or calls its code.
local ADDON, ns = ...

local function copy()
  local sv = rawget(_G, "AskMrRobotDb5")
  if type(sv) ~= "table" or type(sv.char) ~= "table" then return end
  local name, realm = UnitName("player") or "?", GetRealmName() or ""
  local me = sv.char[name .. " - " .. realm]            -- AceDB's key for this character
  local db = LevelingLedgerDB
  if type(me) ~= "table" or type(db) ~= "table" or type(db.chars) ~= "table" then return end
  local c = db.chars[name .. "-" .. realm]
  if type(c) ~= "table" then return end
  local out = { at = time(), setups = {}, junk = {}, keep = {}, names = {} }
  -- the item's name when the game has it cached (your gear and bags always are), so the page can show it
  local id = function(it)
    local n = type(it) == "table" and tonumber(it.id) or nil
    if n and not out.names[n] then
      local nm = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(n)) or (GetItemInfo and GetItemInfo(n))
      if type(nm) == "string" then out.names[n] = nm end
    end
    return n
  end
  for _, s in ipairs(type(me.GearSetups) == "table" and me.GearSetups or {}) do
    if type(s) == "table" and type(s.Gear) == "table" then
      local gear = {}
      for slot, it in pairs(s.Gear) do
        if type(slot) == "number" and id(it) then gear[#gear + 1] = { slot, id(it), tonumber(it.enchantId) or 0 } end
      end
      if #gear > 0 then
        out.setups[#out.setups + 1] = { label = tostring(s.Label or "Setup"), spec = tonumber(s.SpecSlot) or 0, bib = s.IsBib and 1 or 0, gear = gear }
      end
    end
  end
  local jd = type(me.JunkData) == "table" and me.JunkData or {}
  for _, it in ipairs(type(jd.Junk) == "table" and jd.Junk or {}) do if id(it) then out.junk[#out.junk + 1] = id(it) end end
  for _, it in pairs(type(jd.Keep) == "table" and jd.Keep or {}) do if id(it) then out.keep[#out.keep + 1] = id(it) end end
  if #out.setups > 0 or #out.junk > 0 then c.amr = out end
end

local f = CreateFrame("Frame")
if ns.listen then ns.listen(f, "PLAYER_LOGOUT") else pcall(f.RegisterEvent, f, "PLAYER_LOGOUT") end
f:SetScript("OnEvent", function() pcall(copy) end)
