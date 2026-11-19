--[[
	Biome definitions. Add/remove/edit freely.

	Biomes are placed on a Temperature/Moisture plane (both 0..1). Each point of the world
	has a climate; nearby biomes are blended smoothly for height and the closest one wins
	for surface materials/decorations.

	Fields:
	  Name, Temperature, Moisture
	  Base, Amplitude      surface height in studs = Base + Amplitude * noise(-1..1)
	  Ridged               0..1 mix of ridged (mountain-like) noise into the height
	  Surface, Subsurface, Deep, SubsurfaceDepth (voxels), Underwater
	  PeakMaterial, PeakHeight   (optional) e.g. snow caps above a height in studs
	  NoBeach              (optional) skip sand near the coastline
	  DecorationChance     0..1 probability each decoration attempt does something
	  Decorations          { {Type=, Weight=, Scale={min,max}, MinNormalY=} ... }
	                       Type is a builder name (see Decorator.luau) or a Model in
	                       ServerStorage.WorldAssets with that name. "None" = nothing.
]]

local M = Enum.Material

return {
	{
		Name = "Plains",
		Temperature = 0.5, Moisture = 0.4,
		Base = 72, Amplitude = 26, Ridged = 0,
		Surface = M.Grass, Subsurface = M.Ground, Deep = M.Slate, SubsurfaceDepth = 3,
		Underwater = M.Sand,
		DecorationChance = 0.55,
		Decorations = {
			{ Type = "Tree", Weight = 1 },
			{ Type = "Bush", Weight = 3 },
			{ Type = "Rock", Weight = 1 },
			{ Type = "None", Weight = 6 },
		},
	},
	{
		Name = "Forest",
		Temperature = 0.45, Moisture = 0.75,
		Base = 76, Amplitude = 34, Ridged = 0.1,
		Surface = M.Grass, Subsurface = M.Ground, Deep = M.Slate, SubsurfaceDepth = 3,
		Underwater = M.Sand,
		DecorationChance = 0.9,
		Decorations = {
			{ Type = "Tree", Weight = 8, Scale = { 0.9, 1.5 } },
			{ Type = "Pine", Weight = 2 },
			{ Type = "Bush", Weight = 3 },
			{ Type = "Rock", Weight = 1 },
		},
	},
	{
		Name = "Taiga",
		Temperature = 0.25, Moisture = 0.65,
		Base = 80, Amplitude = 36, Ridged = 0.2,
		Surface = M.Grass, Subsurface = M.Ground, Deep = M.Slate, SubsurfaceDepth = 3,
		Underwater = M.Sand,
		DecorationChance = 0.85,
		Decorations = {
			{ Type = "Pine", Weight = 9, Scale = { 0.9, 1.6 } },
			{ Type = "Rock", Weight = 2 },
			{ Type = "None", Weight = 2 },
		},
	},
	{
		Name = "Tundra",
		Temperature = 0.1, Moisture = 0.3,
		Base = 84, Amplitude = 24, Ridged = 0.15,
		Surface = M.Snow, Subsurface = M.Ground, Deep = M.Slate, SubsurfaceDepth = 2,
		Underwater = M.Ground, NoBeach = true,
		DecorationChance = 0.25,
		Decorations = {
			{ Type = "Rock", Weight = 2 },
			{ Type = "Pine", Weight = 1 },
			{ Type = "None", Weight = 6 },
		},
	},
	{
		Name = "Desert",
		Temperature = 0.92, Moisture = 0.08,
		Base = 70, Amplitude = 40, Ridged = 0,
		Surface = M.Sand, Subsurface = M.Sandstone, Deep = M.Sandstone, SubsurfaceDepth = 5,
		Underwater = M.Sand,
		DecorationChance = 0.2,
		Decorations = {
			{ Type = "Cactus", Weight = 3 },
			{ Type = "Rock", Weight = 1 },
			{ Type = "None", Weight = 8 },
		},
	},
	{
		Name = "Savanna",
		Temperature = 0.8, Moisture = 0.35,
		Base = 72, Amplitude = 22, Ridged = 0,
		Surface = M.LeafyGrass, Subsurface = M.Ground, Deep = M.Sandstone, SubsurfaceDepth = 3,
		Underwater = M.Sand,
		DecorationChance = 0.3,
		Decorations = {
			{ Type = "Tree", Weight = 1, Scale = { 0.8, 1.2 } },
			{ Type = "Bush", Weight = 2 },
			{ Type = "None", Weight = 6 },
		},
	},
	{
		Name = "Jungle",
		Temperature = 0.85, Moisture = 0.92,
		Base = 74, Amplitude = 40, Ridged = 0.15,
		Surface = M.LeafyGrass, Subsurface = M.Mud, Deep = M.Slate, SubsurfaceDepth = 3,
		Underwater = M.Mud,
		DecorationChance = 0.95,
		Decorations = {
			{ Type = "JungleTree", Weight = 6 },
			{ Type = "Tree", Weight = 3 },
			{ Type = "Bush", Weight = 4 },
		},
	},
	{
		Name = "Swamp",
		Temperature = 0.6, Moisture = 0.97,
		Base = 62, Amplitude = 6, Ridged = 0,
		Surface = M.Mud, Subsurface = M.Mud, Deep = M.Ground, SubsurfaceDepth = 3,
		Underwater = M.Mud, NoBeach = true,
		DecorationChance = 0.4,
		Decorations = {
			{ Type = "Tree", Weight = 2 },
			{ Type = "Bush", Weight = 4 },
			{ Type = "None", Weight = 3 },
		},
	},
	{
		Name = "Mountains",
		Temperature = 0.3, Moisture = 0.15,
		Base = 105, Amplitude = 120, Ridged = 0.9,
		Surface = M.Rock, Subsurface = M.Rock, Deep = M.Slate, SubsurfaceDepth = 4,
		Underwater = M.Rock, NoBeach = true,
		PeakMaterial = M.Snow, PeakHeight = 175,
		DecorationChance = 0.15,
		Decorations = {
			{ Type = "Rock", Weight = 3, Scale = { 1, 2.5 } },
			{ Type = "Pine", Weight = 1 },
			{ Type = "None", Weight = 4 },
		},
	},
}
