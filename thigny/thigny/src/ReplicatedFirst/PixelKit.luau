--[[
	PixelKit: tiny 8-bit UI toolkit. Everything is drawn from flat, hard-edged rectangles on a
	320x180 "virtual pixel" grid, scaled by an integer unit (Kit.U real pixels per virtual pixel),
	so nothing is ever blurry. All x/y/w/h arguments below are in VIRTUAL pixels.

	Look rules: 16-colour palette, no gradients, no rounded corners (corners are notched by one
	pixel), hard drop shadows, a 5x7 bitmap font, and animation that moves in whole steps at a low
	frame rate (like old sprite animation) instead of smooth tweens.
]]

local RunService = game:GetService("RunService")

local Kit = {}
Kit.U = 4
Kit.ReducedMotion = false

-- Sweetie-16 style palette
local function hex(s) return Color3.fromHex(s) end
local C = {
	ink = hex("1a1c2c"), plum = hex("5d275d"), red = hex("b13e53"), orange = hex("ef7d57"),
	yellow = hex("ffcd75"), lime = hex("a7f070"), green = hex("38b764"), teal = hex("257179"),
	navy = hex("29366f"), blue = hex("3b5dc9"), sky = hex("41a6f6"), cyan = hex("73eff7"),
	white = hex("f4f4f4"), silver = hex("94b0c2"), slate = hex("566c86"), dusk = hex("333c57"),
	brown = hex("8b5a2b"),
}
Kit.C = C

-- The screen size, waiting (briefly) for the camera to exist and report a real size
function Kit.viewport(): Vector2
	local cam = workspace.CurrentCamera
	local started = os.clock()
	while (not cam or cam.ViewportSize.X < 200) and os.clock() - started < 5 do
		task.wait()
		cam = workspace.CurrentCamera
	end
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

-- Largest whole-number scale at which a 320x180 canvas fits the screen
function Kit.fitUnit(viewport: Vector2): number
	return math.max(2, math.floor(math.min(viewport.X / 320, viewport.Y / 180)))
end

-- ===== Primitives =====

local function rect(parent, x, y, w, h, color)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromOffset(math.floor(x * Kit.U), math.floor(y * Kit.U))
	f.Size = UDim2.fromOffset(math.floor(w * Kit.U), math.floor(h * Kit.U))
	f.Parent = parent
	return f
end
Kit.rect = rect

-- Invisible container
function Kit.group(parent, x, y, w, h)
	local f = rect(parent, x, y, w, h, C.ink)
	f.BackgroundTransparency = 1
	return f
end

-- Notched, bevelled box. style: fill, border, hi, lo. Returns { Root, Fill, Hi }.
function Kit.panel(parent, x, y, w, h, style)
	style = style or {}
	local root = Kit.group(parent, x, y, w, h)
	local border = style.border or C.ink
	local b1 = rect(root, 1, 0, w - 2, h, border)
	local b2 = rect(root, 0, 1, w, h - 2, border)
	local fill = rect(root, 1, 1, w - 2, h - 2, style.fill or C.navy)
	local hi, lo = style.hi or C.blue, style.lo or C.ink
	local hiA = rect(root, 2, 1, w - 4, 1, hi)
	local hiB = rect(root, 1, 2, 1, h - 4, hi)
	rect(root, 2, h - 2, w - 4, 1, lo)
	rect(root, w - 2, 2, 1, h - 4, lo)
	return { Root = root, Fill = fill, Hi = { hiA, hiB }, Border = { b1, b2 } }
end

-- ===== Bitmap font (5x7) =====

local RAW = {
	A = "01110/10001/10001/11111/10001/10001/10001", B = "11110/10001/10001/11110/10001/10001/11110",
	C = "01110/10001/10000/10000/10000/10001/01110", D = "11110/10001/10001/10001/10001/10001/11110",
	E = "11111/10000/10000/11110/10000/10000/11111", F = "11111/10000/10000/11110/10000/10000/10000",
	G = "01110/10001/10000/10111/10001/10001/01111", H = "10001/10001/10001/11111/10001/10001/10001",
	I = "01110/00100/00100/00100/00100/00100/01110", J = "00111/00010/00010/00010/00010/10010/01100",
	K = "10001/10010/10100/11000/10100/10010/10001", L = "10000/10000/10000/10000/10000/10000/11111",
	M = "10001/11011/10101/10101/10001/10001/10001", N = "10001/11001/10101/10011/10001/10001/10001",
	O = "01110/10001/10001/10001/10001/10001/01110", P = "11110/10001/10001/11110/10000/10000/10000",
	Q = "01110/10001/10001/10001/10101/10010/01101", R = "11110/10001/10001/11110/10100/10010/10001",
	S = "01111/10000/10000/01110/00001/00001/11110", T = "11111/00100/00100/00100/00100/00100/00100",
	U = "10001/10001/10001/10001/10001/10001/01110", V = "10001/10001/10001/10001/10001/01010/00100",
	W = "10001/10001/10001/10101/10101/10101/01010", X = "10001/10001/01010/00100/01010/10001/10001",
	Y = "10001/10001/01010/00100/00100/00100/00100", Z = "11111/00001/00010/00100/01000/10000/11111",
	["0"] = "01110/10001/10011/10101/11001/10001/01110", ["1"] = "00100/01100/00100/00100/00100/00100/01110",
	["2"] = "01110/10001/00001/00010/00100/01000/11111", ["3"] = "11110/00001/00001/01110/00001/00001/11110",
	["4"] = "00010/00110/01010/10010/11111/00010/00010", ["5"] = "11111/10000/11110/00001/00001/10001/01110",
	["6"] = "00110/01000/10000/11110/10001/10001/01110", ["7"] = "11111/00001/00010/00100/01000/01000/01000",
	["8"] = "01110/10001/10001/01110/10001/10001/01110", ["9"] = "01110/10001/10001/01111/00001/00010/01100",
	["."] = "00000/00000/00000/00000/00000/01100/01100", [","] = "00000/00000/00000/00000/01100/00100/01000",
	[":"] = "00000/01100/01100/00000/01100/01100/00000", ["!"] = "00100/00100/00100/00100/00100/00000/00100",
	["?"] = "01110/10001/00001/00110/00100/00000/00100", ["-"] = "00000/00000/00000/11111/00000/00000/00000",
	["+"] = "00000/00100/00100/11111/00100/00100/00000", ["/"] = "00001/00010/00010/00100/01000/01000/10000",
	["%"] = "11001/11010/00010/00100/01000/01011/10011", ["'"] = "00100/00100/01000/00000/00000/00000/00000",
	["("] = "00010/00100/01000/01000/01000/00100/00010", [")"] = "01000/00100/00010/00010/00010/00100/01000",
	["_"] = "00000/00000/00000/00000/00000/00000/11111", [">"] = "10000/01000/00100/00010/00100/01000/10000",
	["<"] = "00001/00010/00100/01000/00100/00010/00001", ["="] = "00000/00000/11111/00000/11111/00000/00000",
	[" "] = "00000/00000/00000/00000/00000/00000/00000",
}
local GLYPH = {}
for ch, s in RAW do
	GLYPH[ch] = string.split(s, "/")
end

function Kit.textWidth(str: string, scale: number?): number
	return if #str > 0 then (#str * 6 - 1) * (scale or 1) else 0
end

local function drawGlyphs(parent, str: string, scale: number, color: Color3, ox: number, oy: number)
	for i = 1, #str do
		local g = GLYPH[str:sub(i, i)] or GLYPH["?"]
		local gx = (i - 1) * 6 * scale
		for r = 1, 7 do
			local row, c = g[r], 1
			while c <= 5 do
				if row:sub(c, c) == "1" then
					local e = c
					while e < 5 and row:sub(e + 1, e + 1) == "1" do
						e += 1
					end
					rect(parent, ox + gx + (c - 1) * scale, oy + (r - 1) * scale, (e - c + 1) * scale, scale, color)
					c = e + 1
				else
					c += 1
				end
			end
		end
	end
end

local info = setmetatable({}, { __mode = "k" })

local function layoutText(group)
	local t = info[group]
	local w = Kit.textWidth(t.str, t.scale) + 1
	local x = t.x
	if t.align == "c" then
		x = math.floor(t.x - w / 2)
	elseif t.align == "r" then
		x = t.x - w
	end
	group.Position = UDim2.fromOffset(math.floor(x * Kit.U), math.floor(t.y * Kit.U))
	group.Size = UDim2.fromOffset(w * Kit.U, (7 * t.scale + 1) * Kit.U)
	group:ClearAllChildren()
	if t.shadow then
		drawGlyphs(group, t.str, t.scale, t.shadow, 1, 1)
	end
	drawGlyphs(group, t.str, t.scale, t.color, 0, 0)
end

-- opts: x, y, color, shadow (Color3 | false), scale, align ("l" | "c" | "r"). Text is upper-cased.
function Kit.text(parent, str: string, opts)
	opts = opts or {}
	local group = Kit.group(parent, 0, 0, 1, 1)
	info[group] = {
		str = str:upper(), x = opts.x or 0, y = opts.y or 0, color = opts.color or C.white,
		shadow = if opts.shadow == nil then C.ink else opts.shadow, scale = opts.scale or 1, align = opts.align or "l",
	}
	layoutText(group)
	return group
end

function Kit.setText(group, str: string, color: Color3?)
	local t = info[group]
	if not t then
		return
	end
	str = str:upper()
	if str == t.str and (color == nil or color == t.color) then
		return
	end
	t.str = str
	t.color = color or t.color
	layoutText(group)
end

-- ===== Logo: big extruded bitmap letters, one Frame per letter so they can animate =====

local BANDS = { C.yellow, C.yellow, C.yellow, C.orange, C.orange, C.red, C.red }

function Kit.logo(parent, str: string, cx: number, y: number, scale: number)
	str = str:upper()
	local advance = 6 * scale
	local total = #str * advance - scale
	local letters = {}
	for i = 1, #str do
		local g = GLYPH[str:sub(i, i)] or GLYPH["?"]
		local lx = math.floor(cx - total / 2) + (i - 1) * advance
		local holder = Kit.group(parent, lx, y, 5 * scale + 2, 7 * scale + 3)
		for layer = 1, 3 do
			for r = 1, 7 do
				local row, c = g[r], 1
				while c <= 5 do
					if row:sub(c, c) == "1" then
						local e = c
						while e < 5 and row:sub(e + 1, e + 1) == "1" do
							e += 1
						end
						local px, py = (c - 1) * scale, (r - 1) * scale
						local pw = (e - c + 1) * scale
						if layer == 1 then -- drop shadow
							rect(holder, px + 1, py + 2, pw + 2, scale + 2, C.navy)
						elseif layer == 2 then -- outline
							rect(holder, px - 1 + 1, py - 1 + 1, pw + 2, scale + 2, C.ink)
						else
							rect(holder, px + 1, py + 1, pw, scale, BANDS[r])
						end
						c = e + 1
					else
						c += 1
					end
				end
			end
		end
		letters[i] = holder
	end
	return letters
end

-- ===== Buttons =====

-- opts: fill, hover, hi, disabled
function Kit.button(parent, label: string, x, y, w, h, onClick, opts)
	opts = opts or {}
	local fill = if opts.disabled then C.dusk else (opts.fill or C.navy)
	local hover = opts.hover or C.blue
	local root = Kit.group(parent, x, y, w, h + 1)
	Kit.panel(root, 0, 1, w, h, { fill = C.ink, border = C.ink, hi = C.ink, lo = C.ink })
	local face = Kit.group(root, 0, 0, w, h)
	local p = Kit.panel(face, 0, 0, w, h, { fill = fill, border = C.ink, hi = opts.hi or C.sky, lo = C.ink })
	local textColor = if opts.disabled then C.slate else C.white
	local txt = Kit.text(face, label, { x = w / 2, y = math.floor((h - 7) / 2), align = "c", color = textColor })

	local arrowL = Kit.group(face, 3, math.floor(h / 2) - 2, 3, 5)
	local arrowR = Kit.group(face, w - 6, math.floor(h / 2) - 2, 3, 5)
	for _, a in { arrowL, arrowR } do
		a.Visible = false
	end
	Kit.arrow(arrowL, 0, 0, C.yellow, true)
	Kit.arrow(arrowR, 0, 0, C.yellow, false)

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 5
	hit.Parent = root

	local obj = { Root = root, Label = txt }
	if not opts.disabled then
		local function setHover(on)
			p.Fill.BackgroundColor3 = if on then hover else fill
			arrowL.Visible, arrowR.Visible = on, on
			if not on then
				face.Position = UDim2.fromOffset(0, 0)
			end
		end
		hit.MouseEnter:Connect(function() setHover(true) end)
		hit.MouseLeave:Connect(function() setHover(false) end)
		hit.MouseButton1Down:Connect(function() face.Position = UDim2.fromOffset(0, Kit.U) end)
		hit.MouseButton1Up:Connect(function() face.Position = UDim2.fromOffset(0, 0) end)
		hit.Activated:Connect(function()
			if onClick then
				onClick()
			end
		end)
	end
	return obj
end

-- Little right (or left) pointing triangle, 3 wide x 5 tall
function Kit.arrow(parent, x, y, color, pointRight: boolean)
	if pointRight then
		rect(parent, x, y, 1, 5, color)
		rect(parent, x + 1, y + 1, 1, 3, color)
		rect(parent, x + 2, y + 2, 1, 1, color)
	else
		rect(parent, x + 2, y, 1, 5, color)
		rect(parent, x + 1, y + 1, 1, 3, color)
		rect(parent, x, y + 2, 1, 1, color)
	end
end

-- ===== Item sprites (8x8). o = outline, c = item colour, l = light, d = dark, h = wood =====

local SPRITES = {
	Block = "oooooooo/ollllllo/ollllllo/occccccco/occccccco/oddddddo/oddddddo/oooooooo",
	Pickaxe = "..oooo../occccco./oc.oho.c/o..oh..o/...oh.../...oh.../...oh.../...oo...",
	Axe = "..oooo../occcco../occchho./.occho../..ohho../..oho.../..oho.../..ooo...",
	Shovel = "..oooo../.occco../.occco../..occo../...oho../...oho../..ohho../..oooo..",
	Lump = "......../..oooo../.occclo./occllcco/occccco./.occddo./..oooo../........",
	Gem = "..oooo../.olllco./olllccdo/.occcdo./..ocdo../...oo.../......../........",
	Stick = ".......o/......oh/.....oh./....oh../...oh.../..oh..../.oh...../oo......",
}
for name, s in SPRITES do
	SPRITES[name] = string.split(s, "/")
end

local function shade(c: Color3, k: number): Color3
	return if k >= 0 then c:Lerp(Color3.new(1, 1, 1), k) else c:Lerp(Color3.new(0, 0, 0), -k)
end

-- scale = virtual pixels per sprite pixel (2 -> a 16x16 icon)
function Kit.icon(parent, x, y, sprite: string, color: Color3, scale: number)
	local rows = SPRITES[sprite] or SPRITES.Lump
	local map = { o = C.ink, c = color, l = shade(color, 0.45), d = shade(color, -0.35), h = C.brown }
	for r = 1, 8 do
		local row, c = rows[r], 1
		while c <= 8 do
			local ch = row:sub(c, c)
			if map[ch] then
				local e = c
				while e < 8 and row:sub(e + 1, e + 1) == ch do
					e += 1
				end
				rect(parent, x + (c - 1) * scale, y + (r - 1) * scale, (e - c + 1) * scale, scale, map[ch])
				c = e + 1
			else
				c += 1
			end
		end
	end
end

-- ===== Stepped animation =====

local tickers = {}
local conn
local function ensureLoop()
	if conn then
		return
	end
	conn = RunService.Heartbeat:Connect(function(dt)
		for t in tickers do
			t.acc += dt
			local step = 1 / t.fps
			while t.acc >= step do
				t.acc -= step
				t.n += 1
				if t.always or not Kit.ReducedMotion then
					t.fn(t.n)
				end
			end
		end
	end)
end

-- Calls fn(frameNumber) fps times a second. Returns a stop function.
function Kit.every(fps: number, fn, always: boolean?)
	local t = { fps = fps, fn = fn, acc = 0, n = 0, always = always }
	tickers[t] = true
	ensureLoop()
	return function()
		tickers[t] = nil
	end
end

-- Runs fn(0..1) in `count` whole steps over `duration` seconds (jumps to the end if reduced motion)
function Kit.steps(duration: number, count: number, fn, done)
	task.spawn(function()
		if Kit.ReducedMotion then
			fn(1)
		else
			for i = 1, count do
				task.wait(duration / count)
				fn(i / count)
			end
		end
		if done then
			done()
		end
	end)
end

return Kit
