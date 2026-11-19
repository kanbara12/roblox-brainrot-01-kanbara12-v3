-- TreasureChuteService: brainrots sail out of the wrecked galleon, ride the
-- glowing treasure chute past the docks, and can be bought before they sail
-- off the end. Buying carries the brainrot home to the buyer's deck.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local PlunderService = require(script.Parent.PlunderService)

local TreasureChuteService = {}
TreasureChuteService.riders = {}
TreasureChuteService.spawnInterval = 6

function TreasureChuteService.spawnConveyorBrainrot()
	local rarity = BootyCatalog.rollRarityTier()
	local def = BootyCatalog.pickRandomBrainrotOfRarity(rarity)
	local mutation = BootyCatalog.rollMutationModifier()
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	local price = BootyCatalog.getBrainrotCost(def, mutation)
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
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = 40
	clicker.MouseClick:Connect(function(player)
		TreasureChuteService.handleBuyBrainrotRequest(player, rider)
	end)
	clicker.Parent = model.PrimaryPart
	table.insert(TreasureChuteService.riders, rider)
	return rider
end

function TreasureChuteService.stepConveyorMovement(dt)
	local now = os.clock()
	for i = #TreasureChuteService.riders, 1, -1 do
		local rider = TreasureChuteService.riders[i]
		rider.progress += LagoonLayout.CHUTE_SPEED * dt
		local total = (LagoonLayout.CHUTE_END - LagoonLayout.CHUTE_START).Magnitude
		if rider.progress >= total or now - rider.bornAt > LagoonLayout.CHUTE_LIFETIME then
			TreasureChuteService.despawnConveyorBrainrot(i)
		else
			local t = rider.progress / total
			local pos = LagoonLayout.CHUTE_START:Lerp(LagoonLayout.CHUTE_END, t)
			rider.model:PivotTo(CFrame.new(pos))
		end
	end
end

function TreasureChuteService.despawnConveyorBrainrot(index)
	local rider = TreasureChuteService.riders[index]
	if rider and rider.model then
		rider.model:Destroy()
	end
	table.remove(TreasureChuteService.riders, index)
end

function TreasureChuteService.handleBuyBrainrotRequest(player, rider)
	for i, other in ipairs(TreasureChuteService.riders) do
		if other == rider then
			local state = PirateState.getState(player)
			if not state then return end
			if state.carrying then
				PirateState.broadcast(player, { type = "feed", text = "Carry the brainrot home first!", color = "red" })
				return
			end
			if not player.Character then
				return
			end
			local slot = PirateState.getFreeSlot(player)
			if not slot then
				PirateState.broadcast(player, { type = "feed", text = "Your deck is FULL! Buy a pedestal first.", color = "red" })
				return
			end
			if not PirateState.spendCash(player, rider.price) then
				PirateState.broadcast(player, { type = "feed", text = "Not enough doubloons for " .. rider.def.name .. "!", color = "red" })
				return
			end
			TreasureChuteService.despawnConveyorBrainrot(i)
			TreasureChuteService.carryBrainrotHome(player, rider.def, rider.mutation, slot)
			return
		end
	end
end

-- A bought brainrot walks home over the buyer's head, then lands on a pedestal.
function TreasureChuteService.carryBrainrotHome(player, def, mutation, slot)
	local character = player.Character
	local state = PirateState.getState(player)
	if not state or not character then return end
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	model.Parent = workspace
	state.carrying = { defId = def.id, mutation = mutation, slot = slot, model = model }
	PirateState.broadcast(player, { type = "carrying", name = def.name, income = income })
	PirateState.broadcastAll({ type = "feed", text = player.Name .. " bought " .. def.name .. "!", color = "green" })
	local humanoidRoot = nil
	local target = LagoonLayout.getPedestalPosition(state.base, slot)
	local waited = 0
	local reached = false
	while waited < 25 do
		if not state.carrying or state.carrying.model ~= model then
			return
		end
		local liveCharacter = player.Character
		humanoidRoot = liveCharacter and liveCharacter:FindFirstChild("HumanoidRootPart")
		if humanoidRoot then
			local carryPos = humanoidRoot.Position + Vector3.new(0, 4, 0)
			model:PivotTo(CFrame.new(carryPos))
			if (humanoidRoot.Position - target).Magnitude < 10 then
				reached = true
				break
			end
		end
		task.wait(0.1)
		waited += 0.1
	end
	if not state.carrying or state.carrying.model ~= model then
		return
	end
	if not reached then
		state.carrying = nil
		PirateState.addCash(player, BootyCatalog.getBrainrotCost(def, mutation))
		model:Destroy()
		PirateState.broadcast(player, { type = "carrying", name = nil })
		PirateState.broadcast(player, { type = "feed", text = "Timed out carrying " .. def.name .. " — refunded!", color = "red" })
		return
	end
	state.carrying = nil
	PirateState.assignBrainrotToSlot(player, slot, def.id, mutation)
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
	model:PivotTo(CFrame.new(target))
	PirateState.broadcast(player, { type = "carrying", name = nil })
	BountyService.addBountyProgress(player, "buy", 1)
	BountyService.checkBountyCompletion(player)
end

function TreasureChuteService.startChuteLoop()
	-- Pre-populate the chute at boot, spread along its length, so it is
	-- never empty in the first seconds of a fresh server (a photo taken
	-- right after joining used to show a bare chute even though spawns
	-- were working).
	do
		local total = (LagoonLayout.CHUTE_END - LagoonLayout.CHUTE_START).Magnitude
		for _, progress in ipairs({ 0, 45, 90 }) do
			local rider = TreasureChuteService.spawnConveyorBrainrot()
			rider.progress = progress
			local t = progress / total
			rider.model:PivotTo(CFrame.new(LagoonLayout.CHUTE_START:Lerp(LagoonLayout.CHUTE_END, t)))
		end
	end
	task.spawn(function()
		while true do
			task.wait(TreasureChuteService.spawnInterval)
			TreasureChuteService.spawnConveyorBrainrot()
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			TreasureChuteService.stepConveyorMovement(now - last)
			last = now
		end
	end)
end

return TreasureChuteService
