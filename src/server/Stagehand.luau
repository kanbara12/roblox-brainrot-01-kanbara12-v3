-- Stagehand: stages each TOUR screenshot for the first player in Studio.
-- Called by the kit's TOUR steps as stageScreenshot("hero" | "chute" |
-- "index" | "kraken"). It seeds cash, fills showcase pedestals, spawns
-- chute riders, marks index tiles, and sets the event state for the shot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local TreasureChuteService = require(script.Parent.TreasureChuteService)
local PlunderService = require(script.Parent.PlunderService)
local StormService = require(script.Parent.StormService)
local BountyService = require(script.Parent.BountyService)
local LegendService = require(script.Parent.LegendService)

local Stagehand = {}

-- Top-tier showcase deck: 6 pedestals whose combined income at rebirth x4
-- is about $1.31M/s ($2.63M/s during Golden Tide x2).
local TOP_DECK = {
	{ slot = 1, defId = 23, mutation = "GOLDEN" },
	{ slot = 2, defId = 25, mutation = "GOLDEN" },
	{ slot = 3, defId = 30, mutation = "NONE" },
	{ slot = 4, defId = 28, mutation = "CURSED" },
	{ slot = 5, defId = 26, mutation = "PEARL" },
	{ slot = 6, defId = 22, mutation = "NONE" },
}

function Stagehand.fillTopDeck(player)
	for _, entry in ipairs(TOP_DECK) do
		Stagehand.fillShowcasePedestal(player, entry.slot, entry.defId, entry.mutation)
	end
end

function Stagehand.getFirstPlayer()
	local players = Players:GetPlayers()
	return players[1]
end

function Stagehand.fillShowcasePedestal(player, slot, defId, mutation)
	local state = PirateState.getState(player)
	if not state then return end
	PirateState.clearBaseSlot(player, slot)
	PirateState.assignBrainrotToSlot(player, slot, defId, mutation)
	local def = BootyCatalog.getBrainrotDefinition(defId)
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	model:PivotTo(CFrame.new(LagoonLayout.getPedestalPosition(state.base, slot)))
	model.Parent = workspace
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
end

function Stagehand.stageScreenshot(shot)
	local player = Stagehand.getFirstPlayer()
	if not player then
		warn("Stagehand: no player in server to stage " .. tostring(shot))
		return false
	end
	local state = PirateState.getState(player)
	if not state then
		warn("Stagehand: player has no state yet for " .. tostring(shot))
		return false
	end
	-- Staged wealth: $2.5M cash, rebirth 2 (income x4) with the gold aura,
	-- so the HUD shows big numbers instead of a fresh $100 start.
	state.cash = 2500000
	state.rebirths = 2
	LegendService.applyRebirthAura(player)
	PirateState.broadcast(player, { type = "cash", cash = state.cash, income = PirateState.getIncomePerSecond(player) })
	if shot == "hero" then
		Stagehand.fillTopDeck(player)
		TreasureChuteService.spawnConveyorBrainrot()
		TreasureChuteService.spawnConveyorBrainrot()
		StormService.goldenTideUntil = os.clock() + 60
		StormService.currentEvent = "golden"
		PirateState.broadcastAll({ type = "event", name = "GOLDEN TIDE!", text = "ALL BASES PAY x2 FOR 60s!", countdown = 60 })
	elseif shot == "chute" then
		TreasureChuteService.spawnConveyorBrainrot()
		TreasureChuteService.spawnConveyorBrainrot()
		TreasureChuteService.spawnConveyorBrainrot()
		Stagehand.fillShowcasePedestal(player, 1, 30, "NONE")
		Stagehand.fillShowcasePedestal(player, 2, 11, "PEARL")
	elseif shot == "index" then
		for i = 1, 34 do
			PirateState.markFound(player, i)
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
		if root then
			model:PivotTo(CFrame.new(root.Position + Vector3.new(0, 4, 0)))
		end
		state.carrying = { defId = 34, mutation = "GHOST", model = model }
		PirateState.broadcast(player, { type = "carrying", name = def.name, income = 0, stolen = true })
		local wave = workspace:FindFirstChild("SurgeWave")
		if wave then
			wave.Transparency = 0.25
			wave.Position = Vector3.new(0, 6, -40)
		end
		for i = 1, 5 do
			local tentacle = workspace:FindFirstChild("Tentacle" .. i)
			if tentacle then
				tentacle.Transparency = 0
				tentacle.Position = Vector3.new(tentacle.Position.X, 4, -100)
			end
		end
		StormService.currentEvent = "kraken"
		PirateState.broadcastAll({ type = "event", name = "KRAKEN SURGE!", text = "GET TO HIGH GROUND! The wave is coming!", countdown = 6 })
	end
	-- Push the full staged state to the HUD: pedestals, Log tiles and
	-- bounties, not just cash, so the shot shows the staged game even if
	-- the join snapshot was missed.
	PirateState.broadcast(player, { type = "cash", cash = state.cash, income = PirateState.getIncomePerSecond(player) })
	PirateState.broadcast(player, { type = "slots", slots = state.slots })
	PirateState.broadcast(player, { type = "index", found = state.found, foundCount = PirateState.getFoundCount(player) })
	PirateState.broadcast(player, { type = "bounties", list = BountyService.getBountyList(player) })
	return true
end

return Stagehand
