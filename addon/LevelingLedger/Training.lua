-- What to train: the class spells you can learn now (with their cost and the total) and the ones coming in the next
-- levels, for every class. A window of the add-on's own, opened from a "Training" button beside the spellbook or with
-- /ledger train. Hover a row for the spell's tooltip; right-click to ignore a spell (/ledger train reset brings them back).
-- Spells: ClassSpellsData.lua (generated from Forever's game tables). Known: the game (IsSpellKnown / IsPlayerSpell; a
-- higher rank known counts for the lower ones). Talent spells only once you know a rank. Costs: what the add-on read at
-- a trainer of your class (this character's visits, or another character of the same class), so open your trainer once.
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local SOON = 4      -- how many coming levels (that bring spells) to show
local ROWS = 22

local function myClass() local _, c = UnitClass("player"); return c end
local function db() return ns.db and ns.db() end
local function ignored() local d = db(); if not d then return {} end; d.trainIgnore = d.trainIgnore or {}; return d.trainIgnore end
local function spellKnown(id)
  if IsPlayerSpell then local ok, v = pcall(IsPlayerSpell, id); if ok and v then return true end end
  if IsSpellKnown then local ok, v = pcall(IsSpellKnown, id); if ok and v then return true end end
  if C_SpellBook and C_SpellBook.IsSpellKnown then local ok, v = pcall(C_SpellBook.IsSpellKnown, id); if ok and v then return true end end
  return false
end
local function icon(id)
  local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
  return tex and ("|T" .. tex .. ":16:16|t ") or ""
end
-- trainer prices by spell name and level: this character first, then others of the same class
local function prices()
  local out, d, me = {}, db(), ns.char and ns.char()
  local cls = myClass()
  local function take(c)
    for _, t in pairs(c and c.trainer or {}) do
      if t.cost and t.n and t.lv and not t.sk and not t.line then local k = t.n .. "|" .. t.lv; if out[k] == nil then out[k] = t.cost end end
    end
  end
  take(me)
  for _, c in pairs(d and d.chars or {}) do if c ~= me and c.class and tostring(c.class):upper() == cls then take(c) end end
  return out
end

-- the lists: { now = { spells... }, soon = { spells... }, total, unpriced }
local function lists()
  local spells = ns.classSpells and ns.classSpells[myClass()] or {}
  local lv = UnitLevel and UnitLevel("player") or 1
  local ign, cost = ignored(), prices()
  -- the highest rank known of each spell (a higher rank known means the lower ones are too)
  local best = {}
  for _, s in ipairs(spells) do if (best[s[2]] or -1) < s[3] and spellKnown(s[1]) then best[s[2]] = s[3] end end
  local now, soon, levels, seenLv = {}, {}, {}, {}
  local total, unpriced = 0, 0
  for _, s in ipairs(spells) do
    local id, name, rank, slv, talent = s[1], s[2], s[3], s[4], s[5]
    local known = best[name] ~= nil and best[name] >= rank
    if not known and not ign[id] and (not talent or best[name] ~= nil) then
      local row = { id = id, n = name, r = rank, lv = slv, cost = cost[name .. "|" .. slv] }
      if slv <= lv then
        now[#now + 1] = row
        if row.cost then total = total + row.cost else unpriced = unpriced + 1 end
      elseif slv <= 60 then
        if not seenLv[slv] then seenLv[slv] = true; levels[#levels + 1] = slv end
        soon[#soon + 1] = row
      end
    end
  end
  table.sort(levels)
  local cut = levels[SOON] or 61
  local soonShown = {}
  for _, r in ipairs(soon) do if r.lv <= cut then soonShown[#soonShown + 1] = r end end
  return { now = now, soon = soonShown, total = total, unpriced = unpriced, lv = lv }
end

-- ---------- the window ----------
local win, rows, offset, data = nil, {}, 0, nil
local function fill()
  if not win or not data then return end
  -- one list: a header, the spells available now, a header, the ones coming soon
  local items = {}
  items[#items + 1] = { head = "|cff40ff40Available now|r  " .. #data.now }
  for _, r in ipairs(data.now) do items[#items + 1] = r end
  if #data.now == 0 then items[#items + 1] = { note = "Nothing to train right now." } end
  items[#items + 1] = { head = "|cff6fb4ffComing soon|r  " .. #data.soon }
  for _, r in ipairs(data.soon) do items[#items + 1] = r end
  offset = math.max(0, math.min(offset, #items - ROWS))
  for i = 1, ROWS do
    local b, it = rows[i], items[i + offset]
    b.item = it
    if not it then b.left:SetText(""); b.right:SetText(""); b:Hide()
    else
      b:Show()
      if it.head then b.left:SetText(it.head); b.right:SetText("")
      elseif it.note then b.left:SetText("|cff9d9d9d" .. it.note .. "|r"); b.right:SetText("")
      else
        b.left:SetText(icon(it.id) .. it.n .. (it.r > 0 and ("  |cff9d9d9dRank " .. it.r .. "|r") or ""))
        if it.lv > data.lv then b.right:SetText("|cffd9c9a8Level " .. it.lv .. "|r")
        else b.right:SetText(it.cost and (ns.coins and ns.coins(it.cost) or (it.cost .. "c")) or "|cff9d9d9dvisit a trainer|r") end
      end
    end
  end
  local tot = ns.coins and ns.coins(data.total) or (data.total .. "c")
  win.total:SetText("Available total: " .. tot .. (data.unpriced > 0 and ("  |cff9d9d9d(+" .. data.unpriced .. " without a price yet)|r") or ""))
end
local function build()
  if win then return end
  win = CreateFrame("Frame", "LevelingLedgerTraining", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(340, 80 + ROWS * 18)
  if win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    win:SetBackdropColor(0.07, 0.06, 0.04, 0.95)
  end
  win:SetFrameStrata("HIGH"); win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -10); title:SetText("What's training?")
  win.total = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.total:SetPoint("TOPLEFT", 12, -32)
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2); close:SetScript("OnClick", function() win:Hide() end)
  for i = 1, ROWS do
    local b = CreateFrame("Button", nil, win)
    b:SetSize(316, 18); b:SetPoint("TOPLEFT", 12, -50 - (i - 1) * 18)
    b.left = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.left:SetPoint("LEFT", 0, 0)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.right:SetPoint("RIGHT", 0, 0)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnEnter", function(self)
      local it = self.item; if not (it and it.id) or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetSpellByID, GameTooltip, it.id)
      GameTooltip:AddLine(it.lv > data.lv and ("Trainable at level " .. it.lv) or "Right-click to ignore", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self, button)
      local it = self.item
      if button == "RightButton" and it and it.id then ignored()[it.id] = true; print(TAG .. it.n .. (it.r > 0 and (" rank " .. it.r) or "") .. " ignored. /ledger train reset brings ignored spells back."); data = lists(); fill() end
    end)
    rows[i] = b
  end
  win:EnableMouseWheel(true)
  win:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; fill() end)
  local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 12, 10); hint:SetText("Hover for details; right-click to ignore; scroll for more")
  win:Hide()
end
local function refresh() if win and win:IsShown() then data = lists(); fill() end end
local function toggle()
  build()
  if win:IsShown() then win:Hide() return end
  offset = 0; data = lists(); fill(); win:Show()
end
ns.toggleTraining = toggle

-- a "Training" button beside the spellbook (whichever spellbook this client has), only while it's open
local tbtn
local function placeButton()
  local book = rawget(_G, "PlayerSpellsFrame") or rawget(_G, "SpellBookFrame")
  if not book then return end
  if not tbtn then
    tbtn = CreateFrame("Button", "LevelingLedgerTrainingButton", UIParent, "UIPanelButtonTemplate")
    tbtn:SetSize(84, 22); tbtn:SetText("Training"); tbtn:SetFrameStrata("HIGH")
    tbtn:SetScript("OnClick", toggle)
  end
  tbtn:ClearAllPoints(); tbtn:SetPoint("TOPLEFT", book, "TOPRIGHT", -2, -40)
  if book:IsShown() then tbtn:Show() else tbtn:Hide() end
end
local hookedBook = false
local function hookBook()
  if hookedBook then return end
  local book = rawget(_G, "PlayerSpellsFrame") or rawget(_G, "SpellBookFrame")
  if not (book and book.HookScript) then return end
  hookedBook = true
  book:HookScript("OnShow", function() if ns.safe then ns.safe(placeButton) else pcall(placeButton) end end)
  book:HookScript("OnHide", function() if tbtn then tbtn:Hide() end end)
end

function ns.trainCommand(arg)
  arg = (arg or ""):match("^%s*(.-)%s*$")
  if arg == "reset" then local d = db(); if d then d.trainIgnore = {} end; print(TAG .. "Ignored spells are back on the training list."); refresh() return end
  if arg == "list" then
    local l = lists()
    print(TAG .. #l.now .. " to train now" .. (l.total > 0 and (", " .. (ns.coins and ns.coins(l.total) or l.total)) or "") .. (l.unpriced > 0 and (" (+" .. l.unpriced .. " without a price yet)") or "") .. ":")
    for i, r in ipairs(l.now) do if i > 12 then print("  ...and " .. (#l.now - 12) .. " more") break end; print("  " .. r.n .. (r.r > 0 and (" rank " .. r.r) or "")) end
    return
  end
  toggle()
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED", "TRAINER_UPDATE", "TRAINER_CLOSED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then if ns.safe then ns.safe(hookBook) else pcall(hookBook) end end
  if event ~= "ADDON_LOADED" then if ns.safe then ns.safe(refresh) else pcall(refresh) end end
end)
