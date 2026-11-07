-- Leveling Ledger: your other characters in game.
-- Item tooltips show who else holds the item; /ledger alts shows each character's details, bags and bank;
-- the profession window says what you could make with your alts' materials.
-- Characters on this WoW account come from the add-on's own saved data. Characters on your other devices and
-- accounts come from Shared.lua, which the Leveling Ledger app (or its relay) keeps up to date on each device;
-- for each character, the newer of the two is used.

local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r"

local function shared()
  local sh = LevelingLedgerShared
  return (type(sh) == "table" and type(sh.chars) == "table") and sh or nil
end
local function others()
  local db, me = ns.db and ns.db(), ns.char and ns.char()
  local myKey = me and ((me.name or "") .. "-" .. (me.realm or ""))
  local byKey = {}
  if db and db.chars then for key, c in pairs(db.chars) do if c ~= me then byKey[key] = { key = key, c = c } end end end
  local sh = shared()
  if sh then
    for key, c in pairs(sh.chars) do
      if type(c) == "table" and key ~= myKey then
        local cur = byKey[key]
        if not cur then byKey[key] = { key = key, c = c, remote = true }
        else
          -- the same character recorded here and elsewhere: newer details, bags and bank each win
          local m = {}
          for k, v in pairs(cur.c) do m[k] = v end
          if (c.stateAt or 0) > (cur.c.stateAt or 0) then for _, k in ipairs({ "level", "money", "rested", "zone", "subzone", "stateAt" }) do m[k] = c[k] end end
          if (c.bagsAt or 0) > (cur.c.bagsAt or 0) then m.bags, m.bagsAt = c.bags, c.bagsAt end
          if (c.bankAt or 0) > (cur.c.bankAt or 0) then m.bank, m.bankAt = c.bank, c.bankAt end
          m.account = m.account or c.account
          byKey[key] = { key = key, c = m }
        end
      end
    end
  end
  local out = {}
  for _, o in pairs(byKey) do out[#out + 1] = o end
  table.sort(out, function(a, b) return (a.c.level or 0) > (b.c.level or 0) end)
  return out
end
local function held(c, id) return (c.bags and c.bags[id] or 0), (c.bank and c.bank[id] or 0) end
local function altTotal(id)
  local total, who = 0, {}
  for _, o in ipairs(others()) do
    local bg, bk = held(o.c, id)
    if bg + bk > 0 then total = total + bg + bk; who[#who + 1] = (o.c.name or o.key) .. " " .. (bg + bk) end
  end
  return total, who
end
local function ago(t)
  if not t then return "never" end
  local d = (ns.now() - t) / 86400
  if d < 1 then return "today" elseif d < 2 then return "yesterday" end
  return math.floor(d) .. " days ago"
end
local function cap(s) s = tostring(s or ""):lower(); return (s:gsub("^%l", string.upper)) end
-- class colours and class icons, as the game shows them
local function classHex(class)
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tostring(class or ""):upper()]
  if not c then return "ffd9c9a8" end
  return c.colorStr or string.format("ff%02x%02x%02x", math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
end
local function classIcon(class, size)
  local t = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tostring(class or ""):upper()]
  if not t then return "" end
  size = size or 14
  return string.format("|TInterface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t ", size, size, t[1] * 256, t[2] * 256, t[3] * 256, t[4] * 256)
end
local function cname(c, key) return "|c" .. classHex(c.class) .. (c.name or key or "?") .. "|r" end
local function itemIcon(id)
  local tex = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
  return tex and ("|T" .. tex .. ":14:14|t ") or ""
end

-- ---------- tooltips ----------
local function addTooltipLines(tt, id)
  if not tt or not id then return end
  local any = false
  for _, o in ipairs(others()) do
    local bg, bk = held(o.c, id)
    if bg + bk > 0 then
      if not any then tt:AddLine(" "); any = true end
      local where = {}
      if bk > 0 then where[#where + 1] = "bank " .. bk end
      if bg > 0 then where[#where + 1] = "bags " .. bg end
      tt:AddDoubleLine(classIcon(o.c.class, 12) .. cname(o.c, o.key), ns.fmtNum(bg + bk) .. "  (" .. table.concat(where, ", ") .. ")", 1, 1, 1, 1, 1, 1)
    end
  end
  if any then tt:Show() end
end
local function hookTooltips()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      if tt == GameTooltip or tt == ItemRefTooltip then ns.safe(addTooltipLines, tt, data and data.id) end
    end)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      if tt and tt.HookScript then
        tt:HookScript("OnTooltipSetItem", function(self)
          local _, link = self:GetItem()
          ns.safe(addTooltipLines, self, ns.idFromLink(link))
        end)
      end
    end
  end
end

-- ---------- /ledger alts window ----------
local win, sel, page, query = nil, nil, 1, ""
local PER_PAGE = 18
local function itemName(id)
  local db = ns.db()
  local it = db.items and db.items[id]
  local sh = shared()
  local si = sh and sh.items and sh.items[id]
  local n = (it and it.n) or (si and si[1]) or (GetItemInfo and GetItemInfo(id)) or ("Item " .. id)
  local q = (it and it.q) or (si and si[2])
  local col = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] and ITEM_QUALITY_COLORS[q].hex
  return n, col
end
local function refreshWindow()
  if not win or not win:IsShown() then return end
  local list = others()
  local me = ns.char()
  if me then table.insert(list, 1, { key = "you", c = me }) end
  for i, b in ipairs(win.charButtons) do
    local o = list[i]
    if o then
      b.text:SetText(classIcon(o.c.class) .. cname(o.c, o.key) .. (o.c.level and ("  |cffffd100" .. o.c.level .. "|r") or "") .. (o.c == me and "  |cff9d9d9d(you)|r" or ""))
      b.o = o; b:Show()
    else b:Hide() end
  end
  if not sel or not sel.c then sel = list[1] end
  if not sel then win.info:SetText("No characters recorded yet."); return end
  local c = sel.c
  local lines = {
    classIcon(c.class, 16) .. cname(c, sel.key) .. "   |cffffd100level " .. (c.level or "?") .. "|r " .. cap(c.class) .. (sel.remote and c.account and c.account ~= "" and ("   |cff9d9d9d(" .. c.account .. ")|r") or ""),
    (ns.coins and ns.coins(c.money or 0) or ns.fmtMoney(c.money or 0)) .. (c.rested and c.rested > 0 and ("   |cff4d8ff0rested " .. ns.fmtNum(c.rested) .. "|r") or ""),
    (c.zone and c.zone ~= "" and (c.zone .. (c.subzone and c.subzone ~= "" and (", " .. c.subzone) or "")) or "Zone unknown") .. "   last played " .. ago(c.stateAt),
    "Bags updated " .. ago(c.bagsAt) .. "   bank updated " .. (c.bankAt and ago(c.bankAt) or "never (open the bank once)"),
  }
  win.info:SetText(table.concat(lines, "\n"))
  -- items in bags and bank, filtered by the search box
  local items = {}
  local q = query:lower()
  local seen = {}
  for _, src in ipairs({ c.bags or {}, c.bank or {} }) do for id in pairs(src) do seen[id] = true end end
  for id in pairs(seen) do
    local n, col = itemName(id)
    if q == "" or n:lower():find(q, 1, true) then
      local bg, bk = held(c, id)
      items[#items + 1] = { id = id, n = n, col = col, bg = bg, bk = bk }
    end
  end
  table.sort(items, function(a, b) return a.n < b.n end)
  local pages = math.max(1, math.ceil(#items / PER_PAGE))
  if page > pages then page = pages end
  for i, fs in ipairs(win.rows) do
    local it = items[(page - 1) * PER_PAGE + i]
    if it then
      local where = {}
      if it.bg > 0 then where[#where + 1] = "bags " .. it.bg end
      if it.bk > 0 then where[#where + 1] = "bank " .. it.bk end
      fs:SetText(itemIcon(it.id) .. (it.col and ("|c" .. it.col) or "") .. it.n .. (it.col and "|r" or "") .. "   |cffffd100x" .. (it.bg + it.bk) .. "|r  |cff9d9d9d(" .. table.concat(where, ", ") .. ")|r")
    else fs:SetText("") end
  end
  local sh = shared()
  win.note:SetText(sh and ("Includes your other devices and accounts, as of " .. ago(sh.generated) .. ".") or "Characters on this WoW account. Set up the Leveling Ledger app to see your other devices and accounts here.")
  win.pageText:SetText(#items == 0 and (q == "" and "No items recorded" or "Nothing matches") or ("Page " .. page .. " of " .. pages .. "  (" .. #items .. " items)"))
end
local function makeWindow()
  -- the game's own window frame (title bar, close button) where the client has it; a bordered frame otherwise
  local ok, w = pcall(CreateFrame, "Frame", "LevelingLedgerAlts", UIParent, "BasicFrameTemplateWithInset")
  local templ = ok and w and rawget(w, "TitleText") ~= nil
  if not templ then w = CreateFrame("Frame", "LevelingLedgerAlts", UIParent, ns.BACKDROP_TEMPLATE); ns.styleFrame(w, 0.95) end
  w:SetSize(560, 440)
  w:SetPoint("CENTER")
  w:SetFrameStrata("DIALOG")
  w:SetClampedToScreen(true)
  w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
  if templ then rawget(w, "TitleText"):SetText("Leveling Ledger: your characters")
  else
    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 12, -10); title:SetText("Leveling Ledger: your characters")
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  end
  w.note = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); w.note:SetPoint("BOTTOMLEFT", 12, 10)
  w.charButtons = {}
  for i = 1, 14 do
    local b = CreateFrame("Button", nil, w)
    b:SetSize(150, 22); b:SetPoint("TOPLEFT", 10, -32 - (i - 1) * 24)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); if hl.SetColorTexture then hl:SetColorTexture(1, 1, 1, 0.1) end
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 6, 0); b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self) sel = self.o; page = 1; ns.safe(refreshWindow) end)
    w.charButtons[i] = b
  end
  w.info = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); w.info:SetPoint("TOPLEFT", 172, -32); w.info:SetWidth(375); w.info:SetJustifyH("LEFT")
  local search = CreateFrame("EditBox", "LevelingLedgerAltsSearch", w, "InputBoxTemplate")
  search:SetSize(200, 20); search:SetPoint("TOPLEFT", 178, -104); search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function(self) query = self:GetText() or ""; page = 1; ns.safe(refreshWindow) end)
  search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("LEFT", search, "RIGHT", 8, 0); hint:SetText("Search items")
  w.rows = {}
  for i = 1, PER_PAGE do
    local fs = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 172, -132 - (i - 1) * 15); fs:SetWidth(375); fs:SetJustifyH("LEFT")
    w.rows[i] = fs
  end
  local prev = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); prev:SetSize(60, 20); prev:SetPoint("BOTTOMRIGHT", -80, 28); prev:SetText("Prev")
  local nxt = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); nxt:SetSize(60, 20); nxt:SetPoint("BOTTOMRIGHT", -12, 28); nxt:SetText("Next")
  prev:SetScript("OnClick", function() if page > 1 then page = page - 1; ns.safe(refreshWindow) end end)
  nxt:SetScript("OnClick", function() page = page + 1; ns.safe(refreshWindow) end)
  w.pageText = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); w.pageText:SetPoint("BOTTOMLEFT", 172, 32)
  if UISpecialFrames then table.insert(UISpecialFrames, "LevelingLedgerAlts") end -- Escape closes it
  w:SetScript("OnShow", function() ns.safe(refreshWindow) end)
  w:Hide()
  return w
end
ns.toggleAlts = function()
  if not ns.db or not ns.db() then print(TAG .. ": not ready yet."); return end
  win = win or makeWindow()
  if win:IsShown() then win:Hide() else sel = nil; page = 1; win:Show() end
end

-- ---------- profession window: what your alts' materials would let you make ----------
local function craftLine(numReagents, reagentInfo, reagentLink, index)
  local n = numReagents(index) or 0
  if n == 0 then return nil end
  local now, withAlts, short = math.huge, math.huge, {}
  for r = 1, n do
    local name, _, need, have = reagentInfo(index, r)
    need, have = need or 1, have or 0
    local id = ns.idFromLink(reagentLink(index, r))
    local alt, who = 0, {}
    if id then alt, who = altTotal(id) end
    now = math.min(now, math.floor(have / need))
    withAlts = math.min(withAlts, math.floor((have + alt) / need))
    if have < need and alt > 0 then short[#short + 1] = (name or "?") .. ": " .. table.concat(who, ", ") end
  end
  if withAlts <= now then return nil end
  return "|cffffd100With your alts' materials you could make " .. withAlts .. "|r" .. (now > 0 and (" (" .. now .. " now)") or "") .. ".\n" .. table.concat(short, "\n")
end
local helpers = {}
local function attach(parent, key)
  if helpers[key] or not parent then return helpers[key] end
  local fr = CreateFrame("Frame", nil, parent, ns.BACKDROP_TEMPLATE)
  fr:SetSize(240, 60)
  fr:SetPoint("TOPLEFT", parent, "TOPRIGHT", -30, -80)
  ns.styleFrame(fr, 0.9)
  fr.text = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fr.text:SetPoint("TOPLEFT", 8, -8); fr.text:SetWidth(224); fr.text:SetJustifyH("LEFT")
  fr:Hide()
  helpers[key] = fr
  return fr
end
local function show(key, parent, text)
  local fr = attach(parent, key)
  if not fr then return end
  if text then fr.text:SetText(text); fr:SetHeight((fr.text.GetStringHeight and fr.text:GetStringHeight() or 40) + 16); fr:Show() else fr:Hide() end
end
local function onTradeSelect(i)
  if not GetTradeSkillNumReagents then return end
  show("trade", TradeSkillFrame, i and craftLine(GetTradeSkillNumReagents, GetTradeSkillReagentInfo, GetTradeSkillReagentItemLink, i))
end
local function onCraftSelect(i)
  if not GetCraftNumReagents then return end
  show("craft", CraftFrame, i and craftLine(GetCraftNumReagents, GetCraftReagentInfo, GetCraftReagentItemLink, i))
end
local hooked = {}
local function hookProfessions()
  if not hooked.trade and TradeSkillFrame_SetSelection then hooked.trade = true; hooksecurefunc("TradeSkillFrame_SetSelection", function(i) ns.safe(onTradeSelect, i) end) end
  if not hooked.craft and CraftFrame_SetSelection then hooked.craft = true; hooksecurefunc("CraftFrame_SetSelection", function(i) ns.safe(onCraftSelect, i) end) end
end

-- ---------- start ----------
local ev = CreateFrame("Frame")
if ns.listen then ns.listen(ev, "PLAYER_LOGIN") else pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN") end
if ns.listen then ns.listen(ev, "ADDON_LOADED") else pcall(ev.RegisterEvent, ev, "ADDON_LOADED") end -- the profession windows load on demand
if ns.listen then ns.listen(ev, "BAG_UPDATE_DELAYED") else pcall(ev.RegisterEvent, ev, "BAG_UPDATE_DELAYED") end
ev:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGIN" then ns.safe(hookTooltips); ns.safe(hookProfessions)
  elseif event == "ADDON_LOADED" and (name == "Blizzard_TradeSkillUI" or name == "Blizzard_CraftUI") then ns.safe(hookProfessions)
  elseif event == "BAG_UPDATE_DELAYED" then ns.safe(refreshWindow) end
end)
