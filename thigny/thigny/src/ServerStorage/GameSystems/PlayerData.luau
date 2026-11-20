--[[
	Per-player save data in a DataStore: an ACCOUNT record holding 3 character slots + settings.

	Key:     Player_<UserId>   in DataStore GameConfig.PlayerDataStoreName
	Record:  { Version = 2, Slots = { ["1"] = slot, ["2"] = slot, ["3"] = slot }, Settings = {...} }
	Slot:    { Name, Created, LastPlayed, PlayTime, Inventory, Stats, Selected, Position }
	Safety:  session lock (two servers never write the same player), UpdateAsync, retries,
	         autosave, save on leave / exit-to-menu / server shutdown.

	Flow:
		local profile = PlayerData.Load(player)           -- the account (yields; nil = kick)
		PlayerData.CreateSlot / DeleteSlot / SetSettings   -- menu actions
		PlayerData.Select(profile, slotNumber)             -- makes that slot active
		profile.Inventory / profile.Data                   -- the ACTIVE slot (nil until selected)
		PlayerData.GetActive(player)                       -- profile, only while a slot is active
		PlayerData.Deselect(player)                        -- save + back to the menu
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Inventory = require(script.Parent.Inventory)

local JOB = if game.JobId == "" then "studio" else game.JobId
local SLOTS = Config.SaveSlots

local PlayerData = {}
local profiles = {} -- [Player] = profile
local store = DataStoreService:GetDataStore(Config.PlayerDataStoreName)
local offline = false -- set when DataStore API access is disabled (Studio setting)
local started = false

-- ===== Defaults / migration =====

local function defaultSettings()
	return { UIScale = 2, Tips = true, ReducedMotion = false, ShowFps = false }
end

local function newSlot(name: string)
	return {
		Name = name,
		Created = os.time(),
		LastPlayed = os.time(),
		PlayTime = 0,
		Inventory = {},
		Stats = { Mined = 0, Chopped = 0, Placed = 0, Crafted = 0 },
		Selected = 1,
	}
end

local function template()
	return { Version = 2, Slots = {}, Settings = defaultSettings() }
end

-- Old (version 1) saves were a single character; keep it as slot 1.
local function migrate(data)
	if data.Version == 2 and data.Slots then
		data.Settings = data.Settings or defaultSettings()
		return data
	end
	local out = template()
	if data.Inventory or data.Stats then
		local slot = newSlot("Player")
		slot.Inventory = data.Inventory or {}
		slot.Stats = data.Stats or slot.Stats
		slot.Selected = data.Selected or 1
		slot.Position = data.Position
		out.Slots["1"] = slot
	end
	return out
end

local function dsKey(player: Player)
	return "Player_" .. player.UserId
end

local function isStudioApiError(err)
	local s = tostring(err)
	return s:find("StudioAccessToApisNotAllowed") ~= nil or s:find("Studio access to APIs is not allowed") ~= nil
end

local function goOffline()
	if not offline then
		offline = true
		warn("[PlayerData] DataStore unavailable (enable Game Settings > Security > Studio Access to API Services). Progress will NOT be saved.")
	end
end

local function waitBudget(requestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < 30 do
		task.wait(1)
		waited += 1
	end
end

local function lockedByOther(old): boolean
	local lock = old and old.Lock
	return lock ~= nil and lock.Job ~= JOB and (os.time() - lock.Time) < Config.SessionLockSeconds
end

-- ===== Load =====

-- Yields. Returns the account profile, or nil, reason if it could not be loaded safely.
function PlayerData.Load(player: Player)
	local data
	local failReason = "unknown"
	if not offline then
		for attempt = 1, 8 do
			local locked = false
			waitBudget(Enum.DataStoreRequestType.UpdateAsync)
			local ok, res = pcall(function()
				return store:UpdateAsync(dsKey(player), function(old)
					if lockedByOther(old) then
						locked = true
						return nil
					end
					old = if old then migrate(old) else template()
					old.Lock = { Job = JOB, Time = os.time() }
					return old
				end)
			end)
			if ok and not locked then
				data = res
				break
			elseif ok and locked then
				failReason = "save is locked by another session (wait ~2 minutes after leaving another server or a crashed test)"
				warn(("[PlayerData] %s: %s (attempt %d)"):format(player.Name, failReason, attempt))
				task.wait(3)
			else
				if isStudioApiError(res) then
					goOffline()
					break
				end
				failReason = tostring(res)
				warn(("[PlayerData] load failed for %s (attempt %d): %s"):format(player.Name, attempt, failReason))
				task.wait(2)
			end
		end
		if not data and not offline then
			if RunService:IsStudio() then
				warn("[PlayerData] Studio fallback: temporary UNSAVED profile. Reason: " .. failReason)
				data = template()
				data.NoSave = true
			else
				return nil, failReason
			end
		end
	end

	data = migrate(data or template())
	local profile = {
		Player = player,
		Account = data,
		Settings = data.Settings,
		Slot = nil, -- active slot number
		Data = nil, -- active slot record
		Inventory = nil, -- active slot inventory
		Active = false,
		Dirty = false,
		Released = false,
		SessionStart = os.clock(),
		OnInventoryChanged = nil,
	}

	if not player.Parent then
		PlayerData._write(profile, true)
		return nil, "left"
	end
	profiles[player] = profile
	return profile
end

function PlayerData.Get(player: Player)
	return profiles[player]
end

function PlayerData.GetActive(player: Player)
	local p = profiles[player]
	return if p and p.Active and not p.Released then p else nil
end

function PlayerData.AddStat(profile, name: string, amount: number?)
	if not profile.Data then
		return
	end
	profile.Data.Stats[name] = (profile.Data.Stats[name] or 0) + (amount or 1)
	profile.Dirty = true
end

-- ===== Menu actions =====

local function cleanName(name: any): string?
	if type(name) ~= "string" then
		return nil
	end
	name = name:gsub("[^%w _%-]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #name < 1 then
		return nil
	end
	return name:sub(1, 12)
end

local function slotKey(n: any): string?
	if type(n) == "number" and n == math.floor(n) and n >= 1 and n <= SLOTS then
		return tostring(n)
	end
	return nil
end

-- Compact list for the menu: array [1..SLOTS] of false | {name, played, playTime, mined, chopped, placed}
function PlayerData.Summaries(profile)
	local out = {}
	for i = 1, SLOTS do
		local s = profile.Account.Slots[tostring(i)]
		out[i] = if s
			then {
				name = s.Name,
				played = s.LastPlayed,
				playTime = s.PlayTime,
				mined = s.Stats.Mined or 0,
				chopped = s.Stats.Chopped or 0,
				placed = s.Stats.Placed or 0,
			}
			else false
	end
	return out
end

function PlayerData.CreateSlot(profile, n: any, name: any): (boolean, string?)
	local key, clean = slotKey(n), cleanName(name)
	if not key then
		return false, "Bad slot"
	end
	if not clean then
		return false, "Enter a name"
	end
	if profile.Account.Slots[key] then
		return false, "Slot already used"
	end
	profile.Account.Slots[key] = newSlot(clean)
	profile.Dirty = true
	return true
end

function PlayerData.DeleteSlot(profile, n: any): (boolean, string?)
	local key = slotKey(n)
	if not key or not profile.Account.Slots[key] then
		return false, "Nothing to delete"
	end
	if profile.Active and profile.Slot == tonumber(key) then
		return false, "Slot in use"
	end
	profile.Account.Slots[key] = nil
	profile.Dirty = true
	return true
end

local SETTING_RULES = {
	UIScale = function(v) return type(v) == "number" and v >= 1 and v <= 3 and v == math.floor(v) end,
	Tips = function(v) return type(v) == "boolean" end,
	ReducedMotion = function(v) return type(v) == "boolean" end,
	ShowFps = function(v) return type(v) == "boolean" end,
}

function PlayerData.SetSetting(profile, key: any, value: any): boolean
	local rule = type(key) == "string" and SETTING_RULES[key]
	if not rule or not rule(value) then
		return false
	end
	profile.Settings[key] = value
	profile.Dirty = true
	return true
end

-- Makes a slot the active character. Returns true on success.
function PlayerData.Select(profile, n: any): boolean
	local key = slotKey(n)
	local slot = key and profile.Account.Slots[key]
	if not slot or profile.Active then
		return false
	end
	slot.Inventory = slot.Inventory or {}
	slot.Stats = slot.Stats or { Mined = 0, Chopped = 0, Placed = 0, Crafted = 0 }
	slot.Selected = slot.Selected or 1

	profile.Slot = tonumber(key)
	profile.Data = slot
	profile.Inventory = Inventory.new(slot.Inventory)
	profile.Inventory.Changed = function()
		profile.Dirty = true
		if profile.OnInventoryChanged then
			profile.OnInventoryChanged()
		end
	end
	profile.SessionStart = os.clock()
	profile.Active = true
	return true
end

-- ===== Saving =====

local function capture(profile)
	local d = profile.Data
	if not d then
		return
	end
	d.Inventory = profile.Inventory:Serialize()
	local char = profile.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local p = root.Position
		d.Position = { math.floor(p.X * 10) / 10, math.floor(p.Y * 10) / 10, math.floor(p.Z * 10) / 10 }
	end
	d.PlayTime = (d.PlayTime or 0) + math.floor(os.clock() - profile.SessionStart)
	profile.SessionStart = os.clock()
	d.LastPlayed = os.time()
end

-- Writes the account. release = true also drops the session lock. Yields. Returns true on success.
function PlayerData._write(profile, release: boolean): boolean
	if offline or profile.Account.NoSave then
		return false
	end
	capture(profile)
	local account = profile.Account
	for attempt = 1, 4 do
		waitBudget(Enum.DataStoreRequestType.UpdateAsync)
		local lostLock = false
		local ok, err = pcall(function()
			store:UpdateAsync(dsKey(profile.Player), function(old)
				if lockedByOther(old) then
					lostLock = true
					return nil -- never overwrite data another server owns
				end
				local out = table.clone(account)
				out.Lock = if release then nil else { Job = JOB, Time = os.time() }
				return out
			end)
		end)
		if ok and lostLock then
			warn("[PlayerData] lost the session lock for " .. profile.Player.Name .. "; not saving")
			return false
		elseif ok then
			profile.Dirty = false
			return true
		end
		if isStudioApiError(err) then
			goOffline()
			return false
		end
		warn(("[PlayerData] save failed for %s (attempt %d): %s"):format(profile.Player.Name, attempt, tostring(err)))
		task.wait(2 ^ attempt * 0.5)
	end
	return false
end

-- Saves and returns to the menu (keeps the account loaded and locked)
function PlayerData.Deselect(player: Player)
	local profile = profiles[player]
	if not profile or not profile.Active then
		return
	end
	PlayerData._write(profile, false)
	profile.Active = false
	profile.OnInventoryChanged = nil
	profile.Slot, profile.Data, profile.Inventory = nil, nil, nil
end

function PlayerData.Release(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	profile.Released = true
	profile.OnInventoryChanged = nil
	profile.Active = false -- stop the game systems before the final write
	PlayerData._write(profile, true)
	profiles[player] = nil
end

function PlayerData.Start()
	if started then
		return
	end
	started = true

	Players.PlayerRemoving:Connect(function(player)
		PlayerData.Release(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for _, profile in profiles do
				if not profile.Released then
					PlayerData._write(profile, false)
					task.wait(0.25)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				PlayerData.Release(player)
				pending -= 1
			end)
		end
		local waited = 0
		while pending > 0 and waited < 25 do
			task.wait(0.25)
			waited += 0.25
		end
	end)
end

return PlayerData
