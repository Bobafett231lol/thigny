--[[
	Game bootstrap: shared saved world + per-player save slots, inventory, mining, gathering, building.
	Flow per player: load account -> main menu (client) -> pick/create slot -> safe spawn -> play.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local World = require(ServerStorage:WaitForChild("WorldFramework"))
local Systems = ServerStorage:WaitForChild("GameSystems")
local PlayerData = require(Systems:WaitForChild("PlayerData"))
local Remotes = require(Systems:WaitForChild("Remotes"))
local Mining = require(Systems:WaitForChild("Mining"))
local Gathering = require(Systems:WaitForChild("Gathering"))
local Building = require(Systems:WaitForChild("Building"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Items = require(Shared:WaitForChild("Items"))
local Recipes = require(Shared:WaitForChild("Recipes"))

Players.CharacterAutoLoads = false

-- ===== World =====

local world = World.new({
	WorldId = "Main",
	ViewDistance = 5,
	-- Seed = 12345, -- optional fixed seed (only used when creating a new save)
})
world:Load()

local spawn = world:GetMeta("Spawn")
local spawnPos
if spawn then
	spawnPos = Vector3.new(spawn[1], spawn[2], spawn[3])
else
	spawnPos = world:FindLandNear(0, 0)
	world:SetMeta("Spawn", { spawnPos.X, spawnPos.Y, spawnPos.Z })
end

world:Start()
world:PreloadAround(spawnPos, 2) -- keeps the menu backdrop (and the first spawn) ready

local mining = Mining.new(world, Remotes)
local gathering = Gathering.new(world, Remotes)
local building = Building.new(world, Remotes)

local recipesById = {}
for _, r in Recipes do
	recipesById[r.Id] = r
end

-- ===== Helpers =====

local function validSlot(n: any): boolean
	return type(n) == "number" and n == math.floor(n) and n >= 1 and n <= Config.SlotCount
end

local function sync(profile)
	if profile.SyncQueued then
		return
	end
	profile.SyncQueued = true
	task.defer(function()
		profile.SyncQueued = false
		if profile.Active and not profile.Released then
			Remotes.InventoryUpdate:FireClient(profile.Player, profile.Inventory:Snapshot(), profile.Data.Selected)
		end
	end)
end

local function sendMenu(profile)
	Remotes.MenuState:FireClient(
		profile.Player,
		PlayerData.Summaries(profile),
		profile.Settings,
		if profile.Active then profile.Slot else 0
	)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true -- dig through water to the ground below
rayParams.FilterDescendantsInstances = { workspace.Terrain, world.Chunks.DecoRoot }

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.IgnoreWater = true
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }

local function castFrom(player: Player, direction: any): RaycastResult?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return nil
	end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 or direction ~= direction then
		return nil
	end
	local head = char:FindFirstChild("Head")
	local origin = if head and head:IsA("BasePart") then head.Position else root.Position
	return workspace:Raycast(origin, direction.Unit * Config.ReachStuds, rayParams)
end

local function heldItem(profile): string?
	local s = profile.Inventory:Get(profile.Data.Selected)
	return s and s.id or nil
end

local lastAction = {} -- [Player] = os.clock()
local function tooFast(player: Player, interval: number): boolean
	local now = os.clock()
	if now - (lastAction[player] or 0) < interval then
		return true
	end
	lastAction[player] = now
	return false
end

-- ===== Safe spawning =====
-- The character is anchored at the destination until real terrain exists under it, so nobody
-- can fall through ungenerated ground. Saved positions are re-validated against the terrain.

local function surfaceY(x: number, z: number): number?
	local r = workspace:Raycast(Vector3.new(x, Config.WorldTopY, z), Vector3.new(0, -(Config.WorldTopY + 50), 0), terrainOnly)
	return r and r.Position.Y
end

local function groundNear(x: number, y: number, z: number): number?
	local r = workspace:Raycast(Vector3.new(x, y + 3, z), Vector3.new(0, -80, 0), terrainOnly)
	return r and r.Position.Y
end

-- Waits (up to `timeout` s) until terrain exists at x,z and returns where to stand. Never returns nil.
local function findStandingY(x: number, z: number, savedY: number?, timeout: number): (number, boolean)
	local deadline = os.clock() + timeout
	repeat
		local y = (savedY and groundNear(x, savedY, z)) or surfaceY(x, z)
		if y then
			task.wait(0.4) -- let the voxels settle so collision exists
			return y, true
		end
		task.wait(0.2)
	until os.clock() > deadline
	return world:GetGeneratedHeight(x, z), false
end

local enterWorld

local function placeCharacter(player: Player, profile, useSaved: boolean)
	local target, savedY = spawnPos, nil
	local saved = profile.Data.Position
	if useSaved and saved and type(saved[2]) == "number" and saved[2] > 8 then
		target, savedY = Vector3.new(saved[1], saved[2], saved[3]), saved[2]
	end

	player:LoadCharacter()
	local char = player.Character
	local root = char and char:WaitForChild("HumanoidRootPart", 10)
	if not char or not root or not profile.Active then
		return
	end
	root.Anchored = true
	char:PivotTo(CFrame.new(target.X, Config.WorldTopY - 20, target.Z)) -- near the top so chunks stream in below

	local y, found = findStandingY(target.X, target.Z, savedY, 25)
	if not found and target ~= spawnPos then
		-- saved place never generated: fall back to the world spawn
		world:PreloadAround(spawnPos, 1)
		target = spawnPos
		y = findStandingY(target.X, target.Z, nil, 15)
	end
	if not player.Parent or player.Character ~= char or not profile.Active then
		return
	end
	char:PivotTo(CFrame.new(target.X, y + 5, target.Z))
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = false

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			task.delay(Players.RespawnTime, function()
				if profile.Active and player.Parent then
					placeCharacter(player, profile, false) -- respawn at the world spawn, keep inventory
				end
			end)
		end)
	end
	Remotes.EnterWorld:FireClient(player)
end

enterWorld = function(player: Player, profile)
	sync(profile)
	placeCharacter(player, profile, true)
end

-- Safety net: anyone who ends up far below the world gets put back on the ground.
task.spawn(function()
	while true do
		task.wait(2)
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.GetActive(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if profile and root and not root.Anchored and root.Position.Y < -30 then
				warn("[Game] rescuing " .. player.Name .. " from below the world")
				local y = surfaceY(spawnPos.X, spawnPos.Z) or spawnPos.Y
				player.Character:PivotTo(CFrame.new(spawnPos.X, y + 5, spawnPos.Z))
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end)

-- ===== Player lifecycle =====

local ready = {} -- players whose client UI is connected

local function onPlayerAdded(player: Player)
	local profile, reason = PlayerData.Load(player)
	if not profile then
		if player.Parent then
			warn("[Game] Kicking " .. player.Name .. ": " .. tostring(reason))
			player:Kick("Your save data could not be loaded safely. Please rejoin in a minute.")
		end
		return
	end
	profile.OnInventoryChanged = function()
		sync(profile)
	end
	if ready[player] then
		sendMenu(profile)
	end
end

Remotes.Ready.OnServerEvent:Connect(function(player)
	ready[player] = true
	local profile = PlayerData.Get(player)
	if profile then
		sendMenu(profile)
		if profile.Active then
			sync(profile)
		end
	end
end)

-- Menu actions: ("Create", slot, name) ("Delete", slot) ("Play", slot) ("Setting", key, value) ("ExitToMenu")
Remotes.MenuAction.OnServerEvent:Connect(function(player, action, a, b)
	local profile = PlayerData.Get(player)
	if not profile or profile.Released or profile.Busy or type(action) ~= "string" then
		return
	end
	profile.Busy = true
	local ok, err = xpcall(function()
		if action == "Setting" then
			PlayerData.SetSetting(profile, a, b)
		elseif action == "Create" then
			local made, msg = PlayerData.CreateSlot(profile, a, b)
			if not made then
				Remotes.Notify:FireClient(player, msg or "Can't create that")
			end
			sendMenu(profile)
		elseif action == "Delete" then
			local gone, msg = PlayerData.DeleteSlot(profile, a)
			if not gone then
				Remotes.Notify:FireClient(player, msg or "Can't delete that")
			end
			sendMenu(profile)
		elseif action == "Play" then
			if not profile.Active and PlayerData.Select(profile, a) then
				profile.OnInventoryChanged = function()
					sync(profile)
				end
				enterWorld(player, profile)
			end
		elseif action == "ExitToMenu" then
			if profile.Active then
				PlayerData.Deselect(player)
				if player.Character then
					player.Character:Destroy()
				end
				lastAction[player] = nil
				sendMenu(profile)
			end
		end
	end, debug.traceback)
	profile.Busy = false
	if not ok then
		warn("[Game] menu action '" .. action .. "' failed: " .. tostring(err))
	end
end)

-- ===== Gameplay remotes =====

local warnedUnknown = 0

Remotes.Swing.OnServerEvent:Connect(function(player, direction)
	local profile = PlayerData.GetActive(player)
	if not profile or tooFast(player, Config.SwingCooldown * 0.8) then
		return
	end
	local ok, err = xpcall(function()
		local hit = castFrom(player, direction)
		if not hit then
			return
		end
		local held = heldItem(profile)
		local inst = hit.Instance
		if inst:IsA("Terrain") then
			local def = Items.TerrainMats[hit.Material.Name]
			local item = def and Items.Defs[def.Item]
			Remotes.Hit:FireClient(player, hit.Position, if item then item.Color else Color3.fromRGB(120, 120, 120))
			mining:MineHit(player, profile, hit, held)
		elseif inst:GetAttribute("BlockX") ~= nil then
			local item = Items.Defs[Items.BlockById[inst:GetAttribute("BlockId")]]
			Remotes.Hit:FireClient(player, hit.Position, if item then item.Color else Color3.fromRGB(160, 160, 160))
			building:BreakBlock(player, profile, inst, held)
		else
			local model = Gathering.FindDecoration(inst)
			if model then
				local color = if inst:IsA("BasePart") then inst.Color else Color3.fromRGB(110, 160, 80)
				Remotes.Hit:FireClient(player, hit.Position, color)
				gathering:GatherHit(player, profile, model, held)
			elseif warnedUnknown < 5 then
				warnedUnknown += 1
				warn("[Game] swing hit something that isn't terrain, a block or a decoration: " .. inst:GetFullName())
			end
		end
	end, debug.traceback)
	if not ok then
		warn("[Game] swing error: " .. tostring(err))
	end
end)

Remotes.Place.OnServerEvent:Connect(function(player, direction)
	local profile = PlayerData.GetActive(player)
	if not profile or tooFast(player, 0.2) then
		return
	end
	local hit = castFrom(player, direction)
	if hit then
		local ok, err = xpcall(function()
			building:Place(player, profile, hit, profile.Data.Selected)
		end, debug.traceback)
		if not ok then
			warn("[Game] place error: " .. tostring(err))
		end
	end
end)

Remotes.SelectSlot.OnServerEvent:Connect(function(player, slot)
	local profile = PlayerData.GetActive(player)
	if profile and type(slot) == "number" and slot == math.floor(slot) and slot >= 1 and slot <= Config.HotbarSize then
		profile.Data.Selected = slot
		profile.Dirty = true
	end
end)

Remotes.MoveSlot.OnServerEvent:Connect(function(player, from, to)
	local profile = PlayerData.GetActive(player)
	if profile and validSlot(from) and validSlot(to) then
		profile.Inventory:Move(from, to)
		sync(profile) -- also refresh if nothing changed, so the client's pick snaps back
	end
end)

Remotes.DropSlot.OnServerEvent:Connect(function(player, slot)
	local profile = PlayerData.GetActive(player)
	if profile and validSlot(slot) then
		profile.Inventory:Clear(slot)
	end
end)

Remotes.Craft.OnServerEvent:Connect(function(player, recipeId)
	local profile = PlayerData.GetActive(player)
	local recipe = type(recipeId) == "string" and recipesById[recipeId]
	if not profile or not recipe then
		return
	end
	local ok, err = profile.Inventory:Craft(recipe)
	if ok then
		PlayerData.AddStat(profile, "Crafted", 1)
		Remotes.Notify:FireClient(player, "Crafted " .. Items.Defs[recipe.Out[1]].Name)
	else
		Remotes.Notify:FireClient(player, err or "Can't craft that")
	end
end)

-- ===== Go =====

PlayerData.Start()
Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)
Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
	ready[player] = nil
end)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

print(("[Game] Ready. World seed %d"):format(world:GetSeed()))
