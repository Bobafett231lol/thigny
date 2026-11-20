--[[
	In-game HUD (8-bit): hotbar, held-item name, notices, FPS counter, MENU button, and the
	inventory + crafting window (E).

	Inventory: all 36 slots are shown (3 storage rows + the hotbar row).
	  click a slot            pick the stack up (it follows your cursor); click another slot to place / swap / merge
	  shift + click           quick-move between hotbar and storage
	  "TRASH" with a stack up deletes it
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Kit = require(ReplicatedFirst:WaitForChild("PixelKit"))
local C = Kit.C

local Hud = {}

local env -- { Remotes, Items, Recipes, Config, onMenu }
local gui, root
local hudU = 4
local Wv, Hv = 320, 200
local settings = { UIScale = 2, Tips = true, ShowFps = false }

local slots = {} -- latest snapshot: false | { id, n }
local selected = 1
local picked: number? = nil
local hovered: number? = nil
local invOpen = false

local hudSlots, invSlots = {}, {}
local invFrame, craftBox, pageLabel
local craftPage = 1
local heldText, fpsText, hintGroup
local ghost, tip
local noticeGroup, noticeToken = nil, 0
local conns = {}

local SLOT, STEP = 18, 19
local PER_PAGE = 6

local function use()
	Kit.U = hudU
end

local function spriteFor(id: string, def)
	if def.Tool then
		return def.Tool.Type
	elseif def.Block then
		return "Block"
	elseif id == "Diamond" then
		return "Gem"
	elseif id == "Stick" then
		return "Stick"
	end
	return "Lump"
end

local function count(id: string): number
	local total = 0
	for _, s in slots do
		if s and s.id == id then
			total += s.n
		end
	end
	return total
end

-- ===== slots =====

local function drawContent(w, d)
	local key = if d then d.id .. ":" .. d.n else ""
	if w.key == key then
		return
	end
	w.key = key
	w.content:ClearAllChildren()
	if not d then
		return
	end
	use()
	local def = env.Items.Defs[d.id]
	if def then
		Kit.icon(w.content, 1, 1, spriteFor(d.id, def), def.Color, 2)
	end
	if d.n > 1 then
		Kit.text(w.content, tostring(d.n), { x = SLOT - 1, y = SLOT - 9, align = "r" })
	end
end

local function setBorder(w, color: Color3)
	for _, f in w.panel.Border do
		f.BackgroundColor3 = color
	end
end

local function makeSlot(parent, x, y, index, hint, onClick)
	local p = Kit.panel(parent, x, y, SLOT, SLOT, { fill = C.dusk, border = C.ink, hi = C.slate, lo = C.ink })
	local w = { panel = p, content = Kit.group(p.Root, 0, 0, SLOT, SLOT), index = index }
	if hint then
		Kit.text(p.Root, hint, { x = 2, y = 1, color = C.silver })
	end
	if onClick then
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 8
		hit.Parent = p.Root
		hit.Activated:Connect(function()
			onClick(index)
		end)
		hit.MouseEnter:Connect(function()
			hovered = index
		end)
		hit.MouseLeave:Connect(function()
			if hovered == index then
				hovered = nil
			end
		end)
	end
	return w
end

local function updateGhost()
	if not ghost then
		return
	end
	use()
	ghost:ClearAllChildren()
	local d = picked and slots[picked]
	if d then
		local def = env.Items.Defs[d.id]
		if def then
			Kit.icon(ghost, 0, 0, spriteFor(d.id, def), def.Color, 2)
		end
	end
	ghost.Visible = d and true or false
end

local rebuildCraft

local function refresh()
	if not gui then
		return
	end
	for i = 1, 9 do
		local w = hudSlots[i]
		if w then
			drawContent(w, slots[i] or nil)
			setBorder(w, if i == selected then C.yellow else C.ink)
		end
	end
	for i = 1, env.Config.SlotCount do
		local w = invSlots[i]
		if w then
			drawContent(w, slots[i] or nil)
			setBorder(w, if i == picked then C.cyan elseif i == selected then C.yellow else C.ink)
		end
	end
	use()
	local held = slots[selected]
	local name = if held and env.Items.Defs[held.id] then env.Items.Defs[held.id].Name else ""
	Kit.setText(heldText, name)
	updateGhost()
	if invOpen then
		rebuildCraft()
	end
end

function Hud.Select(i: number)
	if i < 1 or i > env.Config.HotbarSize then
		return
	end
	selected = i
	env.Remotes.SelectSlot:FireServer(i)
	refresh()
end

local function onInvClick(i: number)
	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	if shift and slots[i] then
		local lo, hi = 10, env.Config.SlotCount
		if i >= 10 then
			lo, hi = 1, 9
		end
		local stack = env.Items.Defs[slots[i].id].Stack
		local empty, same
		for j = lo, hi do
			local s = slots[j]
			if not s then
				empty = empty or j
			elseif s.id == slots[i].id and s.n < stack then
				same = same or j
			end
		end
		local target = same or empty
		if target then
			env.Remotes.MoveSlot:FireServer(i, target)
		end
		picked = nil
	elseif picked == nil then
		if slots[i] then
			picked = i
		end
	elseif picked == i then
		picked = nil
	else
		env.Remotes.MoveSlot:FireServer(picked, i)
		picked = nil
	end
	refresh()
end

-- ===== crafting list =====

local function craftable(r): boolean
	for _, input in r.In do
		if count(input[1]) < input[2] then
			return false
		end
	end
	return true
end

rebuildCraft = function()
	if not craftBox then
		return
	end
	use()
	craftBox:ClearAllChildren()
	local pages = math.ceil(#env.Recipes / PER_PAGE)
	craftPage = math.clamp(craftPage, 1, pages)
	if pageLabel then
		Kit.setText(pageLabel, ("%d/%d"):format(craftPage, pages))
	end
	for k = 1, PER_PAGE do
		local r = env.Recipes[(craftPage - 1) * PER_PAGE + k]
		if not r then
			break
		end
		local ok = craftable(r)
		local row = Kit.panel(craftBox, 0, (k - 1) * 19, 122, 18, {
			fill = if ok then C.teal else C.dusk, border = C.ink, hi = if ok then C.green else C.slate, lo = C.ink,
		})
		local def = env.Items.Defs[r.Out[1]]
		Kit.icon(row.Root, 3, 5, spriteFor(r.Out[1], def), def.Color, 1)
		local name = def.Name .. (if r.Out[2] > 1 then " X" .. r.Out[2] else "")
		Kit.text(row.Root, name, { x = 13, y = 3, color = if ok then C.white else C.silver })
		local needs = {}
		for _, input in r.In do
			needs[#needs + 1] = ("%d %s"):format(input[2], env.Items.Defs[input[1]].Name)
		end
		local line = table.concat(needs, ",")
		Kit.text(row.Root, line:sub(1, 18), { x = 13, y = 10, color = if ok then C.lime else C.slate, shadow = false })
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 8
		hit.Parent = row.Root
		hit.Activated:Connect(function()
			env.Remotes.Craft:FireServer(r.Id)
		end)
	end
end

-- ===== inventory window =====

local function closeInventory()
	invOpen = false
	picked, hovered = nil, nil
	if invFrame then
		invFrame:Destroy()
	end
	invFrame, craftBox, pageLabel = nil, nil, nil
	invSlots = {}
	if tip then
		tip.Visible = false
	end
	refresh()
end

local function openInventory()
	use()
	invOpen = true
	local W, H = 316, 146
	local x0, y0 = math.floor((Wv - W) / 2), math.max(2, math.floor((Hv - H) / 2) - 8)
	invFrame = Kit.group(root, x0, y0, W, H)

	-- storage + hotbar
	local left = Kit.panel(invFrame, 0, 0, 184, H, { fill = C.navy, border = C.ink, hi = C.blue, lo = C.ink })
	Kit.text(left.Root, "INVENTORY", { x = 8, y = 6, color = C.yellow })
	local hb = env.Config.HotbarSize
	for r = 0, 2 do
		for c = 0, 8 do
			local idx = hb + r * 9 + c + 1
			invSlots[idx] = makeSlot(left.Root, 7 + c * STEP, 18 + r * STEP, idx, nil, onInvClick)
		end
	end
	Kit.text(left.Root, "HOTBAR", { x = 8, y = 18 + 3 * STEP + 1, color = C.silver, shadow = false })
	for c = 0, 8 do
		invSlots[c + 1] = makeSlot(left.Root, 7 + c * STEP, 18 + 3 * STEP + 10, c + 1, tostring(c + 1), onInvClick)
	end
	Kit.button(left.Root, "TRASH", 7, 112, 52, 13, function()
		if picked then
			env.Remotes.DropSlot:FireServer(picked)
			picked = nil
			refresh()
		end
	end, { fill = C.plum, hover = C.red, hi = C.red })
	Kit.text(left.Root, "CLICK: PICK UP / PLACE", { x = 7, y = 130, color = C.silver, shadow = false })
	Kit.text(left.Root, "SHIFT+CLICK: QUICK MOVE", { x = 7, y = 138, color = C.silver, shadow = false })

	-- crafting
	local right = Kit.panel(invFrame, 186, 0, 130, H, { fill = C.navy, border = C.ink, hi = C.blue, lo = C.ink })
	Kit.text(right.Root, "CRAFTING", { x = 8, y = 6, color = C.yellow })
	craftBox = Kit.group(right.Root, 4, 18, 122, PER_PAGE * 19)
	pageLabel = Kit.text(right.Root, "1/1", { x = 65, y = 134, align = "c", color = C.white })
	local pages = math.ceil(#env.Recipes / PER_PAGE)
	Kit.button(right.Root, "<", 8, 130, 22, 13, function()
		craftPage = if craftPage <= 1 then pages else craftPage - 1
		use()
		rebuildCraft()
	end)
	Kit.button(right.Root, ">", 100, 130, 22, 13, function()
		craftPage = if craftPage >= pages then 1 else craftPage + 1
		use()
		rebuildCraft()
	end)
	refresh()
end

function Hud.IsInventoryOpen(): boolean
	return invOpen
end

function Hud.ToggleInventory()
	if not gui then
		return
	end
	if invOpen then
		closeInventory()
	else
		openInventory()
	end
end

-- ===== notices =====

function Hud.Notify(text: string)
	if not gui then
		return
	end
	use()
	noticeToken += 1
	local mine = noticeToken
	if noticeGroup then
		noticeGroup:Destroy()
	end
	text = text:upper()
	local w = Kit.textWidth(text, 1) + 14
	noticeGroup = Kit.group(root, math.floor((Wv - w) / 2), 14, w, 15)
	Kit.panel(noticeGroup, 0, 0, w, 15, { fill = C.plum, border = C.ink, hi = C.red, lo = C.ink })
	Kit.text(noticeGroup, text, { x = w / 2, y = 4, align = "c" })
	task.delay(2.2, function()
		if mine == noticeToken and noticeGroup then
			noticeGroup:Destroy()
			noticeGroup = nil
		end
	end)
end

-- ===== 3D hit debris (little square chips) =====

function Hud.Hit(position: Vector3, color: Color3)
	for _ = 1, 5 do
		local p = Instance.new("Part")
		p.Size = Vector3.one * 0.45
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Position = position + Vector3.new(math.random() - 0.5, math.random() * 0.5, math.random() - 0.5)
		p.AssemblyLinearVelocity = Vector3.new(math.random() * 14 - 7, math.random() * 9 + 3, math.random() * 14 - 7)
		p.Parent = workspace
		game:GetService("Debris"):AddItem(p, 0.7)
	end
end

-- ===== build / destroy =====

local function destroy()
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	if gui then
		gui:Destroy()
	end
	gui, root, invFrame, craftBox, pageLabel, noticeGroup = nil, nil, nil, nil, nil, nil
	hudSlots, invSlots = {}, {}
end

local function build()
	destroy()
	local viewport = Kit.viewport()
	hudU = math.max(2, math.floor(viewport.Y / 200) + (settings.UIScale - 2))
	hudU = math.max(2, math.min(hudU, math.floor(viewport.X / 320)))
	use()
	Wv, Hv = math.ceil(viewport.X / hudU), math.ceil(viewport.Y / hudU)

	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	root = Kit.group(gui, 0, 0, Wv, Hv)
	root.Size = UDim2.fromScale(1, 1)

	-- hotbar
	local hb = env.Config.HotbarSize
	local barW = hb * STEP - 1
	local bar = Kit.group(root, math.floor((Wv - barW) / 2), Hv - SLOT - 6, barW, SLOT)
	for i = 1, hb do
		hudSlots[i] = makeSlot(bar, (i - 1) * STEP, 0, i, tostring(i), function(idx)
			Hud.Select(idx)
		end)
	end
	heldText = Kit.text(root, "", { x = Wv / 2, y = Hv - SLOT - 17, align = "c", color = C.white })

	-- top-left FPS, top-right MENU
	fpsText = Kit.text(root, "", { x = 4, y = 4, color = C.lime })
	Kit.button(root, "MENU", Wv - 36, 4, 32, 12, function()
		if env.onMenu then
			env.onMenu()
		end
	end)

	-- controls hint for the first half minute
	if settings.Tips then
		hintGroup = Kit.group(root, 4, Hv - 22, 150, 20)
		Kit.text(hintGroup, "LMB MINE   RMB PLACE", { x = 0, y = 0, color = C.silver })
		Kit.text(hintGroup, "E INVENTORY   1-9 SELECT", { x = 0, y = 9, color = C.silver })
		task.delay(30, function()
			if hintGroup then
				hintGroup:Destroy()
			end
		end)
	end

	-- cursor-following stack + tooltip (always on top)
	ghost = Kit.group(root, 0, 0, 16, 16)
	ghost.Visible = false
	ghost.ZIndex = 20
	tip = Kit.text(root, "", { x = 0, y = 0, color = C.white })
	tip.Visible = false
	tip.ZIndex = 20

	local frames, acc = 0, 0
	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		use()
		local m = UserInputService:GetMouseLocation()
		if ghost.Visible then
			ghost.Position = UDim2.fromOffset(m.X - 8 * hudU, m.Y - 8 * hudU)
		end
		local d = hovered and slots[hovered] and not picked and invOpen and slots[hovered]
		if d and env.Items.Defs[d.id] then
			Kit.setText(tip, env.Items.Defs[d.id].Name)
			tip.Position = UDim2.fromOffset(m.X + 8 * hudU, m.Y + 6 * hudU)
			tip.Visible = true
		else
			tip.Visible = false
		end
		frames += 1
		acc += dt
		if acc >= 0.5 then
			Kit.setText(fpsText, if settings.ShowFps then ("FPS %d"):format(math.floor(frames / acc + 0.5)) else "")
			frames, acc = 0, 0
		end
	end))

	refresh()
end

-- ===== public =====

function Hud.Init(e)
	env = e
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if gui then
			task.delay(0.25, function()
				if gui then
					Hud.Rebuild()
				end
			end)
		end
	end)
end

function Hud.Show()
	build()
end

function Hud.Rebuild()
	if not gui then
		return
	end
	local wasOpen = invOpen
	invOpen = false
	picked = nil
	build()
	if wasOpen then
		openInventory()
	end
end

function Hud.Hide()
	destroy()
	invOpen = false
end

function Hud.IsShown(): boolean
	return gui ~= nil
end

function Hud.SetInventory(newSlots, sel)
	slots = newSlots
	if type(sel) == "number" then
		selected = sel
	end
	refresh()
end

function Hud.SetSettings(s)
	local rebuild = s.UIScale ~= settings.UIScale or s.Tips ~= settings.Tips
	settings = { UIScale = s.UIScale, Tips = s.Tips, ShowFps = s.ShowFps }
	if rebuild and gui then
		Hud.Rebuild()
	end
end

function Hud.Selected(): number
	return selected
end

return Hud
