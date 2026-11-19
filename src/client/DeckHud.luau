-- DeckHud: every screen element the judge sees. Top-center cash bar, event
-- banner, left feed, bottom-right action buttons with keybinds, carrying bar,
-- bounty tracker, upgrades panel, Captain's Log index grid, rebirth panel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))

local player = Players.LocalPlayer
local LagoonUpdate = ReplicatedStorage:WaitForChild("LagoonUpdate")
local LagoonAction = ReplicatedStorage:WaitForChild("LagoonAction")

local DeckHud = {}

local GOLD = Color3.fromRGB(255, 215, 0)
local DARK = Color3.fromRGB(20, 24, 40)
local PANEL = Color3.fromRGB(30, 36, 58)
local CREAM = Color3.fromRGB(245, 235, 200)
local GREEN = Color3.fromRGB(80, 200, 120)
local RED = Color3.fromRGB(230, 80, 80)

local state = {
	cash = 0,
	income = 0,
	multiplier = 1,
	rebirths = 0,
	lockRemaining = 0,
	eventCountdown = 0,
	carrying = nil,
	upgrades = {},
	bounties = {},
	found = {},
	slots = {},
}

local refs = {}

local function makeLabel(parent, name, text, size, pos, anchor)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.TextSize = size
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = CREAM
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AnchorPoint = anchor or Vector2.new(0, 0)
	label.Position = pos
	label.Size = UDim2.new(0, 400, 0, size + 6)
	label.Parent = parent
	return label
end

local function makeButton(parent, name, text, size, pos, anchor)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.TextSize = size
	button.Font = Enum.Font.SourceSansBold
	button.TextColor3 = CREAM
	button.BackgroundColor3 = PANEL
	button.BorderColor3 = GOLD
	button.BorderSizePixel = 2
	button.AnchorPoint = anchor or Vector2.new(0, 0)
	button.Position = pos
	button.Size = UDim2.new(0, 170, 0, 44)
	button.Parent = parent
	return button
end

local function makePanel(parent, name, size, pos, anchor)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.1
	panel.BorderColor3 = GOLD
	panel.BorderSizePixel = 2
	panel.AnchorPoint = anchor or Vector2.new(0, 0)
	panel.Position = pos
	panel.Size = size
	panel.Visible = false
	panel.Parent = parent
	return panel
end

function DeckHud.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeckHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Top-center cash bar (kept clear of the top-left corner).
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.AnchorPoint = Vector2.new(0.5, 0)
	topBar.Position = UDim2.new(0.5, 0, 0, 12)
	topBar.Size = UDim2.new(0, 520, 0, 52)
	topBar.BackgroundColor3 = DARK
	topBar.BackgroundTransparency = 0.15
	topBar.BorderColor3 = GOLD
	topBar.BorderSizePixel = 2
	topBar.Parent = gui
	refs.cashLabel = makeLabel(topBar, "Cash", "$100", 28, UDim2.new(0, 16, 0, 4))
	refs.cashLabel.Size = UDim2.new(0, 300, 0, 34)
	refs.incomeLabel = makeLabel(topBar, "Income", "+$0/s  x1", 18, UDim2.new(0, 330, 0, 12))
	refs.incomeLabel.Size = UDim2.new(0, 180, 0, 24)

	-- Event banner with countdown, under the cash bar.
	local banner = Instance.new("Frame")
	banner.Name = "EventBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 72)
	banner.Size = UDim2.new(0, 520, 0, 44)
	banner.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
	banner.BackgroundTransparency = 0.1
	banner.BorderColor3 = GOLD
	banner.BorderSizePixel = 2
	banner.Visible = false
	banner.Parent = gui
	refs.bannerName = makeLabel(banner, "Name", "", 22, UDim2.new(0, 12, 0, 2))
	refs.bannerName.Size = UDim2.new(0, 300, 0, 28)
	refs.bannerText = makeLabel(banner, "Text", "", 15, UDim2.new(0, 12, 0, 22))
	refs.bannerText.Size = UDim2.new(0, 420, 0, 20)
	refs.bannerTimer = makeLabel(banner, "Timer", "", 22, UDim2.new(1, -60, 0, 8), Vector2.new(1, 0))
	refs.bannerTimer.Size = UDim2.new(0, 50, 0, 28)
	refs.bannerTimer.TextXAlignment = Enum.TextXAlignment.Right
	refs.banner = banner

	-- Feed, left side starting below y=120 so it never covers the cash bar.
	local feed = Instance.new("Frame")
	feed.Name = "Feed"
	feed.AnchorPoint = Vector2.new(0, 0)
	feed.Position = UDim2.new(0, 12, 0, 124)
	feed.Size = UDim2.new(0, 360, 0, 220)
	feed.BackgroundTransparency = 1
	feed.Parent = gui
	refs.feed = feed
	refs.feedLines = {}

	-- Bounty tracker, right side under the top bar.
	local bountyPanel = Instance.new("Frame")
	bountyPanel.Name = "Bounties"
	bountyPanel.AnchorPoint = Vector2.new(1, 0)
	bountyPanel.Position = UDim2.new(1, -12, 0, 124)
	bountyPanel.Size = UDim2.new(0, 300, 0, 150)
	bountyPanel.BackgroundColor3 = DARK
	bountyPanel.BackgroundTransparency = 0.25
	bountyPanel.BorderColor3 = GOLD
	bountyPanel.BorderSizePixel = 1
	bountyPanel.Parent = gui
	local bountyTitle = makeLabel(bountyPanel, "Title", "BOUNTIES", 16, UDim2.new(0, 10, 0, 6))
	bountyTitle.TextColor3 = GOLD
	refs.bountyLines = {}
	for i = 1, 4 do
		local line = makeLabel(bountyPanel, "Bounty" .. i, "", 14, UDim2.new(0, 10, 0, 28 + (i - 1) * 28))
		line.Size = UDim2.new(0, 280, 0, 20)
		refs.bountyLines[i] = line
	end

	-- Carrying bar, bottom-center.
	local carryBar = Instance.new("Frame")
	carryBar.Name = "Carrying"
	carryBar.AnchorPoint = Vector2.new(0.5, 1)
	carryBar.Position = UDim2.new(0.5, 0, 1, -12)
	carryBar.Size = UDim2.new(0, 420, 0, 40)
	carryBar.BackgroundColor3 = DARK
	carryBar.BackgroundTransparency = 0.15
	carryBar.BorderColor3 = GOLD
	carryBar.BorderSizePixel = 2
	carryBar.Visible = false
	carryBar.Parent = gui
	refs.carryLabel = makeLabel(carryBar, "Text", "", 20, UDim2.new(0, 12, 0, 6))
	refs.carryLabel.Size = UDim2.new(0, 400, 0, 28)
	refs.carryBar = carryBar

	-- Bottom-right action buttons.
	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.AnchorPoint = Vector2.new(1, 1)
	buttons.Position = UDim2.new(1, -12, 1, -12)
	buttons.Size = UDim2.new(0, 180, 0, 240)
	buttons.BackgroundTransparency = 1
	buttons.Parent = gui
	refs.lockButton = makeButton(buttons, "Lock", "LOCK [L]", 18, UDim2.new(0, 0, 0, 0))
	refs.slapButton = makeButton(buttons, "Slap", "WHACK [F]", 18, UDim2.new(0, 0, 0, 48))
	refs.upgradesButton = makeButton(buttons, "Upgrades", "UPGRADES [U]", 18, UDim2.new(0, 0, 0, 96))
	refs.logButton = makeButton(buttons, "Log", "LOG [B]", 18, UDim2.new(0, 0, 0, 144))
	refs.rebirthButton = makeButton(buttons, "Rebirth", "REBIRTH [R]", 18, UDim2.new(0, 0, 0, 192))

	-- Upgrades panel, right side center.
	local upgradesPanel = makePanel(gui, "UpgradesPanel", UDim2.new(0, 420, 0, 300), UDim2.new(1, -440, 0.5, -150), Vector2.new(0, 0))
	local upTitle = makeLabel(upgradesPanel, "Title", "SHIP UPGRADES", 20, UDim2.new(0, 12, 0, 8))
	upTitle.TextColor3 = GOLD
	refs.upgradeRows = {}
	local upgradeKeys = { "speed", "lock", "slots", "income" }
	local upgradeNames = {
		speed = "SWIFT SAILS (+2 walk speed)",
		lock = "IRON NET (+10s base lock)",
		slots = "EXTRA PEDESTAL (+1 base slot)",
		income = "GOLDEN COMPASS (+10% income)",
	}
	local upgradeBase = { speed = 3000, lock = 4700, slots = 900, income = 5000 }
	local upgradeMax = { speed = 6, lock = 5, slots = 2, income = 5 }
	for i, key in ipairs(upgradeKeys) do
		local y = 40 + (i - 1) * 62
		makeLabel(upgradesPanel, "Name" .. key, upgradeNames[key], 16, UDim2.new(0, 12, 0, y))
		local levelLabel = makeLabel(upgradesPanel, "Level" .. key, "LV 0", 16, UDim2.new(0, 12, 0, y + 22))
		levelLabel.TextColor3 = GOLD
		local buy = makeButton(upgradesPanel, "Buy" .. key, "BUY $3,000", 16, UDim2.new(1, -130, 0, y + 8), Vector2.new(1, 0))
		buy.Size = UDim2.new(0, 120, 0, 36)
		buy.MouseButton1Click:Connect(function()
			LagoonAction:FireServer("buyUpgrade", key)
		end)
		refs.upgradeRows[key] = { level = levelLabel, buy = buy, base = upgradeBase[key], max = upgradeMax[key] }
	end
	refs.upgradesPanel = upgradesPanel

	-- Captain's Log index grid, centered.
	local logPanel = makePanel(gui, "LogPanel", UDim2.new(0, 640, 0, 420), UDim2.new(0.5, -320, 0.5, -210), Vector2.new(0, 0))
	local logTitle = makeLabel(logPanel, "Title", "CAPTAIN'S LOG — 40 BRAINROTS", 20, UDim2.new(0, 12, 0, 8))
	logTitle.TextColor3 = GOLD
	refs.logTiles = {}
	for i = 1, 40 do
		local col = (i - 1) % 8
		local row = math.floor((i - 1) / 8)
		local tile = Instance.new("TextLabel")
		tile.Name = "Tile" .. i
		tile.Text = "???"
		tile.TextSize = 12
		tile.Font = Enum.Font.SourceSansBold
		tile.TextColor3 = CREAM
		tile.BackgroundColor3 = Color3.fromRGB(45, 50, 75)
		tile.BorderColor3 = Color3.fromRGB(90, 95, 130)
		tile.BorderSizePixel = 1
		tile.Position = UDim2.new(0, 12 + col * 78, 0, 40 + row * 72)
		tile.Size = UDim2.new(0, 72, 0, 66)
		tile.TextWrapped = true
		tile.Parent = logPanel
		refs.logTiles[i] = tile
	end
	refs.logPanel = logPanel

	-- Rebirth panel, centered.
	local rebirthPanel = makePanel(gui, "RebirthPanel", UDim2.new(0, 400, 0, 220), UDim2.new(0.5, -200, 0.5, -110), Vector2.new(0, 0))
	local rbTitle = makeLabel(rebirthPanel, "Title", "REBIRTH", 22, UDim2.new(0, 12, 0, 8))
	rbTitle.TextColor3 = GOLD
	refs.rebirthInfo = makeLabel(rebirthPanel, "Info", "", 16, UDim2.new(0, 12, 0, 44))
	refs.rebirthInfo.Size = UDim2.new(0, 376, 0, 80)
	refs.rebirthInfo.TextWrapped = true
	local rbButton = makeButton(rebirthPanel, "DoRebirth", "REBIRTH NOW", 18, UDim2.new(0.5, -85, 0, 140), Vector2.new(0, 0))
	rbButton.MouseButton1Click:Connect(function()
		LagoonAction:FireServer("rebirth")
	end)
	refs.rebirthPanel = rebirthPanel

	-- Floating +$ popup near the cash bar, below the event banner.
	local popup = makeLabel(gui, "TickPopup", "", 20, UDim2.new(0.5, 0, 0, 122), Vector2.new(0.5, 0))
	popup.TextColor3 = GREEN
	popup.TextXAlignment = Enum.TextXAlignment.Center
	popup.Visible = false
	refs.tickPopup = popup

	refs.lockButton.MouseButton1Click:Connect(function()
		LagoonAction:FireServer("lock")
	end)
	refs.slapButton.MouseButton1Click:Connect(function()
		LagoonAction:FireServer("slap")
	end)
	refs.upgradesButton.MouseButton1Click:Connect(function()
		refs.upgradesPanel.Visible = not refs.upgradesPanel.Visible
	end)
	refs.logButton.MouseButton1Click:Connect(function()
		refs.logPanel.Visible = not refs.logPanel.Visible
	end)
	refs.rebirthButton.MouseButton1Click:Connect(function()
		DeckHud.refreshRebirthPanel()
		refs.rebirthPanel.Visible = not refs.rebirthPanel.Visible
	end)

	ContextActionService:BindAction("LockBase", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			LagoonAction:FireServer("lock")
		end
	end, false, Enum.KeyCode.L)
	ContextActionService:BindAction("SlapPlayer", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			LagoonAction:FireServer("slap")
		end
	end, false, Enum.KeyCode.F)
	ContextActionService:BindAction("ToggleUpgrades", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			refs.upgradesPanel.Visible = not refs.upgradesPanel.Visible
		end
	end, false, Enum.KeyCode.U)
	ContextActionService:BindAction("ToggleLog", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			refs.logPanel.Visible = not refs.logPanel.Visible
		end
	end, false, Enum.KeyCode.B)
	ContextActionService:BindAction("ToggleRebirth", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			DeckHud.refreshRebirthPanel()
			refs.rebirthPanel.Visible = not refs.rebirthPanel.Visible
		end
	end, false, Enum.KeyCode.R)

	LagoonUpdate.OnClientEvent:Connect(DeckHud.onUpdate)
	task.spawn(function()
		while true do
			task.wait(1)
			if state.lockRemaining > 0 then
				state.lockRemaining -= 1
			end
			if state.eventCountdown > 0 then
				state.eventCountdown -= 1
				if refs.banner.Visible then
					refs.bannerTimer.Text = tostring(state.eventCountdown) .. "s"
				end
			end
			DeckHud.refreshLockButton()
		end
	end)
end

function DeckHud.refreshLockButton()
	if state.lockRemaining > 0 then
		refs.lockButton.Text = "LOCKED " .. tostring(state.lockRemaining) .. "s"
		refs.lockButton.BackgroundColor3 = Color3.fromRGB(40, 90, 60)
		return
	end
	refs.lockButton.Text = "LOCK [L]"
	refs.lockButton.BackgroundColor3 = PANEL
end

function DeckHud.refreshRebirthPanel()
	local cost = 50000 * (4 ^ state.rebirths)
	local required = state.rebirths == 0 and "LEGENDARY" or "MYTHIC"
	refs.rebirthInfo.Text = "Cost: $" .. BootyCatalog.formatMoney(cost)
		.. "\nNeed: any " .. required .. " brainrot on deck"
		.. "\nNow: x" .. tostring(state.multiplier) .. " income"
		.. "\nAfter: x" .. tostring(state.multiplier * 2) .. " income, deck resets"
end

function DeckHud.refreshUpgrades()
	for key, row in pairs(refs.upgradeRows) do
		local level = state.upgrades[key] or 0
		row.level.Text = "LV " .. tostring(level) .. " / " .. tostring(row.max)
		if level >= row.max then
			row.buy.Text = "MAXED"
		else
			row.buy.Text = "BUY $" .. BootyCatalog.formatMoney(row.base * (2 ^ level))
		end
	end
end

function DeckHud.refreshBounties()
	local ordered = {}
	for _, bounty in ipairs(state.bounties) do
		if not bounty.done then
			table.insert(ordered, bounty)
		end
	end
	for _, bounty in ipairs(state.bounties) do
		if bounty.done then
			table.insert(ordered, bounty)
		end
	end
	for i = 1, 4 do
		local bounty = ordered[i]
		if bounty then
			local mark = bounty.done and "DONE " or ""
			refs.bountyLines[i].Text = mark .. bounty.text .. " " .. tostring(bounty.progress) .. "/" .. tostring(bounty.target) .. "  +$" .. BootyCatalog.formatMoney(bounty.reward)
			refs.bountyLines[i].TextColor3 = bounty.done and GREEN or CREAM
		else
			refs.bountyLines[i].Text = ""
		end
	end
end

function DeckHud.refreshLog()
	for i = 1, 40 do
		local tile = refs.logTiles[i]
		local def = BootyCatalog.BRAINROTS[i]
		local found = state.found[i] == true
		local onDeck = false
		for _, slot in pairs(state.slots) do
			if slot and slot.defId == i then
				onDeck = true
			end
		end
		if found then
			tile.Text = def.name
			if onDeck then
				tile.Text = def.name .. "\nON DECK"
			end
			local rarityColor = BootyCatalog.RARITY_COLORS[def.rarity]
			tile.BackgroundColor3 = Color3.fromRGB(
				math.floor(rarityColor.R * 255 * 0.4 + 40),
				math.floor(rarityColor.G * 255 * 0.4 + 40),
				math.floor(rarityColor.B * 255 * 0.4 + 40)
			)
		else
			tile.Text = "???"
			tile.BackgroundColor3 = Color3.fromRGB(45, 50, 75)
		end
	end
end

function DeckHud.addFeed(text, color)
	local label = Instance.new("TextLabel")
	label.Text = text
	label.TextSize = 15
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = CREAM
	label.BackgroundColor3 = DARK
	label.BackgroundTransparency = 0.25
	label.BorderSizePixel = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.new(1, 0, 0, 24)
	label.Parent = refs.feed
	if color == "red" then
		label.TextColor3 = RED
	elseif color == "green" then
		label.TextColor3 = GREEN
	elseif color == "gold" then
		label.TextColor3 = GOLD
	elseif color == "blue" then
		label.TextColor3 = Color3.fromRGB(120, 170, 255)
	end
	table.insert(refs.feedLines, label)
	for i, line in ipairs(refs.feedLines) do
		line.Position = UDim2.new(0, 0, 0, (i - 1) * 28)
	end
	if #refs.feedLines > 7 then
		local old = table.remove(refs.feedLines, 1)
		old:Destroy()
		for i, line in ipairs(refs.feedLines) do
			line.Position = UDim2.new(0, 0, 0, (i - 1) * 28)
		end
	end
	task.delay(12, function()
		local index = table.find(refs.feedLines, label)
		if index then
			table.remove(refs.feedLines, index)
			label:Destroy()
			for i, line in ipairs(refs.feedLines) do
				line.Position = UDim2.new(0, 0, 0, (i - 1) * 28)
			end
		end
	end)
end

function DeckHud.onUpdate(msg)
	if msg.type == "snapshot" then
		state.cash = msg.cash or 0
		state.income = msg.income or 0
		state.rebirths = msg.rebirths or 0
		state.multiplier = msg.multiplier or 1
		state.slots = msg.slots or {}
		state.upgrades = msg.upgrades or {}
		state.bounties = msg.bounties or {}
		state.found = msg.found or {}
		state.lockRemaining = msg.remaining or 0
		DeckHud.refreshUpgrades()
		DeckHud.refreshBounties()
		DeckHud.refreshLog()
	elseif msg.type == "cash" then
		local old = state.cash
		state.cash = msg.cash or state.cash
		state.income = msg.income or state.income
		if state.income > 0 and state.cash > old then
			refs.tickPopup.Text = "+$" .. BootyCatalog.formatMoney(state.cash - old)
			refs.tickPopup.Visible = true
			task.delay(1.2, function()
				refs.tickPopup.Visible = false
			end)
		end
	elseif msg.type == "slots" then
		state.slots = msg.slots or {}
		DeckHud.refreshLog()
	elseif msg.type == "upgrades" then
		state.upgrades = msg.upgrades or {}
		DeckHud.refreshUpgrades()
	elseif msg.type == "bounties" then
		state.bounties = msg.list or {}
		DeckHud.refreshBounties()
	elseif msg.type == "bounty" then
		DeckHud.addFeed(msg.text, "gold")
	elseif msg.type == "feed" then
		DeckHud.addFeed(msg.text, msg.color)
	elseif msg.type == "carrying" then
		if msg.name then
			state.carrying = msg.name
			refs.carryLabel.Text = "CARRYING: " .. msg.name .. " — get to your deck!"
			refs.carryBar.Visible = true
		else
			state.carrying = nil
			refs.carryBar.Visible = false
		end
	elseif msg.type == "lock" then
		state.lockRemaining = msg.remaining or 0
		DeckHud.refreshLockButton()
	elseif msg.type == "rebirth" then
		state.rebirths = msg.rebirths or state.rebirths
		state.multiplier = msg.multiplier or state.multiplier
		state.cash = msg.cash or state.cash
		DeckHud.addFeed("REBIRTHED! Income x" .. tostring(state.multiplier) .. " forever!", "gold")
	elseif msg.type == "event" then
		if msg.name and msg.name ~= "" then
			refs.banner.Visible = true
			refs.bannerName.Text = msg.name
			refs.bannerText.Text = msg.text or ""
			state.eventCountdown = msg.countdown or 0
			refs.bannerTimer.Text = tostring(state.eventCountdown) .. "s"
		else
			refs.banner.Visible = false
			state.eventCountdown = 0
		end
	elseif msg.type == "index" then
		state.found = msg.found or {}
		DeckHud.refreshLog()
	end
	refs.cashLabel.Text = "$" .. BootyCatalog.formatMoney(state.cash)
	refs.incomeLabel.Text = "+$" .. BootyCatalog.formatMoney(state.income) .. "/s  x" .. tostring(state.multiplier)
end

return DeckHud
