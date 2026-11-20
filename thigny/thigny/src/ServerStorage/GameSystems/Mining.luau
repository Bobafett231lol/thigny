--[[
	Mining / digging terrain. Server authoritative.

	Each 4-stud cell of terrain has hit points (from Items.TerrainMats). Every swing does damage based on
	the held tool. When the cell breaks, the player gets the drop and a sphere of terrain is carved out
	through world:ModifyTerrain (which the world framework saves to its DataStore).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("GameConfig"))
local PlayerData = require(script.Parent.PlayerData)

local Mining = {}
Mining.__index = Mining

local PROGRESS_TTL = 4 -- seconds before a half-mined cell heals
local BEDROCK_Y = 4 -- studs; terrain below this is the unbreakable world floor

function Mining.new(world, remotes)
	local self = setmetatable({}, Mining)
	self.World = world
	self.Remotes = remotes
	self.Progress = {} -- cellKey -> { hp, t }
	self.Count = 0
	return self
end

function Mining:_purge(now: number)
	if self.Count < 300 then
		return
	end
	for k, e in self.Progress do
		if now - e.t > PROGRESS_TTL then
			self.Progress[k] = nil
			self.Count -= 1
		end
	end
end

-- hit: RaycastResult against Terrain. heldId: item id in the selected slot (or nil).
function Mining:MineHit(player: Player, profile, hit: RaycastResult, heldId: string?)
	local def = Items.TerrainMats[hit.Material.Name]
	if not def then
		self.Remotes.Notify:FireClient(player, "You can't mine that")
		return
	end

	local power, tier = Items.SwingPower(heldId, def.Tool)
	if tier < def.Tier then
		self.Remotes.Notify:FireClient(player, ("Needs a better %s"):format(def.Tool:lower()))
		return
	end

	-- A point just inside the surface that was hit
	local inside = hit.Position - hit.Normal * 1.5
	local cs = Config.DigCell
	local key = string.format("%d,%d,%d", math.floor(inside.X / cs), math.floor(inside.Y / cs), math.floor(inside.Z / cs))

	local now = os.clock()
	self:_purge(now)
	local entry = self.Progress[key]
	if not entry or now - entry.t > PROGRESS_TTL then
		if not entry then
			self.Count += 1
		end
		entry = { hp = def.HP, t = now }
		self.Progress[key] = entry
	end
	entry.t = now
	entry.hp -= power
	if entry.hp > 0 then
		return
	end

	-- Broke it. Make sure the drop fits before carving anything.
	local amount = math.random(def.Min, def.Max)
	if profile.Inventory:Overflow(def.Item, amount) > 0 then
		entry.hp = 1
		self.Remotes.Notify:FireClient(player, "Inventory full")
		return
	end
	self.Progress[key] = nil
	self.Count -= 1

	profile.Inventory:Add(def.Item, amount)
	PlayerData.AddStat(profile, "Mined", 1)

	local radius = Config.DigRadius
	local center = Vector3.new(inside.X, math.max(inside.Y, BEDROCK_Y + radius), inside.Z)
	self.World:ModifyTerrain(center, radius, Enum.Material.Air)
end

return Mining
