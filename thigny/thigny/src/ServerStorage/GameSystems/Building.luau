--[[
	Placing and breaking grid blocks (Minecraft-style cubes). Server authoritative.

	Placed blocks are stored by the world framework (World:PlaceBlock / RemoveBlock), which saves them
	per chunk in the same DataStore records as terrain edits.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("GameConfig"))
local PlayerData = require(script.Parent.PlayerData)

local VS = Config.BlockSize

local Building = {}
Building.__index = Building

function Building.new(world, remotes)
	local self = setmetatable({}, Building)
	self.World = world
	self.Remotes = remotes
	world:SetBlockBuilder(Building.MakePart)
	return self
end

-- Used by the world to create the visual for a saved block id
function Building.MakePart(blockId: number): Part?
	local itemId = Items.BlockById[blockId]
	local def = itemId and Items.Defs[itemId].Block
	if not def then
		return nil
	end
	local part = Instance.new("Part")
	part.Material = def.Material
	part.Color = def.Color
	part.Transparency = def.Transparency or 0
	return part
end

local function cellOf(p: Vector3): (number, number, number)
	return math.floor(p.X / VS), math.floor(p.Y / VS), math.floor(p.Z / VS)
end

local function cellCenter(gx: number, gy: number, gz: number): Vector3
	return Vector3.new((gx + 0.5) * VS, (gy + 0.5) * VS, (gz + 0.5) * VS)
end

-- Is the terrain in this cell solid enough to block placing?
local function terrainBlocks(gx: number, gy: number, gz: number): boolean
	local min = Vector3.new(gx * VS, gy * VS, gz * VS)
	local region = Region3.new(min, min + Vector3.one * VS)
	local mats, occs = workspace.Terrain:ReadVoxels(region, VS)
	local mat, occ = mats[1][1][1], occs[1][1][1]
	return mat ~= Enum.Material.Air and mat ~= Enum.Material.Water and occ > 0.5
end

local function playerInCell(center: Vector3): boolean
	local chars = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			chars[#chars + 1] = p.Character
		end
	end
	if #chars == 0 then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = chars
	return #workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.one * (VS - 0.4), params) > 0
end

-- part: a placed Block part that was hit. Several swings may be needed.
function Building:BreakBlock(player: Player, profile, part: BasePart, heldId: string?)
	local gx, gy, gz = part:GetAttribute("BlockX"), part:GetAttribute("BlockY"), part:GetAttribute("BlockZ")
	if gx == nil then
		return
	end
	local itemId = Items.BlockById[part:GetAttribute("BlockId")]

	local power = Items.SwingPower(heldId, "Pickaxe")
	local hp = (part:GetAttribute("HP") or 3) - power
	if hp > 0 then
		part:SetAttribute("HP", hp)
		return
	end

	if itemId and profile.Inventory:Overflow(itemId, 1) > 0 then
		part:SetAttribute("HP", 1)
		self.Remotes.Notify:FireClient(player, "Inventory full")
		return
	end
	local removed = self.World:RemoveBlock(gx, gy, gz)
	if removed and itemId then
		profile.Inventory:Add(itemId, 1)
	end
end

-- hit: RaycastResult the player aimed at; slot: hotbar slot being held
function Building:Place(player: Player, profile, hit: RaycastResult, slot: number)
	local stack = profile.Inventory:Get(slot)
	local def = stack and Items.Defs[stack.id]
	if not def or not def.Block then
		return
	end

	local gx, gy, gz
	local bx = hit.Instance:GetAttribute("BlockX")
	if bx ~= nil then
		-- Aimed at another placed block: build on the face that was hit
		gx = bx + math.round(hit.Normal.X)
		gy = hit.Instance:GetAttribute("BlockY") + math.round(hit.Normal.Y)
		gz = hit.Instance:GetAttribute("BlockZ") + math.round(hit.Normal.Z)
	else
		gx, gy, gz = cellOf(hit.Position + hit.Normal * (VS * 0.5))
	end

	local center = cellCenter(gx, gy, gz)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - center).Magnitude > Config.ReachStuds + 6 then
		self.Remotes.Notify:FireClient(player, "Too far away")
		return
	end
	if self.World:GetBlock(gx, gy, gz) ~= nil or terrainBlocks(gx, gy, gz) then
		self.Remotes.Notify:FireClient(player, "Space is taken")
		return
	end
	if playerInCell(center) then
		self.Remotes.Notify:FireClient(player, "Someone is in the way")
		return
	end

	local ok, err = self.World:PlaceBlock(gx, gy, gz, def.Block.Id)
	if not ok then
		self.Remotes.Notify:FireClient(player, err or "Can't build there")
		return
	end

	-- Take the item (the slot may have changed while PlaceBlock yielded)
	local cur = profile.Inventory:Get(slot)
	if cur and cur.id == stack.id then
		profile.Inventory:TakeOneFromSlot(slot)
	elseif not profile.Inventory:Remove(stack.id, 1) then
		self.World:RemoveBlock(gx, gy, gz)
		return
	end
	PlayerData.AddStat(profile, "Placed", 1)
end

return Building
