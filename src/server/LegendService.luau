-- LegendService: rebirth. Cash and deck reset for a permanent x2 income
-- multiplier, a golden aura, and (from rebirth 2) the LEGEND tier opens.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)

local LegendService = {}

function LegendService.getRebirthCost(player)
	local state = PirateState.getState(player)
	if not state then return 50000 end
	return 50000 * (4 ^ state.rebirths)
end

function LegendService.getRequiredRarity(player)
	local state = PirateState.getState(player)
	if not state then return "LEGENDARY" end
	if state.rebirths == 0 then
		return "LEGENDARY"
	else
		return "MYTHIC"
	end
end

function LegendService.canPlayerRebirth(player)
	local state = PirateState.getState(player)
	if not state then return false end
	if state.cash < LegendService.getRebirthCost(player) then
		return false
	end
	local required = LegendService.getRequiredRarity(player)
	local requiredIndex = table.find(BootyCatalog.RARITY_ORDER, required) or 4
	for _, slot in pairs(state.slots) do
		if slot then
			local def = BootyCatalog.getBrainrotDefinition(slot.defId)
			if def then
				local defIndex = table.find(BootyCatalog.RARITY_ORDER, def.rarity) or 1
				if defIndex >= requiredIndex then
					return true
				end
			end
		end
	end
	return false
end

function LegendService.performPlayerRebirth(player)
	if not LegendService.canPlayerRebirth(player) then
		return false
	end
	PirateState.incrementRebirth(player)
	LegendService.applyRebirthAura(player)
	BountyService.addBountyProgress(player, "rebirth", 1)
	PirateState.broadcastAll({ type = "feed", text = player.Name .. " REBIRTHED! Income x" .. tostring(PirateState.getRebirthMultiplier(player)) .. " forever!", color = "gold" })
	return true
end

function LegendService.applyRebirthAura(player)
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local sparkles = Instance.new("Sparkles")
	sparkles.Name = "RebirthAura"
	sparkles.SparkleColor = Color3.fromRGB(255, 215, 0)
	sparkles.Parent = root
	local light = Instance.new("PointLight")
	light.Name = "RebirthLight"
	light.Color = Color3.fromRGB(255, 215, 0)
	light.Range = 8
	light.Brightness = 1
	light.Parent = root
end

return LegendService
