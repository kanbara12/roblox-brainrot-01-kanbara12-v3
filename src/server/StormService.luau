-- StormService: the lagoon's threats on a schedule. A Kraken Surge forces
-- everyone carrying a brainrot to high ground, a Golden Tide doubles all
-- income, and a Parrot Raid sends thieving parrots at unlocked decks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)

local StormService = {}
StormService.goldenTideUntil = 0
StormService.surgeActive = false
StormService.currentEvent = ""

function StormService.getGoldenTideMultiplier()
	if os.clock() < StormService.goldenTideUntil then
		return 2
	end
	return 1
end

function StormService.isPlayerOnHighGround(player)
	local character = player.Character
	return LagoonLayout.isOnHighGround(character)
end

function StormService.startEventScheduler()
	task.spawn(function()
		local events = { "kraken", "golden", "parrot" }
		local index = 0
		while true do
			task.wait(math.random(75, 120))
			index = (index % #events) + 1
			local name = events[index]
			if name == "kraken" then
				StormService.triggerKrakenSurge()
			elseif name == "golden" then
				StormService.triggerGoldenTide()
			else
				StormService.triggerParrotRaid()
			end
		end
	end)
end

function StormService.triggerKrakenSurge()
	if StormService.surgeActive then
		return
	end
	StormService.surgeActive = true
	StormService.currentEvent = "kraken"
	PirateState.broadcastAll({ type = "event", name = "KRAKEN SURGE!", text = "GET TO HIGH GROUND! The wave is coming!", countdown = 10 })
	task.wait(10)
	local wave = workspace:FindFirstChild("SurgeWave")
	if wave then
		wave.Transparency = 0.25
		for step = 1, 40 do
			wave.Position = Vector3.new(0, 6, -140 + step * 3.5)
			task.wait(0.1)
		end
	end
	for i = 1, 5 do
		local tentacle = workspace:FindFirstChild("Tentacle" .. i)
		if tentacle then
			tentacle.Transparency = 0
			tentacle.Position = Vector3.new(tentacle.Position.X, 4, -100)
		end
	end
	StormService.sweepExposedCarriedBrainrots()
	PirateState.broadcastAll({ type = "event", name = "KRAKEN SURGE!", text = "The wave took what it could reach!", countdown = 0 })
	task.wait(6)
	if wave then
		wave.Transparency = 1
		wave.Position = Vector3.new(0, 6, -140)
	end
	for i = 1, 5 do
		local tentacle = workspace:FindFirstChild("Tentacle" .. i)
		if tentacle then
			tentacle.Transparency = 1
			tentacle.Position = Vector3.new(tentacle.Position.X, -8, -100)
		end
	end
	if StormService.currentEvent == "kraken" then
		PirateState.broadcastAll({ type = "event", name = "", text = "", countdown = 0 })
		StormService.currentEvent = ""
	end
	StormService.surgeActive = false
end

function StormService.sweepExposedCarriedBrainrots()
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and state.carrying and not StormService.isPlayerOnHighGround(player) then
			local def = BootyCatalog.getBrainrotDefinition(state.carrying.defId)
			local name = def and def.name or "brainrot"
			PirateState.broadcast(player, { type = "feed", text = "The Kraken took your " .. name .. "!", color = "red" })
			if state.carrying.model then
				state.carrying.model:Destroy()
			end
			state.carrying = nil
			PirateState.broadcast(player, { type = "carrying", name = nil })
		elseif state and state.carrying then
			BountyService.addBountyProgress(player, "survive", 1)
		end
	end
end

function StormService.triggerGoldenTide()
	StormService.goldenTideUntil = os.clock() + 60
	StormService.currentEvent = "golden"
	PirateState.broadcastAll({ type = "event", name = "GOLDEN TIDE!", text = "ALL BASES PAY x2 FOR 60s!", countdown = 60 })
	task.wait(60)
	if StormService.currentEvent == "golden" then
		PirateState.broadcastAll({ type = "event", name = "", text = "", countdown = 0 })
		StormService.currentEvent = ""
	end
end

function StormService.triggerParrotRaid()
	StormService.currentEvent = "parrot"
	PirateState.broadcastAll({ type = "event", name = "PARROT RAID!", text = "Thieving parrots are circling! LOCK your deck [L]!", countdown = 8 })
	local parrots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and not PirateState.isBaseLocked(player) then
			local def = BootyCatalog.BRAINROTS[25] -- Parrot Pistachio
			local model = RigBuilder.buildBrainrotRig(def, "NONE")
			model:PivotTo(CFrame.new(LagoonLayout.BASES[state.base].center + Vector3.new(0, 14, 0)))
			model.Parent = workspace
			table.insert(parrots, { model = model, player = player })
		end
	end
	task.wait(8)
	for _, parrot in ipairs(parrots) do
		local state = PirateState.getState(parrot.player)
		if parrot.model then
			parrot.model:Destroy()
		end
		if state and not PirateState.isBaseLocked(parrot.player) then
			for slot = 1, 8 do
				if state.slots[slot] then
					local stolen = PirateState.clearBaseSlot(parrot.player, slot)
					local def = BootyCatalog.getBrainrotDefinition(stolen.defId)
					PirateState.broadcastAll({ type = "feed", text = "A parrot stole " .. def.name .. " from " .. parrot.player.Name .. "!", color = "red" })
					break
				end
			end
		elseif state then
			PirateState.broadcast(parrot.player, { type = "feed", text = "Your LOCK kept the parrots out!", color = "green" })
		end
	end
	if StormService.currentEvent == "parrot" then
		PirateState.broadcastAll({ type = "event", name = "", text = "", countdown = 0 })
		StormService.currentEvent = ""
	end
end

return StormService
