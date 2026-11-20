-- RivalCrewService — the solo rival deck.
-- A solo rival's deck north of the chute, so stealing is playable with one
-- player in the server. Six mid-tier brainrots sit on the rival pedestals,
-- the rival locks its deck on a timer, and a stolen rival brainrot grows
-- back after 30 seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local PirateState = require(script.Parent:WaitForChild("PirateState"))
local BountyService = require(script.Parent:WaitForChild("BountyService"))

-- NOTE: PlunderService requires this module, so this module must NEVER
-- require PlunderService at load time. The deck-steal clicker requires it
-- lazily, inside the click callback only.

local RivalCrewService = {}

local rivalSlots = {} -- slots 1-6, each nil or { defId, mutation, model }
local rivalLockUntil = 0

-- The rival pool: 14 mid-tier brainrots (defIds 6-19).
local RIVAL_POOL = { 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
local RIVAL_SLOT_COUNT = 6
local LOCK_WAIT = 75
local LOCK_DURATION = 25
local REGROW_SECONDS = 30
local CARRY_SECONDS = 30
local CARRY_STEP = 0.1
local REACH_DISTANCE = 10
local CARRY_HEIGHT = 4
local CLICK_DISTANCE = 40

--------------------------------------------------------------------------------
-- Steal clickers
--------------------------------------------------------------------------------

function RivalCrewService.attachRivalStealClicker(model, slot)
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = CLICK_DISTANCE
	detector.Parent = model.PrimaryPart
	detector.MouseClick:Connect(function(player)
		RivalCrewService.handleStealFromRivalPlot(player, slot)
	end)
end

-- Attaches a clicker to a brainrot stolen from the rival and deposited on a
-- player deck, so it stays stealable by others. The PlunderService require
-- is lazy, inside the callback, to avoid a load-time circular require.
function RivalCrewService.attachDeckStealClicker(model, owner, slot)
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = CLICK_DISTANCE
	detector.Parent = model.PrimaryPart
	detector.MouseClick:Connect(function(player)
		if player ~= owner then
			local PlunderService = require(script.Parent:WaitForChild("PlunderService"))
			PlunderService.startStealBrainrot(player, owner, slot)
		end
	end)
end

--------------------------------------------------------------------------------
-- Rival lock
--------------------------------------------------------------------------------

function RivalCrewService.isRivalLocked()
	return os.clock() < rivalLockUntil
end

local function startRivalLockTimer()
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

--------------------------------------------------------------------------------
-- Filling slots
--------------------------------------------------------------------------------

function RivalCrewService.fillRivalSlot(slot)
	local defId = RIVAL_POOL[math.random(1, #RIVAL_POOL)]
	local def = BootyCatalog.getBrainrotDefinition(defId)
	local mutation = BootyCatalog.rollMutationModifier()
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, 1)
	RigBuilder.attachOverheadBillboard(
		model,
		def,
		mutation,
		"+" .. BootyCatalog.formatMoney(income) .. "/s"
	)
	model.Parent = workspace
	model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition("R", slot)))
	RivalCrewService.attachRivalStealClicker(model, slot)
	rivalSlots[slot] = { defId = defId, mutation = mutation, model = model }
end

function RivalCrewService.populateSoloRivalPlot()
	for slot = 1, RIVAL_SLOT_COUNT do
		RivalCrewService.fillRivalSlot(slot)
	end
	startRivalLockTimer()
end

--------------------------------------------------------------------------------
-- Stealing from the rival
--------------------------------------------------------------------------------

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
	-- The stolen brainrot grows back after 30 seconds, if the slot is
	-- still empty.
	task.delay(REGROW_SECONDS, function()
		if not rivalSlots[slot] then
			RivalCrewService.fillRivalSlot(slot)
		end
	end)
	return true
end

function RivalCrewService.carryRivalBrainrotHome(player, def, mutation, fromSlot)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "STOLEN! RUN HOME!")
	model.Parent = workspace
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local startPos = root and root.Position or character:GetPivot().Position
	model:PivotTo(CFrame.new(startPos + Vector3.new(0, CARRY_HEIGHT, 0)))
	local record = {
		defId = def.id,
		mutation = mutation,
		model = model,
		fromRival = true,
		fromSlot = fromSlot,
	}
	state.carrying = record
	PirateState.broadcast(player, {
		type = "carrying",
		name = def.name,
		income = 0,
		stolen = true,
	})
	if not character then
		RivalCrewService.restoreRivalSlot(fromSlot, def.id, mutation, model)
		state.carrying = nil
		PirateState.broadcast(player, { type = "carrying", name = nil })
		return
	end
	local targetSlot = PirateState.getFreeSlot(player)
	local pedestalPos = targetSlot
		and LagoonLayout.getPedestalPosition(state.base, targetSlot)
		or nil
	task.spawn(function()
		local arrived = false
		local timedOut = false
		local steps = math.floor(CARRY_SECONDS / CARRY_STEP)
		for step = 1, steps do
			task.wait(CARRY_STEP)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				break
			end
			if not model.Parent then
				break
			end
			local current = PirateState.getState(player)
			if not current or current.carrying ~= record then
				break
			end
			model:PivotTo(CFrame.new(hrp.Position + Vector3.new(0, CARRY_HEIGHT, 0)))
			if pedestalPos and (hrp.Position - pedestalPos).Magnitude <= REACH_DISTANCE then
				arrived = true
				break
			end
			if step == steps then
				timedOut = true
			end
		end
		local current = PirateState.getState(player)
		-- Someone else already handled the carry: end silently.
		if not current or current.carrying ~= record then
			return
		end
		if arrived then
			local slot = PirateState.getFreeSlot(player)
			if not slot then
				current.carrying = nil
				PirateState.broadcast(player, { type = "carrying", name = nil })
				model:Destroy()
				return
			end
			if not PirateState.assignBrainrotToSlot(player, slot, def.id, mutation) then
				current.carrying = nil
				PirateState.broadcast(player, { type = "carrying", name = nil })
				model:Destroy()
				return
			end
			local income = BootyCatalog.calculateBrainrotIncome(
				def,
				mutation,
				PirateState.getRebirthMultiplier(player)
			)
			PirateState.setPedestalModel(player, slot, model)
			RigBuilder.replaceOverheadBillboard(
				model,
				def,
				mutation,
				"+" .. BootyCatalog.formatMoney(income) .. "/s"
			)
			-- A deck steal clicker, so it stays stealable by others.
			RivalCrewService.attachDeckStealClicker(model, player, slot)
			model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
			current.carrying = nil
			PirateState.broadcast(player, { type = "carrying", name = nil })
			BountyService.addBountyProgress(player, "steal", 1)
		else
			current.carrying = nil
			PirateState.broadcast(player, { type = "carrying", name = nil })
			RivalCrewService.restoreRivalSlot(fromSlot, def.id, mutation, model)
			if timedOut then
				PirateState.broadcast(player, {
					type = "feed",
					text = "Too slow! " .. def.name .. " went back to the rival deck.",
					color = "red",
				})
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Restoring a rival slot
--------------------------------------------------------------------------------

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
			RigBuilder.replaceOverheadBillboard(
				model,
				def,
				mutation,
				"+" .. BootyCatalog.formatMoney(income) .. "/s"
			)
			RivalCrewService.attachRivalStealClicker(model, slot)
			model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition("R", slot)))
		else
			model:Destroy()
			rivalSlots[slot].model = nil
		end
	end
end

return RivalCrewService
