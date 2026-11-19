--[[
	Seeded noise layers on top of math.noise. Each layer gets its own offsets derived
	from (seed, layerName), so layers are uncorrelated but fully deterministic.
]]

local Noise = {}
Noise.__index = Noise

local function hashString(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

function Noise.new(seed: number, layer: string)
	local rng = Random.new((seed + hashString(layer)) % 2147483647)
	return setmetatable({
		ox = rng:NextNumber(-5000, 5000),
		oy = rng:NextNumber(-5000, 5000),
		oz = rng:NextNumber(-5000, 5000),
		s = rng:NextNumber(0.13, 0.87),
	}, Noise)
end

-- Fractal Brownian motion, returns roughly -1..1
function Noise:fbm2(x: number, z: number, octaves: number, frequency: number, lacunarity: number?, gain: number?)
	lacunarity = lacunarity or 2
	gain = gain or 0.5
	local sum, amp, norm, f = 0, 1, 0, frequency
	for i = 1, octaves do
		sum += math.noise(x * f + self.ox + i * 13.37, z * f + self.oz - i * 7.91, self.s) * amp
		norm += amp
		amp *= gain
		f *= lacunarity
	end
	return sum / norm
end

-- Ridged multifractal, returns 0..1 (1 along ridge lines)
function Noise:ridged2(x: number, z: number, octaves: number, frequency: number, lacunarity: number?, gain: number?)
	lacunarity = lacunarity or 2
	gain = gain or 0.5
	local sum, amp, norm, f = 0, 1, 0, frequency
	for i = 1, octaves do
		local n = math.noise(x * f + self.ox + i * 5.77, z * f + self.oz + i * 3.13, self.s)
		local r = math.max(0, 1 - math.abs(n * 2))
		sum += r * r * amp
		norm += amp
		amp *= gain
		f *= lacunarity
	end
	return sum / norm
end

function Noise:fbm3(x: number, y: number, z: number, octaves: number, frequency: number)
	local sum, amp, norm, f = 0, 1, 0, frequency
	for i = 1, octaves do
		sum += math.noise(x * f + self.ox + i * 11.7, y * f + self.oy - i * 5.3, z * f + self.oz + i * 3.1) * amp
		norm += amp
		amp *= 0.5
		f *= 2
	end
	return sum / norm
end

-- Static helpers
function Noise.contrast01(v: number, contrast: number): number
	return math.clamp(0.5 + v * 0.5 * contrast, 0, 1)
end

function Noise.smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

return Noise
