-- Runs first on the client: removes Roblox's default loading screen and shows ours immediately.
local ReplicatedFirst = game:GetService("ReplicatedFirst")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local Loading = require(ReplicatedFirst:WaitForChild("Loading"))
Loading.Show("LOADING")
