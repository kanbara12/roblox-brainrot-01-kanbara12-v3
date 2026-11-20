local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RivalCrewService = {}

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)

local rivalSlots = {}
local rivalLockUntil = 0
local RIVAL_POOL = { 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }

local function getAnchorPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

function RivalCrewService.attachRivalStealClicker(model, slot)
	local anchor = getAnchorPart(model)
	if not anchor then
		return
	end
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = 40
	clicker.Parent = anchor
	clicker.MouseClick:Connect(function(clickingPlayer)
		RivalCrewService.handleStealFromRivalPlot(clickingPlayer, slot)
	end)
end

function RivalCrewService.attachDeckStealClicker(model, owner, slot)
	local anchor = getAnchorPart(model)
	if not anchor then
		return
	end
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = 40
	clicker.Parent = anchor
	clicker.MouseClick:Connect(function(clickingPlayer)
		if clickingPlayer ~= owner then
			local PlunderService = require(script.Parent.PlunderService)
			PlunderService.startStealBrainrot(clickingPlayer, owner, slot)
		end
	end)
end

function RivalCrewService.isRivalLocked()
	return os.clock() < rivalLockUntil
end

function RivalCrewService.fillRivalSlot(slot)
	local defId = RIVAL_POOL[math.random(1, #RIVAL_POOL)]
	local def = BootyCatalog.getBrainrotDefinition(defId)
	if not def then
		return
	end
	local mutation = BootyCatalog.rollMutationModifier()
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, 1)
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	model.Parent = workspace
	model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition("R", slot)))
	RivalCrewService.attachRivalStealClicker(model, slot)
	rivalSlots[slot] = { defId = defId, mutation = mutation, model = model }
end

function RivalCrewService.populateSoloRivalPlot()
	for slot = 1, 6 do
		RivalCrewService.fillRivalSlot(slot)
	end
	task.spawn(function()
		while true do
			task.wait(75)
			rivalLockUntil = os.clock() + 25
			local dome = LagoonLayout.getLockDome("R")
			if dome then
				dome.Transparency = 0.55
			end
			PirateState.broadcastAll({
				type = "feed",
				text = "The rival crew LOCKED their deck for 25s!",
				color = "blue",
			})
			task.wait(25)
			rivalLockUntil = 0
			local domeAfter = LagoonLayout.getLockDome("R")
			if domeAfter then
				domeAfter.Transparency = 1
			end
		end
	end)
end

function RivalCrewService.carryRivalBrainrotHome(player, def, mutation, fromSlot)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "STOLEN! RUN HOME!")
	model.Parent = workspace
	state.carrying = {
		defId = def.id,
		mutation = mutation,
		model = model,
		fromRival = true,
		fromSlot = fromSlot,
	}
	PirateState.broadcast(player, {
		type = "carrying",
		name = def.name,
		income = 0,
		stolen = true,
	})
	local startTime = os.clock()
	local reached = false
	while os.clock() - startTime < 30 do
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
		local freeSlot = PirateState.getFreeSlot(player)
		if freeSlot then
			local pedestalPos = LagoonLayout.getPedestalPosition(currentState.base, freeSlot)
			if (hrp.Position - pedestalPos).Magnitude <= 10 then
				reached = true
				break
			end
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
	if not finalState.carrying or finalState.carrying.model ~= model then
		return
	end
	if reached then
		finalState.carrying = nil
		PirateState.broadcast(player, {
			type = "carrying",
			name = nil,
			income = 0,
			stolen = false,
		})
		local freeSlot = PirateState.getFreeSlot(player)
		if freeSlot then
			local placed = PirateState.assignBrainrotToSlot(player, freeSlot, def.id, mutation)
			if placed then
				local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
				RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
				PirateState.setPedestalModel(player, freeSlot, model)
				RivalCrewService.attachDeckStealClicker(model, player, freeSlot)
				model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(finalState.base, freeSlot)))
				BountyService.addBountyProgress(player, "steal", 1)
				PirateState.broadcastAll({
					type = "feed",
					text = player.Name .. " got away with " .. def.name .. "!",
					color = "gold",
				})
			else
				model:Destroy()
			end
		else
			model:Destroy()
		end
	else
		finalState.carrying = nil
		PirateState.broadcast(player, {
			type = "carrying",
			name = nil,
			income = 0,
			stolen = false,
		})
		PirateState.broadcast(player, {
			type = "feed",
			text = "Too slow! " .. def.name .. " went back to the rival deck.",
			color = "red",
		})
		RivalCrewService.restoreRivalSlot(fromSlot, def.id, mutation, model)
	end
end

function RivalCrewService.handleStealFromRivalPlot(player, slot)
	local state = PirateState.getState(player)
	if not state then
		return false
	end
	if state.carrying then
		PirateState.broadcast(player, {
			type = "feed",
			text = "You are already carrying a brainrot!",
			color = "red",
		})
		return false
	end
	local freeSlot = PirateState.getFreeSlot(player)
	if not freeSlot then
		PirateState.broadcast(player, {
			type = "feed",
			text = "Your deck is FULL! Buy a pedestal first.",
			color = "red",
		})
		return false
	end
	if RivalCrewService.isRivalLocked() then
		PirateState.broadcast(player, {
			type = "feed",
			text = "The rival deck is LOCKED!",
			color = "red",
		})
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local entry = rivalSlots[slot]
	if not entry then
		return false
	end
	local def = BootyCatalog.getBrainrotDefinition(entry.defId)
	if not def then
		return false
	end
	rivalSlots[slot] = nil
	if entry.model then
		entry.model:Destroy()
	end
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. " STOLE " .. def.name .. " from the rival crew!",
		color = "red",
	})
	RivalCrewService.carryRivalBrainrotHome(player, def, entry.mutation, slot)
	task.delay(30, function()
		if not rivalSlots[slot] then
			RivalCrewService.fillRivalSlot(slot)
		end
	end)
	return true
end

function RivalCrewService.restoreRivalSlot(slot, defId, mutation, model)
	if rivalSlots[slot] then
		if model then
			model:Destroy()
		end
		return
	end
	rivalSlots[slot] = { defId = defId, mutation = mutation, model = model }
	if model and model.Parent then
		local def = BootyCatalog.getBrainrotDefinition(defId)
		if def then
			local income = BootyCatalog.calculateBrainrotIncome(def, mutation, 1)
			RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
		end
		RivalCrewService.attachRivalStealClicker(model, slot)
		model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition("R", slot)))
	end
end

return RivalCrewService
