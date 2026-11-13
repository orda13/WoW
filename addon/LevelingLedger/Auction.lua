-- Auction prices: whatever you browse or search at the auction house, the lowest buyout per item (per single item),
-- kept for the whole account in LevelingLedgerDB.ah = { [itemID] = { p = copper each, n = how many listed, at = time } }.
-- The app shows them on material and recipe cards. Both the classic auction API and the newer C_AuctionHouse are
-- read, whichever this client has; every call is guarded, and events the client doesn't have are skipped.
local ADDON, ns = ...
local MAX = 6000

local function now() return time() end
local seen = {}   -- this scan: itemID -> { p, n } (lowest price, total listed)
local function note(id, each, n)
  id, each, n = tonumber(id), tonumber(each), tonumber(n) or 1
  if not id or not each or each <= 0 then return end
  local s = seen[id]
  if not s then seen[id] = { p = each, n = n } else s.n = s.n + n; if each < s.p then s.p = each end end
end
-- ---------- the price line on reagent tooltips ----------
-- the newest price for an item: this account's own scans (LevelingLedgerDB.ah) or every device's, from the app
-- (Shared.lua ah = { [id] = { copper each, listed, seen at } })
function ns.ahPrice(id)
  id = tonumber(id); if not id then return nil end
  local db = ns.db and ns.db()
  local mine = db and db.ah and db.ah[id]
  local sh = rawget(_G, "LevelingLedgerShared"); sh = type(sh) == "table" and type(sh.ah) == "table" and sh.ah[id] or nil
  local best = mine and { p = mine.p, n = mine.n, at = mine.at } or nil
  if type(sh) == "table" and tonumber(sh[1]) and (not best or (tonumber(sh[3]) or 0) > (best.at or 0)) then best = { p = tonumber(sh[1]), n = tonumber(sh[2]), at = tonumber(sh[3]) } end
  return best
end
local function isReagent(id)
  local info = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(id) }
  if info[17] then return true end              -- the game's own "Crafting Reagent" flag
  if info[12] == 7 then return true end          -- Trade Goods
  return C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(id)) == 7 or false
end
local function ago(t)
  if not t or t <= 0 then return "" end
  local d = (now() - t) / 86400
  if d < 1 / 24 then return "just now" elseif d < 1 then return math.floor(d * 24) .. " h ago" elseif d < 2 then return "yesterday" end
  return math.floor(d) .. " days ago"
end
-- adds the line and returns true when there is one
function ns.addPriceLine(tt, id)
  if not tt or not id then return false end
  local ok, reagent = pcall(isReagent, id)
  if not ok or not reagent then return false end
  local pr = ns.ahPrice(id)
  if not pr or not pr.p or pr.p <= 0 then return false end
  local each = ns.coins and ns.coins(pr.p) or (pr.p .. "c")
  local info = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(id) }
  local stack = tonumber(info[8]) or 1
  local right = each .. " each"
  if stack >= 5 then right = right .. ", " .. (ns.coins and ns.coins(pr.p * stack) or (pr.p * stack)) .. " for " .. stack end
  tt:AddLine(" ")
  tt:AddDoubleLine("|cffd9aa5aAuction house|r" .. ((pr.n or 0) > 0 and (" |cff9d9d9d(" .. pr.n .. " listed, " .. ago(pr.at) .. ")|r") or (" |cff9d9d9d(" .. ago(pr.at) .. ")|r")), right, 1, 1, 1, 1, 1, 1)
  return true
end

local function flush()
  local db = ns.db and ns.db(); if not db or not next(seen) then return end
  db.ah = db.ah or {}
  local t, count = now(), 0
  for id, s in pairs(seen) do db.ah[id] = { p = math.floor(s.p), n = s.n, at = t } end
  seen = {}
  -- keep the newest MAX items
  for _ in pairs(db.ah) do count = count + 1 end
  if count > MAX then
    local list = {}
    for id, v in pairs(db.ah) do list[#list + 1] = { id = id, at = v.at or 0 } end
    table.sort(list, function(a, b) return a.at < b.at end)
    for i = 1, count - MAX do db.ah[list[i].id] = nil end
  end
end
local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a, b, c = pcall(fn, ...) if ok then return a, b, c end end

-- classic: the current page of results
local function classicList()
  if not GetNumAuctionItems or not GetAuctionItemInfo then return end
  local n = call(GetNumAuctionItems, "list") or 0
  for i = 1, n do
    local r = { pcall(GetAuctionItemInfo, "list", i) }
    if r[1] then
      local count, buyout, itemID = r[4], r[11], r[18]
      if buyout and buyout > 0 and (count or 0) > 0 then note(itemID, buyout / count, count) end
    end
  end
  flush()
end

-- newer API: browse results carry the lowest price per item
local AH = rawget(_G, "C_AuctionHouse")
local function browse()
  if not AH then return end
  for _, r in ipairs(call(AH.GetBrowseResults) or {}) do
    if r and r.itemKey and r.minPrice then note(r.itemKey.itemID, r.minPrice, r.totalQuantity) end
  end
  flush()
end
local function commodity(itemID)
  if not AH or not itemID then return end
  for i = 1, call(AH.GetNumCommoditySearchResults, itemID) or 0 do
    local r = call(AH.GetCommoditySearchResultInfo, itemID, i)
    if r and r.unitPrice then note(itemID, r.unitPrice, r.quantity) end
  end
  flush()
end
local function items(itemKey)
  if not AH or type(itemKey) ~= "table" then return end
  for i = 1, call(AH.GetNumItemSearchResults, itemKey) or 0 do
    local r = call(AH.GetItemSearchResultInfo, itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 then note(itemKey.itemID, r.buyoutAmount / math.max(1, r.quantity or 1), r.quantity) end
  end
  flush()
end

-- ---------- full scan: the "Scan all prices" button on the auction house window ----------
-- Newer clients: C_AuctionHouse.ReplicateItems (every listing, read by index from 0). Classic: QueryAuctionItems with
-- getAll. The game allows one about every 15 minutes, started by a click. Results are read a chunk at a time.
local COOLDOWN, CHUNK = 15 * 60, 1500
local scanning, btn, status
local function setStatus(t) if status then status:SetText(t or "") end end
local function canScanIn()
  local db = ns.db and ns.db(); local last = db and db.ahScanAt or 0
  return math.max(0, COOLDOWN - (now() - last))
end
-- read n results with get(i) -> itemID, buyout, count, a chunk per frame, then save
local reader = CreateFrame("Frame")
local function readAll(n, first, get)
  local i, last = first, first + n - 1
  setStatus("Reading 0 / " .. n .. "...")
  reader:SetScript("OnUpdate", function(self)
    local stop = math.min(last, i + CHUNK - 1)
    for k = i, stop do
      local id, buyout, count = get(k)
      if id and buyout and buyout > 0 and (count or 0) > 0 then note(id, buyout / count, count) end
    end
    i = stop + 1
    setStatus("Reading " .. (i - first) .. " / " .. n .. "...")
    if i > last then
      self:SetScript("OnUpdate", nil)
      local items = 0; for _ in pairs(seen) do items = items + 1 end
      flush(); scanning = nil
      setStatus("Done: prices for " .. items .. " items. Press Save (or /reload) to send them to the ledger.")
      print("|cffd9aa5aLeveling Ledger|r: auction scan done, prices for " .. items .. " items. Press Save (or /reload) to send them to the ledger.")
    end
  end)
end
local function startScan()
  if scanning then return end
  local wait = canScanIn()
  if wait > 0 then setStatus("The game allows a full scan again in " .. math.ceil(wait / 60) .. " min."); return end
  local db = ns.db and ns.db()
  if AH and type(AH.ReplicateItems) == "function" then
    scanning = "replicate"
  elseif QueryAuctionItems and CanSendAuctionQuery and select(2, call(CanSendAuctionQuery)) then
    scanning = "classic"
  else
    setStatus(QueryAuctionItems and "The auction house isn't ready for a full scan yet; try again in a moment." or "This client has no full-scan request; prices still come from what you browse.")
    return
  end
  if db then db.ahScanAt = now() end
  seen = {}
  setStatus("Asking the auction house for every listing...")
  local ok
  if scanning == "replicate" then ok = pcall(AH.ReplicateItems)
  else ok = pcall(QueryAuctionItems, "", nil, nil, 0, false, nil, true) end
  if not ok then scanning = nil; setStatus("The game didn't accept the scan request."); return end
  -- no results within 90 seconds: give up, so the button works again
  local mode = scanning
  if C_Timer and C_Timer.After then C_Timer.After(90, function()
    if scanning == mode then scanning = nil; setStatus("The auction house didn't send the full list. Prices still come from what you browse.") end
  end) end
end
local function onReplicate()
  if scanning ~= "replicate" then return end
  scanning = "reading"
  local n = call(AH.GetNumReplicateItems) or 0
  readAll(n, 0, function(k)
    local r = { pcall(AH.GetReplicateItemInfo, k) }
    if r[1] then return r[18], r[11], r[4] end -- itemID, buyout, count
  end)
end
local function onClassicAll()
  scanning = "reading"
  local n = call(GetNumAuctionItems, "list") or 0
  readAll(n, 1, function(k)
    local r = { pcall(GetAuctionItemInfo, "list", k) }
    if r[1] then return r[18], r[11], r[4] end
  end)
end
-- The button, on whichever auction window this client has (created once, when it first opens)
local function ahWindow() return rawget(_G, "AuctionHouseFrame") or rawget(_G, "AuctionFrame") end
local function makeButton()
  if btn then return true end
  local parent = ahWindow()
  if not parent then return false end
  btn = CreateFrame("Button", "LevelingLedgerScanButton", parent, "UIPanelButtonTemplate")
  -- just outside the window's top right corner: inside it, the window's own title bar and tabs cover it on some clients
  btn:SetSize(130, 22); btn:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, -28); btn:SetText("Scan all prices")
  if btn.SetFrameStrata then btn:SetFrameStrata("HIGH") end
  if btn.SetFrameLevel and parent.GetFrameLevel then btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 50) end
  if btn.SetClampedToScreen then btn:SetClampedToScreen(true) end
  btn:SetScript("OnClick", function() ns.safe(startScan) end)
  btn:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Leveling Ledger: scan all prices")
    local w = canScanIn()
    GameTooltip:AddLine(w > 0 and ("Next scan allowed in " .. math.ceil(w / 60) .. " min.") or "Reads every listing (allowed about every 15 minutes).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  status = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2); status:SetWidth(220); status:SetJustifyH("LEFT")
  return true
end
-- The game loads the auction window the first time it opens, sometimes after this add-on hears that it opened:
-- try again for a moment, and when the window's own add-on finishes loading.
local told = false
local function tell()
  if told or not btn then return end
  told = true
  print("|cffd9aa5aLeveling Ledger|r: \"Scan all prices\" is just right of the auction window (or type /ledger scan).")
end
local function makeButtonSoon()
  if makeButton() then tell() return end
  if not (C_Timer and C_Timer.After) then return end
  if C_Timer and C_Timer.After then C_Timer.After(3.5, function() pcall(tell) end) end
  for _, d in ipairs({ 0.1, 0.5, 1.5, 3 }) do C_Timer.After(d, function() pcall(makeButton) end) end
end
ns.ahScan = startScan
-- /ledger scan: the same as the button, while the auction house is open
function ns.ahScanCommand()
  local w = ahWindow()
  if not (w and w.IsShown and w:IsShown()) then print("|cffd9aa5aLeveling Ledger|r: open the auction house first, then /ledger scan."); return end
  pcall(makeButton)
  local wait = canScanIn()
  if wait > 0 then print("|cffd9aa5aLeveling Ledger|r: the game allows a full scan again in " .. math.ceil(wait / 60) .. " min. Prices still come from what you browse."); return end
  print("|cffd9aa5aLeveling Ledger|r: scanning every auction listing; this takes a few seconds.")
  ns.safe(startScan)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "AUCTION_HOUSE_SHOW", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event, a1)
  local safe = ns.safe or pcall
  if event == "ADDON_LOADED" then if a1 == "Blizzard_AuctionHouseUI" or a1 == "Blizzard_AuctionUI" then safe(makeButton) end
  elseif event == "AUCTION_HOUSE_SHOW" then safe(makeButtonSoon)
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then safe(onReplicate)
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then if scanning == "classic" then safe(onClassicAll) elseif not scanning then safe(classicList) end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then safe(browse)
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then safe(commodity, a1)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then safe(items, a1) end
end)
