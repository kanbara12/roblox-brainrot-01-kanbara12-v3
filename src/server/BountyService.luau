-- BountyService — twelve bounties with doubloon rewards.
-- Progress is counted by the services that own each action, and completion
-- pays out at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))

local PirateState = require(script.Parent:WaitForChild("PirateState"))

local BountyService = {}

-- The twelve bounties. Keep this table exactly as specified.
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

-- The rarity index a kind requires: EPIC is index 3, MYTHIC is index 5.
local OWNED_RARITY_INDEX = { ownEpic = 3, ownMythic = 5 }

-- Returns 1 if any brainrot on the player's deck has a rarity index at or
-- above the wanted index, else 0. Returns 0 when there is no state.
function BountyService.countOwnedRarity(player, kind)
	local state = PirateState.getState(player)
	if not state then
		return 0
	end
	local wanted = OWNED_RARITY_INDEX[kind]
	if not wanted then
		return 0
	end
	for _, entry in ipairs(state.slots) do
		if entry then
			local def = BootyCatalog.getBrainrotDefinition(entry.defId)
			if def then
				local index = table.find(BootyCatalog.RARITY_ORDER, def.rarity)
				if index and index >= wanted then
					return 1
				end
			end
		end
	end
	return 0
end

-- Computes one bounty's current progress for a player.
local function getProgress(player, bounty)
	local state = PirateState.getState(player)
	if not state then
		return 0
	end
	if bounty.kind == "index" then
		return PirateState.getFoundCount(player)
	elseif bounty.kind == "ownEpic" or bounty.kind == "ownMythic" then
		return BountyService.countOwnedRarity(player, bounty.kind)
	else
		return state.bounties[bounty.kind] or 0
	end
end

function BountyService.getBountyList(player)
	local state = PirateState.getState(player)
	local list = {}
	for _, bounty in ipairs(BountyService.BOUNTIES) do
		table.insert(list, {
			id = bounty.id,
			text = bounty.text,
			target = bounty.target,
			reward = bounty.reward,
			progress = getProgress(player, bounty),
			done = state and state.bountiesDone[bounty.id] or false,
		})
	end
	return list
end

function BountyService.addBountyProgress(player, kind, amount)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	state.bounties[kind] = (state.bounties[kind] or 0) + (amount or 1)
	BountyService.checkBountyCompletion(player)
end

function BountyService.checkBountyCompletion(player)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local anyDone = false
	for _, bounty in ipairs(BountyService.BOUNTIES) do
		if not state.bountiesDone[bounty.id] then
			local progress = getProgress(player, bounty)
			if progress >= bounty.target then
				state.bountiesDone[bounty.id] = true
				PirateState.addCash(player, bounty.reward)
				PirateState.broadcast(player, {
					type = "bounty",
					text = "BOUNTY DONE: "
						.. bounty.text
						.. " +"
						.. BootyCatalog.formatMoney(bounty.reward),
					reward = bounty.reward,
				})
				anyDone = true
			end
		end
	end
	if anyDone then
		PirateState.broadcast(player, {
			type = "bounties",
			list = BountyService.getBountyList(player),
		})
	end
end

return BountyService
