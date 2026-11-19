-- PlunderService: stealing, slapping and locking. A thief carries the stolen
-- brainrot over their head and must reach their own deck. A slap knocks it
-- loose. A lock seals a deck behind a cannon-net dome.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local RivalCrewService = require(script.Parent.RivalCrewService)

local PlunderService = {}
PlunderService.LOCK_BASE_SECONDS = 40
PlunderService.LOCK_COOLDOWN_SECONDS = 60

function PlunderService.attachStealClicker(model, owner, slot)
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = 40
	clicker.MouseClick:Connect(function(player)
		if player ~= owner then
			PlunderService.startStealBrainrot(player, owner, slot)
		end
	end)
	clicker.Parent = model.PrimaryPart
end

function PlunderService.startStealBrainrot(player, targetPlayer, slot)
	local state = PirateState.getState(player)
	local targetState = PirateState.getState(targetPlayer)
	if not state or not targetState then return false end
	if state.carrying then
		PirateState.broadcast(player, { type = "feed", text = "You are already carrying a brainrot!", color = "red" })
		return false
	end
	if PirateState.getFreeSlot(player) == nil then
		PirateState.broadcast(player, { type = "feed", text = "Your deck is FULL! Buy a pedestal first.", color = "red" })
		return false
	end
	if PirateState.isBaseLocked(targetPlayer) then
		PirateState.broadcast(player, { type = "feed", text = targetPlayer.Name .. "'s deck is LOCKED!", color = "red" })
		return false
	end
	if not player.Character then
		return false
	end
	local stolen = PirateState.clearBaseSlot(targetPlayer, slot)
	if not stolen then return false end
	local def = BootyCatalog.getBrainrotDefinition(stolen.defId)
	PlunderService.carryStolenBrainrot(player, def, stolen.mutation, targetPlayer, slot)
	PirateState.broadcastAll({ type = "feed", text = player.Name .. " STOLE " .. def.name .. " from " .. targetPlayer.Name .. "!", color = "red" })
	return true
end

function PlunderService.carryStolenBrainrot(player, def, mutation, fromPlayer, fromSlot)
	local character = player.Character
	local state = PirateState.getState(player)
	if not state or not character then return end
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "STOLEN! RUN HOME!")
	model.Parent = workspace
	state.carrying = { defId = def.id, mutation = mutation, model = model, fromPlayer = fromPlayer, fromSlot = fromSlot }
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
		PlunderService.dropCarriedBrainrot(player)
		PirateState.broadcast(player, { type = "feed", text = "Too slow! " .. def.name .. " went back to " .. fromPlayer.Name .. "'s deck.", color = "red" })
		return
	end
	state.carrying = nil
	local slot = PirateState.getFreeSlot(player)
	if slot then
		PirateState.assignBrainrotToSlot(player, slot, def.id, mutation)
		PirateState.setPedestalModel(player, slot, model)
		local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
		RigBuilder.replaceOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
		PlunderService.attachStealClicker(model, player, slot)
		model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
		PirateState.broadcast(player, { type = "carrying", name = nil })
		BountyService.addBountyProgress(player, "steal", 1)
		BountyService.checkBountyCompletion(player)
		PirateState.broadcastAll({ type = "feed", text = player.Name .. " got away with " .. def.name .. "!", color = "gold" })
	else
		model:Destroy()
	end
end

function PlunderService.dropCarriedBrainrot(player)
	local state = PirateState.getState(player)
	if not state or not state.carrying then return end
	local carried = state.carrying
	state.carrying = nil
	PirateState.broadcast(player, { type = "carrying", name = nil })
	if carried.fromPlayer and carried.fromSlot then
		local fromState = PirateState.getState(carried.fromPlayer)
		if fromState and fromState.slots[carried.fromSlot] == nil then
			fromState.slots[carried.fromSlot] = { defId = carried.defId, mutation = carried.mutation }
			PirateState.broadcast(carried.fromPlayer, { type = "slots", slots = fromState.slots })
			if carried.model then
				local def = BootyCatalog.getBrainrotDefinition(carried.defId)
				local income = BootyCatalog.calculateBrainrotIncome(def, carried.mutation, PirateState.getRebirthMultiplier(carried.fromPlayer))
				RigBuilder.replaceOverheadBillboard(carried.model, def, carried.mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
				PlunderService.attachStealClicker(carried.model, carried.fromPlayer, carried.fromSlot)
				carried.model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(fromState.base, carried.fromSlot)))
				PirateState.setPedestalModel(carried.fromPlayer, carried.fromSlot, carried.model)
			end
			return
		end
	end
	if carried.fromRival and carried.fromSlot then
		RivalCrewService.restoreRivalSlot(carried.fromSlot, carried.defId, carried.mutation, carried.model)
		return
	end
	if carried.model then
		carried.model:Destroy()
	end
end

function PlunderService.handleSlapPlayer(slapper, victim)
	if slapper == victim then return end
	local slapperChar = slapper.Character
	local victimChar = victim.Character
	if not slapperChar or not victimChar then return end
	local slapperRoot = slapperChar:FindFirstChild("HumanoidRootPart")
	local victimRoot = victimChar:FindFirstChild("HumanoidRootPart")
	if not slapperRoot or not victimRoot then return end
	if (slapperRoot.Position - victimRoot.Position).Magnitude > 14 then
		return
	end
	local direction = (victimRoot.Position - slapperRoot.Position).Unit
	victimRoot.AssemblyLinearVelocity = direction * 30 + Vector3.new(0, 12, 0)
	local victimState = PirateState.getState(victim)
	if victimState and victimState.carrying and (victimState.carrying.fromPlayer or victimState.carrying.fromRival) then
		PlunderService.dropCarriedBrainrot(victim)
		PirateState.broadcastAll({ type = "feed", text = slapper.Name .. " SLAPPED " .. victim.Name .. " and the brainrot dropped!", color = "gold" })
	end
end

function PlunderService.activateBaseLock(player)
	local state = PirateState.getState(player)
	if not state then return false end
	local now = os.clock()
	if now < state.lockCooldownUntil then
		PirateState.broadcast(player, { type = "feed", text = "Lock recharging: " .. tostring(math.ceil(state.lockCooldownUntil - now)) .. "s", color = "red" })
		return false
	end
	local duration = PlunderService.LOCK_BASE_SECONDS + 10 * PirateState.getUpgradeLevel(player, "lock")
	PirateState.setBaseLockUntil(player, now + duration)
	state.lockCooldownUntil = now + duration + PlunderService.LOCK_COOLDOWN_SECONDS
	local dome = LagoonLayout.getLockDome(state.base)
	if dome then
		dome.Transparency = 0.55
		task.delay(duration, function()
			if dome then
				dome.Transparency = 1
			end
		end)
	end
	PirateState.broadcast(player, { type = "lock", remaining = math.ceil(duration) })
	BountyService.addBountyProgress(player, "lock", 1)
	return true
end

function PlunderService.expireBaseLocks()
	for player, state in pairs(PirateState.players) do
		if state.lockUntil > 0 and os.clock() >= state.lockUntil then
			state.lockUntil = 0
			PirateState.broadcast(player, { type = "lock", remaining = 0 })
		end
	end
end

return PlunderService
