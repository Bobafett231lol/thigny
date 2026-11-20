--[[
	WorldFramework - procedurally generated, DataStore-persisted terrain worlds.

	local World = require(game.ServerStorage.WorldFramework)
	local world = World.new({ WorldId = "Main", ViewDistance = 5 })
	world:Load()   -- reads/creates save (seed + meta)
	world:Start()  -- streaming + autosave + BindToClose save

	See README.md for the full API.
]]

local RunService = game:GetService("RunService")

local Config = require(script.Config)
local DefaultBiomes = require(script.Biomes)
local Generator = require(script.TerrainGenerator)
local Decorator = require(script.Decorator)
local ChunkManager = require(script.ChunkManager)
local WorldStore = require(script.WorldStore)

local VS = 4

local function merge(base, over)
	local out = {}
	for k, v in base do
		out[k] = if type(v) == "table" then merge(v, {}) else v
	end
	for k, v in over do
		if type(v) == "table" and type(out[k]) == "table" then
			out[k] = merge(out[k], v)
		else
			out[k] = v
		end
	end
	return out
end

local function round2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local World = {}
World.__index = World

function World.new(overrides: { [string]: any }?)
	overrides = overrides or {}
	local biomes = overrides.Biomes or DefaultBiomes
	local cfgOverrides = table.clone(overrides)
	cfgOverrides.Biomes = nil

	local self = setmetatable({}, World)
	self.Config = merge(Config, cfgOverrides)
	self.BiomeList = biomes
	self.Store = WorldStore.new(self.Config)
	self.Loaded = false
	self.BlockParts = {} -- "gx,gy,gz" -> Part for blocks in loaded chunks
	self.BlockBuilder = nil
	self._running = false
	self._warnedEditCap = false
	return self
end

-- Loads the save (or creates a new world). Yields. Must be called before anything else.
function World:Load()
	local cfg = self.Config
	local ok, meta = self.Store:LoadMeta()
	if not ok and not cfg.AllowUnsavedOnLoadFailure then
		error("[World] Could not read the saved world; refusing to start so the save isn't overwritten.")
	end

	if meta then
		if cfg.Seed and cfg.Seed ~= meta.Seed then
			warn("[World] Config.Seed ignored: this save already has seed " .. tostring(meta.Seed))
		end
		cfg.Seed, cfg.ChunkSize, cfg.ChunkHeight, cfg.SeaLevel = meta.Seed, meta.ChunkSize, meta.ChunkHeight, meta.SeaLevel
		if meta.GeneratorVersion ~= cfg.GeneratorVersion then
			warn(("[World] Save was created with GeneratorVersion %s, current is %s. Terrain may differ from when it was saved.")
				:format(tostring(meta.GeneratorVersion), tostring(cfg.GeneratorVersion)))
		end
		meta.Custom = meta.Custom or {}
		self.Meta = meta
	else
		cfg.Seed = cfg.Seed or Random.new():NextInteger(1, 2147483646)
		self.Meta = {
			Seed = cfg.Seed,
			ChunkSize = cfg.ChunkSize,
			ChunkHeight = cfg.ChunkHeight,
			SeaLevel = cfg.SeaLevel,
			GeneratorVersion = cfg.GeneratorVersion,
			Created = os.time(),
			Custom = {},
		}
		self.Store:PutMeta(self.Meta)
	end

	self.Generator = Generator.new(cfg, self.BiomeList)
	self.Decorator = Decorator.new(cfg, self.Generator)
	self.Chunks = ChunkManager.new(self)
	self.ChunkLoaded = self.Chunks.ChunkLoaded
	self.ChunkUnloaded = self.Chunks.ChunkUnloaded
	self.Loaded = true
	return self
end

function World:Start()
	assert(self.Loaded, "Call world:Load() first")
	if self._running then
		return
	end
	self._running = true
	self.Chunks:Start()

	task.spawn(function()
		while self._running do
			task.wait(self.Config.AutosaveInterval)
			if self._running then
				self:Save()
			end
		end
	end)

	game:BindToClose(function()
		if self._running then
			self:Save()
		end
	end)
end

function World:Stop()
	self._running = false
	self.Chunks:Stop()
end

-- Flushes dirty chunks + meta to the DataStore. Yields. Returns true on success.
function World:Save(): boolean
	self.Meta.LastSaved = os.time()
	self.Store:MarkMetaDirty()
	return self.Store:Flush()
end

function World:Destroy()
	self:Stop()
	self:Save()
	self.Chunks:Destroy()
end

-- ===== Queries =====

function World:WorldToChunk(position: Vector3): (number, number)
	local size = self.Config.ChunkSize * VS
	return math.floor(position.X / size), math.floor(position.Z / size)
end

-- Procedural (pre-edit) terrain height in studs at x,z
function World:GetGeneratedHeight(x: number, z: number): number
	return (self.Generator:SampleColumn(x, z))
end

-- Returns biomeName, { Temperature, Moisture, Height }
function World:GetBiomeAt(position: Vector3)
	local h, biome, t, m = self.Generator:SampleColumn(position.X, position.Z)
	return biome.Name, { Temperature = t, Moisture = m, Height = h }
end

-- Spiral-searches for dry land near x,z. Returns Vector3 on the generated surface.
function World:FindLandNear(x: number, z: number, minAboveSea: number?): Vector3
	local above = minAboveSea or 6
	local sea = self.Config.SeaLevel
	local step = 64
	for ring = 0, 80 do
		for dx = -ring, ring do
			for dz = -ring, ring do
				if math.max(math.abs(dx), math.abs(dz)) == ring then
					local px, pz = x + dx * step, z + dz * step
					local h = self.Generator:SampleColumn(px, pz)
					if h > sea + above then
						return Vector3.new(px, h, pz)
					end
				end
			end
		end
	end
	return Vector3.new(x, sea + above, z)
end

function World:PreloadAround(position: Vector3, radiusChunks: number?)
	self.Chunks:PreloadAround(position, radiusChunks or 2)
end

-- ===== Editing (persisted) =====

-- Carve (material = Air / nil) or fill a sphere of terrain. Saved and replayed on chunk load.
function World:ModifyTerrain(position: Vector3, radius: number, material: Enum.Material?)
	material = material or Enum.Material.Air
	local size = self.Config.ChunkSize * VS
	local minCx = math.floor((position.X - radius) / size)
	local maxCx = math.floor((position.X + radius) / size)
	local minCz = math.floor((position.Z - radius) / size)
	local maxCz = math.floor((position.Z + radius) / size)

	for cx = minCx, maxCx do
		for cz = minCz, maxCz do
			local data = self.Store:GetChunk(cx, cz) -- may yield if the record must be fetched
			local edits = data.Edits
			edits[#edits + 1] = {
				round2(position.X), round2(position.Y), round2(position.Z), round2(radius), material.Value,
			}
			if #edits > self.Config.MaxEditsPerChunk then
				table.remove(edits, 1)
				if not self._warnedEditCap then
					self._warnedEditCap = true
					warn("[World] MaxEditsPerChunk exceeded; oldest edits are being dropped.")
				end
			end
			self.Store:MarkDirty(cx, cz)
		end
	end

	workspace.Terrain:FillBall(position, radius, material)
end

-- Destroy a decoration (tree, rock...) and remember it's gone. Accepts the model or any descendant.
function World:RemoveDecoration(instance: Instance)
	local model = instance
	while model and model:GetAttribute("DecoId") == nil do
		model = model.Parent
	end
	if not model then
		return false
	end
	local data = self.Store:GetChunk(model:GetAttribute("ChunkX"), model:GetAttribute("ChunkZ"))
	data.Removed[model:GetAttribute("DecoId")] = true
	self.Store:MarkDirty(model:GetAttribute("ChunkX"), model:GetAttribute("ChunkZ"))
	model:Destroy()
	return true
end

function World:RegisterDecoration(name: string, builder)
	self.Decorator:Register(name, builder)
end

-- ===== Player-placed blocks: grid-aligned 4-stud cubes, saved per chunk =====
-- Cell (gx, gy, gz) is the cube from (gx*4, gy*4, gz*4) to +4 on each axis.

-- builder(blockId) -> BasePart. Style it (Material/Color/Transparency); size, position and anchoring are set for you.
function World:SetBlockBuilder(builder)
	self.BlockBuilder = builder
end

local function blockKey(gx: number, gy: number, gz: number): string
	return string.format("%d,%d,%d", gx, gy, gz)
end

function World:_spawnBlock(folder: Instance, gx: number, gy: number, gz: number, id: number)
	local part = if self.BlockBuilder then self.BlockBuilder(id) else nil
	if not part then
		part = Instance.new("Part")
		part.Color = Color3.fromRGB(160, 160, 160)
	end
	part.Name = "Block"
	part.Size = Vector3.one * VS
	part.CFrame = CFrame.new((gx + 0.5) * VS, (gy + 0.5) * VS, (gz + 0.5) * VS)
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("BlockX", gx)
	part:SetAttribute("BlockY", gy)
	part:SetAttribute("BlockZ", gz)
	part:SetAttribute("BlockId", id)

	local key = blockKey(gx, gy, gz)
	self.BlockParts[key] = part
	part.Destroying:Connect(function()
		if self.BlockParts[key] == part then
			self.BlockParts[key] = nil
		end
	end)
	part.Parent = folder
	return part
end

function World:_populateBlocks(folder: Instance, blocks: { [string]: number })
	for key, id in blocks do
		local gx, gy, gz = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
		if gx then
			self:_spawnBlock(folder, tonumber(gx), tonumber(gy), tonumber(gz), id)
		end
	end
end

-- Returns the block id at a cell, or nil. May yield if the chunk's record must be fetched.
function World:GetBlock(gx: number, gy: number, gz: number): number?
	local cs = self.Config.ChunkSize
	local data = self.Store:GetChunk(math.floor(gx / cs), math.floor(gz / cs))
	return data.Blocks[blockKey(gx, gy, gz)]
end

-- Returns ok, errorMessage. Saved and re-created whenever the chunk loads.
function World:PlaceBlock(gx: number, gy: number, gz: number, id: number): (boolean, string?)
	if gy < 0 or gy >= self.Config.ChunkHeight then
		return false, "Can't build there"
	end
	local cs = self.Config.ChunkSize
	local cx, cz = math.floor(gx / cs), math.floor(gz / cs)
	local data = self.Store:GetChunk(cx, cz) -- may yield; everything below must not
	local key = blockKey(gx, gy, gz)
	if data.Blocks[key] then
		return false, "Space is taken"
	end
	if data.BlockCount >= (self.Config.MaxBlocksPerChunk or 6000) then
		return false, "Too many blocks in this area"
	end
	data.Blocks[key] = id
	data.BlockCount += 1
	self.Store:MarkDirty(cx, cz)

	local info = self.Chunks.Loaded[string.format("%d,%d", cx, cz)]
	if info then
		self:_spawnBlock(info.folder, gx, gy, gz, id)
	end
	return true
end

-- Returns the removed block's id, or nil if there was none.
function World:RemoveBlock(gx: number, gy: number, gz: number): number?
	local cs = self.Config.ChunkSize
	local cx, cz = math.floor(gx / cs), math.floor(gz / cs)
	local data = self.Store:GetChunk(cx, cz)
	local key = blockKey(gx, gy, gz)
	local id = data.Blocks[key]
	if not id then
		return nil
	end
	data.Blocks[key] = nil
	data.BlockCount -= 1
	self.Store:MarkDirty(cx, cz)

	local part = self.BlockParts[key]
	if part then
		part:Destroy()
	end
	return id
end

-- ===== Custom saved data (spawn point, time of day, quest flags...). JSON-safe values only. =====

function World:SetMeta(key: string, value: any)
	self.Meta.Custom[key] = value
	self.Store:MarkMetaDirty()
end

function World:GetMeta(key: string): any
	return self.Meta.Custom[key]
end

function World:GetSeed(): number
	return self.Config.Seed
end

return World
