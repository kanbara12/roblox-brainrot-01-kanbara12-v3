-- PirateState — the single store for all player state.
-- Every player's money, base, deck, lock, rebirths, collection, upgrades,
-- bounties, and carried brainrot live here. No other script keeps player
-- state of its own; every other server module reads and mutates state only
-- through this module's functions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
-- Circular with StormService (it requires PirateState). Safe: neither module
-- calls the other at load time, only at runtime, and both return the same
-- table object they keep adding functions to.
local StormService = require(script.Parent:WaitForChild("StormService"))

-- The LagoonUpdate remote is created by init.server before any require.
-- Reuse it here; only create it if it somehow does not exist yet.
local LagoonUpdate = ReplicatedStorage:FindFirstChild("LagoonUpdate")
if not LagoonUpdate then
	LagoonUpdate = Instance.new("RemoteEvent")
	LagoonUpdate.Name = "LagoonUpdate"
	LagoonUpdate.Parent = ReplicatedStorage
end

local PirateState = {}

-- Module-level tables.
local players = {} -- player -> state record
local baseOccupants = { A = 0, B = 0 }
local pedestalModels = {} -- player -> slot -> pedestal Model

local STARTING_CASH = 250000
local REBIRTH_RESET_CASH = 100
local SLOT_COUNT = 8
local BASE_SLOT_CAP = 6
local MAX_EXTRA_SLOTS = 2

--------------------------------------------------------------------------------
-- Pedestal models
--------------------------------------------------------------------------------

function PirateState.setPedestalModel(player, slot, model)
	local bySlot = pedestalModels[player]
	if not bySlot then
		bySlot = {}
		pedestalModels[player] = bySlot
	end
	bySlot[slot] = model
end

function PirateState.getPedestalModel(player, slot)
	local bySlot = pedestalModels[player]
	if not bySlot then
		return nil
	end
	return bySlot[slot]
end

function PirateState.destroyPedestalModel(player, slot)
	local bySlot = pedestalModels[player]
	if not bySlot then
		return
	end
	local model = bySlot[slot]
	if model then
		bySlot[slot] = nil
		model:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Broadcasting
--------------------------------------------------------------------------------

function PirateState.broadcast(player, payload)
	LagoonUpdate:FireClient(player, payload)
end

function PirateState.broadcastAll(payload)
	LagoonUpdate:FireAllClients(payload)
end

--------------------------------------------------------------------------------
-- Join / leave
--------------------------------------------------------------------------------

-- Assigns the less-occupied base (ties go to A) and counts the occupant.
function PirateState.assignBase()
	local base = "A"
	if baseOccupants.B < baseOccupants.A then
		base = "B"
	end
	baseOccupants[base] = baseOccupants[base] + 1
	return base
end

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
	for slot = 1, SLOT_COUNT do
		state.slots[slot] = nil
	end
	players[player] = state
	return state
end

function PirateState.removePlayerState(player)
	local state = players[player]
	if not state then
		return
	end
	for slot = 1, SLOT_COUNT do
		PirateState.destroyPedestalModel(player, slot)
	end
	if state.carrying and state.carrying.model then
		state.carrying.model:Destroy()
	end
	pedestalModels[player] = nil
	baseOccupants[state.base] = math.max(0, baseOccupants[state.base] - 1)
	players[player] = nil
end

function PirateState.getState(player)
	return players[player]
end

--------------------------------------------------------------------------------
-- Cash
--------------------------------------------------------------------------------

function PirateState.getCash(player)
	local state = players[player]
	if not state then
		return 0
	end
	return state.cash
end

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

-- Returns false (and changes nothing) when cash is insufficient.
function PirateState.spendCash(player, amount)
	local state = players[player]
	if not state or state.cash < amount then
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

--------------------------------------------------------------------------------
-- Rebirths and income
--------------------------------------------------------------------------------

function PirateState.getRebirthMultiplier(player)
	local state = players[player]
	if not state then
		return 1
	end
	return 2 ^ state.rebirths
end

function PirateState.getIncomePerSecond(player)
	local state = players[player]
	if not state then
		return 0
	end
	local total = 0
	local multiplier = PirateState.getRebirthMultiplier(player)
	for _, entry in ipairs(state.slots) do
		if entry then
			local def = BootyCatalog.getBrainrotDefinition(entry.defId)
			if def then
				total = total
					+ BootyCatalog.calculateBrainrotIncome(def, entry.mutation, multiplier)
			end
		end
	end
	local compass = PirateState.getUpgradeLevel(player, "income")
	local tide = StormService.getGoldenTideMultiplier()
	return math.floor(total * (1 + 0.10 * compass) * tide)
end

--------------------------------------------------------------------------------
-- Deck slots
--------------------------------------------------------------------------------

function PirateState.getFreeSlot(player)
	local state = players[player]
	if not state then
		return nil
	end
	local cap = BASE_SLOT_CAP + PirateState.getUpgradeLevel(player, "slots")
	if cap > SLOT_COUNT then
		cap = SLOT_COUNT
	end
	for slot = 1, cap do
		if not state.slots[slot] then
			return slot
		end
	end
	return nil
end

-- Records the brainrot in the slot, marks it found in the Captain's Log,
-- and broadcasts the new slot table. Fails when there is no state or the
-- slot is already occupied.
function PirateState.assignBrainrotToSlot(player, slot, defId, mutation)
	local state = players[player]
	if not state or state.slots[slot] then
		return false
	end
	state.slots[slot] = { defId = defId, mutation = mutation }
	PirateState.markFound(player, defId)
	PirateState.broadcast(player, { type = "slots", slots = state.slots })
	return true
end

-- Clears the slot and destroys its pedestal model. Returns the old entry.
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

--------------------------------------------------------------------------------
-- Lock
--------------------------------------------------------------------------------

function PirateState.setBaseLockUntil(player, untilTime)
	local state = players[player]
	if not state then
		return
	end
	state.lockUntil = untilTime
	PirateState.broadcast(player, {
		type = "lock",
		remaining = math.floor(PirateState.getBaseLockRemaining(player)),
	})
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

--------------------------------------------------------------------------------
-- Rebirth
--------------------------------------------------------------------------------

function PirateState.incrementRebirth(player)
	local state = players[player]
	if not state then
		return
	end
	state.rebirths = state.rebirths + 1
	state.cash = REBIRTH_RESET_CASH
	for slot = 1, SLOT_COUNT do
		state.slots[slot] = nil
		PirateState.destroyPedestalModel(player, slot)
	end
	-- The empty slots and the reset income MUST be included, or the client
	-- keeps showing the old deck after the rebirth.
	PirateState.broadcast(player, {
		type = "rebirth",
		rebirths = state.rebirths,
		multiplier = PirateState.getRebirthMultiplier(player),
		cash = state.cash,
		slots = state.slots,
		income = PirateState.getIncomePerSecond(player),
	})
end

--------------------------------------------------------------------------------
-- Captain's Log (collection)
--------------------------------------------------------------------------------

function PirateState.markFound(player, defId)
	local state = players[player]
	if not state or state.found[defId] then
		return
	end
	state.found[defId] = true
	-- Keep the found set keyed by numeric brainrot id when broadcasting;
	-- the client normalises the string keys RemoteEvent serialization makes.
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
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- Upgrades
--------------------------------------------------------------------------------

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
