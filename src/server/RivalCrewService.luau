-- RivalCrewService: the solo rival's deck north of the chute, so stealing is
-- playable with one player in Studio. Six mid-tier brainrots sit on the
-- rival pedestals, the rival locks its deck on a timer, and a stolen rival
-- brainrot grows back after 30 seconds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)

local RivalCrewService = {}
RivalCrewService.rivalSlots = {}
RivalCrewService.rivalLockUntil = 0
RivalCrewService.RIVAL_POOL = { 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }

function RivalCrewService.attachRivalStealClicker(model, slot)
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = 40
	clicker.MouseClick:Connect(function(player)
		RivalCrewService.handleStealFromRivalPlot(player, slot)
	end)
	clicker.Parent = model.PrimaryPart
end

-- A brainrot stolen from the rival and deposited on a player deck must stay
-- stealable. PlunderService already requires this module, so the require
-- happens lazily inside the click callback, never at load time.
function RivalCrewService.attachDeckStealClicker(model, owner, slot)
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = 40
	clicker.MouseClick:Connect(function(player)
		if player ~= owner then
			local PlunderService = require(script.Parent.PlunderService)
			PlunderService.startStealBrainrot(player, owner, slot)
		end
	end)
	clicker.Parent = model.PrimaryPart
end

function RivalCrewService.isRivalLocked()
	return os.clock() < RivalCrewService.rivalLockUntil
end

function RivalCrewService.populateSoloRivalPlot()
	for slot = 1, 6 do
		RivalCrewService.fillRivalSlot(slot)
	end
	task.spawn(function()
		while true do
			task.wait(75)
			RivalCrewService.rivalLockUntil = os.clock() + 25
			local dome = LagoonLayout.getLockDome("R")
			if dome then dome.Transparency = 0.55 end
			PirateState.broadcastAll({ type = "feed", text = "The rival crew LOCKED their deck for 25s!", color = "blue" })
			task.wait(25)
			RivalCrewService.rivalLockUntil = 0
			if dome then dome.Transparency = 1 end
		end
	end)
end

function RivalCrewService.fillRivalSlot(slot)
	local defId = RivalCrewService.RIVAL_POOL[math.random(1, #RivalCrewService.RIVAL_POOL)]
	local def = BootyCatalog.getBrainrotDefinition(defId)
	local mutation = BootyCatalog.rollMutationModifier()
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, 1)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition("R", slot)))
	model.Parent = workspace
	RivalCrewService.attachRivalStealClicker(model, slot)
	RivalCrewService.rivalSlots[slot] = { defId = def.id, mutation = mutation, model = model }
end

function RivalCrewService.handleStealFromRivalPlot(player, slot)
	local state = PirateState.getState(player)
	if not state then return false end
	if state.carrying then
		PirateState.broadcast(player, { type = "feed", text = "You are already carrying a brainrot!", color = "red" })
		return false
	end
	if PirateState.getFreeSlot(player) == nil then
		PirateState.broadcast(player, { type = "feed", text = "Your deck is FULL! Buy a pedestal first.", color = "red" })
		return false
	end
	if RivalCrewService.isRivalLocked() then
		PirateState.broadcast(player, { type = "feed", text = "The rival deck is LOCKED!", color = "red" })
		return false
	end
	if not player.Character then
		return false
	end
	local stolen = RivalCrewService.rivalSlots[slot]
	if not stolen then return false end
	RivalCrewService.rivalSlots[slot] = nil
	local def = BootyCatalog.getBrainrotDefinition(stolen.defId)
	if stolen.model then
		stolen.model:Destroy()
	end
	RivalCrewService.carryRivalBrainrotHome(player, def, stolen.mutation, slot)
	PirateState.broadcastAll({ type = "feed", text = player.Name .. " STOLE " .. def.name .. " from the rival crew!", color = "red" })
	task.delay(30, function()
		if RivalCrewService.rivalSlots[slot] == nil then
			RivalCrewService.fillRivalSlot(slot)
		end
	end)
	return true
end

function RivalCrewService.carryRivalBrainrotHome(player, def, mutation, fromSlot)
	local character = player.Character
	local state = PirateState.getState(player)
	if not state or not character then return end
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "STOLEN! RUN HOME!")
	model.Parent = workspace
	state.carrying = { defId = def.id, mutation = mutation, model = model, fromRival = true, fromSlot = fromSlot }
	PirateState.broadcast(player, { type = "carrying", name = def.name, income = 0, stolen = true })
	local target = LagoonLayout.getPedestalPosition(state.base, PirateState.getFreeSlot(player) or 1)
	local waited = 0
	local reached = false
	while waited < 30 do
		if not state.carrying or state.carrying.model ~= model then
			return
		end
		local liveCharacter = player.Character
		local humanoidRoot = liveCharacter and liveCharacter:FindFirstChild("HumanoidRootPart")
		if humanoidRoot then
			model:PivotTo(CFrame.new(humanoidRoot.Position + Vector3.new(0, 4, 0)))
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
		PirateState.broadcast(player, { type = "carrying", name = nil })
		RivalCrewService.restoreRivalSlot(fromSlot, def.id, mutation, model)
		PirateState.broadcast(player, { type = "feed", text = "Too slow! " .. def.name .. " went back to the rival deck.", color = "red" })
		return
	end
	state.carrying = nil
	local slot = PirateState.getFreeSlot(player)
	if slot then
		PirateState.assignBrainrotToSlot(player, slot, def.id, mutation)
		PirateState.setPedestalModel(player, slot, model)
		local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
		RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
		RivalCrewService.attachDeckStealClicker(model, player, slot)
		model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
		PirateState.broadcast(player, { type = "carrying", name = nil })
		BountyService.addBountyProgress(player, "steal", 1)
		BountyService.checkBountyCompletion(player)
	else
		model:Destroy()
	end
end

function RivalCrewService.restoreRivalSlot(slot, defId, mutation, model)
	if RivalCrewService.rivalSlots[slot] ~= nil then
		if model then model:Destroy() end
		return
	end
	RivalCrewService.rivalSlots[slot] = { defId = defId, mutation = mutation, model = model }
	if model then
		local def = BootyCatalog.getBrainrotDefinition(defId)
		local income = BootyCatalog.calculateBrainrotIncome(def, mutation, 1)
		RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
		RivalCrewService.attachRivalStealClicker(model, slot)
		model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition("R", slot)))
	end
end

return RivalCrewService
