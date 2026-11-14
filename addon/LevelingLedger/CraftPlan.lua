-- The profession guide in game: when you open a profession window, the next crafting steps the Leveling Ledger page
-- worked out for this character (Shared.lua crafts, from shared/craftplan), with what you still have to buy, and a
-- button that finds the recipe in the window. Steps you've already passed (your skill is past them) are skipped.
-- The window is the add-on's own frame, next to the profession window; Blizzard's frames are only read, never changed.
--   /ledger craft   the next steps for each of your professions
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "

local function plans() local sh = rawget(_G, "LevelingLedgerShared"); return type(sh) == "table" and type(sh.crafts) == "table" and ns.forMe and ns.forMe(sh.crafts) or nil end
-- the open profession and your skill in it, on whichever profession window this client has
local function openProfession()
  if GetTradeSkillLine then
    local ok, name, rank, max = pcall(GetTradeSkillLine)
    if ok and type(name) == "string" and name ~= "" and name ~= "UNKNOWN" then return name, tonumber(rank), tonumber(max), "trade" end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if ok and type(info) == "table" and info.professionName then return info.professionName, tonumber(info.skillLevel), tonumber(info.maxSkillLevel), "modern" end
  end
  if GetCraftDisplaySkillLine then
    local ok, name, rank, max = pcall(GetCraftDisplaySkillLine)
    if ok and type(name) == "string" and name ~= "" then return name, tonumber(rank), tonumber(max), "craft" end
  end
end
local function stepsFor(prof, skill)
  local p = plans(); local list = p and p[prof]
  if type(list) ~= "table" then return {} end
  local out = {}
  for _, st in ipairs(list) do if type(st) == "table" and (not skill or (st.to or 0) > skill) then out[#out + 1] = st end end
  return out
end
local function shortText(st)
  local parts = {}
  for _, m in ipairs(st.short or {}) do if type(m) == "table" and m[1] then parts[#parts + 1] = (m[2] or 0) .. " " .. m[1] end end
  return #parts > 0 and ("to get: " .. table.concat(parts, ", ")) or "you have the materials"
end

-- find a recipe in the open window and select it
local function findRecipe(name, kind)
  if not name then return false end
  if kind == "trade" and GetNumTradeSkills and GetTradeSkillInfo and TradeSkillFrame_SetSelection then
    for i = 1, GetNumTradeSkills() do
      local n, t = GetTradeSkillInfo(i)
      if n == name and t ~= "header" then TradeSkillFrame_SetSelection(i); if TradeSkillFrame_Update then pcall(TradeSkillFrame_Update) end return true end
    end
  elseif kind == "craft" and GetNumCrafts and GetCraftInfo and CraftFrame_SetSelection then
    for i = 1, GetNumCrafts() do
      local n = GetCraftInfo(i)
      if n == name then CraftFrame_SetSelection(i); if CraftFrame_Update then pcall(CraftFrame_Update) end return true end
    end
  elseif kind == "modern" and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.OpenRecipe then
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
      local r = C_TradeSkillUI.GetRecipeInfo(id)
      if r and r.name == name then C_TradeSkillUI.OpenRecipe(id) return true end
    end
  end
  return false
end

-- ---------- the window ----------
local win, lines, btn
local function build()
  if win then return end
  win = CreateFrame("Frame", "LevelingLedgerCraftPlan", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(300, 150)
  if win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    win:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
  end
  win:SetFrameStrata("HIGH")
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8); title:SetText("Leveling Ledger: next crafts")
  lines = {}
  for i = 1, 4 do
    local fs = win:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 10, -10 - i * 22); fs:SetWidth(280); fs:SetJustifyH("LEFT")
    lines[i] = fs
  end
  btn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  btn:SetSize(110, 20); btn:SetPoint("BOTTOMRIGHT", -8, 8); btn:SetText("Find it")
  win:Hide()
end
local cur = {}
local function render()
  local prof, skill, max, kind = openProfession()
  if not prof then if win then win:Hide() end return end
  local steps = stepsFor(prof, skill)
  if #steps == 0 then if win then win:Hide() end return end
  build()
  local anchor = (kind == "trade" and rawget(_G, "TradeSkillFrame")) or (kind == "craft" and rawget(_G, "CraftFrame")) or rawget(_G, "ProfessionsFrame")
  win:ClearAllPoints()
  if anchor and anchor.IsShown and anchor:IsShown() then win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -30, -14) else win:SetPoint("CENTER", UIParent, "CENTER", 300, 0) end
  local first = steps[1]
  lines[1]:SetText(string.format("|cff40ff40Now|r %d× %s |cff9d9d9d(%d–%d)|r", first.crafts or 0, first.n or "?", first.from or 0, first.to or 0))
  lines[2]:SetText("|cffd9c9a8" .. shortText(first) .. "|r")
  for i = 2, 3 do
    local st = steps[i]
    lines[i + 1]:SetText(st and string.format("|cff9d9d9dThen|r %d× %s |cff9d9d9d(%d–%d)|r", st.crafts or 0, st.n or "?", st.from or 0, st.to or 0) or "")
  end
  cur = { name = first.n, kind = kind }
  btn:SetScript("OnClick", function() if not findRecipe(cur.name, cur.kind) then print(TAG .. (cur.name or "That recipe") .. " isn't in this window: learn it first (the page's guide says where).") end end)
  win:Show()
end
ns.refreshCraftPlan = render

function ns.craftCommand()
  local p = plans()
  if type(p) ~= "table" or not next(p) then print(TAG .. "No crafting plan yet: open the Profession guide on the Leveling Ledger page, then /reload.") return end
  local skills = (ns.char and ns.char() or {}).skills or {}
  for prof, _ in pairs(p) do
    local s = skills[prof] and skills[prof].rank
    local steps = stepsFor(prof, s)
    if #steps > 0 then
      print(TAG .. prof .. (s and (" (" .. s .. ")") or "") .. ":")
      for i, st in ipairs(steps) do
        if i > 3 then break end
        print(string.format("  %d× %s (%d–%d): %s", st.crafts or 0, st.n or "?", st.from or 0, st.to or 0, shortText(st)))
      end
    end
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "TRADE_SKILL_CLOSE", "CRAFT_CLOSE", "SKILL_LINES_CHANGED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event)
  if event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then if win then win:Hide() end return end
  if ns.safe then ns.safe(render) else pcall(render) end
end)
