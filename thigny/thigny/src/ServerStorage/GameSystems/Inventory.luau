--[[
	Server-side inventory: a fixed number of slots, each nil/false or { id = itemId, n = count }.
	Pure logic (no Roblox instances), so it is easy to test.

	Saved form is a sparse list: { { s = slot, i = itemId, n = count }, ... }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("GameConfig"))

local N = Config.SlotCount

local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(saved: { any }?)
	local self = setmetatable({}, Inventory)
	self.Slots = table.create(N, false)
	self.Changed = nil -- optional callback, set by whoever owns this inventory
	if saved then
		for _, rec in saved do
			local def = Items.Defs[rec.i]
			if def and type(rec.s) == "number" and rec.s >= 1 and rec.s <= N and type(rec.n) == "number" and rec.n > 0 then
				self.Slots[rec.s] = { id = rec.i, n = math.min(math.floor(rec.n), def.Stack) }
			end
		end
	end
	return self
end

function Inventory:_changed()
	if self.Changed then
		self.Changed()
	end
end

function Inventory:Get(slot: number)
	return self.Slots[slot] or nil
end

function Inventory:Count(id: string): number
	local total = 0
	for _, s in self.Slots do
		if s and s.id == id then
			total += s.n
		end
	end
	return total
end

-- How many of `id` would not fit right now (0 = everything fits)
function Inventory:Overflow(id: string, amount: number): number
	local def = Items.Defs[id]
	if not def then
		return amount
	end
	local room = 0
	for _, s in self.Slots do
		if not s then
			room += def.Stack
		elseif s.id == id then
			room += def.Stack - s.n
		end
	end
	return math.max(0, amount - room)
end

-- Adds items (hotbar first). Returns how many did NOT fit.
function Inventory:Add(id: string, amount: number): number
	local def = Items.Defs[id]
	if not def or amount <= 0 then
		return amount
	end
	local left = amount
	for i = 1, N do
		local s = self.Slots[i]
		if s and s.id == id and s.n < def.Stack then
			local put = math.min(def.Stack - s.n, left)
			s.n += put
			left -= put
			if left <= 0 then
				break
			end
		end
	end
	if left > 0 then
		for i = 1, N do
			if not self.Slots[i] then
				local put = math.min(def.Stack, left)
				self.Slots[i] = { id = id, n = put }
				left -= put
				if left <= 0 then
					break
				end
			end
		end
	end
	if left < amount then
		self:_changed()
	end
	return left
end

-- Removes items (taking from the back of the inventory first). Returns true if it had enough.
function Inventory:Remove(id: string, amount: number): boolean
	if amount <= 0 then
		return true
	end
	if self:Count(id) < amount then
		return false
	end
	local left = amount
	for i = N, 1, -1 do
		local s = self.Slots[i]
		if s and s.id == id then
			local take = math.min(s.n, left)
			s.n -= take
			left -= take
			if s.n <= 0 then
				self.Slots[i] = false
			end
			if left <= 0 then
				break
			end
		end
	end
	self:_changed()
	return true
end

-- Removes one item from a specific slot (e.g. the block being placed). Returns the item id or nil.
function Inventory:TakeOneFromSlot(slot: number): string?
	local s = self.Slots[slot]
	if not s then
		return nil
	end
	local id = s.id
	s.n -= 1
	if s.n <= 0 then
		self.Slots[slot] = false
	end
	self:_changed()
	return id
end

-- Drag-and-drop: merges same items, otherwise swaps.
function Inventory:Move(from: number, to: number)
	if from == to or from < 1 or to < 1 or from > N or to > N then
		return
	end
	local a, b = self.Slots[from], self.Slots[to]
	if not a then
		return
	end
	if b and b.id == a.id then
		local stack = Items.Defs[a.id].Stack
		local put = math.min(stack - b.n, a.n)
		b.n += put
		a.n -= put
		if a.n <= 0 then
			self.Slots[from] = false
		end
	else
		self.Slots[from], self.Slots[to] = b or false, a
	end
	self:_changed()
end

function Inventory:Clear(slot: number)
	if self.Slots[slot] then
		self.Slots[slot] = false
		self:_changed()
	end
end

function Inventory:CanCraft(recipe): boolean
	for _, input in recipe.In do
		if self:Count(input[1]) < input[2] then
			return false
		end
	end
	return true
end

-- Returns ok, errorMessage
function Inventory:Craft(recipe): (boolean, string?)
	if not self:CanCraft(recipe) then
		return false, "Missing materials"
	end
	local backup = table.create(N, false)
	for i, s in self.Slots do
		backup[i] = if s then { id = s.id, n = s.n } else false
	end

	local changed = self.Changed
	self.Changed = nil -- don't spam updates while we remove + add
	for _, input in recipe.In do
		self:Remove(input[1], input[2])
	end
	local leftover = self:Add(recipe.Out[1], recipe.Out[2])
	self.Changed = changed

	if leftover > 0 then
		self.Slots = backup
		return false, "Inventory full"
	end
	self:_changed()
	return true
end

-- Copy for sending to the client: array of false | { id, n }
function Inventory:Snapshot()
	local out = table.create(N, false)
	for i, s in self.Slots do
		if s then
			out[i] = { id = s.id, n = s.n }
		end
	end
	return out
end

function Inventory:Serialize()
	local out = {}
	for i, s in self.Slots do
		if s then
			out[#out + 1] = { s = i, i = s.id, n = s.n }
		end
	end
	return out
end

return Inventory
