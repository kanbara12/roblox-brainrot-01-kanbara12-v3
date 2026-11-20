-- PirateState.luau
-- The single store for all player state. Every player's money, base, deck,
-- lock, rebirths, collection, upgrades, bounties, and carried brainrot live
-- here. No other script keeps player state of its own; every other server
-- module reads and mutates state only through this module's functions
-- (or through the state record returned by getState).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local StormService = require(script.Parent.StormService)

local PirateState = {}

-- Module-level tables.
local players = {} -- player -> state record
local baseOccupants = { A = 0, B = 0 }
local pedestalModels = {} -- player -> slot -> pedestal Model

-- The LagoonUpdate RemoteEvent is created by init.server before any require.
-- Reuse it; only create it here if it does not already exist.
local LagoonUpdate = ReplicatedStorage:FindFirstChild("LagoonUpdate")
if not LagoonUpdate then
	LagoonUpdate = Instance.new("RemoteEvent")
	LagoonUpdate.Name = "LagoonUpdate"
	LagoonUpdate.Parent = ReplicatedStorage
end

-- The starting cash for every new player.
local STARTING_CASH = 250000
-- The cash a player is reset to after a rebirth.
local REBIRTH_CASH = 100
-- The base number of usable deck slots (before EXTRA PEDESTAL).
local BASE_DECK_SLOTS = 6
-- The absolute maximum number of deck slots.
local MAX_DECK_SLOTS = 8

-- Records the pedestal Model for a player's slot, creating the player's
-- sub-table if needed.
function PirateState.setPedestalModel(player, slot, model)
	if not pedestalModels[player] then
		pedestalModels[player] = {}
	end
	pedestalModels[player][slot] = model
end

-- Returns the recorded pedestal Model for a player's slot, or nil.
function PirateState.getPedestalModel(player, slot)
	local byPlayer = pedestalModels[player]
	if not byPlayer then
		return nil
	end
	return byPlayer[slot]
end

-- Destroys the recorded pedestal Model for a player's slot if any, and
-- clears the record.
function PirateState.destroyPedestalModel(player, slot)
	local byPlayer = pedestalModels[player]
	if not byPlayer then
		return
	end
	local model = byPlayer[slot]
	if model then
		model:Destroy()
	end
	byPlayer[slot] = nil
end

-- Sends a LagoonUpdate message to one player.
function PirateState.broadcast(player, payload)
	LagoonUpdate:FireClient(player, payload)
end

-- Sends a LagoonUpdate message to every player.
function PirateState.broadcastAll(payload)
	LagoonUpdate:FireAllClients(payload)
end

-- Assigns the less-occupied base (ties go to A) and increments its
-- occupant count. Returns "A" or "B".
function PirateState.assignBase()
	local base = "A"
	if baseOccupants.B < baseOccupants.A then
		base = "B"
	end
	baseOccupants[base] = baseOccupants[base] + 1
	return base
end

-- Creates the state record for a player joining the server and returns it.
function PirateState.initPlayerState(player)
	local state = {
		cash = STARTING_CASH,
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
	for slot = 1, MAX_DECK_SLOTS do
		state.slots[slot] = nil
	end
	players[player] = state
	return state
end

-- Removes a player's state: destroys all pedestal models and the carried
-- model if any, decrements the base occupant count (never below 0), and
-- removes the record.
function PirateState.removePlayerState(player)
	local state = players[player]
	if not state then
		return
	end
	for slot = 1, MAX_DECK_SLOTS do
		PirateState.destroyPedestalModel(player, slot)
	end
	local carrying = state.carrying
	if carrying and carrying.model then
		carrying.model:Destroy()
	end
	if state.base and baseOccupants[state.base] then
		baseOccupants[state.base] = math.max(0, baseOccupants[state.base] - 1)
	end
	players[player] = nil
	pedestalModels[player] = nil
end

-- Returns the state record for a player, or nil.
function PirateState.getState(player)
	return players[player]
end

-- Returns the player's current cash, or 0 if there is no state.
function PirateState.getCash(player)
	local state = players[player]
	if not state then
		return 0
	end
	return state.cash
end

-- Adds cash and broadcasts a cash message (cash + current income per second).
function PirateState.addCash(player, amount)
	local state = players[player]
	if not state then
		return
	end
	state.cash = state.cash + amount
	PirateState.broadcast(player, {
		type = "cash",
		cash = state.cash,
		income = PirateState.getIncomePerSecond(player),
	})
end

-- Deducts cash if the player can afford it. Returns false (and changes
-- nothing) if cash is insufficient; otherwise deducts, broadcasts a cash
-- message, and returns true.
function PirateState.spendCash(player, amount)
	local state = players[player]
	if not state then
		return false
	end
	if state.cash < amount then
		return false
	end
	state.cash = state.cash - amount
	PirateState.broadcast(player, {
		type = "cash",
		cash = state.cash,
		income = PirateState.getIncomePerSecond(player),
	})
	return true
end

-- Returns 2 ^ rebirths (1 if there is no state).
function PirateState.getRebirthMultiplier(player)
	local state = players[player]
	if not state then
		return 1
	end
	return 2 ^ state.rebirths
end

-- Returns the income per second: floor of (sum over occupied slots of that
-- brainrot's income at its mutation and the player's rebirth multiplier)
-- x (1 + 0.10 x GOLDEN COMPASS level) x (Golden Tide multiplier, 2 or 1).
-- Returns 0 if there is no state.
function PirateState.getIncomePerSecond(player)
	local state = players[player]
	if not state then
		return 0
	end
	local multiplier = PirateState.getRebirthMultiplier(player)
	local total = 0
	for _, slot in ipairs(state.slots) do
		if slot and slot.defId then
			local def = BootyCatalog.getBrainrotDefinition(slot.defId)
			if def then
				total = total + BootyCatalog.calculateBrainrotIncome(def, slot.mutation, multiplier)
			end
		end
	end
	local compassLevel = PirateState.getUpgradeLevel(player, "income")
	local compassFactor = 1 + 0.10 * compassLevel
	local tideMultiplier = StormService.getGoldenTideMultiplier()
	return math.floor(total * compassFactor * tideMultiplier)
end

-- Returns the lowest empty slot number within the usable cap
-- (6 + EXTRA PEDESTAL level, at most 8), or nil if the deck is full.
function PirateState.getFreeSlot(player)
	local state = players[player]
	if not state then
		return nil
	end
	local cap = math.min(BASE_DECK_SLOTS + PirateState.getUpgradeLevel(player, "slots"), MAX_DECK_SLOTS)
	for slot = 1, cap do
		if state.slots[slot] == nil then
			return slot
		end
	end
	return nil
end

-- Assigns a brainrot to a slot. Fails (false) if there is no state or the
-- slot is already occupied; otherwise records { defId, mutation }, marks the
-- brainrot found, broadcasts a slots message, and returns true.
function PirateState.assignBrainrotToSlot(player, slot, defId, mutation)
	local state = players[player]
	if not state then
		return false
	end
	if state.slots[slot] ~= nil then
		return false
	end
	state.slots[slot] = { defId = defId, mutation = mutation }
	PirateState.markFound(player, defId)
	PirateState.broadcast(player, {
		type = "slots",
		slots = state.slots,
	})
	return true
end

-- Clears a slot, destroys its pedestal model, and broadcasts a slots
-- message. Returns the old slot entry (or nil).
function PirateState.clearBaseSlot(player, slot)
	local state = players[player]
	if not state then
		return nil
	end
	local old = state.slots[slot]
	state.slots[slot] = nil
	PirateState.destroyPedestalModel(player, slot)
	PirateState.broadcast(player, {
		type = "slots",
		slots = state.slots,
	})
	return old
end

-- Sets the lock expiry, broadcasts a lock message with the remaining whole
-- seconds, and broadcasts a feed message to all players.
function PirateState.setBaseLockUntil(player, untilTime)
	local state = players[player]
	if not state then
		return
	end
	state.lockUntil = untilTime
	local remaining = math.max(0, math.floor(untilTime - os.clock()))
	PirateState.broadcast(player, {
		type = "lock",
		remaining = remaining,
	})
	PirateState.broadcastAll({
		type = "feed",
		text = player.Name .. "'s deck is LOCKED!",
		color = "blue",
	})
end

-- Returns true while the clock is before the player's lock expiry.
function PirateState.isBaseLocked(player)
	local state = players[player]
	if not state then
		return false
	end
	return os.clock() < state.lockUntil
end

-- Returns the remaining lock seconds (0 when not locked).
function PirateState.getBaseLockRemaining(player)
	local state = players[player]
	if not state then
		return 0
	end
	return math.max(0, state.lockUntil - os.clock())
end

-- Applies a rebirth: rebirths +1, cash reset to $100, all 8 slots cleared
-- and their pedestal models destroyed, and a rebirth message broadcast
-- carrying rebirths, the new multiplier, cash, the (now empty) slots table,
-- and the reset income per second.
function PirateState.incrementRebirth(player)
	local state = players[player]
	if not state then
		return
	end
	state.rebirths = state.rebirths + 1
	state.cash = REBIRTH_CASH
	for slot = 1, MAX_DECK_SLOTS do
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

-- Marks a brainrot as found in the Captain's Log. If it was not already
-- found, adds it to the found set and broadcasts an index message.
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

-- Returns the number of distinct brainrots found in the Captain's Log.
function PirateState.getFoundCount(player)
	local state = players[player]
	if not state then
		return 0
	end
	local count = 0
	for _ in pairs(state.found) do
		count = count + 1
	end
	return count
end

-- Returns the player's level for an upgrade key (0 if no state or unset).
function PirateState.getUpgradeLevel(player, key)
	local state = players[player]
	if not state then
		return 0
	end
	return state.upgrades[key] or 0
end

-- Sets the player's level for an upgrade key and broadcasts an upgrades
-- message with the whole upgrade table.
function PirateState.setUpgradeLevel(player, key, level)
	local state = players[player]
	if not state then
		return
	end
	state.upgrades[key] = level
	PirateState.broadcast(player, {
		type = "upgrades",
		upgrades = state.upgrades,
	})
end

return PirateState
