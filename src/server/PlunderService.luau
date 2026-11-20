-- PlunderService — stealing, slapping, locking.
-- Steal a brainrot off another player's deck and carry it home, slap a thief
-- to knock a stolen brainrot loose, and lock your own deck behind a
-- cannon-net dome.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local PirateState = require(script.Parent:WaitForChild("PirateState"))
local BountyService = require(script.Parent:WaitForChild("BountyService"))
local RivalCrewService = require(script.Parent:WaitForChild("RivalCrewService"))

local PlunderService = {}

local BASE_LOCK_SECONDS = 40
local LOCK_BONUS_PER_LEVEL = 10
local LOCK_COOLDOWN_SECONDS = 60
local SLAP_RANGE = 14
local SLAP_KNOCKBACK = 30
local SLAP_UPWARD = 12
local CARRY_SECONDS = 30
local CARRY_STEP = 0.1
local REACH_DISTANCE = 10
local CARRY_HEIGHT = 4
local CLICK_DISTANCE = 40

--------------------------------------------------------------------------------
-- Steal clickers
--------------------------------------------------------------------------------

function PlunderService.attachStealClicker(model, owner, slot)
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = CLICK_DISTANCE
	detector.Parent = model.PrimaryPart
	detector.MouseClick:Connect(function(player)
		if player ~= owner then
			PlunderService.startStealBrainrot(player, owner, slot)
		end
	end)
end

--------------------------------------------------------------------------------
-- Stealing from another player
--------------------------------------------------------------------------------

function PlunderService.startStealBrainrot(player, targetPlayer, slot)
	local state = PirateState.getState(player)
	local victimState = PirateState.getState(targetPlayer)
	if not state or not victimState then
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
	local entry = victimState.slots[slot]
	if not entry then
		return false
	end
	local def = BootyCatalog.getBrainrotDefinition(entry.defId)
	if not def then
		return false
	end
	-- The brainrot leaves the victim's deck immediately.
	PirateState.clearBaseSlot(targetPlayer, slot)
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. " STOLE " .. def.name .. " from " .. targetPlayer.Name .. "!",
		color = "red",
	})
	PlunderService.carryStolenBrainrot(player, def, entry.mutation, targetPlayer, slot)
	return true
end

function PlunderService.carryStolenBrainrot(player, def, mutation, fromPlayer, fromSlot)
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
		fromPlayer = fromPlayer,
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
		PlunderService.dropCarriedBrainrot(player)
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
		for _ = 1, steps do
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
			if _ == steps then
				timedOut = true
			end
		end
		local current = PirateState.getState(player)
		-- Someone else already handled the carry (a slap dropped it, or the
		-- Kraken took it): end silently.
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
			PlunderService.attachStealClicker(model, player, slot)
			model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
			current.carrying = nil
			PirateState.broadcast(player, { type = "carrying", name = nil })
			BountyService.addBountyProgress(player, "steal", 1)
			PirateState.broadcastAll({
				type = "feed",
				text = player.Name .. " got away with " .. def.name .. "!",
				color = "gold",
			})
		else
			PlunderService.dropCarriedBrainrot(player)
			if timedOut then
				PirateState.broadcast(player, {
					type = "feed",
					text = "Too slow! "
						.. def.name
						.. " went back to "
						.. fromPlayer.Name
						.. "'s deck.",
					color = "red",
				})
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Dropping a carried brainrot
--------------------------------------------------------------------------------

function PlunderService.dropCarriedBrainrot(player)
	local state = PirateState.getState(player)
	if not state or not state.carrying then
		return
	end
	local record = state.carrying
	state.carrying = nil
	PirateState.broadcast(player, { type = "carrying", name = nil })
	local model = record.model
	if record.fromPlayer then
		local victimState = PirateState.getState(record.fromPlayer)
		if victimState and not victimState.slots[record.fromSlot] then
			victimState.slots[record.fromSlot] =
				{ defId = record.defId, mutation = record.mutation }
			PirateState.broadcast(record.fromPlayer, {
				type = "slots",
				slots = victimState.slots,
			})
			if model and model.Parent then
				local def = BootyCatalog.getBrainrotDefinition(record.defId)
				if def then
					local income = BootyCatalog.calculateBrainrotIncome(
						def,
						record.mutation,
						PirateState.getRebirthMultiplier(record.fromPlayer)
					)
					RigBuilder.replaceOverheadBillboard(
						model,
						def,
						record.mutation,
						"+" .. BootyCatalog.formatMoney(income) .. "/s"
					)
					PirateState.setPedestalModel(record.fromPlayer, record.fromSlot, model)
					PlunderService.attachStealClicker(model, record.fromPlayer, record.fromSlot)
					model:PivotTo(
						CFrame.new(
							LagoonLayout.getPedestalPosition(victimState.base, record.fromSlot)
						)
					)
				else
					model:Destroy()
				end
			end
		elseif model then
			model:Destroy()
		end
	elseif record.fromRival then
		RivalCrewService.restoreRivalSlot(record.fromSlot, record.defId, record.mutation, model)
	elseif model then
		model:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Slapping
--------------------------------------------------------------------------------

function PlunderService.handleSlapPlayer(slapper, victim)
	if slapper == victim then
		return
	end
	local slapChar = slapper.Character
	local victimChar = victim.Character
	if not slapChar or not victimChar then
		return
	end
	local slapRoot = slapChar:FindFirstChild("HumanoidRootPart")
	local victimRoot = victimChar:FindFirstChild("HumanoidRootPart")
	if not slapRoot or not victimRoot then
		return
	end
	local offset = victimRoot.Position - slapRoot.Position
	if offset.Magnitude > SLAP_RANGE then
		return
	end
	local away = offset.Magnitude > 0.01 and offset.Unit or Vector3.new(0, 0, 1)
	victimRoot.AssemblyLinearVelocity = away * SLAP_KNOCKBACK + Vector3.new(0, SLAP_UPWARD, 0)
	local victimState = PirateState.getState(victim)
	if victimState and victimState.carrying then
		local carried = victimState.carrying
		if carried.fromPlayer or carried.fromRival then
			PlunderService.dropCarriedBrainrot(victim)
			PirateState.broadcastAll({
				type = "feed",
				text = slapper.Name .. " SLAPPED " .. victim.Name .. " and the brainrot dropped!",
				color = "gold",
			})
		end
	end
end

--------------------------------------------------------------------------------
-- Locking
--------------------------------------------------------------------------------

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
	local duration = BASE_LOCK_SECONDS
		+ LOCK_BONUS_PER_LEVEL * PirateState.getUpgradeLevel(player, "lock")
	PirateState.setBaseLockUntil(player, now + duration)
	state.lockCooldownUntil = now + duration + LOCK_COOLDOWN_SECONDS
	local dome = LagoonLayout.getLockDome(state.base)
	if dome then
		dome.Transparency = 0.55
		task.delay(duration, function()
			if not PirateState.isBaseLocked(player) then
				dome.Transparency = 1
			end
		end)
	end
	BountyService.addBountyProgress(player, "lock", 1)
	return true
end

-- Clears every lock whose expiry has passed. Driven by init.server.
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
