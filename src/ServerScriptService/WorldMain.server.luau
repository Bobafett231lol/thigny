--[[
	Example bootstrap: one shared, saved world. Players spawn on land near the origin.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local World = require(ServerStorage:WaitForChild("WorldFramework"))

Players.CharacterAutoLoads = false

local world = World.new({
	WorldId = "Main",
	ViewDistance = 5,
	-- Seed = 12345,             -- optional fixed seed (only used when creating a new save)
	-- AutosaveInterval = 30,
})

world:Load()

-- Spawn point is saved in the world's meta so it stays put across sessions
local spawn = world:GetMeta("Spawn")
local spawnPos
if spawn then
	spawnPos = Vector3.new(spawn[1], spawn[2], spawn[3])
else
	spawnPos = world:FindLandNear(0, 0)
	world:SetMeta("Spawn", { spawnPos.X, spawnPos.Y, spawnPos.Z })
end

world:Start()
world:PreloadAround(spawnPos, 2) -- make sure there's ground before anyone spawns

local function spawnPlayer(player: Player)
	player:LoadCharacter()
	local char = player.Character
	if char then
		char:PivotTo(CFrame.new(spawnPos + Vector3.new(0, 12, 0)))
	end
end

Players.PlayerAdded:Connect(spawnPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(spawnPlayer, p)
end

print(("[World] Ready. Seed %d"):format(world:GetSeed()))

--[[ Usage examples
	world:ModifyTerrain(Vector3.new(0, 90, 0), 10, Enum.Material.Air)       -- dig a crater (saved)
	world:ModifyTerrain(pos, 6, Enum.Material.Brick)                        -- build a blob (saved)
	print(world:GetBiomeAt(somePlayerRoot.Position))
	world:RemoveDecoration(someTreePart)                                    -- chop a tree (saved)
	world:Save()                                                            -- force a save
]]
