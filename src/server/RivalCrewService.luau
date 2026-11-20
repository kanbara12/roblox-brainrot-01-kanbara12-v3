-- RivalCrewService.luau
-- A solo rival's deck north of the chute, so stealing is playable with one
-- player in the server. Six mid-tier brainrots sit on the rival pedestals,
-- the rival locks its deck on a timer, and a stolen rival brainrot grows
-- back after 30 seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local RivalCrewService = {}

-- Module state: the rival's six slots, each nil or { defId, mutation, model }.
local rivalSlots = {}
-- The clock time until which the rival deck is locked (0 = unlocked).
local rivalLockUntil = 0
-- The rival pool: 14 mid-tier brainrot definition ids.
local RIVAL_POOL = { 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
-- The rival deck size.
local RIVAL_SLOTS = 6
-- The rival lock cycle: lock after 75 seconds, locked for 25 seconds.
local LOCK_WAIT = 75
local LOCK_DURATION = 25
-- The regrow delay after a rival brainrot is stolen.
local REGROW_DELAY = 30
-- How far above the thief's head a stolen brainrot floats.
local CARRY_HEIGHT = 4
-- How close the thief must get to the target pedestal to land.
local LAND_DISTANCE = 10
-- The maximum steal carry-home time in seconds.
local CARRY_TIMEOUT = 30

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

-- Attaches a ClickDetector (40 studs) to a rival pedestal model; a click
-- starts a steal from that rival slot.
function RivalCrewService.attachRivalStealClicker(model, slot)
	local clickPart = getClickPart(model)
	if not clickPart then
		return
	end
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 40
	clickDetector.Parent = clickPart
	clickDetector.MouseClick:Connect(function(player)
		RivalCrewService.handleStealFromRivalPlot(player, slot)
	end)
end

-- Attaches a ClickDetector (40 studs) to a brainrot that was stolen from the
-- rival and deposited on a player deck, so it stays stealable by others. A
-- click by anyone other than the owner starts a steal from that player slot.
-- PlunderService is required lazily inside the click callback only; a
-- load-time require here would be circular (PlunderService requires this
-- module).
function RivalCrewService.attachDeckStealClicker(model, owner, slot)
	local clickPart = getClickPart(model)
	if not clickPart then
		return
	end
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 40
	clickDetector.Parent = clickPart
	clickDetector.MouseClick:Connect(function(player)
		if player ~= owner then
			local PlunderService = require(script.Parent.PlunderService)
			PlunderService.startStealBrainrot(player, owner, slot)
		end
	end)
end

-- Returns true while the clock is before the rival lock expiry.
function RivalCrewService.isRivalLocked()
	return os.clock() < rivalLockUntil
end

-- Fills one rival slot with a random brainrot from the pool and a random
-- mutation: builds the rig, computes income at rebirth multiplier 1,
-- attaches a billboard reading "+<income>/s", places the model on the rival
-- pedestal, attaches a rival steal clicker, and records the slot.
function RivalCrewService.fillRivalSlot(slot)
	local defId = RIVAL_POOL[math.random(1, #RIVAL_POOL)]
	local def = BootyCatalog.getBrainrotDefinition(defId)
	if not def then
		return
	end
	local mutation = BootyCatalog.rollMutationModifier()
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, 1)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	local pedestalPos = LagoonLayout.getPedestalPosition("R", slot)
	model:PivotTo(CFrame.new(pedestalPos))
	model.Parent = Workspace
	RivalCrewService.attachRivalStealClicker(model, slot)
	rivalSlots[slot] = { defId = defId, mutation = mutation, model = model }
end

-- Fills rival slots 1-6 and starts the rival lock timer.
function RivalCrewService.populateSoloRivalPlot()
	for slot = 1, RIVAL_SLOTS do
		RivalCrewService.fillRivalSlot(slot)
	end
	task.spawn(function()
		while true do
			task.wait(LOCK_WAIT)
			rivalLockUntil = os.clock() + LOCK_DURATION
			local dome = LagoonLayout.getLockDome("R")
			if dome then
				dome.Transparency = 0.55
			end
			PirateState.broadcastAll({
				type = "feed",
				text = "The rival crew LOCKED their deck for 25s!",
				color = "blue",
			})
			task.wait(LOCK_DURATION)
			rivalLockUntil = 0
			if dome then
				dome.Transparency = 1
			end
		end
	end)
end

-- Puts a brainrot back on a rival slot. If the slot is already occupied,
-- the passed model is destroyed and nothing else happens. Otherwise the slot
-- is recorded, and if a model was passed its billboard is replaced with
-- "+<income>/s" (income at multiplier 1), a rival steal clicker is attached,
-- and it is placed on the rival pedestal.
function RivalCrewService.restoreRivalSlot(slot, defId, mutation, model)
	if rivalSlots[slot] ~= nil then
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
		RivalCrewService.attachRivalStealClicker(model, slot)
		local pedestalPos = LagoonLayout.getPedestalPosition("R", slot)
		model:PivotTo(CFrame.new(pedestalPos))
	end
end

-- The carry home for a rival brainrot. Same shape as the player-steal carry:
-- the model floats overhead (billboard "STOLEN! RUN HOME!", carrying message
-- with stolen = true) for up to 30 seconds, heading for the first free
-- slot's pedestal (within 10 studs). If interrupted, it ends silently. If
-- time runs out, the carrying record is cleared, the brainrot is restored to
-- the rival slot, and the thief sees the "Too slow" message. If the thief
-- arrives, the brainrot is assigned to the free slot, a deck steal clicker
-- is attached (so it stays stealable), and a steal bounty progresses.
function RivalCrewService.carryRivalBrainrotHome(player, def, mutation, fromSlot)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local targetSlot = PirateState.getFreeSlot(player)
	if not targetSlot then
		return
	end
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "STOLEN! RUN HOME!")
	model.Parent = Workspace
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
	task.spawn(function()
		local startTime = os.clock()
		local reached = false
		while os.clock() - startTime < CARRY_TIMEOUT do
			local currentState = PirateState.getState(player)
			if not currentState then
				return
			end
			local carrying = currentState.carrying
			if not carrying or carrying.model ~= model then
				return
			end
			if not model.Parent then
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
			model:PivotTo(CFrame.new(root.Position + Vector3.new(0, CARRY_HEIGHT, 0)))
			local pedestalPos = LagoonLayout.getPedestalPosition(currentState.base, targetSlot)
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
		if not carrying or carrying.model ~= model then
			return
		end
		if reached then
			local freeSlot = PirateState.getFreeSlot(player)
			finalState.carrying = nil
			PirateState.broadcast(player, {
				type = "carrying",
				name = nil,
			})
			if not freeSlot then
				model:Destroy()
				return
			end
			local assigned = PirateState.assignBrainrotToSlot(player, freeSlot, def.id, mutation)
			if not assigned then
				model:Destroy()
				return
			end
			local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
			RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
			local pedestalPos = LagoonLayout.getPedestalPosition(finalState.base, freeSlot)
			model:PivotTo(CFrame.new(pedestalPos))
			PirateState.setPedestalModel(player, freeSlot, model)
			RivalCrewService.attachDeckStealClicker(model, player, freeSlot)
			BountyService.addBountyProgress(player, "steal", 1)
			PirateState.broadcastAll({
				type = "feed",
				text = player.Name .. " got away with " .. def.name .. "!",
				color = "gold",
			})
		else
			finalState.carrying = nil
			PirateState.broadcast(player, {
				type = "carrying",
				name = nil,
			})
			RivalCrewService.restoreRivalSlot(fromSlot, def.id, mutation, model)
			PirateState.broadcast(player, {
				type = "feed",
				text = "Too slow! " .. def.name .. " went back to the rival deck.",
				color = "red",
			})
		end
	end)
end

-- The rival steal flow. Guards, in order: the thief must have state; must
-- not already be carrying; must have a free deck slot; the rival must not be
-- locked; the thief must have a character; the rival slot must be occupied.
-- The rival slot is cleared and its model destroyed, the carry home begins,
-- and all see the steal feed. Thirty seconds later, if the slot is still
-- empty, it is refilled. Returns true when the steal starts.
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
	if not player.Character then
		return false
	end
	local rivalEntry = rivalSlots[slot]
	if not rivalEntry then
		return false
	end
	local def = BootyCatalog.getBrainrotDefinition(rivalEntry.defId)
	if not def then
		return false
	end
	local mutation = rivalEntry.mutation
	if rivalEntry.model then
		rivalEntry.model:Destroy()
	end
	rivalSlots[slot] = nil
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. " STOLE " .. def.name .. " from the rival crew!",
		color = "red",
	})
	RivalCrewService.carryRivalBrainrotHome(player, def, mutation, slot)
	task.delay(REGROW_DELAY, function()
		if rivalSlots[slot] == nil then
			RivalCrewService.fillRivalSlot(slot)
		end
	end)
	return true
end

return RivalCrewService
