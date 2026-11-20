-- TreasureChuteService.luau
-- Brainrots sail out of the wrecked galleon, ride the glowing treasure
-- chute past the docks, and can be bought before they sail off the end.
-- Buying carries the brainrot home to the buyer's deck.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local PlunderService = require(script.Parent.PlunderService)
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local TreasureChuteService = {}

-- Module state: the riders currently on the chute.
local riders = {}
-- A new brainrot spawns on the chute every 6 seconds.
local SPAWN_INTERVAL = 6
-- The chute length in studs (from start to end).
local CHUTE_LENGTH = (LagoonLayout.CHUTE_END - LagoonLayout.CHUTE_START).Magnitude
-- How far above the buyer's head a carried brainrot floats.
local CARRY_HEIGHT = 4
-- How close the buyer must get to the target pedestal to land.
local LAND_DISTANCE = 10
-- The maximum carry-home time in seconds.
local CARRY_TIMEOUT = 25

-- Returns a part of a model that can host a ClickDetector.
local function getClickPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

-- Returns the interpolated chute position for a progress in studs.
local function chutePosition(progress)
	local t = math.clamp(progress / CHUTE_LENGTH, 0, 1)
	return LagoonLayout.CHUTE_START:Lerp(LagoonLayout.CHUTE_END, t)
end

-- Spawns a new rider on the chute: rolls a rarity, picks a random brainrot
-- of that rarity, rolls a mutation, builds the rig, computes the price,
-- attaches a billboard reading "BUY <price>", places the model at the chute
-- start, attaches a ClickDetector (40 studs) wired to the buy handler, and
-- appends the rider to the list. Returns the new rider.
function TreasureChuteService.spawnConveyorBrainrot()
	local rarity = BootyCatalog.rollRarityTier()
	local def = BootyCatalog.pickRandomBrainrotOfRarity(rarity)
	local mutation = BootyCatalog.rollMutationModifier()
	local price = BootyCatalog.getBrainrotCost(def, mutation)
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "BUY " .. BootyCatalog.formatMoney(price))
	model:PivotTo(CFrame.new(LagoonLayout.CHUTE_START))
	model.Parent = Workspace
	local rider = {
		model = model,
		def = def,
		mutation = mutation,
		price = price,
		progress = 0,
		birthTime = os.clock(),
	}
	local clickPart = getClickPart(model)
	if clickPart then
		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = 40
		clickDetector.Parent = clickPart
		clickDetector.MouseClick:Connect(function(player)
			TreasureChuteService.handleBuyBrainrotRequest(player, rider)
		end)
	end
	table.insert(riders, rider)
	return rider
end

-- Advances every rider by chute speed x dt along the chute. A rider is
-- despawned when its progress reaches the chute length or its age exceeds
-- the 25-second lifetime; otherwise its model is moved to the interpolated
-- position along the chute.
function TreasureChuteService.stepConveyorMovement(dt)
	local now = os.clock()
	for index = #riders, 1, -1 do
		local rider = riders[index]
		rider.progress = rider.progress + LagoonLayout.CHUTE_SPEED * dt
		local age = now - rider.birthTime
		if rider.progress >= CHUTE_LENGTH or age > LagoonLayout.CHUTE_LIFETIME then
			TreasureChuteService.despawnConveyorBrainrot(index)
		elseif rider.model then
			rider.model:PivotTo(CFrame.new(chutePosition(rider.progress)))
		end
	end
end

-- Destroys a rider's model (if any) and removes the rider from the list.
function TreasureChuteService.despawnConveyorBrainrot(index)
	local rider = riders[index]
	if not rider then
		return
	end
	if rider.model then
		rider.model:Destroy()
	end
	table.remove(riders, index)
end

-- Places a bought brainrot on its pedestal. If the player has no state the
-- model is destroyed. If the model is missing or was destroyed (e.g. a
-- Kraken Surge dropped it mid-carry), a fresh rig is built with an income
-- billboard. The model is recorded as the slot's pedestal model, a steal
-- clicker is attached, and it is placed at the pedestal position.
local function landBrainrotOnPedestal(player, def, mutation, slot, model)
	local state = PirateState.getState(player)
	if not state then
		if model then
			model:Destroy()
		end
		return
	end
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	if not model then
		model = RigBuilder.buildBrainrotRig(def, mutation)
		RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
		model.Parent = Workspace
	end
	local pedestalPos = LagoonLayout.getPedestalPosition(state.base, slot)
	model:PivotTo(CFrame.new(pedestalPos))
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
end

-- The visual carry home. A fresh rig is built with an income billboard and
-- placed in the world. The carrying record is set and the buyer gets a
-- carrying message while all players see the purchase feed. The model
-- follows 4 studs above the buyer's head, re-checked every 0.1 seconds for
-- up to 25 seconds, ending early when the buyer comes within 10 studs of
-- the target pedestal. Then the carrying record is cleared, a carrying
-- message with a nil name is sent, and the brainrot lands on its pedestal.
function TreasureChuteService.carryBrainrotHome(player, def, mutation, slot)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local character = player.Character
	if not character then
		landBrainrotOnPedestal(player, def, mutation, slot, nil)
		return
	end
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	model.Parent = Workspace
	state.carrying = { defId = def.id, mutation = mutation, slot = slot, model = model }
	PirateState.broadcast(player, {
		type = "carrying",
		name = def.name,
		income = income,
		stolen = false,
	})
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. " bought " .. def.name .. "!",
		color = "green",
	})
	task.spawn(function()
		local startTime = os.clock()
		local reached = false
		while os.clock() - startTime < CARRY_TIMEOUT do
			local currentState = PirateState.getState(player)
			if not currentState then
				return
			end
			local carrying = currentState.carrying
			if not carrying or carrying.model ~= model or carrying.slot ~= slot then
				return
			end
			local char = player.Character
			if not char then
				break
			end
			local root = char:FindFirstChild("HumanoidRootPart")
			if not root then
				break
			end
			if model.Parent then
				model:PivotTo(CFrame.new(root.Position + Vector3.new(0, CARRY_HEIGHT, 0)))
			end
			local pedestalPos = LagoonLayout.getPedestalPosition(currentState.base, slot)
			if (root.Position - pedestalPos).Magnitude <= LAND_DISTANCE then
				reached = true
				break
			end
			task.wait(0.1)
		end
		local finalState = PirateState.getState(player)
		if not finalState then
			if model then
				model:Destroy()
			end
			return
		end
		local carrying = finalState.carrying
		local carryModel = nil
		if carrying and carrying.model == model and carrying.slot == slot then
			carryModel = carrying.model
			finalState.carrying = nil
		end
		PirateState.broadcast(player, {
			type = "carrying",
			name = nil,
		})
		landBrainrotOnPedestal(player, def, mutation, slot, carryModel)
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
	end)
end

-- The purchase flow. Guards, in order: the rider must still be on the
-- chute; the buyer must have state; the buyer must not already be carrying;
-- the buyer must have a character; the buyer must have a free deck slot;
-- the buyer must have enough cash. Payment is taken, ownership is recorded
-- at purchase (slot assigned, Log marked, buy bounty progressed), the rider
-- is despawned, and the visual carry home begins.
function TreasureChuteService.handleBuyBrainrotRequest(player, rider)
	local riderIndex = nil
	for index, entry in ipairs(riders) do
		if entry == rider then
			riderIndex = index
			break
		end
	end
	if not riderIndex then
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
	local character = player.Character
	if not character then
		return
	end
	local freeSlot = PirateState.getFreeSlot(player)
	if not freeSlot then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Your deck is FULL! Buy a pedestal first.",
			color = "red",
		})
		return
	end
	if PirateState.getCash(player) < rider.price then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Not enough doubloons for " .. rider.def.name .. "!",
			color = "red",
		})
		return
	end
	if not PirateState.spendCash(player, rider.price) then
		return
	end
	local assigned = PirateState.assignBrainrotToSlot(player, freeSlot, rider.def.id, rider.mutation)
	if not assigned then
		PirateState.addCash(player, rider.price)
		PirateState.broadcast(player, {
			type = "feed",
			text = "Could not place " .. rider.def.name .. " — refunded!",
			color = "red",
		})
		return
	end
	BountyService.addBountyProgress(player, "buy", 1)
	TreasureChuteService.despawnConveyorBrainrot(riderIndex)
	TreasureChuteService.carryBrainrotHome(player, rider.def, rider.mutation, freeSlot)
end

-- Pre-populates 3 riders at progress 0, 45, and 90 studs, then starts two
-- background loops: one spawning a new rider every 6 seconds, and one
-- stepping rider movement every 0.1 seconds.
function TreasureChuteService.startChuteLoop()
	local preplaced = { 0, 45, 90 }
	for _, progress in ipairs(preplaced) do
		local rider = TreasureChuteService.spawnConveyorBrainrot()
		rider.progress = progress
		if rider.model then
			rider.model:PivotTo(CFrame.new(chutePosition(progress)))
		end
	end
	task.spawn(function()
		while true do
			task.wait(SPAWN_INTERVAL)
			TreasureChuteService.spawnConveyorBrainrot()
		end
	end)
	task.spawn(function()
		local lastTime = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local dt = now - lastTime
			lastTime = now
			TreasureChuteService.stepConveyorMovement(dt)
		end
	end)
end

return TreasureChuteService
