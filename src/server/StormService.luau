-- StormService.luau
-- The lagoon's threats on a schedule. Three events cycle: a Kraken Surge
-- forces everyone carrying a brainrot to high ground, a Golden Tide doubles
-- all income, and a Parrot Raid sends thieving parrots at unlocked decks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PirateState = require(script.Parent.PirateState)
local BountyService = require(script.Parent.BountyService)
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local StormService = {}

-- Module state.
local goldenTideUntil = 0 -- clock time, 0 = inactive
local surgeActive = false
local currentEvent = "" -- "" or "kraken" / "golden" / "parrot"

-- The wave sweep geometry.
local WAVE_START_Z = -140
local WAVE_STEPS = 40
local WAVE_STEP_SIZE = 3.5
local WAVE_STEP_WAIT = 0.1
local WAVE_HEIGHT = 6
-- The parrot raid geometry.
local PARROT_HEIGHT = 14
-- The scheduler timing.
local SCHEDULER_MIN_WAIT = 75
local SCHEDULER_MAX_WAIT = 120

-- Returns 2 while the clock is before the Golden Tide expiry, else 1.
-- Called by PirateState's income calculation.
function StormService.getGoldenTideMultiplier()
	if os.clock() < goldenTideUntil then
		return 2
	end
	return 1
end

-- Returns true when the player's character is on high ground.
function StormService.isPlayerOnHighGround(player)
	local character = player.Character
	if not character then
		return false
	end
	return LagoonLayout.isOnHighGround(character)
end

-- Broadcasts an event banner to all players. An empty name hides the banner.
local function broadcastEventBanner(name, text, countdown)
	PirateState.broadcastAll({
		type = "event",
		name = name,
		text = text,
		countdown = countdown,
	})
end

-- Clears the event banner if the current event is still the given one.
local function clearEventBannerIfCurrent(eventKey)
	if currentEvent == eventKey then
		currentEvent = ""
		broadcastEventBanner("", "", 0)
	end
end

-- Sets the event banner to a staged (static) state for screenshot staging.
-- Stagehand uses this for the "kraken" shot (countdown 6). It does not start
-- the event itself; the wave and tentacles are shown by the caller.
function StormService.setStagedEventBanner(eventKey, name, text, countdown)
	currentEvent = eventKey
	broadcastEventBanner(name, text, countdown)
end

-- The surge's victim sweep. For every player carrying a brainrot: if the
-- player is not on high ground, the carried brainrot is lost (model
-- destroyed, carrying record cleared, carrying message sent with a nil
-- name); if the player is on high ground, a survive bounty progresses.
function StormService.sweepExposedCarriedBrainrots()
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and state.carrying then
			local carrying = state.carrying
			if StormService.isPlayerOnHighGround(player) then
				BountyService.addBountyProgress(player, "survive", 1)
			else
				local def = BootyCatalog.getBrainrotDefinition(carrying.defId)
				local name = def and def.name or "brainrot"
				PirateState.broadcast(player, {
					type = "feed",
					text = "The Kraken took your " .. name .. "!",
					color = "red",
				})
				if carrying.model then
					carrying.model:Destroy()
				end
				state.carrying = nil
				PirateState.broadcast(player, {
					type = "carrying",
					name = nil,
				})
			end
		end
	end
end

-- The Kraken Surge. A 10-second warning is broadcast, then the wave sweeps
-- across the lagoon and the tentacles rise. Carried brainrots that are not
-- on high ground are lost. Six seconds after the sweep the wave and
-- tentacles are hidden again.
function StormService.triggerKrakenSurge()
	if surgeActive then
		return
	end
	surgeActive = true
	currentEvent = "kraken"
	broadcastEventBanner("KRAKEN SURGE!", "GET TO HIGH GROUND! The wave is coming!", 10)
	task.wait(10)
	local wave = Workspace:FindFirstChild("SurgeWave")
	if wave then
		wave.Transparency = 0.25
		for step = 0, WAVE_STEPS - 1 do
			wave.Position = Vector3.new(0, WAVE_HEIGHT, WAVE_START_Z + step * WAVE_STEP_SIZE)
			task.wait(WAVE_STEP_WAIT)
		end
	end
	for index = 1, 5 do
		local tentacle = Workspace:FindFirstChild("Tentacle" .. index)
		if tentacle then
			tentacle.Transparency = 0
			local pos = tentacle.Position
			tentacle.Position = Vector3.new(pos.X, 4, -100)
		end
	end
	StormService.sweepExposedCarriedBrainrots()
	PirateState.broadcastAll({
		type = "feed",
		text = "The wave took what it could reach!",
		color = "blue",
	})
	task.wait(6)
	if wave then
		wave.Transparency = 1
		wave.Position = Vector3.new(0, WAVE_HEIGHT, WAVE_START_Z)
	end
	for index = 1, 5 do
		local tentacle = Workspace:FindFirstChild("Tentacle" .. index)
		if tentacle then
			tentacle.Transparency = 1
			local pos = tentacle.Position
			tentacle.Position = Vector3.new(pos.X, -8, pos.Z)
		end
	end
	clearEventBannerIfCurrent("kraken")
	surgeActive = false
end

-- The Golden Tide. All bases pay x2 income for 60 seconds.
function StormService.triggerGoldenTide()
	goldenTideUntil = os.clock() + 60
	currentEvent = "golden"
	broadcastEventBanner("GOLDEN TIDE!", "ALL BASES PAY x2 FOR 60s!", 60)
	task.wait(60)
	clearEventBannerIfCurrent("golden")
end

-- The Parrot Raid. A parrot is spawned 14 studs above the centre of every
-- unlocked player's base. After 8 seconds, each parrot steals the player's
-- first occupied deck slot unless the player locked in the meantime.
function StormService.triggerParrotRaid()
	currentEvent = "parrot"
	broadcastEventBanner("PARROT RAID!", "Thieving parrots are circling! LOCK your deck [L]!", 8)
	local parrotDef = BootyCatalog.getBrainrotDefinition(25)
	local parrots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and not PirateState.isBaseLocked(player) then
			local baseRecord = LagoonLayout.BASES[state.base]
			if baseRecord and parrotDef then
				local centre = baseRecord.center or baseRecord.centre
				if centre then
					local parrot = RigBuilder.buildBrainrotRig(parrotDef, "NONE")
					parrot:PivotTo(CFrame.new(centre + Vector3.new(0, PARROT_HEIGHT, 0)))
					parrot.Parent = Workspace
					table.insert(parrots, { player = player, model = parrot })
				end
			end
		end
	end
	task.wait(8)
	for _, entry in ipairs(parrots) do
		local player = entry.player
		local model = entry.model
		if model then
			model:Destroy()
		end
		local state = PirateState.getState(player)
		if not state then
			continue
		end
		if PirateState.isBaseLocked(player) then
			PirateState.broadcast(player, {
				type = "feed",
				text = "Your LOCK kept the parrots out!",
				color = "green",
			})
		else
			local firstSlot = nil
			for slot = 1, 8 do
				if state.slots[slot] ~= nil then
					firstSlot = slot
					break
				end
			end
			if firstSlot then
				local stolen = state.slots[firstSlot]
				local def = stolen and BootyCatalog.getBrainrotDefinition(stolen.defId)
				local name = def and def.name or "brainrot"
				PirateState.clearBaseSlot(player, firstSlot)
				PirateState.broadcastAll({
					type = "feed",
					text = "A parrot stole " .. name .. " from " .. player.Name .. "!",
					color = "red",
				})
			end
		end
	end
	clearEventBannerIfCurrent("parrot")
end

-- Starts the event scheduler: waits a random 75-120 seconds, then fires the
-- next event in a fixed rotation (kraken, golden, parrot, repeat), forever.
function StormService.startEventScheduler()
	task.spawn(function()
		local rotation = { "kraken", "golden", "parrot" }
		local nextIndex = 1
		while true do
			local waitTime = math.random(SCHEDULER_MIN_WAIT, SCHEDULER_MAX_WAIT)
			task.wait(waitTime)
			local eventKey = rotation[nextIndex]
			nextIndex = nextIndex % #rotation + 1
			if eventKey == "kraken" then
				StormService.triggerKrakenSurge()
			elseif eventKey == "golden" then
				StormService.triggerGoldenTide()
			elseif eventKey == "parrot" then
				StormService.triggerParrotRaid()
			end
		end
	end)
end

return StormService
