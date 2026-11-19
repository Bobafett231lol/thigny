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
	GeneratorVersion = 1, -- bump when you change generation in a way that should be flagged on old saves

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

	Decorations = {
		Enabled = true,
		AttemptsPerChunk = 40,
	},

	-- Saving
	SavingEnabled = true,
	DataStoreName = "ProceduralWorlds_v1",
	AutosaveInterval = 60, -- seconds
	MaxEditsPerChunk = 500,
	AllowUnsavedOnLoadFailure = false, -- if the save can't be read, refuse to start (protects against overwriting)
}
