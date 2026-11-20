--[[
	8-bit loading screen (shared module: Boot shows it on join, GameClient reuses it when entering a world).

	Loading.Show(message)      show (or change the message of) the screen
	Loading.SetMessage(text)
	Loading.SetProgress(0..1)  fills the bar; Loading.SetProgress(nil) = scanning "working" bar
	Loading.SetTips(bool)      show rotating tips
	Loading.Hide()             pixel wipe out
]]

local Players = game:GetService("Players")

local Kit = require(script.Parent:WaitForChild("PixelKit"))
local C = Kit.C

local TIPS = {
	"HOLD LEFT MOUSE TO MINE AND CHOP",
	"RIGHT CLICK PLACES THE BLOCK YOU HOLD",
	"PRESS E FOR INVENTORY AND CRAFTING",
	"TREES GIVE WOOD. WOOD MAKES TOOLS",
	"DIG DEEP FOR COAL, IRON, GOLD, DIAMOND",
	"BETTER PICKAXES MINE HARDER ROCK",
	"1-9 OR MOUSE WHEEL SELECTS YOUR HOTBAR",
	"YOUR WORLD AND INVENTORY SAVE AUTOMATICALLY",
}

local Loading = {}

local gui, canvas, state
local building = false
local stopAnim
local tipsOn = true
local message = "LOADING"
local progress: number? = nil

local SEGMENTS, SEG_W = 24, 5
local loadU = 4

local function build()
	local player = Players.LocalPlayer
	gui = Instance.new("ScreenGui")
	gui.Name = "LoadingScreen"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local viewport = Kit.viewport()
	Kit.U = Kit.fitUnit(viewport)
	loadU = Kit.U
	local U = Kit.U

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.ink
	bg.BorderSizePixel = 0
	bg.Parent = gui

	canvas = Instance.new("Frame")
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(320 * U, 180 * U)
	canvas.BackgroundTransparency = 1
	canvas.Parent = bg

	state = {}

	-- The block being mined (cracks grow, then it bursts and starts over)
	local bx, by = 144, 38
	Kit.icon(canvas, bx, by, "Block", C.green, 4)
	local crackLayer = Kit.group(canvas, bx, by, 32, 32)
	local debris = Kit.group(canvas, bx - 16, by - 16, 64, 64)
	state.crackLayer, state.debris = crackLayer, debris

	state.title = Kit.text(canvas, message, { x = 160, y = 90, align = "c", scale = 2, color = C.yellow })
	state.dots = Kit.text(canvas, "", { x = 160, y = 90, align = "l", scale = 2, color = C.yellow })

	-- Segmented bar
	local barW = SEGMENTS * SEG_W + 4
	local barX = math.floor((320 - barW) / 2)
	Kit.panel(canvas, barX, 110, barW, 14, { fill = C.dusk, border = C.ink, hi = C.slate, lo = C.ink })
	state.segs = {}
	for i = 1, SEGMENTS do
		local s = Kit.rect(canvas, barX + 2 + (i - 1) * SEG_W, 113, SEG_W - 1, 8, C.slate)
		state.segs[i] = s
	end

	state.tip = Kit.text(canvas, "", { x = 160, y = 140, align = "c", color = C.silver })
end

local CRACKS = {
	{ 14, 12, 4, 1 }, { 16, 13, 1, 5 }, { 10, 20, 7, 1 }, { 20, 8, 1, 8 }, { 6, 14, 1, 7 }, { 22, 22, 6, 1 },
}
local BITS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -2 }, { 0, 2 } }

local function applyBar(frame: number)
	local lit = {}
	if progress then
		local n = math.floor(progress * SEGMENTS + 0.5)
		for i = 1, n do
			lit[i] = true
		end
	else
		local pos = frame % (SEGMENTS * 2 - 4)
		if pos >= SEGMENTS - 1 then
			pos = (SEGMENTS * 2 - 4) - pos
		end
		for i = pos + 1, pos + 4 do
			lit[i] = true
		end
	end
	for i, s in state.segs do
		s.BackgroundColor3 = if lit[i] then C.lime else C.slate
	end
end

local function animate(frame: number)
	if not state then
		return
	end
	Kit.U = loadU
	-- cracks: one more per tick, burst on the 8th
	local phase = frame % 9
	state.crackLayer:ClearAllChildren()
	for i = 1, math.min(phase, #CRACKS) do
		local c = CRACKS[i]
		Kit.rect(state.crackLayer, c[1], c[2], c[3], c[4], C.ink)
	end
	state.debris:ClearAllChildren()
	if phase >= 7 then
		local d = (phase - 6) * 4
		for _, b in BITS do
			Kit.rect(state.debris, 30 + b[1] * d, 30 + b[2] * d + (phase - 6) * 2, 3, 3, if (b[1] + b[2]) % 2 == 0 then C.green else C.lime)
		end
	end
	applyBar(frame)

	-- "LOADING..." dots
	local dots = string.rep(".", frame % 4)
	local w = Kit.textWidth(message, 2)
	Kit.setText(state.dots, dots)
	state.dots.Position = UDim2.fromOffset(math.floor(160 * Kit.U + (w / 2 + 2) * Kit.U), 90 * Kit.U)

	-- tips
	if tipsOn then
		if not state.tipIndex then
			state.tipIndex = math.random(#TIPS)
			Kit.setText(state.tip, TIPS[state.tipIndex])
		elseif frame % 24 == 0 then -- every 4 seconds
			state.tipIndex = state.tipIndex % #TIPS + 1
			Kit.setText(state.tip, TIPS[state.tipIndex])
		end
	else
		state.tipIndex = nil
		Kit.setText(state.tip, "")
	end
end

function Loading.IsShowing(): boolean
	return gui ~= nil
end

function Loading.Show(text: string?)
	if text then
		message = text
	end
	if building then
		return
	end
	if gui then
		if state then
			Kit.setText(state.title, message)
		end
		return
	end
	building = true
	build()
	building = false
	stopAnim = Kit.every(6, animate, true)
end

function Loading.SetMessage(text: string)
	message = text
	if state then
		Kit.setText(state.title, text)
	end
end

function Loading.SetProgress(p: number?)
	progress = p
end

function Loading.SetTips(on: boolean)
	tipsOn = on
end

function Loading.Hide()
	if not gui then
		return
	end
	local g = gui
	gui, state = nil, nil
	if stopAnim then
		stopAnim()
		stopAnim = nil
	end
	-- pixel wipe: the black screen peels away in vertical strips, left to right
	local bg = g:FindFirstChild("Background")
	if not bg or Kit.ReducedMotion then
		g:Destroy()
		return
	end
	for _, child in bg:GetChildren() do
		child.Visible = false
	end
	bg.BackgroundTransparency = 1
	local strips = {}
	local n = 12
	for i = 1, n do
		local s = Instance.new("Frame")
		s.BorderSizePixel = 0
		s.BackgroundColor3 = C.ink
		s.Position = UDim2.fromScale((i - 1) / n, 0)
		s.Size = UDim2.fromScale(1 / n + 0.001, 1)
		s.Parent = bg
		strips[i] = s
	end
	task.spawn(function()
		for i = 1, n do
			strips[i]:Destroy()
			task.wait(0.03)
		end
		g:Destroy()
	end)
end

return Loading
