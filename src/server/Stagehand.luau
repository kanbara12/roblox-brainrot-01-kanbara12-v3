-- Stagehand.luau
-- TOUR screenshot staging. Stages each TOUR screenshot for the first
-- player in the server. The kit's TOUR steps call stageScreenshot with a
-- shot name ("hero", "chute", "index", or "kraken"). It seeds cash, fills
-- showcase pedestals, spawns chute riders, marks Log tiles, and sets the
-- event state for the shot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PirateState = require(script.Parent.PirateState)
local TreasureChuteService = require(script.Parent.TreasureChuteService)
local PlunderService = require(script.Parent.PlunderService)
local StormService = require(script.Parent.StormService)
local BountyService = require(script.Parent.BountyService)
local LegendService = require(script.Parent.LegendService)
local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))

local Stagehand = {}

-- The six showcase pedestals for the top deck, chosen so their combined
-- income at rebirth x4 is about $1.31M/s ($2.63M/s during Golden Tide x2).
local TOP_DECK = {
	{ slot = 1, defId = 23, mutation = "GOLDEN" },
	{ slot = 2, defId = 25, mutation = "GOLDEN" },
	{ slot = 3, defId = 30, mutation = "NONE" },
	{ slot = 4, defId = 28, mutation = "CURSED" },
	{ slot = 5, defId = 26, mutation = "PEARL" },
	{ slot = 6, defId = 22, mutation = "NONE" },
}

local STAGED_CASH = 2500000
local STAGED_REBIRTHS = 2
local CARRY_HEIGHT = 4

-- Fills one showcase pedestal: clears the slot, assigns the brainrot to
-- it (which marks it found), builds the rig, computes income at the
-- player's rebirth multiplier, attaches an income billboard, places the
-- model on the pedestal, records it as the slot's pedestal model, and
-- attaches a steal clicker.
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
	if not PirateState.assignBrainrotToSlot(player, slot, defId, mutation) then
		return
	end
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	local pedestalPos = LagoonLayout.getPedestalPosition(state.base, slot)
	model:PivotTo(CFrame.new(pedestalPos))
	model.Parent = workspace
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
end

-- Fills the player's top 6 showcase pedestals.
function Stagehand.fillTopDeck(player)
	for _, entry in ipairs(TOP_DECK) do
		Stagehand.fillShowcasePedestal(player, entry.slot, entry.defId, entry.mutation)
	end
end

-- The first player in the server, or nil when the server is empty.
function Stagehand.getFirstPlayer()
	local list = Players:GetPlayers()
	if #list == 0 then
		return nil
	end
	return list[1]
end

-- Stages one shot. Returns false (with a warning) when there is no player
-- or the player has no state. Otherwise stages the shared wealth (cash
-- $2,500,000, rebirths 2 for income x4, golden rebirth aura), then the
-- per-shot staging, then pushes the full staged state to the HUD and
-- returns true.
function Stagehand.stageScreenshot(shot)
	local player = Stagehand.getFirstPlayer()
	if not player then
		warn("[Stagehand] No player in the server to stage for.")
		return false
	end
	local state = PirateState.getState(player)
	if not state then
		warn("[Stagehand] Player has no state to stage for.")
		return false
	end
	-- Shared wealth for every shot.
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
		task.spawn(StormService.triggerGoldenTide)
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
			local def = BootyCatalog.getBrainrotDefinition(34)
			if def then
				local model = RigBuilder.buildBrainrotRig(def, "GHOST")
				RigBuilder.attachOverheadBillboard(model, def, "GHOST", "STOLEN! RUN HOME!")
				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					model:PivotTo(CFrame.new(rootPart.Position + Vector3.new(0, CARRY_HEIGHT, 0)))
				end
				model.Parent = workspace
				local income = BootyCatalog.calculateBrainrotIncome(def, "GHOST", PirateState.getRebirthMultiplier(player))
				state.carrying = { defId = 34, mutation = "GHOST", model = model }
				PirateState.broadcast(player, {
					type = "carrying",
					name = def.name,
					income = income,
					stolen = true,
				})
			end
		end
		local wave = workspace:WaitForChild("SurgeWave")
		wave.Transparency = 0.25
		wave.CFrame = CFrame.new(0, 6, -40)
		for i = 1, 5 do
			local tentacle = workspace:WaitForChild("Tentacle" .. i)
			tentacle.Transparency = 0
			local pos = tentacle.CFrame.Position
			tentacle.CFrame = CFrame.new(pos.X, 4, -100)
		end
		StormService.setStagedEventBanner("kraken", "KRAKEN SURGE!", "GET TO HIGH GROUND! The wave is coming!", 6)
	end
	-- Push the full staged state to the HUD so the shot shows the staged
	-- game even when the join snapshot was missed.
	PirateState.broadcast(player, {
		type = "cash",
		cash = state.cash,
		income = PirateState.getIncomePerSecond(player),
	})
	PirateState.broadcast(player, {
		type = "slots",
		slots = state.slots,
	})
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
