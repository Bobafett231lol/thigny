--[[
	Title-screen backdrop, all hard-edged pixel rectangles:
	banded sunset sky, twinkling stars, a setting sun, drifting clouds and three parallax hill
	layers (looping tiles). Everything moves in whole-pixel steps at low frame rates.
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Kit = require(ReplicatedFirst:WaitForChild("PixelKit"))
local C = Kit.C

local Scene = {}

local SKY = { C.ink, C.dusk, C.navy, C.plum, C.red, C.orange, C.yellow } -- top -> horizon

-- Wv x Hv = the screen measured in virtual pixels. Returns a destroy function.
function Scene.Build(parent: Instance, Wv: number, Hv: number)
	local stops = {}
	local u = Kit.U -- tickers keep using the scale this scene was built with
	local rng = Random.new(7) -- fixed, so the scene is always the same
	local root = Kit.group(parent, 0, 0, Wv, Hv)

	-- Sky bands
	local Hy = math.floor(Hv * 0.74)
	local bandH = math.ceil(Hy / #SKY)
	for i, col in SKY do
		Kit.rect(root, 0, (i - 1) * bandH, Wv, bandH + 1, col)
	end
	Kit.rect(root, 0, Hy, Wv, Hv - Hy, C.ink)

	-- Stars (upper three bands)
	local stars = {}
	for _ = 1, 38 do
		local s = Kit.rect(root, rng:NextInteger(1, math.floor(Wv) - 2), rng:NextInteger(1, bandH * 3 - 2), 1, 1, C.white)
		stars[#stars + 1] = s
	end
	table.insert(stops, Kit.every(3, function(n)
		for i, s in stars do
			local phase = (n + i * 5) % 6
			s.BackgroundColor3 = if phase == 0 then C.slate elseif phase < 3 then C.silver else C.white
			s.Visible = phase ~= 5
		end
	end))

	-- Setting sun: orange disc with a yellow core
	local sx, sy = math.floor(Wv * 0.7), Hy - 12
	for _, d in { { 15, C.orange }, { 12, C.yellow } } do
		for dy = -d[1], d[1] do
			local half = math.floor(math.sqrt(d[1] * d[1] - dy * dy))
			Kit.rect(root, sx - half, sy + dy, half * 2 + 1, 1, d[2])
		end
	end

	-- Clouds
	local clouds = {}
	for i = 1, 5 do
		local g = Kit.group(root, 0, 0, 16, 6)
		Kit.rect(g, 4, 0, 5, 2, C.white)
		Kit.rect(g, 1, 2, 11, 2, C.white)
		Kit.rect(g, 0, 4, 13, 1, C.silver)
		clouds[i] = { g = g, x = rng:NextInteger(0, math.floor(Wv)), y = rng:NextInteger(6, math.floor(Hy * 0.5)), speed = rng:NextInteger(1, 2) }
		g.Position = UDim2.fromOffset(clouds[i].x * u, clouds[i].y * u)
	end
	table.insert(stops, Kit.every(4, function()
		for _, c in clouds do
			c.x -= c.speed
			if c.x < -16 then
				c.x = Wv + 2
			end
			c.g.Position = UDim2.fromOffset(c.x * u, c.y * u)
		end
	end))

	-- Hills: periodic height profile, tiled and scrolled so the loop is seamless
	local function hillLayer(color, baseH, amp1, amp2, seed, trees, fps)
		local N, CW = 40, 4
		local tileW = N * CW
		local tiles = math.ceil(Wv / tileW) + 1
		local layer = Kit.group(root, 0, 0, tileW * tiles, Hv)
		local hs = {}
		for i = 0, N - 1 do
			local a = i / N * math.pi * 2
			hs[i] = math.floor(baseH + amp1 * math.sin(a * 2 + seed) + amp2 * math.sin(a * 5 + seed * 1.7) + 0.5)
		end
		for t = 0, tiles - 1 do
			local i = 0
			while i < N do
				local j = i
				while j + 1 < N and hs[j + 1] == hs[i] do
					j += 1
				end
				Kit.rect(layer, t * tileW + i * CW, Hv - hs[i], (j - i + 1) * CW, hs[i], color)
				i = j + 1
			end
			if trees then
				for i = 3, N - 5, 7 do
					local cx = t * tileW + i * CW + 1
					local top = Hv - hs[i]
					Kit.rect(layer, cx, top - 2, 1, 2, color)
					Kit.rect(layer, cx - 1, top - 5, 3, 3, color)
					Kit.rect(layer, cx - 2, top - 8, 5, 3, color)
					Kit.rect(layer, cx, top - 11, 1, 3, color)
				end
			end
		end
		local shift = 0
		table.insert(stops, Kit.every(fps, function()
			shift = (shift + 1) % tileW
			layer.Position = UDim2.fromOffset(-shift * u, 0)
		end))
	end

	local far = Hv - Hy + 8
	hillLayer(C.plum, far, 7, 3, 0.4, false, 2)
	hillLayer(C.dusk, far - 10, 6, 3, 2.1, false, 4)
	hillLayer(C.ink, far - 22, 5, 2, 4.0, true, 8)

	return function()
		for _, stop in stops do
			stop()
		end
		root:Destroy()
	end
end

return Scene
