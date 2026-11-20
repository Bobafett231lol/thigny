--[[
	Crafting recipes (hand crafting, no table required). Out = {itemId, count}.
	There is no smelting step: iron/gold/diamond tools are crafted straight from ore.
]]

return {
	{ Id = "Planks", Out = { "Planks", 4 }, In = { { "Wood", 1 } } },
	{ Id = "Stick", Out = { "Stick", 4 }, In = { { "Planks", 2 } } },
	{ Id = "Cobblestone", Out = { "Cobblestone", 2 }, In = { { "Stone", 2 } } },
	{ Id = "Glass", Out = { "Glass", 1 }, In = { { "Sand", 2 } } },

	{ Id = "WoodPickaxe", Out = { "WoodPickaxe", 1 }, In = { { "Planks", 3 }, { "Stick", 2 } } },
	{ Id = "WoodAxe", Out = { "WoodAxe", 1 }, In = { { "Planks", 3 }, { "Stick", 2 } } },
	{ Id = "WoodShovel", Out = { "WoodShovel", 1 }, In = { { "Planks", 1 }, { "Stick", 2 } } },

	{ Id = "StonePickaxe", Out = { "StonePickaxe", 1 }, In = { { "Stone", 3 }, { "Stick", 2 } } },
	{ Id = "StoneAxe", Out = { "StoneAxe", 1 }, In = { { "Stone", 3 }, { "Stick", 2 } } },
	{ Id = "StoneShovel", Out = { "StoneShovel", 1 }, In = { { "Stone", 1 }, { "Stick", 2 } } },

	{ Id = "IronPickaxe", Out = { "IronPickaxe", 1 }, In = { { "IronOre", 3 }, { "Stick", 2 } } },
	{ Id = "IronAxe", Out = { "IronAxe", 1 }, In = { { "IronOre", 3 }, { "Stick", 2 } } },
	{ Id = "IronShovel", Out = { "IronShovel", 1 }, In = { { "IronOre", 1 }, { "Stick", 2 } } },

	{ Id = "DiamondPickaxe", Out = { "DiamondPickaxe", 1 }, In = { { "Diamond", 3 }, { "Stick", 2 } } },
}
