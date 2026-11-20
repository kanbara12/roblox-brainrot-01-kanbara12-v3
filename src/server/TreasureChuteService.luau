-- TreasureChuteService — the treasure chute.
-- Brainrots sail out of the wrecked galleon, ride the glowing treasure chute
-- past the docks, and can be bought before they sail off the end. Buying
-- carries the brainrot home to the buyer's deck.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local PirateState = require(script.Parent:WaitForChild("PirateState"))
local BountyService = require(script.Parent:WaitForChild("BountyService"))
local PlunderService = require(script.Parent:WaitForChild("PlunderService"))

local TreasureChuteService = {}

local riders = {} -- each rider: model, def, mutation, price, progress, born
local SPAWN_INTERVAL = 6
local CARRY_SECONDS = 25
local CARRY_STEP = 0.1
local REACH_DISTANCE = 10
local CARRY_HEIGHT = 4
local CLICK_DISTANCE = 40

local function chuteLength()
	return (LagoonLayout.CHUTE_END - LagoonLayout.CHUTE_START).Magnitude
end

local function chutePosition(progress)
	local length = chuteLength()
	return LagoonLayout.CHUTE_START:Lerp(LagoonLayout.CHUTE_END, progress / length)
end

--------------------------------------------------------------------------------
-- Landing (internal helper)
--------------------------------------------------------------------------------

-- Places the brainrot on its pedestal. The slot itself was already assigned
-- at purchase, so landing only ever places the visible model. If the model
-- is missing or was destroyed (a Kraken Surge dropped it mid-carry), a fresh
-- rig is built so the brainrot still lands.
local function landOnPedestal(player, def, mutation, slot, model)
	local state = PirateState.getState(player)
	if not state then
		if model then
			model:Destroy()
		end
		return
	end
	if not model or not model.Parent then
		local income =
			BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
		model = RigBuilder.buildBrainrotRig(def, mutation)
		RigBuilder.attachOverheadBillboard(
			model,
			def,
			mutation,
			"+" .. BootyCatalog.formatMoney(income) .. "/s"
		)
		model.Parent = workspace
	end
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
	model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
end

--------------------------------------------------------------------------------
-- Spawning and movement
--------------------------------------------------------------------------------

function TreasureChuteService.spawnConveyorBrainrot(progress)
	local rarity = BootyCatalog.rollRarityTier()
	local def = BootyCatalog.pickRandomBrainrotOfRarity(rarity)
	local mutation = BootyCatalog.rollMutationModifier()
	local price = BootyCatalog.getBrainrotCost(def, mutation)
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(
		model,
		def,
		mutation,
		"BUY " .. BootyCatalog.formatMoney(price)
	)
	local rider = {
		model = model,
		def = def,
		mutation = mutation,
		price = price,
		progress = progress or 0,
		born = os.clock(),
	}
	model.Parent = workspace
	model:PivotTo(CFrame.new(chutePosition(rider.progress)))
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = CLICK_DISTANCE
	detector.Parent = model.PrimaryPart
	detector.MouseClick:Connect(function(player)
		TreasureChuteService.handleBuyBrainrotRequest(player, rider)
	end)
	table.insert(riders, rider)
	return rider
end

function TreasureChuteService.stepConveyorMovement(dt)
	local length = chuteLength()
	for index = #riders, 1, -1 do
		local rider = riders[index]
		rider.progress = rider.progress + LagoonLayout.CHUTE_SPEED * dt
		local age = os.clock() - rider.born
		if rider.progress >= length or age > LagoonLayout.CHUTE_LIFETIME then
			TreasureChuteService.despawnConveyorBrainrot(index)
		elseif rider.model and rider.model.Parent then
			rider.model:PivotTo(CFrame.new(chutePosition(rider.progress)))
		end
	end
end

function TreasureChuteService.despawnConveyorBrainrot(index)
	local rider = riders[index]
	if rider and rider.model then
		rider.model:Destroy()
	end
	table.remove(riders, index)
end

--------------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------------

function TreasureChuteService.handleBuyBrainrotRequest(player, rider)
	local index = table.find(riders, rider)
	if not index then
		return
	end
	local state = PirateState.getState(player)
	if not state then
		return
	end
	if state.carrying then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Carry the brainrot home first!",
			color = "red",
		})
		return
	end
	if not player.Character then
		return
	end
	local slot = PirateState.getFreeSlot(player)
	if not slot then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Your deck is FULL! Buy a pedestal first.",
			color = "red",
		})
		return
	end
	local price = rider.price
	local def = rider.def
	local mutation = rider.mutation
	if PirateState.getCash(player) < price then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Not enough doubloons for " .. def.name .. "!",
			color = "red",
		})
		return
	end
	if not PirateState.spendCash(player, price) then
		return
	end
	-- Ownership is recorded at purchase: the brainrot is assigned to the
	-- free slot (which marks it found) before the walk home begins.
	if not PirateState.assignBrainrotToSlot(player, slot, def.id, mutation) then
		PirateState.addCash(player, price)
		PirateState.broadcast(player, {
			type = "feed",
			text = "Could not place " .. def.name .. " — refunded!",
			color = "red",
		})
		return
	end
	BountyService.addBountyProgress(player, "buy", 1)
	TreasureChuteService.despawnConveyorBrainrot(index)
	TreasureChuteService.carryBrainrotHome(player, def, mutation, slot)
end

--------------------------------------------------------------------------------
-- Carry home (visual only — the slot was already assigned at purchase)
--------------------------------------------------------------------------------

function TreasureChuteService.carryBrainrotHome(player, def, mutation, slot)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	-- No state or no character: land on the pedestal immediately, no carry.
	local character = player.Character
	if not character then
		landOnPedestal(player, def, mutation, slot, nil)
		return
	end
	local income =
		BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(
		model,
		def,
		mutation,
		"+" .. BootyCatalog.formatMoney(income) .. "/s"
	)
	model.Parent = workspace
	local root = character:FindFirstChild("HumanoidRootPart")
	local startPos = root and root.Position or character:GetPivot().Position
	model:PivotTo(CFrame.new(startPos + Vector3.new(0, CARRY_HEIGHT, 0)))
	local record = { defId = def.id, mutation = mutation, slot = slot, model = model }
	state.carrying = record
	PirateState.broadcast(player, { type = "carrying", name = def.name, income = income })
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. " bought " .. def.name .. "!",
		color = "green",
	})
	task.spawn(function()
		local reached = false
		local pedestalPos = LagoonLayout.getPedestalPosition(state.base, slot)
		local steps = math.floor(CARRY_SECONDS / CARRY_STEP)
		for _ = 1, steps do
			task.wait(CARRY_STEP)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				break
			end
			if not model.Parent then
				break
			end
			model:PivotTo(CFrame.new(hrp.Position + Vector3.new(0, CARRY_HEIGHT, 0)))
			if (hrp.Position - pedestalPos).Magnitude <= REACH_DISTANCE then
				reached = true
				break
			end
		end
		local current = PirateState.getState(player)
		if current and current.carrying == record then
			current.carrying = nil
		end
		PirateState.broadcast(player, { type = "carrying", name = nil })
		landOnPedestal(player, def, mutation, slot, model)
		if current then
			if reached then
				PirateState.broadcast(player, {
					type = "feed",
					text = def.name .. " is on your deck!",
					color = "green",
				})
			else
				PirateState.broadcast(player, {
					type = "feed",
					text = def.name .. " took the scenic route — it is on your deck!",
					color = "green",
				})
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Loops
--------------------------------------------------------------------------------

function TreasureChuteService.startChuteLoop()
	-- Pre-populate so the chute is never empty in the first seconds.
	TreasureChuteService.spawnConveyorBrainrot(0)
	TreasureChuteService.spawnConveyorBrainrot(45)
	TreasureChuteService.spawnConveyorBrainrot(90)
	task.spawn(function()
		while true do
			task.wait(SPAWN_INTERVAL)
			TreasureChuteService.spawnConveyorBrainrot()
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local dt = now - last
			last = now
			TreasureChuteService.stepConveyorMovement(dt)
		end
	end)
end

return TreasureChuteService
