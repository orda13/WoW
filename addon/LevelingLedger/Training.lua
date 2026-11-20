-- What to train, laid out like the What's Training? add-on, for every class: your class spells in groups, each with a
-- count and the total cost, in a window that opens beside the spellbook from a "Training" button on its right edge
-- (the button shows how many you can train now), or with /ledger train.
--   Available now          your level allows it, and you know the rank before it
--   Missing requirements   your level allows it, but you need the rank before it first, or the trainer listed it as
--                          unavailable to you (a quest or other requirement)
--   Coming soon            the next 4 levels that bring spells, with the level each needs
--   Not yet available      later levels (folded)
--   Ignored                spells you right-clicked (folded); right-click again to take one back
--   Already known          (folded)
-- Click a group's heading to fold or unfold it (remembered). Hover a spell for its tooltip; hold Shift to compare it with
-- the rank you know; Shift-click to link it in chat; right-click to ignore it.
-- Spells: ClassSpellsData.lua (generated from Forever's game tables). Known: the game (IsPlayerSpell / IsSpellKnown; a
-- higher rank known counts for the lower ones). Talent spells only once you know a rank. Costs and the trainer's
-- "unavailable" mark: what the add-on read at a trainer of your class (this character, or another of the same class).
-- The window is the add-on's own frame; the spellbook is only read and anchored to, never changed.
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local SOON = 4
local ROWS = 24
local ROW_H = 18

local function myClass() local _, c = UnitClass("player"); return c end
local function db() return ns.db and ns.db() end
local function ignored() local d = db(); if not d then return {} end; d.trainIgnore = d.trainIgnore or {}; return d.trainIgnore end
local function folded()
  local d = db(); if not d then return {} end
  d.trainFolded = d.trainFolded or { later = true, ignored = true, known = true }
  return d.trainFolded
end
local function spellKnown(id)
  if IsPlayerSpell then local ok, v = pcall(IsPlayerSpell, id); if ok and v then return true end end
  if IsSpellKnown then local ok, v = pcall(IsSpellKnown, id); if ok and v then return true end end
  if C_SpellBook and C_SpellBook.IsSpellKnown then local ok, v = pcall(C_SpellBook.IsSpellKnown, id); if ok and v then return true end end
  return false
end
local function icon(id)
  local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
  return tex and ("|T" .. tex .. ":16:16|t ") or "|TInterface\\Icons\\INV_Misc_QuestionMark:16:16|t "
end
local function coins(c) return ns.coins and ns.coins(c) or (tostring(c) .. "c") end
-- what a trainer of your class told the add-on, by spell name and level: price, and whether it was "unavailable"
local function trainerInfo()
  local out, d, me = {}, db(), ns.char and ns.char()
  local cls = myClass()
  local function take(c, mine)
    for _, t in pairs(c and c.trainer or {}) do
      if t.n and t.lv and not t.sk and not t.line then
        local k = t.n .. "|" .. t.lv
        local o = out[k] or {}
        if o.cost == nil and t.cost then o.cost = t.cost end
        if mine and t.state then o.state = t.state end
        out[k] = o
      end
    end
  end
  take(me, true)
  for _, c in pairs(d and d.chars or {}) do if c ~= me and c.class and tostring(c.class):upper() == cls then take(c, false) end end
  return out
end

-- the groups, in order
local GROUPS = {
  { key = "now", title = "Available now", color = "40ff40" },
  { key = "missing", title = "Missing requirements", color = "ff8040" },
  { key = "soon", title = "Coming soon", color = "6fb4ff" },
  { key = "later", title = "Not yet available", color = "9d9d9d" },
  { key = "ignored", title = "Ignored", color = "9d9d9d" },
  { key = "known", title = "Already known", color = "9d9d9d" },
}
local function lists()
  local spells = ns.classSpells and ns.classSpells[myClass()] or {}
  local lv = UnitLevel and UnitLevel("player") or 1
  local ign, info = ignored(), trainerInfo()
  local best, byRank = {}, {}
  for _, s in ipairs(spells) do
    if spellKnown(s[1]) and (best[s[2]] or -1) < s[3] then best[s[2]] = s[3] end
    byRank[s[2] .. "#" .. s[3]] = s[1]
  end
  local g = {}
  for _, gr in ipairs(GROUPS) do g[gr.key] = { rows = {}, total = 0, unpriced = 0 } end
  local soonLevels, seenLv = {}, {}
  for _, s in ipairs(spells) do if not (best[s[2]] and best[s[2]] >= s[3]) and s[4] > lv and s[4] <= 60 and not seenLv[s[4]] and not ign[s[1]] and (not s[5] or best[s[2]]) then seenLv[s[4]] = true; soonLevels[#soonLevels + 1] = s[4] end end
  table.sort(soonLevels)
  local soonCut = soonLevels[SOON] or 61
  for _, s in ipairs(spells) do
    local id, name, rank, slv, talent = s[1], s[2], s[3], s[4], s[5]
    local known = best[name] ~= nil and best[name] >= rank
    if talent and best[name] == nil then -- a talent you haven't taken: not trainable
    else
      local ti = info[name .. "|" .. slv] or {}
      local row = { id = id, n = name, r = rank, lv = slv, cost = ti.cost, prev = rank > 1 and byRank[name .. "#" .. (rank - 1)] or nil }
      local key
      if known then key = "known"
      elseif ign[id] then key = "ignored"
      elseif slv <= lv then
        local needsPrev = rank > 1 and byRank[name .. "#" .. (rank - 1)] and not (best[name] and best[name] >= rank - 1)
        if needsPrev then row.why = "learn rank " .. (rank - 1) .. " first" end
        if ti.state == "unavailable" then row.why = row.why or "the trainer won't teach it yet" end
        key = row.why and "missing" or "now"
      elseif slv <= soonCut then key = "soon"
      elseif slv <= 60 then key = "later" end
      if key then
        local grp = g[key]; grp.rows[#grp.rows + 1] = row
        if row.cost then grp.total = grp.total + row.cost else grp.unpriced = grp.unpriced + 1 end
      end
    end
  end
  table.sort(g.known.rows, function(a, b) return a.lv > b.lv end) -- the newest first
  g.lv = lv
  return g
end

-- ---------- the window ----------
local win, rows, offset, data, items = nil, {}, 0, nil, {}
local function groupHeading(gr, grp)
  local f = folded()[gr.key]
  local total = grp.total > 0 and ("  |cffd9c9a8" .. coins(grp.total) .. "|r") or ""
  return (f and "|cff9d9d9d+|r " or "|cff9d9d9d-|r ") .. "|cff" .. gr.color .. gr.title .. "|r  |cff9d9d9d" .. #grp.rows .. "|r" .. total
end
local function fill()
  if not win or not data then return end
  items = {}
  for _, gr in ipairs(GROUPS) do
    local grp = data[gr.key]
    if #grp.rows > 0 or gr.key == "now" then
      items[#items + 1] = { head = gr, grp = grp }
      if not folded()[gr.key] then
        for _, r in ipairs(grp.rows) do r.group = gr.key; items[#items + 1] = r end
        if gr.key == "now" and #grp.rows == 0 then items[#items + 1] = { note = "Nothing to train right now." } end
      end
    end
  end
  offset = math.max(0, math.min(offset, #items - ROWS))
  for i = 1, ROWS do
    local b, it = rows[i], items[i + offset]
    b.item = it
    if not it then b:Hide()
    else
      b:Show()
      b.name:SetText(""); b.rank:SetText(""); b.right:SetText("")
      if it.head then b.name:SetText(groupHeading(it.head, it.grp)); b.bg:Show()
      elseif it.note then b.name:SetText("|cff9d9d9d" .. it.note .. "|r"); b.bg:Hide()
      else
        b.bg:Hide()
        local dim = it.group == "known" or it.group == "ignored" or it.group == "later"
        b.name:SetText(icon(it.id) .. (dim and ("|cff9d9d9d" .. it.n .. "|r") or it.n))
        b.rank:SetText(it.r > 0 and ("|cffbbbbbbRank " .. it.r .. "|r") or "")
        if it.group == "now" then b.right:SetText(it.cost and coins(it.cost) or "|cff9d9d9d?|r")
        elseif it.group == "missing" then b.right:SetText("|cffff8040" .. (it.why or "") .. "|r")
        elseif it.group == "known" then b.right:SetText("")
        else b.right:SetText("|cffd9c9a8Level " .. it.lv .. "|r") end
      end
    end
  end
  local now = data.now
  win.total:SetText("Available total: " .. coins(now.total) .. (now.unpriced > 0 and ("  |cff9d9d9d(+" .. now.unpriced .. " not priced: visit your trainer)|r") or ""))
end
-- the spell's tooltip; with Shift, the rank you know beside it
local function showTip(self)
  local it = self.item
  if not (it and it.id) or not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  pcall(GameTooltip.SetSpellByID, GameTooltip, it.id)
  if it.lv and data and it.lv > data.lv then GameTooltip:AddLine("Trainable at level " .. it.lv, 1, 0.82, 0) end
  if it.why then GameTooltip:AddLine("Missing: " .. it.why, 1, 0.5, 0.25) end
  if it.cost then GameTooltip:AddLine("Training cost: " .. coins(it.cost), 1, 1, 1) end
  GameTooltip:AddLine(it.group == "ignored" and "Right-click to stop ignoring" or "Shift: compare · Shift-click: link · Right-click: ignore", 0.6, 0.6, 0.6)
  GameTooltip:Show()
  local cmp = rawget(_G, "ShoppingTooltip1")
  if IsShiftKeyDown and IsShiftKeyDown() and it.prev and cmp and cmp.SetSpellByID then
    cmp:SetOwner(GameTooltip, "ANCHOR_NONE"); cmp:ClearAllPoints(); cmp:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 4, 0)
    pcall(cmp.SetSpellByID, cmp, it.prev)
    cmp:AddLine("The rank before it", 0.6, 0.6, 0.6); cmp:Show()
  end
end
local function hideTip() if GameTooltip then GameTooltip:Hide() end local cmp = rawget(_G, "ShoppingTooltip1"); if cmp then cmp:Hide() end end
local function linkSpell(id)
  local link = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)) or (GetSpellLink and GetSpellLink(id))
  if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

local tbtn
local function updateButton()
  if not tbtn then return end
  local n = data and #data.now.rows or 0
  tbtn:SetText(n > 0 and ("Training (" .. n .. ")") or "Training")
end
local function book() return rawget(_G, "PlayerSpellsFrame") or rawget(_G, "SpellBookFrame") end
local function dock()
  if not win then return end
  win:ClearAllPoints()
  local b = book()
  if b and b.IsShown and b:IsShown() then win:SetPoint("TOPLEFT", b, "TOPRIGHT", 4, 0) else win:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end
local function build()
  if win then return end
  win = CreateFrame("Frame", "LevelingLedgerTraining", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(380, 92 + ROWS * ROW_H)
  if win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", tile = true, tileSize = 16, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    win:SetBackdropColor(0.16, 0.12, 0.07, 0.96)
  end
  win:SetFrameStrata("HIGH"); win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14); title:SetText("What's Training?")
  win.total = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.total:SetPoint("TOPRIGHT", -34, -18)
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2); close:SetScript("OnClick", function() win:Hide() end)
  for i = 1, ROWS do
    local b = CreateFrame("Button", nil, win)
    b:SetSize(348, ROW_H); b:SetPoint("TOPLEFT", 16, -44 - (i - 1) * ROW_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.06); b.bg:Hide()
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.name:SetPoint("LEFT", 4, 0); b.name:SetWidth(200); b.name:SetJustifyH("LEFT")
    b.rank = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.rank:SetPoint("LEFT", 208, 0)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.right:SetPoint("RIGHT", -4, 0)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnEnter", showTip)
    b:SetScript("OnLeave", hideTip)
    b:SetScript("OnClick", function(self, button)
      local it = self.item; if not it then return end
      if it.head then local f = folded(); f[it.head.key] = not f[it.head.key] or nil; fill() return end
      if not it.id then return end
      if IsShiftKeyDown and IsShiftKeyDown() and button ~= "RightButton" then linkSpell(it.id) return end
      if button == "RightButton" then
        local ign = ignored()
        if ign[it.id] then ign[it.id] = nil; print(TAG .. it.n .. (it.r > 0 and (" rank " .. it.r) or "") .. " is back on the list.")
        else ign[it.id] = true; print(TAG .. it.n .. (it.r > 0 and (" rank " .. it.r) or "") .. " ignored (in the Ignored group; right-click it there to take it back).") end
        data = lists(); fill(); updateButton()
      end
    end)
    rows[i] = b
  end
  win:EnableMouseWheel(true)
  win:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; fill() end)
  local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 16, 14); hint:SetText("Click a heading to fold it · Hover: details · Shift: compare · Shift-click: link · Right-click: ignore")
  hint:SetWidth(348); hint:SetJustifyH("LEFT")
  win:Hide()
end
local function refresh()
  data = lists(); updateButton()
  if win and win:IsShown() then fill() end
end
local function toggle()
  build()
  if win:IsShown() then win:Hide() return end
  offset = 0; data = lists(); fill(); dock(); win:Show(); updateButton()
end
ns.toggleTraining = toggle

-- the "Training (N)" button on the spellbook's right edge, only while the spellbook is open
local function placeButton()
  local b = book(); if not b then return end
  if not tbtn then
    tbtn = CreateFrame("Button", "LevelingLedgerTrainingButton", UIParent, "UIPanelButtonTemplate")
    tbtn:SetSize(104, 22); tbtn:SetFrameStrata("HIGH")
    tbtn:SetScript("OnClick", toggle)
  end
  tbtn:ClearAllPoints(); tbtn:SetPoint("TOPLEFT", b, "TOPRIGHT", -2, -40)
  data = lists(); updateButton()
  if b:IsShown() then tbtn:Show() else tbtn:Hide() end
end
local hookedBook = false
local function hookBook()
  if hookedBook then return end
  local b = book()
  if not (b and b.HookScript) then return end
  hookedBook = true
  b:HookScript("OnShow", function() if ns.safe then ns.safe(placeButton) else pcall(placeButton) end end)
  b:HookScript("OnHide", function() if tbtn then tbtn:Hide() end if win and win:IsShown() then win:Hide() end end)
end

function ns.trainCommand(arg)
  arg = (arg or ""):match("^%s*(.-)%s*$")
  if arg == "reset" then local d = db(); if d then d.trainIgnore = {} end; print(TAG .. "Ignored spells are back on the training list."); refresh() return end
  if arg == "list" then
    local l = lists()
    print(TAG .. #l.now.rows .. " to train now" .. (l.now.total > 0 and (", " .. coins(l.now.total)) or "") .. (l.now.unpriced > 0 and (" (+" .. l.now.unpriced .. " not priced yet)") or "") .. ":")
    for i, r in ipairs(l.now.rows) do if i > 12 then print("  ...and " .. (#l.now.rows - 12) .. " more") break end; print("  " .. r.n .. (r.r > 0 and (" rank " .. r.r) or "")) end
    if #l.missing.rows > 0 then print(TAG .. #l.missing.rows .. " more your level allows, once you meet their requirement (/ledger train to see them).") end
    return
  end
  toggle()
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED", "TRAINER_UPDATE", "TRAINER_CLOSED", "MODIFIER_STATE_CHANGED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then if ns.safe then ns.safe(hookBook) else pcall(hookBook) end return end
  if event == "MODIFIER_STATE_CHANGED" then
    -- Shift pressed or let go over a spell: redraw its tooltip with or without the comparison
    local owner = GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip.GetOwner and GameTooltip:GetOwner()
    if owner and owner.item and owner.item.id and win and win:IsShown() then hideTip(); showTip(owner) end
    return
  end
  if ns.safe then ns.safe(refresh) else pcall(refresh) end
end)
