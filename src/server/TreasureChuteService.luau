local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TreasureChuteService = {}

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local PlunderService = require(script.Parent.PlunderService)

local riders = {}
local CHUTE_LENGTH = (LagoonLayout.CHUTE_END - LagoonLayout.CHUTE_START).Magnitude

local function getAnchorPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

local function chutePositionAt(progress)
	return LagoonLayout.CHUTE_START:Lerp(LagoonLayout.CHUTE_END, progress / CHUTE_LENGTH)
end

local function landOnPedestal(player, def, mutation, slot, model)
	local state = PirateState.getState(player)
	if not state then
		if model then
			model:Destroy()
		end
		return
	end
	local placeModel = model
	if not placeModel or not placeModel.Parent then
		local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
		placeModel = RigBuilder.buildBrainrotRig(def, mutation)
		RigBuilder.attachOverheadBillboard(placeModel, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
		placeModel.Parent = workspace
	end
	PirateState.setPedestalModel(player, slot, placeModel)
	PlunderService.attachStealClicker(placeModel, player, slot)
	placeModel:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
end

function TreasureChuteService.spawnConveyorBrainrot()
	local rarity = BootyCatalog.rollRarityTier()
	local def = BootyCatalog.pickRandomBrainrotOfRarity(rarity)
	local mutation = BootyCatalog.rollMutationModifier()
	local price = BootyCatalog.getBrainrotCost(def, mutation)
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "BUY " .. BootyCatalog.formatMoney(price))
	model:PivotTo(CFrame.new(LagoonLayout.CHUTE_START))
	model.Parent = workspace
	local rider = {
		model = model,
		def = def,
		mutation = mutation,
		price = price,
		progress = 0,
		bornAt = os.clock(),
	}
	local anchor = getAnchorPart(model)
	if anchor then
		local clicker = Instance.new("ClickDetector")
		clicker.MaxActivationDistance = 40
		clicker.Parent = anchor
		clicker.MouseClick:Connect(function(clickingPlayer)
			TreasureChuteService.handleBuyBrainrotRequest(clickingPlayer, rider)
		end)
	end
	table.insert(riders, rider)
	return rider
end

function TreasureChuteService.stepConveyorMovement(dt)
	local i = 1
	while i <= #riders do
		local rider = riders[i]
		rider.progress += LagoonLayout.CHUTE_SPEED * dt
		local age = os.clock() - rider.bornAt
		if rider.progress >= CHUTE_LENGTH or age > LagoonLayout.CHUTE_LIFETIME then
			TreasureChuteService.despawnConveyorBrainrot(i)
		else
			if rider.model and rider.model.Parent then
				rider.model:PivotTo(CFrame.new(chutePositionAt(rider.progress)))
			end
			i += 1
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

function TreasureChuteService.carryBrainrotHome(player, def, mutation, slot)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	model.Parent = workspace
	local character = player.Character
	if not character then
		landOnPedestal(player, def, mutation, slot, model)
		return
	end
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
	local startTime = os.clock()
	local reached = false
	while os.clock() - startTime < 25 do
		local currentState = PirateState.getState(player)
		if not currentState or not currentState.carrying or currentState.carrying.model ~= model then
			break
		end
		local char = player.Character
		if not char then
			break
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			break
		end
		model:PivotTo(CFrame.new(hrp.Position + Vector3.new(0, 4, 0)))
		local pedestalPos = LagoonLayout.getPedestalPosition(currentState.base, slot)
		if (hrp.Position - pedestalPos).Magnitude <= 10 then
			reached = true
			break
		end
		task.wait(0.1)
	end
	local finalState = PirateState.getState(player)
	if finalState and finalState.carrying and finalState.carrying.model == model then
		finalState.carrying = nil
	end
	PirateState.broadcast(player, {
		type = "carrying",
		name = nil,
		income = 0,
		stolen = false,
	})
	landOnPedestal(player, def, mutation, slot, model)
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

function TreasureChuteService.handleBuyBrainrotRequest(player, rider)
	local riderIndex = nil
	for i, r in ipairs(riders) do
		if r == rider then
			riderIndex = i
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
	if not PirateState.spendCash(player, price) then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Not enough doubloons for " .. rider.def.name .. "!",
			color = "red",
		})
		return
	end
	local placed = PirateState.assignBrainrotToSlot(player, slot, rider.def.id, rider.mutation)
	if not placed then
		PirateState.addCash(player, price)
		PirateState.broadcast(player, {
			type = "feed",
			text = "Could not place " .. rider.def.name .. " — refunded!",
			color = "red",
		})
		return
	end
	BountyService.addBountyProgress(player, "buy", 1)
	TreasureChuteService.despawnConveyorBrainrot(riderIndex)
	TreasureChuteService.carryBrainrotHome(player, rider.def, rider.mutation, slot)
end

function TreasureChuteService.startChuteLoop()
	for _, progress in ipairs({ 0, 45, 90 }) do
		local rider = TreasureChuteService.spawnConveyorBrainrot()
		rider.progress = progress
		if rider.model and rider.model.Parent then
			rider.model:PivotTo(CFrame.new(chutePositionAt(progress)))
		end
	end
	task.spawn(function()
		while true do
			task.wait(6)
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
