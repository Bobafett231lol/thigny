--[[
	Main menu + pause menu (8-bit style, built with PixelKit on a 320x180 virtual canvas).

	Screens:  title -> slots -> new      title -> settings      pause -> settings
	Menu.Init({ onPlay, onCreate, onDelete, onSetting, onExit })
	Menu.SetData(slotSummaries, settings, activeSlot)    (from the server)
	Menu.Show("title" | "pause")    Menu.Hide()    Menu.IsOpen()    Menu.Mode()
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Kit = require(ReplicatedFirst:WaitForChild("PixelKit"))
local Scene = require(script.Parent.Scene)
local C = Kit.C

local Menu = {}

local env = {}
local gui, root, canvas, killScene, stopLogo
local cvx, cvy = 0, 0
local menuU = 4
local mode, screen = "title", "title"
local open = false
local data = { slots = { false, false, false }, settings = { UIScale = 2, Tips = true, ReducedMotion = false, ShowFps = false }, active = 0 }
local confirmDelete: number? = nil
local newSlot = 1
local logoLetters, logoBase

local SIZES = { "SMALL", "NORMAL", "LARGE" }
local SLOT_COUNT = 3

-- ===== helpers =====

local function fmtTime(sec: number?): string
	local m = math.floor((sec or 0) / 60)
	if m >= 60 then
		return ("%dH %02dM"):format(m // 60, m % 60)
	end
	return ("%dM"):format(m)
end

local function fmtDate(ts: number?): string
	return if ts then os.date("%b %d", ts):upper() else "-"
end

local function onoff(v: boolean): string
	return if v then "ON" else "OFF"
end

local render

local function go(name: string)
	screen = name
	confirmDelete = nil
	render(true)
end

local function slideIn()
	Kit.U = menuU
	local U = menuU
	canvas.Position = UDim2.fromOffset(cvx * U, (cvy + 6) * U)
	Kit.steps(0.16, 4, function(t)
		if canvas and canvas.Parent then
			canvas.Position = UDim2.fromOffset(cvx * menuU, math.floor((cvy + 6 * (1 - t)) * menuU))
		end
	end)
end

local function heading(text: string, y: number?)
	Kit.text(canvas, text, { x = 160, y = y or 14, align = "c", scale = 2, color = C.yellow })
end

local function backButton(y: number, target: string)
	Kit.button(canvas, "BACK", 110, y, 100, 14, function()
		go(target)
	end)
end

-- ===== screens =====

local function screenTitle()
	logoLetters = Kit.logo(canvas, "THIGNY", 160, 18, 4)
	logoBase = {}
	for _, l in logoLetters do
		logoBase[l] = l.Position.Y.Offset
	end
	Kit.text(canvas, "MINE. BUILD. SURVIVE.", { x = 160, y = 56, align = "c", color = C.silver })
	Kit.button(canvas, "PLAY", 110, 86, 100, 16, function()
		go("slots")
	end, { fill = C.green, hover = C.teal, hi = C.lime })
	Kit.button(canvas, "SETTINGS", 110, 108, 100, 16, function()
		go("settings")
	end)
	Kit.text(canvas, "V1.0", { x = 316, y = 170, align = "r", color = C.slate })
end

local function screenSlots()
	heading("SELECT CHARACTER", 10)
	for i = 1, SLOT_COUNT do
		local s = data.slots[i]
		local y = 30 + (i - 1) * 44
		Kit.panel(canvas, 20, y, 280, 40, { fill = C.dusk, border = C.ink, hi = C.slate, lo = C.ink })
		Kit.panel(canvas, 24, y + 4, 18, 32, { fill = if s then C.blue else C.slate, border = C.ink, hi = C.sky, lo = C.navy })
		Kit.text(canvas, tostring(i), { x = 33, y = y + 13, align = "c", scale = 2 })

		if s then
			Kit.text(canvas, s.name, { x = 48, y = y + 5, scale = 2 })
			Kit.text(canvas, ("MINED %d  CHOPPED %d  BUILT %d"):format(s.mined, s.chopped, s.placed), { x = 48, y = y + 23, color = C.silver })
			Kit.text(canvas, ("PLAYED %s  LAST %s"):format(fmtTime(s.playTime), fmtDate(s.played)), { x = 48, y = y + 31, color = C.slate })
			if confirmDelete == i then
				Kit.text(canvas, "DELETE?", { x = 225, y = y + 17, align = "r", color = C.orange })
				Kit.button(canvas, "YES", 250, y + 4, 44, 14, function()
					confirmDelete = nil
					if env.onDelete then
						env.onDelete(i)
					end
				end, { fill = C.red, hover = C.orange, hi = C.orange })
				Kit.button(canvas, "NO", 250, y + 22, 44, 14, function()
					confirmDelete = nil
					render(false)
				end)
			else
				Kit.button(canvas, "PLAY", 250, y + 4, 44, 14, function()
					if env.onPlay then
						env.onPlay(i)
					end
				end, { fill = C.green, hover = C.teal, hi = C.lime })
				Kit.button(canvas, "DELETE", 250, y + 22, 44, 14, function()
					confirmDelete = i
					render(false)
				end, { fill = C.plum, hover = C.red, hi = C.red })
			end
		else
			Kit.text(canvas, "EMPTY", { x = 48, y = y + 8, scale = 2, color = C.slate })
			Kit.text(canvas, "CREATE A NEW CHARACTER", { x = 48, y = y + 27, color = C.slate })
			Kit.button(canvas, "NEW", 236, y + 13, 58, 14, function()
				newSlot = i
				go("new")
			end)
		end
	end
	backButton(164, "title")
end

local function screenNew()
	heading("NEW CHARACTER", 34)
	Kit.panel(canvas, 60, 56, 200, 70, { fill = C.dusk, border = C.ink, hi = C.slate, lo = C.ink })
	Kit.text(canvas, ("SLOT %d"):format(newSlot), { x = 160, y = 64, align = "c", color = C.silver })
	Kit.panel(canvas, 76, 78, 168, 20, { fill = C.ink, border = C.slate, hi = C.ink, lo = C.ink })

	local U = Kit.U
	local tb = Instance.new("TextBox")
	tb.BackgroundTransparency = 1
	tb.Position = UDim2.fromOffset(82 * U, 80 * U)
	tb.Size = UDim2.fromOffset(156 * U, 16 * U)
	tb.Font = Enum.Font.Arcade
	tb.TextSize = math.max(12, math.floor(9 * U))
	tb.TextColor3 = C.white
	tb.PlaceholderText = "PLAYER"
	tb.PlaceholderColor3 = C.slate
	tb.Text = ""
	tb.ClearTextOnFocus = false
	tb.TextXAlignment = Enum.TextXAlignment.Left
	tb.ZIndex = 6
	tb.Parent = canvas
	tb:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = tb.Text:upper():gsub("[^A-Z0-9 _%-]", "")
		clean = clean:sub(1, 12)
		if clean ~= tb.Text then
			tb.Text = clean
		end
	end)

	local function create()
		local name = tb.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then
			name = "PLAYER"
		end
		if env.onCreate then
			env.onCreate(newSlot, name)
		end
		go("slots")
	end
	tb.FocusLost:Connect(function(enter)
		if enter then
			create()
		end
	end)
	Kit.button(canvas, "CREATE", 76, 106, 80, 14, create, { fill = C.green, hover = C.teal, hi = C.lime })
	Kit.button(canvas, "CANCEL", 164, 106, 80, 14, function()
		go("slots")
	end)
	task.defer(function()
		if tb.Parent then
			tb:CaptureFocus()
		end
	end)
end

local function screenSettings()
	heading("SETTINGS", 14)
	local s = data.settings
	local rows = {
		{ "HUD SIZE", SIZES[s.UIScale] or "NORMAL", function() return "UIScale", s.UIScale % 3 + 1 end },
		{ "TIPS", onoff(s.Tips), function() return "Tips", not s.Tips end },
		{ "REDUCED MOTION", onoff(s.ReducedMotion), function() return "ReducedMotion", not s.ReducedMotion end },
		{ "FPS COUNTER", onoff(s.ShowFps), function() return "ShowFps", not s.ShowFps end },
	}
	for i, r in rows do
		local y = 40 + (i - 1) * 24
		Kit.panel(canvas, 40, y, 240, 20, { fill = C.dusk, border = C.ink, hi = C.slate, lo = C.ink })
		Kit.text(canvas, r[1], { x = 50, y = y + 7 })
		Kit.button(canvas, r[2], 206, y + 3, 66, 14, function()
			local key, value = r[3]()
			data.settings[key] = value
			if key == "ReducedMotion" then
				Kit.ReducedMotion = value
			end
			if env.onSetting then
				env.onSetting(key, value)
			end
			render(false)
		end, { fill = if (r[2] == "OFF") then C.slate else C.navy })
	end
	Kit.text(canvas, "SETTINGS SAVE WITH YOUR ACCOUNT", { x = 160, y = 142, align = "c", color = C.slate })
	backButton(156, if mode == "pause" then "pause" else "title")
end

local function screenPause()
	heading("PAUSED", 40)
	Kit.button(canvas, "RESUME", 100, 68, 120, 16, function()
		Menu.Hide()
	end, { fill = C.green, hover = C.teal, hi = C.lime })
	Kit.button(canvas, "SETTINGS", 100, 90, 120, 16, function()
		go("settings")
	end)
	Kit.button(canvas, "SAVE & QUIT", 100, 112, 120, 16, function()
		if env.onExit then
			env.onExit()
		end
	end, { fill = C.plum, hover = C.red, hi = C.red })
end

local SCREENS = { title = screenTitle, slots = screenSlots, new = screenNew, settings = screenSettings, pause = screenPause }

render = function(animate: boolean?)
	if not canvas then
		return
	end
	Kit.U = menuU
	canvas:ClearAllChildren()
	logoLetters, logoBase = nil, nil
	local fn = SCREENS[screen]
	if fn then
		fn()
	end
	if animate then
		slideIn()
	end
end

-- ===== gui lifecycle =====

local function destroy()
	if killScene then
		killScene()
		killScene = nil
	end
	if stopLogo then
		stopLogo()
		stopLogo = nil
	end
	if gui then
		gui:Destroy()
	end
	gui, root, canvas = nil, nil, nil
end

local function build()
	destroy()
	local viewport = Kit.viewport()
	Kit.U = Kit.fitUnit(viewport)
	menuU = Kit.U
	local U = menuU
	local Wv, Hv = math.ceil(viewport.X / U), math.ceil(viewport.Y / U)
	cvx, cvy = math.floor((Wv - 320) / 2), math.floor((Hv - 180) / 2)

	gui = Instance.new("ScreenGui")
	gui.Name = "MainMenu"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 500
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BorderSizePixel = 0
	if mode == "title" then
		root.BackgroundColor3 = C.ink
		killScene = Scene.Build(root, Wv, Hv)
	else
		root.BackgroundColor3 = C.ink
		root.BackgroundTransparency = 0.35
	end
	root.Parent = gui

	canvas = Kit.group(root, cvx, cvy, 320, 180)

	-- the logo letters bob up and down in whole-pixel steps
	stopLogo = Kit.every(6, function(n)
		if not logoLetters then
			return
		end
		for i, letter in logoLetters do
			local off = math.floor(math.sin(n * 0.55 + i * 0.9) * 1.5 + 0.5)
			letter.Position = UDim2.fromOffset(letter.Position.X.Offset, logoBase[letter] - off * menuU)
		end
	end)
end

local resizeToken = 0
local function watchViewport()
	local cam = workspace.CurrentCamera
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if not open then
			return
		end
		resizeToken += 1
		local mine = resizeToken
		task.delay(0.25, function()
			if mine == resizeToken and open then
				build()
				render(false)
			end
		end)
	end)
end

-- ===== public =====

function Menu.Init(callbacks)
	env = callbacks
	watchViewport()
end

function Menu.Show(kind: string)
	mode = kind
	screen = if kind == "pause" then "pause" else "title"
	confirmDelete = nil
	open = true
	build()
	render(true)
end

function Menu.Hide()
	open = false
	destroy()
end

function Menu.IsOpen(): boolean
	return open
end

function Menu.Mode(): string
	return mode
end

function Menu.SetData(slots, settings, active)
	data.slots, data.settings, data.active = slots, settings, active
	Kit.ReducedMotion = settings.ReducedMotion == true
	if open and (screen == "slots" or screen == "settings") then
		render(false)
	end
end

return Menu
