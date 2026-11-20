-- RivalCrewService.luau
-- The solo rival deck north of the chute, so stealing is playable with one
-- player in the server. Six mid-tier brainrots sit on the rival pedestals,
-- the rival locks its deck on a timer, and a stolen rival brainrot grows
-- back after 30 seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))

local RivalCrewService = {}

-- Rival slots 1-6, each nil or { defId, mutation, model }.
local rivalSlots = {}
-- Clock time until which the rival deck is locked (0 = not locked).
local rivalLockUntil = 0
-- The rival pool: 14 mid-tier brainrot defIds.
local RIVAL_POOL = { 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
local RIVAL_SLOT_COUNT = 6
local RIVAL_PREFIX = "R"
local CLICK_DISTANCE = 40
local STEAL_SECONDS = 30
local CARRY_HEIGHT = 4
local LAND_DISTANCE = 10
local LOCK_WAIT_SECONDS = 75
local LOCK_DURATION_SECONDS = 25
local REGROW_SECONDS = 30

-- Attaches a ClickDetector (40 studs) to a rival pedestal model; a click
-- starts a steal from that rival slot.
function RivalCrewService.attachRivalStealClicker(model, slot)
	if not model or not model.PrimaryPart then
		return
	end
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = CLICK_DISTANCE
	clicker.Parent = model.PrimaryPart
	clicker.MouseClick:Connect(function(clickingPlayer)
		RivalCrewService.handleStealFromRivalPlot(clickingPlayer, slot)
	end)
end

-- Attaches a ClickDetector (40 studs) to a brainrot that was stolen from
-- the rival and deposited on a player deck, so it stays stealable by
-- others. A click by anyone other than the owner starts a steal from that
-- player slot. PlunderService is required lazily, inside the click
-- callback only -- never at load time, because PlunderService already
-- requires this module (a load-time require here would be circular).
function RivalCrewService.attachDeckStealClicker(model, owner, slot)
	if not model or not model.PrimaryPart then
		return
	end
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = CLICK_DISTANCE
	clicker.Parent = model.PrimaryPart
	clicker.MouseClick:Connect(function(clickingPlayer)
		if clickingPlayer ~= owner then
			local PlunderService = require(script.Parent.PlunderService)
			PlunderService.startStealBrainrot(clickingPlayer, owner, slot)
		end
	end)
end

-- True while the clock is before the rival lock expiry.
function RivalCrewService.isRivalLocked()
	return os.clock() < rivalLockUntil
end

-- Fills one rival slot with a random brainrot from the pool and a random
-- mutation: builds the rig, computes income at rebirth multiplier 1,
-- attaches an income billboard, places the model on the rival pedestal,
-- attaches a rival steal clicker, and records the slot.
function RivalCrewService.fillRivalSlot(slot)
	local defId = RIVAL_POOL[math.random(1, #RIVAL_POOL)]
	local mutation = BootyCatalog.rollMutationModifier()
	local def = BootyCatalog.getBrainrotDefinition(defId)
	if not def then
		return
	end
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, 1)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	local pedestalPos = LagoonLayout.getPedestalPosition(RIVAL_PREFIX, slot)
	model:PivotTo(CFrame.new(pedestalPos))
	model.Parent = workspace
	RivalCrewService.attachRivalStealClicker(model, slot)
	rivalSlots[slot] = { defId = defId, mutation = mutation, model = model }
end

-- Fills rival slots 1-6 and starts the rival lock timer: a background
-- loop waits 75 seconds, locks the rival deck for 25 seconds (dome shown,
-- feed to all), unlocks it, and repeats forever.
function RivalCrewService.populateSoloRivalPlot()
	for slot = 1, RIVAL_SLOT_COUNT do
		RivalCrewService.fillRivalSlot(slot)
	end
	task.spawn(function()
		while true do
			task.wait(LOCK_WAIT_SECONDS)
			rivalLockUntil = os.clock() + LOCK_DURATION_SECONDS
			local dome = LagoonLayout.getLockDome(RIVAL_PREFIX)
			if dome then
				dome.Transparency = 0.55
			end
			PirateState.broadcastAll({
				type = "feed",
				text = "The rival crew LOCKED their deck for 25s!",
				color = "blue",
			})
			task.wait(LOCK_DURATION_SECONDS)
			rivalLockUntil = 0
			if dome then
				dome.Transparency = 1
			end
		end
	end)
end

-- Puts a brainrot back on a rival slot. When the slot is already occupied
-- the passed model is destroyed and nothing else happens. Otherwise the
-- slot is recorded and, when a model was passed, its billboard is replaced
-- with an income line (multiplier 1), a rival steal clicker is attached,
-- and it is placed on the rival pedestal.
function RivalCrewService.restoreRivalSlot(slot, defId, mutation, model)
	if rivalSlots[slot] then
		if model then
			model:Destroy()
		end
		return
	end
	rivalSlots[slot] = { defId = defId, mutation = mutation, model = model }
	if model then
		local def = BootyCatalog.getBrainrotDefinition(defId)
		if def then
			local income = BootyCatalog.calculateBrainrotIncome(def, mutation, 1)
			RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
		end
		local pedestalPos = LagoonLayout.getPedestalPosition(RIVAL_PREFIX, slot)
		model:PivotTo(CFrame.new(pedestalPos))
		RivalCrewService.attachRivalStealClicker(model, slot)
	end
end

-- The carry home for a rival brainrot. Same shape as the player-steal
-- carry: the model floats overhead (billboard "STOLEN! RUN HOME!") for up
-- to 30 seconds, heading for the thief's first free slot's pedestal
-- (within 10 studs). If interrupted it ends silently. If time runs out,
-- the carrying record is cleared, the brainrot is restored to the rival
-- slot, and the thief is told they were too slow. If the thief arrives,
-- the brainrot is assigned to the free slot, the model is placed on the
-- pedestal with an income billboard and a deck steal clicker (so it stays
-- stealable), and a steal bounty progresses.
function RivalCrewService.carryRivalBrainrotHome(player, def, mutation, fromSlot)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "STOLEN! RUN HOME!")
	model.Parent = workspace
	local carrying = {
		defId = def.id,
		mutation = mutation,
		model = model,
		fromRival = true,
		fromSlot = fromSlot,
	}
	state.carrying = carrying
	PirateState.broadcast(player, {
		type = "carrying",
		name = def.name,
		income = 0,
		stolen = true,
	})
	task.spawn(function()
		local targetSlot = PirateState.getFreeSlot(player)
		local pedestalPos = nil
		if targetSlot then
			pedestalPos = LagoonLayout.getPedestalPosition(state.base, targetSlot)
		end
		local startTime = os.clock()
		local reached = false
		while os.clock() - startTime < STEAL_SECONDS do
			local currentState = PirateState.getState(player)
			if not currentState or currentState.carrying ~= carrying then
				return
			end
			local currentCharacter = player.Character
			if not currentCharacter then
				return
			end
			local rootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
			if not rootPart then
				return
			end
			if not model.Parent then
				return
			end
			model:PivotTo(CFrame.new(rootPart.Position + Vector3.new(0, CARRY_HEIGHT, 0)))
			if pedestalPos and (rootPart.Position - pedestalPos).Magnitude <= LAND_DISTANCE then
				reached = true
				break
			end
			task.wait(0.1)
		end
		local finalState = PirateState.getState(player)
		if not finalState or finalState.carrying ~= carrying then
			return
		end
		if not reached then
			finalState.carrying = nil
			PirateState.broadcast(player, {
				type = "carrying",
				name = nil,
				income = 0,
				stolen = false,
			})
			RivalCrewService.restoreRivalSlot(fromSlot, def.id, mutation, model)
			PirateState.broadcast(player, {
				type = "feed",
				text = "Too slow! " .. def.name .. " went back to the rival deck.",
				color = "red",
			})
			return
		end
		local freeSlot = PirateState.getFreeSlot(player)
		if not freeSlot then
			finalState.carrying = nil
			PirateState.broadcast(player, {
				type = "carrying",
				name = nil,
				income = 0,
				stolen = false,
			})
			model:Destroy()
			return
		end
		if not PirateState.assignBrainrotToSlot(player, freeSlot, def.id, mutation) then
			finalState.carrying = nil
			PirateState.broadcast(player, {
				type = "carrying",
				name = nil,
				income = 0,
				stolen = false,
			})
			model:Destroy()
			return
		end
		finalState.carrying = nil
		PirateState.broadcast(player, {
			type = "carrying",
			name = nil,
			income = 0,
			stolen = false,
		})
		local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
		RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
		local landPos = LagoonLayout.getPedestalPosition(finalState.base, freeSlot)
		model:PivotTo(CFrame.new(landPos))
		PirateState.setPedestalModel(player, freeSlot, model)
		RivalCrewService.attachDeckStealClicker(model, player, freeSlot)
		BountyService.addBountyProgress(player, "steal", 1)
	end)
end

-- The rival steal flow, guards in order. Returns true when the steal
-- starts, false otherwise. The rival slot is cleared and its model
-- destroyed, the carry home begins, and everyone sees the steal. Thirty
-- seconds later, when the slot is still empty, it is refilled.
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
	if not PirateState.getFreeSlot(player) then
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
	if not player.Character then
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
	local mutation = entry.mutation
	if entry.model then
		entry.model:Destroy()
	end
	rivalSlots[slot] = nil
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. " STOLE " .. def.name .. " from the rival crew!",
		color = "red",
	})
	RivalCrewService.carryRivalBrainrotHome(player, def, mutation, slot)
	task.delay(REGROW_SECONDS, function()
		if not rivalSlots[slot] then
			RivalCrewService.fillRivalSlot(slot)
		end
	end)
	return true
end

return RivalCrewService
