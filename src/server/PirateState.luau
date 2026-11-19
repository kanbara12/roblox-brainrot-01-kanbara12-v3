-- PirateState: every player's money, base, brainrots, lock, rebirth, upgrades,
-- collection and bounties live in this one module. No other script keeps
-- player state of its own.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PirateState = {}
PirateState.players = {}
PirateState.baseOccupants = { A = 0, B = 0 }
PirateState.pedestalModels = {}

function PirateState.setPedestalModel(player, slot, model)
	if not PirateState.pedestalModels[player] then
		PirateState.pedestalModels[player] = {}
	end
	PirateState.pedestalModels[player][slot] = model
end

function PirateState.getPedestalModel(player, slot)
	if not PirateState.pedestalModels[player] then
		return nil
	end
	return PirateState.pedestalModels[player][slot]
end

function PirateState.destroyPedestalModel(player, slot)
	local model = PirateState.getPedestalModel(player, slot)
	if model then
		model:Destroy()
	end
	if PirateState.pedestalModels[player] then
		PirateState.pedestalModels[player][slot] = nil
	end
end

-- init.server already creates LagoonUpdate before the requires; reuse it here
-- instead of creating a duplicate.
local updateEvent = ReplicatedStorage:FindFirstChild("LagoonUpdate")
if not updateEvent then
	updateEvent = Instance.new("RemoteEvent")
	updateEvent.Name = "LagoonUpdate"
	updateEvent.Parent = ReplicatedStorage
end

function PirateState.broadcast(player, payload)
	updateEvent:FireClient(player, payload)
end

function PirateState.broadcastAll(payload)
	updateEvent:FireAllClients(payload)
end

function PirateState.assignBase()
	if PirateState.baseOccupants.A <= PirateState.baseOccupants.B then
		PirateState.baseOccupants.A += 1
		return "A"
	else
		PirateState.baseOccupants.B += 1
		return "B"
	end
end

function PirateState.initPlayerState(player)
	local base = PirateState.assignBase()
	local state = {
		cash = 250000,
		base = base,
		slots = {},
		lockUntil = 0,
		lockCooldownUntil = 0,
		rebirths = 0,
		found = {},
		upgrades = { speed = 0, income = 0, lock = 0, slots = 0 },
		bounties = {},
		bountiesDone = {},
		carrying = nil,
	}
	for i = 1, 8 do
		state.slots[i] = nil
	end
	PirateState.players[player] = state
	return state
end

function PirateState.removePlayerState(player)
	local state = PirateState.players[player]
	if state then
		for i = 1, 8 do
			PirateState.destroyPedestalModel(player, i)
		end
		if state.carrying and state.carrying.model then
			state.carrying.model:Destroy()
		end
		if state.base == "A" then
			PirateState.baseOccupants.A = math.max(0, PirateState.baseOccupants.A - 1)
		elseif state.base == "B" then
			PirateState.baseOccupants.B = math.max(0, PirateState.baseOccupants.B - 1)
		end
	end
	PirateState.players[player] = nil
end

function PirateState.getState(player)
	return PirateState.players[player]
end

function PirateState.getCash(player)
	local state = PirateState.players[player]
	if not state then return 0 end
	return state.cash
end

function PirateState.addCash(player, amount)
	local state = PirateState.players[player]
	if not state then return end
	state.cash += amount
	PirateState.broadcast(player, { type = "cash", cash = state.cash, income = PirateState.getIncomePerSecond(player) })
end

function PirateState.spendCash(player, amount)
	local state = PirateState.players[player]
	if not state then return false end
	if state.cash < amount then return false end
	state.cash -= amount
	PirateState.broadcast(player, { type = "cash", cash = state.cash, income = PirateState.getIncomePerSecond(player) })
	return true
end

function PirateState.getRebirthMultiplier(player)
	local state = PirateState.players[player]
	if not state then return 1 end
	return 2 ^ state.rebirths
end

function PirateState.getIncomePerSecond(player)
	local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
	local StormService = require(script.Parent.StormService)
	local state = PirateState.players[player]
	if not state then return 0 end
	local total = 0
	for _, slot in pairs(state.slots) do
		if slot then
			local def = BootyCatalog.getBrainrotDefinition(slot.defId)
			if def then
				total += BootyCatalog.calculateBrainrotIncome(def, slot.mutation, PirateState.getRebirthMultiplier(player))
			end
		end
	end
	return math.floor(total * (1 + 0.1 * (state.upgrades.income or 0)) * StormService.getGoldenTideMultiplier())
end

function PirateState.getFreeSlot(player)
	local state = PirateState.players[player]
	if not state then return nil end
	local maxSlots = 6 + state.upgrades.slots
	for i = 1, math.min(8, maxSlots) do
		if state.slots[i] == nil then
			return i
		end
	end
	return nil
end

function PirateState.assignBrainrotToSlot(player, slot, defId, mutation)
	local state = PirateState.players[player]
	if not state then return false end
	if state.slots[slot] ~= nil then return false end
	state.slots[slot] = { defId = defId, mutation = mutation }
	PirateState.markFound(player, defId)
	PirateState.broadcast(player, { type = "slots", slots = state.slots })
	return true
end

function PirateState.clearBaseSlot(player, slot)
	local state = PirateState.players[player]
	if not state then return nil end
	local old = state.slots[slot]
	state.slots[slot] = nil
	PirateState.destroyPedestalModel(player, slot)
	PirateState.broadcast(player, { type = "slots", slots = state.slots })
	return old
end

function PirateState.setBaseLockUntil(player, untilTime)
	local state = PirateState.players[player]
	if not state then return end
	state.lockUntil = untilTime
	PirateState.broadcast(player, { type = "lock", remaining = math.max(0, math.ceil(untilTime - os.clock())) })
	PirateState.broadcastAll({ type = "feed", text = player.Name .. "'s deck is LOCKED!", color = "blue" })
end

function PirateState.isBaseLocked(player)
	local state = PirateState.players[player]
	if not state then return false end
	return os.clock() < state.lockUntil
end

function PirateState.getBaseLockRemaining(player)
	local state = PirateState.players[player]
	if not state then return 0 end
	return math.max(0, state.lockUntil - os.clock())
end

function PirateState.incrementRebirth(player)
	local state = PirateState.players[player]
	if not state then return end
	state.rebirths += 1
	state.cash = 100
	for i = 1, 8 do
		state.slots[i] = nil
		PirateState.destroyPedestalModel(player, i)
	end
	PirateState.broadcast(player, {
		type = "rebirth",
		rebirths = state.rebirths,
		multiplier = PirateState.getRebirthMultiplier(player),
		cash = state.cash,
	})
end

function PirateState.markFound(player, defId)
	local state = PirateState.players[player]
	if not state then return end
	if not state.found[defId] then
		state.found[defId] = true
		local count = 0
		for _ in pairs(state.found) do count += 1 end
		PirateState.broadcast(player, { type = "index", found = state.found, foundCount = count })
	end
end

function PirateState.getFoundCount(player)
	local state = PirateState.players[player]
	if not state then return 0 end
	local count = 0
	for _ in pairs(state.found) do count += 1 end
	return count
end

function PirateState.getUpgradeLevel(player, key)
	local state = PirateState.players[player]
	if not state then return 0 end
	return state.upgrades[key] or 0
end

function PirateState.setUpgradeLevel(player, key, level)
	local state = PirateState.players[player]
	if not state then return end
	state.upgrades[key] = level
	PirateState.broadcast(player, { type = "upgrades", upgrades = state.upgrades })
end

return PirateState
