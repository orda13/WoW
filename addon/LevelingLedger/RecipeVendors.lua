-- Recipes you need to buy (worked out by the Leveling Ledger page; LevelingLedgerShared.recipes, written by the app
-- into Shared.lua): highlighted where you can buy them.
--   * at a vendor: a chat line naming them, and a gold frame on those items in the merchant window
--   * on a vendor's tooltip: "Sells recipes you need: ..."
--   * with Questie: the vendors pinned on the map (Questie's internals, guarded like QuestiePlan.lua)
--   /ledger recipes    lists them
local ADDON, ns = ...
local TAG = "|cffd9aa5aLeveling Ledger|r: "
local ICON = "Interface\\AddOns\\Questie\\Icons\\available.blp"

local function needs()
  local all = rawget(_G, "LevelingLedgerShared") and LevelingLedgerShared.recipes
  local me = (UnitName("player") or ""):lower()
  local r = type(all) == "table" and all[me]
  return type(r) == "table" and type(r.items) == "table" and r or { items = {}, npcs = {} }
end
local function idFromLink(link) return link and tonumber(link:match("item:(%d+)")) end
local function npcOf(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  return (kind == "Creature") and tonumber(id) or nil
end
local function namesFor(npc)
  local r = needs(); local ids = r.npcs and r.npcs[npc]; if type(ids) ~= "table" then return nil end
  local out = {}
  for _, id in ipairs(ids) do if r.items[id] then out[#out + 1] = r.items[id] end end
  return #out > 0 and out or nil
end

-- ---------- at the vendor ----------
local glows = {}
local function glowFor(btn)
  if glows[btn] then return glows[btn] end
  local g = CreateFrame("Frame", nil, btn, ns.BACKDROP_TEMPLATE)
  g:SetPoint("TOPLEFT", -3, 3); g:SetPoint("BOTTOMRIGHT", 3, -3)
  if g.SetBackdrop then g:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 }); g:SetBackdropBorderColor(1, 0.82, 0, 1) end
  g:Hide(); glows[btn] = g
  return g
end
local function markMerchant()
  local r = needs(); if not next(r.items) then return end
  local per = MERCHANT_ITEMS_PER_PAGE or 10
  local page = (MerchantFrame and MerchantFrame.page) or 1
  for i = 1, per do
    local btn = rawget(_G, "MerchantItem" .. i .. "ItemButton")
    if btn then
      local id = idFromLink(GetMerchantItemLink and GetMerchantItemLink((page - 1) * per + i))
      local g = glowFor(btn)
      if id and r.items[id] then g:Show() else g:Hide() end
    end
  end
end
local function announce()
  local r = needs(); if not next(r.items) or not GetMerchantNumItems then return end
  local here = {}
  for i = 1, GetMerchantNumItems() do
    local id = idFromLink(GetMerchantItemLink and GetMerchantItemLink(i))
    if id and r.items[id] then here[#here + 1] = r.items[id] end
  end
  if #here > 0 then print(TAG .. "|cffffd100this vendor sells recipes you need:|r " .. table.concat(here, ", ")) end
end

-- ---------- tooltip on the vendor ----------
local function addTooltip(tt, guid)
  local names = namesFor(npcOf(guid)); if not names then return end
  tt:AddLine("Sells recipes you need: " .. table.concat(names, ", "), 1, 0.82, 0, true)
  tt:Show()
end
local function hookTooltip()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
      if tt ~= GameTooltip then return end
      ns.safe(function() local g = data and data.guid; if type(g) ~= "string" then g = UnitGUID("mouseover") end; addTooltip(tt, g) end)
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) ns.safe(function() addTooltip(tt, UnitGUID("mouseover")) end) end)
  end
end

-- ---------- Questie: pin the vendors ----------
local function questie(name)
  local L = rawget(_G, "QuestieLoader")
  if type(L) ~= "table" or type(L.ImportModule) ~= "function" then return nil end
  local ok, m = pcall(L.ImportModule, L, name)
  return ok and type(m) == "table" and m or nil
end
local pinned = 0
local function pinVendors()
  local Map = questie("QuestieMap"); if not (Map and type(Map.ShowNPC) == "function") then return end
  for npc in pairs(needs().npcs or {}) do
    local names = namesFor(npc)
    if names and pcall(Map.ShowNPC, Map, npc, ICON, 1.0, "Recipe vendor: " .. table.concat(names, ", "), { { "Leveling Ledger", "sells recipes you need" } }, true) then pinned = pinned + 1 end
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
local hooked = false
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    ns.safe(hookTooltip)
    local api = rawget(_G, "Questie") and Questie.API
    if api and type(api.RegisterOnReady) == "function" then pcall(api.RegisterOnReady, function() ns.safe(pinVendors) end) end
  elseif event == "MERCHANT_SHOW" then
    ns.safe(announce); ns.safe(markMerchant)
    -- the merchant window pages: mark again whenever it redraws
    if not hooked and type(rawget(_G, "MerchantFrame_UpdateMerchantInfo")) == "function" then hooked = true; hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function() ns.safe(markMerchant) end) end
  else ns.safe(markMerchant) end
end)

function ns.recipesCommand()
  local r, n = needs(), 0
  for id, name in pairs(r.items) do
    local where = {}
    for npc, ids in pairs(r.npcs or {}) do for _, x in ipairs(ids) do if x == id then where[#where + 1] = npc end end end
    n = n + 1
    print(TAG .. name .. (#where > 0 and (" (" .. #where .. " vendor" .. (#where == 1 and "" or "s") .. (pinned > 0 and ", pinned on the map" or "") .. ")") or ""))
  end
  if n == 0 then print(TAG .. "no recipes to buy for " .. (UnitName("player") or "this character") .. ". The page works them out from your professions; /reload after it updates.") end
end
