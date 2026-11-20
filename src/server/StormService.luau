-- StormService — the lagoon's threats on a schedule.
-- Three scheduled events: a Kraken Surge forces everyone carrying a brainrot
-- to high ground, a Golden Tide doubles all income, and a Parrot Raid sends
-- thieving parrots at unlocked decks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

local PirateState = require(script.Parent:WaitForChild("PirateState"))
local BountyService = require(script.Parent:WaitForChild("BountyService"))

local StormService = {}

local goldenTideUntil = 0
local surgeActive = false
local currentEvent = ""

local GOLDEN_TIDE_SECONDS = 60
local SURGE_WARNING_SECONDS = 10
local SURGE_SWEEP_STEPS = 40
local SURGE_SWEEP_STEP = 3.5
local SURGE_STEP_WAIT = 0.1
local SURGE_HIDE_DELAY = 6
local PARROT_WARNING_SECONDS = 8
local PARROT_HEIGHT = 14
local PARROT_DEF_ID = 25

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

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

-- Sets the event banner without running an event. Used by Stagehand to stage
-- the static Kraken shot (countdown 6) for screenshots.
function StormService.setStagedEventBanner(eventKey, name, text, countdown)
	currentEvent = eventKey
	PirateState.broadcastAll({
		type = "event",
		name = name,
		text = text,
		countdown = countdown,
	})
end

local function clearEventBannerIf(eventKey)
	if currentEvent == eventKey then
		currentEvent = ""
		PirateState.broadcastAll({ type = "event", name = "", text = "", countdown = 0 })
	end
end

--------------------------------------------------------------------------------
-- Kraken Surge
--------------------------------------------------------------------------------

function StormService.sweepExposedCarriedBrainrots()
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and state.carrying then
			if StormService.isPlayerOnHighGround(player) then
				BountyService.addBountyProgress(player, "survive", 1)
			else
				local def = BootyCatalog.getBrainrotDefinition(state.carrying.defId)
				local name = def and def.name or "brainrot"
				PirateState.broadcast(player, {
					type = "feed",
					text = "The Kraken took your " .. name .. "!",
					color = "red",
				})
				if state.carrying.model then
					state.carrying.model:Destroy()
				end
				state.carrying = nil
				PirateState.broadcast(player, { type = "carrying", name = nil })
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
		countdown = SURGE_WARNING_SECONDS,
	})
	task.spawn(function()
		task.wait(SURGE_WARNING_SECONDS)
		local wave = workspace:FindFirstChild("SurgeWave")
		if wave then
			wave.Transparency = 0.25
			for step = 1, SURGE_SWEEP_STEPS do
				wave.CFrame = CFrame.new(0, 6, -140 + step * SURGE_SWEEP_STEP)
				task.wait(SURGE_STEP_WAIT)
			end
		end
		for index = 1, 5 do
			local tentacle = workspace:FindFirstChild("Tentacle" .. index)
			if tentacle then
				tentacle.Transparency = 0
				local cf = tentacle.CFrame
				tentacle.CFrame = CFrame.new(cf.X, 4, -100)
			end
		end
		StormService.sweepExposedCarriedBrainrots()
		PirateState.broadcastAll({
			type = "event",
			name = "KRAKEN SURGE!",
			text = "The wave took what it could reach!",
			countdown = 0,
		})
		task.wait(SURGE_HIDE_DELAY)
		if wave then
			wave.Transparency = 1
			wave.CFrame = CFrame.new(0, 6, -140)
		end
		for index = 1, 5 do
			local tentacle = workspace:FindFirstChild("Tentacle" .. index)
			if tentacle then
				tentacle.Transparency = 1
				local cf = tentacle.CFrame
				tentacle.CFrame = CFrame.new(cf.X, -8, cf.Z)
			end
		end
		clearEventBannerIf("kraken")
		surgeActive = false
	end)
end

--------------------------------------------------------------------------------
-- Golden Tide
--------------------------------------------------------------------------------

function StormService.triggerGoldenTide()
	goldenTideUntil = os.clock() + GOLDEN_TIDE_SECONDS
	currentEvent = "golden"
	PirateState.broadcastAll({
		type = "event",
		name = "GOLDEN TIDE!",
		text = "ALL BASES PAY x2 FOR 60s!",
		countdown = GOLDEN_TIDE_SECONDS,
	})
	task.delay(GOLDEN_TIDE_SECONDS, function()
		clearEventBannerIf("golden")
	end)
end

--------------------------------------------------------------------------------
-- Parrot Raid
--------------------------------------------------------------------------------

function StormService.triggerParrotRaid()
	currentEvent = "parrot"
	PirateState.broadcastAll({
		type = "event",
		name = "PARROT RAID!",
		text = "Thieving parrots are circling! LOCK your deck [L]!",
		countdown = PARROT_WARNING_SECONDS,
	})
	local parrots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PirateState.getState(player)
		if state and not PirateState.isBaseLocked(player) then
			local baseRecord = LagoonLayout.BASES[state.base]
			local centre = baseRecord and (baseRecord.center or baseRecord.centre)
			if centre then
				local def = BootyCatalog.getBrainrotDefinition(PARROT_DEF_ID)
				local model = RigBuilder.buildBrainrotRig(def, "NONE")
				model.Parent = workspace
				model:PivotTo(CFrame.new(centre + Vector3.new(0, PARROT_HEIGHT, 0)))
				table.insert(parrots, { player = player, model = model })
			end
		end
	end
	task.delay(PARROT_WARNING_SECONDS, function()
		for _, parrot in ipairs(parrots) do
			local player = parrot.player
			if parrot.model then
				parrot.model:Destroy()
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
					if state.slots[slot] then
						firstSlot = slot
						break
					end
				end
				if firstSlot then
					local old = PirateState.clearBaseSlot(player, firstSlot)
					if old then
						local def = BootyCatalog.getBrainrotDefinition(old.defId)
						local name = def and def.name or "brainrot"
						PirateState.broadcastAll({
							type = "feed",
							text = "A parrot stole " .. name .. " from " .. player.Name .. "!",
							color = "red",
						})
					end
				end
			end
		end
		clearEventBannerIf("parrot")
	end)
end

--------------------------------------------------------------------------------
-- Scheduler
--------------------------------------------------------------------------------

function StormService.startEventScheduler()
	task.spawn(function()
		local rotation = { "kraken", "golden", "parrot" }
		local nextIndex = 1
		while true do
			task.wait(math.random(75, 120))
			local eventKey = rotation[nextIndex]
			nextIndex = nextIndex % #rotation + 1
			if eventKey == "kraken" then
				StormService.triggerKrakenSurge()
			elseif eventKey == "golden" then
				StormService.triggerGoldenTide()
			else
				StormService.triggerParrotRaid()
			end
		end
	end)
end

return StormService
