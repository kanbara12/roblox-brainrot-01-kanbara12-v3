-- PlunderService.luau
-- Stealing from other players' decks, slapping a thief to knock a stolen
-- brainrot loose, and locking your own deck behind a cannon-net dome.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local RivalCrewService = require(script.Parent.RivalCrewService)
local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))

local PlunderService = {}

local BASE_LOCK_SECONDS = 40
local LOCK_BONUS_PER_LEVEL = 10
local LOCK_COOLDOWN_SECONDS = 60
local LOCK_DOME_SHOWN = 0.55
local LOCK_DOME_HIDDEN = 1
local SLAP_RANGE = 14
local SLAP_KNOCKBACK = 30
local SLAP_UPWARD = 12
local CLICK_DISTANCE = 40
local STEAL_SECONDS = 30
local CARRY_HEIGHT = 4
local LAND_DISTANCE = 10

-- Attaches a ClickDetector (40 studs) to a pedestal model's primary part.
-- A click by anyone other than the owner starts a steal from that slot.
function PlunderService.attachStealClicker(model, owner, slot)
	if not model or not model.PrimaryPart then
		return
	end
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = CLICK_DISTANCE
	clicker.Parent = model.PrimaryPart
	clicker.MouseClick:Connect(function(clickingPlayer)
		if clickingPlayer ~= owner then
			PlunderService.startStealBrainrot(clickingPlayer, owner, slot)
		end
	end)
end

-- Drops whatever the player is carrying. Clears the carrying record and
-- tells the client it is no longer carrying. A brainrot stolen from
-- another player goes back to that player's slot when it is still empty
-- (slot record restored, model re-placed on the victim's pedestal with an
-- income billboard and a steal clicker). A brainrot stolen from the rival
-- goes back to the rival slot. Otherwise the model is destroyed.
function PlunderService.dropCarriedBrainrot(player)
	local state = PirateState.getState(player)
	if not state or not state.carrying then
		return
	end
	local carrying = state.carrying
	state.carrying = nil
	PirateState.broadcast(player, {
		type = "carrying",
		name = nil,
		income = 0,
		stolen = false,
	})
	if carrying.fromPlayer and carrying.fromSlot then
		local victimState = PirateState.getState(carrying.fromPlayer)
		if victimState and not victimState.slots[carrying.fromSlot] then
			victimState.slots[carrying.fromSlot] = { defId = carrying.defId, mutation = carrying.mutation }
			PirateState.broadcast(carrying.fromPlayer, {
				type = "slots",
				slots = victimState.slots,
			})
			if carrying.model then
				local def = BootyCatalog.getBrainrotDefinition(carrying.defId)
				local income = BootyCatalog.calculateBrainrotIncome(def, carrying.mutation, PirateState.getRebirthMultiplier(carrying.fromPlayer))
				RigBuilder.replaceOverheadBillboard(carrying.model, def, carrying.mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
				local pedestalPos = LagoonLayout.getPedestalPosition(victimState.base, carrying.fromSlot)
				carrying.model:PivotTo(CFrame.new(pedestalPos))
				PirateState.setPedestalModel(carrying.fromPlayer, carrying.fromSlot, carrying.model)
				PlunderService.attachStealClicker(carrying.model, carrying.fromPlayer, carrying.fromSlot)
			end
		else
			if carrying.model then
				carrying.model:Destroy()
			end
		end
	elseif carrying.fromRival and carrying.fromSlot then
		RivalCrewService.restoreRivalSlot(carrying.fromSlot, carrying.defId, carrying.mutation, carrying.model)
	else
		if carrying.model then
			carrying.model:Destroy()
		end
	end
end

-- The carry home for a stolen brainrot. The model floats overhead
-- (billboard "STOLEN! RUN HOME!") for up to 30 seconds, heading for the
-- thief's first free slot's pedestal (within 10 studs). If the carry is
-- interrupted (the carrying record changes or the model disappears) it
-- ends silently. If time runs out, the brainrot drops back to the victim
-- and the thief is told they were too slow. If the thief arrives, the
-- brainrot is assigned to the free slot, the model is placed on the
-- pedestal with an income billboard and a steal clicker, a steal bounty
-- progresses, and everyone sees the getaway.
function PlunderService.carryStolenBrainrot(player, def, mutation, fromPlayer, fromSlot)
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
		fromPlayer = fromPlayer,
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
			PlunderService.dropCarriedBrainrot(player)
			PirateState.broadcast(player, {
				type = "feed",
				text = "Too slow! " .. def.name .. " went back to " .. fromPlayer.Name .. "'s deck.",
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
		PlunderService.attachStealClicker(model, player, freeSlot)
		BountyService.addBountyProgress(player, "steal", 1)
		PirateState.broadcastAll({
			type = "feed",
			text = player.Name .. " got away with " .. def.name .. "!",
			color = "gold",
		})
	end)
end

-- The steal flow, guards in order. Returns true when the steal starts,
-- false otherwise. The brainrot is removed from the victim's slot
-- immediately and the thief carries it home.
function PlunderService.startStealBrainrot(player, targetPlayer, slot)
	local state = PirateState.getState(player)
	local targetState = PirateState.getState(targetPlayer)
	if not state or not targetState then
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
	if PirateState.isBaseLocked(targetPlayer) then
		PirateState.broadcast(player, {
			type = "feed",
			text = targetPlayer.Name .. "'s deck is LOCKED!",
			color = "red",
		})
		return false
	end
	if not player.Character then
		return false
	end
	local entry = targetState.slots[slot]
	if not entry then
		return false
	end
	local def = BootyCatalog.getBrainrotDefinition(entry.defId)
	if not def then
		return false
	end
	PirateState.clearBaseSlot(targetPlayer, slot)
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. " STOLE " .. def.name .. " from " .. targetPlayer.Name .. "!",
		color = "red",
	})
	PlunderService.carryStolenBrainrot(player, def, entry.mutation, targetPlayer, slot)
	return true
end

-- The slap. Does nothing when the slapper and victim are the same player,
-- when either has no character or HumanoidRootPart, or when they are more
-- than 14 studs apart. Otherwise the victim is knocked back away from the
-- slapper (30 studs/s plus 12 studs/s upward). A victim carrying a stolen
-- brainrot drops it and everyone sees the drop.
function PlunderService.handleSlapPlayer(slapper, victim)
	if slapper == victim then
		return
	end
	local slapperCharacter = slapper.Character
	local victimCharacter = victim.Character
	if not slapperCharacter or not victimCharacter then
		return
	end
	local slapperRoot = slapperCharacter:FindFirstChild("HumanoidRootPart")
	local victimRoot = victimCharacter:FindFirstChild("HumanoidRootPart")
	if not slapperRoot or not victimRoot then
		return
	end
	local offset = victimRoot.Position - slapperRoot.Position
	if offset.Magnitude > SLAP_RANGE then
		return
	end
	local direction = offset.Unit
	victimRoot.AssemblyLinearVelocity = direction * SLAP_KNOCKBACK + Vector3.new(0, SLAP_UPWARD, 0)
	local victimState = PirateState.getState(victim)
	if victimState and victimState.carrying then
		local carrying = victimState.carrying
		if carrying.fromPlayer or carrying.fromRival then
			PlunderService.dropCarriedBrainrot(victim)
			PirateState.broadcastAll({
				type = "feed",
				text = slapper.Name .. " SLAPPED " .. victim.Name .. " and the brainrot dropped!",
				color = "gold",
			})
		end
	end
end

-- The lock. Guards: the player must have state, and the lock must not be
-- recharging. Duration is 40 + 10 seconds per IRON NET level. The lock
-- expiry and a 60-second cooldown are set, the dome is shown and hidden
-- again after the duration, the owner gets a lock message, and a lock
-- bounty progresses. Returns true on success, false otherwise.
function PlunderService.activateBaseLock(player)
	local state = PirateState.getState(player)
	if not state then
		return false
	end
	local now = os.clock()
	if now < state.lockCooldownUntil then
		local remaining = math.ceil(state.lockCooldownUntil - now)
		PirateState.broadcast(player, {
			type = "feed",
			text = "Lock recharging: " .. remaining .. "s",
			color = "red",
		})
		return false
	end
	local duration = BASE_LOCK_SECONDS + LOCK_BONUS_PER_LEVEL * PirateState.getUpgradeLevel(player, "lock")
	local lockUntil = now + duration
	state.lockCooldownUntil = now + duration + LOCK_COOLDOWN_SECONDS
	PirateState.setBaseLockUntil(player, lockUntil)
	local dome = LagoonLayout.getLockDome(state.base)
	if dome then
		dome.Transparency = LOCK_DOME_SHOWN
		task.delay(duration, function()
			if not PirateState.isBaseLocked(player) then
				dome.Transparency = LOCK_DOME_HIDDEN
			end
		end)
	end
	BountyService.addBountyProgress(player, "lock", 1)
	return true
end

-- A sweep over all players: any player whose lock expiry is set and has
-- passed gets the lock cleared (expiry 0) and a lock message with
-- remaining 0. Driven by init.server every 5 seconds.
function PlunderService.expireBaseLocks()
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and state.lockUntil > 0 and os.clock() >= state.lockUntil then
			state.lockUntil = 0
			PirateState.broadcast(player, {
				type = "lock",
				remaining = 0,
			})
		end
	end
end

return PlunderService
