--[[
	Resource gathering from world decorations (trees, rocks, bushes, cactus).
	A decoration is any model with a DecoType attribute (set by WorldFramework's Decorator).
	Breaking one gives the drops in Items.Gather and removes it permanently (saved by the world).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local PlayerData = require(script.Parent.PlayerData)

local Gathering = {}
Gathering.__index = Gathering

function Gathering.new(world, remotes)
	local self = setmetatable({}, Gathering)
	self.World = world
	self.Remotes = remotes
	return self
end

-- Finds the decoration model that owns an instance, or nil
function Gathering.FindDecoration(inst: Instance): Model?
	local cur = inst
	while cur and cur ~= workspace do
		if cur:GetAttribute("DecoId") ~= nil then
			return cur :: Model
		end
		cur = cur.Parent
	end
	return nil
end

function Gathering:GatherHit(player: Player, profile, model: Model, heldId: string?)
	local def = Items.Gather[model:GetAttribute("DecoType")]
	if not def then
		self.Remotes.Notify:FireClient(player, "Nothing to gather here")
		warn("[Gathering] no Items.Gather entry for decoration type: " .. tostring(model:GetAttribute("DecoType")))
		return
	end

	local power = Items.SwingPower(heldId, def.Tool)
	local hp = (model:GetAttribute("HP") or def.HP) - power
	if hp > 0 then
		model:SetAttribute("HP", hp)
		return
	end

	-- Roll drops, and refuse (without breaking it) if they will not fit
	local drops = {}
	for _, d in def.Drops do
		local n = math.random(d[2], d[3])
		if n > 0 then
			if profile.Inventory:Overflow(d[1], n) > 0 then
				model:SetAttribute("HP", 1)
				self.Remotes.Notify:FireClient(player, "Inventory full")
				return
			end
			drops[#drops + 1] = { d[1], n }
		end
	end

	-- Remove it first (this saves the removal and can yield); only pay out if WE removed it
	if not model.Parent or not self.World:RemoveDecoration(model) then
		return
	end
	for _, d in drops do
		profile.Inventory:Add(d[1], d[2])
	end
	PlayerData.AddStat(profile, "Chopped", 1)
end

return Gathering
