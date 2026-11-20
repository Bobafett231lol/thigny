--[[
	Shared tuning values for the game systems (inventory, mining, building).
	Both server and client read this.
]]

return {
	-- Inventory
	SlotCount = 36, -- slots 1..HotbarSize are the hotbar
	HotbarSize = 9,

	-- Interaction
	ReachStuds = 22, -- how far a player can mine / place / gather
	SwingCooldown = 0.3, -- seconds between swings (server enforced)
	DigRadius = 4.5, -- studs carved out of terrain per fully mined spot
	DigCell = 4, -- terrain mining progress is tracked per 4-stud cell

	-- Building
	BlockSize = 4, -- grid size of placed blocks (matches terrain voxels)
	MaxBlocksPerChunk = 6000,

	-- Saving
	PlayerDataStoreName = "PlayerData_v1", -- same key as before; old saves migrate into slot 1
	SaveSlots = 3,
	WorldTopY = 256, -- ChunkHeight (64) * 4 studs: the top of the generated world
	AutosaveInterval = 60,
	SessionLockSeconds = 120, -- a lock older than this is considered stale (crashed server)

	-- Remote names (created by the server under ReplicatedStorage.GameRemotes)
	Remotes = {
		"InventoryUpdate", -- server -> client: full inventory snapshot
		"Notify", -- server -> client: small text messages
		"Swing", -- client -> server: mine / gather / break block (direction)
		"Place", -- client -> server: place a block (position hint)
		"MoveSlot", -- client -> server: swap/merge two slots
		"Craft", -- client -> server: craft a recipe
		"DropSlot", -- client -> server: trash a slot
		"SelectSlot", -- client -> server: change held hotbar slot
		"Ready", -- client -> server: UI is connected, send me my menu data + inventory
		"MenuState", -- server -> client: save slot summaries + settings
		"MenuAction", -- client -> server: Play / Create / Delete / Setting / ExitToMenu
		"EnterWorld", -- server -> client: character is placed on solid ground, hide the loading screen
		"Hit", -- server -> client: a swing landed (position, kind) for feedback
	},
}
