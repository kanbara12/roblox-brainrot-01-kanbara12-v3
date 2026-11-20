-- BountyService.luau
-- Twelve bounties with doubloon rewards. Progress is counted by the
-- services that own each action, and completion pays out at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PirateState = require(script.Parent.PirateState)
local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))

local BountyService = {}

-- The twelve bounties: id, kind, target, text, reward.
-- Kinds: buy, steal, lock, survive, rebirth, upgrades are counters on the
-- player state. index is the Captain's Log found-count. ownEpic / ownMythic
-- are computed from the rarities on the player's deck.
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

-- One entry per bounty: id, text, target, reward, current progress, and
-- whether it is done. Progress is computed per kind: index reads the
-- player's found count, ownEpic / ownMythic read the owned-rarity check,
-- every other kind reads the player's counter for that kind.
function BountyService.getBountyList(player)
	local state = PirateState.getState(player)
	local list = {}
	for _, bounty in ipairs(BountyService.BOUNTIES) do
		local progress = 0
		if state then
			if bounty.kind == "index" then
				progress = PirateState.getFoundCount(player)
			elseif bounty.kind == "ownEpic" or bounty.kind == "ownMythic" then
				progress = BountyService.countOwnedRarity(player, bounty.kind)
			else
				progress = state.bounties[bounty.kind] or 0
			end
		end
		local done = false
		if state and state.bountiesDone[bounty.id] then
			done = true
		end
		table.insert(list, {
			id = bounty.id,
			text = bounty.text,
			target = bounty.target,
			reward = bounty.reward,
			progress = progress,
			done = done,
		})
	end
	return list
end

-- Returns 1 when any brainrot on the player's deck has a rarity index at
-- or above the wanted index (EPIC = 3 for ownEpic, MYTHIC = 5 for
-- ownMythic), else 0. Returns 0 when the player has no state.
function BountyService.countOwnedRarity(player, kind)
	local state = PirateState.getState(player)
	if not state then
		return 0
	end
	local wantedIndex = 3
	if kind == "ownMythic" then
		wantedIndex = 5
	end
	for slot = 1, 8 do
		local entry = state.slots[slot]
		if entry then
			local def = BootyCatalog.getBrainrotDefinition(entry.defId)
			if def then
				local rarityIndex = table.find(BootyCatalog.RARITY_ORDER, def.rarity)
				if rarityIndex and rarityIndex >= wantedIndex then
					return 1
				end
			end
		end
	end
	return 0
end

-- Adds amount (default 1) to the player's counter for a kind, then checks
-- whether any bounty just completed.
function BountyService.addBountyProgress(player, kind, amount)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	amount = amount or 1
	state.bounties[kind] = (state.bounties[kind] or 0) + amount
	BountyService.checkBountyCompletion(player)
end

-- For every bounty not yet done, computes progress the same way as
-- getBountyList. When progress reaches the target, marks it done, pays the
-- reward into the player's cash at once, broadcasts a bounty message, and
-- broadcasts a refreshed bounty list.
function BountyService.checkBountyCompletion(player)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	for _, bounty in ipairs(BountyService.BOUNTIES) do
		if not state.bountiesDone[bounty.id] then
			local progress = 0
			if bounty.kind == "index" then
				progress = PirateState.getFoundCount(player)
			elseif bounty.kind == "ownEpic" or bounty.kind == "ownMythic" then
				progress = BountyService.countOwnedRarity(player, bounty.kind)
			else
				progress = state.bounties[bounty.kind] or 0
			end
			if progress >= bounty.target then
				state.bountiesDone[bounty.id] = true
				PirateState.addCash(player, bounty.reward)
				PirateState.broadcast(player, {
					type = "bounty",
					text = "BOUNTY DONE: " .. bounty.text .. " +" .. BootyCatalog.formatMoney(bounty.reward),
					reward = bounty.reward,
				})
				PirateState.broadcast(player, {
					type = "bounties",
					list = BountyService.getBountyList(player),
				})
			end
		end
	end
end

return BountyService
