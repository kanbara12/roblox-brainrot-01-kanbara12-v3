local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlunderService = {}

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local RivalCrewService = require(script.Parent.RivalCrewService)

local BASE_LOCK_DURATION = 40
local LOCK_COOLDOWN = 60
local SLAP_RANGE = 14

local function getAnchorPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

function PlunderService.attachStealClicker(model, owner, slot)
	local anchor = getAnchorPart(model)
	if not anchor then
		return
	end
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = 40
	clicker.Parent = anchor
	clicker.MouseClick:Connect(function(clickingPlayer)
		if clickingPlayer ~= owner then
			PlunderService.startStealBrainrot(clickingPlayer, owner, slot)
		end
	end)
end

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
	local model = carrying.model
	if carrying.fromPlayer then
		local victimState = PirateState.getState(carrying.fromPlayer)
		if victimState and not victimState.slots[carrying.fromSlot] then
			PirateState.assignBrainrotToSlot(carrying.fromPlayer, carrying.fromSlot, carrying.defId, carrying.mutation)
			if model and model.Parent then
				local def = BootyCatalog.getBrainrotDefinition(carrying.defId)
				if def then
					local income = BootyCatalog.calculateBrainrotIncome(
						def,
						carrying.mutation,
						PirateState.getRebirthMultiplier(carrying.fromPlayer)
					)
					RigBuilder.replaceOverheadBillboard(
						model,
						def,
						carrying.mutation,
						"+" .. BootyCatalog.formatMoney(income) .. "/s"
					)
				end
				PirateState.setPedestalModel(carrying.fromPlayer, carrying.fromSlot, model)
				PlunderService.attachStealClicker(model, carrying.fromPlayer, carrying.fromSlot)
				model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(victimState.base, carrying.fromSlot)))
			end
			return
		end
	elseif carrying.fromRival then
		RivalCrewService.restoreRivalSlot(carrying.fromSlot, carrying.defId, carrying.mutation, model)
		return
	end
	if model then
		model:Destroy()
	end
end

function PlunderService.carryStolenBrainrot(player, def, mutation, fromPlayer, fromSlot)
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
		fromPlayer = fromPlayer,
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
				PlunderService.attachStealClicker(model, player, freeSlot)
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
		PirateState.broadcast(player, {
			type = "feed",
			text = "Too slow! " .. def.name .. " went back to " .. fromPlayer.Name .. "'s deck.",
			color = "red",
		})
		PlunderService.dropCarriedBrainrot(player)
	end
end

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
	local character = player.Character
	if not character then
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

function PlunderService.handleSlapPlayer(slapper, victim)
	if slapper == victim then
		return
	end
	local slapperChar = slapper.Character
	local victimChar = victim.Character
	if not slapperChar or not victimChar then
		return
	end
	local slapperHrp = slapperChar:FindFirstChild("HumanoidRootPart")
	local victimHrp = victimChar:FindFirstChild("HumanoidRootPart")
	if not slapperHrp or not victimHrp then
		return
	end
	local distance = (slapperHrp.Position - victimHrp.Position).Magnitude
	if distance > SLAP_RANGE then
		return
	end
	local away = victimHrp.Position - slapperHrp.Position
	if away.Magnitude == 0 then
		away = Vector3.new(0, 0, 1)
	else
		away = away.Unit
	end
	victimHrp.AssemblyLinearVelocity = away * 30 + Vector3.new(0, 12, 0)
	local victimState = PirateState.getState(victim)
	if victimState and victimState.carrying and (victimState.carrying.fromPlayer or victimState.carrying.fromRival) then
		PlunderService.dropCarriedBrainrot(victim)
		PirateState.broadcastAll({
			type = "feed",
			text = slapper.Name .. " SLAPPED " .. victim.Name .. " and the brainrot dropped!",
			color = "gold",
		})
	end
end

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
	local lockLevel = PirateState.getUpgradeLevel(player, "lock")
	local duration = BASE_LOCK_DURATION + 10 * lockLevel
	local untilTime = now + duration
	state.lockCooldownUntil = untilTime + LOCK_COOLDOWN
	PirateState.setBaseLockUntil(player, untilTime)
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

function PlunderService.expireBaseLocks()
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and state.lockUntil > 0 and os.clock() >= state.lockUntil then
			state.lockUntil = 0
			PirateState.broadcast(player, { type = "lock", remaining = 0 })
		end
	end
end

return PlunderService
