local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PirateState = {}

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local StormService = require(script.Parent.StormService)

local players = {}
local baseOccupants = { A = 0, B = 0 }
local pedestalModels = {}

local updateRemote = ReplicatedStorage:FindFirstChild("LagoonUpdate")
if not updateRemote then
	updateRemote = Instance.new("RemoteEvent")
	updateRemote.Name = "LagoonUpdate"
	updateRemote.Parent = ReplicatedStorage
end

function PirateState.setPedestalModel(player, slot, model)
	if not pedestalModels[player] then
		pedestalModels[player] = {}
	end
	pedestalModels[player][slot] = model
end

function PirateState.getPedestalModel(player, slot)
	local byPlayer = pedestalModels[player]
	if not byPlayer then
		return nil
	end
	return byPlayer[slot]
end

function PirateState.destroyPedestalModel(player, slot)
	local model = PirateState.getPedestalModel(player, slot)
	if model then
		model:Destroy()
	end
	if pedestalModels[player] then
		pedestalModels[player][slot] = nil
	end
end

function PirateState.broadcast(player, payload)
	updateRemote:FireClient(player, payload)
end

function PirateState.broadcastAll(payload)
	updateRemote:FireAllClients(payload)
end

function PirateState.assignBase()
	local base = "A"
	if baseOccupants.B < baseOccupants.A then
		base = "B"
	end
	baseOccupants[base] += 1
	return base
end

function PirateState.initPlayerState(player)
	local state = {
		cash = 250000,
		base = PirateState.assignBase(),
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
	players[player] = state
	pedestalModels[player] = {}
	return state
end

function PirateState.removePlayerState(player)
	local state = players[player]
	if not state then
		return
	end
	for slot = 1, 8 do
		PirateState.destroyPedestalModel(player, slot)
	end
	if state.carrying and state.carrying.model then
		state.carrying.model:Destroy()
	end
	local base = state.base
	if base and baseOccupants[base] then
		baseOccupants[base] = math.max(0, baseOccupants[base] - 1)
	end
	pedestalModels[player] = nil
	players[player] = nil
end

function PirateState.getState(player)
	return players[player]
end

function PirateState.getCash(player)
	local state = players[player]
	if not state then
		return 0
	end
	return state.cash
end

function PirateState.getIncomePerSecond(player)
	local state = players[player]
	if not state then
		return 0
	end
	local rebirthMultiplier = PirateState.getRebirthMultiplier(player)
	local total = 0
	for slot = 1, 8 do
		local entry = state.slots[slot]
		if entry then
			local def = BootyCatalog.getBrainrotDefinition(entry.defId)
			if def then
				total += BootyCatalog.calculateBrainrotIncome(def, entry.mutation, rebirthMultiplier)
			end
		end
	end
	local compass = PirateState.getUpgradeLevel(player, "income")
	local tide = StormService.getGoldenTideMultiplier()
	return math.floor(total * (1 + 0.10 * compass) * tide)
end

function PirateState.addCash(player, amount)
	local state = players[player]
	if not state then
		return
	end
	state.cash += amount
	PirateState.broadcast(player, {
		type = "cash",
		cash = state.cash,
		income = PirateState.getIncomePerSecond(player),
	})
end

function PirateState.spendCash(player, amount)
	local state = players[player]
	if not state then
		return false
	end
	if state.cash < amount then
		return false
	end
	state.cash -= amount
	PirateState.broadcast(player, {
		type = "cash",
		cash = state.cash,
		income = PirateState.getIncomePerSecond(player),
	})
	return true
end

function PirateState.getRebirthMultiplier(player)
	local state = players[player]
	if not state then
		return 1
	end
	return 2 ^ state.rebirths
end

function PirateState.getFreeSlot(player)
	local state = players[player]
	if not state then
		return nil
	end
	local cap = 6 + PirateState.getUpgradeLevel(player, "slots")
	if cap > 8 then
		cap = 8
	end
	for slot = 1, cap do
		if not state.slots[slot] then
			return slot
		end
	end
	return nil
end

function PirateState.assignBrainrotToSlot(player, slot, defId, mutation)
	local state = players[player]
	if not state then
		return false
	end
	if state.slots[slot] then
		return false
	end
	state.slots[slot] = { defId = defId, mutation = mutation }
	PirateState.markFound(player, defId)
	PirateState.broadcast(player, { type = "slots", slots = state.slots })
	return true
end

function PirateState.clearBaseSlot(player, slot)
	local state = players[player]
	if not state then
		return nil
	end
	local old = state.slots[slot]
	state.slots[slot] = nil
	PirateState.destroyPedestalModel(player, slot)
	PirateState.broadcast(player, { type = "slots", slots = state.slots })
	return old
end

function PirateState.setBaseLockUntil(player, untilTime)
	local state = players[player]
	if not state then
		return
	end
	state.lockUntil = untilTime
	local remaining = math.max(0, math.floor(untilTime - os.clock()))
	PirateState.broadcast(player, { type = "lock", remaining = remaining })
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. "'s deck is LOCKED!",
		color = "blue",
	})
end

function PirateState.isBaseLocked(player)
	local state = players[player]
	if not state then
		return false
	end
	return os.clock() < state.lockUntil
end

function PirateState.getBaseLockRemaining(player)
	local state = players[player]
	if not state then
		return 0
	end
	return math.max(0, state.lockUntil - os.clock())
end

function PirateState.incrementRebirth(player)
	local state = players[player]
	if not state then
		return
	end
	state.rebirths += 1
	state.cash = 100
	for slot = 1, 8 do
		state.slots[slot] = nil
		PirateState.destroyPedestalModel(player, slot)
	end
	PirateState.broadcast(player, {
		type = "rebirth",
		rebirths = state.rebirths,
		multiplier = PirateState.getRebirthMultiplier(player),
		cash = state.cash,
		slots = state.slots,
		income = PirateState.getIncomePerSecond(player),
	})
end

function PirateState.markFound(player, defId)
	local state = players[player]
	if not state then
		return
	end
	if state.found[defId] then
		return
	end
	state.found[defId] = true
	PirateState.broadcast(player, {
		type = "index",
		found = state.found,
		foundCount = PirateState.getFoundCount(player),
	})
end

function PirateState.getFoundCount(player)
	local state = players[player]
	if not state then
		return 0
	end
	local count = 0
	for _ in pairs(state.found) do
		count += 1
	end
	return count
end

function PirateState.getUpgradeLevel(player, key)
	local state = players[player]
	if not state then
		return 0
	end
	return state.upgrades[key] or 0
end

function PirateState.setUpgradeLevel(player, key, level)
	local state = players[player]
	if not state then
		return
	end
	state.upgrades[key] = level
	PirateState.broadcast(player, { type = "upgrades", upgrades = state.upgrades })
end

return PirateState
