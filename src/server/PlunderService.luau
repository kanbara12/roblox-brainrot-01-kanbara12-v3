-- PlunderService.luau
-- Stealing from other players' decks, slapping a thief to knock a stolen
-- brainrot loose, and locking your own deck behind a cannon-net dome.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local RivalCrewService = require(script.Parent.RivalCrewService)
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local PlunderService = {}

-- The base lock duration in seconds.
local BASE_LOCK_DURATION = 40
-- The lock cooldown in seconds after the lock ends.
local LOCK_COOLDOWN = 60
-- The extra lock seconds per IRON NET level.
local LOCK_PER_LEVEL = 10
-- The slap range in studs.
local SLAP_RANGE = 14
-- The slap knockback speed in studs per second.
local SLAP_KNOCKBACK = 30
-- The slap upward velocity in studs per second.
local SLAP_UPWARD = 12
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

-- Attaches a ClickDetector (40 studs) to a pedestal model's primary part.
-- A click by anyone other than the owner starts a steal from that slot.
function PlunderService.attachStealClicker(model, owner, slot)
	local clickPart = getClickPart(model)
	if not clickPart then
		return
	end
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 40
	clickDetector.Parent = clickPart
	clickDetector.MouseClick:Connect(function(player)
		if player ~= owner then
			PlunderService.startStealBrainrot(player, owner, slot)
		end
	end)
end

-- Drops whatever the player is carrying. Clears the carrying record and
-- tells the client it is no longer carrying. If the brainrot came from
-- another player and that player's slot is still empty, it goes back to the
-- victim's slot (slot record restored, model re-placed on the victim's
-- pedestal with an income billboard and a steal clicker). If it came from
-- the rival, it goes back to the rival slot. Otherwise the model is
-- destroyed.
function PlunderService.dropCarriedBrainrot(player)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local carrying = state.carrying
	if not carrying then
		return
	end
	state.carrying = nil
	PirateState.broadcast(player, {
		type = "carrying",
		name = nil,
	})
	local model = carrying.model
	if carrying.fromPlayer then
		local victim = carrying.fromPlayer
		local fromSlot = carrying.fromSlot
		local victimState = PirateState.getState(victim)
		if victimState and victimState.slots[fromSlot] == nil then
			PirateState.assignBrainrotToSlot(victim, fromSlot, carrying.defId, carrying.mutation)
			if model then
				local def = BootyCatalog.getBrainrotDefinition(carrying.defId)
				local income = 0
				if def then
					income = BootyCatalog.calculateBrainrotIncome(def, carrying.mutation, PirateState.getRebirthMultiplier(victim))
				end
				if def then
					RigBuilder.replaceOverheadBillboard(model, def, carrying.mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
				end
				local pedestalPos = LagoonLayout.getPedestalPosition(victimState.base, fromSlot)
				model:PivotTo(CFrame.new(pedestalPos))
				PirateState.setPedestalModel(victim, fromSlot, model)
				PlunderService.attachStealClicker(model, victim, fromSlot)
			end
		else
			if model then
				model:Destroy()
			end
		end
	elseif carrying.fromRival then
		RivalCrewService.restoreRivalSlot(carrying.fromSlot, carrying.defId, carrying.mutation, model)
	else
		if model then
			model:Destroy()
		end
	end
end

-- The carry home for a stolen brainrot. The model floats overhead (billboard
-- "STOLEN! RUN HOME!", carrying message with stolen = true) for up to 30
-- seconds, heading for the first free slot's pedestal (within 10 studs).
-- If interrupted (the carrying record changes or the model disappears), it
-- ends silently. If the 30 seconds run out, the brainrot drops and the thief
-- sees the "Too slow" message. If the thief reaches the pedestal, the
-- brainrot is assigned to the free slot, the pedestal model is placed, the
-- billboard becomes "+<income>/s", a steal clicker is attached, a steal
-- bounty progresses, and all see the getaway feed.
function PlunderService.carryStolenBrainrot(player, def, mutation, fromPlayer, fromSlot)
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
	model.Parent = game:GetService("Workspace")
	state.carrying = {
		defId = def.id,
		mutation = mutation,
		model = model,
		fromPlayer = fromPlayer,
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
			PlunderService.attachStealClicker(model, player, freeSlot)
			BountyService.addBountyProgress(player, "steal", 1)
			PirateState.broadcastAll({
				type = "feed",
				text = player.Name .. " got away with " .. def.name .. "!",
				color = "gold",
			})
		else
			PlunderService.dropCarriedBrainrot(player)
			local victimName = fromPlayer and fromPlayer.Name or "the rival crew"
			PirateState.broadcast(player, {
				type = "feed",
				text = "Too slow! " .. def.name .. " went back to " .. victimName .. "'s deck.",
				color = "red",
			})
		end
	end)
end

-- The steal flow. Guards, in order: both players must have state; the thief
-- must not already be carrying; the thief must have a free deck slot; the
-- victim's deck must not be locked; the thief must have a character. The
-- brainrot is removed from the victim's slot immediately and the thief
-- carries it home. Returns true when the steal starts, false otherwise.
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
	local freeSlot = PirateState.getFreeSlot(player)
	if not freeSlot then
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
	local stolen = targetState.slots[slot]
	if not stolen then
		return false
	end
	local def = BootyCatalog.getBrainrotDefinition(stolen.defId)
	if not def then
		return false
	end
	PirateState.clearBaseSlot(targetPlayer, slot)
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. " STOLE " .. def.name .. " from " .. targetPlayer.Name .. "!",
		color = "red",
	})
	PlunderService.carryStolenBrainrot(player, def, stolen.mutation, targetPlayer, slot)
	return true
end

-- The slap. Does nothing if slapper and victim are the same player, if
-- either has no character, if either has no HumanoidRootPart, or if they are
-- more than 14 studs apart. Otherwise the victim is knocked back away from
-- the slapper (30 studs/s plus 12 studs/s upward). If the victim is carrying
-- a stolen brainrot, it drops.
function PlunderService.handleSlapPlayer(slapper, victim)
	if slapper == victim then
		return
	end
	local slapperChar = slapper.Character
	local victimChar = victim.Character
	if not slapperChar or not victimChar then
		return
	end
	local slapperRoot = slapperChar:FindFirstChild("HumanoidRootPart")
	local victimRoot = victimChar:FindFirstChild("HumanoidRootPart")
	if not slapperRoot or not victimRoot then
		return
	end
	local offset = victimRoot.Position - slapperRoot.Position
	if offset.Magnitude > SLAP_RANGE then
		return
	end
	local away = Vector3.new(offset.X, 0, offset.Z)
	if away.Magnitude < 0.01 then
		away = Vector3.new(0, 0, 1)
	else
		away = away.Unit
	end
	victimRoot.AssemblyLinearVelocity = away * SLAP_KNOCKBACK + Vector3.new(0, SLAP_UPWARD, 0)
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

-- Activates the player's base lock. Guards: the player must have state; the
-- lock must not be recharging. Duration is 40 + 10 x IRON NET level seconds.
-- The lock expiry is set, the cooldown is set to now + duration + 60s, the
-- deck's lock dome is shown and hidden again after the duration, the owner
-- gets a lock message, and a lock bounty progresses. Returns true on success.
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
	local duration = BASE_LOCK_DURATION + LOCK_PER_LEVEL * PirateState.getUpgradeLevel(player, "lock")
	PirateState.setBaseLockUntil(player, now + duration)
	state.lockCooldownUntil = now + duration + LOCK_COOLDOWN
	local dome = LagoonLayout.getLockDome(state.base)
	if dome then
		dome.Transparency = 0.55
		task.delay(duration, function()
			if dome.Parent then
				dome.Transparency = 1
			end
		end)
	end
	BountyService.addBountyProgress(player, "lock", 1)
	return true
end

-- Clears expired locks: any player whose lock expiry is set and has passed
-- gets the lock cleared (expiry 0) and a lock message with remaining 0.
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
