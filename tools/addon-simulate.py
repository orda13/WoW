# Runs the add-on in real Lua with a fake WoW API, then writes SavedVariables the way the game does.
import lupa, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else 'SampleSavedVariables.lua'
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
T = 1794000000
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
  function fr:RegisterEvent(e) self.ev[e] = true end
  function fr:SetScript(n, fn) self.scripts[n] = fn; if n == "OnEvent" then self.fn = fn end end
  function fr:Show() self.shown = true end
  function fr:Hide() self.shown = false end
  function fr:IsShown() return self.shown end
  function fr:SetPoint(...) self.point = { ... } end
  function fr:GetPoint() local p = self.point or {} return p[1], p[2], p[3], p[4], p[5] end
  fr.fonts = {}
  function fr:CreateFontString() local fs = obj({}) function fs:SetText(t) self.text = t end table.insert(fr.fonts, fs) return fs end
  function fr:CreateTexture() return obj({}) end
  if name then _G[name] = obj(fr) end
  if not FRAME then FRAME = fr end
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
function GetNumTrainerServices() return 3 end
local TS = { { "Regrowth", "Rank 1", "available", 180, 12 }, { "Thorns", "Rank 2", "available", 200, 14 }, { "Druid", nil, "header", 0, 0 } }
function GetTrainerServiceInfo(i) return TS[i][1], TS[i][2], TS[i][3] end
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
function GetLootSlotLink(s) if s == 1 then return "|cff0070dd|Hitem:273297::::::::13:::::|h[Goblin Hammer]|h|r" end return "|cff9d9d9d|Hitem:2589::::::::13:::::|h[Linen Cloth]|h|r" end
function GetLootSourceInfo(s) return "Creature-0-1-36-1-1763-0000AAAA", 1 end
function GetItemInfo(link) return nil end
C_Item = { GetItemQualityByID = function(link) if link:find("Goblin") then return 3 end return 1 end }
SlashCmdList = {}
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
function print(...) io.write(table.concat({...}, " ") .. "\n") end
''')
L.execute(open(os.path.join(ROOT, 'addon', 'LevelingLedger', 'LevelingLedger.lua')).read().replace('local ADDON = ...', 'local ADDON = "LevelingLedger"'))
fire = L.eval('function(e, ...) FRAME.fn(FRAME, e, ...) end')
fire('ADDON_LOADED', 'LevelingLedger'); fire('PLAYER_LOGIN'); fire('PLAYER_ENTERING_WORLD', True, False)
L.execute('T = T + 1800; state.xp = 10000; REST = 500'); fire('PLAYER_XP_UPDATE')
# 3 kills by you (one with rested bonus), 1 by your pet, 1 by a party member (XP but not your kill), and a non-creature kill
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
L.execute('T = T + 60'); fire('QUEST_TURNED_IN', 486, 1150, 1000); money(1000)   # quest gold after the event
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
money(500); money(-20); fire('MERCHANT_CLOSED')                       # sell, then buy or repair
L.execute('NPCGUID = "Creature-0-1-0-1-3602-000002"; NPCNAME = "Kal"'); fire('TRAINER_SHOW')
money(-380); fire('TRAINER_CLOSED')                                   # training
L.execute('T = T + 60'); fire('MAIL_SHOW'); money(10000); money(-30); fire('MAIL_CLOSED')   # gold from an alt, postage
L.execute('ZONE = "The Deadmines"; INSTANCE = true; TARGETGUID = "Creature-0-1-36-1-1763-0000AAAA"'); fire('PLAYER_TARGET_CHANGED'); fire('LOOT_OPENED')
fire('PLAYER_DEAD')
L.execute('ZONE = "Darkshore"; INSTANCE = false; SUBZONE = "Lor\'danel"'); fire('ZONE_CHANGED_NEW_AREA')
L.execute('RESTING = true; SUBZONE = "Lor\'danel Inn"'); fire('PLAYER_UPDATE_RESTING')
L.execute('T = T + 600'); fire('PLAYER_LOGOUT')
# the in-game panel, before logging out
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
