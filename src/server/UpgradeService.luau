-- UpgradeService: spend doubloons on permanent ship upgrades. Every upgrade
-- is a level with a price, and the HUD shows level and next price.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)

local UpgradeService = {}

UpgradeService.UPGRADES = {
	speed = { name = "SWIFT SAILS", desc = "+2 walk speed", base = 3000, max = 6 },
	lock = { name = "IRON NET", desc = "+10s base lock", base = 4700, max = 5 },
	slots = { name = "EXTRA PEDESTAL", desc = "+1 base slot", base = 900, max = 2 },
	income = { name = "GOLDEN COMPASS", desc = "+10% income", base = 5000, max = 5 },
}

function UpgradeService.getUpgradeCost(key, level)
	local def = UpgradeService.UPGRADES[key]
	if not def then return 0 end
	return def.base * (2 ^ level)
end

function UpgradeService.buyUpgrade(player, key)
	local def = UpgradeService.UPGRADES[key]
	if not def then return false end
	local level = PirateState.getUpgradeLevel(player, key)
	if level >= def.max then
		PirateState.broadcast(player, { type = "feed", text = def.name .. " is MAXED!", color = "red" })
		return false
	end
	local cost = UpgradeService.getUpgradeCost(key, level)
	if not PirateState.spendCash(player, cost) then
		PirateState.broadcast(player, { type = "feed", text = "Not enough doubloons for " .. def.name .. "!", color = "red" })
		return false
	end
	PirateState.setUpgradeLevel(player, key, level + 1)
	UpgradeService.applyUpgradeToCharacter(player, key)
	local state = PirateState.getState(player)
	if state then
		PirateState.broadcast(player, { type = "upgrades", upgrades = state.upgrades })
	end
	PirateState.broadcast(player, { type = "feed", text = "Bought " .. def.name .. " LV " .. tostring(level + 1) .. "!", color = "green" })
	BountyService.addBountyProgress(player, "upgrades", 1)
	return true
end

function UpgradeService.applyUpgradeToCharacter(player, key)
	if key ~= "speed" then return end
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.WalkSpeed = 16 + 2 * PirateState.getUpgradeLevel(player, "speed")
end

function UpgradeService.applyAllUpgradesToCharacter(player)
	UpgradeService.applyUpgradeToCharacter(player, "speed")
end

return UpgradeService
