-- Stagehand.luau
-- TOUR screenshot staging. Stages each TOUR screenshot for the first player
-- in the server. The kit's TOUR steps call stageScreenshot with a shot name
-- ("hero", "chute", "index", or "kraken"). It seeds cash, fills showcase
-- pedestals, spawns chute riders, marks Log tiles, and sets the event state
-- for the shot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PirateState = require(script.Parent.PirateState)
local TreasureChuteService = require(script.Parent.TreasureChuteService)
local PlunderService = require(script.Parent.PlunderService)
local StormService = require(script.Parent.StormService)
local BountyService = require(script.Parent.BountyService)
local LegendService = require(script.Parent.LegendService)
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local Stagehand = {}

-- The six showcase entries for the top deck (slot, defId, mutation).
-- Combined income at rebirth x4 is about $1.31M/s ($2.63M/s during
-- Golden Tide x2).
local TOP_DECK = {
	{ slot = 1, defId = 23, mutation = "GOLDEN" },
	{ slot = 2, defId = 25, mutation = "GOLDEN" },
	{ slot = 3, defId = 30, mutation = "NONE" },
	{ slot = 4, defId = 28, mutation = "CURSED" },
	{ slot = 5, defId = 26, mutation = "PEARL" },
	{ slot = 6, defId = 22, mutation = "NONE" },
}

-- Returns the first player in the server, or nil.
function Stagehand.getFirstPlayer()
	local list = Players:GetPlayers()
	if #list == 0 then
		return nil
	end
	return list[1]
end

-- Fills one showcase pedestal: clears the slot, assigns the brainrot to it
-- (which marks it found), builds the rig, computes income at the player's
-- rebirth multiplier, attaches a billboard reading "+<income>/s", places the
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
	local assigned = PirateState.assignBrainrotToSlot(player, slot, defId, mutation)
	if not assigned then
		return
	end
	local income = BootyCatalog.calculateBrainrotIncome(def, mutation, PirateState.getRebirthMultiplier(player))
	local model = RigBuilder.buildBrainrotRig(def, mutation)
	RigBuilder.attachOverheadBillboard(model, def, mutation, "+" .. BootyCatalog.formatMoney(income) .. "/s")
	local pedestalPos = LagoonLayout.getPedestalPosition(state.base, slot)
	model:PivotTo(CFrame.new(pedestalPos))
	model.Parent = Workspace
	PirateState.setPedestalModel(player, slot, model)
	PlunderService.attachStealClicker(model, player, slot)
end

-- Fills the player's top 6 showcase pedestals.
function Stagehand.fillTopDeck(player)
	for _, entry in ipairs(TOP_DECK) do
		Stagehand.fillShowcasePedestal(player, entry.slot, entry.defId, entry.mutation)
	end
end

-- Stages one shot. Returns true on success, false when there is no player
-- or the player has no state. First stages the shared wealth (cash
-- $2,500,000, rebirths 2, golden aura, cash broadcast), then stages the
-- shot-specific content, then pushes the full staged state to the HUD.
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
		task.spawn(function()
			StormService.triggerGoldenTide()
		end)
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
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				model:PivotTo(CFrame.new(root.Position + Vector3.new(0, 4, 0)))
			else
				model:PivotTo(CFrame.new(LagoonLayout.LIGHTHOUSE_TOP + Vector3.new(0, 4, 0)))
			end
			model.Parent = Workspace
			local income = BootyCatalog.calculateBrainrotIncome(def, "GHOST", PirateState.getRebirthMultiplier(player))
			state.carrying = { defId = 34, mutation = "GHOST", model = model }
			PirateState.broadcast(player, {
				type = "carrying",
				name = def.name,
				income = income,
				stolen = true,
			})
		end
		local wave = Workspace:FindFirstChild("SurgeWave")
		if wave then
			wave.Transparency = 0.25
			wave.Position = Vector3.new(0, 6, -40)
		end
		for index = 1, 5 do
			local tentacle = Workspace:FindFirstChild("Tentacle" .. index)
			if tentacle then
				tentacle.Transparency = 0
				local pos = tentacle.Position
				tentacle.Position = Vector3.new(pos.X, 4, -100)
			end
		end
		StormService.setStagedEventBanner("kraken", "KRAKEN SURGE!", "GET TO HIGH GROUND! The wave is coming!", 6)
	end
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
