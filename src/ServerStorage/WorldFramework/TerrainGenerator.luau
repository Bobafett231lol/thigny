--[[
	Pure, deterministic terrain generation. Given (seed, config, biomes) the same chunk
	always produces the same voxels, so only player EDITS need to be saved.
]]

local Noise = require(script.Parent.Noise)

local AIR, WATER, SAND = Enum.Material.Air, Enum.Material.Water, Enum.Material.Sand
local VS = 4 -- Roblox terrain voxel size (fixed)

local MATERIAL_BY_VALUE = {}
for _, item in Enum.Material:GetEnumItems() do
	MATERIAL_BY_VALUE[item.Value] = item
end

local BIOME_DEFAULTS = {
	Base = 70,
	Amplitude = 10,
	Ridged = 0,
	Surface = Enum.Material.Grass,
	Subsurface = Enum.Material.Ground,
	Deep = Enum.Material.Slate,
	SubsurfaceDepth = 2,
	Underwater = Enum.Material.Sand,
	DecorationChance = 0,
}

local function normalizeBiomes(list)
	local out = {}
	for _, b in list do
		local nb = {}
		for k, v in BIOME_DEFAULTS do
			nb[k] = v
		end
		for k, v in b do
			nb[k] = v
		end
		nb.Decorations = nb.Decorations or {}
		out[#out + 1] = nb
	end
	assert(#out > 0, "[World] At least one biome is required")
	return out
end

local Generator = {}
Generator.__index = Generator

function Generator.new(config, biomeList)
	local seed = assert(config.Seed, "Config.Seed must be set before creating the generator")
	local self = setmetatable({}, Generator)
	self.Config = config
	self.Biomes = normalizeBiomes(biomeList)
	self._ds = table.create(#self.Biomes, 0)
	self.height = Noise.new(seed, "height")
	self.ridge = Noise.new(seed, "ridge")
	self.temp = Noise.new(seed, "temperature")
	self.moist = Noise.new(seed, "moisture")
	self.cont = Noise.new(seed, "continent")
	self.cave1 = Noise.new(seed, "cave1")
	self.cave2 = Noise.new(seed, "cave2")
	return self
end

-- Returns: surfaceHeightStuds, dominantBiome, temperature(0..1), moisture(0..1)
function Generator:SampleColumn(wx: number, wz: number)
	local c = self.Config
	local t = Noise.contrast01(self.temp:fbm2(wx, wz, 3, c.TemperatureFrequency), c.ClimateContrast)
	local m = Noise.contrast01(self.moist:fbm2(wx, wz, 3, c.MoistureFrequency), c.ClimateContrast)
	local cont = Noise.contrast01(self.cont:fbm2(wx, wz, 3, c.ContinentFrequency), c.ContinentContrast)

	local hn = math.clamp(self.height:fbm2(wx, wz, c.HeightOctaves, c.HeightFrequency) * c.HeightContrast, -1, 1)
	local rn = self.ridge:ridged2(wx, wz, 4, c.RidgeFrequency) * 2 - 1

	-- Find the closest biome in climate space, then blend heights of all by distance
	local biomes, ds = self.Biomes, self._ds
	local dmin, best = math.huge, biomes[1]
	for i, b in biomes do
		local dt, dm = t - b.Temperature, m - b.Moisture
		local d = dt * dt + dm * dm
		ds[i] = d
		if d < dmin then
			dmin, best = d, b
		end
	end

	local sum, h = 0, 0
	local sharp = c.BiomeBlendSharpness
	for i, b in biomes do
		local w = math.exp(-(ds[i] - dmin) * sharp)
		local n = hn + (rn - hn) * b.Ridged
		h += w * (b.Base + b.Amplitude * n)
		sum += w
	end
	h /= sum

	-- Continents: blend toward an ocean floor where continentalness is low
	local land = Noise.smoothstep(c.ContinentThreshold[1], c.ContinentThreshold[2], cont)
	local ocean = c.OceanFloor + hn * c.OceanVariation
	h = ocean + (h - ocean) * land

	h = math.clamp(h, 6, c.ChunkHeight * VS - 8)
	return h, best, t, m
end

local function applyEdit(self, mats, occs, ox, oz, e)
	local cs, ch = self.Config.ChunkSize, self.Config.ChunkHeight
	local ex, ey, ez, r, mv = e[1], e[2], e[3], e[4], e[5]
	local mat = MATERIAL_BY_VALUE[mv] or AIR

	local x0 = math.max(1, math.floor((ex - r - ox) / VS) + 1)
	local x1 = math.min(cs, math.floor((ex + r - ox) / VS) + 1)
	local y0 = math.max(1, math.floor((ey - r) / VS) + 1)
	local y1 = math.min(ch, math.floor((ey + r) / VS) + 1)
	local z0 = math.max(1, math.floor((ez - r - oz) / VS) + 1)
	local z1 = math.min(cs, math.floor((ez + r - oz) / VS) + 1)

	for x = x0, x1 do
		local dx = ox + (x - 0.5) * VS - ex
		for y = y0, y1 do
			local dy = (y - 0.5) * VS - ey
			for z = z0, z1 do
				local dz = oz + (z - 0.5) * VS - ez
				local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
				local cover = math.clamp((r - dist) / VS + 0.5, 0, 1)
				if cover > 0 then
					local cur = occs[x][y][z]
					if mat == AIR then
						local newOcc = cur * (1 - cover)
						if newOcc < 0.05 then
							occs[x][y][z] = 0
							mats[x][y][z] = AIR
						else
							occs[x][y][z] = newOcc
						end
					else
						if cover > cur then
							occs[x][y][z] = cover
						end
						if cover >= 0.5 or cur == 0 then
							mats[x][y][z] = mat
						end
					end
				end
			end
		end
	end
end

-- Builds voxel arrays for one chunk (no side effects). edits: array of {x,y,z,r,matValue}
function Generator:BuildChunk(cx: number, cz: number, edits: { any }?)
	local c = self.Config
	local cs, ch = c.ChunkSize, c.ChunkHeight
	local ox, oz = cx * cs * VS, cz * cs * VS
	local seaVoxel = math.floor(c.SeaLevel / VS)
	local caves = c.Caves
	local cavesOn = caves and caves.Enabled

	local mats, occs = table.create(cs), table.create(cs)
	for x = 1, cs do
		local mx, qx = table.create(ch), table.create(ch)
		for y = 1, ch do
			mx[y] = table.create(cs, AIR)
			qx[y] = table.create(cs, 0)
		end
		mats[x], occs[x] = mx, qx
	end

	for x = 1, cs do
		local wx = ox + (x - 0.5) * VS
		local matsX, occsX = mats[x], occs[x]
		for z = 1, cs do
			local wz = oz + (z - 0.5) * VS
			local h, biome = self:SampleColumn(wx, wz)

			local surfaceY = math.floor(h / VS) + 1
			local frac = (h - (surfaceY - 1) * VS) / VS

			local top, sub, subDepth
			if h < c.SeaLevel - 1 then
				top, sub, subDepth = biome.Underwater, biome.Underwater, 2
			elseif h < c.SeaLevel + c.BeachHeight and not biome.NoBeach then
				top, sub, subDepth = SAND, SAND, 2
			else
				top, sub, subDepth = biome.Surface, biome.Subsurface, biome.SubsurfaceDepth
				if biome.PeakMaterial and h > biome.PeakHeight then
					top = biome.PeakMaterial
				end
			end
			local deep = biome.Deep

			for y = 1, math.min(surfaceY, ch) do
				local yy = (y - 0.5) * VS
				local carved = false
				if cavesOn and y > 1 and yy > caves.MinY and (h - yy) > caves.SurfaceMargin then
					if math.abs(self.cave1:fbm3(wx, yy, wz, 2, caves.Frequency)) < caves.Width then
						carved = math.abs(self.cave2:fbm3(wx, yy, wz, 2, caves.Frequency)) < caves.Width
					end
				end
				if not carved then
					local depth = surfaceY - y
					local m
					if y == 1 then
						m = c.BottomMaterial
					elseif depth == 0 then
						m = top
					elseif depth <= subDepth then
						m = sub
					else
						m = deep
					end
					local occ = if depth == 0 then frac else 1
					if occ >= 0.08 then
						matsX[y][z] = m
						occsX[y][z] = occ
					end
				end
			end

			-- Ocean / lake water
			local waterStart = if frac >= 0.08 then surfaceY + 1 else surfaceY
			for y = waterStart, math.min(seaVoxel, ch) do
				matsX[y][z] = WATER
				occsX[y][z] = 1
			end
		end
	end

	if edits then
		for _, e in edits do
			applyEdit(self, mats, occs, ox, oz, e)
		end
	end

	local min = Vector3.new(ox, 0, oz)
	local region = Region3.new(min, min + Vector3.new(cs * VS, ch * VS, cs * VS))
	return region, mats, occs
end

function Generator:GenerateChunk(cx: number, cz: number, edits: { any }?)
	local region, mats, occs = self:BuildChunk(cx, cz, edits)
	workspace.Terrain:WriteVoxels(region, VS, mats, occs)
end

function Generator:ClearChunk(cx: number, cz: number)
	local cs, ch = self.Config.ChunkSize * VS, self.Config.ChunkHeight * VS
	local size = Vector3.new(cs, ch, cs)
	local center = Vector3.new(cx * cs, 0, cz * cs) + size / 2
	workspace.Terrain:FillBlock(CFrame.new(center), size, AIR)
end

return Generator
