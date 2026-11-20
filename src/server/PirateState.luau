-- PirateState.luau
-- The single store for all player state in Rotbeard's Lagoon.
-- Every player's money, base, deck, lock, rebirths, collection, upgrades,
-- bounties, and carried brainrot live here. No other server script keeps
-- player state of its own; every other module reads and mutates state only
-- through this module's functions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
-- Circular require with StormService is safe: neither module calls the
-- other at load time, only at runtime (income needs the Golden Tide state).
local StormService = require(script.Parent.StormService)

local PirateState = {}

-- The LagoonUpdate RemoteEvent is created by init.server before any
-- require, so it already exists. Reuse it; only create it if missing.
local LagoonUpdate = ReplicatedStorage:FindFirstChild("LagoonUpdate")
if not LagoonUpdate then
	LagoonUpdate = Instance.new("RemoteEvent")
	LagoonUpdate.Name = "LagoonUpdate"
	LagoonUpdate.Parent = ReplicatedStorage
end

-- One record per player, keyed by the Player instance.
local players = {}
-- How many players are on each base right now.
local baseOccupants = { A = 0, B = 0 }
-- Pedestal models in the world, keyed by player then slot number.
local pedestalModels = {}

local STARTING_CASH = 250000
local REBIRTH_RESET_CASH = 100
local BASE_SLOT_CAP = 6
local MAX_SLOTS = 8

-- Records the pedestal Model for a player's slot, creating the player's
-- sub-table if it does not exist yet.
function PirateState.setPedestalModel(player, slot, model)
	local bySlot = pedestalModels[player]
	if not bySlot then
		bySlot = {}
		pedestalModels[player] = bySlot
	end
	bySlot[slot] = model
end

-- Returns the recorded pedestal Model for a player's slot, or nil.
function PirateState.getPedestalModel(player, slot)
	local bySlot = pedestalModels[player]
	if not bySlot then
		return nil
	end
	return bySlot[slot]
end

-- Destroys the recorded pedestal Model for a player's slot, if any,
-- and clears the record.
function PirateState.destroyPedestalModel(player, slot)
	local bySlot = pedestalModels[player]
	if not bySlot then
		return
	end
	local model = bySlot[slot]
	if model then
		model:Destroy()
	end
	bySlot[slot] = nil
end

-- Sends a LagoonUpdate message to one player.
function PirateState.broadcast(player, payload)
	LagoonUpdate:FireClient(player, payload)
end

-- Sends a LagoonUpdate message to every player in the server.
function PirateState.broadcastAll(payload)
	LagoonUpdate:FireAllClients(payload)
end

-- Assigns the less-occupied base (ties go to A) and increments its count.
function PirateState.assignBase()
	local base = "A"
	if baseOccupants.B < baseOccupants.A then
		base = "B"
	end
	baseOccupants[base] = baseOccupants[base] + 1
	return base
end

-- Creates the state record for a newly joined player and returns it.
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
	players[player] = state
	return state
end

-- Tears down a player's state on leave: destroys all pedestal models and
-- the carried model, drops the base occupant count (never below 0), and
-- removes the record.
function PirateState.removePlayerState(player)
	local state = players[player]
	if not state then
		return
	end
	for slot = 1, MAX_SLOTS do
		PirateState.destroyPedestalModel(player, slot)
	end
	if state.carrying and state.carrying.model then
		state.carrying.model:Destroy()
	end
	if state.base and baseOccupants[state.base] then
		baseOccupants[state.base] = math.max(0, baseOccupants[state.base] - 1)
	end
	pedestalModels[player] = nil
	players[player] = nil
end

-- Returns the state record for a player, or nil if they have none.
function PirateState.getState(player)
	return players[player]
end

-- Returns the player's current cash, or 0 if they have no state.
function PirateState.getCash(player)
	local state = players[player]
	if not state then
		return 0
	end
	return state.cash
end

-- Adds cash and broadcasts a cash message (cash + current income/s).
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

-- Deducts cash if the player can afford it. Returns false (changing
-- nothing) when the player cannot afford it; otherwise deducts, broadcasts
-- a cash message, and returns true.
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

-- The permanent income multiplier from rebirths: 2 ^ rebirths (1 at 0).
function PirateState.getRebirthMultiplier(player)
	local state = players[player]
	if not state then
		return 1
	end
	return 2 ^ state.rebirths
end

-- Income per second: floor of (sum of each slotted brainrot's income at
-- its mutation and the player's rebirth multiplier) x (1 + 0.10 per
-- GOLDEN COMPASS level) x (Golden Tide multiplier, 2 or 1).
function PirateState.getIncomePerSecond(player)
	local state = players[player]
	if not state then
		return 0
	end
	local rebirthMultiplier = PirateState.getRebirthMultiplier(player)
	local total = 0
	for slot = 1, MAX_SLOTS do
		local entry = state.slots[slot]
		if entry then
			local def = BootyCatalog.getBrainrotDefinition(entry.defId)
			if def then
				total = total + BootyCatalog.calculateBrainrotIncome(def, entry.mutation, rebirthMultiplier)
			end
		end
	end
	local compassLevel = state.upgrades.income or 0
	local tideMultiplier = StormService.getGoldenTideMultiplier()
	return math.floor(total * (1 + 0.10 * compassLevel) * tideMultiplier)
end

-- The lowest empty slot number within the usable cap (6 + EXTRA PEDESTAL
-- level, at most 8), or nil when the deck is full.
function PirateState.getFreeSlot(player)
	local state = players[player]
	if not state then
		return nil
	end
	local cap = math.min(MAX_SLOTS, BASE_SLOT_CAP + (state.upgrades.slots or 0))
	for slot = 1, cap do
		if not state.slots[slot] then
			return slot
		end
	end
	return nil
end

-- Assigns a brainrot to a slot. Fails (false) when there is no state or
-- the slot is already occupied. Otherwise records the brainrot, marks it
-- found in the Captain's Log, broadcasts the slots, and returns true.
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
	PirateState.broadcast(player, {
		type = "slots",
		slots = state.slots,
	})
	return true
end

-- Clears a slot, destroys its pedestal model, broadcasts the slots, and
-- returns the old slot entry (or nil).
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

-- Sets the lock expiry, broadcasts a lock message with the remaining
-- whole seconds, and tells everyone the deck is locked.
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

-- True while the clock is before the lock expiry.
function PirateState.isBaseLocked(player)
	local state = players[player]
	if not state then
		return false
	end
	return os.clock() < state.lockUntil
end

-- Seconds of lock left, never below 0.
function PirateState.getBaseLockRemaining(player)
	local state = players[player]
	if not state then
		return 0
	end
	return math.max(0, state.lockUntil - os.clock())
end

-- Applies a rebirth: rebirths +1, cash reset to $100, all 8 slots cleared
-- and their pedestal models destroyed, then broadcasts a rebirth message
-- carrying the new rebirth count, multiplier, cash, the now-empty slots
-- table, and the reset income per second. The empty slots and reset
-- income must be included, or the client keeps showing the old deck.
function PirateState.incrementRebirth(player)
	local state = players[player]
	if not state then
		return
	end
	state.rebirths = state.rebirths + 1
	state.cash = REBIRTH_RESET_CASH
	for slot = 1, MAX_SLOTS do
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

-- Marks a brainrot found in the Captain's Log. If it was not already
-- found, adds it and broadcasts an index message (found set + count).
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

-- The number of distinct brainrots found in the Captain's Log.
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

-- The level of one upgrade key (0 when there is no state or it is unset).
function PirateState.getUpgradeLevel(player, key)
	local state = players[player]
	if not state then
		return 0
	end
	return state.upgrades[key] or 0
end

-- Sets an upgrade level and broadcasts the whole upgrade table.
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
