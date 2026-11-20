--[[
	Deterministic decoration (trees, rocks, ...) per chunk.

	- Each chunk uses an RNG seeded from (worldSeed, cx, cz); attempt index i is the
	  decoration's stable ID, so removals can be saved as a list of IDs.
	- Types resolve in this order: Model named <Type> in ServerStorage.WorldAssets,
	  then a built-in/registered builder function.
	- Register your own:  world:RegisterDecoration("Lamp", function(rng, scale) ... return Model end)
]]

local ServerStorage = game:GetService("ServerStorage")

local Decorator = {}
Decorator.__index = Decorator

local VS = 4

local function mk(parent, shape, size, cf, color, material, collide)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local CYL, BALL, BLOCK = Enum.PartType.Cylinder, Enum.PartType.Ball, Enum.PartType.Block

-- Upright cylinder with its base at baseY
local function cyl(parent, x, baseY, z, diameter, height, color, material, collide)
	return mk(
		parent, CYL, Vector3.new(height, diameter, diameter),
		CFrame.new(x, baseY + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
		color, material, collide
	)
end

local function jitter(rng, c: Color3, amt: number)
	local k = rng:NextNumber(-amt, amt)
	return Color3.new(math.clamp(c.R + k, 0, 1), math.clamp(c.G + k, 0, 1), math.clamp(c.B + k, 0, 1))
end

local function newModel()
	return Instance.new("Model")
end

local function finish(model)
	model.WorldPivot = CFrame.new()
	return model
end

local Builders = {}

function Builders.Tree(rng, s)
	local m = newModel()
	local h = rng:NextNumber(9, 14) * s
	cyl(m, 0, 0, 0, 1.8 * s, h, Color3.fromRGB(105, 74, 46), Enum.Material.Wood)
	local leaf = jitter(rng, Color3.fromRGB(70, 130, 55), 0.05)
	mk(m, BALL, Vector3.one * 10 * s, CFrame.new(0, h + 2 * s, 0), leaf, Enum.Material.Grass, false)
	mk(m, BALL, Vector3.one * 7 * s, CFrame.new(3 * s, h, 1.5 * s), leaf, Enum.Material.Grass, false)
	mk(m, BALL, Vector3.one * 7 * s, CFrame.new(-2.5 * s, h + 0.5 * s, -2 * s), leaf, Enum.Material.Grass, false)
	return finish(m)
end

function Builders.JungleTree(rng, s)
	local m = newModel()
	local h = rng:NextNumber(20, 30) * s
	cyl(m, 0, 0, 0, 2.6 * s, h, Color3.fromRGB(92, 66, 42), Enum.Material.Wood)
	local leaf = jitter(rng, Color3.fromRGB(40, 110, 40), 0.05)
	mk(m, BALL, Vector3.new(16, 7, 16) * s, CFrame.new(0, h + 2 * s, 0), leaf, Enum.Material.Grass, false)
	mk(m, BALL, Vector3.new(11, 5, 11) * s, CFrame.new(4 * s, h - 3 * s, 2 * s), leaf, Enum.Material.Grass, false)
	return finish(m)
end

function Builders.Pine(rng, s)
	local m = newModel()
	local h = rng:NextNumber(12, 18) * s
	cyl(m, 0, 0, 0, 1.6 * s, h * 0.8, Color3.fromRGB(88, 62, 40), Enum.Material.Wood)
	local leaf = jitter(rng, Color3.fromRGB(35, 88, 52), 0.04)
	local tiers = 4
	for i = 1, tiers do
		local d = (11 - i * 2.2) * s
		cyl(m, 0, h * 0.25 + (i - 1) * (h * 0.17), 0, d, 2.4 * s, leaf, Enum.Material.Grass, false)
	end
	return finish(m)
end

function Builders.Cactus(rng, s)
	local m = newModel()
	local h = rng:NextNumber(7, 12) * s
	local col = jitter(rng, Color3.fromRGB(80, 130, 70), 0.04)
	cyl(m, 0, 0, 0, 2.2 * s, h, col, Enum.Material.Grass)
	if rng:NextNumber() < 0.7 then
		local ah = h * 0.35
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		mk(m, BLOCK, Vector3.new(2.5 * s, 1.5 * s, 1.5 * s), CFrame.new(side * 2 * s, h * 0.45, 0), col, Enum.Material.Grass)
		cyl(m, side * 3.2 * s, h * 0.45, 0, 1.5 * s, ah, col, Enum.Material.Grass)
	end
	return finish(m)
end

function Builders.Rock(rng, s)
	local m = newModel()
	local w = rng:NextNumber(3, 6) * s
	local col = jitter(rng, Color3.fromRGB(125, 125, 125), 0.08)
	mk(
		m, BALL, Vector3.new(w, w * rng:NextNumber(0.55, 0.9), w * rng:NextNumber(0.8, 1.1)),
		CFrame.new(0, w * 0.2, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		col, Enum.Material.Slate
	)
	return finish(m)
end

function Builders.Bush(rng, s)
	local m = newModel()
	local w = rng:NextNumber(2.5, 4) * s
	mk(m, BALL, Vector3.new(w, w * 0.75, w), CFrame.new(0, w * 0.3, 0), jitter(rng, Color3.fromRGB(80, 140, 60), 0.06), Enum.Material.Grass, false)
	return finish(m)
end

function Decorator.new(config, generator)
	local self = setmetatable({}, Decorator)
	self.Config = config
	self.Generator = generator
	self.Builders = table.clone(Builders)
	self.RaycastParams = RaycastParams.new()
	self.RaycastParams.FilterType = Enum.RaycastFilterType.Include
	self.RaycastParams.FilterDescendantsInstances = { workspace.Terrain }
	return self
end

function Decorator:Register(name: string, builder)
	self.Builders[name] = builder
end

function Decorator:Build(typeName: string, rng: Random, scale: number)
	local assets = ServerStorage:FindFirstChild("WorldAssets")
	local template = assets and assets:FindFirstChild(typeName)
	if template and template:IsA("Model") then
		local clone = template:Clone()
		clone:ScaleTo(scale)
		return clone
	end
	local builder = self.Builders[typeName]
	if builder then
		return builder(rng, scale)
	end
	return nil
end

local function chunkSeed(seed, cx, cz)
	return bit32.bxor(seed % 4294967296, (cx * 73856093) % 4294967296, (cz * 19349663) % 4294967296)
end

local function pickWeighted(entries, r01)
	local total = 0
	for _, e in entries do
		total += e.Weight or 1
	end
	if total <= 0 then
		return nil
	end
	local r = r01 * total
	for _, e in entries do
		r -= e.Weight or 1
		if r <= 0 then
			return e
		end
	end
	return entries[#entries]
end

-- removed: set of decoration IDs the players have destroyed in this chunk
function Decorator:PopulateChunk(cx: number, cz: number, parent: Instance, removed: { [number]: boolean })
	local c = self.Config
	local cs = c.ChunkSize * VS
	local ox, oz = cx * cs, cz * cs
	local rng = Random.new(chunkSeed(c.Seed, cx, cz))
	local skyY = c.ChunkHeight * VS + 50

	for i = 1, c.Decorations.AttemptsPerChunk do
		-- Always draw the same numbers per attempt so IDs stay stable
		local rx, rz, roll, pick, sc, yaw = rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber()
		local bseed = rng:NextInteger(1, 1000000000)

		if removed[i] then
			continue
		end

		local wx, wz = ox + rx * cs, oz + rz * cs
		local h, biome = self.Generator:SampleColumn(wx, wz)
		if h <= c.SeaLevel + 1 or roll > biome.DecorationChance then
			continue
		end

		local entry = pickWeighted(biome.Decorations, pick)
		if not entry or entry.Type == "None" then
			continue
		end

		local hit = workspace:Raycast(Vector3.new(wx, skyY, wz), Vector3.new(0, -(skyY + 50), 0), self.RaycastParams)
		if not hit or hit.Material == Enum.Material.Water then
			continue
		end
		if hit.Normal.Y < (entry.MinNormalY or 0.8) then
			continue
		end

		local range = entry.Scale or { 0.8, 1.25 }
		local scale = range[1] + (range[2] - range[1]) * sc
		local model = self:Build(entry.Type, Random.new(bseed), scale)
		if model then
			model:SetAttribute("DecoId", i)
			model:SetAttribute("ChunkX", cx)
			model:SetAttribute("ChunkZ", cz)
			model:SetAttribute("DecoType", entry.Type)
			model.Name = entry.Type
			model.Parent = parent
			model:PivotTo(CFrame.new(hit.Position - Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, yaw * math.pi * 2, 0))
		end
	end
end

return Decorator
