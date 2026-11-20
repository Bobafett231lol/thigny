--[[
	Client orchestrator.  Loading screen -> main menu -> (pick slot) -> loading screen -> world + HUD.

	Controls
	  1-9 / mouse wheel   select hotbar slot        E   inventory + crafting
	  Left mouse (hold)   mine / dig / chop / break  Right mouse   place the held block
	  M or the MENU button   pause menu (settings, save & quit to the title screen)
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera or workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() and workspace.CurrentCamera

local Kit = require(ReplicatedFirst:WaitForChild("PixelKit"))
local Loading = require(ReplicatedFirst:WaitForChild("Loading"))
local Menu = require(script:WaitForChild("Menu"))
local Hud = require(script:WaitForChild("Hud"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("GameConfig"))
local Recipes = require(Shared:WaitForChild("Recipes"))

-- Make sure the loading screen is up (Boot normally did this already)
Loading.Show("LOADING")
Loading.SetProgress(0.1)
local loadStart = os.clock()

local folder = ReplicatedStorage:WaitForChild("GameRemotes")
local remotes = {}
for _, name in Config.Remotes do
	remotes[name] = folder:WaitForChild(name)
end
Loading.SetProgress(0.4)

-- ===== state =====
local settings = { UIScale = 2, Tips = true, ReducedMotion = false, ShowFps = false }
local inWorld = false
local entering = false
local gotMenu = false

Hud.Init({
	Remotes = remotes,
	Items = Items,
	Recipes = Recipes,
	Config = Config,
	onMenu = function()
		if inWorld and not Menu.IsOpen() then
			Menu.Show("pause")
		end
	end,
})

local function applySettings()
	Kit.ReducedMotion = settings.ReducedMotion == true
	Loading.SetTips(settings.Tips)
	Hud.SetSettings(settings)
end

-- ===== menu callbacks =====
Menu.Init({
	onPlay = function(slot)
		entering = true
		Menu.Hide()
		Loading.SetProgress(nil)
		Loading.Show("ENTERING WORLD")
		remotes.MenuAction:FireServer("Play", slot)
	end,
	onCreate = function(slot, name)
		remotes.MenuAction:FireServer("Create", slot, name)
	end,
	onDelete = function(slot)
		remotes.MenuAction:FireServer("Delete", slot)
	end,
	onSetting = function(key, value)
		settings[key] = value
		remotes.MenuAction:FireServer("Setting", key, value)
		applySettings()
	end,
	onExit = function()
		inWorld = false
		Menu.Hide()
		Hud.Hide()
		Loading.SetProgress(nil)
		Loading.Show("SAVING")
		remotes.MenuAction:FireServer("ExitToMenu")
	end,
})

-- ===== server events =====
remotes.MenuState.OnClientEvent:Connect(function(summaries, newSettings, active)
	for k, v in newSettings do
		settings[k] = v
	end
	applySettings()
	Menu.SetData(summaries, settings, active)
	gotMenu = true
	if not inWorld and not entering and not Menu.IsOpen() then
		-- keep the loading screen up long enough to read, then reveal the title screen
		local wait = 1.4 - (os.clock() - loadStart)
		if wait > 0 then
			task.wait(wait)
		end
		if not inWorld and not entering and not Menu.IsOpen() then
			Menu.Show("title")
		end
		Loading.Hide()
	end
end)

remotes.EnterWorld.OnClientEvent:Connect(function()
	entering = false
	inWorld = true
	if not Hud.IsShown() then
		Hud.Show()
	end
	Loading.Hide()
end)

remotes.InventoryUpdate.OnClientEvent:Connect(function(snapshot, selected)
	Hud.SetInventory(snapshot, selected)
end)

remotes.Notify.OnClientEvent:Connect(function(text)
	Hud.Notify(text)
end)

remotes.Hit.OnClientEvent:Connect(function(position, color)
	if typeof(position) == "Vector3" and typeof(color) == "Color3" then
		Hud.Hit(position, color)
	end
end)

-- Tell the server our UI is ready, and wait for the account data
Loading.SetProgress(0.7)
remotes.Ready:FireServer()
task.delay(20, function()
	if not gotMenu then
		Loading.SetMessage("STILL LOADING")
	end
end)

-- ===== input =====

local function aimDirection(): Vector3?
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	local target = if result then result.Position else ray.Origin + ray.Direction * 500
	local dir = target - head.Position
	if dir.Magnitude < 0.5 then
		return ray.Direction
	end
	return dir
end

local function canPlay(): boolean
	return inWorld and not Menu.IsOpen() and not Hud.IsInventoryOpen()
end

local holding = false

local function swingLoop()
	while holding do
		local dir = aimDirection()
		if dir and canPlay() then
			remotes.Swing:FireServer(dir)
		end
		task.wait(Config.SwingCooldown)
	end
end

local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not inWorld then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		if Menu.IsOpen() then
			if Menu.Mode() == "pause" then
				Menu.Hide()
			end
		else
			Menu.Show("pause")
		end
		return
	end
	if Menu.IsOpen() then
		return
	end
	local slot = NUMBER_KEYS[input.KeyCode]
	if slot then
		Hud.Select(slot)
	elseif input.KeyCode == Enum.KeyCode.E then
		Hud.ToggleInventory()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and canPlay() then
		if not holding then
			holding = true
			task.spawn(swingLoop)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and canPlay() then
		local dir = aimDirection()
		if dir then
			remotes.Place:FireServer(dir)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if processed or not canPlay() or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	local step = if input.Position.Z > 0 then -1 else 1
	Hud.Select(((Hud.Selected() - 1 + step) % Config.HotbarSize) + 1)
end)
