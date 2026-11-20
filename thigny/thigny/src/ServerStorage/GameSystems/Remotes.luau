--[[
	Creates ReplicatedStorage.GameRemotes with one RemoteEvent per name in GameConfig.Remotes
	and returns them as a table: Remotes.Swing, Remotes.Place, ...
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local folder = ReplicatedStorage:FindFirstChild("GameRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "GameRemotes"
	folder.Parent = ReplicatedStorage
end

local remotes = {}
for _, name in Config.Remotes do
	local ev = folder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	remotes[name] = ev
end

return remotes
