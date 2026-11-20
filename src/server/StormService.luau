local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StormService = {}

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)

local goldenTideUntil = 0
local surgeActive = false
local currentEvent = ""

function StormService.getGoldenTideMultiplier()
	if os.clock() < goldenTideUntil then
		return 2
	end
	return 1
end

function StormService.isPlayerOnHighGround(player)
	local character = player.Character
	if not character then
		return false
	end
	return LagoonLayout.isOnHighGround(character)
end

function StormService.setStagedEventBanner(eventKey, bannerName, bannerText, countdown)
	currentEvent = eventKey
	PirateState.broadcastAll({
		type = "event",
		name = bannerName,
		text = bannerText,
		countdown = countdown,
	})
end

function StormService.startEventScheduler()
	task.spawn(function()
		local events = { "kraken", "golden", "parrot" }
		local index = 1
		while true do
			task.wait(math.random(75, 120))
			local eventName = events[index]
			index = index % #events + 1
			if eventName == "kraken" then
				StormService.triggerKrakenSurge()
			elseif eventName == "golden" then
				StormService.triggerGoldenTide()
			elseif eventName == "parrot" then
				StormService.triggerParrotRaid()
			end
		end
	end)
end

function StormService.sweepExposedCarriedBrainrots()
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and state.carrying then
			local def = BootyCatalog.getBrainrotDefinition(state.carrying.defId)
			local name = def and def.name or "brainrot"
			if StormService.isPlayerOnHighGround(player) then
				BountyService.addBountyProgress(player, "survive", 1)
			else
				PirateState.broadcast(player, {
					type = "feed",
					text = "The Kraken took your " .. name .. "!",
					color = "red",
				})
				if state.carrying.model then
					state.carrying.model:Destroy()
				end
				state.carrying = nil
				PirateState.broadcast(player, {
					type = "carrying",
					name = nil,
					income = 0,
					stolen = false,
				})
			end
		end
	end
end

function StormService.triggerKrakenSurge()
	if surgeActive then
		return
	end
	surgeActive = true
	currentEvent = "kraken"
	PirateState.broadcastAll({
		type = "event",
		name = "KRAKEN SURGE!",
		text = "GET TO HIGH GROUND! The wave is coming!",
		countdown = 10,
	})
	task.delay(10, function()
		local wave = workspace:FindFirstChild("SurgeWave")
		if wave then
			wave.Transparency = 0.25
			task.spawn(function()
				for step = 1, 40 do
					wave.CFrame = CFrame.new(0, 6, -140 + step * 3.5)
					task.wait(0.1)
				end
			end)
		end
		for i = 1, 5 do
			local tentacle = workspace:FindFirstChild("Tentacle" .. i)
			if tentacle then
				tentacle.Transparency = 0
				local pos = tentacle.Position
				tentacle.CFrame = CFrame.new(pos.X, 4, -100)
			end
		end
		StormService.sweepExposedCarriedBrainrots()
		PirateState.broadcastAll({
			type = "event",
			name = "KRAKEN SURGE!",
			text = "The wave took what it could reach!",
			countdown = 0,
		})
		task.delay(6, function()
			if wave then
				wave.Transparency = 1
				wave.CFrame = CFrame.new(0, 6, -140)
			end
			for i = 1, 5 do
				local tentacle = workspace:FindFirstChild("Tentacle" .. i)
				if tentacle then
					tentacle.Transparency = 1
					local pos = tentacle.Position
					tentacle.CFrame = CFrame.new(pos.X, -8, pos.Z)
				end
			end
			if currentEvent == "kraken" then
				currentEvent = ""
				PirateState.broadcastAll({
					type = "event",
					name = "",
					text = "",
					countdown = 0,
				})
			end
			surgeActive = false
		end)
	end)
end

function StormService.triggerGoldenTide()
	goldenTideUntil = os.clock() + 60
	currentEvent = "golden"
	PirateState.broadcastAll({
		type = "event",
		name = "GOLDEN TIDE!",
		text = "ALL BASES PAY x2 FOR 60s!",
		countdown = 60,
	})
	task.delay(60, function()
		if currentEvent == "golden" then
			currentEvent = ""
			PirateState.broadcastAll({
				type = "event",
				name = "",
				text = "",
				countdown = 0,
			})
		end
	end)
end

function StormService.triggerParrotRaid()
	currentEvent = "parrot"
	PirateState.broadcastAll({
		type = "event",
		name = "PARROT RAID!",
		text = "Thieving parrots are circling! LOCK your deck [L]!",
		countdown = 8,
	})
	local parrots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and not PirateState.isBaseLocked(player) then
			local def = BootyCatalog.getBrainrotDefinition(25)
			if def then
				local model = RigBuilder.buildBrainrotRig(def, "NONE")
				local baseRecord = LagoonLayout.BASES[state.base]
				local baseCenter = baseRecord.center or baseRecord.centre
				model:PivotTo(CFrame.new(baseCenter + Vector3.new(0, 14, 0)))
				model.Parent = workspace
				table.insert(parrots, { player = player, model = model })
			end
		end
	end
	task.delay(8, function()
		for _, entry in ipairs(parrots) do
			if entry.model then
				entry.model:Destroy()
			end
			local player = entry.player
			local state = PirateState.getState(player)
			if state then
				if PirateState.isBaseLocked(player) then
					PirateState.broadcast(player, {
						type = "feed",
						text = "Your LOCK kept the parrots out!",
						color = "green",
					})
				else
					for slot = 1, 8 do
						local slotEntry = state.slots[slot]
						if slotEntry then
							local def = BootyCatalog.getBrainrotDefinition(slotEntry.defId)
							local name = def and def.name or "brainrot"
							PirateState.clearBaseSlot(player, slot)
							PirateState.broadcastAll({
								type = "feed",
								text = "A parrot stole " .. name .. " from " .. player.Name .. "!",
								color = "red",
							})
							break
						end
					end
				end
			end
		end
		if currentEvent == "parrot" then
			currentEvent = ""
			PirateState.broadcastAll({
				type = "event",
				name = "",
				text = "",
				countdown = 0,
			})
		end
	end)
end

return StormService
