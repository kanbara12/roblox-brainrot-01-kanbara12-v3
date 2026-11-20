local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local PirateState = require(script.Parent.PirateState)

local BountyService = {}

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

local function rarityIndex(rarityName)
	for i, name in ipairs(BootyCatalog.RARITY_ORDER) do
		if name == rarityName then
			return i
		end
	end
	return 1
end

local function computeProgress(player, bounty)
	local state = PirateState.getState(player)
	if bounty.kind == "index" then
		return PirateState.getFoundCount(player)
	elseif bounty.kind == "ownEpic" or bounty.kind == "ownMythic" then
		return BountyService.countOwnedRarity(player, bounty.kind)
	end
	if not state then
		return 0
	end
	return state.bounties[bounty.kind] or 0
end

function BountyService.countOwnedRarity(player, kind)
	local state = PirateState.getState(player)
	if not state then
		return 0
	end
	local wanted = 3
	if kind == "ownMythic" then
		wanted = 5
	end
	for slot = 1, 8 do
		local entry = state.slots[slot]
		if entry then
			local def = BootyCatalog.getBrainrotDefinition(entry.defId)
			if def and rarityIndex(def.rarity) >= wanted then
				return 1
			end
		end
	end
	return 0
end

function BountyService.getBountyList(player)
	local state = PirateState.getState(player)
	local list = {}
	for _, bounty in ipairs(BountyService.BOUNTIES) do
		local done = false
		if state and state.bountiesDone[bounty.id] then
			done = true
		end
		table.insert(list, {
			id = bounty.id,
			text = bounty.text,
			target = bounty.target,
			reward = bounty.reward,
			progress = computeProgress(player, bounty),
			done = done,
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
	for _, bounty in ipairs(BountyService.BOUNTIES) do
		if not state.bountiesDone[bounty.id] then
			local progress = computeProgress(player, bounty)
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
