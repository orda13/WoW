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

local f = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do
  if ns.listen then ns.listen(f, e) else pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event, a1)
  local safe = ns.safe or pcall
  if event == "AUCTION_ITEM_LIST_UPDATE" then safe(classicList)
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then safe(browse)
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then safe(commodity, a1)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then safe(items, a1) end
end)
