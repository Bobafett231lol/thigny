--[[
	Default configuration. Override any field via World.new({ ... }).

	NOTE: Roblox terrain voxels are always 4 studs, so chunk sizes are in voxels:
	ChunkSize 16 = 64 studs wide, ChunkHeight 64 = 256 studs tall.

	World-defining values (Seed, ChunkSize, ChunkHeight, SeaLevel) are written into the
	save's meta record on creation and LOCKED to the saved values on later loads,
	because saved edits are keyed by chunk coordinates.
]]

return {
	WorldId = "World1", -- DataStore key prefix. One id = one save slot (e.g. "Player_" .. userId)
	Seed = nil, -- nil = random on first creation
	GeneratorVersion = 2, -- (2 = ore veins added) bump when you change generation in a way that should be flagged on old saves

	-- Layout (voxels of 4 studs)
	ChunkSize = 16,
	ChunkHeight = 64,
	SeaLevel = 64, -- studs

	-- Streaming
	ViewDistance = 5, -- chunks
	UnloadPadding = 1, -- extra chunks before unloading (prevents flicker)
	ChunksPerStep = 1, -- chunks generated per step (raise for faster, hitchier loading)
	UpdateInterval = 0.25,

	-- Noise (frequencies are per-stud)
	HeightFrequency = 1 / 260,
	HeightOctaves = 5,
	RidgeFrequency = 1 / 320,
	TemperatureFrequency = 1 / 1400,
	MoistureFrequency = 1 / 1100,
	ContinentFrequency = 1 / 2500,
	ClimateContrast = 2.4, -- stretches temp/moisture so all biomes actually appear
	HeightContrast = 1.8,
	ContinentContrast = 2.2,
	ContinentThreshold = { 0.34, 0.46 }, -- below first = deep ocean, above second = full land
	BiomeBlendSharpness = 30, -- higher = harder biome borders
	OceanFloor = 28, -- studs
	OceanVariation = 14,
	BeachHeight = 3, -- studs above sea level that turn to sand

	BottomMaterial = Enum.Material.Basalt,

	Caves = {
		Enabled = true,
		Frequency = 1 / 70,
		Width = 0.1, -- larger = fatter/more tunnels
		MinY = 12, -- studs
		SurfaceMargin = 8, -- studs of solid ground kept under the surface
	},

	-- Ore veins: normal terrain materials veined into deep rock (see Items.TerrainMats for what
	-- each one drops). MaxY = studs, only generates below this height. MinDepth = studs under the
	-- surface. Threshold: higher = rarer (noise is roughly -0.5..0.5). Tune these by eye.
	Ores = {
		Enabled = true,
		Frequency = 1 / 12, -- vein size (smaller number = bigger veins)
		Veins = {
			{ Name = "Coal", Material = Enum.Material.Asphalt, MaxY = 70, MinDepth = 6, Threshold = 0.26 },
			{ Name = "Iron", Material = Enum.Material.Limestone, MaxY = 50, MinDepth = 10, Threshold = 0.30 },
			{ Name = "Gold", Material = Enum.Material.Salt, MaxY = 32, MinDepth = 20, Threshold = 0.34 },
			{ Name = "Diamond", Material = Enum.Material.Glacier, MaxY = 20, MinDepth = 30, Threshold = 0.38 },
		},
	},

	Decorations = {
		Enabled = true,
		AttemptsPerChunk = 40,
	},

	-- Saving
	SavingEnabled = true,
	DataStoreName = "ProceduralWorlds_v1",
	AutosaveInterval = 60, -- seconds
	MaxBlocksPerChunk = 6000, -- player-placed blocks per chunk (each ~25 bytes in the save)
	MaxEditsPerChunk = 3000, -- mining adds one edit per broken cell; oldest are dropped past this
	AllowUnsavedOnLoadFailure = false, -- if the save can't be read, refuse to start (protects against overwriting)
}
