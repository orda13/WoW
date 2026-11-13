# Runs the add-on in real Lua with a fake WoW API, then writes SavedVariables the way the game does.
import lupa, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else 'SampleSavedVariables.lua'
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
T = 1794000000
-- events the current client doesn't have (registering one is an error, as in game)
UNKNOWN_EVENTS = { TRADE_SKILL_UPDATE = true, CRAFT_UPDATE = true }
-- events add-ons may not register on this client (the game blocks the add-on)
RESTRICTED_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true }
unpack = table.unpack
state = { level = 13, xp = 8088, xpMax = { [13] = 11400, [14] = 12900 }, money = 5000 }
function time() return T end
function GetTime() return T end
-- frames: the first one is the add-on's event frame; later ones are UI (the panel)
local function obj(extra)
  local o = extra or {}
  return setmetatable(o, { __index = function(_, k) return function() end end })
end
UIParent = obj({})
function CreateFrame(kind, name, parent)
  local fr = { ev = {}, scripts = {}, shown = true, point = nil }
  function fr:RegisterEvent(e) if UNKNOWN_EVENTS[e] then error('Attempt to register unknown event "' .. e .. '"') end if RESTRICTED_EVENTS[e] then error("ADDON_ACTION_FORBIDDEN: RegisterEvent " .. e) end self.ev[e] = true end
  function fr:SetScript(n, fn) self.scripts[n] = fn; if n == "OnEvent" then self.fn = fn end end
  function fr:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
  function fr:Hide() self.shown = false end
  function fr:IsShown() return self.shown end
  function fr:SetPoint(...) self.point = { ... } end
  function fr:SetAttribute(k, v) local a = rawget(self, "attrs") or {}; rawset(self, "attrs", a); a[k] = v end
  function fr:GetPoint() local p = self.point or {} return p[1], p[2], p[3], p[4], p[5] end
  fr.fonts = {}
  function fr:CreateFontString() local fs = obj({ text = "" }) function fs:SetText(t) self.text = t end table.insert(fr.fonts, fs) return fs end
  function fr:CreateTexture() return obj({}) end
  if name then _G[name] = obj(fr) end
  if not FRAME then FRAME = fr end
  FRAMES = FRAMES or {}; table.insert(FRAMES, fr)
  return obj(fr)
end
function UnitName(u) if u == "player" then return "Talwyn" elseif u == "npc" then return NPCNAME else return "Mob" end end
function GetRealmName() return "Normal" end
function UnitClass() return "Druid", "DRUID" end
function UnitRace() return "Night Elf", "NightElf" end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return state.level end
function UnitXP() return state.xp end
function UnitXPMax() return state.xpMax[state.level] end
function GetXPExhaustion() return REST end
REST = 2400
function IsResting() return RESTING or false end
function GetSubZoneText() return SUBZONE or "" end
function GetMoney() return state.money end
function GetRealZoneText() return ZONE or "Darkshore" end
function GetZoneText() return GetRealZoneText() end
function RequestTimePlayed() FRAME.fn(FRAME, "TIME_PLAYED_MSG", 86400, 3600) end
function UnitGUID(u) if u == "npc" then return NPCGUID end return TARGETGUID end
function UnitExists() return true end
function IsInInstance() return INSTANCE or false end
strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = p end return unpack(out) end
C_Map = { GetBestMapForUnit = function() return 1439 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.374, 0.401 end } end }
-- trainer
local TS = { { "Regrowth", "Rank 1", "available", 180, 12 }, { "Thorns", "Rank 2", "available", 200, 14 }, { "Druid", nil, "header", 0, 0 }, { "Thorns", "Rank 3", "unavailable", 1800, 24 }, { "Elixir of Minor Fortitude", nil, "available", 90, 5, "Alchemy", 50 } }
-- the trainer window hides known and too-high abilities until its filters are switched on
FILTER = { available = 1, unavailable = 0, used = 0 }
function GetNumTrainerServices() return FILTER.used == 1 and #TS or 0 end
function GetTrainerServiceTypeFilter(k) return FILTER[k] end
function SetTrainerServiceTypeFilter(k, v) FILTER[k] = v; if FRAME then FRAME.fn(FRAME, "TRAINER_UPDATE") end end
function GetTrainerServiceSkillLine(i) return TS[i][6] end
function GetTrainerServiceSkillReq(i) if TS[i][6] then return TS[i][6], TS[i][7], true end return nil end
-- this client returns name, status, icon (no rank text), and each rank needs its own level
function GetTrainerServiceInfo(i) return TS[i][1], TS[i][3], 136000 + i end
function GetTrainerServiceCost(i) return TS[i][4] end
function GetTrainerServiceLevelReq(i) return TS[i][5] end
-- merchant (Merchant's Favor recipe + a gold item)
function GetMerchantNumItems() return 2 end
function GetMerchantItemInfo(i) if i == 1 then return "Recipe: Elixir of Lesser Spirit", 0, 0, 1, -1, true, true, true else return "Empty Vial", 0, 20, 5, -1, true, true, false end end
function GetMerchantItemLink(i) if i == 1 then return "|cff1eff00|Hitem:271900::::::::13:::::|h[Recipe: Elixir of Lesser Spirit]|h|r" else return "|cffffffff|Hitem:3371::::::::13:::::|h[Empty Vial]|h|r" end end
function GetMerchantItemCostInfo(i) return 1 end
function GetMerchantItemCostItem(i, j) return 0, 120, nil, "Merchant's Favor" end
-- loot
function GetNumLootItems() return 2 end
function GetItemInfoInstant(id) if id == 2318 then return 2318, "Tradeskill", "Leather", "", 0, 7, 6 end return id, "Misc", "Junk", "", 0, 15, 0 end
function GetLootSlotLink(s) if LOOTLINKS then return LOOTLINKS[s] end if s == 1 then return "|cff0070dd|Hitem:273297::::::::13:::::|h[Goblin Hammer]|h|r" end return "|cff9d9d9d|Hitem:2589::::::::13:::::|h[Linen Cloth]|h|r" end
LOOTSRC = "Creature-0-1-36-1-1763-0000AAAA"
function GetLootSourceInfo(s) return LOOTSRC, 1 end
function GetItemInfo(link) return nil end
C_Item = { GetItemQualityByID = function(link) if link:find("Goblin") then return 3 end return 1 end }
-- items the game hasn't loaded yet: their links have an empty name until requested (Wool Cloth here)
LOADED = {}
C_Item.GetItemNameByID = function(id) return LOADED[id] end
C_Item.RequestLoadItemDataByID = function(id) if id == 2592 and not LOADED[id] then LOADED[id] = "Wool Cloth"; FRAME_FIRE("GET_ITEM_INFO_RECEIVED", id, true) end end
SlashCmdList = {}
-- another character already in the saved data (as if played before), with bags and bank
LevelingLedgerDB = { chars = { ["Bob-Normal"] = { name = "Bob", level = 12, class = "MAGE", money = 52000, rested = 1200, zone = "Elwynn Forest",
  stateAt = T - 2 * 86400, bagsAt = T - 2 * 86400, bankAt = T - 5 * 86400,
  bags = { [2447] = 6, [2589] = 3 }, bank = { [2447] = 4, [2589] = 20, [3371] = 2 } } },
  items = { [2447] = { n = "Peacebloom", q = 1 }, [2589] = { n = "Linen Cloth", q = 1 }, [3371] = { n = "Empty Vial", q = 1 } } }
-- your bags and bank (C_Container, as modern clients have it)
CONTAINERS = { [0] = { { 2589, 4, "|cffffffff|Hitem:2589::::::::13:::::|h[Linen Cloth]|h|r" }, { 2447, 1, "|cffffffff|Hitem:2447::::::::13:::::|h[Peacebloom]|h|r" } },
  [1] = { { 3371, 5, "|cffffffff|Hitem:3371::::::::13:::::|h[Empty Vial]|h|r" }, { 2592, 10, "|cffffffff|Hitem:2592::::::::13:::::|h[]|h|r" } },
  [-1] = { { 2450, 7, "|cffffffff|Hitem:2450::::::::13:::::|h[Briarthorn]|h|r" } }, [5] = { { 2447, 3, "|cffffffff|Hitem:2447::::::::13:::::|h[Peacebloom]|h|r" } },
  [6] = { { 2589, 10, "|cffffffff|Hitem:2589::::::::13:::::|h[Linen Cloth]|h|r" } } }
C_Container = { GetContainerNumSlots = function(b) return CONTAINERS[b] and #CONTAINERS[b] or 0 end,
  GetContainerItemInfo = function(b, s) local x = CONTAINERS[b] and CONTAINERS[b][s]; if x then return { itemID = x[1], stackCount = x[2], hyperlink = x[3] } end end }
NUM_BAG_SLOTS, NUM_BANKBAGSLOTS, BANK_CONTAINER = 4, 6, -1
-- the modern engine's bag numbering: the reagent bag is bag 5 (here holding Peacebloom), the bank bags start at 6
Enum = Enum or {}; Enum.BagIndex = { Backpack = 0, Bag_1 = 1, Bag_4 = 4, ReagentBag = 5, BankBag_1 = 6, Bank = -1, Reagentbank = -3 }
-- the bags in the bag slots: a Linen Bag (4245) in bag 1, a reagent bag (4498 here) in the reagent slot and a Small Brown Pouch (4496) in the first bank bag slot
function C_Container.ContainerIDToInventoryID(bag) return 30 + bag end
function GetInventoryItemID(unit, slot) if slot == 31 then return 4245 elseif slot == 35 then return 4498 elseif slot == 36 then return 4496 end end
-- tooltips
local function tooltip(name)
  local tt = { lines = {}, hooks = {} }
  function tt:HookScript(n, fn) self.hooks[n] = fn end
  function tt:GetItem() return self.itemName, self.itemLink end
  function tt:AddLine(t) table.insert(self.lines, t) end
  function tt:AddDoubleLine(a, b) table.insert(self.lines, a .. " | " .. b) end
  function tt:Show() end
  function tt:SetItem(name, link) self.lines = {}; self.itemName, self.itemLink = name, link; if self.hooks.OnTooltipSetItem then self.hooks.OnTooltipSetItem(self) end end
  return tt
end
GameTooltip, ItemRefTooltip = tooltip(), tooltip()
-- a profession window: Elixir of Wisdom needs 2 Peacebloom (you have 1) and 1 Empty Vial (you have 5)
function hooksecurefunc(name, fn) local orig = _G[name]; _G[name] = function(...) local r = orig and orig(...); fn(...); return r end end
function TradeSkillFrame_SetSelection(i) end
TradeSkillFrame = obj({})
function GetTradeSkillNumReagents(i) return 2 end
function GetTradeSkillReagentInfo(i, r) if r == 1 then return "Peacebloom", "", 2, 1 end return "Empty Vial", "", 1, 5 end
function GetTradeSkillReagentItemLink(i, r) if r == 1 then return "|Hitem:2447::|h[Peacebloom]|h" end return "|Hitem:3371::|h[Empty Vial]|h" end
UISpecialFrames = {}
-- the game's class colours, class icon positions, coin and item icons
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04, colorStr = "ffff7c0a" }, MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" }, PRIEST = { r = 1, g = 1, b = 1 } }
CLASS_ICON_TCOORDS = { DRUID = { 0.74609375, 0.98828125, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 } }
function GetCoinTextureString(c) return "[coins " .. c .. "]" end
function GetItemIcon(id) return 132000 + id % 1000 end
-- skills and professions
SKILLS = { { "Professions", true }, { "Alchemy", false, 67, 150 }, { "Herbalism", false, 121, 150 },
           { "Secondary Skills", true }, { "Cooking", false, 108, 150 }, { "Weapon Skills", true }, { "Staves", false, 64, 70 } }
function GetNumSkillLines() return #SKILLS end
function GetSkillLineInfo(i) local x = SKILLS[i] return x[1], x[2], true, x[3] or 0, 0, 0, x[4] or 0 end
TRADE = { { "Reagents", "header" }, { "Elixir of Minor Defense", "trivial" }, { "Minor Healing Potion", "easy" }, { "Elixir of Wisdom", "optimal" } }
function GetTradeSkillLine() return "Alchemy", 70, 150 end
function GetNumTradeSkills() return #TRADE end
function GetTradeSkillInfo(i) return TRADE[i][1], TRADE[i][2] end
-- factions: name, standing, barMin, barMax, barValue, header, hasRep
FACTIONS = { { "Alliance", 0, 0, 0, 0, true, false }, { "Darnassus", 6, 9000, 21000, 11355 }, { "Stormwind", 5, 3000, 9000, 3795 },
             { "Other", 0, 0, 0, 0, true, false }, { "Cenarion Circle", 4, 0, 3000, 2200 } }
function GetNumFactions() return #FACTIONS end
function GetFactionInfo(i) local f = FACTIONS[i] return f[1], "", f[2], f[3], f[4], f[5], false, false, f[6] or false, false, f[7] ~= false and not f[6], false, false, 100 + i end
ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
-- combat log and XP chat
CLEU = {}
function CombatLogGetCurrentEventInfo() return unpack(CLEU) end
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
PLAYERGUID = "Player-1-0000ABCD"; PETGUID = "Creature-0-1-0-1-0000-PET0001"
local origGUID = UnitGUID
function UnitGUID(u) if u == "player" then return PLAYERGUID elseif u == "pet" then return PETGUID end return origGUID(u) end
-- quest log (this client's C_QuestLog), and Questie's official API
QLOG = { { questID = 486, title = "Ursal the Mauler", level = 12, have = 3 }, }
C_QuestLog = {
  GetNumQuestLogEntries = function() return #QLOG + 1 end,
  GetInfo = function(i) if i == 1 then return { isHeader = true, title = "Teldrassil" } end local q = QLOG[i - 1]; return q and { questID = q.questID, title = q.title, level = q.level, isHeader = false } end,
  IsComplete = function(id) return false end,
  GetQuestObjectives = function(id) for _, q in ipairs(QLOG) do if q.questID == id then return { { text = "Thistle Bear slain: " .. q.have .. "/8", numFulfilled = q.have, numRequired = 8, finished = false }, { text = "Ursal the Mauler slain: 0/1", numFulfilled = 0, numRequired = 1, finished = false } } end end return {} end,
}
QUESTIE_CB = nil
Questie = { API = { RegisterOnReady = function(cb) cb() end, RegisterForQuestUpdates = function(cb) QUESTIE_CB = cb end }, db = { char = { hidden = { [999] = true } } } }
-- Questie's internals the plan bridge uses
PINS, WATCHED, UNHIDDEN, BOOKPINS = {}, {}, {}, {}
local QMODS = {
  QuestieDB = { GetQuest = function(id) if id == 999 then return { name = "The Balance of Nature", level = 5, Starts = { NPC = { 2079 } } } end end },
  QuestieMap = { ShowNPC = function(self, npc, icon, scale, title, body) table.insert(PINS, npc .. " " .. title) end,
    DrawManualIcon = function(self, data, area, x, y, typ) BOOKPINS[data.id] = data.ManualTooltipData.Title .. " @" .. area .. " " .. x .. "," .. y; return {} end,
    UnloadManualFrames = function(self, id, typ) BOOKPINS[id] = nil end },
  ZoneDB = { GetAreaIdByUiMapId = function(self, m) return m + 100000 end },
  QuestieQuest = { UnhideQuest = function(self, id) UNHIDDEN[#UNHIDDEN + 1] = id; Questie.db.char.hidden[id] = nil end },
}
QuestieLoader = { ImportModule = function(self, name) return QMODS[name] end }
C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 488 or id == 81952 or id == 79008 or id == 79192 end
function GetItemCount(id) return id == 209843 and 1 or 0 end
C_QuestLog.GetLogIndexForQuestID = function(id) for i, q in ipairs(QLOG) do if q.questID == id then return i + 1 end end end
C_QuestLog.GetQuestWatchType = function(id) return WATCHED[id] end
C_QuestLog.AddQuestWatch = function(id) WATCHED[id] = 0 end
-- auction house: classic result pages and the newer C_AuctionHouse browse results
AHLIST = { { "Peacebloom", 5, 600, 2447 }, { "Peacebloom", 20, 2000, 2447 }, { "Empty Vial", 1, 0, 3371 }, { "Empty Vial", 10, 300, 3371 } }
function GetNumAuctionItems() return #AHLIST end
function GetAuctionItemInfo(kind, i) local a = AHLIST[i]; return a[1], 0, a[2], 1, true, 1, "", 100, 10, a[3], 0, false, nil, "x", nil, 0, a[4], true end
C_AuctionHouse = { GetBrowseResults = function() return { { itemKey = { itemID = 765 }, minPrice = 35, totalQuantity = 40 } } end }
-- full scan, newer style: 3,200 listings of 2 items (read in chunks), indexes from 0
C_AuctionHouse.ReplicateItems = function() FRAME_FIRE("REPLICATE_ITEM_LIST_UPDATE") end
C_AuctionHouse.GetNumReplicateItems = function() return 3200 end
C_AuctionHouse.GetReplicateItemInfo = function(k) local id = (k % 2 == 0) and 2449 or 2450; return "x", 0, 4, 1, true, 1, "", 1, 1, 400 + k, 0, false, nil, "x", nil, 0, id, true end
-- full scan, classic style
function CanSendAuctionQuery() return true, true end
function QueryAuctionItems(text, a, b, page, u, q, getAll) if getAll then FRAME_FIRE("AUCTION_ITEM_LIST_UPDATE") end end
-- water break window
function InCombatLockdown() return COMBAT or false end
function ReloadUI() RELOADED = true end
function print(...) io.write(table.concat({...}, " ") .. "\n") end
''')
L.execute('function FRAME_FIRE(e, ...) for _, fr in ipairs(FRAMES) do if fr.ev[e] and fr.fn then fr.fn(fr, e, ...) end end end')
L.execute('LL_NS = {}')
# the game's own dungeon entrance list (newer clients): one the generated data doesn't place, one it does (skipped)
L.execute('''C_Map = C_Map or {}
C_Map.GetMapChildrenInfo = function(id) if id == 1414 then return { { mapID = 1413 }, { mapID = 2548 }, { mapID = 2521 }, { mapID = 1439 } } end return {} end
C_EncounterJournal = { GetDungeonEntrancesForMap = function(m)
  if m == 2548 then return { { name = "The Drowned City", position = { x = 0.412, y = 0.633 }, atlasName = "Dungeon" } } end
  if m == 1413 then return { { name = "Wailing Caverns", position = { x = 0.46, y = 0.365 }, atlasName = "Dungeon" } } end
  return {} end }
-- the game's flight point list (newer clients): Auberdine known, a new Zephras Isle point not learned, a Horde one
Enum = Enum or {}; Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }; Enum.FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 }
C_TaxiMap = { GetTaxiNodesForMap = function(m)
  if m == 1439 then return { { name = "Auberdine, Darkshore", position = { x = 0.3634, y = 0.4558 }, state = 1, faction = 2 } } end
  if m == 2521 then return { { name = "Shen'dar Village, Zephras Isle", position = { x = 0.52, y = 0.61 }, state = 2, faction = 0 },
                             { name = "Horde Camp, Zephras Isle", position = { x = 0.2, y = 0.3 }, state = 2, faction = 1 } } end
  return {} end }
TAXI = {}
function NumTaxiNodes() return #(TAXI.nodes or {}) end
function TaxiNodeName(i) return TAXI.nodes[i][1] end
function TaxiNodeGetType(i) return TAXI.nodes[i][2] end''')
for f in ('LevelingLedger.lua', 'Shared.lua', 'Alts.lua', 'Break.lua', 'QuestLog.lua', 'QuestiePlan.lua', 'Auction.lua', 'RecipeVendors.lua', 'MrRobot.lua', 'Talents.lua', 'CollectionsData.lua', 'Collections.lua', 'EntranceData.lua', 'Entrances.lua', 'FlightData.lua', 'Flights.lua'):   # the order the .toc loads them; all get the same private table
    src = os.environ.get('LL_SHARED') if f == 'Shared.lua' and os.environ.get('LL_SHARED') else os.path.join(ROOT, 'addon', 'LevelingLedger', f)
    L.execute(open(src).read().replace('local ADDON, ns = ...', 'local ADDON, ns = "LevelingLedger", LL_NS'))
fire = L.eval('function(e, ...) for _, fr in ipairs(FRAMES) do if fr.ev[e] and fr.fn then fr.fn(fr, e, ...) end end end')
L.execute('LevelingLedgerShared = LevelingLedgerShared or {}; LevelingLedgerShared.recipes = { talwyn = { items = { [271900] = "Recipe: Elixir of Lesser Spirit" }, npcs = { [256729] = { 271900 } } } }')
L.execute('CreateFrame("Button", "MerchantItem1ItemButton"); CreateFrame("Button", "MerchantItem2ItemButton")')
L.execute('LevelingLedgerShared = LevelingLedgerShared or {}; LevelingLedgerShared.plans = { talwyn = { [486] = "Ursal the Mauler", [999] = "The Balance of Nature", [488] = "Zenn\'s Bidding" } }')
fire('ADDON_LOADED', 'LevelingLedger'); fire('PLAYER_LOGIN')
print('item name for an unloaded item, after the game sent it:', L.eval('LevelingLedgerDB.items[2592] and LevelingLedgerDB.items[2592].n'))
print('plan: tracked', dict(L.globals().WATCHED), '| pins', list(L.globals().PINS.values()), '| unhidden', list(L.globals().UNHIDDEN.values()))
slash_ = L.eval('SlashCmdList.LEVELINGLEDGER'); slash_('plan'); fire('PLAYER_ENTERING_WORLD', True, False)
L.execute('T = T + 1800; state.xp = 10000; REST = 500'); fire('PLAYER_XP_UPDATE')
# 5 kills that give you XP (yours, your pet's and a party member's) and a player kill with no XP: kills come from the XP messages
def kill(src, dst, msg=None):
    L.execute(f'CLEU = {{ 0, "PARTY_KILL", false, "{src}", "x", 0, 0, "{dst}" }}'); fire('COMBAT_LOG_EVENT_UNFILTERED')
    if msg: fire('CHAT_MSG_COMBAT_XP_GAIN', msg)
kill('Player-1-0000ABCD', 'Creature-0-1-1-1-2163-01', 'Thistle Bear dies, you gain 165 experience.')
kill('Player-1-0000ABCD', 'Creature-0-1-1-1-2163-02', 'Thistle Bear dies, you gain 330 experience. (+165 exp Rested bonus)')
kill('Player-1-0000ABCD', 'Creature-0-1-1-1-2235-03', 'Reef Crawler dies, you gain 150 experience.')
kill('Creature-0-1-0-1-0000-PET0001', 'Creature-0-1-1-1-2235-04', 'Reef Crawler dies, you gain 150 experience.')
kill('Player-1-0000FFFF', 'Creature-0-1-1-1-2163-05', 'Thistle Bear dies, you gain 82 experience.')
kill('Player-1-0000ABCD', 'Player-1-0000EEEE')
fire('CHAT_MSG_COMBAT_XP_GAIN', 'Discovered Auberdine: 90 experience gained')
L.execute('T = T + 900; state.level = 14; state.xp = 2000'); fire('PLAYER_LEVEL_UP', 14); fire('PLAYER_XP_UPDATE')
def money(d, *after):
    L.execute(f'state.money = state.money + ({d})'); fire('PLAYER_MONEY')
L.execute('T = T + 5'); money(125)                                   # loot
# an objective moves: Questie tells us, and the log is read again
L.execute('QLOG[1].have = 6; QUESTIE_CB(486, 1, 2)')
print('quest log:', L.eval('function() local q = LevelingLedgerDB.chars["Talwyn-Normal"].questLog[486]; return q.t .. " | " .. q.ob[1].text .. " | " .. q.ob[2].text end')())
L.execute('T = T + 60'); fire('QUEST_TURNED_IN', 486, 1150, 1000); money(1000)   # quest gold after the event
print('quest 486 took:', L.eval('function() for _, q in ipairs(LevelingLedgerDB.chars["Talwyn-Normal"].quests) do if q.id == 486 then return q.took end end end')(), 'seconds')
L.execute('T = T + 60'); money(250); fire('QUEST_TURNED_IN', 487, 300, 250)      # quest gold before the event
L.execute('T = T + 60'); money(40)                                    # loot
L.execute('SKILLS[3][3] = 125'); fire('CHAT_MSG_SKILL', 'Your skill in Herbalism has increased to 125.')
L.execute('SKILLS[3][3] = 128'); fire('CHAT_MSG_SKILL', 'Your skill in Herbalism has increased to 128.')
L.execute('SKILLS[7][3] = 66'); fire('SKILL_LINES_CHANGED')          # weapon skill: ignored
fire('CHAT_MSG_SYSTEM', 'You have learned how to create a new item: Elixir of Wisdom.')
L.execute('FACTIONS[2][5] = 11605'); fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Your reputation with Darnassus has increased by 250.'); fire('UPDATE_FACTION')
L.execute('FACTIONS[5][5] = 2950'); fire('UPDATE_FACTION')
L.execute('FACTIONS[5][2] = 5; FACTIONS[5][3] = 3000; FACTIONS[5][4] = 9000; FACTIONS[5][5] = 3075'); fire('UPDATE_FACTION')   # Cenarion Circle: Neutral -> Friendly
fire('CHAT_MSG_SYSTEM', 'You have learned a new spell: Moonfire (Rank 3).')   # not a recipe
L.execute('SKILLS[2][3] = 70'); fire('SKILL_LINES_CHANGED'); fire('TRADE_SKILL_SHOW')
L.execute('NPCGUID = "Creature-0-1-0-1-256729-000001"; NPCNAME = "Nina Surefire"; ZONE = "Redridge Mountains"'); fire('MERCHANT_SHOW')
slash_('recipes')
money(500); money(-20); fire('MERCHANT_CLOSED')                       # sell, then buy or repair
L.execute('NPCGUID = "Creature-0-1-0-1-3602-000002"; NPCNAME = "Kal"'); fire('TRAINER_SHOW'); print('trainer filters afterwards:', dict(L.globals().FILTER))
money(-380); fire('TRAINER_CLOSED')                                   # training
L.execute('T = T + 60'); fire('MAIL_SHOW'); money(10000); money(-30); fire('MAIL_CLOSED')   # gold from an alt, postage
L.execute('ZONE = "The Deadmines"; INSTANCE = true; TARGETGUID = "Creature-0-1-36-1-1763-0000AAAA"'); fire('PLAYER_TARGET_CHANGED'); fire('LOOT_OPENED')
# gathering a Peacebloom node (object 1618) in Darkshore: recorded with its map position
L.execute('ZONE = "Darkshore"; INSTANCE = false; LOOTSRC = "GameObject-0-1-1-1-1618-0000BBBB"'); fire('LOOT_OPENED')
# skinning a Thistle Bear (creature 2163): Light Leather from its corpse is a skinning spot
L.execute('LOOTLINKS = { "|cffffffff|Hitem:2318::::::::13:::::|h[Light Leather]|h|r", "|cffffffff|Hitem:2318::::::::13:::::|h[Light Leather]|h|r" }; LOOTSRC = "Creature-0-1-1-1-2163-0000CCCC"'); fire('LOOT_OPENED')
# fishing: two catches from the same bobber window counted once, a second bobber, a getaway (newer clients send
# error type and message; older ones the message alone), and another zone
L.execute('function IsFishingLoot() return FISHING or false end; GetLootSlotInfo = GetLootSlotInfo or function(s) return nil, "", 1 end; ERR_FISH_ESCAPED = "Your fish got away!"')
L.execute('FISHING = true; ZONE = "Darkshore"; LOOTLINKS = { "|cffffffff|Hitem:6291::::::::13:::::|h[Raw Brilliant Smallfish]|h|r", "|cffffffff|Hitem:6303::::::::13:::::|h[Raw Slitherskin Mackerel]|h|r" }; LOOTSRC = "GameObject-0-1-1-1-35591-0000F001"')
fire('LOOT_OPENED'); fire('LOOT_OPENED')
L.execute('LOOTSRC = "GameObject-0-1-1-1-35591-0000F002"'); fire('LOOT_OPENED')
fire('UI_ERROR_MESSAGE', 51, 'Your fish got away!'); fire('UI_ERROR_MESSAGE', 'Your fish got away!'); fire('UI_ERROR_MESSAGE', 50, 'Not enough mana')
L.execute('ZONE = "Westfall"; LOOTSRC = "GameObject-0-1-1-1-35591-0000F003"'); fire('LOOT_OPENED')
L.execute('FISHING = false; LOOTLINKS = nil; ZONE = "Darkshore"')
_fz = L.eval('LevelingLedgerDB.chars["Talwyn-Normal"].fishing.zones')
print('fishing:', {z: {'c': _fz[z].c, 'g': _fz[z].g, 'items': dict(_fz[z]['items']), 'lo': _fz[z].lo} for z in _fz})
print('fishing spots:', [(p.z, p.x, p.y, p.g) for p in L.eval('LevelingLedgerDB.chars["Talwyn-Normal"].fishing.spots').values()])
L.execute('LOOTLINKS = nil')
L.execute('LOOTSRC = "Creature-0-1-36-1-1763-0000AAAA"')
print('gathers:', [dict(g) for g in L.globals().LevelingLedgerDB.chars['Talwyn-Normal'].gathers.values()])
fire('PLAYER_DEAD')
L.execute('ZONE = "Darkshore"; INSTANCE = false; SUBZONE = "Lor\'danel"'); fire('ZONE_CHANGED_NEW_AREA')
L.execute('RESTING = true; SUBZONE = "Lor\'danel Inn"'); fire('PLAYER_UPDATE_RESTING')
# Ask Mr. Robot Classic's saved table after an import from the website (AceDB: char["Name - Realm"])
L.execute(r'''
AskMrRobotDb5 = { char = { ["Talwyn - Normal"] = {
  GearSetups = { { IsBib = false, SpecSlot = 2, Id = "AMR1", Label = "Feral leveling",
    Gear = { [1] = { id = 274155, enchantId = 0, gemIds = {} }, [16] = { id = 6681, enchantId = 241, gemIds = {} }, [11] = { id = 6693, enchantId = 0, gemIds = {} } } } },
  JunkData = { Junk = { { id = 2589 }, { id = 4306 } }, Keep = { ["x"] = { id = 6693 } } } } } }
C_Item = C_Item or {}
C_Item.GetItemNameByID = function(id) return ({ [274155] = "Geomancer Headdress", [6681] = "Thornspike" })[id] end
''')
# while logging out the game can answer with nothing: no rested XP, zone, resting, gold, level, XP, bags, completed
# quests, quest log or item names. Everything saved before must survive.
fire('BAG_UPDATE_DELAYED'); fire('QUEST_LOG_UPDATE')
_snap = 'function() local c = LevelingLedgerDB.chars["Talwyn-Normal"]; local n, q = 0, 0; for _ in pairs(c.bags or {}) do n = n + 1 end; for _ in pairs(c.questLog or {}) do q = q + 1 end; local s = c.sessions[#c.sessions]; return string.format("rested %s, zone %s/%s, resting %s, money %s, level %s, lastXP %s, bag kinds %d, bagItems %d, quest log %d, books %d, chain quests %d, session end level %s xp %s rested %s", tostring(c.rested), tostring(c.zone), tostring(c.subzone), tostring(c.resting), tostring(c.money), tostring(c.level), tostring(c.lastXP), n, #(c.bagItems or {}), q, #((c.books or {}).done or {}), #((c.chainq or {}).done or {}), tostring(s.endLevel), tostring(s.endXP), tostring(s.endRested)) end'
fire('PLAYER_LOGOUT')  # an ordinary /reload first: Ask Mr. Robot's names are known then
L.execute('LevelingLedgerDB.chars["Talwyn-Normal"].questLog = LevelingLedgerDB.chars["Talwyn-Normal"].questLog or {}; local ql = LevelingLedgerDB.chars["Talwyn-Normal"].questLog; ql[90001] = ql[90001] or { t = "x" }; ql[90002] = ql[90002] or { t = "y" }')
before = L.eval(_snap)()
L.execute('''_SAVE = { REST, ZONE, SUBZONE, RESTING, state.money, state.level, state.xp, CONTAINERS, QLOG, C_QuestLog.IsQuestFlaggedCompleted, C_Item.GetItemNameByID }
REST = nil; ZONE = ""; SUBZONE = ""; RESTING = false; state.money = 0; state.level = 0; state.xp = 0; CONTAINERS = {}; QLOG = {}
C_QuestLog.IsQuestFlaggedCompleted = function() return false end; C_Item.GetItemNameByID = function() return nil end
GetRealZoneText = function() return ZONE end
_GIID = GetInventoryItemID; GetInventoryItemID = function() return nil end''')
L.execute('T = T + 600'); fire('QUEST_LOG_UPDATE'); fire('PLAYER_LOGOUT')
after = L.eval(_snap)()
print('before logout:', before); print('after a blank logout:', after)
print('logout kept everything:', before.split(', session')[0] == after.split(', session')[0])
print('Ask Mr. Robot names kept:', dict(L.globals().LevelingLedgerDB.chars['Talwyn-Normal'].amr.names))
L.execute('''REST, ZONE, SUBZONE, RESTING, state.money, state.level, state.xp, CONTAINERS, QLOG, C_QuestLog.IsQuestFlaggedCompleted, C_Item.GetItemNameByID = unpack(_SAVE)
GetRealZoneText = function() return ZONE or "Darkshore" end; GetInventoryItemID = _GIID''')
# bags, bank, tooltip, profession window and /ledger alts
fire('BAG_UPDATE_DELAYED'); fire('BANKFRAME_OPENED'); fire('BANKFRAME_CLOSED')
me = L.globals().LevelingLedgerDB.chars['Talwyn-Normal']
print('your bags:', dict(me.bags), '| bank:', dict(me.bank), '| gold:', me.money)
# the newest engine: no bank bags, character bank tabs from 6 (and the reagent bag at 5, which is never bank)
L.execute('_BI = Enum.BagIndex; Enum.BagIndex = { Backpack = 0, Bag_1 = 1, Bag_4 = 4, ReagentBag = 5, Bank = -1, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7 }')
fire('BANKFRAME_OPENED'); fire('BANKFRAME_CLOSED')
print('bank tabs engine: bags', dict(me.bags), '| bank:', dict(me.bank))
# a client with no bag names at all (classic numbering): bank bags straight after the four bags
L.execute('Enum.BagIndex = nil')
fire('BANKFRAME_OPENED'); fire('BANKFRAME_CLOSED')
print('no bag names: bank:', dict(me.bank))
L.execute('Enum.BagIndex = _BI')
fire('BANKFRAME_OPENED'); fire('BANKFRAME_CLOSED')
# auction prices on reagent tooltips: Peacebloom from this account's own scan, Briarthorn where the app's copy
# (Shared.lua, every device) is newer than ours
L.execute('''_GII = GetItemInfo
GetItemInfo = function(link) local id = tonumber(tostring(link):match("item:(%d+)") or link)
  if id == 2447 or id == 2450 then return "Herb", nil, 1, 5, 0, "Tradeskill", "Herb", 20, "", nil, 10, 7, 9, 0, 0, nil, true end
  return nil end
LevelingLedgerDB.ah = LevelingLedgerDB.ah or {}
LevelingLedgerDB.ah[2447] = { p = 95, n = 40, at = T - 3600 * 30 }
LevelingLedgerDB.ah[2450] = { p = 300, n = 3, at = T - 86400 * 9 }
LevelingLedgerShared = LevelingLedgerShared or {}; LevelingLedgerShared.ah = { [2450] = { 182, 12, T - 7200 } }
GetCoinTextureString = function(c) local g, s2, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100; return (g > 0 and (g .. "g ") or "") .. (s2 > 0 and (s2 .. "s ") or "") .. cp .. "c" end''')
L.execute('GameTooltip:SetItem("Peacebloom", "|cffffffff|Hitem:2447::::::::13:::::|h[Peacebloom]|h|r")')
print('tooltip for Peacebloom:', list(L.globals().GameTooltip.lines.values()))
L.execute('GameTooltip:SetItem("Briarthorn", "|cffffffff|Hitem:2450::::::::13:::::|h[Briarthorn]|h|r")')
print('tooltip for Briarthorn (only you have it):', list(L.globals().GameTooltip.lines.values()))
L.execute('GetItemInfo = _GII')
L.execute('TradeSkillFrame_SetSelection(3)')
helper = L.eval('function() for _, fr in ipairs(FRAMES) do if fr.fonts and fr.fonts[1] and fr.fonts[1].text and fr.fonts[1].text:find("alts\' materials") then return fr.fonts[1].text end end end')()
print('profession window:', helper)
L.eval('SlashCmdList.LEVELINGLEDGER')('alts')
alts = L.globals().LevelingLedgerAlts
print('alts window shown:', alts.shown)
print(L.eval('function() return LevelingLedgerAlts.info and LevelingLedgerAlts.info.text end')())
print('\n'.join(t for t in L.eval('function() local t = {} for _, f in ipairs(LevelingLedgerAlts.rows) do t[#t + 1] = f.text or "" end return t end')().values() if t))
L.execute('for _, b in ipairs(LevelingLedgerAlts.charButtons) do if type(rawget(b, "o")) == "table" and b.o.c.name == "Bob" then b.scripts.OnClick(b) end end')
print('-- Bob:'); print(L.eval('function() return LevelingLedgerAlts.info.text end')())
print('\n'.join(t for t in L.eval('function() local t = {} for _, f in ipairs(LevelingLedgerAlts.rows) do t[#t + 1] = f.text or "" end return t end')().values() if t))
L.execute('LevelingLedgerAltsSearch.text = "linen"; function LevelingLedgerAltsSearch:GetText() return self.text end; LevelingLedgerAltsSearch.scripts.OnTextChanged(LevelingLedgerAltsSearch)')
print('-- search "linen":', [t for t in L.eval('function() local t = {} for _, f in ipairs(LevelingLedgerAlts.rows) do t[#t + 1] = f.text or "" end return t end')().values() if t])

# the newer engine: no skill lines or classic trade skill functions; GetProfessions and C_TradeSkillUI instead
L.execute('''GetNumSkillLines, GetSkillLineInfo, GetTradeSkillLine, GetNumTradeSkills = nil, nil, nil, nil
function GetProfessions() return 1, nil, nil, 4, 5 end
local P = { [1] = { "Herbalism", 128, 150 }, [4] = { "Cooking", 112, 150 }, [5] = { "First Aid", 75, 75 } }
function GetProfessionInfo(i) local p = P[i]; return p[1], 0, p[2], p[3] end
C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionName = "Cooking" } end, GetAllRecipeIDs = function() return { 1, 2, 3 } end,
  GetRecipeInfo = function(id) return ({ { name = "Coyote Steak", learned = true }, { name = "Thistle Tea", learned = false }, { name = "Herb Baked Egg", learned = true } })[id] end }''')
fire('SKILL_LINES_CHANGED'); fire('TRADE_SKILL_LIST_UPDATE')
c = L.globals().LevelingLedgerDB.chars['Talwyn-Normal']
print('skills (newer engine):', {k: dict(v)['rank'] for k, v in c.skills.items()})
# the in-game panel, before logging out
fire('AUCTION_ITEM_LIST_UPDATE'); fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
print('auction prices:', {k: dict(v) for k, v in L.globals().LevelingLedgerDB.ah.items()})
# Bob logged out at an inn two days ago: 30% of a level rested by now, so he's the best alt
L.execute('for k, c in pairs(LevelingLedgerDB.chars) do if c.name == "Bob" then c.level = 10; c.xpMax = { [10] = 8000 }; c.rested = 0; c.resting = true; c.stateAt = T - 48 * 3600 end end')
show = L.eval('function() local p = LevelingLedgerPanel; p.scripts.OnUpdate(p, 1.5); local t = {} for _, f in ipairs(p.fonts) do t[#t + 1] = f.text or "" end return table.concat(t, "\\n") end')
p = L.globals().LevelingLedgerPanel
print('panel shown:', p.shown, '| starts at', [p.point[k] for k in (1, 3, 4, 5)])
print(show())
slash = L.eval('SlashCmdList.LEVELINGLEDGER')
for cmd in ('lock', 'hide', 'show', 'unlock'):
    slash(cmd); print('  after', cmd, '-> shown', p.shown, 'locked', L.globals().LevelingLedgerDB.panel.locked)
L.execute('LevelingLedgerPanel.point = { "CENTER", UIParent, "CENTER", 120, -40 }; LevelingLedgerPanel.scripts.OnDragStop(LevelingLedgerPanel)')
print('saved spot after drag:', dict(L.globals().LevelingLedgerDB.panel))
slash('reset'); print('after reset:', dict(L.globals().LevelingLedgerDB.panel), [p.point[k] for k in (1, 3, 4, 5)])
L.eval('SlashCmdList.LEVELINGLEDGER')('')
# Save: a secure /reload button (the key binding clicks it); add-on code never calls ReloadUI
b = L.eval('function() local b = rawget(_G, "LevelingLedgerSaveButton"); return b and b.attrs and (b.attrs.type .. " " .. b.attrs.macrotext) end')()
print('save button:', b, '| binding:', L.eval('function() return _G["BINDING_NAME_CLICK LevelingLedgerSaveButton:LeftButton"] end')())
L.execute('RELOADED = nil'); slash('save'); print('/ledger save reloaded:', L.globals().RELOADED)
# water breaks: due an hour after login, held back during a fight, "Later" asks again in 15 minutes
tick = L.eval('function() for _, fr in ipairs(FRAMES) do if fr.scripts.OnUpdate and fr ~= LevelingLedgerPanel then fr.scripts.OnUpdate(fr, 20) end end end')
water = lambda: L.eval('function() local w = rawget(_G, "LevelingLedgerWater") if not w then return "none" end return (w.shown and "shown: " or "hidden: ") .. (w.text.text or "") end')()
slash('water')
L.execute('T = T + 3600; COMBAT = true'); tick(); print('water window in a fight:', water())
L.execute('COMBAT = false'); fire('PLAYER_REGEN_ENABLED'); print('after the fight:', water())
L.execute('LevelingLedgerWater.later.scripts.OnClick()'); print('after Later:', water()[:7]); slash('water')
L.execute('T = T + 900'); tick(); print('15 min later:', water())
L.execute('COMBAT = true; LevelingLedgerWater.later.scripts.OnClick()'); print('Later in a fight, window shown:', L.globals().LevelingLedgerWater.shown)
L.execute('COMBAT = false'); fire('PLAYER_REGEN_ENABLED'); print('after the fight, window shown:', L.globals().LevelingLedgerWater.shown)
print('Reload now is a secure /reload:', L.eval('function() return LevelingLedgerWater.ok.attrs and LevelingLedgerWater.ok.attrs.macrotext end')())
# full auction scan: the button appears on the auction window; newer style first, then classic; 15-minute limit
# the window doesn't exist yet when the game says the auction house opened (it loads on first use): no button yet,
# then the window's add-on finishes loading and the button is made; /ledger scan does the same as the button
L.execute('_AH_BUTTONS = 0; local cf = CreateFrame; CreateFrame = function(kind, name, parent, ...) local f = cf(kind, name, parent, ...); if kind == "Button" and parent and parent == rawget(_G, "AuctionHouseFrame") then _AH_BUTTONS = _AH_BUTTONS + 1 end; return f end')
slash('scan'); fire('AUCTION_HOUSE_SHOW')
print('auction window not loaded yet, buttons:', L.eval('_AH_BUTTONS'))
L.execute('CreateFrame("Frame", "AuctionHouseFrame")'); fire('ADDON_LOADED', 'Blizzard_AuctionHouseUI'); fire('AUCTION_HOUSE_SHOW')
print('after the window loaded, buttons:', L.eval('_AH_BUTTONS'))
slash('scan')
for _ in range(4): tick()
ah = L.globals().LevelingLedgerDB.ah
print('full scan (newer):', {k: dict(ah[k]) for k in (2449, 2450)})
L.execute('LL_NS.ahScan()')   # too soon
L.execute('LevelingLedgerDB.ahScanAt = 0; C_AuctionHouse.ReplicateItems = nil; AHLIST = { { "Earthroot", 10, 900, 2449 } }; LL_NS.ahScan()'); tick()
print('full scan (classic):', dict(L.globals().LevelingLedgerDB.ah[2449]))
slash('water 45'); slash('water off'); L.execute('LevelingLedgerWater:Hide(); T = T + 9000'); tick(); print('with reminders off:', water()[:7]); slash('water on')
# talent plan reminders from Shared.lua: at level up, and /ledger talents
L.execute('LevelingLedgerShared = LevelingLedgerShared or {}; LevelingLedgerShared.talents = { ["talwyn"] = { from = 10, picks = { "Ferocity 1/5", "Ferocity 2/5", "Ferocity 3/5", "Ferocity 4/5", "Ferocity 5/5", "Furor 1/3" } } }')
fire('PLAYER_LEVEL_UP', 14); slash('talents')
# Library Books: pins for books still needed (not handed in, not in bags), /ledger books, and the logout record
_n = L.eval('function() local n = 0; for _ in pairs(BOOKPINS) do n = n + 1 end; return n end')()
print('book pins:', _n, '| book 1 pinned:', L.eval('BOOKPINS[990001]'), '| book 2 pinned:', L.eval('BOOKPINS[990002]'), '| book 3:', L.eval('BOOKPINS[990003]'))
slash('books')
print('chain pin:', L.eval('BOOKPINS[995001]'))
print('bags in slots:', list(L.eval('function() for _, c in pairs(LevelingLedgerDB.chars) do if c.name == "Talwyn" then return c.bagItems end end end')().values()), '| bank bag slots:', list((L.eval('function() for _, c in pairs(LevelingLedgerDB.chars) do if c.name == "Talwyn" then return c.bankBagItems end end end')() or {}).values()))
slash('chains')
# secrets: ? pins on the spots of the ones not done yet (your class, faction and level), /ledger secrets, a toy learned,
# a tick from the page (Shared.lua), and the logout record
_sp = 'function() local n, t = 0, {}; for id, v in pairs(BOOKPINS) do if id >= 996000 and id < 997000 then n = n + 1; t[v:match("Secret: ([^@]-) @")] = true end end; local l = {}; for k in pairs(t) do l[#l + 1] = k end; table.sort(l); return n .. " pins: " .. table.concat(l, ", ") end'
print('secret pins:', L.eval(_sp)())
slash('secrets')
L.execute('PlayerHasToy = function(id) return id == 280612 end; LevelingLedgerShared.secrets = { ["talwyn"] = { ["gustjumper"] = true } }')
fire('BAG_UPDATE_DELAYED')
print('after learning the torch and ticking the frog on the page:', L.eval(_sp)())
slash('secrets pins off'); print('secret pins after off:', L.eval(_sp)()); slash('secrets pins on')
fire('PLAYER_LOGOUT')
print('secrets saved at logout:', list(L.eval('LevelingLedgerDB.chars["Talwyn-Normal"].secrets.done').values()))
# dungeon and raid entrances: a pin per entrance spot (Blackrock Mountain's instances share one), the game's list for the
# newest dungeons, /ledger dungeons for your level, pins off and on
_ep = 'function() local n, t = 0, {}; for id, v in pairs(BOOKPINS) do if id >= 997000 and id < 998000 then n = n + 1; t[#t + 1] = v end end; table.sort(t); return n, t end'
_n, _t = L.eval(_ep)()
print('entrance pins:', _n, '|', [v for v in _t.values() if 'Blackrock' in v or 'Drowned' in v or 'Wailing' in v or 'Ahn' in v])
L.execute('FIRSTPIN = nil; for id, v in pairs(BOOKPINS) do if id >= 997000 then FIRSTPIN = id end end')
slash('dungeons')
slash('dungeons pins off'); print('entrance pins after off:', L.eval(_ep)()[0]); slash('dungeons pins on'); print('after on:', L.eval(_ep)()[0])
# flight points: a pin per flight master of your faction (and neutral ones), learned or not, the game's list for new
# zones, a flight map opened, /ledger flights, pins off and on
_fp = 'function() local n, t = 0, {}; for id, v in pairs(BOOKPINS) do if id >= 998000 then n = n + 1; t[#t + 1] = v end end; table.sort(t); return n, t end'
_n, _t = L.eval(_fp)()
print('flight pins:', _n, '|', [v for v in _t.values() if 'Darkshore' in v or 'Zephras' in v or 'Westfall' in v])
L.execute('NPCGUID = "Creature-0-1-0-1-523-000003"; TAXI.nodes = { { "Sentinel Hill, Westfall", "CURRENT" }, { "Lakeshire, Redridge Mountains", "REACHABLE" }, { "Darkshire, Duskwood", "NONE" } }')
fire('TAXIMAP_OPENED')
print('after the flight map at Thor:', dict(L.eval('LevelingLedgerDB.chars["Talwyn-Normal"].flights.npcs')), sorted(L.eval('LevelingLedgerDB.chars["Talwyn-Normal"].flights.names').keys()))
slash('flights')
slash('flights pins off'); print('flight pins after off:', L.eval(_fp)()[0]); slash('flights pins on'); print('after on:', L.eval(_fp)()[0])
slash('books pins off'); print('pins after off:', L.eval('function() local n = 0; for _ in pairs(BOOKPINS) do n = n + 1 end; return n end')()); slash('books pins on')
# serialize like WoW's SavedVariables writer
ser = L.eval(r'''
function(v)
  local function s(x, ind)
    local t = type(x)
    if t == "table" then
      local keys = {} for k in pairs(x) do keys[#keys+1] = k end
      table.sort(keys, function(a, b) if type(a) == type(b) then return a < b end return type(a) == "number" end)
      local out = {"{\n"}
      for _, k in ipairs(keys) do
        local kk = type(k) == "number" and ("[" .. k .. "]") or string.format("[%q]", k)
        out[#out+1] = ind .. "\t" .. kk .. " = " .. s(x[k], ind .. "\t") .. ",\n"
      end
      out[#out+1] = ind .. "}" return table.concat(out)
    elseif t == "string" then return string.format("%q", x)
    elseif t == "boolean" then return tostring(x) else return tostring(x) end
  end
  return "\nLevelingLedgerDB = " .. s(v, "") .. "\n"
end''')
open(OUT, 'w').write(ser(L.globals().LevelingLedgerDB))
print('wrote', OUT)
