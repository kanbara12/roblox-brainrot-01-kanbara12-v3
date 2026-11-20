-- StormService.luau
-- The lagoon's threats on a schedule. Three events cycle in a fixed
-- rotation: a Kraken Surge forces everyone carrying a brainrot to high
-- ground, a Golden Tide doubles all income, and a Parrot Raid sends
-- thieving parrots at unlocked decks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))

local StormService = {}

-- Clock time until which the Golden Tide pays double (0 = inactive).
local goldenTideUntil = 0
-- True while a Kraken Surge is running.
local surgeActive = false
-- "" when no event banner is up, else "kraken" / "golden" / "parrot".
local currentEvent = ""

local SURGE_WARNING_SECONDS = 10
local TIDE_DURATION_SECONDS = 60
local RAID_WARNING_SECONDS = 8
local PARROT_HEIGHT = 14

-- 2 while the Golden Tide is active, else 1. Called by PirateState's
-- income calculation.
function StormService.getGoldenTideMultiplier()
	if os.clock() < goldenTideUntil then
		return 2
	end
	return 1
end

-- True when the player's character is on high ground (above the
-- HIGH_GROUND_Y height).
function StormService.isPlayerOnHighGround(player)
	local state = PirateState.getState(player)
	if not state then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	return LagoonLayout.isOnHighGround(character)
end

-- Sets the event banner directly (used by Stagehand to stage a static
-- banner for a screenshot without running the full event).
function StormService.setStagedEventBanner(eventKey, name, text, countdown)
	currentEvent = eventKey
	PirateState.broadcastAll({
		type = "event",
		name = name,
		text = text,
		countdown = countdown,
	})
end

-- Clears the event banner when the given event is still the current one.
local function clearEventBanner(eventKey)
	if currentEvent == eventKey then
		currentEvent = ""
		PirateState.broadcastAll({
			type = "event",
			name = "",
			text = "",
			countdown = 0,
		})
	end
end

-- The surge's victim sweep. Every player carrying a brainrot who is not
-- on high ground loses it; every player carrying who IS on high ground
-- records a survive bounty instead.
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

-- Kraken Surge: a 10-second warning, then a wave sweeps the lagoon and
-- tentacles rise. Carried brainrots below high ground are lost. Does
-- nothing while a surge is already active.
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
		countdown = SURGE_WARNING_SECONDS,
	})
	task.wait(SURGE_WARNING_SECONDS)
	local wave = workspace:WaitForChild("SurgeWave")
	wave.Transparency = 0.25
	-- Sweep from z=-140 toward +z: 40 steps of 3.5 studs, 0.1s each.
	for step = 0, 40 do
		local z = -140 + step * 3.5
		wave.CFrame = CFrame.new(0, 6, z)
		task.wait(0.1)
	end
	for i = 1, 5 do
		local tentacle = workspace:WaitForChild("Tentacle" .. i)
		tentacle.Transparency = 0
		local pos = tentacle.CFrame.Position
		tentacle.CFrame = CFrame.new(pos.X, 4, -100)
	end
	StormService.sweepExposedCarriedBrainrots()
	PirateState.broadcastAll({
		type = "feed",
		text = "The wave took what it could reach!",
		color = "red",
	})
	task.wait(6)
	wave.Transparency = 1
	wave.CFrame = CFrame.new(0, 6, -140)
	for i = 1, 5 do
		local tentacle = workspace:WaitForChild("Tentacle" .. i)
		tentacle.Transparency = 1
		local pos = tentacle.CFrame.Position
		tentacle.CFrame = CFrame.new(pos.X, -8, -100)
	end
	clearEventBanner("kraken")
	surgeActive = false
end

-- Golden Tide: all bases pay x2 income for 60 seconds.
function StormService.triggerGoldenTide()
	goldenTideUntil = os.clock() + TIDE_DURATION_SECONDS
	currentEvent = "golden"
	PirateState.broadcastAll({
		type = "event",
		name = "GOLDEN TIDE!",
		text = "ALL BASES PAY x2 FOR 60s!",
		countdown = TIDE_DURATION_SECONDS,
	})
	task.wait(TIDE_DURATION_SECONDS)
	clearEventBanner("golden")
end

-- Parrot Raid: an 8-second warning, then a parrot appears above every
-- unlocked player's base. After 8 seconds each parrot steals the first
-- occupied deck slot of a player who is still unlocked; a player who
-- locked in the meantime keeps their deck.
function StormService.triggerParrotRaid()
	currentEvent = "parrot"
	PirateState.broadcastAll({
		type = "event",
		name = "PARROT RAID!",
		text = "Thieving parrots are circling! LOCK your deck [L]!",
		countdown = RAID_WARNING_SECONDS,
	})
	local parrots = {}
	local parrotDef = BootyCatalog.getBrainrotDefinition(25)
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and not PirateState.isBaseLocked(player) then
			local baseRecord = LagoonLayout.BASES[state.base]
			if baseRecord and parrotDef then
				local model = RigBuilder.buildBrainrotRig(parrotDef, "NONE")
				local centre = baseRecord.center
				model:PivotTo(CFrame.new(centre.X, centre.Y + PARROT_HEIGHT, centre.Z))
				model.Parent = workspace
				table.insert(parrots, { player = player, model = model })
			end
		end
	end
	task.wait(RAID_WARNING_SECONDS)
	for _, parrot in ipairs(parrots) do
		local player = parrot.player
		if parrot.model then
			parrot.model:Destroy()
		end
		local state = PirateState.getState(player)
		if state then
			if PirateState.isBaseLocked(player) then
				PirateState.broadcast(player, {
					type = "feed",
					text = "Your LOCK kept the parrots out!",
					color = "green",
				})
			else
				-- Steal the first occupied deck slot (lowest slot number).
				for slot = 1, 8 do
					local entry = state.slots[slot]
					if entry then
						local def = BootyCatalog.getBrainrotDefinition(entry.defId)
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
	clearEventBanner("parrot")
end

-- The event scheduler: waits a random 75-120 seconds, then fires the
-- next event in the fixed rotation (Kraken, Golden Tide, Parrot Raid),
-- cycling forever.
function StormService.startEventScheduler()
	local rotation = { "kraken", "golden", "parrot" }
	local nextIndex = 1
	task.spawn(function()
		while true do
			task.wait(math.random(75, 120))
			local eventKey = rotation[nextIndex]
			nextIndex = nextIndex + 1
			if nextIndex > #rotation then
				nextIndex = 1
			end
			if eventKey == "kraken" then
				task.spawn(StormService.triggerKrakenSurge)
			elseif eventKey == "golden" then
				task.spawn(StormService.triggerGoldenTide)
			elseif eventKey == "parrot" then
				task.spawn(StormService.triggerParrotRaid)
			end
		end
	end)
end

return StormService
