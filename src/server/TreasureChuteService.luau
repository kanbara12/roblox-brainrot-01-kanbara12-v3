-- TreasureChuteService.luau
-- The treasure chute. Brainrots sail out of the wrecked galleon, ride the
-- glowing treasure chute past the docks, and can be bought before they sail
-- off the end. Buying carries the brainrot home to the buyer's deck.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local PlunderService = require(script.Parent.PlunderService)
local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))

local TreasureChuteService = {}

-- Every rider on the chute: model, brainrot definition, mutation, price,
-- progress along the chute in studs, and birth time.
local riders = {}
local SPAWN_INTERVAL_SECONDS = 6
local CLICK_DISTANCE = 40
local CARRY_SECONDS = 25
local CARRY_HEIGHT = 4
local LAND_DISTANCE = 10

local CHUTE_LENGTH = (LagoonLayout.CHUTE_END - LagoonLayout.CHUTE_START).Magnitude

-- The world position of a point `progress` studs along the chute.
local function chutePosition(progress)
	local t = math.clamp(progress / CHUTE_LENGTH, 0, 1)
	return LagoonLayout.CHUTE_START:Lerp(LagoonLayout.CHUTE_END, t)
end

-- Rolls a rarity, picks a random brainrot of that rarity, rolls a
-- mutation, builds the rig, computes the price, attaches a BUY billboard,
-- places the model at the chute start, wires a ClickDetector to the buy
-- handler, and appends the rider to the list. Returns the new rider.
function TreasureChuteService.spawnConveyorBrainrot()
	local rarity = BootyCatalog.rollRarityTier()
	local def = BootyCatalog.pickRandomBrainrotOfRarity(rarity)
	local mutation = BootyCatalog.rollMutationModifier()
	local price = BootyCatalog.getBrainrotCost(def, mutation)
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "BUY " .. BootyCatalog.formatMoney(price))
	model:PivotTo(CFrame.new(LagoonLayout.CHUTE_START))
	model.Parent = workspace
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = CLICK_DISTANCE
	clicker.Parent = model.PrimaryPart
	local rider = {
		model = model,
		def = def,
		mutation = mutation,
		price = price,
		progress = 0,
		birthTime = os.clock(),
	}
	clicker.MouseClick:Connect(function(clickingPlayer)
		TreasureChuteService.handleBuyBrainrotRequest(clickingPlayer, rider)
	end)
	table.insert(riders, rider)
	return rider
end

-- Advances every rider by chute speed x dt. A rider despawns when its
-- progress reaches the chute length or its age exceeds the 25-second
-- lifetime; otherwise its model moves to the interpolated position.
function TreasureChuteService.stepConveyorMovement(dt)
	for i = #riders, 1, -1 do
		local rider = riders[i]
		rider.progress = rider.progress + LagoonLayout.CHUTE_SPEED * dt
		local age = os.clock() - rider.birthTime
		if rider.progress >= CHUTE_LENGTH or age > LagoonLayout.CHUTE_LIFETIME then
			TreasureChuteService.despawnConveyorBrainrot(i)
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

-- Places a brainrot's model on its pedestal. If the player has no state
-- the model is destroyed. If the model is missing or was destroyed (for
-- example a Kraken Surge dropped it mid-carry), a fresh rig is built with
-- an income billboard. The model is recorded as the slot's pedestal
-- model, a steal clicker is attached, and it is placed at the pedestal.
local function landBrainrotOnPedestal(player, def, mutation, slot, model)
	local state = PirateState.getState(player)
	if not state then
		if model then
			model:Destroy()
		end
		return
	end
	if not model then
		model = RigBuilder.buildBrainrotRig(def, mutation)
		model.Parent = workspace
	end
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	local pedestalPos = LagoonLayout.getPedestalPosition(state.base, slot)
	model:PivotTo(CFrame.new(pedestalPos))
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
end

-- The visual carry home. A fresh rig is built with an income billboard and
-- floats 4 studs above the buyer's head, re-checked every 0.1 seconds for
-- up to 25 seconds, ending early when the buyer comes within 10 studs of
-- the target pedestal. Then the brainrot lands on its pedestal. The slot
-- itself was already assigned at purchase, so landing only places the
-- visible model. If the player has no state or no character when the carry
-- starts, the brainrot lands on its pedestal immediately (no carry).
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
	model.Parent = workspace
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
		local reached = false
		local pedestalPos = LagoonLayout.getPedestalPosition(state.base, slot)
		local startTime = os.clock()
		while os.clock() - startTime < CARRY_SECONDS do
			local currentState = PirateState.getState(player)
			if not currentState or currentState.carrying ~= state.carrying then
				break
			end
			local currentCharacter = player.Character
			if not currentCharacter then
				break
			end
			local rootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
			if not rootPart then
				break
			end
			if not model.Parent then
				break
			end
			model:PivotTo(CFrame.new(rootPart.Position + Vector3.new(0, CARRY_HEIGHT, 0)))
			if (rootPart.Position - pedestalPos).Magnitude <= LAND_DISTANCE then
				reached = true
				break
			end
			task.wait(0.1)
		end
		local finalState = PirateState.getState(player)
		if finalState and finalState.carrying then
			finalState.carrying = nil
			PirateState.broadcast(player, {
				type = "carrying",
				name = nil,
				income = 0,
				stolen = false,
			})
		end
		landBrainrotOnPedestal(player, def, mutation, slot, model)
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

-- The purchase flow, guards in order. Does nothing when the rider is no
-- longer on the chute. Ownership is recorded at purchase: payment is
-- taken, the brainrot is assigned to the free slot (which marks it found
-- in the Captain's Log), and only then does the visual carry home begin.
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
	local freeSlot = PirateState.getFreeSlot(player)
	if not freeSlot then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Your deck is FULL! Buy a pedestal first.",
			color = "red",
		})
		return
	end
	if not PirateState.spendCash(player, rider.price) then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Not enough doubloons for " .. rider.def.name .. "!",
			color = "red",
		})
		return
	end
	if not PirateState.assignBrainrotToSlot(player, freeSlot, rider.def.id, rider.mutation) then
		PirateState.addCash(player, rider.price)
		PirateState.broadcast(player, {
			type = "feed",
			text = "Could not place " .. rider.def.name .. " — refunded!",
			color = "red",
		})
		return
	end
	BountyService.addBountyProgress(player, "buy", 1)
	TreasureChuteService.despawnConveyorBrainrot(index)
	TreasureChuteService.carryBrainrotHome(player, rider.def, rider.mutation, freeSlot)
end

-- Pre-populates 3 riders at progress 0, 45, and 90 studs so the chute is
-- never empty in the first seconds, then starts the spawn loop (a new
-- rider every 6 seconds) and the movement loop (stepped every 0.1s).
function TreasureChuteService.startChuteLoop()
	for _, progress in ipairs({ 0, 45, 90 }) do
		local rider = TreasureChuteService.spawnConveyorBrainrot()
		rider.progress = progress
		if rider.model then
			rider.model:PivotTo(CFrame.new(chutePosition(progress)))
		end
	end
	task.spawn(function()
		while true do
			task.wait(SPAWN_INTERVAL_SECONDS)
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
