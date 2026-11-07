# Level ranges of the original 2004-era zones (well-established; Forever is set in that era).
RANGES = {'Elwynn Forest':(1,10),'Dun Morogh':(1,10),'Teldrassil':(1,10),'Durotar':(1,10),'Mulgore':(1,10),'Tirisfal Glades':(1,10),
'Northshire Valley':(1,5),'Coldridge Valley':(1,5),'Shadowglen':(1,5),'Valley of Trials':(1,5),'Camp Narache':(1,5),'Deathknell':(1,5),
'Westfall':(10,20),'Loch Modan':(10,20),'Darkshore':(10,20),'The Barrens':(10,25),'Silverpine Forest':(10,20),'Redridge Mountains':(15,25),
'Stonetalon Mountains':(15,27),'Ashenvale':(18,30),'Duskwood':(18,30),'Wetlands':(20,30),'Hillsbrad Foothills':(20,30),'Thousand Needles':(25,35),
'Alterac Mountains':(30,40),'Arathi Highlands':(30,40),'Desolace':(30,40),'Stranglethorn Vale':(30,45),'Dustwallow Marsh':(35,45),'Badlands':(35,45),
'Swamp of Sorrows':(35,45),'Feralas':(40,50),'The Hinterlands':(40,50),'Tanaris':(40,50),'Searing Gorge':(43,50),'Azshara':(45,55),
'Blasted Lands':(45,55),"Un'Goro Crater":(48,55),'Felwood':(48,55),'Burning Steppes':(50,58),'Western Plaguelands':(51,58),
'Eastern Plaguelands':(53,60),'Winterspring':(53,60),'Silithus':(55,60),'Deadwind Pass':(55,60)}
RANGES.update({
 # Original dungeons
 'Ragefire Chasm':(13,18),'The Deadmines':(17,26),'Wailing Caverns':(17,24),'Shadowfang Keep':(22,30),'Blackfathom Deeps':(24,32),
 'The Stockade':(24,32),'Gnomeregan':(29,38),'Razorfen Kraul':(29,38),'Scarlet Monastery':(34,45),'Razorfen Downs':(37,46),
 'Uldaman':(41,51),"Zul'Farrak":(44,54),'Maraudon':(46,55),'The Temple of Atal\'Hakkar':(50,56),'Sunken Temple':(50,56),
 'Blackrock Depths':(52,60),'Blackrock Spire':(55,60),'Blackrock Mountain':(52,60),'Dire Maul':(55,60),'Scholomance':(58,60),'Stratholme':(58,60),
 # Raids and battlegrounds
 'Molten Core':(60,60),"Onyxia's Lair":(60,60),'Blackwing Lair':(60,60),"Zul'Gurub":(60,60),"Ahn'Qiraj":(60,60),'Ruins of Ahn\'Qiraj':(60,60),
 'Naxxramas':(60,60),'Alterac Valley':(51,60),'Arathi Basin':(20,60),'Warsong Gulch':(10,60),
 # Sub-zones and hubs, given their parent zone's range
 'Northshire Abbey':(1,5),'Anvilmar':(1,5),'Kharanos':(1,10),'Red Cloud Mesa':(1,5),'Auberdine':(10,20),'Booty Bay':(30,45),
 'Ratchet':(10,25),'Aerie Peak':(40,50),'Feathermoon Stronghold':(40,50),'Gadgetzan':(40,50),'The Shimmering Flats':(25,35),
 'Stonewrought Dam':(10,20),"Rut'theran Village":(1,10),'Timbermaw Hold':(48,55),"Thoradin's Wall":(30,40),'Moonglade':(10,60),
})
CITIES = {'Darnassus','Stormwind City','Ironforge','Orgrimmar','Thunder Bluff','Undercity','Deeprun Tram','City of Dalaran','Crafting'}
