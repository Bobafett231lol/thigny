--[[
	Streams chunks in/out around players (and optional anchors).
	Unloaded chunks are erased from Terrain and re-generated (plus saved edits replayed)
	when needed again, so memory/part counts stay bounded no matter how far players roam.
]]

local Players = game:GetService("Players")

local ChunkManager = {}
ChunkManager.__index = ChunkManager

local function key(cx, cz)
	return string.format("%d,%d", cx, cz)
end

function ChunkManager.new(world)
	local self = setmetatable({}, ChunkManager)
	self.World = world
	self.Loaded = {} -- key -> {cx, cz, folder}
	self.Anchors = {}
	self.Running = false

	self.DecoRoot = Instance.new("Folder")
	self.DecoRoot.Name = "WorldDecorations_" .. world.Config.WorldId
	self.DecoRoot.Parent = workspace

	self._loadedEvent = Instance.new("BindableEvent")
	self._unloadedEvent = Instance.new("BindableEvent")
	self.ChunkLoaded = self._loadedEvent.Event -- (cx, cz)
	self.ChunkUnloaded = self._unloadedEvent.Event -- (cx, cz)
	return self
end

-- Returns true if the chunk is loaded (or just got loaded); false if its save data isn't ready yet.
-- Never yields after the data is available, so it is safe to call from multiple threads.
function ChunkManager:LoadChunk(cx: number, cz: number): boolean
	local k = key(cx, cz)
	if self.Loaded[k] then
		return true
	end
	local world = self.World
	local data = world.Store:TryGetChunk(cx, cz)
	if not data then
		return false
	end

	world.Generator:GenerateChunk(cx, cz, data.Edits)

	local folder = Instance.new("Folder")
	folder.Name = k
	folder.Parent = self.DecoRoot
	if world.Config.Decorations.Enabled then
		world.Decorator:PopulateChunk(cx, cz, folder, data.Removed)
	end

	self.Loaded[k] = { cx = cx, cz = cz, folder = folder }
	self._loadedEvent:Fire(cx, cz)
	return true
end

function ChunkManager:UnloadChunk(cx: number, cz: number)
	local k = key(cx, cz)
	local info = self.Loaded[k]
	if not info then
		return
	end
	self.Loaded[k] = nil
	info.folder:Destroy()
	self.World.Generator:ClearChunk(cx, cz)
	self._unloadedEvent:Fire(cx, cz)
end

function ChunkManager:AddAnchor(position: Vector3)
	local a = { Position = position }
	self.Anchors[a] = true
	return a
end

function ChunkManager:RemoveAnchor(anchor)
	self.Anchors[anchor] = nil
end

function ChunkManager:_centers()
	local list = {}
	local world = self.World
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local cx, cz = world:WorldToChunk(root.Position)
			list[#list + 1] = { cx = cx, cz = cz }
		end
	end
	for a in self.Anchors do
		local cx, cz = world:WorldToChunk(a.Position)
		list[#list + 1] = { cx = cx, cz = cz }
	end
	return list
end

function ChunkManager:Step()
	local cfg = self.World.Config
	local R = cfg.ViewDistance
	local centers = self:_centers()
	if #centers == 0 then
		return
	end

	-- Unload far chunks
	local limit = (R + cfg.UnloadPadding) ^ 2
	for _, info in self.Loaded do
		local dmin = math.huge
		for _, c in centers do
			local dx, dz = c.cx - info.cx, c.cz - info.cz
			dmin = math.min(dmin, dx * dx + dz * dz)
		end
		if dmin > limit then
			self:UnloadChunk(info.cx, info.cz)
		end
	end

	-- Collect wanted chunks, nearest first
	local wanted, seen = {}, {}
	for _, c in centers do
		for dx = -R, R do
			for dz = -R, R do
				local d = dx * dx + dz * dz
				if d <= R * R + 1 then
					local cx, cz = c.cx + dx, c.cz + dz
					local k = key(cx, cz)
					if not self.Loaded[k] then
						local w = seen[k]
						if not w then
							w = { cx = cx, cz = cz, d = d }
							seen[k] = w
							wanted[#wanted + 1] = w
						elseif d < w.d then
							w.d = d
						end
					end
				end
			end
		end
	end
	table.sort(wanted, function(a, b)
		return a.d < b.d
	end)

	local budget = cfg.ChunksPerStep
	for _, w in wanted do
		if budget <= 0 then
			break
		end
		if self:LoadChunk(w.cx, w.cz) then
			budget -= 1
			task.wait() -- spread generation across frames
		end
	end
end

function ChunkManager:Start()
	if self.Running then
		return
	end
	self.Running = true
	task.spawn(function()
		while self.Running do
			self:Step()
			task.wait(self.World.Config.UpdateInterval)
		end
	end)
end

function ChunkManager:Stop()
	self.Running = false
end

-- Blocks until every chunk within `radius` chunks of position is loaded.
function ChunkManager:PreloadAround(position: Vector3, radius: number)
	local ccx, ccz = self.World:WorldToChunk(position)
	local list = {}
	for dx = -radius, radius do
		for dz = -radius, radius do
			list[#list + 1] = { cx = ccx + dx, cz = ccz + dz, d = dx * dx + dz * dz }
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	for _, w in list do
		while not self:LoadChunk(w.cx, w.cz) do
			task.wait(0.1)
		end
		task.wait()
	end
end

function ChunkManager:Destroy()
	self.Running = false
	for _, info in self.Loaded do
		self:UnloadChunk(info.cx, info.cz)
	end
	self.DecoRoot:Destroy()
	self._loadedEvent:Destroy()
	self._unloadedEvent:Destroy()
end

return ChunkManager
