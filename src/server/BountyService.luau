-- BountyService.luau
-- Twelve bounties with doubloon rewards. Progress is counted by the services
-- that own each action; this module owns the table, the list, and completion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PirateState = require(script.Parent.PirateState)
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))

local BountyService = {}

-- The twelve bounties. Fields: id, kind, target, text, reward (doubloons).
BountyService.BOUNTIES = {
	{ id = "buy1", kind = "buy", target = 1, text = "Buy your first brainrot", reward = 100 },
	{ id = "buy5", kind = "buy", target = 5, text = "Buy 5 brainrots", reward = 500 },
	{ id = "ownEpic", kind = "ownEpic", target = 1, text = "Own an EPIC or better", reward = 1000 },
	{ id = "ownMythic", kind = "ownMythic", target = 1, text = "Own a MYTHIC or better", reward = 5000 },
	{ id = "steal1", kind = "steal", target = 1, text = "Steal a brainrot", reward = 1500 },
	{ id = "steal3", kind = "steal", target = 3, text = "Steal 3 brainrots", reward = 5000 },
	{ id = "lock1", kind = "lock", target = 1, text = "Lock your deck", reward = 800 },
	{ id = "survive1", kind = "survive", target = 1, text = "Survive a Kraken Surge", reward = 2000 },
	{ id = "rebirth1", kind = "rebirth", target = 1, text = "Rebirth once", reward = 10000 },
	{ id = "index10", kind = "index", target = 10, text = "Find 10 brainrots in the Log", reward = 2000 },
	{ id = "index25", kind = "index", target = 25, text = "Find 25 brainrots in the Log", reward = 10000 },
	{ id = "upgrade3", kind = "upgrades", target = 3, text = "Buy 3 upgrades", reward = 1500 },
}

-- Returns the 1-based index of a rarity name in the rarity ladder, or 0.
local function rarityIndex(rarityName)
	for index, name in ipairs(BootyCatalog.RARITY_ORDER) do
		if name == rarityName then
			return index
		end
	end
	return 0
end

-- Computes the progress for one bounty kind for a player.
-- index -> found count; ownEpic / ownMythic -> owned-rarity check;
-- every other kind -> the player's counter for that kind.
local function progressForKind(player, kind)
	local state = PirateState.getState(player)
	if not state then
		return 0
	end
	if kind == "index" then
		return PirateState.getFoundCount(player)
	end
	if kind == "ownEpic" or kind == "ownMythic" then
		return BountyService.countOwnedRarity(player, kind)
	end
	local counters = state.bounties
	if not counters then
		return 0
	end
	return counters[kind] or 0
end

-- Returns 1 if any brainrot on the player's deck has a rarity index at or
-- above the wanted index (EPIC = 3 for ownEpic, MYTHIC = 5 for ownMythic),
-- else 0. Returns 0 if the player has no state.
function BountyService.countOwnedRarity(player, kind)
	local wantedIndex = 0
	if kind == "ownEpic" then
		wantedIndex = 3
	elseif kind == "ownMythic" then
		wantedIndex = 5
	else
		return 0
	end
	local state = PirateState.getState(player)
	if not state then
		return 0
	end
	for _, slot in ipairs(state.slots) do
		if slot and slot.defId then
			local def = BootyCatalog.getBrainrotDefinition(slot.defId)
			if def and def.rarity then
				if rarityIndex(def.rarity) >= wantedIndex then
					return 1
				end
			end
		end
	end
	return 0
end

-- Returns the bounty list for a player: one entry per bounty with id, text,
-- target, reward, current progress, and whether it is done.
function BountyService.getBountyList(player)
	local state = PirateState.getState(player)
	local doneSet = state and state.bountiesDone or {}
	local list = {}
	for _, bounty in ipairs(BountyService.BOUNTIES) do
		table.insert(list, {
			id = bounty.id,
			text = bounty.text,
			target = bounty.target,
			reward = bounty.reward,
			progress = progressForKind(player, bounty.kind),
			done = doneSet[bounty.id] == true,
		})
	end
	return list
end

-- Checks every bounty that is not yet done. When a bounty's progress reaches
-- its target, it is marked done, the reward is paid into cash at once, a
-- bounty message is broadcast, and the refreshed bounty list is broadcast.
function BountyService.checkBountyCompletion(player)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	if not state.bountiesDone then
		state.bountiesDone = {}
	end
	local changed = false
	for _, bounty in ipairs(BountyService.BOUNTIES) do
		if state.bountiesDone[bounty.id] ~= true then
			local progress = progressForKind(player, bounty.kind)
			if progress >= bounty.target then
				state.bountiesDone[bounty.id] = true
				changed = true
				PirateState.addCash(player, bounty.reward)
				PirateState.broadcast(player, {
					type = "bounty",
					text = "BOUNTY DONE: " .. bounty.text .. " +" .. BootyCatalog.formatMoney(bounty.reward),
					reward = bounty.reward,
				})
			end
		end
	end
	if changed then
		PirateState.broadcast(player, {
			type = "bounties",
			list = BountyService.getBountyList(player),
		})
	end
end

-- Adds amount (default 1) to the player's counter for a kind, then checks
-- whether any bounty completed.
function BountyService.addBountyProgress(player, kind, amount)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	if not state.bounties then
		state.bounties = {}
	end
	local add = amount or 1
	state.bounties[kind] = (state.bounties[kind] or 0) + add
	BountyService.checkBountyCompletion(player)
end

return BountyService
