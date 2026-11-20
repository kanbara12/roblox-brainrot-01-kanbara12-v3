local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stagehand = {}

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local TreasureChuteService = require(script.Parent.TreasureChuteService)
local PlunderService = require(script.Parent.PlunderService)
local StormService = require(script.Parent.StormService)
local BountyService = require(script.Parent.BountyService)
local LegendService = require(script.Parent.LegendService)

local TOP_DECK = {
	{ slot = 1, defId = 23, mutation = "GOLDEN" },
	{ slot = 2, defId = 25, mutation = "GOLDEN" },
	{ slot = 3, defId = 30, mutation = "NONE" },
	{ slot = 4, defId = 28, mutation = "CURSED" },
	{ slot = 5, defId = 26, mutation = "PEARL" },
	{ slot = 6, defId = 22, mutation = "NONE" },
}

function Stagehand.getFirstPlayer()
	local all = Players:GetPlayers()
	if #all == 0 then
		return nil
	end
	return all[1]
end

function Stagehand.fillShowcasePedestal(player, slot, defId, mutation)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	local def = BootyCatalog.getBrainrotDefinition(defId)
	if not def then
		return
	end
	PirateState.clearBaseSlot(player, slot)
	local placed = PirateState.assignBrainrotToSlot(player, slot, defId, mutation)
	if not placed then
		return
	end
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	model.Parent = workspace
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
	model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
end

function Stagehand.fillTopDeck(player)
	for _, entry in ipairs(TOP_DECK) do
		Stagehand.fillShowcasePedestal(player, entry.slot, entry.defId, entry.mutation)
	end
end

function Stagehand.stageScreenshot(shot)
	local player = Stagehand.getFirstPlayer()
	if not player then
		warn("[Stagehand] No player in server to stage screenshot: " .. tostring(shot))
		return false
	end
	local state = PirateState.getState(player)
	if not state then
		warn("[Stagehand] Player has no state: " .. player.Name)
		return false
	end
	state.cash = 2500000
	state.rebirths = 2
	LegendService.applyRebirthAura(player)
	PirateState.broadcast(player, {
		type = "cash",
		cash = state.cash,
		income = PirateState.getIncomePerSecond(player),
	})
	if shot == "hero" then
		Stagehand.fillTopDeck(player)
		TreasureChuteService.spawnConveyorBrainrot()
		TreasureChuteService.spawnConveyorBrainrot()
		StormService.triggerGoldenTide()
	elseif shot == "chute" then
		TreasureChuteService.spawnConveyorBrainrot()
		TreasureChuteService.spawnConveyorBrainrot()
		TreasureChuteService.spawnConveyorBrainrot()
		Stagehand.fillShowcasePedestal(player, 1, 30, "NONE")
		Stagehand.fillShowcasePedestal(player, 2, 11, "PEARL")
	elseif shot == "index" then
		for defId = 1, 34 do
			PirateState.markFound(player, defId)
		end
		Stagehand.fillTopDeck(player)
	elseif shot == "kraken" then
		local character = player.Character
		if character then
			character:PivotTo(CFrame.new(LagoonLayout.LIGHTHOUSE_TOP))
		end
		local def = BootyCatalog.getBrainrotDefinition(34)
		if def then
			local model = RigBuilder.buildBrainrotRig(def, "GHOST")
			RigBuilder.attachOverheadBillboard(model, def, "GHOST", "STOLEN! RUN HOME!")
			model.Parent = workspace
			if character then
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp then
					model:PivotTo(CFrame.new(hrp.Position + Vector3.new(0, 4, 0)))
				end
			end
			local income = BootyCatalog.calculateBrainrotIncome(def, "GHOST", PirateState.getRebirthMultiplier(player))
			state.carrying = { defId = 34, mutation = "GHOST", model = model }
			PirateState.broadcast(player, {
				type = "carrying",
				name = def.name,
				income = income,
				stolen = true,
			})
		end
		local wave = workspace:FindFirstChild("SurgeWave")
		if wave then
			wave.Transparency = 0.25
			wave.CFrame = CFrame.new(0, 6, -40)
		end
		for i = 1, 5 do
			local tentacle = workspace:FindFirstChild("Tentacle" .. i)
			if tentacle then
				tentacle.Transparency = 0
				local pos = tentacle.Position
				tentacle.CFrame = CFrame.new(pos.X, 4, -100)
			end
		end
		StormService.setStagedEventBanner(
			"kraken",
			"KRAKEN SURGE!",
			"GET TO HIGH GROUND! The wave is coming!",
			6
		)
	end
	PirateState.broadcast(player, {
		type = "cash",
		cash = state.cash,
		income = PirateState.getIncomePerSecond(player),
	})
	PirateState.broadcast(player, { type = "slots", slots = state.slots })
	PirateState.broadcast(player, {
		type = "index",
		found = state.found,
		foundCount = PirateState.getFoundCount(player),
	})
	PirateState.broadcast(player, {
		type = "bounties",
		list = BountyService.getBountyList(player),
	})
	return true
end

return Stagehand
