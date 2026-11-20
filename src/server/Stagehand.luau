-- Stagehand — TOUR screenshot staging.
-- Stages each TOUR screenshot for the first player in the server. The kit's
-- TOUR steps call it with a shot name ("hero", "chute", "index", or
-- "kraken"). It seeds cash, fills showcase pedestals, spawns chute riders,
-- marks Log tiles, and sets the event state for the shot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local PirateState = require(script.Parent:WaitForChild("PirateState"))
local TreasureChuteService = require(script.Parent:WaitForChild("TreasureChuteService"))
local PlunderService = require(script.Parent:WaitForChild("PlunderService"))
local StormService = require(script.Parent:WaitForChild("StormService"))
local BountyService = require(script.Parent:WaitForChild("BountyService"))
local LegendService = require(script.Parent:WaitForChild("LegendService"))

local Stagehand = {}

local STAGED_CASH = 2500000
local STAGED_REBIRTHS = 2
local CARRY_HEIGHT = 4

-- Six fixed showcase entries. Their combined income at rebirth x4 is about
-- $1.31M/s ($2.63M/s during a Golden Tide x2).
local TOP_DECK = {
	{ slot = 1, defId = 23, mutation = "GOLDEN" },
	{ slot = 2, defId = 25, mutation = "GOLDEN" },
	{ slot = 3, defId = 30, mutation = "NONE" },
	{ slot = 4, defId = 28, mutation = "CURSED" },
	{ slot = 5, defId = 26, mutation = "PEARL" },
	{ slot = 6, defId = 22, mutation = "NONE" },
}

function Stagehand.getFirstPlayer()
	local players = Players:GetPlayers()
	return players[1]
end

function Stagehand.fillShowcasePedestal(player, slot, defId, mutation)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	PirateState.clearBaseSlot(player, slot)
	if not PirateState.assignBrainrotToSlot(player, slot, defId, mutation) then
		return
	end
	local def = BootyCatalog.getBrainrotDefinition(defId)
	if not def then
		return
	end
	local income =
		BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(
		model,
		def,
		mutation,
		"+" .. BootyCatalog.formatMoney(income) .. "/s"
	)
	model.Parent = workspace
	model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
end

function Stagehand.fillTopDeck(player)
	for _, entry in ipairs(TOP_DECK) do
		Stagehand.fillShowcasePedestal(player, entry.slot, entry.defId, entry.mutation)
	end
end

function Stagehand.stageScreenshot(shot)
	local player = Stagehand.getFirstPlayer()
	if not player then
		warn("[Stagehand] No player in server to stage " .. shot)
		return false
	end
	local state = PirateState.getState(player)
	if not state then
		warn("[Stagehand] No state for first player to stage " .. shot)
		return false
	end
	-- Shared wealth staging for every shot.
	state.cash = STAGED_CASH
	state.rebirths = STAGED_REBIRTHS
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
		local model = RigBuilder.buildBrainrotRig(def, "GHOST")
		RigBuilder.attachOverheadBillboard(model, def, "GHOST", "STOLEN! RUN HOME!")
		model.Parent = workspace
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local headPos = root and root.Position or LagoonLayout.LIGHTHOUSE_TOP
		model:PivotTo(CFrame.new(headPos + Vector3.new(0, CARRY_HEIGHT, 0)))
		local income =
			BootyCatalog.calculateBrainrotIncome(def, "GHOST", PirateState.getRebirthMultiplier(player))
		state.carrying = { defId = 34, mutation = "GHOST", model = model }
		PirateState.broadcast(player, {
			type = "carrying",
			name = def.name,
			income = income,
			stolen = true,
		})
		local wave = workspace:FindFirstChild("SurgeWave")
		if wave then
			wave.Transparency = 0.25
			wave.CFrame = CFrame.new(0, 6, -40)
		end
		for index = 1, 5 do
			local tentacle = workspace:FindFirstChild("Tentacle" .. index)
			if tentacle then
				tentacle.Transparency = 0
				local cf = tentacle.CFrame
				tentacle.CFrame = CFrame.new(cf.X, 4, -100)
			end
		end
		StormService.setStagedEventBanner(
			"kraken",
			"KRAKEN SURGE!",
			"GET TO HIGH GROUND! The wave is coming!",
			6
		)
	end
	-- Push the full staged state to the HUD, so the shot shows the staged
	-- game even if the join snapshot was missed.
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
