--[[
	Item, terrain-material, gathering and tool definitions. Edit this file to add content.

	Items.Defs[id]       = { Name, Stack, Color, Tool = {Type,Tier}?, Block = {Id,Material,Color,...}? }
	Items.TerrainMats[m] = what mining a Roblox terrain material gives and costs
	Items.Gather[decoType] = what chopping/breaking a world decoration (tree, rock...) gives
]]

local M = Enum.Material

local Items = {}

-- Tool power per tier (index = tier + 1). Tier 0 = bare hands.
Items.TierPower = { 1, 2, 3, 5, 8 }

Items.Defs = {
	-- Resources
	Wood = { Name = "Wood", Stack = 99, Color = Color3.fromRGB(120, 86, 52) },
	Stick = { Name = "Stick", Stack = 99, Color = Color3.fromRGB(150, 110, 70) },
	Fiber = { Name = "Fiber", Stack = 99, Color = Color3.fromRGB(110, 160, 80) },
	Cactus = { Name = "Cactus", Stack = 99, Color = Color3.fromRGB(80, 130, 70) },
	Coal = { Name = "Coal", Stack = 99, Color = Color3.fromRGB(40, 40, 44) },
	IronOre = { Name = "Iron Ore", Stack = 99, Color = Color3.fromRGB(200, 170, 150) },
	GoldOre = { Name = "Gold Ore", Stack = 99, Color = Color3.fromRGB(240, 200, 60) },
	Diamond = { Name = "Diamond", Stack = 99, Color = Color3.fromRGB(90, 220, 235) },

	-- Placeable blocks (Block.Id is what gets saved in the world, never change an id)
	Dirt = { Name = "Dirt", Stack = 99, Color = Color3.fromRGB(110, 78, 50),
		Block = { Id = 1, Material = M.Ground, Color = Color3.fromRGB(110, 78, 50) } },
	Stone = { Name = "Stone", Stack = 99, Color = Color3.fromRGB(125, 125, 130),
		Block = { Id = 2, Material = M.Slate, Color = Color3.fromRGB(125, 125, 130) } },
	Sand = { Name = "Sand", Stack = 99, Color = Color3.fromRGB(222, 205, 150),
		Block = { Id = 3, Material = M.Sand, Color = Color3.fromRGB(222, 205, 150) } },
	Cobblestone = { Name = "Cobblestone", Stack = 99, Color = Color3.fromRGB(110, 110, 112),
		Block = { Id = 4, Material = M.Cobblestone, Color = Color3.fromRGB(110, 110, 112) } },
	Planks = { Name = "Planks", Stack = 99, Color = Color3.fromRGB(190, 150, 95),
		Block = { Id = 5, Material = M.WoodPlanks, Color = Color3.fromRGB(190, 150, 95) } },
	Glass = { Name = "Glass", Stack = 99, Color = Color3.fromRGB(190, 230, 240),
		Block = { Id = 6, Material = M.Glass, Color = Color3.fromRGB(190, 230, 240), Transparency = 0.5 } },
	Snow = { Name = "Snow", Stack = 99, Color = Color3.fromRGB(240, 245, 250),
		Block = { Id = 7, Material = M.Snow, Color = Color3.fromRGB(240, 245, 250) } },

	-- Tools
	WoodPickaxe = { Name = "Wood Pickaxe", Stack = 1, Color = Color3.fromRGB(150, 110, 70), Tool = { Type = "Pickaxe", Tier = 1 } },
	StonePickaxe = { Name = "Stone Pickaxe", Stack = 1, Color = Color3.fromRGB(130, 130, 130), Tool = { Type = "Pickaxe", Tier = 2 } },
	IronPickaxe = { Name = "Iron Pickaxe", Stack = 1, Color = Color3.fromRGB(210, 190, 180), Tool = { Type = "Pickaxe", Tier = 3 } },
	DiamondPickaxe = { Name = "Diamond Pickaxe", Stack = 1, Color = Color3.fromRGB(90, 220, 235), Tool = { Type = "Pickaxe", Tier = 4 } },
	WoodAxe = { Name = "Wood Axe", Stack = 1, Color = Color3.fromRGB(150, 110, 70), Tool = { Type = "Axe", Tier = 1 } },
	StoneAxe = { Name = "Stone Axe", Stack = 1, Color = Color3.fromRGB(130, 130, 130), Tool = { Type = "Axe", Tier = 2 } },
	IronAxe = { Name = "Iron Axe", Stack = 1, Color = Color3.fromRGB(210, 190, 180), Tool = { Type = "Axe", Tier = 3 } },
	WoodShovel = { Name = "Wood Shovel", Stack = 1, Color = Color3.fromRGB(150, 110, 70), Tool = { Type = "Shovel", Tier = 1 } },
	StoneShovel = { Name = "Stone Shovel", Stack = 1, Color = Color3.fromRGB(130, 130, 130), Tool = { Type = "Shovel", Tier = 2 } },
	IronShovel = { Name = "Iron Shovel", Stack = 1, Color = Color3.fromRGB(210, 190, 180), Tool = { Type = "Shovel", Tier = 3 } },
}

-- Reverse lookup: block id -> item id
Items.BlockById = {}
for itemId, def in Items.Defs do
	if def.Block then
		Items.BlockById[def.Block.Id] = itemId
	end
end

--[[
	Mining terrain. Keyed by Enum.Material.Name.
	  Item     what you get      HP    swings-worth of damage to break
	  Tool     best tool type (wrong tool = bare-hand power)
	  Tier     minimum tool tier required (0 = hands are fine)
	  Min/Max  drop amount
	Ores are normal Roblox terrain materials that the generator veins into deep rock.
	Change which material is which ore in TerrainGenerator (Config.Ores) and here.
]]
Items.TerrainMats = {
	Grass = { Item = "Dirt", HP = 3, Tool = "Shovel", Tier = 0, Min = 1, Max = 1 },
	LeafyGrass = { Item = "Dirt", HP = 3, Tool = "Shovel", Tier = 0, Min = 1, Max = 1 },
	Ground = { Item = "Dirt", HP = 3, Tool = "Shovel", Tier = 0, Min = 1, Max = 1 },
	Mud = { Item = "Dirt", HP = 3, Tool = "Shovel", Tier = 0, Min = 1, Max = 1 },
	Sand = { Item = "Sand", HP = 3, Tool = "Shovel", Tier = 0, Min = 1, Max = 1 },
	Snow = { Item = "Snow", HP = 2, Tool = "Shovel", Tier = 0, Min = 1, Max = 1 },
	Sandstone = { Item = "Sand", HP = 6, Tool = "Pickaxe", Tier = 0, Min = 1, Max = 2 },
	Rock = { Item = "Stone", HP = 8, Tool = "Pickaxe", Tier = 1, Min = 1, Max = 1 },
	Slate = { Item = "Stone", HP = 12, Tool = "Pickaxe", Tier = 1, Min = 1, Max = 1 },
	Asphalt = { Item = "Coal", HP = 10, Tool = "Pickaxe", Tier = 1, Min = 1, Max = 2 }, -- coal ore
	Limestone = { Item = "IronOre", HP = 14, Tool = "Pickaxe", Tier = 2, Min = 1, Max = 1 }, -- iron ore
	Salt = { Item = "GoldOre", HP = 16, Tool = "Pickaxe", Tier = 3, Min = 1, Max = 1 }, -- gold ore
	Glacier = { Item = "Diamond", HP = 20, Tool = "Pickaxe", Tier = 3, Min = 1, Max = 1 }, -- diamond ore
	-- Basalt (the world floor) is intentionally missing: it can't be mined.
}

-- World decorations (trees, rocks...) from the Decorator. Keyed by DecoType attribute.
Items.Gather = {
	Tree = { HP = 6, Tool = "Axe", Drops = { { "Wood", 3, 5 }, { "Stick", 0, 2 } } },
	Pine = { HP = 6, Tool = "Axe", Drops = { { "Wood", 3, 5 }, { "Stick", 0, 2 } } },
	JungleTree = { HP = 9, Tool = "Axe", Drops = { { "Wood", 5, 8 }, { "Stick", 1, 3 } } },
	Bush = { HP = 1, Tool = "Axe", Drops = { { "Fiber", 1, 3 }, { "Stick", 0, 1 } } },
	Rock = { HP = 5, Tool = "Pickaxe", Drops = { { "Stone", 2, 4 } } },
	Cactus = { HP = 3, Tool = "Axe", Drops = { { "Cactus", 1, 3 } } },
}

-- Damage of one swing for a given held item against a wanted tool type
function Items.SwingPower(heldId: string?, wantedTool: string): (number, number)
	local def = heldId and Items.Defs[heldId]
	local tool = def and def.Tool
	if tool and tool.Type == wantedTool then
		return Items.TierPower[tool.Tier + 1], tool.Tier
	end
	return Items.TierPower[1], 0
end

return Items
