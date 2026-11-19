--[[
	DataStore persistence.

	Keys (per world):
	  <WorldId>:meta        { Seed, ChunkSize, ChunkHeight, SeaLevel, GeneratorVersion, Created,
	                          LastSaved, Custom = {...}, Edited = { ["cx,cz"] = true } }
	  <WorldId>:c:<cx>,<cz> { e = {x,y,z,r,mat, x,y,z,r,mat, ...}, d = {removedDecoIds...} }

	The terrain itself is NEVER stored - it is regenerated from the seed. Only chunks that
	have player edits get a record, and the Edited index in meta means pristine chunks cost
	zero DataStore requests.

	Assumes ONE server owns a given WorldId at a time (private server, per-player island,
	or a single public server). Add a session lock if several servers could write the same world.
]]

local DataStoreService = game:GetService("DataStoreService")

local Store = {}
Store.__index = Store

local function chunkKey(cx, cz)
	return string.format("%d,%d", cx, cz)
end

local function newChunkData()
	return { Edits = {}, Removed = {} }
end

local function decode(raw)
	local data = newChunkData()
	if raw then
		local e = raw.e or {}
		for i = 1, #e, 5 do
			data.Edits[#data.Edits + 1] = { e[i], e[i + 1], e[i + 2], e[i + 3], e[i + 4] }
		end
		for _, id in raw.d or {} do
			data.Removed[id] = true
		end
	end
	return data
end

local function encode(data)
	local e, d = {}, {}
	for _, edit in data.Edits do
		for k = 1, 5 do
			e[#e + 1] = edit[k]
		end
	end
	for id in data.Removed do
		d[#d + 1] = id
	end
	table.sort(d)
	return { e = e, d = d }
end

function Store.new(config)
	local self = setmetatable({}, Store)
	self.Config = config
	self.WorldId = config.WorldId
	self.Chunks = {} -- key -> {Edits, Removed}
	self.Pending = {} -- key -> true while fetching
	self.Index = {} -- key -> true (chunks that have a saved record)
	self.Dirty = {} -- key -> true
	self.Meta = nil
	self.MetaDirty = false
	self.Offline = false
	self.DS = if config.SavingEnabled then DataStoreService:GetDataStore(config.DataStoreName) else nil
	return self
end

function Store:_metaKey()
	return self.WorldId .. ":meta"
end

function Store:_chunkDSKey(key)
	return self.WorldId .. ":c:" .. key
end

function Store:_canIO()
	return self.DS ~= nil and not self.Offline
end

function Store:_retry(label, fn)
	local lastErr
	for attempt = 1, 4 do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = tostring(res)
		if lastErr:find("StudioAccessToApisNotAllowed") or lastErr:find("Studio access to APIs is not allowed") then
			if not self.Offline then
				warn("[WorldStore] DataStore unavailable (enable Game Settings > Security > Enable Studio Access to API Services). Running UNSAVED.")
			end
			self.Offline = true
			return false, lastErr
		end
		warn(string.format("[WorldStore] %s failed (attempt %d): %s", label, attempt, lastErr))
		task.wait(2 ^ attempt * 0.5)
	end
	return false, lastErr
end

function Store:_waitBudget(requestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < 60 do
		task.wait(1)
		waited += 1
	end
end

-- Returns ok, meta(or nil if this is a brand-new world)
function Store:LoadMeta()
	if not self:_canIO() then
		return true, nil
	end
	self:_waitBudget(Enum.DataStoreRequestType.GetAsync)
	local ok, res = self:_retry("load meta", function()
		return self.DS:GetAsync(self:_metaKey())
	end)
	if not ok then
		if self.Offline then
			return true, nil
		end
		return false, res
	end
	self.Meta = res
	if res and res.Edited then
		self.Index = res.Edited
	end
	return true, res
end

function Store:PutMeta(meta)
	self.Meta = meta
	self.MetaDirty = true
end

function Store:MarkMetaDirty()
	self.MetaDirty = true
end

-- Non-yielding. Returns chunk data, or nil if it's still being fetched.
function Store:TryGetChunk(cx, cz)
	local key = chunkKey(cx, cz)
	local data = self.Chunks[key]
	if data then
		return data
	end
	if not self.Index[key] or not self:_canIO() then
		data = newChunkData()
		self.Chunks[key] = data
		return data
	end
	if not self.Pending[key] then
		self.Pending[key] = true
		task.spawn(function()
			self:_waitBudget(Enum.DataStoreRequestType.GetAsync)
			local ok, res = self:_retry("load chunk " .. key, function()
				return self.DS:GetAsync(self:_chunkDSKey(key))
			end)
			if ok then
				self.Chunks[key] = decode(res)
			else
				task.wait(5) -- try again on a later streaming pass
			end
			self.Pending[key] = nil
		end)
	end
	return nil
end

-- Yielding version
function Store:GetChunk(cx, cz)
	local data = self:TryGetChunk(cx, cz)
	while not data do
		task.wait(0.1)
		data = self:TryGetChunk(cx, cz)
	end
	return data
end

function Store:MarkDirty(cx, cz)
	local key = chunkKey(cx, cz)
	self.Dirty[key] = true
	if not self.Index[key] then
		self.Index[key] = true
		self.MetaDirty = true
	end
end

-- Writes all dirty chunks + meta. Yields. Returns true if everything was written.
function Store:Flush()
	if not self:_canIO() then
		return false
	end
	local allOk = true

	local keys = {}
	for key in self.Dirty do
		keys[#keys + 1] = key
	end

	for _, key in keys do
		local data = self.Chunks[key]
		if data then
			local payload = encode(data)
			self:_waitBudget(Enum.DataStoreRequestType.SetIncrementAsync)
			local ok = self:_retry("save chunk " .. key, function()
				self.DS:SetAsync(self:_chunkDSKey(key), payload)
			end)
			if ok then
				self.Dirty[key] = nil
			else
				allOk = false
			end
		else
			self.Dirty[key] = nil
		end
	end

	if self.MetaDirty and self.Meta then
		self.Meta.Edited = self.Index
		self:_waitBudget(Enum.DataStoreRequestType.SetIncrementAsync)
		local ok = self:_retry("save meta", function()
			self.DS:SetAsync(self:_metaKey(), self.Meta)
		end)
		if ok then
			self.MetaDirty = false
		else
			allOk = false
		end
	end
	return allOk
end

return Store
